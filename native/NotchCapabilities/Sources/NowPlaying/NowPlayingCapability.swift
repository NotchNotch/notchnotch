import Foundation
import NotchProtocol

/// `now-playing`: the song in Spotify or Apple Music, and playback controls.
/// The methods are those of the Music helper it replaced (extensions/music/ADAPTER.md).
@MainActor
final class NowPlayingCapability: JSONRPCCapability {
    private struct Status: Encodable {
        var state: NowPlayingState?
        let authorized: [String]
        let errors: [String: String]
        let commandError: String?
    }
    private let provider = MusicProvider()

    override init(send: @escaping @MainActor (JSONValue) -> Void) {
        super.init(send: send)
        provider.onChange = { [weak self] _ in
            guard let self else { return }
            self.notify("music/state", self.status())
        }
        provider.start()
    }

    override func finish() { provider.stop() }

    override func handle(_ method: String, _ params: JSONValue?) async throws -> JSONValue {
        switch method {
        case "music/getState":
            return status()
        case "music/connect":
            guard case let .object(fields)? = params, case let .string(id)? = fields["player"],
                  let player = MediaPlayer(rawValue: id) else { throw ProtocolError.invalid("Unknown music player") }
            await provider.connect(player)
            return status()
        case "music/command":
            guard let params else { throw ProtocolError.invalid("Missing command") }
            let command = try JSONDecoder().decode(MediaRequest.self, from: JSONEncoder().encode(params))
            try command.validate()
            guard provider.state != nil else { throw ProtocolError.invalid("No current track") }
            provider.perform(command)
            return .null
        default:
            throw CapabilityError.unknownMethod
        }
    }

    private func status() -> JSONValue {
        let status = Status(state: provider.state, authorized: provider.authorized.map(\.rawValue).sorted(),
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
