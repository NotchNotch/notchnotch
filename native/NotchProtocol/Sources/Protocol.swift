import Foundation

public let protocolVersion = 1
public let maximumMessageBytes = 262_144
/// One extension's storage object; leaves room for the envelope that carries it to the app.
public let maximumStorageBytes = maximumMessageBytes - 1024

// The message types themselves are generated from schemas/ into
// Generated.swift. This file adds their rules and helpers.

extension NodeKind {
    /// Nodes that send user actions. Compact wings are a single host click target.
    public var isInteractive: Bool { [.button, .textField, .toggle, .picker, .player].contains(self) }
    /// Nodes the management window can render with system controls.
    public static let settingsKinds: Set<NodeKind> = [
        .column, .row, .text, .symbol, .progress, .button, .textField,
        .spacer, .divider, .toggle, .section, .listItem, .badge, .picker,
    ]
}

extension Snapshot {
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
                  (node.props.unit?.count ?? 0) <= 32,
                  (node.props.name?.count ?? 0) <= 128,
                  (node.props.action?.count ?? 0) <= 128,
                  (node.props.label?.count ?? 0) <= 256 else {
                throw ProtocolError.invalid("Invalid or oversized UI tree")
            }
            if compact && node.type.isInteractive {
                throw ProtocolError.invalid("Compact content cannot contain interactive controls")
            }
            if settings && !NodeKind.settingsKinds.contains(node.type) {
                throw ProtocolError.invalid("Settings cannot contain media components, values or rings")
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
            if [.spacer, .divider, .picker, .value].contains(node.type), !node.children.isEmpty {
                throw ProtocolError.invalid("Spacers, dividers, pickers and values cannot have children")
            }
            if let source = node.props.source, !NowPlayingState.isArtworkSource(source, imageHosts: imageHosts) {
                throw ProtocolError.invalid("Artwork must use a host declared in the manifest's imageHosts or bounded image data")
            }
            if let media = node.props.media { try media.validate(imageHosts: imageHosts) }
            if node.type == .player, node.props.media == nil {
                throw ProtocolError.invalid("A music player requires now-playing state")
            }
            if let value = node.props.value, !value.isFinite || !(0...1).contains(value) {
                throw ProtocolError.invalid("Progress and rings must be between zero and one")
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

/// The first line a runner started with `--preferences` reads, before it runs
/// the extension, so preference values are available to top-level code.
public struct RunnerPreferences: Codable, Sendable {
    public var protocolVersion = 1
    public var type = "preferences"
    public var values: [String: JSONValue]
    public init(values: [String: JSONValue]) { self.values = values }
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

extension ExtensionManifest {
    /// An `icon` ending in `.png` names a file in the package's `assets/`
    /// folder. Any other value is an SF Symbol name.
    public var iconFile: String? {
        guard let icon, icon.hasSuffix(".png") else { return nil }
        return icon
    }

    public func validate() throws {
        guard id.range(of: "^[a-z][a-z0-9.-]{2,79}$", options: .regularExpression) != nil,
              !name.isEmpty, name.count <= 128, !version.isEmpty, version.count <= 64,
              apiVersion == 1, entry == "bundle.js", Set(permissions).count == permissions.count,
              permissions.allSatisfy({ ["local-network", "process"].contains($0) || SystemCapability(rawValue: $0) != nil }),
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
        if let preferences {
            guard preferences.count <= ExtensionPreference.maximumCount,
                  Set(preferences.map(\.name)).count == preferences.count else {
                throw ProtocolError.invalid("preferences must list up to 16 entries with unique names.")
            }
            for preference in preferences { try preference.validate() }
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

/// One setting declared in the manifest. The app stores its value, draws the
/// field in Setup and hands the values to the extension when it starts.
extension ExtensionPreference {
    public typealias Kind = PreferenceKind
    public typealias Option = PreferenceOption

    public static let maximumCount = 16
    public static let maximumTextBytes = 4096

    public var isRequired: Bool { required == true }

    func validate() throws {
        let fail = { (reason: String) in ProtocolError.invalid("Preference \(name): \(reason)") }
        guard name.range(of: "^[A-Za-z][A-Za-z0-9_]{0,31}$", options: .regularExpression) != nil else {
            throw ProtocolError.invalid("Preference names use letters, digits and _, start with a letter, up to 32 characters.")
        }
        guard (1...64).contains(title.count), (description?.count ?? 0) <= 256, (placeholder?.count ?? 0) <= 128 else {
            throw fail("title is 1–64 characters, description up to 256, placeholder up to 128.")
        }
        switch type {
        case .text:
            if let value = self.default { guard case let .string(text) = value, text.utf8.count <= Self.maximumTextBytes else { throw fail("default must be text.") } }
        case .password:
            guard self.default == nil else { throw fail("a password can't have a default.") }
        case .toggle:
            guard !isRequired else { throw fail("a toggle can't be required.") }
            if let value = self.default { guard case .bool = value else { throw fail("default must be true or false.") } }
        case .dropdown:
            guard let options, (1...32).contains(options.count), Set(options.map(\.value)).count == options.count,
                  options.allSatisfy({ (1...64).contains($0.value.count) && (1...64).contains($0.title.count) }) else {
                throw fail("a dropdown needs 1–32 options with unique values and titles of up to 64 characters.")
            }
            if let value = self.default {
                guard case let .string(selected) = value, options.contains(where: { $0.value == selected }) else {
                    throw fail("default must be one of the option values.")
                }
            }
        }
        if type != .dropdown, options != nil { throw fail("only a dropdown has options.") }
    }

    /// Whether `value` is acceptable for this preference.
    public func accepts(_ value: JSONValue) -> Bool {
        switch (type, value) {
        case (.text, .string(let text)), (.password, .string(let text)): text.utf8.count <= Self.maximumTextBytes
        case (.toggle, .bool): true
        case (.dropdown, .string(let selected)): options?.contains { $0.value == selected } ?? false
        default: false
        }
    }
}

extension ExtensionManifest {
    /// Stored values with defaults filled in. Values that no longer fit their
    /// preference, or belong to none, are dropped.
    public func preferenceValues(stored: [String: JSONValue]) -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        for preference in preferences ?? [] {
            if let value = stored[preference.name], preference.accepts(value) { values[preference.name] = value }
            else if let value = preference.default { values[preference.name] = value }
        }
        return values
    }

    /// Titles of required preferences that have no value yet.
    public func missingRequiredPreferences(stored: [String: JSONValue]) -> [String] {
        let values = preferenceValues(stored: stored)
        return (preferences ?? []).filter { preference in
            guard preference.isRequired else { return false }
            if case let .string(text)? = values[preference.name] { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return values[preference.name] == nil
        }.map(\.title)
    }
}

public enum ProtocolError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

/// Protected data the app reads for an extension in place of a native helper.
/// Each one is a manifest permission and a JSON-RPC stream with the connection
/// identifier `capability:<name>`, which a manifest connection can't use.
public enum SystemCapability: String, CaseIterable, Sendable {
    case calendar
    case nowPlaying = "now-playing"

    public static let connectionPrefix = "capability:"
    public var connectionID: String { Self.connectionPrefix + rawValue }

    public init?(connectionID: String) {
        guard connectionID.hasPrefix(Self.connectionPrefix) else { return nil }
        self.init(rawValue: String(connectionID.dropFirst(Self.connectionPrefix.count)))
    }
}
