import Foundation

public let protocolVersion = 1
public let maximumMessageBytes = 262_144

public enum SurfaceKind: String, Codable, Sendable { case activity, prompt }
public enum Presentation: String, Codable, Sendable { case compact, expanded }
public enum SurfacePhase: String, Codable, Sendable { case active, paused, completed, pending }
public enum NodeKind: String, Codable, Sendable {
    case column, row, text, symbol, progress, button, textField, artwork, waveform, player
    case spacer, divider, toggle, section, listItem, badge, picker

    /// Nodes that send user actions. Compact wings are a single host click target.
    public var isInteractive: Bool { [.button, .textField, .toggle, .picker, .player].contains(self) }
    /// Nodes the management window can render with system controls.
    public static let settingsKinds: Set<NodeKind> = [
        .column, .row, .text, .symbol, .progress, .button, .textField,
        .spacer, .divider, .toggle, .section, .listItem, .badge, .picker,
    ]
}
public enum Tone: String, Codable, Sendable { case primary, secondary, accent, success, warning, danger }
public enum TextSize: String, Codable, Sendable { case caption, body, headline, title, timer }
public enum Spacing: String, Codable, Sendable { case none, tight, regular, loose }
public enum LayoutAlignment: String, Codable, Sendable { case start, center, end }
public struct PickerOption: Codable, Equatable, Hashable, Sendable {
    public var value: String
    public var label: String
    public init(value: String, label: String) { self.value = value; self.label = label }
}

public struct NodeProps: Codable, Equatable, Sendable {
    public var text: String?
    public var name: String?
    public var tone: Tone?
    public var size: TextSize?
    public var value: Double?
    public var action: String?
    public var placeholder: String?
    public var source: String?
    public var media: NowPlayingState?
    public var disabled: Bool?
    /// Secondary line: list item subtitle or section footer.
    public var detail: String?
    public var spacing: Spacing?
    public var align: LayoutAlignment?
    /// Picker choices; `selection` holds the chosen value.
    public var options: [PickerOption]?
    public var selection: String?

    public init(text: String? = nil, name: String? = nil, tone: Tone? = nil, size: TextSize? = nil,
                value: Double? = nil, action: String? = nil, placeholder: String? = nil, disabled: Bool? = nil,
                source: String? = nil, media: NowPlayingState? = nil, detail: String? = nil,
                spacing: Spacing? = nil, align: LayoutAlignment? = nil,
                options: [PickerOption]? = nil, selection: String? = nil) {
        self.text = text; self.name = name; self.tone = tone; self.size = size
        self.value = value; self.action = action; self.placeholder = placeholder; self.disabled = disabled
        self.source = source; self.media = media; self.detail = detail; self.spacing = spacing; self.align = align
        self.options = options; self.selection = selection
    }
}

public struct UINode: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: NodeKind
    public var props: NodeProps
    public var children: [UINode]
    public init(id: String, type: NodeKind, props: NodeProps = .init(), children: [UINode] = []) {
        self.id = id; self.type = type; self.props = props; self.children = children
    }
}

public struct CompactContent: Codable, Equatable, Sendable {
    public var leading: [UINode]
    public var trailing: [UINode]
    public init(leading: [UINode], trailing: [UINode]) { self.leading = leading; self.trailing = trailing }
}

/// A new id announces a new event. Ordinary snapshots keep the same id.
public struct PeekContent: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var duration: Double
    public init(id: String, text: String, duration: Double = 4) {
        self.id = id; self.text = text; self.duration = duration
    }
}

public struct Surface: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: SurfaceKind
    public var title: String
    public var initialView: Presentation
    public var phase: SurfacePhase
    public var compact: CompactContent?
    public var expanded: UINode
    public var peek: PeekContent?
    public var idlePreview: Bool?

    public init(id: String, kind: SurfaceKind, title: String, initialView: Presentation = .compact,
                phase: SurfacePhase = .active, compact: CompactContent? = nil, expanded: UINode, peek: PeekContent? = nil, idlePreview: Bool? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.initialView = initialView
        self.phase = phase; self.compact = compact; self.expanded = expanded; self.peek = peek; self.idlePreview = idlePreview
    }
}

public struct Snapshot: Codable, Sendable {
    public var protocolVersion: Int
    public var type: String
    public var extensionID: String
    public var revision: Int
    public var surfaces: [Surface]
    public var settings: UINode?
    public init(extensionID: String, revision: Int, surfaces: [Surface], settings: UINode? = nil) {
        self.protocolVersion = 1; self.type = "snapshot"; self.extensionID = extensionID
        self.revision = revision; self.surfaces = surfaces
        self.settings = settings
    }

