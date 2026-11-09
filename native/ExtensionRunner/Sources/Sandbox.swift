import Foundation

@_silgen_name("sandbox_init")
private func sandbox_init(_ profile: UnsafePointer<CChar>, _ flags: UInt64,
                          _ errorbuf: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
@_silgen_name("sandbox_free_error")
private func sandbox_free_error(_ errorbuf: UnsafeMutablePointer<CChar>?)

/// Locks the runner down before it runs extension code, the way Chrome
/// sandboxes its renderers on macOS. Everything the extension may do goes
/// through the app over stdin/stdout, which stay open: fetch, connections,
/// secrets and storage writes. The runner itself can't open files outside the
/// system, reach the network, or start processes.
enum Sandbox {
    static let profile = #"""
    (version 1)
    (deny default)

    ; JavaScriptCore compiles JavaScript to machine code.
    (allow dynamic-code-generation)

    ; System frameworks, ICU data, time zones and locale settings.
    (allow file-read*
        (subpath "/System")
        (subpath "/usr/lib")
        (subpath "/usr/share")
        (subpath "/Library/Apple/System")
        (subpath "/private/var/db/timezone")
        (literal "/private/etc/localtime")
        (literal "/dev/urandom")
        (literal "/dev/random"))
    (allow file-read-metadata)
    (allow file-read* file-write-data (literal "/dev/null"))

    (allow user-preference-read)
    (allow sysctl-read)
    (allow process-info* (target self))
    (allow signal (target self))
    (allow mach-lookup
        (global-name "com.apple.cfprefsd.daemon")
        (global-name "com.apple.cfprefsd.agent")
        (global-name "com.apple.logd")
        (global-name "com.apple.diagnosticd"))
    """#

    /// Applies the profile to this process for the rest of its life.
    static func enter() throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sandbox_init(profile, 0, &error) == 0 else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sandbox_free_error(error)
            throw NSError(domain: "ExtensionRunner.Sandbox", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not enter the sandbox: \(message)"])
        }
    }
}

/// `ExtensionRunner --sandbox-probe <readable file> <writable folder>` enters the
/// sandbox and tries what extension code must never do, printing one JSON
/// object of what succeeded. Tests use it to prove the sandbox holds.
enum SandboxProbe {
    static func run(readable: String, writable: String) -> Never {
        var results: [String: Bool] = [:]
        results["readBeforeSandbox"] = FileManager.default.isReadableFile(atPath: readable) && (try? Data(contentsOf: URL(fileURLWithPath: readable))) != nil
        do { try Sandbox.enter() } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1)
        }
        results["readUserFile"] = (try? Data(contentsOf: URL(fileURLWithPath: readable))) != nil
        results["writeFile"] = (try? Data("x".utf8).write(to: URL(fileURLWithPath: writable).appendingPathComponent("escaped.txt"))) != nil
        results["listHome"] = (try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory())) != nil
        results["network"] = connectsToLocalhost()
        results["spawn"] = spawns("/usr/bin/true")
        results["readSystem"] = (try? Data(contentsOf: URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist"))) != nil
        let data = (try? JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])) ?? Data("{}".utf8)
        FileHandle.standardOutput.write(data + Data([10]))
        exit(0)
    }

    private static func connectsToLocalhost() -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(9).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        // Refused means the connection attempt was allowed; only a sandbox denial is EPERM.
        return result == 0 || errno != EPERM
    }

    private static func spawns(_ path: String) -> Bool {
        var pid: pid_t = 0
        let status = path.withCString { executable in
            var arguments: [UnsafeMutablePointer<CChar>?] = [strdup(executable), nil]
            defer { free(arguments[0]) }
            return posix_spawn(&pid, executable, nil, nil, &arguments, nil)
        }
        if status == 0 { var code: Int32 = 0; waitpid(pid, &code, 0) }
        return status == 0
    }
}

