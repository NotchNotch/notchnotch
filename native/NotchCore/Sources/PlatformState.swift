import Foundation
import NotchProtocol

public struct SurfaceKey: Hashable, Sendable, Identifiable {
    public let extensionID: String
    public let surfaceID: String
    public var id: String { "\(extensionID)/\(surfaceID)" }
    public init(extensionID: String, surfaceID: String) { self.extensionID = extensionID; self.surfaceID = surfaceID }
}

public struct HostedSurface: Identifiable, Equatable, Sendable {
    public let key: SurfaceKey
    public var surface: Surface
    public var id: SurfaceKey { key }
}

public enum NotchPresentation: Sendable { case idle, compact, hovered, peek, expanded }

public struct ActivePeek: Equatable, Sendable {
    public let key: SurfaceKey
    public let eventID: String
    public let expiresAt: Date
}

/// Presentation is host-owned. Closing a panel never resolves an extension's prompt.
public struct PlatformState: Sendable {
    public private(set) var surfaces: [HostedSurface] = []
    public private(set) var selection: SurfaceKey?
    public private(set) var isExpanded = false
    /// The expanded notch shows Home, the grid of every activity, instead of one surface.
    public private(set) var showsHome = false
    public private(set) var activePeek: ActivePeek?
    private var compactSelection: SurfaceKey?
    private var revisions: [String: Int] = [:]
    private var consumedPeeks: [SurfaceKey: String] = [:]
    private var recentActivities: [SurfaceKey] = []
    /// The user's order, pins, hidden tiles and sizes for Home.
    public var homePreferences = HomePreferences()
    /// Each extension's drop zones, from its last snapshot.
    public private(set) var dropZones: [String: [DropZone]] = [:]

    public init() {}

    /// Whether `other` would draw the same notch. Revisions are left out: they
    /// change with every snapshot, while most snapshots change nothing visible
    /// (a ticking Settings page, a re-render with the same tree). The app
    /// compares before storing so those cost no redraw.
    public func presentsSame(as other: PlatformState) -> Bool {
        surfaces == other.surfaces && selection == other.selection && isExpanded == other.isExpanded &&
            showsHome == other.showsHome &&
            activePeek == other.activePeek && compactSelection == other.compactSelection &&
            consumedPeeks == other.consumedPeeks && recentActivities == other.recentActivities &&
            homePreferences == other.homePreferences && dropZones == other.dropZones
    }

    public var presentation: NotchPresentation {
        if isExpanded { return .expanded }
        if activePeek != nil { return .peek }
        return compact != nil || pendingCount > 0 ? .compact : .idle
    }
    public var selected: HostedSurface? { surfaces.first { $0.key == selection } }
    public var peeking: HostedSurface? { surfaces.first { $0.key == activePeek?.key } }
    public var compact: HostedSurface? {
        // Installed/paused activities remain in the switcher without claiming the notch.
        let visible = surfaces.filter { $0.surface.compact != nil && $0.surface.phase != .paused }
        return peeking
            ?? visible.first { $0.key == compactSelection }
            ?? live.first
            ?? visible.first
    }

    /// Activities that are running now (not paused) and can take the wings:
    /// in the user's order, then the most recently started first.
    public var live: [HostedSurface] {
        let running = surfaces.filter { $0.surface.kind == .activity && $0.surface.compact != nil && $0.surface.phase != .paused }
        func rank(_ item: HostedSurface) -> Int { recentActivities.firstIndex(of: item.key) ?? recentActivities.count }
        return running.enumerated().sorted {
            (homePreferences.rank($0.element.key), rank($0.element), $0.offset) <
                (homePreferences.rank($1.element.key), rank($1.element), $1.offset)
        }.map(\.element)
    }

    /// The live activities beside the one in the wings, shown as small circles.
    public static let maximumMinimals = 3
    public var minimals: [HostedSurface] {
        Array(live.filter { $0.key != compact?.key }.prefix(Self.maximumMinimals))
    }
    /// Live activities with no room in the wings, counted in a `+N` pill.
    public var liveOverflow: Int {
        max(0, live.filter { $0.key != compact?.key }.count - Self.maximumMinimals)
    }

