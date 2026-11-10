import CryptoKit
import Foundation
import NotchProtocol

/// The Store's list of reviewed extensions: `index.json` plus a detached
/// Ed25519 signature in `index.json.sig`, both built by the extensions
/// repository's CI after a pull request is merged.
///
/// The signature covers the exact bytes of `index.json`, and it is checked
/// before anything parses them. A valid signature isn't enough: whoever serves
/// the files could replay an older signed catalog that still lists a version
/// with a known problem, or keep serving one forever. So every catalog carries
/// a `sequence` the app never accepts going backwards and an `expires` date
/// after which it isn't accepted at all; CI re-signs it well before then.
///
/// Each entry carries the extension's whole manifest, so the Store can show
/// what it can do before downloading, and the package's SHA-256, so the
/// download is trusted only if it is exactly what was reviewed.
public struct ExtensionCatalog: Codable, Equatable, Sendable {
    public static let format = 1
    public static let maximumBytes = 8 * 1024 * 1024
    public static let maximumEntries = 2000
    public static let maximumScreenshots = 6

    public var format: Int
    /// Increases with every catalog CI publishes.
    public var sequence: Int
    public var generated: Date
    public var expires: Date
    public var extensions: [Entry]

    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        /// `author/name`, the extension's folder in the extensions repository
        /// and its address on the website and in `notchnotch://extensions/…`.
        public var handle: String
        public var manifest: ExtensionManifest
        public var package: Package
        public var icon: URL?
        public var iconDark: URL?
        public var screenshots: [URL]?
        /// The oldest NotchNotch that can run this version.
        public var minimumAppVersion: String?
        /// When this version was merged.
        public var published: Date

        public var id: String { manifest.id }
        public var author: String { String(handle.prefix { $0 != "/" }) }
    }

    public struct Package: Codable, Equatable, Sendable {
        public var url: URL
        /// Lowercase hex SHA-256 of the `.notchext` file.
        public var sha256: String
        public var size: Int
    }

    public enum Failure: LocalizedError, Equatable {
        case tooLarge
        case badSignature
        case invalid(String)
        case expired(Date)
        case rolledBack(sequence: Int, last: Int)
        case packageMismatch(String)

        public var errorDescription: String? {
            switch self {
            case .tooLarge: "The Store catalog is larger than 8 MiB."
            case .badSignature: "The Store catalog isn’t signed by NotchNotch."
            case .invalid(let reason): "The Store catalog is invalid: \(reason)."
            case .expired(let date): "The Store catalog expired on \(date.formatted(date: .abbreviated, time: .omitted))."
            case .rolledBack(let sequence, let last): "The Store catalog is older than one already seen (\(sequence) after \(last))."
            case .packageMismatch(let reason): "The downloaded package isn’t the one the Store reviewed: \(reason)."
            }
        }
    }

    /// Checks the signature over `data`, then decodes and validates it.
    /// `lastSequence` is the highest sequence this Mac has accepted before.
    public static func verify(_ data: Data, signature: Data, keys: [Curve25519.Signing.PublicKey],
                              now: Date = .now, lastSequence: Int? = nil) throws -> ExtensionCatalog {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        let text = String(decoding: signature.prefix(256), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: text), raw.count == 64,
              keys.contains(where: { $0.isValidSignature(raw, for: data) }) else { throw Failure.badSignature }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog: ExtensionCatalog
        do { catalog = try decoder.decode(ExtensionCatalog.self, from: data) } catch {
            throw Failure.invalid(Self.describe(error))
        }
        try catalog.validate()
        guard catalog.expires > now else { throw Failure.expired(catalog.expires) }
        if let lastSequence, catalog.sequence < lastSequence {
            throw Failure.rolledBack(sequence: catalog.sequence, last: lastSequence)
        }
        return catalog
    }

    /// Names the field a decoding error is about, so a bad catalog is quick to fix.
    private static func describe(_ error: any Error) -> String {
        switch error as? DecodingError {
        case .keyNotFound(let key, let context)?:
            return "\(path(context.codingPath + [key])) is missing"
        case .typeMismatch(_, let context)?, .valueNotFound(_, let context)?, .dataCorrupted(let context)?:
            return context.codingPath.isEmpty ? "it isn’t a catalog" : "\(path(context.codingPath)) has the wrong type or value"
        default:
            return "it isn’t a catalog"
        }
    }

    /// `extensions[2].package.sha256`, for error messages.
    private static func path(_ keys: [any CodingKey]) -> String {
        keys.reduce("") { result, key in
            if let index = key.intValue { return result + "[\(index)]" }
            return result.isEmpty ? key.stringValue : result + "." + key.stringValue
        }
    }

    /// Loads a base64 Ed25519 public key, as committed beside the app.
    public static func publicKey(base64: String) -> Curve25519.Signing.PublicKey? {
        Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }

    func validate() throws {
        guard format == Self.format else { throw Failure.invalid("format \(format) isn’t supported; update NotchNotch") }
        guard sequence >= 0, generated < expires else { throw Failure.invalid("its dates or sequence are wrong") }
        guard extensions.count <= Self.maximumEntries else { throw Failure.invalid("it lists too many extensions") }
        var ids = Set<String>(), handles = Set<String>()
        for entry in extensions {
            guard ids.insert(entry.id).inserted, handles.insert(entry.handle).inserted else {
                throw Failure.invalid("\(entry.handle) is listed twice")
            }
            try entry.validate()
        }
    }

    /// HTTPS only. Debug builds also accept http://127.0.0.1 so a test Store can
    /// be served locally; release builds never do.
    static func isAllowedLink(_ url: URL) -> Bool {
        guard let host = url.host(), !host.isEmpty else { return false }
        #if DEBUG
        if url.scheme == "http", host == "127.0.0.1" { return true }
        #endif
        return url.scheme == "https"
    }

    public func entry(id: String) -> Entry? { extensions.first { $0.id == id } }
    public func entry(handle: String) -> Entry? { extensions.first { $0.handle == handle } }
}