    /// `imageHosts` comes from the sender's manifest and limits remote artwork.
    public func validate(expectedExtensionID: String, imageHosts: [String] = []) throws {
        guard protocolVersion == 1, type == "snapshot", extensionID == expectedExtensionID, revision > 0,
              surfaces.count <= 16, Set(surfaces.map(\.id)).count == surfaces.count else {
            throw ProtocolError.invalid("Invalid snapshot envelope")
        }
        var count = 0
        var identifiers = Set<String>()
        func visit(_ node: UINode, depth: Int, compact: Bool = false, settings: Bool = false) throws {
            count += 1
            guard depth <= 16, count <= 512, !node.id.isEmpty, node.id.count <= 128,
                  identifiers.insert(node.id).inserted,
                  (node.props.text?.count ?? 0) <= 4096,
                  (node.props.detail?.count ?? 0) <= 4096,
                  (node.props.name?.count ?? 0) <= 128,
                  (node.props.action?.count ?? 0) <= 128 else {
                throw ProtocolError.invalid("Invalid or oversized UI tree")
            }
            if compact && node.type.isInteractive {
                throw ProtocolError.invalid("Compact content cannot contain interactive controls")
            }
            if settings && !NodeKind.settingsKinds.contains(node.type) {
                throw ProtocolError.invalid("Settings cannot contain media components")
            }
            if let options = node.props.options {
                guard node.type == .picker, (1...32).contains(options.count),
                      Set(options.map(\.value)).count == options.count,
                      options.allSatisfy({ !$0.value.isEmpty && $0.value.count <= 128 && $0.label.count <= 128 }) else {
                    throw ProtocolError.invalid("A picker needs 1–32 options with unique values")
                }
            }
            if node.type == .picker {
                guard let options = node.props.options,
                      node.props.selection.map({ value in options.contains { $0.value == value } }) ?? true else {
                    throw ProtocolError.invalid("A picker selection must match one of its options")
                }
            }
            if [.spacer, .divider, .picker].contains(node.type), !node.children.isEmpty {
                throw ProtocolError.invalid("Spacers, dividers and pickers cannot have children")
            }
            if let source = node.props.source, !NowPlayingState.isArtworkSource(source, imageHosts: imageHosts) {
                throw ProtocolError.invalid("Artwork must use a host declared in the manifest's imageHosts or bounded image data")
            }
            if let media = node.props.media { try media.validate(imageHosts: imageHosts) }
            if node.type == .player, node.props.media == nil {
                throw ProtocolError.invalid("A music player requires now-playing state")
            }
            if let value = node.props.value, !value.isFinite || !(0...1).contains(value) {
                throw ProtocolError.invalid("Progress must be between zero and one")
            }
            for child in node.children { try visit(child, depth: depth + 1, compact: compact, settings: settings) }
        }
        for surface in surfaces {
            guard !surface.id.isEmpty, surface.id.count <= 128, !surface.title.isEmpty, surface.title.count <= 128,
                  surface.compact != nil || surface.initialView == .expanded,
                  surface.kind == .prompt ? surface.phase == .pending : surface.phase != .pending else {
                throw ProtocolError.invalid("Invalid surface contract")
            }
            if surface.idlePreview == true, surface.kind != .activity || surface.compact == nil {
                throw ProtocolError.invalid("Idle previews require an activity with compact content")
            }
            if let peek = surface.peek {
                guard surface.kind == .activity, surface.compact != nil,
                      !peek.id.isEmpty, peek.id.count <= 128, !peek.text.isEmpty, peek.text.count <= 256,
                      peek.duration.isFinite, (1...10).contains(peek.duration) else {
                    throw ProtocolError.invalid("A peek requires an activity with compact content, an event id, text, and a duration of 1–10 seconds")
                }
            }
            try visit(surface.expanded, depth: 0)
            for node in (surface.compact?.leading ?? []) + (surface.compact?.trailing ?? []) {
                try visit(node, depth: 0, compact: true)
            }
        }
        if let settings { try visit(settings, depth: 0, settings: true) }
    }
}

public struct UserEvent: Codable, Sendable {
    public var protocolVersion = 1
    public var type = "event"
    public var action: String
    public var value: String?
    public init(action: String, value: String? = nil) { self.action = action; self.value = value }
}

/// Host-to-runner liveness check. The runner answers with `RunnerPong` from
/// the thread that executes JavaScript.
public struct RunnerPing: Codable, Sendable {
    public var protocolVersion = 1
    public var type = "ping"
    public var id: Int
    public init(id: Int) { self.id = id }
}

public struct RunnerPong: Codable, Sendable {
    public var protocolVersion = 1
    public var type = "pong"
    public var extensionID: String
    public var id: Int
    public init(extensionID: String, id: Int) { self.extensionID = extensionID; self.id = id }
}

