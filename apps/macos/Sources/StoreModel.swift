import CryptoKit
import Foundation
import Observation
import NotchExtensions

/// The Store's catalog as the app sees it: the last verified copy right away,
/// then a fresh one in the background.
@MainActor @Observable
final class StoreModel {
    enum Phase: Equatable { case idle, loading, failed(String) }

    private(set) var catalog: ExtensionCatalog?
    private(set) var phase = Phase.idle
    private(set) var refreshedAt: Date?
    /// nil when this build has no Store settings in Info.plist.
    let client: StoreClient?

    init(directory: URL, bundle: Bundle = .main) {
        client = Self.source(bundle).map { StoreClient(source: $0, directory: directory) }
    }

    /// The catalog URL and trusted keys from Info.plist. Debug builds may point
    /// at a test catalog with NOTCHNOTCH_CATALOG_URL and NOTCHNOTCH_CATALOG_KEY.
    private static func source(_ bundle: Bundle) -> StoreClient.Source? {
        var url = (bundle.object(forInfoDictionaryKey: "NotchCatalogURL") as? String).flatMap(URL.init(string:))
        var keys = (bundle.object(forInfoDictionaryKey: "NotchCatalogPublicKeys") as? [String] ?? []).compactMap(ExtensionCatalog.publicKey(base64:))
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["NOTCHNOTCH_CATALOG_URL"].flatMap(URL.init(string:)) { url = override }
        if let override = environment["NOTCHNOTCH_CATALOG_KEY"].flatMap(ExtensionCatalog.publicKey(base64:)) { keys = [override] }
        #endif
        guard let url, !keys.isEmpty else { return nil }
        return .init(url: url, keys: keys)
    }

    /// Shows the kept catalog, then refreshes it if it's more than a few minutes old.
    func open() async {
        guard let client else { return }
        if catalog == nil { catalog = await client.cached() }
        if refreshedAt.map({ Date.now.timeIntervalSince($0) > 300 }) ?? true { await refresh() }
    }

    func refresh() async {
        guard let client, phase != .loading else { return }
        phase = .loading
        do {
            catalog = try await client.refresh()
            refreshedAt = .now
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// What the Store can do with one of its extensions on this Mac.
enum StoreEntryState: Equatable {
    case install, installed, update(from: String), included, developing, needsApp(String)
}
