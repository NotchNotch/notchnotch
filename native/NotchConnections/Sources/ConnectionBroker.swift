import CryptoKit
import Foundation
import NotchProtocol

private final class LocalSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Follows a redirect only to another declared HTTPS host, and never carries
/// credentials to a different host. Anything else is returned to the extension.
private final class NetworkSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let hosts: [String]
    init(hosts: [String]) { self.hosts = hosts }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", let host = url.host(), NetworkHosts.allows(hosts, host: host) else {
            completionHandler(nil); return
        }
        var redirected = request
        if host.lowercased() != task.originalRequest?.url?.host()?.lowercased() {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
            redirected.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        completionHandler(redirected)
    }
}

/// What the host needs to decide whether a connection may start.
public struct ConnectionAuthorizationRequest: Sendable, Equatable {
    public var connectionID: String
    /// Human-readable destination: an endpoint, or an executable path and arguments.
    public var target: String
    /// Changes whenever the destination changes, including a rebuilt helper binary.
    public var fingerprint: String
    /// `false` must not show UI; answer from stored grants only.
    public var interactive: Bool
    public init(connectionID: String, target: String, fingerprint: String, interactive: Bool) {
        self.connectionID = connectionID; self.target = target; self.fingerprint = fingerprint; self.interactive = interactive
    }
}

/// Transports are generic. Application-specific protocols stay in extension code.
@MainActor
public final class ConnectionBroker {
    @MainActor private final class Stream {
        let sessionID: String
        var process: StdioConnection?
        var websocket: URLSessionWebSocketTask?
        var reader: Task<Void, Never>?
        var intervalStart = Date.now
        var messageCount = 0
        init(sessionID: String) { self.sessionID = sessionID }
        func stop() { reader?.cancel(); websocket?.cancel(with: .goingAway, reason: nil); process?.stop() }
    }

    private let manifest: ExtensionManifest
    private let directory: URL
    private let authorize: @MainActor (ConnectionAuthorizationRequest) async -> Bool
    private let emit: (String) -> Void
    private let session: URLSession
    private let websocketSession: URLSession
    /// Created on the first `fetch`; most extensions never use the network.
    private var networkSession: URLSession?
    private let networkProtocolClasses: [AnyClass]?
    /// Only grants are cached; a denial is asked again on the next explicit attempt.
    private var granted: Set<String> = []
    private var pendingDecisions: [String: Task<Bool, Never>] = [:]
    private var streams: [String: Stream] = [:]
    private var closedSessions: [String: String] = [:]
    private var operations: [String: Task<Void, Never>] = [:]
    private var stopped = false

    public convenience init(manifest: ExtensionManifest, directory: URL,
                            authorize: @escaping @MainActor (ConnectionAuthorizationRequest) async -> Bool, emit: @escaping (String) -> Void) {
        self.init(manifest: manifest, directory: directory, networkProtocolClasses: nil, authorize: authorize, emit: emit)
    }

