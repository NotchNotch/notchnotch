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
                    Text("Allow \(request.extensionName) to \(request.runsTool ? "run a local tool" : "connect to a local app")?")
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(request.runsTool
                         ? "The tool runs with your user account and can access your files and network. Allow only tools you trust."
                         : "The extension can exchange data with this local service on your Mac.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(request.connectionID).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(request.target).font(.caption.monospaced()).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Text("“Always Allow” is remembered until the helper changes or you forget access in Settings & Extensions.")
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
}
