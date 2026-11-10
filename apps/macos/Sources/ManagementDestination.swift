import Foundation

enum ManagementDestination: Hashable {
    case general, notch, about, libraryIssues, store
    case extensionDetails(String)
    /// A Store extension by `author/name` handle.
    case storeEntry(String)
}

/// What the sidebar and an extension's header say about it.
enum ExtensionStatus: Equatable {
    case off, starting, running, needsAttention(String)
    /// Waiting for required preferences, listed by title.
    case needsSetup([String])

    var title: String {
        switch self {
        case .off: "Off"
        case .starting: "Starting…"
        case .running: "On"
        case .needsAttention: "Needs attention"
        case .needsSetup: "Needs setup"
        }
    }
}
