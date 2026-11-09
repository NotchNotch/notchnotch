import Foundation
import Testing
import NotchProtocol
@testable import NotchExtensions

private func manifest(_ preferences: String) throws -> ExtensionManifest {
    try JSONDecoder().decode(ExtensionManifest.self, from: Data("""
    {"id":"dev.test.prefs","name":"Prefs","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[],"preferences":\(preferences)}
    """.utf8))
}

private let weather = #"""
[{"name":"apiToken","type":"password","title":"API Token","required":true},
 {"name":"city","type":"text","title":"City","default":"Paris"},
 {"name":"units","type":"dropdown","title":"Units","default":"metric","options":[{"value":"metric","title":"Metric"},{"value":"imperial","title":"Imperial"}]},
 {"name":"showWind","type":"toggle","title":"Show Wind"}]
"""#

@Test func preferencesAreValidatedLikeTheCLI() throws {
    try manifest(weather).validate()
    for invalid in [
        #"[{"name":"x","type":"password","title":"X","default":"s"}]"#,
        #"[{"name":"x","type":"toggle","title":"X","required":true}]"#,
        #"[{"name":"x","type":"dropdown","title":"X","options":[]}]"#,
        #"[{"name":"x","type":"dropdown","title":"X","default":"z","options":[{"value":"a","title":"A"}]}]"#,
        #"[{"name":"1x","type":"text","title":"X"}]"#,
        #"[{"name":"x","type":"text","title":"X"},{"name":"x","type":"text","title":"Y"}]"#,
        #"[{"name":"x","type":"text","title":"X","options":[{"value":"a","title":"A"}]}]"#,
        #"[{"name":"x","type":"text","title":""}]"#,
    ] {
        #expect(throws: ProtocolError.self, "\(invalid)") { try manifest(invalid).validate() }
    }
}

@Test func valuesFillDefaultsDropStrangersAndReportMissingRequiredOnes() throws {
    let manifest = try manifest(weather)
    #expect(manifest.preferenceValues(stored: [:]) == ["city": .string("Paris"), "units": .string("metric")])
    #expect(manifest.missingRequiredPreferences(stored: [:]) == ["API Token"])
    #expect(manifest.missingRequiredPreferences(stored: ["apiToken": .string("  ")]) == ["API Token"])
    let values = manifest.preferenceValues(stored: ["apiToken": .string("t"), "units": .string("kelvin"), "unknown": .string("x"), "showWind": .bool(true)])
    #expect(values == ["apiToken": .string("t"), "city": .string("Paris"), "units": .string("metric"), "showWind": .bool(true)])
    #expect(manifest.missingRequiredPreferences(stored: ["apiToken": .string("t")]).isEmpty)
}

@Test func theStoreKeepsPasswordsInTheKeychainAndOnlyAMarkerInPreferences() throws {
    let key = "test.extensionPreferences.\(UUID().uuidString)"
    let store = ExtensionPreferenceStore(defaultsKey: key, servicePrefix: "NotchNotchTests-\(UUID().uuidString)")
    let manifest = try manifest(weather)
    defer { store.removeAll(extensionID: manifest.id); UserDefaults.standard.removeObject(forKey: key) }

    do { try store.save(["apiToken": .string("secret"), "city": .string("Rome")], for: manifest) } catch {
        return // No unlocked login Keychain on this machine.
    }
    #expect(store.summary(for: manifest)["apiToken"] == .string("•"))
    #expect(store.values(for: manifest)["apiToken"] == .string("secret"))
    #expect(store.values(for: manifest)["city"] == .string("Rome"))
    let defaults = String(decoding: UserDefaults.standard.data(forKey: key) ?? Data(), as: UTF8.self)
    #expect(!defaults.contains("secret"), "the password must not be in the app's preferences")

    try store.save(["apiToken": .string("")], for: manifest)
    #expect(store.values(for: manifest)["apiToken"] == nil)
    #expect(manifest.missingRequiredPreferences(stored: store.summary(for: manifest)) == ["API Token"])
}
