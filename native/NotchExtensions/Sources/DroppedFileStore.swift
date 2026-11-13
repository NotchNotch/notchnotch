import Foundation
import UniformTypeIdentifiers
import NotchProtocol

/// The files people dropped on each extension. An extension holds an opaque
/// id; this keeps the bookmark behind it, so the file is found again after
/// it's renamed or moved, and after a restart. Ids belong to one extension.
public final class DroppedFileStore {
    public static let maximumPerExtension = 10_000

    private struct Entry: Codable {
        var bookmark: Data
        var file: DroppedFile
        /// A copy the app made with `keepCopy`: deleted when it's released.
        var copy: URL?
    }
    private let directory: URL
    private var loaded: [String: [String: Entry]] = [:]

    public init(directory: URL) { self.directory = directory }

    /// A handle for `url`, kept for `extensionID`.
    public func add(_ url: URL, for extensionID: String) throws -> DroppedFile {
        var entries = load(extensionID)
        guard entries.count < Self.maximumPerExtension else {
            throw ProtocolError.invalid("This extension keeps too many files. Remove some first.")
        }
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey, .isPackageKey])
        let folder = values.isDirectory == true && values.isPackage != true
        let file = DroppedFile(id: UUID().uuidString.lowercased(), name: String(url.lastPathComponent.prefix(1024)),
                               type: String((values.contentType ?? (folder ? .folder : .data)).identifier.prefix(128)),
                               size: folder ? 0 : Double(values.fileSize ?? 0), kind: folder ? .folder : .file)
        entries[file.id] = Entry(bookmark: try url.bookmarkData(), file: file)
        save(entries, for: extensionID)
        return file
    }

    public func file(_ id: String, for extensionID: String) -> DroppedFile? { load(extensionID)[id]?.file }

    /// Where the file is now, or nil when it's gone or the id isn't this extension's.
    public func url(_ id: String, for extensionID: String) -> URL? {
        var entries = load(extensionID)
        guard let entry = entries[id] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: entry.bookmark, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        if stale, let fresh = try? url.bookmarkData() {
            entries[id]?.bookmark = fresh
            entries[id]?.file.name = String(url.lastPathComponent.prefix(1024))
            save(entries, for: extensionID)
        }
        return url
    }

    /// Points `id` at the file's new place after the app moved it.
    public func replace(_ id: String, with url: URL, for extensionID: String) {
        var entries = load(extensionID)
        guard entries[id] != nil, let bookmark = try? url.bookmarkData() else { return }
        entries[id]?.bookmark = bookmark
        entries[id]?.file.name = String(url.lastPathComponent.prefix(1024))
        save(entries, for: extensionID)
    }

    /// Copies the file into the app's own folder and hands back a handle to
    /// the copy, which survives the original being moved, emptied or deleted.
    /// The original's handle is released.
    public func keepCopy(_ id: String, for extensionID: String) throws -> DroppedFile {
        guard let url = url(id, for: extensionID) else { throw ProtocolError.invalid("A file is gone, or isn’t this extension’s.") }
        let folder = copiesDirectory(extensionID).appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(url.lastPathComponent)
        do { try FileManager.default.copyItem(at: url, to: target) } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        var file = try add(target, for: extensionID)
        var entries = load(extensionID)
        entries[file.id]?.copy = folder
        file.name = String(url.lastPathComponent.prefix(1024))
        entries[file.id]?.file = file
        save(entries, for: extensionID)
        release([id], for: extensionID)
        return file
    }

    public func release(_ ids: [String], for extensionID: String) {
        var entries = load(extensionID)
        for id in ids {
            if let copy = entries[id]?.copy, copy.path.hasPrefix(copiesDirectory(extensionID).path) {
                try? FileManager.default.removeItem(at: copy)
            }
            entries.removeValue(forKey: id)
        }
        save(entries, for: extensionID)
    }

    private func copiesDirectory(_ extensionID: String) -> URL {
        directory.appendingPathComponent("Copies", isDirectory: true).appendingPathComponent(extensionID, isDirectory: true)
    }

    /// Forgets every file an extension kept, when it's uninstalled.
    public func removeAll(for extensionID: String) {
        loaded[extensionID] = [:]
        try? FileManager.default.removeItem(at: copiesDirectory(extensionID))
        try? FileManager.default.removeItem(at: storeURL(extensionID))
    }

    private func storeURL(_ extensionID: String) -> URL { directory.appendingPathComponent("\(extensionID).json") }

    private func load(_ extensionID: String) -> [String: Entry] {
        if let entries = loaded[extensionID] { return entries }
        let entries = (try? Data(contentsOf: storeURL(extensionID)))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        loaded[extensionID] = entries
        return entries
    }

    private func save(_ entries: [String: Entry], for extensionID: String) {
        loaded[extensionID] = entries
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: storeURL(extensionID), options: [.atomic])
    }
}
