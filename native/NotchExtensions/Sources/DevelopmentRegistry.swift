import Foundation

/// Extensions that `notchnotch dev` is running from a project folder. The CLI
/// writes `<id>.json` with the built folder and its own process id; the app
/// loads the folder while that process lives, and writes the extension's logs
/// to `<id>.log` for the CLI to print. Only processes of the same user can
/// write here, and they could run code anyway, unlike a URL a web page opens.
public struct DevelopmentRegistry: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public struct Entry: Equatable, Sendable {
        public let id: String
        public let folder: URL
        /// The project folder, where Store screenshots go. Older CLIs don't send it.
        public var source: URL? = nil
    }

    private struct Registration: Decodable {
        let path: String
        let pid: Int32
        let source: String?
    }

    /// Registrations whose CLI is still running and whose folder exists.
    public func entries() -> [Entry] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { file in
            guard let data = try? Data(contentsOf: file), data.count <= 16_384,
                  let registration = try? JSONDecoder().decode(Registration.self, from: data),
                  registration.pid > 0, kill(registration.pid, 0) == 0 || errno == EPERM else { return nil }
            let folder = URL(fileURLWithPath: registration.path).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return Entry(id: file.deletingPathExtension().lastPathComponent, folder: folder,
                         source: registration.source.map { URL(fileURLWithPath: $0).standardizedFileURL })
        }
    }

    /// Ids for which `notchnotch screenshot` asked for Store screenshots.
    public func screenshotRequests() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "screenshot" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    /// Answers a request: the files written, or why there are none.
    public func finishScreenshots(id: String, files: [URL], error: String?) {
        struct Result: Encodable { let files: [String]; let error: String? }
        let result = Result(files: files.map(\.path), error: error)
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: directory.appendingPathComponent("\(id).screenshot-result"), options: .atomic)
        }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).screenshot"))
    }

    /// Appends one line to the extension's development log, if it has one.
    public func appendLog(id: String, level: String, message: String) {
        let file = directory.appendingPathComponent("\(id).log")
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("\(level)\t\(message.replacingOccurrences(of: "\n", with: "\n\t"))\n".utf8))
    }
}
