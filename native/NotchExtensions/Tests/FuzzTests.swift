import Foundation
import Testing
import NotchProtocol
@testable import NotchExtensions

/// Seeded random inputs for code that reads untrusted data. Each target runs a
/// few hundred cases in every test run; set NOTCHNOTCH_FUZZ_ITERATIONS for a
/// long run. A failure prints its seed, so it can be replayed exactly.
struct Fuzz {
    /// SplitMix64: small, fast, and the same sequence on every machine.
    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static var iterations: Int {
        ProcessInfo.processInfo.environment["NOTCHNOTCH_FUZZ_ITERATIONS"].flatMap(Int.init) ?? 300
    }

    /// Runs `body` with a fresh generator per case, reporting the failing seed.
    static func run(_ name: String, base: UInt64, iterations: Int = Fuzz.iterations, _ body: (inout Generator, UInt64) throws -> Void) rethrows {
        for index in 0..<UInt64(iterations) {
            let seed = base &+ index
            var generator = Generator(state: seed)
            try body(&generator, seed)
        }
    }

    static let interesting: [UInt32] = [0, 1, 0x7F, 0x80, 0xFF, 0x100, 0xFFFF, 0x1_0000, 0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFE, 0xFFFF_FFFF]

    /// Flips bits, overwrites 2 or 4 bytes with boundary values, truncates or duplicates.
    static func mutate(_ data: Data, _ generator: inout Generator) -> Data {
        var bytes = [UInt8](data)
        for _ in 0..<Int.random(in: 1...4, using: &generator) where !bytes.isEmpty {
            let offset = Int.random(in: 0..<bytes.count, using: &generator)
            switch Int.random(in: 0..<5, using: &generator) {
            case 0: bytes[offset] ^= UInt8(1 << Int.random(in: 0..<8, using: &generator))
            case 1: bytes[offset] = UInt8.random(in: 0...255, using: &generator)
            case 2, 3:
                let value = interesting.randomElement(using: &generator)!
                let width = Int.random(in: 0..<2, using: &generator) == 0 ? 2 : 4
                for byte in 0..<width where offset + byte < bytes.count { bytes[offset + byte] = UInt8((value >> UInt32(8 * byte)) & 0xFF) }
            default:
                if Bool.random(using: &generator) { bytes.removeLast(Int.random(in: 1...min(64, bytes.count), using: &generator)) }
                else { bytes.insert(contentsOf: bytes[offset..<min(bytes.count, offset + 32)], at: offset) }
            }
        }
        return Data(bytes)
    }
}

private let manifest = Data(#"{"id":"dev.test.fuzz","name":"Fuzz","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[]}"#.utf8)

@Test func fuzzedPackagesNeverCrashOrWriteOutsideTheirFolder() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-fuzz-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let valid = ZipWriter.archive([
        .init(name: "notchnotch.json", data: manifest),
        .init(name: "bundle.js", data: Data("void 0;".utf8)),
        .init(name: "assets/", mode: 0o040755),
        .init(name: "assets/icon.txt", data: Data(repeating: 0x61, count: 300)),
    ])
    let archive = root.appendingPathComponent("case.notchext")
    try Fuzz.run("archive", base: 0xA11CE) { generator, seed in
        let destination = root.appendingPathComponent("out-\(seed)")
        try Fuzz.mutate(valid, &generator).write(to: archive)
        do {
            try ExtensionArchive.extract(archive, into: destination)
            // Whatever was accepted stays inside its folder, with no links.
            let base = destination.resolvingSymlinksInPath().path + "/"
            for case let path as String in FileManager.default.enumerator(atPath: destination.path) ?? .init() {
                let url = destination.appendingPathComponent(path)
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                #expect(values.isSymbolicLink != true, "seed \(seed): \(path) is a link")
                #expect(url.resolvingSymlinksInPath().path.hasPrefix(base), "seed \(seed): \(path) escaped")
            }
            try FileManager.default.removeItem(at: destination)
        } catch {
            #expect(!FileManager.default.fileExists(atPath: destination.path), "seed \(seed): a rejected package left files behind")
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != "case.notchext" }
        #expect(leftovers.isEmpty, "seed \(seed): wrote \(leftovers)")
    }
}

