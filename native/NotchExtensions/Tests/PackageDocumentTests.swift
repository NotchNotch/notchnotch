import Foundation
import Testing
import NotchProtocol
@testable import NotchExtensions

@Test func markdownSplitsIntoTheBlocksTheAppRenders() {
    let blocks = Markdown.blocks("""
    # Title

    First line
    continues here.

    ## Set up
    1. Open **Setup**
    2. Connect
       with a wrapped line
    - bullet ![logo](media/logo.png)

    > Note

    ```sh
    npm run build
    ```
    ---
    """)
    #expect(blocks == [
        .heading(level: 1, text: "Title"),
        .paragraph("First line continues here."),
        .heading(level: 2, text: "Set up"),
        .list(ordered: true, items: ["Open **Setup**", "Connect with a wrapped line"]),
        .list(ordered: false, items: ["bullet logo"]),
        .quote("Note"),
        .code("npm run build"),
        .rule,
    ])
}

@Test func anUnclosedCodeFenceKeepsItsText() {
    #expect(Markdown.blocks("```\nlet x = 1") == [.code("let x = 1")])
    #expect(Markdown.blocks("#NoSpace") == [.paragraph("#NoSpace")])
}

@Test func packagesWithUnreadableDocumentsAreRejected() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-docs-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("""
    {"id":"dev.test.docs","name":"Docs","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[]}
    """.utf8).write(to: root.appendingPathComponent("notchnotch.json"))
    try Data("void 0;".utf8).write(to: root.appendingPathComponent("bundle.js"))
    let store = ExtensionStore(directory: root)
    try Data("# Docs".utf8).write(to: root.appendingPathComponent("README.md"))
    _ = try store.inspect(root)
    #expect(PackageDocument.readme.load(from: root) == "# Docs")
    try Data([0xFF, 0xFE, 0x00]).write(to: root.appendingPathComponent("CHANGELOG.md"))
    #expect(throws: ProtocolError.self) { try store.inspect(root) }
    try Data(repeating: 0x41, count: PackageDocument.maximumBytes + 1).write(to: root.appendingPathComponent("CHANGELOG.md"))
    #expect(throws: ProtocolError.self) { try store.inspect(root) }
}
