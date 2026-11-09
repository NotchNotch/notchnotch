import Foundation

public let maximumConnectionPayloadBytes = 65_536
/// Request and response bodies of `fetch`; a response must still fit in one host message.
public let maximumFetchBodyBytes = 196_608

public indirect enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([JSONValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .string(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        }
    }
}

public struct ConnectionDefinition: Codable, Equatable, Sendable {
    public enum Transport: String, Codable, Sendable { case http, websocket, stdio }
    public var transport: Transport
    public var endpoint: String?
    public var executable: String?
    public var arguments: [String]?

    public init(transport: Transport, endpoint: String? = nil, executable: String? = nil, arguments: [String]? = nil) {
        self.transport = transport; self.endpoint = endpoint; self.executable = executable; self.arguments = arguments
    }

    public func validate(permissions: [String]) throws {
        switch transport {
        case .http, .websocket:
            guard permissions.contains("local-network"), executable == nil, arguments == nil,
                  let endpoint, let url = URL(string: endpoint),
                  endpoint.range(of: transport == .http
                    ? #"^https?://(127\.0\.0\.1|\[::1\]):[0-9]+/?$"#
                    : #"^wss?://(127\.0\.0\.1|\[::1\]):[0-9]+(/[^?#]*)?$"#, options: .regularExpression) != nil,
                  Self.isLoopback(url), let port = url.port, (1...65535).contains(port),
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  transport == .websocket || url.path.isEmpty || url.path == "/",
                  transport == .http ? ["http", "https"].contains(url.scheme ?? "") : ["ws", "wss"].contains(url.scheme ?? "") else {
                throw ProtocolError.invalid("Local connections require an explicit loopback origin and local-network permission")
            }
        case .stdio:
            guard permissions.contains("process"), endpoint == nil, let executable,
                  !executable.isEmpty, executable.utf8.count <= 1024, !executable.contains("\0"),
                  executable.hasPrefix("/") || !executable.contains("/") || Self.isBundledPath(executable),
                  (arguments?.count ?? 0) <= 32,
                  (arguments ?? []).allSatisfy({ $0.utf8.count <= 4096 && !$0.contains("\0") }) else {
                throw ProtocolError.invalid("Stdio connections require a fixed executable, bounded arguments, and process permission")
            }
        }
    }

    public static func isLoopback(_ url: URL) -> Bool {
        // Literal addresses avoid DNS rebinding and proxying localhost to a remote host.
        ["127.0.0.1", "[::1]", "::1"].contains(url.host ?? "")
    }
    private static func isBundledPath(_ path: String) -> Bool {
        path.hasPrefix("./") && !path.split(separator: "/").contains("..")
    }
}

public struct ConnectionHTTPRequest: Codable, Sendable {
    public var path: String
    public var method: String
    public var headers: [String: String]?
    public var body: String?
    public var timeoutMs: Int?

    public init(path: String, method: String = "GET", headers: [String: String]? = nil, body: String? = nil, timeoutMs: Int? = nil) {
        self.path = path; self.method = method; self.headers = headers; self.body = body; self.timeoutMs = timeoutMs
    }

    public func url(for definition: ConnectionDefinition) throws -> URL {
        guard definition.transport == .http, let endpoint = definition.endpoint, let origin = URL(string: endpoint),
              path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("\\"),
              let result = URL(string: path, relativeTo: origin)?.absoluteURL,
              result.scheme == origin.scheme, result.host == origin.host, result.port == origin.port,
              result.user == nil, result.password == nil, result.fragment == nil,
              ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].contains(method),
              (body?.utf8.count ?? 0) <= maximumConnectionPayloadBytes,
              (1...30_000).contains(timeoutMs ?? 15_000),
              Self.allowsHeaders(headers) else { throw ProtocolError.invalid("Invalid local HTTP request") }
        return result
    }

    static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    /// Up to 32 headers with token names and single-line values, none that the
    /// transport itself controls.
    static func allowsHeaders(_ headers: [String: String]?) -> Bool {
        (headers?.count ?? 0) <= 32 && (headers ?? [:]).allSatisfy { name, value in
            !name.isEmpty && name.utf8.count <= 128 && value.utf8.count <= 4096 &&
                !["host", "connection", "content-length", "transfer-encoding", "proxy-authorization"].contains(name.lowercased()) &&
                name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || "!#$%&'*+-.^_`|~".utf8.contains($0) }) &&
                !value.contains("\r") && !value.contains("\n")
        }
    }
}

/// An HTTPS request to a host the manifest lists in `network`.
public struct NetworkRequest: Codable, Sendable {
    public var url: String
    public var method: String
    public var headers: [String: String]?
    public var body: String?
    public var timeoutMs: Int?