extension ExtensionCatalog.Entry {
    func validate() throws {
        let fail = { (reason: String) in ExtensionCatalog.Failure.invalid("\(handle): \(reason)") }
        guard handle.range(of: "^[a-z0-9][a-z0-9-]{0,38}/[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil else {
            throw fail("the handle must be author/name in lowercase")
        }
        do { try manifest.validate() } catch { throw fail(error.localizedDescription) }
        guard manifest.author == author else { throw fail("the manifest’s author isn’t \(author)") }
        guard package.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              package.size > 0, package.size <= ExtensionArchive.maximumArchiveBytes else {
            throw fail("the package hash or size is wrong")
        }
        let links = [package.url] + [icon, iconDark].compactMap { $0 } + (screenshots ?? [])
        guard links.allSatisfy(ExtensionCatalog.isAllowedLink) else { throw fail("every link must be https") }
        guard (screenshots?.count ?? 0) <= ExtensionCatalog.maximumScreenshots else { throw fail("it has too many screenshots") }
        if let minimumAppVersion, CatalogVersion.components(minimumAppVersion) == nil {
            throw fail("minimumAppVersion isn’t a version number")
        }
    }

    /// Whether this version runs on NotchNotch `appVersion`.
    public func runs(onApp appVersion: String) -> Bool {
        guard let minimumAppVersion else { return true }
        return CatalogVersion.compare(appVersion, minimumAppVersion) != .orderedAscending
    }

    /// Whether this version is newer than an installed `version`.
    public func isNewer(than version: String) -> Bool {
        CatalogVersion.compare(manifest.version, version) == .orderedDescending
    }

    /// Checks a downloaded `.notchext` against the reviewed size and hash,
    /// reading it in pieces so a large file never sits in memory.
    public func verifyDownload(_ file: URL) throws {
        // Not URL.resourceValues: it caches per URL and would miss a file replaced since.
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? -1
        guard size == package.size else { throw ExtensionCatalog.Failure.packageMismatch("its size is \(size) bytes, not \(package.size)") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == package.sha256 else { throw ExtensionCatalog.Failure.packageMismatch("its SHA-256 differs") }
    }

    /// After extraction: the package must be the manifest the Store listed,
    /// not just any extension that happens to hash right.
    public func verifyContents(_ package: ExtensionPackage) throws {
        guard package.manifest == manifest else {
            throw ExtensionCatalog.Failure.packageMismatch("its manifest differs from the catalog’s")
        }
    }
}

/// Dotted numeric versions such as `0.7.0` or `1.2`; a missing component is 0.
enum CatalogVersion {
    static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        let numbers = parts.map { Int($0) }
        guard numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return numbers.map { $0! }
    }

    /// Versions that aren't dotted numbers fall back to a numeric string comparison.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        guard let left = components(lhs), let right = components(rhs) else { return lhs.compare(rhs, options: .numeric) }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0, b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
