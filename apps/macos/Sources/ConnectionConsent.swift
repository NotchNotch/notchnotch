import AppKit
import SwiftUI
import NotchProtocol
import NotchExtensions

enum ConsentDecision { case deny, once, always }

struct ConsentRequest {
    let extensionName: String
    let extensionIcon: ExtensionIcon
    let connectionID: String
    let target: String
    let runsTool: Bool
    var capability: SystemCapability?
}

/// Asks for connection access in a floating, non-modal window. Requests are
/// shown one at a time; the notch and every runner keep working meanwhile.
@MainActor
final class ConnectionConsentPresenter {
    static let shared = ConnectionConsentPresenter()
    private var queue: [(ConsentRequest, CheckedContinuation<ConsentDecision, Never>)] = []
    private var window: NSPanel?
    private var current: CheckedContinuation<ConsentDecision, Never>?

    func ask(_ request: ConsentRequest) async -> ConsentDecision {
        await withCheckedContinuation { continuation in
            queue.append((request, continuation))
            showNext()
        }
    }

    private func showNext() {
        guard current == nil, !queue.isEmpty else { return }
        let (request, continuation) = queue.removeFirst()
        current = continuation
        let panel = window ?? makeWindow()
        window = panel
        panel.contentView = NSHostingView(rootView: ConsentView(request: request) { [weak self] decision in
            self?.finish(decision)
        })
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 420, height: 240))
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func finish(_ decision: ConsentDecision) {
        guard let continuation = current else { return }
        current = nil
        window?.orderOut(nil)
        continuation.resume(returning: decision)
        showNext()
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        // Closing the window is a denial.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(.deny) }
        }
        return panel
    }
}

private struct ConsentView: View {
    let request: ConsentRequest
    let decide: (ConsentDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ExtensionIdentityView(icon: request.extensionIcon, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow \(request.extensionName) to \(action)?")
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(explanation)
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if request.capability == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.connectionID).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(request.target).font(.caption.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            Text(request.capability == nil
                 ? "“Always Allow” is remembered until the helper changes or you forget access in Settings & Extensions."
                 : "“Always Allow” is remembered until you forget access in Settings & Extensions.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Don’t Allow") { decide(.deny) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Allow Once") { decide(.once) }
                Button("Always Allow") { decide(.always) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).padding(.top, 8)
        .frame(width: 420)
    }

    private var action: String {
        switch request.capability {
        case .calendar: "read your calendars"
        case .nowPlaying: "see and control what’s playing"
        case nil: request.runsTool ? "run a local tool" : "connect to a local app"
        }
    }

    private var explanation: String {
        switch request.capability {
        case .calendar: "It sees the next week’s events from the calendars you choose: titles, times, locations and meeting links. Not notes or attendees, and it can’t change anything."
        case .nowPlaying: "It sees the song playing in Spotify or Apple Music and can play, pause and skip. macOS asks separately before NotchNotch controls each app."
        case nil: request.runsTool
            ? "The tool runs with your user account and can access your files and network. Allow only tools you trust."
            : "The extension can exchange data with this local service on your Mac."
        }
    }
}
