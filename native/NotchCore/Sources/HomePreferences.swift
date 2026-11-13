import NotchProtocol

/// What the user changed about Home: the order of activities, which are
/// pinned first, which are hidden, and a size in place of the automatic one.
/// Keyed by `SurfaceKey.id`, so it outlives an extension's restart.
public struct HomePreferences: Codable, Equatable, Sendable {
    /// The user's order, highest first. It also decides which live activity
    /// takes the wings; activities not in it follow, the most recent first.
    public var order: [String] = []
    /// Shown first in Home, whether live or not.
    public var pinned: Set<String> = []
    /// Left out of Home. The wings still show them while they're live.
    public var hidden: Set<String> = []
    /// A size the user chose; without one Home decides.
    public var sizes: [String: TileSize] = [:]

    public init() {}

    func rank(_ key: SurfaceKey) -> Int { order.firstIndex(of: key.id) ?? order.count }

    /// Takes `keys` as the new order, keeping activities that aren't running now after them.
    public mutating func reorder(_ keys: [SurfaceKey]) {
        let ids = keys.map(\.id)
        order = ids + order.filter { !ids.contains($0) }
    }

    public mutating func setPinned(_ pinned: Bool, _ key: SurfaceKey) {
        if pinned { self.pinned.insert(key.id) } else { self.pinned.remove(key.id) }
    }

    public mutating func setHidden(_ hidden: Bool, _ key: SurfaceKey) {
        if hidden { self.hidden.insert(key.id); pinned.remove(key.id) } else { self.hidden.remove(key.id) }
    }

    /// Nil returns the tile to the automatic size.
    public mutating func setSize(_ size: TileSize?, _ key: SurfaceKey) {
        sizes[key.id] = size == .unknown ? nil : size
    }
}
