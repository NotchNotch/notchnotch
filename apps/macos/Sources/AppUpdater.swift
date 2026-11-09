import AppKit
import Observation
import Sparkle

/// Sparkle-backed updates. Only release builds carry a feed and public key;
/// development builds leave the updater off so they are never replaced.
@MainActor @Observable
final class AppUpdater: NSObject, SPUStandardUserDriverDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    private(set) var canCheckForUpdates = false
    var isAvailable: Bool { controller != nil }

    override init() {
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        guard info["SUFeedURL"] is String, info["SUPublicEDKey"] is String else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        // SPUUpdater is main-actor bound and changes this property on the main thread.
        observations.append(controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        })
    }

    var automaticallyChecks: Bool {
        get { access(keyPath: \.automaticallyChecks); return controller?.updater.automaticallyChecksForUpdates ?? false }
        set { withMutation(keyPath: \.automaticallyChecks) { controller?.updater.automaticallyChecksForUpdates = newValue } }
    }

    var automaticallyDownloads: Bool {
        get { access(keyPath: \.automaticallyDownloads); return controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { withMutation(keyPath: \.automaticallyDownloads) { controller?.updater.automaticallyDownloadsUpdates = newValue } }
    }

    var lastChecked: Date? { controller?.updater.lastUpdateCheckDate }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // NotchNotch is a menu bar app with no Dock icon, so a scheduled update
    // window would otherwise open behind whatever the user is doing.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated { NSApp.activate(ignoringOtherApps: true) }
    }
}
