import Foundation
import Testing
import NotchProtocol
@testable import NotchExtensions

private func manifest(_ id: String, _ version: String, network: [String]? = nil) -> String {
    let hosts = network.map { #","network":["# + $0.map { "\"\($0)\"" }.joined(separator: ",") + "]" } ?? ""
    return #"{"id":"\#(id)","name":"X","version":"\#(version)","apiVersion":1,"entry":"bundle.js","permissions":[],"author":"amir"\#(hosts)}"#
}

private func catalog(_ entries: [(handle: String, manifest: String, minimum: String?)]) throws -> ExtensionCatalog {
    let items = entries.map { entry in
        #"{"handle":"\#(entry.handle)","manifest":\#(entry.manifest),"published":"2026-11-01T00:00:00Z","#
        + (entry.minimum.map { #""minimumAppVersion":"\#($0)","# } ?? "")
        + #""package":{"url":"https://example.com/p.notchext","sha256":"\#(String(repeating: "a", count: 64))","size":1}}"#
    }
    let json = #"{"format":1,"sequence":1,"generated":"2026-11-01T00:00:00Z","expires":"2026-12-01T00:00:00Z","extensions":[\#(items.joined(separator: ","))]}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(ExtensionCatalog.self, from: Data(json.utf8))
}

private func installed(_ json: String, origin: ExtensionOrigin = .local) throws -> InstalledExtension {
    InstalledExtension(manifest: try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8)),
                       directory: URL(fileURLWithPath: "/tmp"), origin: origin)
}

@Test func onlyStoreInstallsThatAskForNothingNewUpdateOnTheirOwn() throws {
    let store = try catalog([
        ("amir/same", manifest("dev.amir.same", "1.1", network: ["api.example.com"]), nil),
        ("amir/more", manifest("dev.amir.more", "2.0", network: ["api.example.com", "tracker.example"]), nil),
        ("amir/fewer", manifest("dev.amir.fewer", "1.1"), nil),
    ])
    let local = [
        try installed(manifest("dev.amir.same", "1.0", network: ["api.example.com"])),
        try installed(manifest("dev.amir.more", "1.0", network: ["api.example.com"])),
        try installed(manifest("dev.amir.fewer", "1.0", network: ["api.example.com"])),
    ]
    let handles = ["dev.amir.same": "amir/same", "dev.amir.more": "amir/more", "dev.amir.fewer": "amir/fewer"]
    let plan = StoreUpdates.plan(store, installed: local, storeInstalls: handles, appVersion: "0.7.0")
    #expect(plan.automatic.map(\.handle) == ["amir/same", "amir/fewer"])
    #expect(plan.needsReview.map(\.handle) == ["amir/more"])
}

@Test func extensionsNotFromTheStoreOrNotNewerAreLeftAlone() throws {
    let store = try catalog([
        ("amir/file", manifest("dev.amir.file", "2.0"), nil),
        ("amir/current", manifest("dev.amir.current", "1.0"), nil),
        ("amir/bundled", manifest("dev.amir.bundled", "2.0"), nil),
        ("amir/later", manifest("dev.amir.later", "2.0"), "0.9"),
        ("sara/renamed", manifest("dev.amir.moved", "2.0"), nil),
    ])
    let local = [
        try installed(manifest("dev.amir.file", "1.0")),
        try installed(manifest("dev.amir.current", "1.0")),
        try installed(manifest("dev.amir.bundled", "1.0"), origin: .bundled),
        try installed(manifest("dev.amir.later", "1.0")),
        try installed(manifest("dev.amir.moved", "1.0")),
    ]
    let handles = ["dev.amir.current": "amir/current", "dev.amir.bundled": "amir/bundled",
                   "dev.amir.later": "amir/later", "dev.amir.moved": "amir/moved"]
    let plan = StoreUpdates.plan(store, installed: local, storeInstalls: handles, appVersion: "0.7.0")
    #expect(plan == StoreUpdates.Plan())
    // A build without a version (swift run) counts as new enough.
    #expect(StoreUpdates.plan(store, installed: local, storeInstalls: handles, appVersion: nil).automatic.map(\.handle) == ["amir/later"])
}
