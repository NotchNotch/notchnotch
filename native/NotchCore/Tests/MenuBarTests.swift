import CoreGraphics
import Testing
import NotchCore

// From the spike: a 14" MacBook Pro, camera from 663 to 848.
private func item(_ name: String, x: CGFloat, width: CGFloat, identifier: String? = nil) -> MenuBarItem {
    MenuBarItem(id: name, pid: 1, appName: name, title: identifier == nil ? nil : "\(name), on", identifier: identifier,
                frame: CGRect(x: x, y: 0, width: width, height: 24))
}
private let claude = item("Claude", x: 808, width: 42)
private let yojam = item("Yojam", x: 856, width: 24)
private let throne = item("Throne", x: 926, width: 24)
private let clock = item("Clock", x: 1376, width: 130, identifier: "com.apple.menuextra.clock")
private let windows = [
    MenuBarWindow(frame: CGRect(x: 809, y: 0, width: 40, height: 24), onScreen: false),
    MenuBarWindow(frame: CGRect(x: 849, y: 0, width: 38, height: 24), onScreen: false),
    MenuBarWindow(frame: CGRect(x: 919, y: 0, width: 38, height: 24), onScreen: true),
    MenuBarWindow(frame: CGRect(x: 1368, y: 0, width: 146, height: 24), onScreen: true),
]

@Test func macOSHidesWhatTheCameraCoversAndItsMargin() {
    // No wings: only what macOS marked off-screen, matched by the icon's center.
    let hidden = MenuBarLayout.hidden([clock, throne, yojam, claude], windows: windows, covered: 663...848)
    #expect(hidden.map(\.id) == ["Claude", "Yojam"])
}

@Test func theWingsHideMoreThanTheCamera() {
    // 96 pt wings on each side of a 185 pt camera.
    let hidden = MenuBarLayout.hidden([clock, throne, yojam, claude], windows: windows, covered: 567...944)
    #expect(hidden.map(\.id) == ["Claude", "Yojam", "Throne"])
}

@Test func turnedOffSystemItemsHaveNoSizeAndAreSkipped() {
    let off = item("Focus", x: 0, width: 0, identifier: "com.apple.menuextra.focusmode")
    #expect(MenuBarLayout.hidden([off], windows: windows, covered: 0...2000).isEmpty)
}

@Test func theHeaderShowsFiveOrFourAndMore() {
    #expect(MenuBarLayout.header(count: 0) == (0, 0))
    #expect(MenuBarLayout.header(count: 5) == (5, 0))
    #expect(MenuBarLayout.header(count: 6) == (4, 2))
    #expect(MenuBarLayout.header(count: 12) == (4, 8))
}

@Test func systemItemsAreNamedByTheirTitle() {
    #expect(clock.name == "Clock")
    #expect(claude.name == "Claude")
}

@Test func theDividerClearsWhenEverythingCoveredIsLeftOfIt() {
    // 96 pt wings reach 944 and cut Throne's window (919…957).
    #expect(!MenuBarLayout.dividerClears(919, windows: windows, covered: 567...944))
    #expect(MenuBarLayout.dividerClears(957, windows: windows, covered: 567...944))
}

@Test func theDividerKeyIsTheLargestThatClears() async {
    // Keys up to 554 put the divider right of what's covered.
    #expect(await MenuBarLayout.dividerKey { $0 <= 554 } == 554)
    #expect(await MenuBarLayout.dividerKey { _ in false } == 0)
}

@Test func greyIconsAreTemplatesAndColoredOnesAreNot() {
    let grey: [UInt8] = [30, 30, 32, 255, 0, 0, 0, 0]
    let red: [UInt8] = [220, 40, 40, 255, 30, 30, 30, 255]
    #expect(MenuBarImageTone.isMonochrome(rgba: grey))
    #expect(!MenuBarImageTone.isMonochrome(rgba: red))
}

@Test func theVisibleBoundsSkipTheWindowsPadding() {
    // 3×2, one visible pixel at (1, 1).
    var rgba = [UInt8](repeating: 0, count: 3 * 2 * 4)
    rgba[(1 * 3 + 1) * 4 + 3] = 255
    #expect(MenuBarImageTone.visibleBounds(rgba: rgba, width: 3, height: 2) == CGRect(x: 1, y: 1, width: 1, height: 1))
    #expect(MenuBarImageTone.visibleBounds(rgba: [UInt8](repeating: 0, count: 8), width: 2, height: 1) == nil)
}
