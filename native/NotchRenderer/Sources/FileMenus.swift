import AppKit

/// AppKit menus for files: a file's menu in a grid, and the Open With and
/// Share menus the app shows beside the pointer when an extension asks.
@MainActor
public enum FileMenus {
    /// The visible window under the pointer and the pointer's place in it, to show a menu there.
    public static func pointerAnchor() -> (view: NSView, rect: NSRect)? {
        let mouse = NSEvent.mouseLocation
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(mouse) }) ?? NSApp.keyWindow,
              let view = window.contentView else { return nil }
        let point = view.convert(window.convertPoint(fromScreen: mouse), from: nil)
        return (view, NSRect(x: point.x, y: point.y, width: 1, height: 1))
    }

    /// Shows a menu at the pointer, over the window it's in.
    public static func popUpAtPointer(_ menu: NSMenu) {
        guard let anchor = pointerAnchor() else { return }
        menu.popUp(positioning: nil, at: anchor.rect.origin, in: anchor.view)
    }

    /// The apps that open every one of the files: the default app first, the rest by name.
    public static func apps(toOpen urls: [URL]) -> (apps: [URL], preferred: URL?) {
        guard let first = urls.first else { return ([], nil) }
        let common = urls.dropFirst().reduce(Set(NSWorkspace.shared.urlsForApplications(toOpen: first))) {
            $0.intersection(NSWorkspace.shared.urlsForApplications(toOpen: $1))
        }
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: first).flatMap { common.contains($0) ? $0 : nil }
        let apps = common.sorted { app, other in
            if app == preferred { return true }
            if other == preferred { return false }
            return name(of: app).localizedStandardCompare(name(of: other)) == .orderedAscending
        }
        return (apps, preferred)
    }

    /// An app's name as Finder shows it, without ".app".
    public static func name(of app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    /// A menu of the apps that open every one of the files, the default app first, then Other….
    public static func openWith(_ urls: [URL]) -> NSMenu {
        let menu = NSMenu(title: "Open With")
        let (apps, preferred) = apps(toOpen: urls)
        for app in apps.prefix(24) {
            let item = ClosureMenuItem(app == preferred ? "\(name(of: app)) (default)" : name(of: app)) { open(urls, with: app) }
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
            if app == preferred, apps.count > 1 { menu.addItem(.separator()) }
        }
        if !apps.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem("Other…") { chooseOtherApp(for: urls) })
        return menu
    }

    /// Asks for any app in an open panel and opens the files with it.
    public static func chooseOtherApp(for urls: [URL]) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Open"
        Task { if let app = await choose(panel) { open(urls, with: app) } }
    }

    /// Shows an open or save panel without blocking the main thread, so the
    /// notch keeps animating behind it. The chosen URL, or nil when cancelled.
    public static func choose(_ panel: NSSavePanel) async -> URL? {
        NSApp.activate()
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }

    /// macOS's own Share menu for the files: AirDrop, Messages, Mail, Notes and the rest.
    public static func shareItem(_ urls: [URL]) -> NSMenuItem {
        NSSharingServicePicker(items: urls).standardShareMenuItem
    }

    /// Puts the files on the clipboard, as Finder's Copy does.
    public static func copy(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    public static func open(_ urls: [URL], with app: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

/// A menu item that runs a closure.
@MainActor
public final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    public init(_ title: String, symbol: String? = nil, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}
