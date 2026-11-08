import Foundation

/// One line of extension console output or a host-reported failure.
struct ExtensionLogEntry: Identifiable, Equatable, Sendable {
    enum Level: Sendable { case info, error }
    let id = UUID()
    let date: Date
    let level: Level
    let message: String
}
