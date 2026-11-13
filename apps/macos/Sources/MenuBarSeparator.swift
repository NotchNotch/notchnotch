import AppKit
import NotchCore

/// NotchNotch's divider in the menu bar, as Bartender and Ice have, without
/// a slot of its own. While hidden it's 10 000 pt wide and pushes every item
/// left of it off the menu bar; those come back in the notch. Which items those
/// are is the person's: holding ⌘ with the pointer in the menu bar shows them
/// and the divider, as macOS needs ⌘ held to drag an item anyway, and dragging
/// one across the divider moves it in or out.
///
/// An item off the menu bar opens its menu off the screen too, so pressing one
/// shows the hidden items first, and hides them once its menu closes.
@MainActor final class MenuBarSeparator {
    private static let dividerName = "NotchNotchDivider"
    private static let hiddenLength: CGFloat = 10_000, shownLength: CGFloat = 14

    /// Why the items are shown, which decides when they hide again.
    private enum Reason { case press, command, rearrange }

    private var divider: NSStatusItem?
    private var monitors: [Any] = []
    private var placeTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var reason = Reason.press
    private(set) var isShown = false
    /// Once the hidden items are back on the menu bar and have settled: the only
    /// time their images can be captured, as ScreenCaptureKit can't see them off the screen.
    var onRevealed: (() -> Void)?
    private var revealTask: Task<Void, Never>?

    /// `covered` is the notch's band on its screen's menu bar: the first time,
    /// the divider goes right after the last item in it, so only those hide.
    init(covered: @escaping () -> (screen: NSScreen, band: ClosedRange<CGFloat>)?) {
        let defaults = UserDefaults.standard
        // From before the divider showed itself on ⌘: a chevron, no longer made.
        defaults.removeObject(forKey: Self.key("NotchNotchChevron"))
        // Global for other apps, local for when NotchNotch is the front app. Needs Accessibility, which this has.
        let flags: (NSEvent) -> Void = { [weak self] event in self?.flagsChanged(event.modifierFlags) }
        monitors = [NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags),
                    NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 }].compactMap { $0 }
        placeTask = Task { [weak self] in
            guard let self else { return }
            if defaults.object(forKey: Self.key(Self.dividerName)) == nil, let covered = covered() {
                let key = await MenuBarLayout.dividerKey(upTo: Int(covered.screen.frame.width)) { key in await Self.dividerClears(at: key, covered) }
                guard !Task.isCancelled else { return }
                defaults.set(key, forKey: Self.key(Self.dividerName))
            }
            self.divider = Self.makeDivider()
            // macOS places an item by its key at a narrow width; it widens after.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.update()
        }
    }

    private static func makeDivider() -> NSStatusItem {
        let divider = NSStatusBar.system.statusItem(withLength: shownLength)
        divider.autosaveName = dividerName
        divider.button?.setAccessibilityLabel("Hidden menu bar items begin here")
        return divider
    }

    /// Tries the divider at `key`: where macOS puts it, and whether that's right of all `covered` holds.
    /// Items slide into place and a removed one fades: it reads only a menu bar that's stopped moving.
    private static func dividerClears(at key: Int, _ covered: (screen: NSScreen, band: ClosedRange<CGFloat>)) async -> Bool {
        UserDefaults.standard.set(key, forKey: Self.key(dividerName))
        let divider = makeDivider()
        defer { NSStatusBar.system.removeStatusItem(divider) }
        var last: [CGRect] = []
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(120))
            guard let ours = divider.button?.window?.frame else { return false }
            let others = MenuBarScanner.windows(on: covered.screen).map(\.frame).filter { abs($0.minX - ours.minX) > 1 }
            let now = [ours] + others.sorted { $0.minX < $1.minX }
            if now == last {
                try? await Task.sleep(for: .milliseconds(300))  // for this one to fade before the next try
                return MenuBarLayout.dividerClears(ours.maxX, windows: others.map { MenuBarWindow(frame: $0, onScreen: true) },
                                                   covered: covered.band)
            }
            last = now
        }
        return false
    }

    private static func key(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }

    func remove() {
        hideTask?.cancel()
        placeTask?.cancel()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
    }

    /// For a press: shows the hidden items until its menu closes.
    func show() { show(.press, grace: .milliseconds(600)) }

    /// Shows the hidden items for a moment, to capture their images.
    func peek() { show(.press, grace: .milliseconds(500)) }

    /// Shows the hidden items and the divider for a while, to drag them across with ⌘.
    func rearrange() { show(.rearrange, grace: .seconds(6)) }

    private func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard flags.intersection(.deviceIndependentFlagsMask) == .command, !isShown, Self.pointerInMenuBar else { return }
        show(.command, grace: .zero)
    }

    /// They hide again once nothing holds them: no menu open, no drag, and ⌘
    /// let go or, for a press or rearranging, the pointer gone from the menu bar.
    private func show(_ reason: Reason, grace: Duration) {
        self.reason = reason
        let wasShown = isShown
        isShown = true
        update()
        if !wasShown, divider != nil {
            revealTask?.cancel()
            revealTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled, self.isShown else { return }
                self.onRevealed?()
            }
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: grace)
            var idle = 0
            while !Task.isCancelled, idle < 2, let self {
                idle = self.isHeld ? 0 : idle + 1
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private var isHeld: Bool {
        let pointer = Self.pointerInMenuBar
        let command = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        return Self.menuOpen || NSEvent.pressedMouseButtons != 0 || (command && pointer) || (reason != .command && pointer)
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        revealTask?.cancel()
        isShown = false
        update()
    }

    private func update() {
        divider?.length = isShown ? Self.shownLength : Self.hiddenLength
        divider?.button?.image = isShown ? Self.bar : nil
        divider?.button?.imagePosition = .imageOnly
    }

    /// The divider while shown: a thin upright bar, in the menu bar's ink.
    private static let bar: NSImage = {
        let image = NSImage(size: NSSize(width: 4, height: 16), flipped: false) { rect in
            NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 2, height: rect.height - 2), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// Any app's menu on the screen, the one a press opened included.
    private static var menuOpen: Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let level = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.contains { $0[kCGWindowLayer as String] as? Int == level }
    }

    private static var pointerInMenuBar: Bool {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            screen.frame.contains(pointer) && pointer.y >= screen.frame.maxY - NSStatusBar.system.thickness - 8
        }
    }
}
