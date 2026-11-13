import Foundation
import NotchProtocol
import NotchConnections
import NotchCapabilities
import NotchExtensions
import AppKit
import NotchCore

@MainActor
final class RunnerConnection {
    let manifest: ExtensionManifest
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var buffer = Data()
    private var stopping = false
    private var failed = false
    private let onSnapshot: (Snapshot) -> Void
    private let onFailure: (String) -> Void
    private let onLog: (ExtensionLogEntry.Level, String) -> Void
    private var liveness = RunnerLiveness(startedAt: .now)
    private var lastStderr = ""
    private let directory: URL
    private var broker: ConnectionBroker?
    private var storageURL: URL?
    /// Set by each click or keystroke sent to the extension; lets it open one link.
    private var activation = UserActivation()
    private var resources = RunnerResources()
    private let writer = DispatchQueue(label: "dev.notchnotch.runner-input", qos: .utility)
    private var queuedBytes = 0

    init(manifest: ExtensionManifest, directory: URL, onSnapshot: @escaping (Snapshot) -> Void,
         onFailure: @escaping (String) -> Void, onLog: @escaping (ExtensionLogEntry.Level, String) -> Void = { _, _ in }) {
        self.manifest = manifest; self.onSnapshot = onSnapshot; self.onFailure = onFailure; self.onLog = onLog
        self.directory = directory
    }

