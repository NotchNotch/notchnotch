import AppKit
import ApplicationServices
import NotchCore

/// Finds every app's menu bar items through Accessibility and presses them.
///
/// Asking an app over Accessibility can take as long as its timeout, and a
/// full scan of a Mac's apps takes seconds, so all of it runs on one serial
/// queue, never the main thread. Each app is asked once, when the scanner
/// starts or the app launches; after that only the apps that have items are
/// asked again, for their items' current places, when the notch wants them.
final class MenuBarScanner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.notchnotch.menubar", qos: .userInitiated)
    /// Confined to `queue`. Per process: its items and their elements, to press them later.
    private var apps: [pid_t: [(item: MenuBarItem, element: AXUIElement)]] = [:]
    private var observers: [NSObjectProtocol] = []
    /// New items, on the main thread.
    private let onChange: @MainActor ([MenuBarItem]) -> Void

    init(onChange: @escaping @MainActor ([MenuBarItem]) -> Void) {
        self.onChange = onChange
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS for Accessibility, which shows its prompt the first time.
    static func requestTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @MainActor func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                // Apps add their items a moment after they launch.
                self?.scan([app.processIdentifier], after: 2)
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.forget(app.processIdentifier)
            },
        ]
        scan(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
    }

    @MainActor func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        queue.async { self.apps = [:] }
    }

    /// Asks only the apps that have items where they are now; cheap, for when the notch opens.
    func refresh() {
        queue.async {
            for pid in self.apps.keys { self.apps[pid] = Self.items(of: pid) }
            self.publish()
        }
    }

    /// Presses the item, as a click on it would: its menu opens where it is.
    func press(_ id: String) {
        queue.async {
            guard let element = self.apps.values.lazy.flatMap({ $0 }).first(where: { $0.item.id == id })?.element else { return }
            AXUIElementPerformAction(element, kAXPressAction as CFString)
        }
    }

    private func scan(_ pids: [pid_t], after delay: TimeInterval = 0) {
        queue.asyncAfter(deadline: .now() + delay) {
            for pid in pids where pid != getpid() {
                let found = Self.items(of: pid)
                self.apps[pid] = found.isEmpty ? nil : found
            }
            self.publish()
        }
    }

    private func forget(_ pid: pid_t) {
        queue.async {
            guard self.apps.removeValue(forKey: pid) != nil else { return }
            self.publish()
        }
    }

    /// On `queue`: hands the items to the main thread.
    private func publish() {
        let items = apps.values.flatMap { $0.map(\.item) }
        let onChange = onChange
        DispatchQueue.main.async { MainActor.assumeIsolated { onChange(items) } }
    }

    /// On `queue`: one app's menu bar items, from its `AXExtrasMenuBar`.
    private static func items(of pid: pid_t) -> [(item: MenuBarItem, element: AXUIElement)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let bar = attribute(app, "AXExtrasMenuBar") as! AXUIElement?,
              let children = attribute(bar, kAXChildrenAttribute) as? [AXUIElement], !children.isEmpty else { return [] }
        let running = NSRunningApplication(processIdentifier: pid)
        let bundle = running?.bundleIdentifier
        // A helper outside any app (node-systray's tray_darwin_release) is named by what launched it.
        let name = bundle == nil ? launcherName(of: pid) ?? running?.localizedName ?? "App"
            : running?.localizedName ?? bundle ?? "App"
        return children.enumerated().compactMap { index, element in
            guard let frame = frame(of: element) else { return nil }
            let identifier = attribute(element, kAXIdentifierAttribute) as? String
            let title = [attribute(element, kAXDescriptionAttribute), attribute(element, kAXTitleAttribute)]
                .compactMap { $0 as? String }.first { !$0.isEmpty }
            let id = "\(bundle ?? String(pid))/\(identifier ?? String(index))"
            return (MenuBarItem(id: id, pid: pid, appName: name, bundleID: bundle, title: title,
                                identifier: identifier?.isEmpty == false ? identifier : nil, frame: frame), element)
        }
    }

    /// The script or program that started a helper process: `node ~/.local/bin/9router` gives "9router".
    private static func launcherName(of pid: pid_t) -> String? {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        guard parent > 1, let arguments = arguments(of: parent), let program = arguments.first else { return nil }
        let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3", "ruby", "perl", "sh", "bash", "zsh"]
        let base = (program as NSString).lastPathComponent
        if interpreters.contains(base), let script = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            return (script as NSString).lastPathComponent
        }
        return base
    }

    /// A process's arguments, from `KERN_PROCARGS2`.
    private static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let count = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        // After the count: the executable path, padding, then the arguments, each ending in a zero.
        var parts = buffer[4..<size].split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
        parts.removeFirst()
        return Array(parts.prefix(Int(count)))
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    /// The status item windows on `screen`'s menu bar, from the window list: fast, and no permission.
    static func windows(on screen: NSScreen) -> [MenuBarWindow] {
        guard let primary = NSScreen.screens.first else { return [] }
        // Window list frames have their origin at the top left of the primary screen. Items pushed
        // off the left end by NotchNotch's divider count too: they're still there, and still draw.
        let top = CGRect(x: screen.frame.minX - 20_000, y: primary.frame.maxY - screen.frame.maxY,
                         width: screen.frame.width + 20_000, height: 40)
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), top.intersects(frame) else { return nil }
            return MenuBarWindow(id: info[kCGWindowNumber as String] as? UInt32 ?? 0, frame: frame,
                                 onScreen: info[kCGWindowIsOnscreen as String] as? Bool == true)
        }
    }
}
