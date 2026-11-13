import Foundation
import Testing
import UniformTypeIdentifiers
import NotchProtocol
@testable import NotchCore

private func zones(_ id: String, _ zones: [DropZone]) throws -> Snapshot {
    var snapshot = Snapshot(extensionID: id, revision: 1, surfaces: [])
    snapshot.drops = zones
    return snapshot
}
private func zone(_ id: String, _ accepts: [UTType], multiple: Bool = true) -> DropZone {
    .init(id: id, title: id.capitalized, accepts: accepts.map(\.identifier), multiple: multiple, action: "\(id):drop")
}
private let pdf = DraggedItem(kind: .file, type: .pdf), photo = DraggedItem(kind: .file, type: .jpeg)
private let folder = DraggedItem(kind: .folder, type: .folder), link = DraggedItem(kind: .url, type: .url)

@Test func onlyZonesThatTakeEveryDraggedItemShow() throws {
    var state = PlatformState()
    try state.apply(zones("shelf", [zone("keep", [.item])]), expectedExtensionID: "shelf")
    try state.apply(zones("photos", [zone("print", [.image]), zone("one", [.item], multiple: false)]), expectedExtensionID: "photos")
    #expect(state.dropTargets(for: [photo]).map(\.zone.id) == ["print", "one", "keep"])
    #expect(state.dropTargets(for: [photo, pdf]).map(\.zone.id) == ["keep"], "a PDF isn't an image; two items skip a single-item zone")
    #expect(state.dropTargets(for: [folder, link]).map(\.zone.id) == ["keep"], "anything takes folders and links too")
    #expect(state.dropTargets(for: []).isEmpty)
}

@Test func zonesFollowTheHomeOrderAndLeaveWithTheirExtension() throws {
    var state = PlatformState()
    try state.apply(zones("a", [zone("a", [.item])]), expectedExtensionID: "a")
    try state.apply(zones("b", [zone("b", [.item])]), expectedExtensionID: "b")
    #expect(state.dropTargets(for: [pdf]).map(\.extensionID) == ["a", "b"])
    state.homePreferences.reorder([.init(extensionID: "b", surfaceID: "x")])
    #expect(state.dropTargets(for: [pdf]).map(\.extensionID) == ["b", "a"])
    state.removeExtension("b")
    #expect(state.dropTargets(for: [pdf]).map(\.extensionID) == ["a"])
    try state.apply(.init(extensionID: "a", revision: 2, surfaces: []), expectedExtensionID: "a")
    #expect(state.dropTargets(for: [pdf]).isEmpty, "a snapshot without zones takes them away")
}

@Test func moreThanFourZonesShowThreeAndMore() {
    let targets = (1...6).map { DropTarget(extensionID: "e\($0)", zone: zone("z\($0)", [.item])) }
    #expect(DropArrangement(Array(targets.prefix(4))).showsMore == false)
    let many = DropArrangement(targets)
    #expect(many.shown.count == 3 && many.hidden.count == 3 && many.showsMore)
}
