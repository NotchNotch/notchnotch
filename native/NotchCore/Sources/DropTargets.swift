import UniformTypeIdentifiers
import NotchProtocol

/// One thing being dragged, as far as choosing zones needs: its type.
public struct DraggedItem: Equatable, Sendable {
    public enum Kind: Sendable { case file, folder, url, text }
    public let kind: Kind
    public let type: UTType
    public init(kind: Kind, type: UTType) { self.kind = kind; self.type = type }
}

/// A drop zone and the extension it belongs to.
public struct DropTarget: Equatable, Identifiable, Sendable {
    public let extensionID: String
    public let zone: DropZone
    public var id: String { "\(extensionID)/\(zone.id)" }
    public init(extensionID: String, zone: DropZone) { self.extensionID = extensionID; self.zone = zone }

    /// Whether it takes these items: every one conforms to a type it accepts,
    /// and there's only one unless it takes several.
    public func accepts(_ items: [DraggedItem]) -> Bool {
        guard !items.isEmpty, items.count == 1 || zone.multiple == true else { return false }
        let types = zone.accepts.compactMap { UTType($0) }
        return items.allSatisfy { item in types.contains { item.type.conforms(to: $0) } }
    }
}

/// What the Drop view shows: up to four zones; with more, three and a More
/// zone that opens the rest when the drag rests on it.
public struct DropArrangement: Equatable, Sendable {
    public static let maximumShown = 4
    public let shown: [DropTarget]
    public let hidden: [DropTarget]
    public var showsMore: Bool { !hidden.isEmpty }

    public init(_ targets: [DropTarget]) {
        if targets.count <= Self.maximumShown { shown = targets; hidden = [] }
        else { shown = Array(targets.prefix(Self.maximumShown - 1)); hidden = Array(targets.dropFirst(Self.maximumShown - 1)) }
    }
}
