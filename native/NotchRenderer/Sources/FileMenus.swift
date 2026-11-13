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

    /// The apps that open every one of the files, the default app first, then Other….
    public static func openWith(_ urls: [URL]) -> NSMenu {
        let menu = NSMenu(title: "Open With")
        guard let first = urls.first else { return menu }
        let common = urls.dropFirst().reduce(Set(NSWorkspace.shared.urlsForApplications(toOpen: first))) {
            $0.intersection(NSWorkspace.shared.urlsForApplications(toOpen: $1))
        }
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: first)
        let apps = common.sorted { app, other in
            if app == preferred { return true }
            if other == preferred { return false }
            return FileManager.default.displayName(atPath: app.path).localizedStandardCompare(FileManager.default.displayName(atPath: other.path)) == .orderedAscending
        }
        for app in apps.prefix(24) {
            let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            let item = ClosureMenuItem(app == preferred ? "\(name) (default)" : name) { open(urls, with: app) }
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
            if app == preferred, apps.count > 1 { menu.addItem(.separator()) }
        }
        if !apps.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem("Other…") {
            let panel = NSOpenPanel()
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            panel.prompt = "Open"
            NSApp.activate()
            if panel.runModal() == .OK, let app = panel.url { open(urls, with: app) }
        })
        return menu
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

    private static func open(_ urls: [URL], with app: URL) {
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
