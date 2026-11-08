import Foundation

/// Persistent "Always Allow" decisions for extension connections.
///
/// A grant is bound to the connection's fingerprint, so a changed endpoint,
/// argument list or rebuilt helper binary asks again. Denials are never stored.
public struct ConnectionGrantStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "connectionGrants.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var all: [String: [String: String]] {
        defaults.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
    }
    private func write(_ value: [String: [String: String]]) {
        if value.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(value, forKey: key) }
    }

    public func isGranted(extensionID: String, connectionID: String, fingerprint: String) -> Bool {
        all[extensionID]?[connectionID] == fingerprint
    }

    public func grant(extensionID: String, connectionID: String, fingerprint: String) {
        var value = all
        value[extensionID, default: [:]][connectionID] = fingerprint
        write(value)
    }

    /// Connection identifiers with a stored grant for this extension.
    public func grantedConnections(extensionID: String) -> [String] {
        (all[extensionID] ?? [:]).keys.sorted()
    }

    public func revoke(extensionID: String) {
        var value = all
        value.removeValue(forKey: extensionID)
        write(value)
    }

    public func revokeAll() { defaults.removeObject(forKey: key) }
}
