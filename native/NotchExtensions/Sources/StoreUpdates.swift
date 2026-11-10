import Foundation

/// Which Store updates install on their own and which wait for the user.
///
/// Only extensions installed from the Store update automatically, and only
/// when the new version asks for nothing the installed one couldn't do: a
/// new website, program, local app, picture host or setting means the user
/// reviews it first, as the install review would mark it New. That's the
/// moment an extension someone already trusts could start asking for more.
public enum StoreUpdates {
    public struct Plan: Equatable, Sendable {
        public var automatic: [ExtensionCatalog.Entry] = []
        public var needsReview: [ExtensionCatalog.Entry] = []
    }

    /// - Parameters:
    ///   - storeInstalls: extension id → the Store handle it was installed from.
    ///   - appVersion: this app's version; nil counts as new enough.
    public static func plan(_ catalog: ExtensionCatalog, installed: [InstalledExtension],
                            storeInstalls: [String: String], appVersion: String?) -> Plan {
        var plan = Plan()
        for entry in catalog.extensions {
            guard let record = installed.first(where: { $0.id == entry.id }), record.origin == .local,
                  storeInstalls[entry.id] == entry.handle, entry.isNewer(than: record.manifest.version),
                  appVersion.map(entry.runs(onApp:)) ?? true else { continue }
            let asksForMore = PermissionSummary.items(for: entry.manifest, comparedTo: record.manifest).contains(where: \.isNew)
            if asksForMore { plan.needsReview.append(entry) } else { plan.automatic.append(entry) }
        }
        return plan
    }
}
