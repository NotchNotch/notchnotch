import CoreGraphics

/// A menu bar item as Accessibility reports it: whose it is and where. Frames
/// are in screen coordinates with the origin at the top left, like the window list.
public struct MenuBarItem: Equatable, Sendable, Identifiable {
    /// Stable while the app runs: its bundle (or process) and the item's identifier or place.
    public var id: String
    public var pid: Int32
    public var appName: String
    public var bundleID: String?
    /// What VoiceOver says for it, when the app gives one ("Battery", "Now Playing").
    public var title: String?
    /// A system item's identifier, such as `com.apple.menuextra.battery`.
    public var identifier: String?
    public var frame: CGRect

    public init(id: String, pid: Int32, appName: String, bundleID: String? = nil, title: String? = nil,
                identifier: String? = nil, frame: CGRect) {
        self.id = id; self.pid = pid; self.appName = appName; self.bundleID = bundleID
        self.title = title; self.identifier = identifier; self.frame = frame
    }

    /// The name to show: the item's own title for system items, else its app's name.
    public var name: String {
        if let title, !title.isEmpty, identifier != nil { return title.components(separatedBy: ",").first ?? title }
        return appName
    }
}

/// A status item window from the window list: where it is, and whether macOS shows it.
public struct MenuBarWindow: Equatable, Sendable {
    /// The window server's number for it, to capture its image.
    public var id: UInt32
    public var frame: CGRect
    public var onScreen: Bool
    public init(id: UInt32 = 0, frame: CGRect, onScreen: Bool) { self.id = id; self.frame = frame; self.onScreen = onScreen }
}

/// Which menu bar items can't be seen or clicked: those macOS hid beside the
/// camera, and those under NotchNotch's own silhouette, wings included.
public enum MenuBarLayout {
    /// The header shows this many icons; past that, one fewer and `+N`.
    public static let headerCapacity = 5

    /// Hidden items, left to right. `covered` is the closed notch's band on the
    /// menu bar (camera and wings), as x from its left to its right edge;
    /// `screen` is the menu bar's own: NotchNotch's divider pushes items past its left end.
    public static func hidden(_ items: [MenuBarItem], windows: [MenuBarWindow], covered: ClosedRange<CGFloat>,
                              screen: ClosedRange<CGFloat> = -.greatestFiniteMagnitude...(.greatestFiniteMagnitude)) -> [MenuBarItem] {
        items
            .filter { $0.frame.width > 0 && $0.frame.height > 0 }
            .filter { item in
                if item.frame.maxX <= screen.lowerBound || item.frame.minX >= screen.upperBound { return true }
                if window(of: item, in: windows)?.onScreen == false { return true }
                return item.frame.maxX > covered.lowerBound && item.frame.minX < covered.upperBound
            }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// An item's window. Accessibility gives the icon, the window adds padding: match by the icon's
    /// center, and the narrowest such window, never NotchNotch's 10 000 pt divider around it.
    public static func window(of item: MenuBarItem, in windows: [MenuBarWindow]) -> MenuBarWindow? {
        windows.filter { $0.frame.minX <= item.frame.midX && item.frame.midX <= $0.frame.maxX }
            .min { $0.frame.width < $1.frame.width }
    }

    /// Whether a divider ending at `dividerMaxX` leaves nothing the notch
    /// covers to its right: every item in `covered` then sits left of it, and
    /// hides with it. Items right of the divider never move when it widens.
    public static func dividerClears(_ dividerMaxX: CGFloat, windows: [MenuBarWindow], covered: ClosedRange<CGFloat>) -> Bool {
        !windows.contains { window in
            window.frame.minX >= dividerMaxX - 1
                && window.frame.maxX > covered.lowerBound && window.frame.minX < covered.upperBound
        }
    }

    /// The largest key for which `clears` holds, by bisection: macOS orders
    /// status items by `NSStatusItem Preferred Position`, a larger key further
    /// left, so `clears` holds for every key up to some point and none after.
    public static func dividerKey(upTo limit: Int = 4096, isolation: isolated (any Actor)? = #isolation,
                                  clears: (Int) async -> Bool) async -> Int {
        var low = 0, high = limit, best = 0
        while low <= high {
            let key = (low + high) / 2
            if await clears(key) { best = key; low = key + 1 } else { high = key - 1 }
        }
        return best
    }

    /// How many icons the header shows, and how many wait behind `+N`.
    public static func header(count: Int) -> (shown: Int, more: Int) {
        count <= headerCapacity ? (count, 0) : (headerCapacity - 1, count - headerCapacity + 1)
    }
}

/// What a captured menu bar image holds, from its pixels.
public enum MenuBarImageTone {
    /// Whether every visible pixel is a shade of grey: macOS draws template icons
    /// in the menu bar's ink, dark on a light menu bar, so the notch redraws those
    /// in its own white and keeps colored ones as they are. `rgba` is 8-bit RGBA.
    public static func isMonochrome(rgba: [UInt8], tolerance: Int = 24) -> Bool {
        stride(from: 0, to: rgba.count - 3, by: 4).allSatisfy { i in
            guard rgba[i + 3] > 24 else { return true }
            let r = Int(rgba[i]), g = Int(rgba[i + 1]), b = Int(rgba[i + 2])
            return max(r, g, b) - min(r, g, b) <= tolerance
        }
    }

    /// The smallest box around the visible pixels, in pixels from the top left;
    /// nil when nothing is visible. The item's window pads its image.
    public static func visibleBounds(rgba: [UInt8], width: Int, height: Int) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where rgba[(y * width + x) * 4 + 3] > 24 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
