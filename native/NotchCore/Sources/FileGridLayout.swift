import CoreGraphics
import UniformTypeIdentifiers
import NotchProtocol

/// How a grid of files fits the notch. Like Home it never scrolls and never
/// shrinks: it widens from four to six columns, then grows to three rows,
/// and past that the files gather into stacks by kind. It never narrows as
/// files are added.
public enum FileGridLayout {
    public static let cellWidth: CGFloat = 78
    public static let spacing: CGFloat = 6
    public static let minimumColumns = 4
    public static let maximumColumns = 6
    public static let maximumRows = 3
    public static var capacity: Int { maximumColumns * maximumRows }

    /// One column per file from four to six; then rows grow.
    public static func columns(for count: Int) -> Int { min(maximumColumns, max(minimumColumns, count)) }

    public static func width(columns: Int) -> CGFloat {
        CGFloat(columns) * cellWidth + CGFloat(columns - 1) * spacing
    }

    /// Whether `count` files show as stacks rather than one by one.
    public static func stacks(_ count: Int) -> Bool { count > capacity }

    /// A stack's files when it's open: all of them when they fit, else the
    /// ones that do beside a last cell for the rest.
    public static func visible(_ count: Int) -> (shown: Int, more: Int) {
        count <= capacity ? (count, 0) : (capacity - 1, count - capacity + 1)
    }
}

/// Files of one kind, for a stack.
public struct FileStack: Equatable, Identifiable, Sendable {
    public enum Kind: Int, CaseIterable, Sendable {
        case folders, images, movies, audio, pdfs, documents, archives, other
        public var title: String {
            switch self {
            case .folders: "Folders"
            case .images: "Photos"
            case .movies: "Movies"
            case .audio: "Audio"
            case .pdfs: "PDFs"
            case .documents: "Documents"
            case .archives: "Archives"
            case .other: "Other"
            }
        }
    }
    public let kind: Kind
    public let files: [DroppedFile]
    public var id: Kind { kind }

    public static func kind(of file: DroppedFile) -> Kind {
        if file.kind == .folder { return .folders }
        guard let type = UTType(file.type) ?? UTType(importedAs: file.type) as UTType? else { return .other }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .movies }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) { return .pdfs }
        if type.conforms(to: .archive) { return .archives }
        if [UTType.text, .presentation, .spreadsheet, .rtf].contains(where: type.conforms(to:)) ||
            ["com.microsoft.", "com.apple.iwork.", "org.openxmlformats.", "org.oasis-open."].contains(where: type.identifier.hasPrefix) {
            return .documents
        }
        return .other
    }

    /// Stacks in a fixed order, each keeping the files' own order; empty kinds are left out.
    public static func group(_ files: [DroppedFile]) -> [FileStack] {
        let grouped = Dictionary(grouping: files, by: kind(of:))
        return Kind.allCases.compactMap { kind in grouped[kind].map { FileStack(kind: kind, files: $0) } }
    }
}
