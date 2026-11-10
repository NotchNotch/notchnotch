import AppKit
import ServiceManagement
import Observation
import NotchCore
import NotchProtocol
import NotchExtensions
import NotchConnections

@MainActor @Observable
final class AppModel {
    static let maximumLogEntries = 300
    var platform = PlatformState()
    private(set) var installedExtensions: [InstalledExtension] = []
    /// Extensions that wait for required preferences, with the missing titles.
    private(set) var missingPreferences: [String: [String]] = [:]
    let preferenceStore = ExtensionPreferenceStore()
    private(set) var libraryIssues: [String: String] = [:]
    private(set) var extensionSettings: [String: UINode] = [:]
    private(set) var extensionSessionIDs: [String: UUID] = [:]
    private(set) var extensionLogs: [String: [ExtensionLogEntry]] = [:]
    private var snapshotRevisions: [String: Int] = [:]
    private var disabledExtensionIDs = Set(UserDefaults.standard.stringArray(forKey: "disabledExtensionIDs") ?? [])
    private var installingIDs: Set<String> = []
    var expandOnHover: Bool = UserDefaults.standard.object(forKey: "expandOnHover") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(expandOnHover, forKey: "expandOnHover")
            hoverTask?.cancel()
            hover.reset()
            onLayoutChange?()
        }
    }
    private nonisolated static var supportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("NotchNotch")
    }
    var extensionStore: ExtensionStore {
        ExtensionStore(directory: Self.supportDirectory.appendingPathComponent("Extensions"))
    }
    /// Projects that `notchnotch dev` runs.
    let developmentRegistry = DevelopmentRegistry(directory: supportDirectory.appendingPathComponent("Development"))
    private var developmentEntries: [DevelopmentRegistry.Entry] = []
    private var developmentTimer: Timer?

    let store = StoreModel(directory: supportDirectory.appendingPathComponent("Store"))
    /// Extension id → Store handle, for extensions installed from the Store.
    private(set) var storeInstalls: [String: String] = UserDefaults.standard.dictionary(forKey: "storeInstalls") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(storeInstalls, forKey: "storeInstalls") }
    }
    /// Records where an installed extension came from: a Store handle, or nil for a local file.
    func recordInstall(_ id: String, storeHandle: String?) { storeInstalls[id] = storeHandle }

    /// This app's version; nil in a build without Info.plist, which counts as new enough.
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    func storeState(of entry: ExtensionCatalog.Entry) -> StoreEntryState {
        let compatible = appVersion.map(entry.runs(onApp:)) ?? true
        guard let record = installedExtensions.first(where: { $0.id == entry.id }) else {
            return compatible ? .install : .needsApp(entry.minimumAppVersion ?? "")
        }
        switch record.origin {
        case .bundled: return .included
        case .development: return .developing
        case .local:
            guard entry.isNewer(than: record.manifest.version) else { return .installed }
            return compatible ? .update(from: record.manifest.version) : .needsApp(entry.minimumAppVersion ?? "")
        }
    }
    var storeUpdates: [ExtensionCatalog.Entry] {
        (store.catalog?.extensions ?? []).filter { if case .update = storeState(of: $0) { true } else { false } }
    }

    /// Per-extension key-value storage written by the runner (manifest ids are validated path-safe).
    func storageURL(for id: String) -> URL {
        Self.supportDirectory.appendingPathComponent("Storage").appendingPathComponent("\(id).json")
    }
    /// Mirrors SMAppService; the system owns the actual state and the user can
    /// change it in System Settings › General › Login Items.
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    var launchAtLoginError: String?
    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }
    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }
        struct Display: Identifiable, Equatable { let id: String; let name: String; let hasNotch: Bool }
    /// Connected screens, refreshed by the app delegate on display changes.
    var displays: [Display] = []
    /// nil = automatic: the built-in display with a camera housing, else the main display.
    var preferredDisplayID: String? = UserDefaults.standard.string(forKey: "preferredDisplayID") {
        didSet {
            UserDefaults.standard.set(preferredDisplayID, forKey: "preferredDisplayID")
            onLayoutChange?()
        }
    }
        var errors: [String: String] = [:]
    var notchWidth: CGFloat = 180
    var topHeight: CGFloat = 34
    var hasNotch = false
    private var contentSizing = ActivityContentSizing()
    var contentHeight: CGFloat { contentSizing.height }
    private(set) var pageDirection: ActivityPageDirection = .next
    private var reservedCanvasHeight: CGFloat = 0
    private var hover = HoverState()
    private var idlePinned = false
    var hoverExpanded: Bool { hover.isExpanded }
    var onLayoutChange: (() -> Void)?
    var onOpenManagement: (() -> Void)?
    var onRevealActivity: ((SurfaceKey) -> Void)?
    private var pointerInside = false
    private var suppressHover = false
    private var hoverTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var scheduledPeek: ActivePeek?
    private(set) var lastPeekText = ""
    /// A host message shown like an extension's peek, e.g. on launch. A menu bar
    /// app has no Dock icon or window, so this is the only sign it has opened.
    private(set) var greeting: String?
    @ObservationIgnored private var greetingTask: Task<Void, Never>?
    private var connections: [String: RunnerConnection] = [:]
    private var reloads: [String: String] = [:]
    private var reloadTimer: Timer?
    private var restartPolicy = RestartPolicy()
    private var restartTasks: [String: Task<Void, Never>] = [:]

    var isExpanded: Bool { platform.isExpanded || idlePinned || hoverExpanded }
    var displayedSurface: HostedSurface? {
        platform.isExpanded ? platform.selected : platform.hoverSurface
    }
    var wingSurface: HostedSurface? {
        presentation == .hovered ? platform.hoverSurface : platform.compact
    }
    var playerNode: UINode? { displayedSurface?.surface.expanded.children.first { $0.type == .player } }
    var presentation: NotchPresentation {
        if isExpanded { return .expanded }
        if platform.activePeek != nil || greeting != nil { return .peek }
        if hover.isHighlighted { return .hovered }
        return platform.presentation
    }
    var isPeeking: Bool { presentation == .peek }
    var geometry: NotchGeometry {
        .init(cameraWidth: notchWidth, cameraHeight: topHeight, attached: hasNotch,
              contentHeight: contentHeight, hasActivity: platform.compact != nil || platform.pendingCount > 0,
              reservedCanvasHeight: reservedCanvasHeight, expandedHeaderHeight: 0)
    }
    var extensionRoot: URL {
        if let value = ProcessInfo.processInfo.environment["NOTCHNOTCH_EXTENSIONS"] { return URL(fileURLWithPath: value) }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/extensions")
    }
    var runnerURL: URL {
        if let value = ProcessInfo.processInfo.environment["NOTCHNOTCH_RUNNER"] { return URL(fileURLWithPath: value) }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ExtensionRunner")
    }

    func start() {
        reloadExtensions()
        if ProcessInfo.processInfo.environment["NOTCHNOTCH_DEV"] == "1" {
            reloadTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadExtensions() }
            }
        }
        // Cheap when nobody develops: one directory listing per second.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDevelopment() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        developmentTimer = timer
    }

    /// Loads, reloads after a rebuild, and unloads `notchnotch dev` projects.
    private func checkDevelopment() {
        let entries = developmentRegistry.entries()
        guard entries != developmentEntries || !entries.isEmpty else { return }
        developmentEntries = entries
        reloadExtensions()
    }

    func reloadExtensions(force: Bool = false, restarting: String? = nil) {
        if force { restartPolicy = RestartPolicy() }
        developmentEntries = developmentRegistry.entries()
        let scan = extensionStore.scan(included: extensionRoot, development: ProcessInfo.processInfo.environment["NOTCHNOTCH_EXTENSIONS"] != nil,
                                       developing: developmentEntries)
        if installedExtensions != scan.extensions { installedExtensions = scan.extensions }
        if libraryIssues != scan.issues { libraryIssues = scan.issues }
        let candidates = scan.extensions.filter { isEnabled($0.id) && !installingIDs.contains($0.id) }
        let ids = Set(candidates.map(\.id))
        for id in connections.keys.filter({ !ids.contains($0) }) { stopExtension(id) }
        for id in missingPreferences.keys where !ids.contains(id) { missingPreferences.removeValue(forKey: id) }
        for record in candidates {
            let manifest = record.manifest
            let missing = manifest.missingRequiredPreferences(stored: preferenceStore.summary(for: manifest))
            if !missing.isEmpty {
                // Starts as soon as the person fills these in under Setup.
                if connections[manifest.id] != nil { stopExtension(manifest.id) }
                reloads.removeValue(forKey: manifest.id)
                if missingPreferences[manifest.id] != missing { missingPreferences[manifest.id] = missing }
                continue
            }
            if missingPreferences[manifest.id] != nil { missingPreferences.removeValue(forKey: manifest.id) }
            do {
                let bundle = record.directory.appendingPathComponent(manifest.entry)
                let modified = try bundle.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let revision = "\(record.directory.path):\(modified.timeIntervalSinceReferenceDate):\(try encoder.encode(manifest).base64EncodedString())"
                guard force || restarting == manifest.id || reloads[manifest.id] != revision else { continue }
                stopExtension(manifest.id)
                let sessionID = UUID()
                extensionSessionIDs[manifest.id] = sessionID
                let connection = RunnerConnection(manifest: manifest, directory: record.directory) { [weak self] snapshot in
                    guard let self, self.extensionSessionIDs[manifest.id] == sessionID else { return }
                    guard snapshot.revision > self.snapshotRevisions[manifest.id, default: 0] else { return }
                    do {
                        try self.platform.apply(snapshot, expectedExtensionID: manifest.id, imageHosts: manifest.imageHosts ?? [], allowPeek: !self.isExpanded)
                        self.snapshotRevisions[manifest.id] = snapshot.revision
                        if self.extensionSettings[manifest.id] != snapshot.settings { self.extensionSettings[manifest.id] = snapshot.settings }
                    }
                    catch { self.errors[manifest.id] = error.localizedDescription }
                    self.synchronizePeek()
                    self.onLayoutChange?()
                } onFailure: { [weak self] message in
                    guard let self, self.extensionSessionIDs[manifest.id] == sessionID else { return }
                    self.extensionSessionIDs.removeValue(forKey: manifest.id)
                    self.platform.removeExtension(manifest.id)
                    self.extensionSettings.removeValue(forKey: manifest.id)
                    self.synchronizePeek()
                    self.errors[manifest.id] = message
                    self.appendLog(manifest.id, message, level: .error)
                    self.scheduleRestart(manifest.id, after: message)
                    self.onLayoutChange?()
                } onLog: { [weak self] level, message in
                    guard let self, self.extensionSessionIDs[manifest.id] == sessionID else { return }
                    self.appendLog(manifest.id, message, level: level)
                }
                connections[manifest.id] = connection
                reloads[manifest.id] = revision
                try connection.start(executable: runnerURL, bundle: bundle, storage: storageURL(for: manifest.id), preferences: preferenceStore)
            } catch { errors[manifest.id] = error.localizedDescription }
        }
        synchronizePeek()
        onLayoutChange?()
    }

    func isEnabled(_ id: String) -> Bool { !disabledExtensionIDs.contains(id) }
    func isRunning(_ id: String) -> Bool { connections[id] != nil && errors[id] == nil }
    func hasRendered(_ id: String) -> Bool { snapshotRevisions[id] != nil }
    subscript(enabledFor id: String) -> Bool {
        get { isEnabled(id) }
        set { setEnabled(newValue, for: id) }
    }
    func setEnabled(_ enabled: Bool, for id: String) {
        guard isEnabled(id) != enabled else { return }
        restartPolicy.reset(id)
        restartTasks.removeValue(forKey: id)?.cancel()
        if enabled { disabledExtensionIDs.remove(id) } else { disabledExtensionIDs.insert(id) }
        UserDefaults.standard.set(disabledExtensionIDs.sorted(), forKey: "disabledExtensionIDs")
        reloadExtensions()
    }
    func canRevealActivity(_ id: String) -> Bool { platform.surfaces.contains { $0.key.extensionID == id } }
    func revealActivity(_ id: String) {
        if let key = platform.surfaces.first(where: { $0.key.extensionID == id })?.key { onRevealActivity?(key) }
    }
    func restartExtension(_ id: String) {
        restartPolicy.reset(id)
        reloadExtensions(restarting: id)
    }
    /// Crashed or hung runners restart with backoff (1 s, 2 s, 4 s) and give
    /// up after three failures in two minutes.
    private func scheduleRestart(_ id: String, after message: String) {
        restartTasks.removeValue(forKey: id)?.cancel()
        guard let delay = restartPolicy.failed(id, now: .now) else {
            errors[id] = message + "\nStopped after repeated failures. Fix the problem, then restart the extension."
            return
        }
        appendLog(id, "Restarting in \(Int(delay)) s…", level: .info)
        restartTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.restartTasks.removeValue(forKey: id)
            // Skip when the user disabled, removed or manually restarted it meanwhile.
            guard self.isEnabled(id), self.errors[id] != nil, self.extensionSessionIDs[id] == nil else { return }
            self.reloadExtensions(restarting: id)
        }
    }
    func clearLogs(_ id: String) { extensionLogs.removeValue(forKey: id) }
    /// Bumped when stored grants change; UserDefaults itself is not observable.
    private(set) var grantsRevision = 0
    func alwaysAllowedConnections(_ id: String) -> [String] {
        _ = grantsRevision
        return ConnectionGrantStore().grantedConnections(extensionID: id)
    }
    /// Removes stored "Always Allow" grants and closes current connections.
    func forgetAccess(_ id: String) {
        ConnectionGrantStore().revoke(extensionID: id)
        grantsRevision += 1
        disconnectExtension(id)
    }
    private func appendLog(_ id: String, _ message: String, level: ExtensionLogEntry.Level) {
        let entry = ExtensionLogEntry(date: .now, level: level, message: message)
        var entries = extensionLogs[id, default: []]
        entries.append(entry)
        // Bounded per extension. Drop the oldest info lines first so the
        // errors explaining a crash survive a chatty timer loop.
        while entries.count > Self.maximumLogEntries {
            entries.remove(at: entries.firstIndex { $0.level == .info } ?? 0)
        }
        extensionLogs[id] = entries
        if installedExtensions.first(where: { $0.id == id })?.origin == .development {
            developmentRegistry.appendLog(id: id, level: level == .error ? "error" : "log", message: message)
        }
    }
    func disconnectExtension(_ id: String) { connections[id]?.resetConnections() }
    private func stopExtension(_ id: String) {
        extensionSessionIDs.removeValue(forKey: id)
        connections.removeValue(forKey: id)?.stop()
        platform.removeExtension(id)
        reloads.removeValue(forKey: id)
        errors.removeValue(forKey: id)
        extensionSettings.removeValue(forKey: id)
        snapshotRevisions.removeValue(forKey: id)
    }
    func reviewInstall(_ folder: URL) async throws -> ExtensionPackage {
        let store = extensionStore
        let package = try await Task.detached(priority: .userInitiated) {
            folder.pathExtension.lowercased() == ExtensionArchive.fileExtension ? try store.inspectArchive(folder) : try store.inspect(folder)
        }.value
        if let existing = installedExtensions.first(where: { $0.id == package.id }), !store.isManaged(existing) {
            ExtensionStore.discardStaged(package)
            throw ProtocolError.invalid("\(existing.manifest.name) is included with NotchNotch and cannot be replaced. Use a different extension identifier.")
        }
        return package
    }
    func installExtension(_ package: ExtensionPackage) async throws {
        // Check again at confirmation time; included/development ids cannot be replaced.
        if let existing = installedExtensions.first(where: { $0.id == package.id }), !extensionStore.isManaged(existing) {
            throw ProtocolError.invalid("An included extension already uses this identifier.")
        }
        let replacing = installedExtensions.contains { $0.id == package.id }
        installingIDs.insert(package.id)
        stopExtension(package.id)
        defer { installingIDs.remove(package.id); reloadExtensions() }
        let store = extensionStore
        _ = try await Task.detached(priority: .userInitiated) { try store.install(package, replacing: replacing) }.value
    }
    /// Saves preference changes and restarts the extension with the new values.
    func savePreferences(_ changes: [String: JSONValue], for record: InstalledExtension) async throws {
        let store = preferenceStore, manifest = record.manifest
        try await Task.detached(priority: .userInitiated) { try store.save(changes, for: manifest) }.value
        reloadExtensions(restarting: record.id)
    }

    func removeExtension(_ record: InstalledExtension) async throws {
        guard extensionStore.isManaged(record) else { throw ProtocolError.invalid("Included extensions can be disabled but not removed.") }
        forgetAccess(record.id)
        storeInstalls[record.id] = nil
        try? FileManager.default.removeItem(at: storageURL(for: record.id))
        let id = record.id
        let preferences = preferenceStore
        Task.detached {
            try? ExtensionSecretStore().deleteAll(extensionID: id)
            preferences.removeAll(extensionID: id)
        }
        installingIDs.insert(record.id)
        stopExtension(record.id)
        defer { installingIDs.remove(record.id); reloadExtensions() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.recycle([record.directory]) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func stop() {
        for task in restartTasks.values { task.cancel() }
        restartTasks.removeAll()
        hoverTask?.cancel()
        peekTask?.cancel()
        reloadTimer?.invalidate()
        developmentTimer?.invalidate()
        for connection in connections.values { connection.stop() }
        connections.removeAll()
    }
    func disconnectExtensions() {
        for connection in connections.values { connection.resetConnections() }
    }
    func greet(_ text: String, for seconds: Double = 4) {
        greetingTask?.cancel()
        greeting = text
        lastPeekText = text
        onLayoutChange?()
        greetingTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.endGreeting()
        }
    }
    func endGreeting() {
        guard greeting != nil else { return }
        greetingTask?.cancel()
        greeting = nil
        if let text = platform.peeking?.surface.peek?.text { lastPeekText = text }
        onLayoutChange?()
    }
    func toggle() {
        endGreeting()
        if platform.isExpanded || idlePinned { close() }
        else { pinOpen() }
    }
    func close() {
        hoverTask?.cancel()
        hover.reset()
        idlePinned = false
        suppressHover = pointerInside
        platform.close()
        synchronizePeek()
        onLayoutChange?()
    }
    func open(_ key: SurfaceKey) {
        if let current = platform.surfaces.firstIndex(where: { $0.key == displayedSurface?.key }),
           let target = platform.surfaces.firstIndex(where: { $0.key == key }), current != target {
            pageDirection = target > current ? .next : .previous
        }
        hoverTask?.cancel()
        hover.reset()
        idlePinned = false
        platform.open(key)
        selectContent()
        synchronizePeek()
        onLayoutChange?()
    }
    func switchActivity(_ direction: ActivityPageDirection) {
        guard isExpanded,
              let current = platform.surfaces.firstIndex(where: { $0.key == displayedSurface?.key }) else { return }
        let target = current + direction.rawValue
        guard platform.surfaces.indices.contains(target) else { return }
        open(platform.surfaces[target].key)
    }
    func selectContent() {
        guard contentSizing.select(displayedSurface?.key) else { return }
        contentSizeChanged()
    }
    func measureContent(_ height: CGFloat, for key: SurfaceKey?) {
        let selectionChanged = contentSizing.select(displayedSurface?.key)
        let measurementChanged = contentSizing.measure(height, for: key)
        guard selectionChanged || measurementChanged else { return }
        contentSizeChanged()
    }
    private func contentSizeChanged() {
        // Reserve enough room BEFORE the shape grows. Reuse that space on
        // smaller surfaces so a closing spring cannot be clipped by the window.
        reservedCanvasHeight = geometry.canvasSize.height
        onLayoutChange?()
    }
    func pointerChanged(inside: Bool) {
        guard pointerInside != inside else { return }
        pointerInside = inside
        hoverTask?.cancel()
        if !inside { suppressHover = false }
        guard !platform.isExpanded, !idlePinned, !isPeeking, !suppressHover else { return }
        hover.pointerChanged(inside: inside)
        onLayoutChange?()
        guard expandOnHover, let deadline = hover.deadline else { return }
        hoverTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
            catch { return }
            guard let self, !self.platform.isExpanded, !self.idlePinned, !self.isPeeking else { return }
            self.hover.advance(now: deadline)
            self.onLayoutChange?()
        }
    }
    func pinOpen() {
        if let key = displayedSurface?.key { open(key) }
        else {
            hoverTask?.cancel()
            hover.reset()
            idlePinned = true
            onLayoutChange?()
        }
    }
    private func synchronizePeek() {
        if let text = platform.peeking?.surface.peek?.text { lastPeekText = text }
        guard scheduledPeek != platform.activePeek else { return }
        peekTask?.cancel()
        scheduledPeek = platform.activePeek
        guard let peek = platform.activePeek else { return }
        hoverTask?.cancel()
        hover.reset()
        peekTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, peek.expiresAt.timeIntervalSinceNow))) }
            catch { return }
            guard let self, self.platform.activePeek == peek else { return }
            self.platform.expirePeek(now: peek.expiresAt)
            self.scheduledPeek = nil
            self.onLayoutChange?()
        }
    }
    func openFirst() { pinOpen() }
    func previewAnnouncement() {
        guard let item = platform.compact.flatMap({ $0.surface.peek == nil ? nil : $0 })
            ?? platform.surfaces.first(where: { $0.surface.peek != nil }) else { return }
        hoverTask?.cancel()
        hover.reset()
        idlePinned = false
        suppressHover = pointerInside
        platform.showPeek(for: item.key)
        synchronizePeek()
        onLayoutChange?()
    }
    func openPrompt() {
        if let key = platform.surfaces.first(where: { $0.surface.kind == .prompt })?.key { open(key) }
    }
    func send(extensionID: String, action: String, value: String?) {
        // Once the user interacts, leaving the hover region must not dismiss a form.
        if !platform.isExpanded { pinOpen() }
        connections[extensionID]?.send(action: action, value: value)
    }
    func sendSettings(extensionID: String, action: String, value: String?) {
        // Setup actions use the same runner but never focus or pin the notch.
        guard isEnabled(extensionID), let settings = extensionSettings[extensionID] else { return }
        func containsAction(_ node: UINode) -> Bool {
            (node.props.action == action && node.props.disabled != true) || node.children.contains(where: containsAction)
        }
        guard containsAction(settings) else { return }
        connections[extensionID]?.send(action: action, value: value)
    }
}
