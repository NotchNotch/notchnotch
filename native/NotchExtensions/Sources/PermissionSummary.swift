import Foundation
import NotchProtocol

/// What an extension can do beyond its sandbox, in plain words and ordered by
/// risk, for the install review. For an update, details the installed version
/// didn't have are marked new: that is when a trusted extension could start
/// asking for more.
public enum PermissionSummary {
    public enum Kind: Int, Comparable, Sendable {
        case runPrograms, personalData, internet, localApps, pictures, settings, deviceStatus
        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Detail: Equatable, Sendable {
        public let text: String
        public let isNew: Bool
    }

    public struct Item: Equatable, Identifiable, Sendable {
        public let kind: Kind
        public let title: String
        public let explanation: String
        public let details: [Detail]
        public var id: Kind { kind }
        /// The whole item is new, or any of its details is.
        public var isNew: Bool { details.contains(where: \.isNew) }
    }

    public static func items(for manifest: ExtensionManifest, comparedTo previous: ExtensionManifest? = nil) -> [Item] {
        let now = details(manifest)
        let before = previous.map(details) ?? [:]
        return now.keys.sorted().compactMap { kind in
            guard let texts = now[kind], !texts.isEmpty else { return nil }
            let old = Set(before[kind] ?? [])
            let marked = texts.map { Detail(text: $0, isNew: previous != nil && !old.contains($0)) }
            return Item(kind: kind, title: title(kind), explanation: explanation(kind), details: marked)
        }
    }

    private static func details(_ manifest: ExtensionManifest) -> [Kind: [String]] {
        var result: [Kind: [String]] = [:]
        let connections = (manifest.connections ?? [:]).sorted { $0.key < $1.key }.map(\.value)
        if manifest.permissions.contains("process") {
            result[.runPrograms] = connections.filter { $0.transport == .stdio }.map { connection in
                ([connection.executable ?? ""] + (connection.arguments ?? [])).joined(separator: " ")
            }
        }
        let capabilities = SystemCapability.allCases.filter { manifest.permissions.contains($0.rawValue) }
        result[.personalData] = capabilities.filter(\.asksFirst).map { capability in
            switch capability {
            case .calendar: "Your calendars: the next week’s events"
            case .nowPlaying: "What’s playing on your Mac, and playback controls"
            case .battery, .system: ""
            }
        }
        if manifest.permissions.contains("file-read") {
            result[.personalData, default: []].append("The files you drop on it: their contents, and saving results where you choose")
        }
        result[.deviceStatus] = capabilities.filter { !$0.asksFirst }.map { capability in
            switch capability {
            case .battery: "Battery charge and whether it’s charging"
            case .system: "CPU, memory, disk and network activity"
            case .calendar, .nowPlaying: ""
            }
        }
        result[.internet] = manifest.network ?? []
        if manifest.permissions.contains("local-network") {
            result[.localApps] = connections.filter { $0.transport != .stdio }.compactMap(\.endpoint)
        }
        result[.pictures] = manifest.imageHosts ?? []
        result[.settings] = (manifest.preferences ?? []).map { preference in
            preference.type == .password ? "\(preference.title) (kept in your Keychain)" : preference.title
        }
        return result
    }

    private static func title(_ kind: Kind) -> String {
        switch kind {
        case .runPrograms: "Run programs on your Mac"
        case .personalData: "Read data on this Mac"
        case .internet: "Exchange data with these websites"
        case .localApps: "Talk to apps on this Mac"
        case .pictures: "Show pictures from these websites"
        case .settings: "Ask you for settings"
        case .deviceStatus: "See your Mac’s status"
        }
    }

    private static func explanation(_ kind: Kind) -> String {
        switch kind {
        case .runPrograms: "These programs run with your account and can read your files and use the network. NotchNotch asks before each one starts."
        case .personalData: "NotchNotch reads it for the extension and asks before the first time. macOS may ask NotchNotch too."
        case .internet: "Only with these websites, without asking again."
        case .localApps: "NotchNotch asks before it connects."
        case .pictures: "NotchNotch downloads the pictures itself."
        case .settings: "You fill these in under Setup."
        case .deviceStatus: "Readings only, nothing personal, so NotchNotch doesn’t ask."
        }
    }
}
