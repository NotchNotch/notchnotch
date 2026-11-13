import AppKit
import ServiceManagement
import Observation
import UniformTypeIdentifiers
import NotchCore
import NotchRenderer
import NotchProtocol
import NotchExtensions
import NotchConnections
import NotchCapabilities

@MainActor @Observable
final class AppModel {
    static let maximumLogEntries = 300
    var platform: PlatformState = {
        var state = PlatformState()
        if let data = UserDefaults.standard.data(forKey: "homePreferences"),
           let saved = try? JSONDecoder().decode(HomePreferences.self, from: data) { state.homePreferences = saved }
        return state
    }()
    private(set) var installedExtensions: [InstalledExtension] = []
    /// Extensions that wait for required preferences, with the missing titles.
    private(set) var missingPreferences: [String: [String]] = [:]
    let preferenceStore = ExtensionPreferenceStore()
    private(set) var libraryIssues: [String: String] = [:]
    private(set) var extensionSettings: [String: UINode] = [:]
    private(set) var extensionSessionIDs: [String: UUID] = [:]
    private(set) var extensionLogs: [String: [ExtensionLogEntry]] = [:]
    /// Changes with every snapshot, so nothing observes it; `renderedIDs` changes once.
    @ObservationIgnored private var snapshotRevisions: [String: Int] = [:]
    private var renderedIDs: Set<String> = []
    private var disabledExtensionIDs = Set(UserDefaults.standard.stringArray(forKey: "disabledExtensionIDs") ?? [])
    /// Every extension that ships inside the app, installed or not. Their native
    /// helpers can't come from the Store yet, so the Store offers them from here.
    private(set) var includedExtensions: [InstalledExtension] = []
    /// The included extensions the person has installed. nil until the first scan
    /// decides: Music on a new Mac, so the notch isn't empty, plus any extension
    /// that already saved data here before included extensions became optional.
    private var installedIncludedIDs = UserDefaults.standard.stringArray(forKey: "installedIncludedIDs").map(Set.init) {
        didSet { UserDefaults.standard.set(installedIncludedIDs?.sorted(), forKey: "installedIncludedIDs") }
    }
    static let defaultIncludedIDs: Set<String> = ["dev.notchnotch.music", "dev.notchnotch.shelf"]
    /// Included extensions that arrived after people already had the app. Each is
    /// installed once for everyone, new Mac or update; uninstalling it then sticks.
    static let introducedIDs: Set<String> = ["dev.notchnotch.shelf"]
    private var introducedIncludedIDs = Set(UserDefaults.standard.stringArray(forKey: "introducedIncludedIDs") ?? []) {
        didSet { UserDefaults.standard.set(introducedIncludedIDs.sorted(), forKey: "introducedIncludedIDs") }
    }
    /// Extensions that used to be included and now come from the Store, by Store
    /// handle. Whoever had one gets the Store version without a review: same
    /// publisher, and it asks for no more than the person already allowed.
    static let movedToStore: [String: String] = ["dev.notchnotch.calendar": "sadeqi-ah/calendar"]
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

