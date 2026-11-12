import Foundation
import NotchProtocol

/// `now-playing`: what macOS's Now Playing shows, from any app, and playback
/// controls; Spotify and Apple Music through Automation where Now Playing can't be read.
/// The methods are those of the Music helper it replaced (extensions/music/ADAPTER.md).
@MainActor
final class NowPlayingCapability: JSONRPCCapability {
    private struct Status: Encodable {
        /// "system": every app in macOS's Now Playing, no per-player access.
        /// "players": Spotify and Apple Music through Automation, connected one by one.
        let source: String
        var state: NowPlayingState?
        let authorized: [String]
        let errors: [String: String]
        let commandError: String?
    }
    private let provider = MusicProvider()
    private var system: SystemNowPlaying?

    override init(send: @escaping @MainActor (JSONValue) -> Void) {
        super.init(send: send)
        provider.onChange = { [weak self] _ in self?.changed() }
        if let system = SystemNowPlaying() {
            self.system = system
            system.onChange = { [weak self] _ in self?.changed() }
            // If the adapter can't run here, Spotify and Apple Music still work through Automation.
            system.onUnavailable = { [weak self] in
                guard let self, !self.stopped else { return }
                self.system = nil
                self.provider.start()
                self.changed()
            }
            system.start()
        } else {
            provider.start()
        }
    }

    private func changed() { notify("music/state", status()) }

    override func finish() { system?.stop(); provider.stop() }

    override func handle(_ method: String, _ params: JSONValue?) async throws -> JSONValue {
        switch method {
        case "music/getState":
            return status()
        case "music/connect":
            guard case let .object(fields)? = params, case let .string(id)? = fields["player"],
                  let player = MediaPlayer(rawValue: id) else { throw ProtocolError.invalid("Unknown music player") }
            // Now Playing needs no access per player.
            if system == nil { await provider.connect(player) }
            return status()
        case "music/command":
            guard let params else { throw ProtocolError.invalid("Missing command") }
            let command = try JSONDecoder().decode(MediaRequest.self, from: JSONEncoder().encode(params))
            try command.validate()
            if let system {
                guard system.state != nil else { throw ProtocolError.invalid("No current track") }
                system.perform(command)
            } else {
                guard provider.state != nil else { throw ProtocolError.invalid("No current track") }
                provider.perform(command)
            }
            return .null
        default:
            throw CapabilityError.unknownMethod
        }
    }

    private func status() -> JSONValue {
        let status = system.map { system in
            Status(source: "system", state: system.state, authorized: [], errors: [:],
                   commandError: system.lastCommandError.map { String($0.prefix(1024)) })
        } ?? Status(source: "players", state: provider.state, authorized: provider.authorized.map(\.rawValue).sorted(),
            errors: Dictionary(uniqueKeysWithValues: provider.errors.map { ($0.key.rawValue, String($0.value.prefix(1024))) }),
            commandError: provider.lastCommandError.map { String($0.prefix(1024)) })
        // Inline Apple Music artwork is the only large field; drop it before anything else.
        return Self.json(status) { status in
            guard status.state?.artwork != nil else { return false }
            status.state?.artwork = nil
            return true
        }
    }
}