public struct RuntimeNotice: Codable, Sendable {
    public var protocolVersion = 1
    public var type: String
    public var extensionID: String
    public var message: String
    public init(type: String, extensionID: String, message: String) {
        self.type = type; self.extensionID = extensionID; self.message = String(message.prefix(4096))
    }
}

public struct ExtensionManifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var apiVersion: Int
    public var entry: String
    public var permissions: [String]
    public var connections: [String: ConnectionDefinition]?
    public var icon: String?
    public var description: String?
    /// HTTPS hosts the host may fetch artwork from for this extension.
    public var imageHosts: [String]?
    /// HTTPS hosts the extension may reach with `fetch`.
    public var network: [String]?
    /// Store handle of the publisher, such as a GitHub user name.
    public var author: String?
    /// One to three entries from `ExtensionCategory.all`.
    public var categories: [String]?
    public var homepage: String?
    public var repository: String?
    /// An SPDX license expression, such as `MIT`.
    public var license: String?

    /// An `icon` ending in `.png` names a file in the package's `assets/`
    /// folder; `name@dark.png` beside it is the optional dark variant. Any
    /// other value is an SF Symbol name.
    public var iconFiles: (light: String, dark: String)? {
        guard let icon, icon.hasSuffix(".png") else { return nil }
        return (icon, String(icon.dropLast(4)) + "@dark.png")
    }

    public func validate() throws {
        guard id.range(of: "^[a-z][a-z0-9.-]{2,79}$", options: .regularExpression) != nil,
              !name.isEmpty, name.count <= 128, !version.isEmpty, version.count <= 64,
              apiVersion == 1, entry == "bundle.js", Set(permissions).count == permissions.count,
              permissions.allSatisfy({ ["local-network", "process"].contains($0) }),
              (icon?.count ?? 0) <= 128, (description?.count ?? 0) <= 512,
              (connections?.count ?? 0) <= 8 else {
            throw ProtocolError.invalid("Invalid API v1 extension manifest or permissions")
        }
        if let imageHosts {
            guard imageHosts.count <= ImageHost.maximumCount, Set(imageHosts).count == imageHosts.count,
                  imageHosts.allSatisfy(ImageHost.isValidPattern) else {
                throw ProtocolError.invalid("imageHosts must list up to 8 lowercase DNS names, optionally starting with *.")
            }
        }
        if let network {
            guard network.count <= NetworkHosts.maximumCount, Set(network).count == network.count,
                  network.allSatisfy(ImageHost.isValidPattern) else {
                throw ProtocolError.invalid("network must list up to 16 lowercase DNS names, optionally starting with *.")
            }
        }
        try validateStoreMetadata()
        if let icon, icon.hasSuffix(".png") {
            guard icon.range(of: "^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,99}\\.png$", options: .regularExpression) != nil else {
                throw ProtocolError.invalid("icon must be an SF Symbol name or the file name of a PNG in assets/, such as icon.png.")
            }
        }
        for (id, definition) in connections ?? [:] {
            guard id.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil else {
                throw ProtocolError.invalid("Invalid connection identifier")
            }
            try definition.validate(permissions: permissions)
        }
    }
}

extension ExtensionManifest {
    /// Optional fields that describe the extension for people browsing or
    /// installing it. They never grant anything.
    func validateStoreMetadata() throws {
        if let author, author.range(of: "^[a-z0-9]([a-z0-9-]{0,37}[a-z0-9])?$", options: .regularExpression) == nil {
            throw ProtocolError.invalid("author must be a store handle: lowercase letters, digits and hyphens, up to 39 characters.")
        }
        if let categories {
            guard (1...3).contains(categories.count), Set(categories).count == categories.count,
                  categories.allSatisfy(ExtensionCategory.all.contains) else {
                throw ProtocolError.invalid("categories must list one to three of: \(ExtensionCategory.all.joined(separator: ", ")).")
            }
        }
        for (field, value) in [("homepage", homepage), ("repository", repository)] {
            guard let value else { continue }
            guard value.count <= 2048, let url = URLComponents(string: value), url.scheme == "https",
                  !(url.host ?? "").isEmpty, url.user == nil, url.password == nil else {
                throw ProtocolError.invalid("\(field) must be an https:// address.")
            }
        }
        if let license, license.count > 64 ||
            license.range(of: "^[A-Za-z0-9.+-]+( (AND|OR|WITH) [A-Za-z0-9.+-]+)*$", options: .regularExpression) == nil {
            throw ProtocolError.invalid("license must be an SPDX license identifier, such as MIT.")
        }
    }
}

/// Categories an extension can list in its manifest, in display order.
public enum ExtensionCategory {
    public static let all = [
        "Communication", "Developer Tools", "Finance", "Fun", "Health", "Media",
        "News", "Productivity", "Sports", "System", "Weather", "Other",
    ]
}

public enum ProtocolError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