    /// Every activity Home can show, hidden ones too, in the user's order.
    /// Prompts interrupt instead; they are never tiles.
    public var homeActivities: [HostedSurface] {
        surfaces.filter { $0.surface.kind == .activity && ($0.surface.compact != nil || $0.surface.tile != nil) }
            .enumerated()
            .sorted { (homePreferences.rank($0.element.key), $0.offset) < (homePreferences.rank($1.element.key), $1.offset) }
            .map(\.element)
    }

    /// The zones that take these items, in the user's Home order of their
    /// extensions (then by name), each extension's zones in its own order.
    public func dropTargets(for items: [DraggedItem]) -> [DropTarget] {
        let order = homePreferences.order.map { $0.split(separator: "/").first.map(String.init) ?? $0 }
        func rank(_ id: String) -> Int { order.firstIndex(of: id) ?? order.count }
        return dropZones.keys.sorted { (rank($0), $0) < (rank($1), $1) }.flatMap { id in
            (dropZones[id] ?? []).map { DropTarget(extensionID: id, zone: $0) }.filter { $0.accepts(items) }
        }
    }

    /// Home's tiles: pinned ones first, then live activities, then the rest,
    /// each group in the user's order. Hidden ones are left out.
    public var homeTiles: [HostedSurface] {
        let live = live
        func group(_ item: HostedSurface) -> Int {
            if homePreferences.pinned.contains(item.key.id) { return 0 }
            return live.contains { $0.key == item.key } ? 1 : 2
        }
        let ordered = live + homeActivities.filter { item in !live.contains { $0.key == item.key } }
        return ordered.enumerated()
            .filter { !homePreferences.hidden.contains($0.element.key.id) }
            .sorted { (group($0.element), $0.offset) < (group($1.element), $1.offset) }
            .map(\.element)
    }

    /// A tile's size: the user's choice, else what the activity asked for,
    /// else wide while live and small otherwise.
    public func tileSize(of item: HostedSurface) -> TileSize {
        if let chosen = homePreferences.sizes[item.key.id], chosen != .unknown { return chosen }
        switch item.surface.tile?.size {
        case .small?: return .small
        case .wide?: return .wide
        case .unknown?: return .small
        case nil: return live.contains { $0.key == item.key } ? .wide : .small
        }
    }
    public var pendingCount: Int { surfaces.filter { $0.surface.kind == .prompt }.count }

    /// Hover is a deliberate request for context, so it can reveal a paused
    /// activity without letting that activity claim the resting notch.
    public var hoverSurface: HostedSurface? {
        if let compact { return compact }
        if let pending = surfaces.first(where: { $0.surface.kind == .prompt && $0.surface.phase == .pending }) {
            return pending
        }
        for key in recentActivities {
            if let recent = surfaces.first(where: { $0.key == key && $0.surface.compact != nil }) { return recent }
        }
        return surfaces.first { $0.surface.kind == .activity && $0.surface.idlePreview == true && $0.surface.compact != nil }
    }

