import Foundation

enum ManagementDestination: Hashable {
    case general, notch, about, libraryIssues
    case extensionDetails(String)
}

/// What the sidebar and an extension's header say about it.
enum ExtensionStatus: Equatable {
    case off, starting, running, needsAttention(String)

    var title: String {
        switch self {
        case .off: "Off"
        case .starting: "Starting…"
        case .running: "On"
        case .needsAttention: "Needs attention"
        }
    }
}