    /// `networkProtocolClasses` lets tests answer `fetch` without the internet.
    init(manifest: ExtensionManifest, directory: URL, networkProtocolClasses: [AnyClass]?,
         authorize: @escaping @MainActor (ConnectionAuthorizationRequest) async -> Bool, emit: @escaping (String) -> Void) {
        self.networkProtocolClasses = networkProtocolClasses
        self.manifest = manifest; self.directory = directory.resolvingSymlinksInPath()
        self.authorize = authorize; self.emit = emit
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration, delegate: LocalSessionDelegate(), delegateQueue: nil)
        configuration.timeoutIntervalForResource = 604_800
        websocketSession = URLSession(configuration: configuration, delegate: LocalSessionDelegate(), delegateQueue: nil)
    }

    public func receive(_ command: ConnectionCommand) {
        guard !stopped else { return }
        do {
            try command.validate(expectedExtensionID: manifest.id)
            guard operations[command.requestID] == nil, operations.count < 32 else {
                throw ProtocolError.invalid("Too many pending or duplicate connection operations")
            }
            operations[command.requestID] = Task { [weak self] in
                guard let self else { return }
                defer { self.operations.removeValue(forKey: command.requestID) }
                do {
                    let result = try await self.perform(command)
                    if !Task.isCancelled { self.send(ConnectionResponse(requestID: command.requestID, result: result)) }
                } catch {
                    if !Task.isCancelled {
                        self.send(ConnectionResponse(requestID: command.requestID, error: String(error.localizedDescription.prefix(2048))))
                    }
                }
            }
        } catch { send(ConnectionResponse(requestID: command.requestID, error: error.localizedDescription)) }
    }

    public func stop() {
        guard !stopped else { return }
        for id in operations.keys { send(ConnectionResponse(requestID: id, error: "Extension connections disconnected")) }
        for (id, stream) in streams {
            send(ConnectionEvent(connectionID: id, sessionID: stream.sessionID, event: "closed", error: "Extension connections disconnected"))
        }
        stopped = true
        for operation in operations.values { operation.cancel() }
        operations.removeAll()
        for stream in streams.values { stream.stop() }
        streams.removeAll(); granted.removeAll()
        for decision in pendingDecisions.values { decision.cancel() }
        pendingDecisions.removeAll()
        session.invalidateAndCancel()
        websocketSession.invalidateAndCancel()
        networkSession?.invalidateAndCancel()
    }

    /// SHA-256 over the transport, destination and, for helpers, the binary itself.
    nonisolated static func fingerprint(executable: URL?, definition: ConnectionDefinition) throws -> String {
        var hash = SHA256()
        hash.update(data: Data(definition.transport.rawValue.utf8))
        if let executable {
            hash.update(data: Data(executable.path.utf8))
            for argument in definition.arguments ?? [] { hash.update(data: Data([0])); hash.update(data: Data(argument.utf8)) }
            let handle = try FileHandle(forReadingFrom: executable)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        } else {
            hash.update(data: Data((definition.endpoint ?? "").utf8))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func perform(_ command: ConnectionCommand) async throws -> JSONValue {
        try manifest.validate()
        if command.operation == .fetch {
            guard let request = command.fetch else { throw ProtocolError.invalid("fetch request is missing") }
            return try await fetch(request)
        }
        guard let definition = manifest.connections?[command.connectionID] else {
            throw ProtocolError.invalid("Connection is not declared in this extension's manifest")
        }
        try definition.validate(permissions: manifest.permissions)
        if command.operation == .close {
            closedSessions[command.connectionID] = command.sessionID
            if let stream = streams[command.connectionID], stream.sessionID == command.sessionID {
                streams.removeValue(forKey: command.connectionID)?.stop()
            }
            return .null
        }
        let executable = definition.transport == .stdio ? try resolveExecutable(definition.executable!) : nil
        if !granted.contains(command.connectionID) {
            let interactive = command.interactive ?? true
            let target = executable.map { $0.path + "\nArguments: " + (definition.arguments ?? []).joined(separator: " · ") }
                ?? definition.endpoint!
            let request = ConnectionAuthorizationRequest(
                connectionID: command.connectionID, target: target,
                fingerprint: try Self.fingerprint(executable: executable, definition: definition), interactive: interactive)
            // Concurrent operations on one connection share a single question.
            let key = "\(command.connectionID)|\(interactive)"
            let decision = pendingDecisions[key] ?? Task { [authorize] in await authorize(request) }
            pendingDecisions[key] = decision
            let allowed = await decision.value
            if pendingDecisions[key] == decision { pendingDecisions.removeValue(forKey: key) }
            guard !stopped, !Task.isCancelled else { throw ProtocolError.invalid("Extension connections disconnected") }
            guard allowed else {
                throw ProtocolError.invalid(interactive ? "Connection access was not granted."
                                            : "Connection access is required. Connect from the extension's settings.")
            }
            granted.insert(command.connectionID)
        }
        switch command.operation {
        case .request:
            guard let request = command.request else { throw ProtocolError.invalid("HTTP request is missing") }
            return try await requestHTTP(request, definition: definition)
        case .open:
            guard definition.transport != .http, let sessionID = command.sessionID, !sessionID.isEmpty else {
                throw ProtocolError.invalid("Stream requires a session identifier and a WebSocket or stdio transport")
            }
            guard closedSessions[command.connectionID] != sessionID else { throw ProtocolError.invalid("Stream was closed while opening") }
            if let stream = streams[command.connectionID] {
                guard stream.sessionID == sessionID else { throw ProtocolError.invalid("Connection is already open") }
                return .null
            }
            let stream = Stream(sessionID: sessionID)
            streams[command.connectionID] = stream
            do {
                if let executable {
                    let process = StdioConnection()
                    stream.process = process
                    try process.start(executable: executable, arguments: definition.arguments ?? [],
                                      directory: definition.executable!.hasPrefix("./") ? directory : FileManager.default.homeDirectoryForCurrentUser) { [weak self, weak stream] message in
                        guard let self, let stream else { return }
                        self.deliver(message, id: command.connectionID, stream: stream)
                    } onClose: { [weak self, weak stream] error in
                        guard let self, let stream else { return }
                        self.closed(command.connectionID, stream: stream, error: error)
                    }
                } else {
                    let task = websocketSession.webSocketTask(with: URL(string: definition.endpoint!)!)
                    task.maximumMessageSize = maximumConnectionPayloadBytes
                    stream.websocket = task; task.resume()
                    stream.reader = Task { [weak self, weak stream] in
                        do {
                            while !Task.isCancelled {
                                let frame = try await task.receive()
                                let data: Data
                                switch frame {
                                case .string(let text): data = Data(text.utf8)
                                case .data(let bytes): data = bytes
                                @unknown default: throw ProtocolError.invalid("Unsupported WebSocket frame")
                                }
                                guard data.count <= maximumConnectionPayloadBytes else { throw ProtocolError.invalid("Connection message exceeds 64 KiB") }
                                let value = try JSONDecoder().decode(JSONValue.self, from: data)
                                guard let self, let stream else { return }
                                self.deliver(value, id: command.connectionID, stream: stream)
                            }
                        } catch {
                            if !Task.isCancelled, let self, let stream { self.closed(command.connectionID, stream: stream, error: error.localizedDescription) }
                        }
                    }
                }
            } catch { streams.removeValue(forKey: command.connectionID)?.stop(); throw error }
            return .null
        case .send:
            guard let stream = streams[command.connectionID], stream.sessionID == command.sessionID,
                  let message = command.message else { throw ProtocolError.invalid("Stream is closed or message is missing") }
            let data = try JSONEncoder().encode(message)
            guard data.count <= maximumConnectionPayloadBytes else { throw ProtocolError.invalid("Connection message exceeds 64 KiB") }
            if let process = stream.process { try await process.write(data + Data([10])) }
            else if let websocket = stream.websocket { try await websocket.send(.string(String(decoding: data, as: UTF8.self))) }
            return .null
        case .close, .fetch: return .null
        }
    }

    private func requestHTTP(_ input: ConnectionHTTPRequest, definition: ConnectionDefinition) async throws -> JSONValue {
        var request = URLRequest(url: try input.url(for: definition))
        request.httpMethod = input.method
        request.timeoutInterval = Double(input.timeoutMs ?? 15_000) / 1000
        request.allHTTPHeaderFields = input.headers
        request.httpBody = input.body.map { Data($0.utf8) }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw ProtocolError.invalid("Invalid HTTP response") }
        if response.expectedContentLength > maximumConnectionPayloadBytes { throw ProtocolError.invalid("HTTP response exceeds 64 KiB") }
        var body = Data()
        for try await byte in bytes {
            guard body.count < maximumConnectionPayloadBytes else { throw ProtocolError.invalid("HTTP response exceeds 64 KiB") }
            body.append(byte)
        }
        guard let text = String(data: body, encoding: .utf8) else { throw ProtocolError.invalid("HTTP response must be UTF-8 text") }
        let headers = response.allHeaderFields.reduce(into: [String: JSONValue]()) { values, item in
            values[String(describing: item.key)] = .string(String(describing: item.value))
        }
        let result = JSONValue.object(["status": .number(Double(response.statusCode)), "headers": .object(headers), "body": .string(text)])
        guard try JSONEncoder().encode(result).count <= maximumMessageBytes - 1024 else {
            throw ProtocolError.invalid("Encoded HTTP response exceeds the message limit")
        }
        return result
    }

    /// The person agreed to these hosts in the install review, so `fetch` asks nothing.
    private func fetch(_ input: NetworkRequest) async throws -> JSONValue {
        let hosts = manifest.network ?? []
        var request = URLRequest(url: try input.validatedURL(hosts: hosts))
        request.httpMethod = input.method
        request.timeoutInterval = Double(input.timeoutMs ?? 15_000) / 1000
        request.allHTTPHeaderFields = input.headers
        request.httpBody = input.body.map { Data($0.utf8) }
        let session = networkSession ?? {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForResource = 30
            configuration.httpMaximumConnectionsPerHost = 4
            if let networkProtocolClasses { configuration.protocolClasses = networkProtocolClasses }
            let created = URLSession(configuration: configuration, delegate: NetworkSessionDelegate(hosts: hosts), delegateQueue: nil)
            networkSession = created
            return created
        }()
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw ProtocolError.invalid("Invalid HTTP response") }
        let tooLarge = ProtocolError.invalid("fetch responses are limited to 192 KiB")
        if response.expectedContentLength > maximumFetchBodyBytes { throw tooLarge }
        var body = Data()
        for try await byte in bytes {
            guard body.count < maximumFetchBodyBytes else { throw tooLarge }
            body.append(byte)
        }
        guard let text = String(data: body, encoding: .utf8) else { throw ProtocolError.invalid("fetch responses must be UTF-8 text") }
        let headers = response.allHeaderFields.reduce(into: [String: JSONValue]()) { values, item in
            values[String(describing: item.key).lowercased()] = .string(String(describing: item.value))
        }
        let result = JSONValue.object([
            "status": .number(Double(response.statusCode)), "url": .string(response.url?.absoluteString ?? input.url),
            "headers": .object(headers), "body": .string(text),
        ])
        guard try JSONEncoder().encode(result).count <= maximumMessageBytes - 1024 else { throw tooLarge }
        return result
    }

    private func resolveExecutable(_ name: String) throws -> URL {
        let manager = FileManager.default
        let candidate: URL
        if name.hasPrefix("./") {
            candidate = directory.appendingPathComponent(String(name.dropFirst(2))).resolvingSymlinksInPath()
            guard candidate.path.hasPrefix(directory.path + "/") else { throw ProtocolError.invalid("Bundled helper escapes the extension directory") }
        } else if name.hasPrefix("/") { candidate = URL(fileURLWithPath: name).resolvingSymlinksInPath() }
        else {
            let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", manager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]
            guard let found = paths.map({ URL(fileURLWithPath: $0).appendingPathComponent(name) }).first(where: { manager.isExecutableFile(atPath: $0.path) }) else {
                throw ProtocolError.invalid("Install \(name) or declare its absolute executable path in the manifest")
            }
            candidate = found.resolvingSymlinksInPath()
        }
        guard manager.isExecutableFile(atPath: candidate.path) else { throw ProtocolError.invalid("Connection executable is not runnable") }
        return candidate
    }

    private func deliver(_ message: JSONValue, id: String, stream: Stream) {
        guard streams[id] === stream else { return }
        if Date.now.timeIntervalSince(stream.intervalStart) >= 1 { stream.intervalStart = .now; stream.messageCount = 0 }
        stream.messageCount += 1
        guard stream.messageCount <= 256 else { closed(id, stream: stream, error: "Connection exceeded 256 messages per second"); return }
        send(ConnectionEvent(connectionID: id, sessionID: stream.sessionID, event: "message", message: message))
    }

    private func closed(_ id: String, stream: Stream, error: String?) {
        guard streams[id] === stream else { return }
        streams.removeValue(forKey: id)?.stop()
        send(ConnectionEvent(connectionID: id, sessionID: stream.sessionID, event: "closed", error: error.map { String($0.prefix(2048)) }))
    }

    private func send(_ value: some Encodable) {
        guard !stopped, let data = try? JSONEncoder().encode(value) else { return }
        guard data.count <= maximumMessageBytes else { return }
        emit(String(decoding: data, as: UTF8.self))
    }
}