    public mutating func apply(_ snapshot: Snapshot, expectedExtensionID: String, imageHosts: [String] = [],
                               now: Date = .now, allowPeek: Bool = true) throws {
        try snapshot.validate(expectedExtensionID: expectedExtensionID, imageHosts: imageHosts)
        guard snapshot.revision > revisions[snapshot.extensionID, default: 0] else { return }
        revisions[snapshot.extensionID] = snapshot.revision
        dropZones[snapshot.extensionID] = snapshot.drops?.isEmpty == false ? snapshot.drops : nil
        let oldIDs = Set(surfaces.filter { $0.key.extensionID == snapshot.extensionID }.map(\.key.surfaceID))
        let previousPhases = Dictionary(uniqueKeysWithValues: surfaces.map { ($0.key, $0.surface.phase) })
        let replacements = snapshot.surfaces.map {
            HostedSurface(key: .init(extensionID: snapshot.extensionID, surfaceID: $0.id), surface: $0)
        }
        // Preserve insertion order so ticking snapshots never shuffle the activity switcher.
        var incoming = replacements
        surfaces = surfaces.compactMap { item in
            guard item.key.extensionID == snapshot.extensionID else { return item }
            guard let index = incoming.firstIndex(where: { $0.key == item.key }) else { return nil }
            return incoming.remove(at: index)
        } + incoming
        recentActivities.removeAll { key in !surfaces.contains { $0.key == key } }
        for item in replacements where item.surface.kind == .activity && item.surface.compact != nil &&
            item.surface.phase != .paused && previousPhases[item.key] != item.surface.phase {
            remember(item.key)
        }
        consumedPeeks = consumedPeeks.filter { entry in surfaces.contains { $0.key == entry.key } }
        let announcements = replacements.filter {
            guard $0.surface.phase != .paused, let peek = $0.surface.peek else { return false }
            return consumedPeeks[$0.key] != peek.id
        }
        // A preloaded, paused track has not started its event yet. Active events
        // are consumed even when a panel is open, so closing never replays them.
        for item in replacements where item.surface.phase != .paused {
            if let peek = item.surface.peek { consumedPeeks[item.key] = peek.id }
        }
        if let activePeek, !surfaces.contains(where: {
            $0.key == activePeek.key && $0.surface.peek != nil &&
                ($0.surface.phase != .paused || previousPhases[$0.key] == .paused)
        }) {
            self.activePeek = nil
        }
        if selected == nil && !showsHome { selection = compact?.key; isExpanded = false }
        if !isExpanded, let newcomer = replacements.first(where: {
            !oldIDs.contains($0.surface.id) && $0.surface.initialView == .expanded
        }) {
            selection = newcomer.key
            isExpanded = true
            showsHome = false
            activePeek = nil
        }
        if selection == nil && !showsHome { selection = compact?.key }
        // Consume events while a user is working in a panel; never replay them on close.
        if !isExpanded, allowPeek, let announcement = announcements.last {
            showPeek(for: announcement.key, now: now)
        }
    }

    public mutating func showPeek(for key: SurfaceKey, now: Date = .now) {
        guard let item = surfaces.first(where: { $0.key == key }), let peek = item.surface.peek else { return }
        isExpanded = false
        showsHome = false
        compactSelection = key
        selection = key
        consumedPeeks[key] = peek.id
        remember(key)
        activePeek = .init(key: key, eventID: peek.id, expiresAt: now.addingTimeInterval(peek.duration))
    }

    /// The host schedules this deadline; revisions and progress updates never extend it.
    public mutating func expirePeek(now: Date = .now) {
        guard let activePeek, now >= activePeek.expiresAt else { return }
        self.activePeek = nil
    }

    public mutating func open(_ key: SurfaceKey) {
        guard let item = surfaces.first(where: { $0.key == key }) else { return }
        selection = key
        isExpanded = true
        showsHome = false
        activePeek = nil
        if item.surface.compact != nil { compactSelection = key }
        if item.surface.kind == .activity, item.surface.compact != nil { remember(key) }
    }

    public mutating func toggle() {
        if isExpanded { close() }
        else if let key = hoverSurface?.key { open(key) }
        else { openHome() }
    }

    public mutating func openHome() {
        selection = nil
        isExpanded = true
        showsHome = true
        activePeek = nil
    }

    public mutating func close() {
        isExpanded = false
        showsHome = false
        activePeek = nil
        selection = compact?.key
    }

    public mutating func removeExtension(_ id: String) {
        surfaces.removeAll { $0.key.extensionID == id }
        revisions.removeValue(forKey: id)
        dropZones.removeValue(forKey: id)
        consumedPeeks = consumedPeeks.filter { $0.key.extensionID != id }
        recentActivities.removeAll { $0.extensionID == id }
        if activePeek?.key.extensionID == id { activePeek = nil }
        if selected == nil && !showsHome { selection = compact?.key; isExpanded = false }
    }

    private mutating func remember(_ key: SurfaceKey) {
        recentActivities.removeAll { $0 == key }
        recentActivities.insert(key, at: 0)
    }
}
