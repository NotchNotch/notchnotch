import Foundation

public enum MediaCommand: String, Codable, Sendable {
    case playPause, previous, next, seek, volume, shuffle, repeatMode = "repeat", openPlayer
}

public struct NowPlayingState: Codable, Equatable, Sendable {
    public var id: String
    public var eventID: String
    public var player: String
    public var playerName: String?
    public var title: String
    public var artist: String
    public var album: String
    public var artwork: String?
    public var duration: Double
    public var position: Double
    public var isPlaying: Bool
    public var volume: Double
    public var shuffle: Bool
    public var repeating: Bool
    public var updatedAt: Double

    public init(id: String, eventID: String, player: String, playerName: String? = nil, title: String, artist: String,
                album: String = "", artwork: String? = nil, duration: Double, position: Double,
                isPlaying: Bool, volume: Double = 1, shuffle: Bool = false, repeating: Bool = false,
                updatedAt: Double = Date.now.timeIntervalSince1970) {
        self.id = id; self.eventID = eventID; self.player = player; self.title = title; self.artist = artist
        self.playerName = playerName; self.album = album; self.artwork = artwork; self.duration = duration; self.position = position
        self.isPlaying = isPlaying; self.volume = volume; self.shuffle = shuffle; self.repeating = repeating
        self.updatedAt = updatedAt
    }

    /// `imageHosts` are the artwork hosts the sending extension declared in its manifest.
    public func validate(imageHosts: [String] = []) throws {
        guard !id.isEmpty, id.count <= 512, !eventID.isEmpty, eventID.count <= 128,
              !player.isEmpty, player.count <= 128, (playerName?.count ?? 0) <= 128,
              !title.isEmpty, title.count <= 256, artist.count <= 256, album.count <= 256,
              duration.isFinite, (0...604_800).contains(duration),
              position.isFinite, (0...604_800).contains(position),
              volume.isFinite, (0...1).contains(volume), updatedAt.isFinite,
              artwork == nil || Self.isArtworkSource(artwork!, imageHosts: imageHosts) else {
            throw ProtocolError.invalid("Invalid now-playing state")
        }
    }

    /// Bounded JPEG/PNG data is always accepted. HTTPS artwork must come from a
    /// host the extension declared in `imageHosts`; the host fetches it, so an
    /// undeclared host would be an unreviewed network destination.
    public static func isArtworkSource(_ source: String, imageHosts: [String]) -> Bool {
        if isArtworkData(source) { return true }
        guard let host = artworkHost(source) else { return false }
        return imageHosts.contains { ImageHost.matches($0, host: host) }
    }

    /// Shape check without a host policy, for code that only renders already validated snapshots.
    public static func isWellFormedArtworkSource(_ source: String) -> Bool {
        isArtworkData(source) || artworkHost(source) != nil
    }

    private static func isArtworkData(_ source: String) -> Bool {
        (source.hasPrefix("data:image/jpeg;base64,") || source.hasPrefix("data:image/png;base64,")) && source.utf8.count <= 65_536
    }

    private static func artworkHost(_ source: String) -> String? {
        guard source.count <= 2048, let url = URL(string: source), url.scheme == "https",
              let host = url.host?.lowercased(), url.user == nil, url.password == nil, url.port == nil else { return nil }
        return host
    }
}

/// Manifest `imageHosts` entries: an exact DNS name (`i.ytimg.com`) or a
/// subdomain wildcard (`*.mzstatic.com`, which does not match the bare domain).
public enum ImageHost {
    public static let maximumCount = 8

    public static func isValidPattern(_ pattern: String) -> Bool {
        pattern.utf8.count <= 253 &&
            pattern.range(of: #"^(\*\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"#, options: .regularExpression) != nil
    }

    public static func matches(_ pattern: String, host: String) -> Bool {
        if pattern.hasPrefix("*.") { return host.hasSuffix(pattern.dropFirst()) && host.count > pattern.count - 1 }
        return host == pattern
    }
}

public struct MediaRequest: Codable, Sendable {
    public var command: MediaCommand
    public var value: Double?
    public init(command: MediaCommand, value: Double? = nil) { self.command = command; self.value = value }
    public func validate() throws {
        if command == .seek || command == .volume {
            guard let value, value.isFinite, (0...1).contains(value) else {
                throw ProtocolError.invalid("Media position and volume must be between zero and one")
            }
        } else if value != nil { throw ProtocolError.invalid("This media command takes no value") }
    }
}