    public init(url: String, method: String = "GET", headers: [String: String]? = nil, body: String? = nil, timeoutMs: Int? = nil) {
        self.url = url; self.method = method; self.headers = headers; self.body = body; self.timeoutMs = timeoutMs
    }

    /// The request's URL when it is well formed and its host is declared.
    public func validatedURL(hosts: [String]) throws -> URL {
        guard url.utf8.count <= 8192, let components = URLComponents(string: url), components.scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty, components.user == nil, components.password == nil,
              let result = components.url else {
            throw ProtocolError.invalid("fetch accepts https:// URLs only")
        }
        guard NetworkHosts.allows(hosts, host: host) else {
            throw ProtocolError.invalid("\(host) is not in this extension's network hosts. Add it to \"network\" in notchnotch.json.")
        }
        guard ConnectionHTTPRequest.methods.contains(method), (body?.utf8.count ?? 0) <= maximumFetchBodyBytes,
              (1...30_000).contains(timeoutMs ?? 15_000), ConnectionHTTPRequest.allowsHeaders(headers) else {
            throw ProtocolError.invalid("Invalid fetch request")
        }
        return result
    }
}

/// Hosts an extension may reach with `fetch`: exact DNS names or `*.` wildcards
/// for subdomains, the same syntax as `imageHosts`.
public enum NetworkHosts {
    public static let maximumCount = 16

    public static func allows(_ patterns: [String], host: String) -> Bool {
        let host = host.lowercased()
        return patterns.contains { ImageHost.matches($0, host: host) }
    }
}

public struct ConnectionCommand: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case request, open, send, close, fetch }
    public var protocolVersion = 1
    public var type = "connectionCommand"
    public var extensionID: String
    public var requestID: String
    public var connectionID: String
    public var operation: Operation
    public var sessionID: String?
    public var request: ConnectionHTTPRequest?
    /// For `fetch`, which uses no declared connection; `connectionID` is empty.
    public var fetch: NetworkRequest?
    public var message: JSONValue?
    /// `false` fails instead of asking the user when access was not granted before.
    public var interactive: Bool?

    private enum CodingKeys: String, CodingKey { case protocolVersion, type, extensionID, requestID, connectionID, operation, sessionID, request, fetch, message, interactive }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
        type = try values.decode(String.self, forKey: .type)
        extensionID = try values.decode(String.self, forKey: .extensionID)
        requestID = try values.decode(String.self, forKey: .requestID)
        connectionID = try values.decode(String.self, forKey: .connectionID)
        operation = try values.decode(Operation.self, forKey: .operation)
        sessionID = try values.decodeIfPresent(String.self, forKey: .sessionID)
        request = try values.decodeIfPresent(ConnectionHTTPRequest.self, forKey: .request)
        fetch = try values.decodeIfPresent(NetworkRequest.self, forKey: .fetch)
        message = values.contains(.message) ? try values.decode(JSONValue.self, forKey: .message) : nil
        interactive = try values.decodeIfPresent(Bool.self, forKey: .interactive)
    }

    public init(extensionID: String, requestID: String, connectionID: String, operation: Operation,
                sessionID: String? = nil, request: ConnectionHTTPRequest? = nil, fetch: NetworkRequest? = nil,
                message: JSONValue? = nil, interactive: Bool? = nil) {
        self.extensionID = extensionID; self.requestID = requestID; self.connectionID = connectionID
        self.operation = operation; self.sessionID = sessionID; self.request = request; self.fetch = fetch; self.message = message
        self.interactive = interactive
    }

    public func validate(expectedExtensionID: String) throws {
        guard protocolVersion == 1, type == "connectionCommand", extensionID == expectedExtensionID,
              !requestID.isEmpty, requestID.count <= 128, operation == .fetch || !connectionID.isEmpty, connectionID.count <= 64,
              (sessionID?.count ?? 0) <= 128 else {
            throw ProtocolError.invalid("Invalid connection command")
        }
        if let message, try JSONEncoder().encode(message).count > maximumConnectionPayloadBytes {
            throw ProtocolError.invalid("Connection message exceeds 64 KiB")
        }
    }
}

public struct ConnectionResponse: Codable, Sendable {
    public var protocolVersion = 1
    public var type = "connectionResponse"
    public let requestID: String
    public let result: JSONValue?
    public let error: String?
    public init(requestID: String, result: JSONValue? = nil, error: String? = nil) {
        self.requestID = requestID; self.result = result; self.error = error
    }
}

public struct ConnectionEvent: Codable, Sendable {
    public var protocolVersion = 1
    public var type = "connectionEvent"
    public let connectionID: String
    public let sessionID: String
    public let event: String
    public let message: JSONValue?
    public let error: String?
    public init(connectionID: String, sessionID: String, event: String, message: JSONValue? = nil, error: String? = nil) {
        self.connectionID = connectionID; self.sessionID = sessionID; self.event = event; self.message = message; self.error = error
    }
}
