import Darwin
import Foundation
import NotchProtocol

/// Runs one declared stdio helper.
///
/// Helpers are spawned with responsibility disclaimed, so macOS treats each
/// helper as its own app for privacy permissions (TCC): its prompts use its own
/// bundle name and usage descriptions, and access granted to one extension's
/// helper is never inherited by NotchNotch or by another extension's helper.
@MainActor
final class StdioConnection {
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let writer = DispatchQueue(label: "dev.notchnotch.connection-input", qos: .utility)
    private(set) var pid: pid_t = 0
    private var running = false
    private var buffer = Data()
    private var diagnostic = ""
    private var stopped = false
    private var onClose: (@MainActor (String?) -> Void)?

    func start(executable: URL, arguments: [String], directory: URL,
               onMessage: @escaping @MainActor (JSONValue) -> Void,
               onClose: @escaping @MainActor (String?) -> Void) throws {
        self.onClose = onClose
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.buffer.append(data)
                do {
                    while let newline = self.buffer.firstIndex(of: 10) {
                        let line = self.buffer.prefix(upTo: newline)
                        guard line.count <= maximumConnectionPayloadBytes else { throw ProtocolError.invalid("Helper message exceeds 64 KiB") }
                        let message = line.isEmpty ? nil : try JSONDecoder().decode(JSONValue.self, from: line)
                        self.buffer.removeSubrange(...newline)
                        if let message { onMessage(message) }
                    }
                    guard self.buffer.count <= maximumConnectionPayloadBytes else { throw ProtocolError.invalid("Helper message exceeds 64 KiB") }
                } catch { onClose(error.localizedDescription) }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self else { return }
                self.diagnostic = String((self.diagnostic + String(decoding: data, as: UTF8.self)).suffix(2048))
            }
        }
        do {
            // Native adapters are explicitly trusted user processes. HOME supports
            // their own normal login/config files; shell tokens are never inherited.
            pid = try Self.spawn(executable: executable.path, arguments: arguments, directory: directory.path, environment: [
                "LANG": "en_US.UTF-8", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            ], stdin: input.fileHandleForReading.fileDescriptor, stdout: output.fileHandleForWriting.fileDescriptor,
               stderr: errors.fileHandleForWriting.fileDescriptor)
        } catch { stop(); throw error }
        running = true
        // The child owns these ends now; keeping them open here would hide EOF.
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        watchExit()
    }

    func write(_ data: Data) async throws {
        guard !stopped, running else { throw ProtocolError.invalid("Helper is not running") }
        let handle = input.fileHandleForWriting
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            writer.async {
                do { try handle.write(contentsOf: data); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        onClose = nil
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        // The exit watcher keeps running after stop so the child is always reaped.
        if running { kill(pid, SIGTERM) }
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close(); try? errors.fileHandleForReading.close()
    }

    private func watchExit() {
        let pid = pid
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        // Reaping must not depend on this object: it may be released right after stop().
        let reap: @Sendable () -> Void = { [weak self] in
            var status: Int32 = 0
            guard waitpid(pid, &status, WNOHANG) == pid else { return }
            source.cancel()
            MainActor.assumeIsolated { self?.exited(status: status) }
        }
        source.setEventHandler(handler: reap)
        source.resume()
        // A helper that exits before the source is armed produces no event.
        reap()
    }

    private func exited(status: Int32) {
        running = false
        guard !stopped, let onClose else { return }
        let signal = status & 0x7f
        let code = signal == 0 ? (status >> 8) & 0xff : signal
        onClose(code == 0 ? nil : "Helper exited (\(code)). \(diagnostic)")
    }

    /// `posix_spawn` with only the three pipe descriptors inherited, default
    /// signal handling and disclaimed responsibility.
    private static func spawn(executable: String, arguments: [String], directory: String, environment: [String: String],
                              stdin: Int32, stdout: Int32, stderr: Int32) throws -> pid_t {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") else {
            throw ProtocolError.invalid("This version of macOS can’t isolate helper permissions")
        }
        // Not in the public SDK; stable since macOS 10.14 and used the same way by Chromium and LLDB.
        typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
        let disclaim = unsafeBitCast(symbol, to: Disclaim.self)

        var attributes: posix_spawnattr_t?
        var actions: posix_spawn_file_actions_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }

        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)))
        var everySignal = sigset_t(), noSignal = sigset_t()
        sigfillset(&everySignal); sigemptyset(&noSignal)
        try check(posix_spawnattr_setsigdefault(&attributes, &everySignal))
        try check(posix_spawnattr_setsigmask(&attributes, &noSignal))
        try check(disclaim(&attributes, 1))

        try check(posix_spawn_file_actions_adddup2(&actions, stdin, STDIN_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, stdout, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, stderr, STDERR_FILENO))
        try check(posix_spawn_file_actions_addchdir_np(&actions, directory))

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        try check(posix_spawn(&pid, executable, &actions, &attributes, argv, envp))
        return pid
    }

    private static func check(_ result: Int32) throws {
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EINVAL) }
    }
}
