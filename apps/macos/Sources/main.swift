import AppKit
import SwiftUI
import NotchCore
import NotchExtensions

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let model = AppModel()
    private let updater = AppUpdater()
    private var panel: NotchPanel?
    private var statusItem: NSStatusItem?
    private var eventMonitors: [Any] = []
    private var pointerTimer: Timer?
    private var pagingGesture = ActivityPagingGesture()
    private var managementController: ManagementWindowController?
    private var welcomeController: WelcomeWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Packages unpacked for a review that never finished (the app quit mid-review).
        // This runs before a double-clicked .notchext is delivered, never after.
        try? FileManager.default.removeItem(at: ExtensionStore.stagingDirectory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "NotchNotch"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: NotchView(model: model) { [weak panel] in panel?.makeKey() })
        self.panel = panel
        model.onLayoutChange = { [weak self] in self?.layoutPanel() }
        model.onOpenManagement = { [weak self] in
            guard let self else { return }
            self.openManagement(extensionID: self.model.displayedSurface?.key.extensionID)
        }
        model.onOpenHomeSettings = { [weak self] in self?.openManagement(destination: .notch) }
        model.onRevealActivity = { [weak self] key in
            self?.model.open(key)
            self?.panel?.makeKey()
            self?.panel?.orderFrontRegardless()
        }
        makeMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIfOutsidePanel() }
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPointerRouting() }
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .leftMouseDragged, .scrollWheel], handler: { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.type == .scrollWheel { return self.handlePaging(event) }
                if event.type == .keyDown, event.keyCode == 53, event.window === self.panel { self.model.close(); return true }
                if event.type == .keyDown, event.window === self.panel, let key = Self.homeKey(event.keyCode) {
                    return self.model.handleHomeKey(key)
                }
                // A right click opens a menu; the notch must not close under it when the pointer moves onto it.
                if [.leftMouseDown, .rightMouseDown].contains(event.type), event.window === self.panel,
                   self.model.hoverExpanded {
                    self.model.pinOpen()
                }
                if event.type == .leftMouseDown, event.window !== self.panel { self.closeIfOutsidePanel() }
                if event.type == .mouseMoved || event.type == .leftMouseDragged { self.refreshPointerRouting() }
                return false
            }
            return handled ? nil : event
        }) { eventMonitors.append(monitor) }
        layoutPanel()
        refreshPointerRouting()
        panel.orderFrontRegardless()
        model.start()
        schedulePointerSampling(interval: Self.fastSampling)
        let firstLaunch = WelcomeWindowController.shouldShow
        model.greet(firstLaunch ? "Hi! NotchNotch lives here" : "NotchNotch is running", for: firstLaunch ? 6 : 3)
        if firstLaunch {
            let welcome = WelcomeWindowController(model: model) { [weak self] id in self?.openManagement(extensionID: id) }
            welcomeController = welcome
            welcome.reveal()
        }
    }

    // Pointer warps, screen/Space switches, and some input devices do not emit
    // mouseMoved. Sampling also keeps hit routing correct while the shell morphs.
    // It runs fast only near the notch or while it is open; elsewhere the global
    // mouse monitor covers ordinary movement and a slow sample catches warps.
    private static let fastSampling: TimeInterval = 0.1
    private static let slowSampling: TimeInterval = 0.75

    private func schedulePointerSampling(interval: TimeInterval) {
        guard pointerTimer?.timeInterval != interval else { return }
        pointerTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPointerRouting() }
        }
        timer.tolerance = interval * 0.3
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func pointerIsNearNotch() -> Bool {
        guard let panel else { return false }
        let mouse = NSEvent.mouseLocation
        return panel.frame.insetBy(dx: -120, dy: -80).contains(mouse)
    }

    private func handlePaging(_ event: NSEvent) -> Bool {
        guard event.window === panel, model.isExpanded, model.platform.surfaces.count > 1,
              pointerIsInsideSilhouette(), event.hasPreciseScrollingDeltas else {
            pagingGesture.reset()
            return false
        }
        let phase: ActivityPagingGesture.Phase
        if !event.momentumPhase.isEmpty { phase = .momentum }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.changed) { phase = .changed }
        else { return false }
        // Paging follows the fingers, even when Natural Scrolling is disabled.
        // AppKit's non-inverted deltas describe scrollbar travel instead.
        let fingerDirection: Double = event.isDirectionInvertedFromDevice ? 1 : -1
        let result = pagingGesture.update(deltaX: Double(event.scrollingDeltaX) * fingerDirection,
                                          deltaY: Double(event.scrollingDeltaY) * fingerDirection, phase: phase)
        if let direction = result.direction {
            panel?.makeKey()
            model.switchActivity(direction)
        }
        return result.handled
    }

    /// Arrows, Return and Enter, which move around Home and open a tile.
    private static func homeKey(_ code: UInt16) -> HomeKey? {
        switch code {
        case 123: .move(.left)
        case 124: .move(.right)
        case 125: .move(.down)
        case 126: .move(.up)
        case 36, 76: .activate
        default: nil
        }
    }

    /// Template image of the NotchNotch logo (assets/logo.svg), 15 pt square.
    private static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 15, height: 15), flipped: true) { rect in
            let scale = rect.width / 100
            let logo = NSBezierPath()
            for shape in [[(0, 0), (0, 100), (50, 100), (50, 50)], [(50, 0), (50, 50), (100, 100), (100, 0)]] {
                logo.move(to: NSPoint(x: CGFloat(shape[0].0) * scale, y: CGFloat(shape[0].1) * scale))
                for point in shape.dropFirst() { logo.line(to: NSPoint(x: CGFloat(point.0) * scale, y: CGFloat(point.1) * scale)) }
                logo.close()
            }
            NSColor.black.setFill(); logo.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "NotchNotch"
        return image
    }

    private func makeMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarImage()
        let menu = NSMenu()
        menu.addItem(withTitle: "NotchNotch · Developer Preview", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for (title, action, key) in [
            ("Settings & Extensions…", #selector(showManagement), ","),
            ("Check for Updates…", #selector(checkForUpdates), ""),
            ("Show activities", #selector(showActivities), ""),
            ("Show pending question", #selector(showPrompt), ""),
            ("Preview announcement", #selector(previewAnnouncement), ""),
            ("Restart extensions", #selector(restart), "r"),
            ("Disconnect extension connections", #selector(disconnectExtensions), ""),
            ("Quit NotchNotch", #selector(quit), "q"),
        ] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            entry.target = self
        }
        item.menu = menu
        statusItem = item
        // Keep commands reachable to keyboard users and accessibility clients even
        // when the notch itself is fully hidden behind the physical camera.
        let mainMenu = NSMenu()
        let appMenu = NSMenuItem(title: "NotchNotch", action: nil, keyEquivalent: "")
        appMenu.submenu = menu.copy() as? NSMenu
        mainMenu.addItem(appMenu)
        NSApp.mainMenu = mainMenu
    }

    private static func displayID(_ screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }

    /// The user's chosen display when connected; otherwise the notched display, else the main one.
    private func targetScreen() -> NSScreen? {
        let displays = NSScreen.screens.compactMap { screen in
            Self.displayID(screen).map { AppModel.Display(id: $0, name: screen.localizedName, hasNotch: screen.safeAreaInsets.top > 0) }
        }
        if model.displays != displays { model.displays = displays }
        if let preferred = model.preferredDisplayID,
           let screen = NSScreen.screens.first(where: { Self.displayID($0) == preferred }) { return screen }
        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private func layoutPanel() {
        guard let panel, let screen = targetScreen() else { return }
        model.hasNotch = screen.safeAreaInsets.top > 0
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notchWidth = max(100, right.minX - left.maxX)
        } else { model.notchWidth = 54 }
        model.topHeight = model.hasNotch ? max(32, screen.safeAreaInsets.top) : 38
        let canvas = model.geometry.canvasSize
        let frame = NSRect(x: screen.frame.midX - canvas.width / 2,
                           y: screen.frame.maxY - (model.hasNotch ? 0 : 6) - canvas.height,
                           width: canvas.width, height: canvas.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        refreshPointerRouting()
    }

    private func pointerIsInsideSilhouette() -> Bool {
        guard let panel else { return false }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        let geometry = model.geometry
        let size = geometry.bodySize(presentation: model.presentation)
        let shape = NotchSilhouette(bodyWidth: size.width, bodyHeight: size.height,
                                    shoulder: geometry.shoulderRadius(presentation: model.presentation),
                                    bottomRadius: geometry.bottomRadius(presentation: model.presentation), attached: geometry.attached)
        return shape.path(in: CGRect(origin: .zero, size: geometry.canvasSize)).contains(point)
    }

    private func refreshPointerRouting() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        let inside = model.geometry.activationFrame(presentation: model.presentation).contains(point)
        // The fixed animation canvas must never intercept clicks on transparent desktop space.
        panel.ignoresMouseEvents = !pointerIsInsideSilhouette() || model.presentation == .idle
        if !model.isExpanded, panel.isKeyWindow { panel.resignKey() }
        model.pointerChanged(inside: inside)
        // Compact wings stay put; only morphing or open states need fast sampling.
        let animating = [.hovered, .peek, .expanded].contains(model.presentation)
        schedulePointerSampling(interval: animating || pointerIsNearNotch() ? Self.fastSampling : Self.slowSampling)
    }

    private func closeIfOutsidePanel() {
        guard !pointerIsInsideSilhouette() else { return }
        model.close()
    }

    @objc private func screenChanged() { layoutPanel() }
    @objc private func showManagement() { openManagement() }
    private func openManagement(extensionID: String? = nil, destination: ManagementDestination? = nil) {
        model.close()
        if managementController == nil { managementController = ManagementWindowController(model: model, updater: updater) }
        managementController?.reveal(extensionID: extensionID, destination: destination)
    }
    /// Double-clicking a `.notchext` (or dropping it on the app) opens its install review;
    /// a `notchnotch://` link from the website opens its Store page.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let link = urls.lazy.compactMap(StoreLink.init).first {
            openManagement()
            managementController?.coordinator.open(link)
            return
        }
        guard let url = urls.first(where: { $0.isFileURL && $0.pathExtension.lowercased() == ExtensionArchive.fileExtension }) else { return }
        openManagement()
        managementController?.coordinator.openPackage(url)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManagement()
        return false
    }
    @objc private func showActivities() { model.openFirst(); panel?.makeKey(); panel?.orderFrontRegardless() }
    @objc private func showPrompt() { model.openPrompt(); panel?.makeKey(); panel?.orderFrontRegardless() }
    @objc private func previewAnnouncement() { model.previewAnnouncement(); panel?.orderFrontRegardless() }
    @objc private func restart() { model.reloadExtensions(force: true) }
    @objc private func disconnectExtensions() { model.disconnectExtensions() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { updater.checkForUpdates() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) {
            if !updater.isAvailable { menuItem.toolTip = "Development builds don’t check for updates." }
            return updater.canCheckForUpdates
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        pointerTimer?.invalidate()
        model.stop()
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        NotificationCenter.default.removeObserver(self)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
