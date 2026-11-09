import Foundation
import Testing
import NotchProtocol
@testable import NotchConnections

/// Answers `fetch` requests in-process, so these tests never reach the internet.
private final class StubInternet: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var authorizationByPath: [String: String] = [:]

    static func authorization(at path: String) -> String? { lock.withLock { authorizationByPath[path] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let client else { return }
        Self.lock.withLock { Self.authorizationByPath[url.path] = request.value(forHTTPHeaderField: "Authorization") ?? "" }
        func respond(_ status: Int, headers: [String: String] = [:], body: Data = Data()) {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
            client.urlProtocolDidFinishLoading(self)
        }
        func redirect(to location: String) {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": location])!
            client.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: location)!), redirectResponse: response)
            // Like the network stack: a refused redirect delivers the 3xx itself.
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(self)
        }
        switch url.path {
        case "/ok": respond(200, headers: ["X-Answer": "42", "Content-Type": "application/json"], body: Data(#"{"hello":"world"}"#.utf8))
        case "/large": respond(200, body: Data(repeating: 0x61, count: maximumFetchBodyBytes + 1))
        case "/binary": respond(200, body: Data([0xFF, 0xFE, 0x00]))
        case "/elsewhere": redirect(to: "https://tracker.invalid/collect")
        case "/sibling": redirect(to: "https://cdn.example.com/final")
        case "/final": respond(200, body: Data("final".utf8))
        default: respond(404)
        }
    }
}

@MainActor
private final class FetchHarness {
    private final class Inbox { var messages: [[String: Any]] = [] }
    private let inbox = Inbox()
    let broker: ConnectionBroker
    var messages: [[String: Any]] { inbox.messages }

    init(network: [String]) throws {
        let hosts = String(decoding: try JSONEncoder().encode(network), as: UTF8.self)
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data("""
        {"id":"dev.test.fetch","name":"Fetch","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[],"network":\(hosts)}
        """.utf8))
        let inbox = inbox
        broker = ConnectionBroker(manifest: manifest, directory: URL(fileURLWithPath: "/tmp"), networkProtocolClasses: [StubInternet.self],
                                  authorize: { _ in Issue.record("fetch must not ask for consent"); return false },
                                  emit: { json in
            if let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] { inbox.messages.append(value) }
        })
    }

    func fetch(_ url: String, headers: [String: String]? = nil) async throws -> [String: Any] {
        let id = UUID().uuidString
        broker.receive(.init(extensionID: "dev.test.fetch", requestID: id, connectionID: "", operation: .fetch,
                             fetch: NetworkRequest(url: url, headers: headers)))
        for _ in 0..<1000 {
            if let response = messages.first(where: { $0["requestID"] as? String == id }) { return response }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("No response for \(url)")
        return [:]
    }
}

@Test @MainActor func fetchReachesDeclaredHostsWithoutAskingAndReportsTheResponse() async throws {
    let harness = try FetchHarness(network: ["api.example.com"])
    defer { harness.broker.stop() }
    let response = try await harness.fetch("https://API.example.com/ok")
    let result = try #require(response["result"] as? [String: Any])
    #expect(result["status"] as? Int == 200)
    #expect(result["body"] as? String == #"{"hello":"world"}"#)
    #expect((result["headers"] as? [String: String])?["x-answer"] == "42")
}

@Test @MainActor func fetchRejectsUndeclaredHostsInsecureURLsAndOversizedBodies() async throws {
    let harness = try FetchHarness(network: ["api.example.com"])
    defer { harness.broker.stop() }
    for url in ["https://other.example.com/ok", "http://api.example.com/ok", "https://user:pw@api.example.com/ok",
                "https://api.example.com/large", "https://api.example.com/binary"] {
        let response = try await harness.fetch(url)
        #expect(response["error"] as? String != nil, "\(url)")
    }
}

@Test @MainActor func redirectsAreFollowedOnlyToDeclaredHostsAndDropCredentials() async throws {
    let harness = try FetchHarness(network: ["api.example.com", "cdn.example.com"])
    defer { harness.broker.stop() }

    let outside = try #require(try await harness.fetch("https://api.example.com/elsewhere")["result"] as? [String: Any])
    #expect(outside["status"] as? Int == 302)
    #expect(StubInternet.authorization(at: "/collect") == nil)

    let sibling = try #require(try await harness.fetch("https://api.example.com/sibling", headers: ["Authorization": "Bearer secret"])["result"] as? [String: Any])
    #expect(sibling["body"] as? String == "final")
    #expect(sibling["url"] as? String == "https://cdn.example.com/final")
    #expect(StubInternet.authorization(at: "/final") == "")
}

@Test func networkHostsAreValidatedInTheManifest() throws {
    func manifest(_ hosts: String) throws -> ExtensionManifest {
        try JSONDecoder().decode(ExtensionManifest.self, from: Data("""
        {"id":"dev.test.fetch","name":"Fetch","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[],"network":\(hosts)}
        """.utf8))
    }
    try manifest(#"["api.github.com","*.example.com"]"#).validate()
    for hosts in [#"["https://api.github.com"]"#, #"["API.github.com"]"#, #"["*"]"#, #"["a.com","a.com"]"#,
                  "[" + (0..<17).map { #""h\#($0).com""# }.joined(separator: ",") + "]"] {
        #expect(throws: ProtocolError.self, "\(hosts)") { try manifest(hosts).validate() }
    }
    #expect(throws: ProtocolError.self) { try NetworkRequest(url: "https://example.com").validatedURL(hosts: ["*.example.com"]) }
}
