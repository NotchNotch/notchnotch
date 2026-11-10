import CryptoKit
import Foundation
import Testing
@testable import NotchExtensions

/// Serves canned responses by URL so the client can be tested without a network.
final class StoreStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: (Int, Data)] = [:]
    static let lock = NSLock()
    static func set(_ url: String, _ status: Int = 200, _ body: Data) { lock.withLock { routes[url] = (status, body) } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.lock.withLock { Self.routes[request.url!.absoluteString] } ?? (404, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private let key = Curve25519.Signing.PrivateKey()

/// Each test uses its own host, so tests running in parallel never share routes.
private struct Fixture {
    let host = "store-\(UUID().uuidString.prefix(8).lowercased()).example"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-store-" + UUID().uuidString)
    var index: String { "https://\(host)/index.json" }

    func client(now: Date = ISO8601DateFormatter().date(from: "2026-11-10T12:00:00Z")!) -> StoreClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StoreStub.self]
        return StoreClient(source: .init(url: URL(string: index)!, keys: [key.publicKey]), directory: directory,
                           session: URLSession(configuration: configuration), now: { now })
    }

    func publish(sequence: Int, expires: String = "2026-12-10T00:00:00Z", package: Data = Data("PK!!".utf8), sha256 override: String? = nil) throws {
        let digest = override ?? SHA256.hash(data: package).map { String(format: "%02x", $0) }.joined()
        let body = Data(#"""
        {"format":1,"sequence":\#(sequence),"generated":"2026-11-10T00:00:00Z","expires":"\#(expires)","extensions":[
         {"handle":"amir/focus","published":"2026-11-01T00:00:00Z",
          "manifest":{"id":"dev.amir.focus","name":"Focus","version":"1.0","apiVersion":1,"entry":"bundle.js","permissions":[],"author":"amir"},
          "package":{"url":"https://\#(host)/focus.notchext","sha256":"\#(digest)","size":\#(package.count)}}]}
        """#.utf8)
        StoreStub.set(index, 200, body)
        StoreStub.set(index + ".sig", 200, Data(try key.signature(for: body).base64EncodedString().utf8))
        StoreStub.set("https://\(host)/focus.notchext", 200, package)
    }
}

@Test func theCatalogIsFetchedVerifiedAndKept() async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let client = fixture.client()
    #expect(await client.cached() == nil)
    try fixture.publish(sequence: 5)
    let catalog = try await client.refresh()
    #expect(catalog.sequence == 5)
    #expect(await client.cached()?.sequence == 5)
    // A fresh client (the next launch) reads the kept copy offline.
    #expect(await fixture.client().cached()?.extensions.first?.handle == "amir/focus")
}

@Test func anOlderCatalogIsRefusedAfterANewerOne() async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let client = fixture.client()
    try fixture.publish(sequence: 5)
    _ = try await client.refresh()
    try fixture.publish(sequence: 4)
    await #expect(throws: ExtensionCatalog.Failure.rolledBack(sequence: 4, last: 5)) { try await client.refresh() }
    #expect(await client.cached()?.sequence == 5)
    // Even after the kept copy expires, its sequence still guards against a replay.
    let later = fixture.client(now: ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z")!)
    #expect(await later.cached() == nil)
    try fixture.publish(sequence: 4, expires: "2027-06-01T00:00:00Z")
    await #expect(throws: ExtensionCatalog.Failure.rolledBack(sequence: 4, last: 5)) { try await later.refresh() }
}

@Test func aBadSignatureOrHTTPErrorLeavesTheKeptCatalogAlone() async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let client = fixture.client()
    try fixture.publish(sequence: 2)
    _ = try await client.refresh()
    StoreStub.set(fixture.index + ".sig", 200, Data(try Curve25519.Signing.PrivateKey().signature(for: Data()).base64EncodedString().utf8))
    await #expect(throws: ExtensionCatalog.Failure.badSignature) { try await client.refresh() }
    StoreStub.set(fixture.index, 503, Data())
    await #expect(throws: StoreClient.Failure.http(503)) { try await client.refresh() }
    #expect(await client.cached()?.sequence == 2)
}

@Test func downloadsMustMatchTheCatalogAndStopAtItsSize() async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let client = fixture.client()
    try fixture.publish(sequence: 1)
    let entry = try #require(try await client.refresh().extensions.first)
    let file = try await client.download(entry)
    #expect(try Data(contentsOf: file) == Data("PK!!".utf8))
    try FileManager.default.removeItem(at: file)

    StoreStub.set("https://\(fixture.host)/focus.notchext", 200, Data("PK??".utf8))
    await #expect(throws: ExtensionCatalog.Failure.packageMismatch("its SHA-256 differs")) { try await client.download(entry) }
    StoreStub.set("https://\(fixture.host)/focus.notchext", 200, Data(repeating: 0, count: 200_000))
    await #expect(throws: StoreClient.Failure.tooLarge) { try await client.download(entry) }
}
