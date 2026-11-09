import Foundation
import Testing
import NotchProtocol

@Test func artworkRequiresBoundedDataOrADeclaredImageHost() {
    let hosts = ["i.scdn.co", "*.mzstatic.com"]
    #expect(NowPlayingState.isArtworkSource("https://i.scdn.co/image/cover", imageHosts: hosts))
    #expect(NowPlayingState.isArtworkSource("https://is1-ssl.mzstatic.com/image/cover.jpg", imageHosts: hosts))
    #expect(NowPlayingState.isArtworkSource("data:image/jpeg;base64,YWJj", imageHosts: []))
    // No extension gets remote artwork without declaring the host, including the bundled CDNs.
    #expect(!NowPlayingState.isArtworkSource("https://i.scdn.co/image/cover", imageHosts: []))
    for source in ["file:///etc/passwd", "http://i.scdn.co/image/cover", "https://i.scdn.co.attacker.example/image",
                   "https://mzstatic.com/cover.jpg", "https://evilmzstatic.com/cover.jpg", "https://i.scdn.co:8443/cover",
                   "https://127.0.0.1/", "https://attacker.example/", "data:image/svg+xml;base64,YWJj",
                   "data:image/jpeg;base64," + String(repeating: "a", count: 65_536)] {
        #expect(!NowPlayingState.isArtworkSource(source, imageHosts: hosts))
    }
}

@Test func manifestImageHostsAreBoundedDNSPatterns() throws {
    func manifest(_ hosts: [String]) throws -> ExtensionManifest {
        let object: [String: Any] = ["id": "dev.example.player", "name": "Player", "version": "1", "apiVersion": 1,
                                     "entry": "bundle.js", "permissions": [], "imageHosts": hosts]
        return try JSONDecoder().decode(ExtensionManifest.self, from: JSONSerialization.data(withJSONObject: object))
    }
    try manifest(["i.ytimg.com", "*.mzstatic.com", "resources.tidal.com"]).validate()
    for hosts in [["*.com"], ["*"], ["localhost"], ["127.0.0.1"], ["I.YTIMG.COM"], ["a.example/path"],
                  ["https://i.ytimg.com"], ["*.*.example.com"], ["x.example.com", "x.example.com"],
                  (0...8).map { "h\($0).example.com" }] {
        #expect(throws: ProtocolError.self) { try manifest(hosts).validate() }
    }
}

@Test func mediaRequestsValidateCommandsAndNormalizedValues() throws {
    try MediaRequest(command: .playPause).validate()
    try MediaRequest(command: .seek, value: 0.5).validate()
    try MediaRequest(command: .volume, value: 0).validate()
    for value in [-0.1, 1.1, Double.infinity, Double.nan] {
        #expect(throws: ProtocolError.self) { try MediaRequest(command: .seek, value: value).validate() }
    }
    #expect(throws: ProtocolError.self) { try MediaRequest(command: .seek).validate() }
    #expect(throws: ProtocolError.self) { try MediaRequest(command: .next, value: 0.5).validate() }
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(MediaRequest.self, from: Data(#"{"command":"runScript","value":0}"#.utf8))
    }
}

@Test func manifestsUseGenericConnectionsAndRejectTheRemovedMediaPermission() throws {
    let json = #"{"id":"dev.example.music","name":"Music","version":"1","apiVersion":1,"entry":"bundle.js","permissions":["process"]}"#
    try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8)).validate()
    for permission in ["media", "filesystem", "shell", "network"] {
        #expect(throws: ProtocolError.self) {
            try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.replacingOccurrences(of: "\"process\"", with: "\"\(permission)\"").utf8)).validate()
        }
    }
}

@Test func manifestPresentationMetadataCannotOverflowTheManagementWindow() throws {
    let json = #"{"id":"dev.example.extension","name":"Example","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[],"icon":"music.note","description":"Example extension"}"#
    try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8)).validate()
    for (key, value) in ["name": String(repeating: "n", count: 129), "version": String(repeating: "v", count: 65),
                         "icon": String(repeating: "i", count: 129), "description": String(repeating: "d", count: 513)] {
        var object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        object[key] = value
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ProtocolError.self) { try JSONDecoder().decode(ExtensionManifest.self, from: data).validate() }
    }
}
