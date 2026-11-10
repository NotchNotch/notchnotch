import CryptoKit
import Foundation
import Testing
import NotchProtocol
@testable import NotchExtensions

private let key = Curve25519.Signing.PrivateKey()
private let now = ISO8601DateFormatter().date(from: "2026-11-10T12:00:00Z")!

private func entry(_ handle: String = "amir/focus", id: String = "dev.amir.focus", version: String = "1.0.0",
                   author: String? = nil, sha256: String = String(repeating: "a", count: 64), extra: String = "") -> String {
    let author = author ?? String(handle.split(separator: "/")[0])
    return #"""
    {"handle":"\#(handle)","published":"2026-11-01T00:00:00Z",
     "manifest":{"id":"\#(id)","name":"Focus","version":"\#(version)","apiVersion":1,"entry":"bundle.js","permissions":[],"author":"\#(author)"},
     "package":{"url":"https://github.com/sadeqi-ah/notchnotch-extensions/releases/download/x/focus.notchext","sha256":"\#(sha256)","size":4}\#(extra)}
    """#
}

private func catalog(sequence: Int = 3, expires: String = "2026-12-10T00:00:00Z", entries: [String] = [entry()]) -> Data {
    Data(#"{"format":1,"sequence":\#(sequence),"generated":"2026-11-10T00:00:00Z","expires":"\#(expires)","extensions":[\#(entries.joined(separator: ","))]}"#.utf8)
}

private func signature(_ data: Data, with signer: Curve25519.Signing.PrivateKey = key) throws -> Data {
    Data(try signer.signature(for: data).base64EncodedString().utf8)
}

private func verify(_ data: Data, signature sig: Data? = nil, lastSequence: Int? = nil) throws -> ExtensionCatalog {
    try ExtensionCatalog.verify(data, signature: sig ?? signature(data), keys: [key.publicKey], now: now, lastSequence: lastSequence)
}

private func failure(_ body: () throws -> Any) -> ExtensionCatalog.Failure? {
    do { _ = try body(); return nil } catch { return error as? ExtensionCatalog.Failure }
}

@Test func aCatalogSignedByNodeVerifies() throws {
    // Made by scripts/catalog.mjs with a throwaway key, so the JS signer and CryptoKit agree.
    let body = Data(#"{"format":1,"sequence":7,"generated":"2026-11-10T00:00:00Z","expires":"2027-11-10T00:00:00Z","extensions":[]}"#.utf8)
    let sig = Data("0CzlJPhPUt8Zghw3nMyT8j9E9+QkeFF624ikZcfwQ7ZdsBMgyybhxR9blYjYeJwD/js03QJ8+kK9SDz3v3GKBA==\n".utf8)
    let publicKey = try #require(ExtensionCatalog.publicKey(base64: "5YmWFd43lD3pwDWVm8gv76KcidUMVnN/x8Zq40GXCDg=\n"))
    let result = try ExtensionCatalog.verify(body, signature: sig, keys: [publicKey], now: now)
    #expect(result.sequence == 7)
    #expect(result.extensions.isEmpty)
}

@Test func aValidCatalogDecodesItsEntries() throws {
    let result = try verify(catalog(entries: [entry(), entry("sara/clock", id: "dev.sara.clock", version: "2.1")]))
    #expect(result.extensions.map(\.handle) == ["amir/focus", "sara/clock"])
    #expect(result.entry(handle: "sara/clock")?.author == "sara")
    #expect(result.entry(id: "dev.amir.focus")?.manifest.version == "1.0.0")
}

@Test func anyChangeToTheSignedBytesIsRejected() throws {
    let data = catalog()
    let sig = try signature(data)
    var tampered = data
    tampered[tampered.count - 3] = UInt8(ascii: " ")
    #expect(failure { try verify(tampered, signature: sig) } == .badSignature)
    #expect(failure { try verify(data, signature: signature(data, with: Curve25519.Signing.PrivateKey())) } == .badSignature)
    #expect(failure { try verify(data, signature: Data("not base64".utf8)) } == .badSignature)
    #expect(failure { try verify(data, signature: Data()) } == .badSignature)
}

@Test func anExpiredOrReplayedCatalogIsRejected() throws {
    #expect(failure { try verify(catalog(expires: "2026-11-10T11:00:00Z")) } == .expired(ISO8601DateFormatter().date(from: "2026-11-10T11:00:00Z")!))
    #expect(failure { try verify(catalog(sequence: 3), lastSequence: 4) } == .rolledBack(sequence: 3, last: 4))
    #expect(try verify(catalog(sequence: 4), lastSequence: 4).sequence == 4)
}

@Test func entriesThatCouldMisleadTheAppAreRejected() throws {
    let bad: [(String, String)] = [
        (entry("Amir/focus"), "handle"),
        (entry("amir/focus/extra"), "handle"),
        (entry(author: "sara"), "author"),
        (entry(sha256: "ABC"), "hash"),
        (entry(extra: #","icon":"http://example.com/icon.png""#), "https"),
        (entry(extra: #","screenshots":["https://a.example/1","https://a.example/2","https://a.example/3","https://a.example/4","https://a.example/5","https://a.example/6","https://a.example/7"]"#), "screenshots"),
        (entry(extra: #","minimumAppVersion":"next""#), "minimumAppVersion"),
        (entry(id: "Bad ID"), "manifest"),
    ]
    for (index, (json, reason)) in bad.enumerated() {
        let error = failure { try verify(catalog(entries: [json])) }
        guard case .invalid(let message) = error else { Issue.record("case \(index) passed: \(String(describing: error))"); continue }
        #expect(message.contains(reason) || reason == "manifest", "case \(index): \(message)")
    }
    let twice = failure { try verify(catalog(entries: [entry(), entry("amir/other")])) }
    #expect(twice == .invalid("amir/other is listed twice"))
    let future = Data(#"{"format":2,"sequence":1,"generated":"2026-11-10T00:00:00Z","expires":"2026-12-10T00:00:00Z","extensions":[]}"#.utf8)
    #expect(failure { try verify(future) } == .invalid("format 2 isn’t supported; update NotchNotch"))
    #expect(failure { try verify(Data("[]".utf8)) } == .invalid("it isn’t a catalog"))
}

@Test func versionsCompareByNumberNotText() throws {
    let result = try verify(catalog(entries: [entry(version: "1.10.0", extra: #","minimumAppVersion":"0.7""#)]))
    let item = try #require(result.extensions.first)
    #expect(item.isNewer(than: "1.9.3"))
    #expect(!item.isNewer(than: "1.10"))
    #expect(!item.isNewer(than: "2.0.0"))
    #expect(item.runs(onApp: "0.7.0"))
    #expect(item.runs(onApp: "0.10.0"))
    #expect(!item.runs(onApp: "0.6.9"))
}

@Test func onlyTheReviewedPackageIsAccepted() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-catalog-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("focus.notchext")
    try Data("PK!!".utf8).write(to: file)
    let digest = SHA256.hash(data: Data("PK!!".utf8)).map { String(format: "%02x", $0) }.joined()

    let good = try #require(verify(catalog(entries: [entry(sha256: digest)])).extensions.first)
    try good.verifyDownload(file)
    let wrongHash = try #require(verify(catalog(entries: [entry()])).extensions.first)
    #expect(failure { try wrongHash.verifyDownload(file) } == .packageMismatch("its SHA-256 differs"))
    try Data("PK!!!".utf8).write(to: file)
    #expect(failure { try good.verifyDownload(file) } == .packageMismatch("its size is 5 bytes, not 4"))
}