    let store = StoreModel(directory: supportDirectory.appendingPathComponent("Store"))
    let problems = ProblemsModel(directory: supportDirectory)
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
    /// Installs Store updates that ask for nothing new without a review.
    var updatesStoreExtensionsAutomatically = UserDefaults.standard.object(forKey: "updatesStoreExtensionsAutomatically") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(updatesStoreExtensionsAutomatically, forKey: "updatesStoreExtensionsAutomatically")
            if updatesStoreExtensionsAutomatically { Task { await checkStoreUpdates() } }
        }
    }
    private var storeUpdateTimer: Timer?
    private var checkingStoreUpdates = false

    /// Refreshes the Store and installs the updates `StoreUpdates` allows. Each
    /// one is downloaded, checked against the catalog and inspected exactly as
    /// a reviewed install; an update that asks for more waits in the Store.
    func checkStoreUpdates() async {
        guard updatesStoreExtensionsAutomatically, let client = store.client, !checkingStoreUpdates else { return }
        checkingStoreUpdates = true
        defer { checkingStoreUpdates = false }
        await store.open()
        guard let catalog = store.catalog else { return }
        let plan = StoreUpdates.plan(catalog, installed: installedExtensions, storeInstalls: storeInstalls, appVersion: appVersion)
        for entry in plan.automatic where !installingIDs.contains(entry.id) {
            let previous = installedExtensions.first { $0.id == entry.id }?.manifest.version ?? "?"
            do {
                let file = try await client.download(entry)
                defer { try? FileManager.default.removeItem(at: file) }
                let package = try await reviewInstall(file)
                defer { ExtensionStore.discardStaged(package) }
                try entry.verifyContents(package)
                // The user may have removed it or installed another copy meanwhile.
                guard storeInstalls[entry.id] == entry.handle,
                      installedExtensions.first(where: { $0.id == entry.id })?.manifest.version == previous else { continue }
                try await installExtension(package)
                recordInstall(entry.id, storeHandle: entry.handle)
                appendLog(entry.id, "Updated from \(previous) to \(entry.manifest.version) from the Store.", level: .info)
            } catch {
                let message = "Couldn’t update to \(entry.manifest.version) from the Store: \(error.localizedDescription)"
                appendLog(entry.id, message, level: .error)
                problems.record(entry.id, message)
            }
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
    /// Why an extension isn't running. Each new reason is also a problem for the report.
    var errors: [String: String] = [:] {
        didSet {
            for (id, message) in errors where oldValue[id] != message { problems.record(id, message) }
        }
    }
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
    @ObservationIgnored private var livenessTimer: Timer?
    private var reloads: [String: String] = [:]
    private var reloadTimer: Timer?
    private var restartPolicy = RestartPolicy()
    private var restartTasks: [String: Task<Void, Never>] = [:]

    var isExpanded: Bool { platform.isExpanded || idlePinned || hoverExpanded || dropSession != nil || appChoice != nil || menuBarShowsAll }
    var displayedSurface: HostedSurface? {
        platform.isExpanded ? platform.selected : platform.hoverSurface
    }
    /// Home shows when it was opened, or when the notch opens with nothing to resume.
    var showsHome: Bool {
        guard dropSession == nil, appChoice == nil, !menuBarShowsAll else { return false }
        return platform.isExpanded ? platform.showsHome : isExpanded && displayedSurface == nil
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
    /// Other live activities join the wings only once the notch rests or is
    /// hovered: an announcement has the notch to itself, and when it ends
    /// they grow in and the wings widen.
    var showsLiveExtras: Bool {
        greeting == nil && !platform.minimals.isEmpty &&
            (presentation == .compact || presentation == .hovered) &&
            wingSurface?.key == platform.compact?.key
    }
    var geometry: NotchGeometry {
        var geometry = NotchGeometry(
            cameraWidth: notchWidth, cameraHeight: topHeight, attached: hasNotch,
            contentHeight: contentHeight, hasActivity: platform.compact != nil || platform.pendingCount > 0,
            reservedCanvasHeight: reservedCanvasHeight, expandedHeaderHeight: 0,
            wingWidth: NotchGeometry.wingWidth(fitting: wingContentWidth, roomy: showsLiveExtras))
        geometry.homeWidth = showsHome ? homeArrangement.width
            : dropSession != nil || appChoice != nil || menuBarShowsAll ? HomeLayout.width(columns: HomeLayout.minimumColumns)
            : displayedSurface.map { Self.fileGridWidth(in: $0.surface.expanded) } ?? 0
        return geometry
    }
    /// The open notch widens for a file grid, as for Home: its columns and the content margins.
    private static func fileGridWidth(in node: UINode) -> CGFloat {
        if node.type == .fileGrid, let count = node.props.files?.files.count, count > 0 {
            return FileGridLayout.width(columns: FileGridLayout.columns(for: count)) + 56
        }
        return node.children.map(fileGridWidth).max() ?? 0
    }

    // MARK: Drop

    /// A drag that came near the notch: what's being dragged, while the Drop view shows.
    struct DropSession: Equatable {
        var items: [DraggedItem]
        /// Resting on More shows every zone.
        var showsAll = false
    }
    private(set) var dropSession: DropSession?
    /// A file from the notch is being dragged out; until the mouse is up, drags aren't drops.
    @ObservationIgnored var draggingOut = false
    let droppedFiles = DroppedFileStore(directory: AppModel.supportDirectory.appendingPathComponent("Dropped Files"))
    @ObservationIgnored lazy var files: FilesService = {
        let service = FilesService(store: droppedFiles)
        service.presentOpenWith = { [weak self] urls in self?.chooseApp(for: urls) }
        return service
    }()
    /// How an extension's tree finds its dropped files: where they are, for
    /// dragging them out, and their thumbnails.
    func notchFiles(for extensionID: String?) -> NotchFiles? {
        guard let extensionID else { return nil }
        let store = droppedFiles, files = files
        return NotchFiles(url: { store.url($0.id, for: extensionID) },
                          thumbnail: { file, size in await files.thumbnail(file.id, for: extensionID, size: size) },
                          draggingOut: { [weak self] in self?.draggingOut = true },
                          perform: { action, chosen in
                              Task { _ = try? await files.perform(.init(action: action, ids: chosen.map(\.id)), extensionID: extensionID, permissions: []) }
                          })
    }
    /// Zones that take what's being dragged.
    var dropTargets: [DropTarget] { dropSession.map { platform.dropTargets(for: $0.items) } ?? [] }
    func dropTargets(for items: [DraggedItem]) -> [DropTarget] { platform.dropTargets(for: items) }

    /// A drag reached the notch: open it on the zones. No extension runs for this.
    func beginDrop(_ items: [DraggedItem]) {
        guard dropSession == nil, !items.isEmpty else { return }
        endGreeting()
        hoverTask?.cancel()
        hover.reset()
        dropSession = DropSession(items: items)
        selectContent()
        onLayoutChange?()
    }
    func showAllDropTargets() { dropSession?.showsAll = true }
    /// The drag left or ended without a drop.
    func endDrop() {
        guard dropSession != nil else { return }
        dropSession = nil
        // Hover sat out the drag; the pointer is still over the notch, so it mustn't open it now.
        hoverTask?.cancel()
        hover.reset()
        suppressHover = pointerInside
        selectContent()
        onLayoutChange?()
    }

    /// Hands what was dropped on `target` to its extension: files become
    /// handles kept for it, links and text go as they are. It reads the drag
    /// pasteboard, which still holds the drag while the drop is handled: item
    /// providers give a dropped photo as image data, not as the file.
    func deliver(from board: NSPasteboard, to target: DropTarget) {
        endDrop()
        let id = target.extensionID
        var items: [DropItem] = []
        for item in (board.pasteboardItems ?? []).prefix(256) {
            if let string = item.string(forType: .fileURL), let url = URL(string: string), url.isFileURL {
                do { items.append(.init(kind: .file, file: try droppedFiles.add(url.standardizedFileURL, for: id))) }
                catch { AppDelegate.debug("couldn't keep \(url.lastPathComponent): \(error)") }
            } else if let string = item.string(forType: .URL), let url = URL(string: string), string.utf8.count <= 8192 {
                let title = item.string(forType: NSPasteboard.PasteboardType("public.url-name")).map { String($0.prefix(1024)) }
                items.append(.init(kind: .url, url: url.absoluteString, title: title))
            } else if let text = item.string(forType: .string), !text.isEmpty {
                items.append(.init(kind: .text, text: String(text.prefix(65_536))))
            }
        }
        // The whole drop must fit one event; keep the items that do.
        let encoder = JSONEncoder()
        while !items.isEmpty, (try? encoder.encode(items))?.count ?? .max > UserEvent.maximumValueBytes { items.removeLast() }
        AppDelegate.debug("delivering \(items.count) items to \(id)")
        guard !items.isEmpty, let data = try? encoder.encode(items) else { return }
        connections[id]?.send(action: target.zone.action, value: String(decoding: data, as: UTF8.self))
        // The person dropped something to act on it: open the zone's activity and keep it open.
        if let opens = target.zone.opens {
            let key = SurfaceKey(extensionID: id, surfaceID: opens)
            if platform.surfaces.contains(where: { $0.key == key && $0.surface.kind == .activity }) { open(key) }
        }
    }

    // MARK: Menu bar

    /// Brings back the menu bar items hidden under the camera and the wings. Needs Accessibility.
    var menuBarEnabled = UserDefaults.standard.bool(forKey: "menuBarEnabled") {
        didSet {
            UserDefaults.standard.set(menuBarEnabled, forKey: "menuBarEnabled")
            if menuBarEnabled, !MenuBarScanner.isTrusted { requestMenuBarAccess() } else { updateMenuBar() }
        }
    }
    private(set) var menuBarTrusted = MenuBarScanner.isTrusted
    /// Each hidden item's own image instead of its app's icon; needs Screen Recording.
    var menuBarExactIcons = UserDefaults.standard.bool(forKey: "menuBarExactIcons") {
        didSet {
            UserDefaults.standard.set(menuBarExactIcons, forKey: "menuBarExactIcons")
            if menuBarExactIcons, !MenuBarImages.isGranted { MenuBarImages.request() }
            updateMenuBar()
        }
    }
    private(set) var menuBarCaptureGranted = MenuBarImages.isGranted
    let menuBarImages = MenuBarImages()
    @ObservationIgnored private var menuBarScanner: MenuBarScanner?
    @ObservationIgnored private var menuBarSeparator: MenuBarSeparator?
    @ObservationIgnored private var menuBarTrustTask: Task<Void, Never>?
    private var menuBarItems: [MenuBarItem] = []
    /// Hidden items, left to right, as of the last time the notch opened or items changed.
    private(set) var hiddenMenuBarItems: [MenuBarItem] = []
    /// Every hidden item as tiles, from the header's `+N`.
    private(set) var menuBarShowsAll = false
    /// The screen the notch is on; set by the app delegate.
    @ObservationIgnored var notchScreen: (() -> NSScreen?)?

    /// Starts or stops reading the menu bar to match the setting and the grant.
    func updateMenuBar() {
        menuBarTrusted = MenuBarScanner.isTrusted
        menuBarCaptureGranted = MenuBarImages.isGranted
        if !menuBarExactIcons || !menuBarCaptureGranted { menuBarImages.clear() }
        if menuBarEnabled, menuBarTrusted {
            if menuBarScanner == nil {
                let scanner = MenuBarScanner { [weak self] items in
                    self?.menuBarItems = items
                    self?.recomputeHiddenMenuBarItems()
                }
                menuBarScanner = scanner
                scanner.start()
            }
            if menuBarSeparator == nil {
                menuBarSeparator = MenuBarSeparator { [weak self] in self?.coveredMenuBar() }
            }
        } else {
            menuBarScanner?.stop()
            menuBarScanner = nil
            menuBarSeparator?.remove()
            menuBarSeparator = nil
            menuBarItems = []
            hiddenMenuBarItems = []
            menuBarShowsAll = false
        }
    }

    /// Asks macOS for Accessibility and starts once it's granted, while the person is in System Settings.
    func requestMenuBarAccess() {
        MenuBarScanner.requestTrust()
        menuBarTrustTask?.cancel()
        menuBarTrustTask = Task { [weak self] in
            for _ in 0..<300 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if MenuBarScanner.isTrusted { self?.updateMenuBar(); return }
            }
        }
    }

    /// When the notch opens: where the items are now, and which of them are hidden.
    func refreshMenuBar() {
        guard let menuBarScanner else { return }
        recomputeHiddenMenuBarItems()
        menuBarScanner.refresh()
    }

    private func recomputeHiddenMenuBarItems() {
        guard let screen = notchScreen?() else { return }
        // The closed notch's band on the menu bar: the camera, and the wings when something is live.
        let half = max(geometry.compactWidth, notchWidth) / 2
        let windows = MenuBarScanner.windows(on: screen)
        let hidden = MenuBarLayout.hidden(menuBarItems, windows: windows,
                                          covered: (screen.frame.midX - half)...(screen.frame.midX + half),
                                          screen: screen.frame.minX...screen.frame.maxX)
        if hidden != hiddenMenuBarItems { hiddenMenuBarItems = hidden }
        if hidden.isEmpty { menuBarShowsAll = false }
        if menuBarExactIcons { menuBarImages.capture(hidden, windows: windows) }
    }

    /// The band a live activity's wings cover on the notch's menu bar: what the divider hides at first.
    private func coveredMenuBar() -> (screen: NSScreen, band: ClosedRange<CGFloat>)? {
        guard let screen = notchScreen?() else { return nil }
        let half = notchWidth / 2 + NotchGeometry.maximumWingWidth
        return (screen, (screen.frame.midX - half)...(screen.frame.midX + half))
    }

    /// Opens the item's menu, as a click on it would. The notch closes first: the menu opens beneath it.
    /// An item pushed off the menu bar would open its menu off the screen: the hidden items come back first.
    func pressMenuBarItem(_ item: MenuBarItem) {
        close()
        menuBarSeparator?.show()
        let scanner = menuBarScanner
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            scanner?.press(item.id)
        }
    }
    /// Shows the hidden items and the divider in the menu bar for a while, to ⌘-drag them across it.
    func rearrangeMenuBar() {
        close()
        menuBarSeparator?.rearrange()
    }
    func showAllMenuBarItems() {
        menuBarShowsAll = true
        selectContent()
        onLayoutChange?()
    }

    // MARK: Open With

    /// Files waiting for the person to pick the app that opens them, shown in the notch.
    struct AppChoice: Equatable {
        var urls: [URL]
        /// The apps that open every file, the default first.
        var apps: [URL]
        var preferred: URL?
    }
    private(set) var appChoice: AppChoice?

    /// Opens the notch on the apps that open these files, in place of a menu.
    func chooseApp(for urls: [URL]) {
        guard !urls.isEmpty else { return }
        endGreeting()
        hoverTask?.cancel()
        hover.reset()
        let found = FileMenus.apps(toOpen: urls)
        appChoice = AppChoice(urls: urls, apps: found.apps, preferred: found.preferred)
        selectContent()
        onLayoutChange?()
    }
    /// Opens the files with `app`, or with nil asks for any app in an open panel.
    func openChosen(with app: URL?) {
        guard let choice = appChoice else { return }
        dismissAppChoice()
        if let app { FileMenus.open(choice.urls, with: app) } else { FileMenus.chooseOtherApp(for: choice.urls) }
    }
    func dismissAppChoice() {
        guard appChoice != nil else { return }
        appChoice = nil
        suppressHover = pointerInside
        selectContent()
        onLayoutChange?()
    }

    /// Natural content widths of Home's tiles, measured by the view.
    private var tileContentWidths: [SurfaceKey: CGFloat] = [:]
    func measureTile(_ key: SurfaceKey, width: CGFloat) {
        guard abs(width - (tileContentWidths[key] ?? 0)) >= 0.5 else { return }
        tileContentWidths[key] = width
    }
    /// Each Home tile's size: the extension's or the default, made wide when
    /// its content can't fit one column at the fixed type size.
    var homeTileSizes: [TileSize] {
        platform.homeTiles.map { item in
            let size = platform.tileSize(of: item)
            guard size == .small, platform.homePreferences.sizes[item.key.id] == nil, let natural = tileContentWidths[item.key],
                  natural > HomeLayout.cellWidth - 2 * HomeTile.inset else { return size }
            return .wide
        }
    }
    var homeArrangement: HomeArrangement { HomeLayout.arrange(homeTileSizes) }
    /// The tile the arrow keys are on. Nil until a key is pressed, so the mouse never sees a focus ring.
    private(set) var homeFocus: Int?
    /// Home lists every activity as chips instead of the grid (the More tile).
    var homeShowsAll = false
    /// Arrow keys and Return in Home. False when Home isn't showing the grid, so the key goes on.
    func handleHomeKey(_ key: HomeKey) -> Bool {
        guard showsHome, !homeShowsAll else { return false }
        let arrangement = homeArrangement
        switch key {
        case .move(let direction):
            guard let next = arrangement.neighbor(of: homeFocus ?? -1, direction) else { return homeFocus != nil }
            homeFocus = next
        case .activate:
            guard let focus = homeFocus, arrangement.placements.indices.contains(focus) else { return false }
            if arrangement.hiddenCount > 0 && focus == arrangement.placements.count - 1 { homeShowsAll = true; homeFocus = nil }
            else if platform.homeTiles.indices.contains(focus) { open(platform.homeTiles[focus].key) }
        }
        return true
    }
    var onOpenHomeSettings: (() -> Void)?
    /// Changes the user's Home order, pins, hidden tiles or sizes, and keeps them.
    func editHome(_ change: (inout HomePreferences) -> Void) {
        var preferences = platform.homePreferences
        change(&preferences)
        guard preferences != platform.homePreferences else { return }
        platform.homePreferences = preferences
        if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "homePreferences") }
        homeFocus = nil
        onLayoutChange?()
    }
    private func resetHomeKeys() { homeFocus = nil; homeShowsAll = false }
    /// The wider compact wing's natural content width, measured by the view.
    private(set) var wingContentWidth: CGFloat = 0
    func measureWings(_ width: CGFloat) {
        guard abs(width - wingContentWidth) >= 0.5 else { return }
        wingContentWidth = width
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
        problems.onUnseenCrash = { [weak self] crash in
            // Extension processes' crashes already show on their pages.
            if crash.process == "NotchNotch" { self?.greet("NotchNotch restarted after a crash", for: 5) }
        }
        problems.start()
        reloadExtensions()
        if ProcessInfo.processInfo.environment["NOTCHNOTCH_DEV"] == "1" {
            reloadTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadExtensions() }
            }
        }
        // One wakeup a second, however many extensions run: it checks every
        // runner and looks for `notchnotch dev` projects (one directory listing).
        // Each wakeup of the main thread costs far more than this work.
        let liveness = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.connections.values.forEach { $0.checkLiveness() }
                self?.checkDevelopment()
            }
        }
        liveness.tolerance = 0.5
        RunLoop.main.add(liveness, forMode: .common)
        livenessTimer = liveness
        // Store updates: shortly after launch, then every six hours.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            await self?.checkStoreUpdates()
        }
        // Formerly included extensions come back sooner than the update check.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.installMovedExtensions()
        }
        let storeTimer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.installMovedExtensions(); await self?.checkStoreUpdates() } }
        }
        storeTimer.tolerance = 600
        RunLoop.main.add(storeTimer, forMode: .common)
        storeUpdateTimer = storeTimer
    }

    /// Where Store screenshots of `record` go: its project's `metadata/` when
    /// `notchnotch dev` runs it, otherwise a folder on the Desktop.
    func screenshotFolder(for record: InstalledExtension) -> URL {
        if let source = developmentEntries.first(where: { $0.id == record.id })?.source {
            return source.appendingPathComponent("metadata", isDirectory: true)
        }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return desktop.appendingPathComponent("\(record.manifest.name) Screenshots", isDirectory: true)
    }
    func captureScreenshots(_ record: InstalledExtension) throws -> [URL] {
        try StoreScreenshot.capture(platform.surfaces, record: record, into: screenshotFolder(for: record))
    }

    /// Loads, reloads after a rebuild, and unloads `notchnotch dev` projects.
    private func checkDevelopment() {
        for id in developmentRegistry.screenshotRequests() {
            guard let record = installedExtensions.first(where: { $0.id == id && $0.origin == .development }) else {
                developmentRegistry.finishScreenshots(id: id, files: [], error: "\(id) isn’t running in NotchNotch. Run notchnotch dev first.")
                continue
            }
            do { developmentRegistry.finishScreenshots(id: id, files: try captureScreenshots(record), error: nil) }
            catch { developmentRegistry.finishScreenshots(id: id, files: [], error: error.localizedDescription) }
        }
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
        let included = scan.extensions.filter { $0.origin == .bundled }
        if installedIncludedIDs == nil {
            let used = (included.map(\.id) + Self.movedToStore.keys).filter(hasBeenUsed)
            installedIncludedIDs = Self.defaultIncludedIDs.union(used)
        }
        var installedIDs = installedIncludedIDs ?? [], offered = introducedIncludedIDs
        IncludedExtensions.introduce(Self.introducedIDs, available: Set(included.map(\.id)), installed: &installedIDs, offered: &offered)
        if offered != introducedIncludedIDs {
            introducedIncludedIDs = offered
            installedIncludedIDs = installedIDs
        }
        let installed = scan.extensions.filter { $0.origin != .bundled || installedIncludedIDs?.contains($0.id) == true }
        if includedExtensions != included { includedExtensions = included }
        if installedExtensions != installed { installedExtensions = installed }
        if libraryIssues != scan.issues { libraryIssues = scan.issues }
        let candidates = installed.filter { isEnabled($0.id) && !installingIDs.contains($0.id) }
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
                    let promptsBefore = Set(self.platform.surfaces.filter { $0.surface.kind == .prompt }.map(\.key))
                    var changed = false
                    do {
                        // Apply to a copy and keep it only if the notch would look different:
                        // writing `platform` redraws the whole notch.
                        var next = self.platform
                        try next.apply(snapshot, expectedExtensionID: manifest.id, imageHosts: manifest.imageHosts ?? [], allowPeek: !self.isExpanded)
                        if !next.presentsSame(as: self.platform) { self.platform = next; changed = true }
                        self.snapshotRevisions[manifest.id] = snapshot.revision
                        if !self.renderedIDs.contains(manifest.id) { self.renderedIDs.insert(manifest.id) }
                        if self.extensionSettings[manifest.id] != snapshot.settings { self.extensionSettings[manifest.id] = snapshot.settings }
                    }
                    catch { self.errors[manifest.id] = error.localizedDescription; changed = true }
                    // A new question is only drawn in the notch; say it for VoiceOver too.
                    for prompt in self.platform.surfaces where prompt.surface.kind == .prompt && !promptsBefore.contains(prompt.key) {
                        NotchAccessibility.announce("\(manifest.name) asks: \(prompt.surface.title). Open NotchNotch to answer.")
                    }
                    guard changed else { return }
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
                connection.files = files
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
    func hasRendered(_ id: String) -> Bool { renderedIDs.contains(id) }
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
    /// The text of a problem report: versions, extensions, problems, this
    /// session's error lines and recent crashes, with names removed.
    func problemReport() async -> String {
        let lines = installedExtensions.map { record in
            let origin = storeInstalls[record.id] != nil ? "Store" : record.origin.rawValue
            return ProblemReport.ExtensionLine(id: record.id, version: record.manifest.version, origin: origin,
                                               enabled: isEnabled(record.id), error: errors[record.id])
        }
        let recent = extensionLogs.mapValues { $0.filter { $0.level == .error }.suffix(10).map(\.message) }
        return await problems.report(extensions: lines, recentErrors: recent)
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
        renderedIDs.remove(id)
    }
    func reviewInstall(_ folder: URL) async throws -> ExtensionPackage {
        let store = extensionStore
        let package = try await Task.detached(priority: .userInitiated) {
            folder.pathExtension.lowercased() == ExtensionArchive.fileExtension ? try store.inspectArchive(folder) : try store.inspect(folder)
        }.value
        if let existing = (installedExtensions + includedExtensions).first(where: { $0.id == package.id }), !store.isManaged(existing) {
            ExtensionStore.discardStaged(package)
            throw ProtocolError.invalid("\(existing.manifest.name) is included with NotchNotch and cannot be replaced. Use a different extension identifier.")
        }
        return package
    }
    func installExtension(_ package: ExtensionPackage) async throws {
        // Check again at confirmation time; included/development ids cannot be replaced.
        if let existing = (installedExtensions + includedExtensions).first(where: { $0.id == package.id }), !extensionStore.isManaged(existing) {
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

    /// Signs that an extension ran on this Mac before: saved data, an "Always
    /// Allow" grant, or something a capability kept for it.
    private func hasBeenUsed(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: storageURL(for: id).path)
            || !ConnectionGrantStore().grantedConnections(extensionID: id).isEmpty
            || SystemCapabilities.hasSavedData(extensionID: id)
    }

    /// Installs the Store version of formerly included extensions for people who
    /// had them. Runs with every Store check until it succeeds.
    func installMovedExtensions() async {
        // Got from the Store by hand meanwhile: nothing left to do for those.
        for id in Self.movedToStore.keys where isInstalled(id) { installedIncludedIDs?.remove(id) }
        let waiting = Self.movedToStore.filter { id, _ in
            installedIncludedIDs?.contains(id) == true && !isInstalled(id) && !installingIDs.contains(id)
        }
        guard !waiting.isEmpty, let client = store.client else { return }
        await store.open()
        guard let catalog = store.catalog else { return }
        for (id, handle) in waiting.sorted(by: { $0.key < $1.key }) {
            guard let entry = catalog.extensions.first(where: { $0.id == id && $0.handle == handle }),
                  appVersion.map(entry.runs(onApp:)) ?? true else { continue }
            do {
                let file = try await client.download(entry)
                defer { try? FileManager.default.removeItem(at: file) }
                let package = try await reviewInstall(file)
                defer { ExtensionStore.discardStaged(package) }
                try entry.verifyContents(package)
                guard !isInstalled(id) else { continue }
                try await installExtension(package)
                recordInstall(id, storeHandle: handle)
                installedIncludedIDs?.remove(id)
                appendLog(id, "\(entry.manifest.name) now comes from the Store. Installed \(entry.manifest.version).", level: .info)
            } catch {
                appendLog(id, "Couldn’t install \(entry.manifest.name) from the Store: \(error.localizedDescription)", level: .error)
            }
        }
    }

    func isInstalled(_ id: String) -> Bool { installedExtensions.contains { $0.id == id } }
    /// Installed packages and installed included extensions; not `notchnotch dev` projects.
    func canUninstall(_ record: InstalledExtension) -> Bool {
        record.origin == .bundled ? installedIncludedIDs?.contains(record.id) == true : extensionStore.isManaged(record)
    }
    /// Turns on an included extension that waits in the Store.
    func installIncluded(_ id: String) {
        guard includedExtensions.contains(where: { $0.id == id }) else { return }
        installedIncludedIDs = (installedIncludedIDs ?? []).union([id])
        reloadExtensions()
    }

    /// Stops the extension and forgets everything it saved. An installed package
    /// moves to Trash; an included one goes back to the Store.
    func removeExtension(_ record: InstalledExtension) async throws {
        guard canUninstall(record) else { throw ProtocolError.invalid("\(record.manifest.name) can’t be uninstalled.") }
        forgetAccess(record.id)
        SystemCapabilities.forget(extensionID: record.id)
        storeInstalls[record.id] = nil
        try? FileManager.default.removeItem(at: storageURL(for: record.id))
        droppedFiles.removeAll(for: record.id)
        let id = record.id
        let preferences = preferenceStore
        Task.detached {
            try? ExtensionSecretStore().deleteAll(extensionID: id)
            preferences.removeAll(extensionID: id)
        }
        if record.origin == .bundled {
            stopExtension(record.id)
            installedIncludedIDs?.remove(record.id)
            disabledExtensionIDs.remove(record.id)
            UserDefaults.standard.set(disabledExtensionIDs.sorted(), forKey: "disabledExtensionIDs")
            reloadExtensions()
            return
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
        storeUpdateTimer?.invalidate()
        livenessTimer?.invalidate()
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
        NotchAccessibility.announce(text)
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
        appChoice = nil
        menuBarShowsAll = false
        hoverTask?.cancel()
        hover.reset()
        idlePinned = false
        suppressHover = pointerInside
        platform.close()
        resetHomeKeys()
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
        resetHomeKeys()
        selectContent()
        synchronizePeek()
        onLayoutChange?()
    }
    func openHome() {
        hoverTask?.cancel()
        hover.reset()
        idlePinned = false
        pageDirection = .previous
        platform.openHome()
        resetHomeKeys()
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
        guard !platform.isExpanded, !idlePinned, !isPeeking, !suppressHover, dropSession == nil, appChoice == nil else { return }
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
        if let surface = platform.peeking?.surface, let text = surface.peek?.text { NotchAccessibility.announce(text) }
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

/// A key Home answers.
enum HomeKey { case move(HomeDirection), activate }
