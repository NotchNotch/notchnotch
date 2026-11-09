import Foundation
import NotchProtocol

/// Values of the preferences extensions declare in their manifest. Text,
/// toggles and dropdowns live in the app's preferences; passwords live in the
/// Keychain, with only a "set" marker in the app's preferences so the app can
/// tell whether a required password is filled in without reading the Keychain.
public struct ExtensionPreferenceStore: Sendable {
    private let defaultsKey: String
    private let secrets: ExtensionSecretStore

    public init() {
        defaultsKey = "extensionPreferences"
        secrets = ExtensionSecretStore(servicePrefix: "NotchNotch preferences")
    }
    init(defaultsKey: String, servicePrefix: String) {
        self.defaultsKey = defaultsKey
        secrets = ExtensionSecretStore(servicePrefix: servicePrefix)
    }

    private struct Entry: Codable {
        var values: [String: JSONValue] = [:]
        var passwordsSet: Set<String> = []
    }

    private func entries() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return entries
    }

    private func write(_ entries: [String: Entry]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: defaultsKey)
    }

    /// Stored values without reading the Keychain: a set password appears as a
    /// non-empty placeholder. Fast enough for the main thread.
    public func summary(for manifest: ExtensionManifest) -> [String: JSONValue] {
        let entry = entries()[manifest.id] ?? Entry()
        var values = entry.values
        for preference in manifest.preferences ?? [] where preference.type == .password {
            values[preference.name] = entry.passwordsSet.contains(preference.name) ? .string("•") : nil
        }
        return manifest.preferenceValues(stored: values)
    }

    /// Every value the extension receives, passwords included. Reads the
    /// Keychain, so call it off the main thread.
    public func values(for manifest: ExtensionManifest) -> [String: JSONValue] {
        var values = entries()[manifest.id]?.values ?? [:]
        for preference in manifest.preferences ?? [] where preference.type == .password {
            values[preference.name] = (try? secrets.value(extensionID: manifest.id, key: preference.name)).flatMap { $0 }.map(JSONValue.string)
        }
        return manifest.preferenceValues(stored: values)
    }

    /// Saves the given values; a password set to "" is removed. Values for
    /// names the manifest doesn't declare, or of the wrong kind, are ignored.
    public func save(_ changes: [String: JSONValue], for manifest: ExtensionManifest) throws {
        var all = entries()
        var entry = all[manifest.id] ?? Entry()
        for preference in manifest.preferences ?? [] {
            guard let value = changes[preference.name], preference.accepts(value) else { continue }
            if preference.type == .password, case let .string(text) = value {
                if text.isEmpty {
                    try secrets.delete(extensionID: manifest.id, key: preference.name)
                    entry.passwordsSet.remove(preference.name)
                } else {
                    try secrets.set(extensionID: manifest.id, key: preference.name, value: text)
                    entry.passwordsSet.insert(preference.name)
                }
            } else {
                entry.values[preference.name] = value
            }
        }
        all[manifest.id] = entry
        write(all)
    }

    /// Forgets everything for an extension, for example when it is removed.
    public func removeAll(extensionID: String) {
        var all = entries()
        all.removeValue(forKey: extensionID)
        write(all)
        try? secrets.deleteAll(extensionID: extensionID)
    }
}