/// Field-aware: sets zip header fields (method, sizes, offsets, name lengths,
/// entry counts) to boundary values. Byte-level mutation rarely changes the
/// several related fields an attack needs at once.
@Test func packagesWithHostileHeaderFieldsAreRejectedWithoutCrashing() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-fuzz-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let valid = ZipWriter.archive([
        .init(name: "notchnotch.json", data: manifest),
        .init(name: "bundle.js", data: Data("void 0;".utf8)),
    ])
    let bytes = [UInt8](valid)
    func signatures(_ value: UInt32) -> [Int] {
        (0..<(bytes.count - 3)).filter { offset in (0..<4).allSatisfy { bytes[offset + $0] == UInt8((value >> UInt32(8 * $0)) & 0xFF) } }
    }
    // (offset, width) of every interesting field in local headers, central entries and the end record.
    var fields: [(Int, Int)] = []
    for local in signatures(0x0403_4b50) { fields += [(local + 6, 2), (local + 8, 2), (local + 14, 4), (local + 18, 4), (local + 22, 4), (local + 26, 2), (local + 28, 2)] }
    for entry in signatures(0x0201_4b50) {
        fields += [(entry + 4, 2), (entry + 8, 2), (entry + 10, 2), (entry + 16, 4), (entry + 20, 4), (entry + 24, 4),
                   (entry + 28, 2), (entry + 30, 2), (entry + 32, 2), (entry + 38, 4), (entry + 42, 4)]
    }
    for end in signatures(0x0605_4b50) { fields += [(end + 4, 2), (end + 6, 2), (end + 8, 2), (end + 10, 2), (end + 12, 4), (end + 16, 4), (end + 20, 2)] }
    let values = Fuzz.interesting + [8, 9, 12, 14, 46, UInt32(valid.count), UInt32(valid.count - 22)]
    let archive = root.appendingPathComponent("case.notchext")
    try Fuzz.run("fields", base: 0xF1E1D) { generator, seed in
        var mutated = bytes
        for _ in 0..<Int.random(in: 1...3, using: &generator) {
            let (offset, width) = fields.randomElement(using: &generator)!
            let value = values.randomElement(using: &generator)!
            for byte in 0..<width { mutated[offset + byte] = UInt8((value >> UInt32(8 * byte)) & 0xFF) }
        }
        try Data(mutated).write(to: archive)
        let destination = root.appendingPathComponent("out-\(seed)")
        if (try? ExtensionArchive.extract(archive, into: destination)) != nil { try FileManager.default.removeItem(at: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path), "seed \(seed)")
    }
}

/// A deflated entry with no compressed bytes but a declared size: the
/// decompressor gets an empty input buffer, which must fail, not crash.
@Test func aDeflatedEntryWithNoDataIsRejected() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-fuzz-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var bytes = [UInt8](ZipWriter.archive([.init(name: "notchnotch.json", data: Data()), .init(name: "bundle.js", data: Data())]))
    func put(_ value: UInt32, _ offset: Int, _ width: Int) { for byte in 0..<width { bytes[offset + byte] = UInt8((value >> UInt32(8 * byte)) & 0xFF) } }
    let entry = (0..<(bytes.count - 3)).first { bytes[$0] == 0x50 && bytes[$0 + 1] == 0x4B && bytes[$0 + 2] == 0x01 && bytes[$0 + 3] == 0x02 }!
    put(8, entry + 10, 2)      // method: deflate
    put(0, entry + 20, 4)      // compressed size: nothing
    put(100, entry + 24, 4)    // declared size: 100 bytes
    let archive = root.appendingPathComponent("empty.notchext")
    try Data(bytes).write(to: archive)
    #expect(throws: ProtocolError.self) { try ExtensionArchive.extract(archive, into: root.appendingPathComponent("out")) }
}

/// A runner controls every byte of its snapshot. A node nested thousands of
/// levels deep still fits the 256 KiB message limit; decoding it must fail
/// cleanly in the app, not overflow the stack.
@Test func deeplyNestedSnapshotsFailWithoutCrashingTheApp() throws {
    for depth in [18, 1_000, 4_000] {
        var json = ""
        for level in 0..<depth { json += #"{"id":"n\#(level)","type":"column","props":{},"children":["# }
        json += String(repeating: "]}", count: depth)
        let message = #"{"protocolVersion":1,"type":"snapshot","extensionID":"dev.test.deep","revision":1,"surfaces":[{"id":"s","kind":"activity","title":"S","initialView":"expanded","phase":"active","expanded":"# + json + "}]}"
        #expect(message.utf8.count <= maximumMessageBytes, "depth \(depth) must fit one message to be a real attack")
        let snapshot = try? JSONDecoder().decode(Snapshot.self, from: Data(message.utf8))
        #expect(throws: (any Error).self, "depth \(depth)") {
            guard let snapshot else { throw ProtocolError.invalid("not decoded") }
            try snapshot.validate(expectedExtensionID: "dev.test.deep")
        }
    }
}

