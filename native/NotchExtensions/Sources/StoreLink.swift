import Foundation

/// `notchnotch://` links, which the website's Install buttons use.
///
/// A link only opens a page. Installing still takes **Get** and the review,
/// so a page that opens links on its own can't install anything.
public enum StoreLink: Equatable, Sendable {
    /// `notchnotch://store`
    case store
    /// `notchnotch://extensions/<author>/<name>`
    case entry(handle: String)

    public static let scheme = "notchnotch"

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.user == nil, url.password == nil, url.port == nil else { return nil }
        let parts = url.path(percentEncoded: true).split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        switch url.host(percentEncoded: true)?.lowercased() {
        case "store" where parts.isEmpty || parts == [""]:
            self = .store
        case "extensions":
            // Trailing slash allowed; anything percent-encoded or extra is not.
            let segments = Array(parts.last == "" ? parts.dropLast() : parts)
            let handle = segments.joined(separator: "/")
            guard segments.count == 2, ExtensionCatalog.isValidHandle(handle) else { return nil }
            self = .entry(handle: handle)
        default:
            return nil
        }
    }

    public var url: URL {
        switch self {
        case .store: URL(string: "\(Self.scheme)://store")!
        case .entry(let handle): URL(string: "\(Self.scheme)://extensions/\(handle)")!
        }
    }
}
