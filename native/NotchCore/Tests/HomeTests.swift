import Foundation
import Testing
import NotchProtocol
@testable import NotchCore

private func surface(_ id: String, phase: SurfacePhase = .active, tile: TileContent? = nil) -> Surface {
    .init(id: id, kind: .activity, title: id.capitalized, phase: phase, compact: .init(leading: [], trailing: []),
          expanded: .init(id: "\(id)-body", type: .column), tile: tile)
}
private func add(_ state: inout PlatformState, _ id: String, phase: SurfacePhase = .active, revision: Int = 1) throws {
    try state.apply(.init(extensionID: id, revision: revision, surfaces: [surface(id, phase: phase)]), expectedExtensionID: id)
}

@Test func tilesFillTheGridInOrder() {
    let placed = HomeLayout.place([.wide, .small, .small, .small], columns: 4)
    #expect(placed == [.init(row: 0, column: 0, span: 2), .init(row: 0, column: 2, span: 1),
                       .init(row: 0, column: 3, span: 1), .init(row: 1, column: 0, span: 1)])
}

@Test func aWideTileThatDoesntFitMovesDownAndASmallOneFillsTheGap() {
    let placed = HomeLayout.place([.small, .small, .small, .wide, .small], columns: 4)
    #expect(placed[3] == .init(row: 1, column: 0, span: 2))
    #expect(placed[4] == .init(row: 0, column: 3, span: 1))
}

@Test func homeGrowsToThreeRowsBeforeItWidens() {
    let twelve = HomeLayout.arrange(Array(repeating: .small, count: 12))
    #expect(twelve.columns == 4 && twelve.rows == 3 && twelve.hiddenCount == 0)
    let thirteen = HomeLayout.arrange(Array(repeating: .small, count: 13))
    #expect(thirteen.columns == 5 && thirteen.rows == 3)
    #expect(thirteen.width > twelve.width)
    #expect(HomeLayout.arrange([.small]).columns == HomeLayout.minimumColumns)
}

@Test func whenSixColumnsAreFullTheRestWaitBehindMore() {
    let arranged = HomeLayout.arrange([.wide, .wide] + Array(repeating: .small, count: 20))
    #expect(arranged.columns == 6 && arranged.rows == 3)
    // 18 cells: two wide tiles (4 cells), thirteen small ones, and the More tile.
    #expect(arranged.placements.count == 2 + 13 + 1)
    #expect(arranged.hiddenCount == 22 - 15)
}

@Test func theNewestLiveActivityTakesTheWingsAndTheNextThreeAreCircles() throws {
    var state = PlatformState()
    for id in ["a", "b", "c", "d", "e"] { try add(&state, id) }
    #expect(state.live.map(\.key.extensionID) == ["e", "d", "c", "b", "a"])
    #expect(state.compact?.key.extensionID == "e")
    #expect(state.minimals.map(\.key.extensionID) == ["d", "c", "b"])
    #expect(state.liveOverflow == 1)
}

@Test func pausingMovesAnActivityFromLiveToTheGlances() throws {
    var state = PlatformState()
    try add(&state, "music")
    try add(&state, "timer")
    #expect(state.minimals.map(\.key.extensionID) == ["music"])
    try add(&state, "music", phase: .paused, revision: 2)
    #expect(state.live.map(\.key.extensionID) == ["timer"])
    #expect(state.minimals.isEmpty)
    #expect(state.homeTiles.map(\.key.extensionID) == ["timer", "music"])
    #expect(state.tileSize(of: state.homeTiles[0]) == .wide)
    #expect(state.tileSize(of: state.homeTiles[1]) == .small)
}

@Test func anActivityChoosesItsTileSizeAndUnknownSizesFallBackToSmall() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "x", revision: 1, surfaces: [
        surface("wide", phase: .paused, tile: .init(size: .wide, content: [])),
        surface("future", phase: .paused, tile: .init(size: .unknown, content: [])),
    ]), expectedExtensionID: "x")
    #expect(state.homeTiles.map { state.tileSize(of: $0) } == [.wide, .small])
}

@Test func homeStaysOpenThroughSnapshotsAndOpeningATileLeavesIt() throws {
    var state = PlatformState()
    try add(&state, "timer", phase: .paused)
    state.openHome()
    #expect(state.isExpanded && state.showsHome && state.selected == nil)
    try add(&state, "timer", phase: .paused, revision: 2)
    #expect(state.isExpanded && state.showsHome)
    state.open(.init(extensionID: "timer", surfaceID: "timer"))
    #expect(!state.showsHome && state.selected?.key.extensionID == "timer")
    state.close()
    #expect(!state.isExpanded && !state.showsHome)
}

