import Testing
import NotchProtocol
import NotchCore

@Test func settingsOnlyExtensionsNeverCreateANotchActivity() throws {
    let settings = UINode(id: "setup", type: .column, children: [
        .init(id: "connect", type: .button, props: .init(text: "Connect", action: "connect:action")),
    ])
    let snapshot = Snapshot(extensionID: "test.settings", revision: 1, surfaces: [], settings: settings)
    var platform = PlatformState()
    try platform.apply(snapshot, expectedExtensionID: "test.settings")
    #expect(platform.surfaces.isEmpty)
    #expect(platform.presentation == .idle)
    #expect(!platform.isExpanded)
}

@Test func settingsShareTheSnapshotBudgetAndRejectPlaybackNodes() throws {
    let playback = Snapshot(extensionID: "test.settings", revision: 1, surfaces: [],
        settings: .init(id: "wave", type: .waveform))
    #expect(throws: ProtocolError.self) { try playback.validate(expectedExtensionID: "test.settings") }
    let large = Snapshot(extensionID: "test.settings", revision: 1, surfaces: [], settings:
        .init(id: "setup", type: .column, children: (0..<512).map { .init(id: "node-\($0)", type: .text) }))
    #expect(throws: ProtocolError.self) { try large.validate(expectedExtensionID: "test.settings") }
    let shared = UINode(id: "shared", type: .column)
    let duplicate = Snapshot(extensionID: "test.settings", revision: 1,
        surfaces: [.init(id: "activity", kind: .activity, title: "Activity", initialView: .expanded, expanded: shared)], settings: shared)
    #expect(throws: ProtocolError.self) { try duplicate.validate(expectedExtensionID: "test.settings") }
}

@Test func settingsAcceptStructuredComponents() throws {
    let settings = UINode(id: "setup", type: .column, children: [
        .init(id: "access", type: .section, props: .init(text: "Access", detail: "Footer"), children: [
            .init(id: "item", type: .listItem, props: .init(text: "Work", name: "calendar", detail: "Subtitle"), children: [
                .init(id: "switch", type: .toggle, props: .init(value: 1, action: "switch:action")),
                .init(id: "count", type: .badge, props: .init(text: "3")),
            ]),
            .init(id: "line", type: .divider),
            .init(id: "row", type: .row, props: .init(spacing: .tight, align: .end), children: [.init(id: "gap", type: .spacer)]),
        ]),
    ])
    let snapshot = Snapshot(extensionID: "test.settings", revision: 1, surfaces: [], settings: settings)
    try snapshot.validate(expectedExtensionID: "test.settings")
}

@Test func compactRejectsTogglesAndLeafNodesRejectChildren() throws {
    let compactToggle = Snapshot(extensionID: "test.contract", revision: 1, surfaces: [
        .init(id: "a", kind: .activity, title: "A",
              compact: .init(leading: [.init(id: "t", type: .toggle, props: .init(action: "t:action"))], trailing: []),
              expanded: .init(id: "e", type: .column)),
    ])
    #expect(throws: ProtocolError.self) { try compactToggle.validate(expectedExtensionID: "test.contract") }
    let spacerWithChild = Snapshot(extensionID: "test.contract", revision: 1, surfaces: [], settings:
        .init(id: "root", type: .column, children: [.init(id: "s", type: .spacer, children: [.init(id: "x", type: .text)])]))
    #expect(throws: ProtocolError.self) { try spacerWithChild.validate(expectedExtensionID: "test.contract") }
}