    func start(executable: URL, bundle: URL, storage: URL, preferences: ExtensionPreferenceStore? = nil) throws {
        try manifest.validate()
        storageURL = storage
        process.executableURL = executable
        let sendsPreferences = preferences != nil && !(manifest.preferences ?? []).isEmpty
        // Values arrive on stdin, not in arguments: other processes can read arguments.
        process.arguments = [bundle.path, manifest.id, storage.path] + (sendsPreferences ? ["--preferences"] : [])
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // Do not pass the developer shell's environment (and potential secrets) into extensions.
        process.environment = ["LANG": "en_US.UTF-8"]
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.read(data) }
        }
        // Stderr is diagnostic output (JavaScriptCore and system frameworks write
        // there too). It is logged; only exit, protocol errors or liveness fail.
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                let message = String(decoding: data.prefix(4096), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                Task { @MainActor in
                    guard let self, !message.isEmpty else { return }
                    self.lastStderr = message
                    self.onLog(.error, message)
                }
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                guard let self, !self.stopping else { return }
                let detail = self.lastStderr.isEmpty ? "" : ": \(self.lastStderr.split(separator: "\n").last ?? "")"
                self.fail("\(self.manifest.name) stopped (exit \(status))\(detail)")
            }
        }
        do { try process.run() }
        catch { stop(); throw error }
        if sendsPreferences, let preferences {
            let manifest = manifest
            Task { [weak self] in
                // Reading passwords can wait for a Keychain prompt; the runner waits for this line.
                let values = await Task.detached { preferences.values(for: manifest) }.value
                guard let self, let data = try? JSONEncoder().encode(RunnerPreferences(values: values)) else { return }
                self.enqueue(data + Data([10]), failure: "Could not send preferences to \(manifest.name)")
                // A Keychain prompt doesn't count against the runner's startup time.
                self.liveness = RunnerLiveness(startedAt: .now)
            }
        }
        liveness = RunnerLiveness(startedAt: .now)
        resources = RunnerResources()
    }

    func send(action: String, value: String?) {
        activation.grant()
        guard process.isRunning, !failed,
              let data = try? JSONEncoder().encode(UserEvent(action: action, value: value)) else { return }
        enqueue(data + Data([10]), failure: "Could not send event to \(manifest.name)")
    }

    /// Called about once a second by the app for every runner from one shared
    /// timer: a timer per runner woke the main thread once per runner each second.
    func checkLiveness() {
        guard !stopping, !failed else { return }
        switch liveness.tick(now: .now) {
        case .none: break
        case .ping(let id):
            if let data = try? JSONEncoder().encode(RunnerPing(id: id)) {
                enqueue(data + Data([10]), failure: "Could not reach \(manifest.name)")
            }
        case .fail(let reason):
            // terminate() is SIGTERM; a runner stuck in JavaScript still exits.
            fail("\(manifest.name) \(reason) and was stopped.")
            return
        }
        if let usage = ProcessUsage.sample(pid: process.processIdentifier),
           let reason = resources.sample(memoryBytes: usage.memoryBytes, cpuTime: usage.cpuTime, now: .now) {
            fail("\(manifest.name) \(reason) and was stopped.")
        }
    }

    func stop() {
        stopping = true
        resetConnections()
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        try? input.fileHandleForWriting.close()
    }

    func resetConnections() { broker?.stop(); broker = nil }

    private func handleConnection(_ command: ConnectionCommand) {
        if [.secretGet, .secretSet, .secretDelete].contains(command.operation) { handleSecret(command); return }
        if command.operation == .openURL { handleOpenURL(command); return }
        if command.operation == .files { handleFiles(command); return }
        if broker == nil {
            let icon = ExtensionIcon(manifest: manifest, directory: directory)
            broker = ConnectionBroker(manifest: manifest, directory: directory, capabilities: SystemCapabilities.session) { [manifest] request in
                let store = ConnectionGrantStore()
                if store.isGranted(extensionID: manifest.id, connectionID: request.connectionID, fingerprint: request.fingerprint) {
                    return true
                }
                guard request.interactive else { return false }
                let decision = await ConnectionConsentPresenter.shared.ask(.init(
                    extensionName: manifest.name, extensionIcon: icon, connectionID: request.connectionID,
                    target: request.target, runsTool: manifest.connections?[request.connectionID]?.transport == .stdio,
                    capability: request.capability))
                if decision == .always {
                    store.grant(extensionID: manifest.id, connectionID: request.connectionID, fingerprint: request.fingerprint)
                }
                return decision != .deny
            } emit: { [weak self] json in self?.sendConnectionMessage(json) }
        }
        broker?.receive(command)
    }

    /// Writes the extension's storage on its behalf; the runner itself can't write files.
    private func saveStorage(_ line: Data) throws {
        guard let storageURL,
              let message = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              let values = message["values"] as? [String: Any] else { throw ProtocolError.invalid("Invalid storage message") }
        let data = try JSONSerialization.data(withJSONObject: values)
        guard data.count <= maximumStorageBytes else { throw ProtocolError.invalid("Extension storage exceeds its limit") }
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: storageURL, options: .atomic)
    }

    /// Opens a link only right after the person interacted with this extension.
    private func handleOpenURL(_ command: ConnectionCommand) {
        let response: ConnectionResponse
        do {
            try command.validate(expectedExtensionID: manifest.id)
            let url = try OpenURLPolicy.validate(command.url ?? "")
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                throw ProtocolError.invalid("No app on this Mac opens \(url.scheme ?? "this") links.")
            }
            guard activation.consume() else {
                throw ProtocolError.invalid("open works only in response to a click or key press.")
            }
            NSWorkspace.shared.open(url)
            response = ConnectionResponse(requestID: command.requestID, result: .null)
        } catch {
            response = ConnectionResponse(requestID: command.requestID, error: String(error.localizedDescription.prefix(2048)))
        }
        if let data = try? JSONEncoder().encode(response) { sendConnectionMessage(String(decoding: data, as: UTF8.self)) }
    }

    /// The app's service for dropped files, set by the model.
    var files: FilesService?

    private func handleFiles(_ command: ConnectionCommand) {
        let permissions = manifest.permissions, extensionID = manifest.id
        // Taken now: the click that allowed it must not outlast a slow request.
        let activated = command.files.map { !FilesService.needsActivation($0.action) } ?? false || activation.consume()
        Task { [weak self] in
            let response: ConnectionResponse
            do {
                try command.validate(expectedExtensionID: extensionID)
                guard let request = command.files, let files = self?.files else { throw ProtocolError.invalid("Files request is missing") }
                guard activated else {
                    throw ProtocolError.invalid("files.\(request.action.rawValue) works only in response to a click or key press.")
                }
                let result = try await files.perform(request, extensionID: extensionID, permissions: permissions)
                response = ConnectionResponse(requestID: command.requestID, result: result)
            } catch {
                response = ConnectionResponse(requestID: command.requestID, error: String(error.localizedDescription.prefix(2048)))
            }
            if let data = try? JSONEncoder().encode(response) { self?.sendConnectionMessage(String(decoding: data, as: UTF8.self)) }
        }
    }

    /// Keychain calls may wait for a macOS prompt, so they run off the main thread.
    private func handleSecret(_ command: ConnectionCommand) {
        let extensionID = manifest.id
        Task { [weak self] in
            let response: ConnectionResponse
            do {
                try command.validate(expectedExtensionID: extensionID)
                guard let secret = command.secret else { throw ProtocolError.invalid("Secret request is missing") }
                try secret.validate(requiresValue: command.operation == .secretSet)
                let result: JSONValue = try await Task.detached {
                    let store = ExtensionSecretStore()
                    switch command.operation {
                    case .secretGet: return try store.value(extensionID: extensionID, key: secret.key).map(JSONValue.string) ?? .null
                    case .secretSet: try store.set(extensionID: extensionID, key: secret.key, value: secret.value ?? ""); return .null
                    default: try store.delete(extensionID: extensionID, key: secret.key); return .null
                    }
                }.value
                response = ConnectionResponse(requestID: command.requestID, result: result)
            } catch {
                response = ConnectionResponse(requestID: command.requestID, error: String(error.localizedDescription.prefix(2048)))
            }
            guard let self, let data = try? JSONEncoder().encode(response) else { return }
            self.sendConnectionMessage(String(decoding: data, as: UTF8.self))
        }
    }

    private func sendConnectionMessage(_ json: String) {
        guard process.isRunning, !failed, json.utf8.count <= maximumMessageBytes else { return }
        enqueue(Data((json + "\n").utf8), failure: "Could not deliver connection message to \(manifest.name)")
    }

    private func enqueue(_ data: Data, failure: String) {
        guard !stopping, !failed, queuedBytes + data.count <= 524_288 else {
            if !stopping, !failed { fail("\(manifest.name) is not keeping up with incoming messages") }
            return
        }
        queuedBytes += data.count
        let handle = input.fileHandleForWriting
        writer.async { [weak self] in
            do {
                try handle.write(contentsOf: data)
                Task { @MainActor [weak self] in self?.queuedBytes -= data.count }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.queuedBytes -= data.count
                    if !self.stopping { self.fail(failure) }
                }
            }
        }
    }

    private func fail(_ message: String) {
        guard !failed, !stopping else { return }
        failed = true
        onFailure(String(message.prefix(4096)))
        stop()
    }

    private func read(_ data: Data) {
        guard !data.isEmpty, !failed, !stopping else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer.prefix(upTo: newline))
            buffer.removeSubrange(...newline)
            guard line.count <= maximumMessageBytes else { fail("Extension message too large"); return }
            do {
                struct Header: Decodable { let type: String; let protocolVersion: Int; let extensionID: String }
                let header = try JSONDecoder().decode(Header.self, from: line)
                guard header.protocolVersion == 1, header.extensionID == manifest.id else {
                    throw ProtocolError.invalid("Extension sent an invalid envelope")
                }
                if let reason = resources.message(now: .now) { fail("\(manifest.name) \(reason) and was stopped."); return }
                liveness.received()
                switch header.type {
                case "pong":
                    liveness.pong(try JSONDecoder().decode(RunnerPong.self, from: line).id)
                case "snapshot":
                    let snapshot = try JSONDecoder().decode(Snapshot.self, from: line)
                    try snapshot.validate(expectedExtensionID: manifest.id, imageHosts: manifest.imageHosts ?? [])
                    onSnapshot(snapshot)
                case "error":
                    let notice = try JSONDecoder().decode(RuntimeNotice.self, from: line)
                    fail(notice.message)
                case "log":
                    onLog(.info, try JSONDecoder().decode(RuntimeNotice.self, from: line).message)
                case "storage":
                    try saveStorage(line)
                case "connectionCommand":
                    let command = try JSONDecoder().decode(ConnectionCommand.self, from: line)
                    try command.validate(expectedExtensionID: manifest.id)
                    handleConnection(command)
                default: throw ProtocolError.invalid("Unknown extension message")
                }
            } catch { fail(error.localizedDescription); return }
        }
        if buffer.count > maximumMessageBytes { fail("Extension message too large") }
    }
}