@Test func togglingWithNothingToResumeOpensHome() throws {
    var state = PlatformState()
    try state.apply(.init(extensionID: "x", revision: 1, surfaces: [{ var s = surface("glance", phase: .paused); s.idlePreview = false; return s }()]),
                    expectedExtensionID: "x")
    #expect(state.hoverSurface == nil)
    state.toggle()
    #expect(state.showsHome)
}

@Test func aTileCannotHoldButtons() {
    var tiled = surface("timer", tile: .init(content: [.init(id: "b", type: .button, props: .init(action: "go"))]))
    let snapshot = { Snapshot(extensionID: "timer", revision: 1, surfaces: [tiled]) }
    #expect(throws: ProtocolError.self) { try snapshot().validate(expectedExtensionID: "timer") }
    tiled.tile = .init(content: [.init(id: "v", type: .value, props: .init(text: "82"))])
    #expect(throws: Never.self) { try snapshot().validate(expectedExtensionID: "timer") }
}

@Test func arrowKeysMoveToTheNearestTileAndStopAtTheEdges() {
    // Row 0: wide 0, small 1, small 2. Row 1: small 3, small 4.
    let home = HomeLayout.arrange([.wide, .small, .small, .small, .small])
    #expect(home.neighbor(of: 0, .right) == 1)
    #expect(home.neighbor(of: 1, .left) == 0)
    #expect(home.neighbor(of: 2, .right) == nil)
    #expect(home.neighbor(of: 0, .down) == 3, "a tie goes to the left tile")
    #expect(home.neighbor(of: 2, .down) == 4)
    #expect(home.neighbor(of: 4, .up) == 0)
    #expect(home.neighbor(of: 3, .down) == nil)
    #expect(home.neighbor(of: 0, .up) == nil)
    #expect(home.neighbor(of: 99, .left) == 0, "the first key press lands on the first tile")
}

@Test func pinnedTilesComeFirstAndHiddenOnesLeaveHome() throws {
    var state = PlatformState()
    try add(&state, "a", phase: .paused)
    try add(&state, "b")
    try add(&state, "c", phase: .paused)
    #expect(state.homeTiles.map(\.key.extensionID) == ["b", "a", "c"])
    let c = SurfaceKey(extensionID: "c", surfaceID: "c"), b = SurfaceKey(extensionID: "b", surfaceID: "b")
    state.homePreferences.setPinned(true, c)
    #expect(state.homeTiles.map(\.key.extensionID) == ["c", "b", "a"], "pinned before live")
    state.homePreferences.setHidden(true, b)
    #expect(state.homeTiles.map(\.key.extensionID) == ["c", "a"])
    #expect(state.live.map(\.key.extensionID) == ["b"], "hiding leaves the wings alone")
    #expect(state.homeActivities.count == 3, "Settings still lists it")
    state.homePreferences.setHidden(true, c)
    #expect(!state.homePreferences.pinned.contains(c.id), "a hidden tile isn't pinned")
}

@Test func theUsersOrderSortsHomeAndDecidesTheWings() throws {
    var state = PlatformState()
    try add(&state, "a")
    try add(&state, "b")
    #expect(state.compact?.key.extensionID == "b", "the most recent takes the wings")
    let a = SurfaceKey(extensionID: "a", surfaceID: "a"), b = SurfaceKey(extensionID: "b", surfaceID: "b")
    state.homePreferences.reorder([a, b])
    #expect(state.compact?.key.extensionID == "a")
    #expect(state.homeTiles.map(\.key.extensionID) == ["a", "b"])
    try add(&state, "c")
    #expect(state.live.map(\.key.extensionID) == ["a", "b", "c"], "ones the user didn't order follow")
    state.homePreferences.reorder([b])
    #expect(state.homePreferences.order == ["b/b", "a/a"], "activities not running keep their place after")
}

@Test func theUsersSizeWinsOverTheActivitysAndAutomaticReturnsIt() throws {
    var state = PlatformState()
    try add(&state, "a")
    let a = SurfaceKey(extensionID: "a", surfaceID: "a")
    #expect(state.tileSize(of: state.homeTiles[0]) == .wide)
    state.homePreferences.setSize(.small, a)
    #expect(state.tileSize(of: state.homeTiles[0]) == .small)
    state.homePreferences.setSize(nil, a)
    #expect(state.tileSize(of: state.homeTiles[0]) == .wide)
    let data = try JSONEncoder().encode(state.homePreferences)
    #expect(try JSONDecoder().decode(HomePreferences.self, from: data) == state.homePreferences)
}
