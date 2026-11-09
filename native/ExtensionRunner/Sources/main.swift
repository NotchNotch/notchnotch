import Foundation
import NotchRuntime
import NotchProtocol

@MainActor
final class Runner {
    let runtime: JavaScriptRuntime
    let extensionID: String
    private var input = Data()
    init(bundle: URL, extensionID: String, storage: URL?, preferences: [String: JSONValue], pending: Data) throws {
        self.extensionID = extensionID
        input = pending
        runtime = try JavaScriptRuntime(extensionID: extensionID, storageURL: storage, preferences: preferences) { json in
            FileHandle.standardOutput.write(Data((json + "\n").utf8))
        }
        try runtime.evaluate(String(contentsOf: bundle, encoding: .utf8), sourceURL: bundle)
    }
    func read(_ data: Data) {
        if data.isEmpty { runtime.stop(); exit(0) }
        input.append(data)
        processInput()
    }
    /// Handles every complete line in the buffer.
    func processInput() {
        while let newline = input.firstIndex(of: 10) {
            let line = input.prefix(upTo: newline)
            guard line.count <= maximumMessageBytes else { runtime.stop(); exit(1) }
            input.removeSubrange(...newline)
            if let ping = try? JSONDecoder().decode(RunnerPing.self, from: line), ping.type == "ping", ping.protocolVersion == 1 {
                // Answered on the JavaScript thread: a busy extension cannot answer.
                if let pong = try? JSONEncoder().encode(RunnerPong(extensionID: extensionID, id: ping.id)) {
                    FileHandle.standardOutput.write(pong + Data([10]))
                }
                continue
            }
            if let json = String(data: line, encoding: .utf8) { runtime.receive(json) }
        }
        guard input.count <= maximumMessageBytes else { runtime.stop(); exit(1) }
    }
}

let readsPreferences = CommandLine.arguments.contains("--preferences")
let arguments = CommandLine.arguments.filter { $0 != "--preferences" }
guard (3...4).contains(arguments.count) else {
    FileHandle.standardError.write(Data("Usage: ExtensionRunner <bundle.js> <extension-id> [storage.json] [--preferences]\n".utf8))
    exit(64)
}

/// With `--preferences`, the app sends the preference values before the
/// extension runs. Lines that arrive earlier, such as liveness pings, are kept
/// in order and handled once the extension is running.
func readPreferences() -> (values: [String: JSONValue], rest: Data) {
    var earlier = Data()
    var buffer = Data()
    while true {
        let chunk = FileHandle.standardInput.availableData
        if chunk.isEmpty { exit(0) }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            let rest = Data(buffer.suffix(from: buffer.index(after: newline)))
            if let message = try? JSONDecoder().decode(RunnerPreferences.self, from: line),
               message.protocolVersion == 1, message.type == "preferences" {
                return (message.values, earlier + rest)
            }
            earlier.append(line + Data([10]))
            buffer = rest
        }
        guard buffer.count + earlier.count <= maximumMessageBytes * 2 else { exit(1) }
    }
}

do {
    let storage = arguments.count == 4 ? URL(fileURLWithPath: arguments[3]) : nil
    let (preferences, pending) = readsPreferences ? readPreferences() : ([:], Data())
    let runner = try Runner(bundle: URL(fileURLWithPath: arguments[1]), extensionID: arguments[2], storage: storage,
                            preferences: preferences, pending: pending)
    if !pending.isEmpty { runner.processInput() }
    FileHandle.standardInput.readabilityHandler = { handle in
        let data = handle.availableData
        Task { @MainActor in runner.read(data) }
    }
    RunLoop.main.run()
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
