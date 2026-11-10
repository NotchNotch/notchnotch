import CryptoKit
import Foundation

/// Fetches the Store catalog, verifies it and downloads reviewed packages.
///
/// The last verified catalog is kept on disk: the Store opens instantly and
/// offline, and its `sequence` is what a newly fetched catalog must not go
/// below. Downloads stop as soon as they exceed the size the catalog lists,
/// so a misbehaving host can't fill the disk.
public actor StoreClient {
    public struct Source: Sendable {
        /// `index.json`; the signature is the same URL with `.sig` appended.
        public var url: URL
        public var keys: [Curve25519.Signing.PublicKey]
        public init(url: URL, keys: [Curve25519.Signing.PublicKey]) { self.url = url; self.keys = keys }
        var signatureURL: URL { URL(string: url.absoluteString + ".sig")! }
    }

    public enum Failure: LocalizedError, Equatable {
        case http(Int)
        case tooLarge
        public var errorDescription: String? {
            switch self {
            case .http(let status): "The Store answered with HTTP \(status)."
            case .tooLarge: "The Store sent more data than expected."
            }
        }
    }

    public let source: Source
    private let directory: URL
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init(source: Source, directory: URL, session: URLSession = .shared, now: @escaping @Sendable () -> Date = { .now }) {
        self.source = source
        self.directory = directory
        self.session = session
        self.now = now
    }

    private var indexFile: URL { directory.appendingPathComponent("index.json") }
    private var signatureFile: URL { directory.appendingPathComponent("index.json.sig") }

    /// The last catalog verified on this Mac, if it hasn't expired.
    public func cached() -> ExtensionCatalog? {
        guard let data = try? Data(contentsOf: indexFile), let signature = try? Data(contentsOf: signatureFile) else { return nil }
        return try? ExtensionCatalog.verify(data, signature: signature, keys: source.keys, now: now())
    }

    /// The highest sequence accepted before, even from an expired catalog.
    private func lastSequence() -> Int? {
        guard let data = try? Data(contentsOf: indexFile), let signature = try? Data(contentsOf: signatureFile) else { return nil }
        return (try? ExtensionCatalog.verify(data, signature: signature, keys: source.keys, now: .distantPast))?.sequence
    }

    /// Downloads, verifies and keeps a new catalog.
    public func refresh() async throws -> ExtensionCatalog {
        async let index = fetch(source.url, limit: ExtensionCatalog.maximumBytes)
        async let signature = fetch(source.signatureURL, limit: 256)
        let (data, sig) = try await (index, signature)
        let catalog = try ExtensionCatalog.verify(data, signature: sig, keys: source.keys, now: now(), lastSequence: lastSequence())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Signature first: a crash between the writes leaves a pair that fails
        // verification, never an unsigned index that passes.
        try sig.write(to: signatureFile, options: .atomic)
        try data.write(to: indexFile, options: .atomic)
        return catalog
    }

    /// Downloads an entry's package to a temporary file and checks it against
    /// the catalog. The caller extracts it and deletes the file.
    public func download(_ entry: ExtensionCatalog.Entry) async throws -> URL {
        let data = try await fetch(entry.package.url, limit: entry.package.size)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchNotchStore", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(UUID().uuidString).\(ExtensionArchive.fileExtension)")
        try data.write(to: file)
        do { try entry.verifyDownload(file) } catch { try? FileManager.default.removeItem(at: file); throw error }
        return file
    }

    /// GETs `url`, refusing anything but HTTPS 200 and stopping past `limit` bytes.
    private func fetch(_ url: URL, limit: Int) async throws -> Data {
        guard ExtensionCatalog.isAllowedLink(url) else { throw ExtensionCatalog.Failure.invalid("every link must be https") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("NotchNotch", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status) }
        if response.expectedContentLength > Int64(limit) { throw Failure.tooLarge }
        var data = Data()
        data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
        var buffer = [UInt8]()
        buffer.reserveCapacity(65_536)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count == 65_536 {
                data.append(contentsOf: buffer); buffer.removeAll(keepingCapacity: true)
                if data.count > limit { throw Failure.tooLarge }
            }
        }
        data.append(contentsOf: buffer)
        guard data.count <= limit else { throw Failure.tooLarge }
        return data
    }
}