/// Text-level mutations of valid messages: whatever decodes must either be
/// rejected by validation or respect its limits.
@Test func fuzzedSnapshotsManifestsAndMarkdownNeverCrash() throws {
    let snapshot = #"{"protocolVersion":1,"type":"snapshot","extensionID":"dev.test.fuzz","revision":3,"surfaces":[{"id":"s","kind":"activity","title":"Timer","initialView":"compact","phase":"active","compact":{"leading":[{"id":"c1","type":"symbol","props":{"name":"timer"},"children":[]}],"trailing":[{"id":"c2","type":"text","props":{"text":"12:00"},"children":[]}]},"expanded":{"id":"e","type":"column","props":{},"children":[{"id":"t","type":"text","props":{"text":"Focus","tone":"accent"},"children":[]},{"id":"p","type":"progress","props":{"value":0.5},"children":[]},{"id":"b","type":"button","props":{"title":"Stop","action":"a1"},"children":[]}]},"peek":{"id":"ev1","text":"Started","duration":4}}],"settings":{"id":"root","type":"column","props":{},"children":[{"id":"tg","type":"toggle","props":{"label":"Ask","value":1,"action":"a2"},"children":[]}]}}"#
    let manifest = #"{"id":"dev.test.fuzz","name":"Fuzz Test","version":"1.0.0","apiVersion":1,"entry":"bundle.js","permissions":["process","local-network"],"icon":"icon.png","network":["api.example.com","*.example.org"],"imageHosts":["img.example.com"],"author":"jane","categories":["Media"],"license":"MIT","homepage":"https://example.com","connections":{"api":{"transport":"http","endpoint":"http://127.0.0.1:4277"},"tool":{"transport":"stdio","executable":"./helpers/tool","arguments":["-v"]}},"preferences":[{"name":"token","type":"password","title":"Token","required":true},{"name":"units","type":"dropdown","title":"Units","default":"a","options":[{"value":"a","title":"A"}]}]}"#
    #expect(throws: Never.self) { try JSONDecoder().decode(Snapshot.self, from: Data(snapshot.utf8)).validate(expectedExtensionID: "dev.test.fuzz") }
    #expect(throws: Never.self) { try JSONDecoder().decode(ExtensionManifest.self, from: Data(manifest.utf8)).validate() }

    try Fuzz.run("messages", base: 0x5EED) { generator, seed in
        let mutatedSnapshot = Fuzz.mutate(Data(snapshot.utf8), &generator)
        if let decoded = try? JSONDecoder().decode(Snapshot.self, from: mutatedSnapshot),
           (try? decoded.validate(expectedExtensionID: "dev.test.fuzz")) != nil {
            #expect(decoded.surfaces.count <= 16, "seed \(seed)")
            #expect(decoded.surfaces.allSatisfy { ($0.peek?.text.count ?? 0) <= 256 }, "seed \(seed)")
        }
        let mutatedManifest = Fuzz.mutate(Data(manifest.utf8), &generator)
        if let decoded = try? JSONDecoder().decode(ExtensionManifest.self, from: mutatedManifest), (try? decoded.validate()) != nil {
            #expect(decoded.apiVersion == 1 && decoded.entry == "bundle.js", "seed \(seed)")
            if let icon = decoded.iconFiles { #expect(!icon.light.contains("/"), "seed \(seed): icon \(icon.light)") }
            _ = PermissionSummary.items(for: decoded)
        }
        let markdown = String(decoding: Fuzz.mutate(Data("# Title\n\n- one\n  two\n1. **bold** [link](https://example.com)\n> quote\n```\ncode\n```\n---\n![alt](x.png)".utf8), &generator), as: UTF8.self)
        _ = Markdown.blocks(markdown)
    }
}

/// URLs built from pieces attackers use to confuse host checks. Whatever fetch
/// accepts must really go to a declared host; whatever open accepts must not
/// be a local file, script or system link.
@Test func fuzzedURLsNeverSlipPastTheHostAndSchemeChecks() throws {
    let schemes = ["https", "HTTPS", "http", "file", "javascript", "data", "x-apple.systempreferences", "notchnotch", "mailto", "ftp", ""]
    let hosts = ["api.example.com", "API.Example.com", "api.example.com.evil.net", "evil.net", "api.example.com@evil.net",
                 "evil.net#api.example.com", "evil.net?api.example.com", "user:pw@api.example.com", "api.example.com:443",
                 "xn--pple-43d.com", "127.0.0.1", "[::1]", "api.example.com%2F@evil.net", "sub.example.org", "example.org", ""]
    let tails = ["", "/", "/path?q=1", "#frag", "/../../etc/passwd", "\\evil.net", "%00", " "]
    let declared = ["api.example.com", "*.example.org"]
    try Fuzz.run("urls", base: 0x0AB1) { generator, seed in
        let separator = ["://", ":", ":///", "//", ":\\\\"].randomElement(using: &generator)!
        let url = schemes.randomElement(using: &generator)! + separator + hosts.randomElement(using: &generator)! + tails.randomElement(using: &generator)!
        if let accepted = try? NetworkRequest(url: url).validatedURL(hosts: declared) {
            let host = accepted.host()?.lowercased() ?? ""
            #expect(accepted.scheme == "https", "seed \(seed): \(url)")
            #expect(host == "api.example.com" || host.hasSuffix(".example.org"), "seed \(seed): \(url) reached \(host)")
            #expect(accepted.user() == nil && accepted.password() == nil, "seed \(seed): \(url)")
        }
        if let opened = try? OpenURLPolicy.validate(url) {
            let scheme = opened.scheme?.lowercased() ?? ""
            #expect(!["file", "data", "javascript", "notchnotch"].contains(scheme) && !scheme.hasPrefix("x-apple"), "seed \(seed): \(url)")
        }
    }
}

