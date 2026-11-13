import Foundation
import Testing
@testable import NotchExtensions

@Test func droppedFilesAreFoundAgainAfterAMoveAndOnlyByTheirExtension() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = root.appendingPathComponent("files"), folder = files.appendingPathComponent("Photos")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let note = files.appendingPathComponent("Note.txt")
    try Data("hello".utf8).write(to: note)

    let store = DroppedFileStore(directory: root.appendingPathComponent("store"))
    let file = try store.add(note, for: "shelf")
    #expect(file.name == "Note.txt" && file.kind == .file && file.size == 5 && file.type == "public.plain-text")
    #expect(try store.add(folder, for: "shelf").kind == .folder)
    #expect(store.url(file.id, for: "other") == nil, "an id is only good for the extension that got it")

    let moved = folder.appendingPathComponent("Renamed.txt")
    try FileManager.default.moveItem(at: note, to: moved)
    let reopened = DroppedFileStore(directory: root.appendingPathComponent("store"))
    #expect(reopened.url(file.id, for: "shelf")?.lastPathComponent == "Renamed.txt", "bookmarks follow a move and survive a restart")
    #expect(reopened.file(file.id, for: "shelf")?.name == "Renamed.txt")

    reopened.release([file.id], for: "shelf")
    #expect(reopened.url(file.id, for: "shelf") == nil)
    reopened.removeAll(for: "shelf")
    #expect(DroppedFileStore(directory: root.appendingPathComponent("store")).file(file.id, for: "shelf") == nil)
}

@Test func aKeptCopySurvivesTheOriginalAndIsDeletedOnRelease() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let original = root.appendingPathComponent("Report.pdf")
    try Data("pdf".utf8).write(to: original)
    let store = DroppedFileStore(directory: root.appendingPathComponent("store"))
    let handle = try store.add(original, for: "shelf")
    let copy = try store.keepCopy(handle.id, for: "shelf")
    #expect(copy.name == "Report.pdf" && store.url(handle.id, for: "shelf") == nil, "the original's handle is released")
    try FileManager.default.removeItem(at: original)
    let kept = try #require(store.url(copy.id, for: "shelf"))
    #expect(try Data(contentsOf: kept) == Data("pdf".utf8))
    store.release([copy.id], for: "shelf")
    #expect(!FileManager.default.fileExists(atPath: kept.path), "releasing a copy deletes it")
}
