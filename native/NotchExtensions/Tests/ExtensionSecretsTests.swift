import Foundation
import Testing
import NotchProtocol
@testable import NotchExtensions

@Test func secretsRoundTripPerExtensionAndAreDeletedTogether() throws {
    let store = ExtensionSecretStore(servicePrefix: "NotchNotchTests-\(UUID().uuidString)")
    defer { try? store.deleteAll(extensionID: "dev.test.one"); try? store.deleteAll(extensionID: "dev.test.two") }
    do { try store.set(extensionID: "dev.test.one", key: "token", value: "first") } catch {
        // Some CI machines have no unlocked login Keychain; the API is the same everywhere else.
        return
    }
    #expect(try store.value(extensionID: "dev.test.one", key: "token") == "first")
    try store.set(extensionID: "dev.test.one", key: "token", value: "second")
    #expect(try store.value(extensionID: "dev.test.one", key: "token") == "second")
    try store.set(extensionID: "dev.test.one", key: "refresh", value: "r")
    #expect(try store.keys(extensionID: "dev.test.one") == ["refresh", "token"])

    #expect(try store.value(extensionID: "dev.test.two", key: "token") == nil)
    try store.set(extensionID: "dev.test.two", key: "token", value: "other")

    try store.delete(extensionID: "dev.test.one", key: "refresh")
    #expect(try store.keys(extensionID: "dev.test.one") == ["token"])
    try store.deleteAll(extensionID: "dev.test.one")
    #expect(try store.keys(extensionID: "dev.test.one").isEmpty)
    #expect(try store.value(extensionID: "dev.test.two", key: "token") == "other")
}

@Test func secretRequestsAreBounded() throws {
    try SecretRequest(key: "api-token.v2_main", value: "x").validate(requiresValue: true)
    try SecretRequest(key: "token").validate(requiresValue: false)
    for key in ["", "has space", "slash/key", String(repeating: "k", count: 65)] {
        #expect(throws: ProtocolError.self, "\(key)") { try SecretRequest(key: key, value: "x").validate(requiresValue: true) }
    }
    #expect(throws: ProtocolError.self) { try SecretRequest(key: "token").validate(requiresValue: true) }
    #expect(throws: ProtocolError.self) {
        try SecretRequest(key: "token", value: String(repeating: "v", count: SecretRequest.maximumValueBytes + 1)).validate(requiresValue: true)
    }
}
