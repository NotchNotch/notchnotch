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

extension ConnectionHTTPRequest {

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

/// Which URLs an extension may open. The app also requires a recent user
/// action and an installed app that handles the scheme.
public enum OpenURLPolicy {
    /// Schemes that would open local files, run code or hide what is opened.
    static let blockedSchemes: Set<String> = ["file", "data", "javascript", "vbscript", "ftp", "applescript", "notchnotch"]

    public static func validate(_ string: String) throws -> URL {
        guard string.utf8.count <= 4096, let components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(),
              scheme.range(of: "^[a-z][a-z0-9+.-]{0,31}$", options: .regularExpression) != nil,
              !blockedSchemes.contains(scheme), !scheme.hasPrefix("x-apple"),
              components.user == nil, components.password == nil, let url = components.url else {
            throw ProtocolError.invalid("open accepts web addresses and app links, such as https://example.com or mailto:")
        }
        if scheme == "http" || scheme == "https" {
            guard let host = components.host, !host.isEmpty else { throw ProtocolError.invalid("open needs a host for web addresses") }
        }
        return url
    }
}

/// A short window after a person's click or keystroke during which an extension
/// may open one URL, like a browser's user activation.
public struct UserActivation: Sendable {
    public static let window: TimeInterval = 5
    private var deadline: Date?

    public init() {}

    public mutating func grant(now: Date = .now) { deadline = now.addingTimeInterval(Self.window) }

    /// `true` once per activation, and only within the window.
    public mutating func consume(now: Date = .now) -> Bool {
        guard let deadline, now <= deadline else { self.deadline = nil; return false }
        self.deadline = nil
        return true
    }
}

/// A key, and for `secretSet` its value, in an extension's Keychain secrets.
extension SecretRequest {
    public static let maximumValueBytes = 8192

    public func validate(requiresValue: Bool) throws {
        guard key.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil else {
            throw ProtocolError.invalid("Secret keys use letters, digits, '.', '_' and '-', up to 64 characters.")
        }
        guard !requiresValue || value != nil, (value?.utf8.count ?? 0) <= Self.maximumValueBytes else {
            throw ProtocolError.invalid("Secret values are text of up to 8 KiB.")
        }
    }
}

/// An HTTPS request to a host the manifest lists in `network`.
extension NetworkRequest {

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

extension ConnectionOperation {
    /// Operations the app answers itself, without a declared connection.
    public var usesConnection: Bool { ![.fetch, .secretGet, .secretSet, .secretDelete, .openURL].contains(self) }
}

extension ConnectionCommand {
    public typealias Operation = ConnectionOperation

    public func validate(expectedExtensionID: String) throws {
        guard protocolVersion == 1, type == "connectionCommand", extensionID == expectedExtensionID,
              !requestID.isEmpty, requestID.count <= 128, !operation.usesConnection || !connectionID.isEmpty, connectionID.count <= 64,
              (sessionID?.count ?? 0) <= 128 else {
            throw ProtocolError.invalid("Invalid connection command")
        }
        if let message, try JSONEncoder().encode(message).count > maximumConnectionPayloadBytes {
            throw ProtocolError.invalid("Connection message exceeds 64 KiB")
        }
    }
}
