import AppKit
import SwiftUI

/// Shown once, on the first launch: where NotchNotch lives and how to start.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static let shownKey = "welcomeShownVersion"
    static let version = 1
    static var shouldShow: Bool {
        ProcessInfo.processInfo.environment["NOTCHNOTCH_SHOW_WELCOME"] == "1" ||
            UserDefaults.standard.integer(forKey: shownKey) < version
    }

    init(model: AppModel, openExtension: @escaping (String?) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "Welcome to NotchNotch"
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: WelcomeView(model: model, finish: { [weak self] in
            self?.close()
        }, connect: { [weak self] in
            self?.close()
            openExtension("dev.notchnotch.music")
        }))
        window.setContentSize(window.contentViewController!.view.fittingSize)
        window.center()
        window.delegate = self
    }
    required init?(coder: NSCoder) { nil }

    func reveal() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(Self.version, forKey: Self.shownKey)
    }
}

struct WelcomeView: View {
    @Bindable var model: AppModel
    let finish: () -> Void
    let connect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 76, height: 76).accessibilityHidden(true)
                Text("Welcome to NotchNotch").font(.largeTitle).bold()
                Text("Your notch now shows live activities: what’s playing, your next meeting, and anything an extension adds.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 36).padding(.horizontal, 36)
            VStack(alignment: .leading, spacing: 18) {
                feature("laptopcomputer", "It lives in the notch",
                        "Hover over the notch to preview an activity and click to open it. Scroll sideways to switch.")
                feature("menubar.rectangle", "And in the menu bar",
                        "There’s no Dock icon. Settings, extensions and updates are in the NotchNotch menu.")
                feature("puzzlepiece.extension.fill", "Add what you need",
                        "Connect Music or Calendar, or build your own extension with React.")
            }
            .padding(.horizontal, 40).padding(.vertical, 28)
            Toggle("Open NotchNotch at login", isOn: Binding(get: { model.launchAtLogin || model.launchAtLoginNeedsApproval },
                                                            set: { model.setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox)
                .onAppear { model.refreshLaunchAtLogin() }
            Spacer(minLength: 24)
            HStack(spacing: 12) {
                Button("Connect Music & Calendar…", action: connect).controlSize(.large)
                Button("Get Started", action: finish).controlSize(.large)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 28)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
