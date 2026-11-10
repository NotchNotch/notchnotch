import Foundation
import Testing
import NotchProtocol
@testable import NotchExtensions

private func manifest(_ extra: String, permissions: String = "[]") throws -> ExtensionManifest {
    try JSONDecoder().decode(ExtensionManifest.self, from: Data("""
    {"id":"dev.test.perm","name":"Perm","version":"1","apiVersion":1,"entry":"bundle.js","permissions":\(permissions)\(extra)}
    """.utf8))
}

@Test func anExtensionThatAsksForNothingHasNoItems() throws {
    let empty = try manifest("")
    #expect(PermissionSummary.items(for: empty).isEmpty)
}

@Test func itemsAreOrderedByRiskWithPlainDetails() throws {
    let full = try manifest(#"""
    ,"network":["api.example.com"],"imageHosts":["img.example.com"],
    "connections":{"tool":{"transport":"stdio","executable":"./helpers/tool","arguments":["--watch"]},
                   "api":{"transport":"http","endpoint":"http://127.0.0.1:4277"}},
    "preferences":[{"name":"token","type":"password","title":"API Token"},{"name":"city","type":"text","title":"City"}]
    """#, permissions: #"["process","local-network"]"#)
    let items = PermissionSummary.items(for: full)
    #expect(items.map(\.kind) == [.runPrograms, .internet, .localApps, .pictures, .settings])
    #expect(items[0].details.map(\.text) == ["./helpers/tool --watch"])
    #expect(items[2].details.map(\.text) == ["http://127.0.0.1:4277"])
    #expect(items[4].details.map(\.text) == ["API Token (kept in your Keychain)", "City"])
    #expect(items.allSatisfy { !$0.isNew }, "nothing is new on a first install")
}

@Test func anUpdateMarksOnlyWhatTheInstalledVersionDidNotHave() throws {
    let installed = try manifest(#","network":["api.example.com"]"#)
    let update = try manifest(#","network":["api.example.com","collect.example.net"],"imageHosts":["img.example.com"]"#)
    let items = PermissionSummary.items(for: update, comparedTo: installed)
    let internet = try #require(items.first { $0.kind == .internet })
    #expect(internet.details == [.init(text: "api.example.com", isNew: false), .init(text: "collect.example.net", isNew: true)])
    #expect(items.first { $0.kind == .pictures }?.isNew == true)
    #expect(PermissionSummary.items(for: installed, comparedTo: installed).allSatisfy { !$0.isNew })
}
