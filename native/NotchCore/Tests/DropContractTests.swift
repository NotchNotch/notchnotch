import Foundation
import Testing
import NotchProtocol

private let file = DroppedFile(id: "h1", name: "Invoice.pdf", type: "com.adobe.pdf", size: 220_000, kind: .file)
private func snapshot(drops: [DropZone]? = nil, nodes: [UINode] = []) -> Snapshot {
    var value = Snapshot(extensionID: "shelf", revision: 1, surfaces: [
        .init(id: "s", kind: .activity, title: "Shelf", initialView: .expanded, phase: .paused,
              expanded: .init(id: "body", type: .column, children: nodes)),
    ])
    value.drops = drops
    return value
}
private func zone(_ id: String, title: String = "Shelf", accepts: [String] = ["public.item"]) -> DropZone {
    .init(id: id, title: title, accepts: accepts, action: "\(id):drop")
}

@Test func anExtensionHasAtMostTwoDropZonesWithTitlesAndTypes() throws {
    try snapshot(drops: [zone("a"), zone("b")]).validate(expectedExtensionID: "shelf")
    #expect(throws: ProtocolError.self) { try snapshot(drops: [zone("a"), zone("b"), zone("c")]).validate(expectedExtensionID: "shelf") }
    #expect(throws: ProtocolError.self) { try snapshot(drops: [zone("a"), zone("a")]).validate(expectedExtensionID: "shelf") }
    #expect(throws: ProtocolError.self) { try snapshot(drops: [zone("a", title: "")]).validate(expectedExtensionID: "shelf") }
    #expect(throws: ProtocolError.self) { try snapshot(drops: [zone("a", accepts: [])]).validate(expectedExtensionID: "shelf") }
}

@Test func aFileItemShowsAFileAndNothingElseDoes() throws {
    try snapshot(nodes: [.init(id: "f", type: .fileItem, props: .init(file: .init(file)))]).validate(expectedExtensionID: "shelf")
    #expect(throws: ProtocolError.self) {
        try snapshot(nodes: [.init(id: "f", type: .fileItem)]).validate(expectedExtensionID: "shelf")
    }
    #expect(throws: ProtocolError.self) {
        try snapshot(nodes: [.init(id: "t", type: .text, props: .init(file: .init(file)))]).validate(expectedExtensionID: "shelf")
    }
}

@Test func filesRequestsNameTheirFilesAndReadInParts() throws {
    func command(_ files: FilesRequest) -> ConnectionCommand {
        .init(extensionID: "shelf", requestID: "r", connectionID: "", operation: .files, files: files)
    }
    try command(.init(action: .airDrop, ids: ["h1", "h2"])).validate(expectedExtensionID: "shelf")
    try command(.init(action: .read, ids: ["h1"], as: .text, limit: FilesRequest.maximumReadBytes, offset: 0)).validate(expectedExtensionID: "shelf")
    #expect(throws: ProtocolError.self) { try command(.init(action: .reveal, ids: [])).validate(expectedExtensionID: "shelf") }
    #expect(throws: ProtocolError.self) { try command(.init(action: .read, ids: ["h1", "h2"])).validate(expectedExtensionID: "shelf") }
    #expect(throws: ProtocolError.self) {
        try command(.init(action: .read, ids: ["h1"], limit: FilesRequest.maximumReadBytes + 1)).validate(expectedExtensionID: "shelf")
    }
    #expect(throws: ProtocolError.self) { try command(.init(action: .save, name: "../x", data: "AA==")).validate(expectedExtensionID: "shelf") }
    #expect(throws: ProtocolError.self) {
        try ConnectionCommand(extensionID: "shelf", requestID: "r", connectionID: "", operation: .files).validate(expectedExtensionID: "shelf")
    }
    #expect(command(.init(action: .save, name: "a.txt", data: "AA==")).files?.readsContents == true)
    #expect(command(.init(action: .open, ids: ["h1"])).files?.readsContents == false)
}

@Test func aFileGridFitsExpandedContentAndTilesButNotTheWings() throws {
    let grid = UINode(id: "g", type: .fileGrid, props: .init(files: FileList([file])))
    try snapshot(nodes: [grid]).validate(expectedExtensionID: "shelf")
    var tiled = snapshot()
    tiled.surfaces[0].compact = .init(leading: [], trailing: [])
    tiled.surfaces[0].tile = .init(content: [grid])
    try tiled.validate(expectedExtensionID: "shelf")
    var winged = snapshot()
    winged.surfaces[0].compact = .init(leading: [grid], trailing: [])
    #expect(throws: ProtocolError.self) { try winged.validate(expectedExtensionID: "shelf") }
}

@Test func aFileGridSelectsAndAListItemDragsText() throws {
    let grid = UINode(id: "g", type: .fileGrid, props: .init(files: .init([file]), selected: ["h1"], removable: true))
    let link = UINode(id: "l", type: .listItem, props: .init(text: "Example", drag: "https://example.com"))
    try snapshot(nodes: [grid, link]).validate(expectedExtensionID: "shelf")
    #expect(throws: ProtocolError.self) {
        try snapshot(nodes: [.init(id: "t", type: .text, props: .init(selected: ["h1"]))]).validate(expectedExtensionID: "shelf")
    }
    #expect(throws: ProtocolError.self) {
        try snapshot(nodes: [.init(id: "t", type: .text, props: .init(drag: "hi"))]).validate(expectedExtensionID: "shelf")
    }
    #expect(throws: ProtocolError.self) {
        try snapshot(nodes: [.init(id: "l", type: .listItem, props: .init(text: "x", drag: ""))]).validate(expectedExtensionID: "shelf")
    }
}

@Test func theClipboardTakesFilesOrText() throws {
    try FilesRequest(action: .clipboard, ids: ["h1"]).validate()
    try FilesRequest(action: .clipboard, text: "Hello").validate()
    #expect(throws: ProtocolError.self) { try FilesRequest(action: .clipboard).validate() }
    #expect(throws: ProtocolError.self) { try FilesRequest(action: .clipboard, ids: ["h1"], text: "Hello").validate() }
    #expect(throws: ProtocolError.self) { try FilesRequest(action: .clipboard, text: String(repeating: "a", count: 65_537)).validate() }
}
