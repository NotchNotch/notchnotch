import Foundation
import Testing
@testable import NotchCapabilities

@Test func linesAreSplitAcrossChunks() {
    let buffer = LineBuffer()
    #expect(buffer.lines(adding: Data("{\"a\":1}\n{\"b\"".utf8)) == [Data("{\"a\":1}".utf8)])
    #expect(buffer.lines(adding: Data(":2}\n".utf8)) == [Data("{\"b\":2}".utf8)])
    // A line that never ends is dropped instead of growing forever.
    #expect(buffer.lines(adding: Data(repeating: 0x41, count: 20), limit: 10).isEmpty)
    #expect(buffer.lines(adding: Data("ok\n".utf8)) == [Data("ok".utf8)])
}

@Test func adapterLinesBecomeNowPlayingStates() throws {
    var decoder = NowPlayingDecoder()
    let line = AdapterLine(type: "state", bundle: "company.thebrowser.dia", title: "A talk", artist: "Someone", album: "",
                           duration: 1825, elapsed: 7, timestamp: 1_000, rate: 1, playing: true, shuffle: false, repeat: false, artwork: "")
    let state = try #require(decoder.state(from: line, now: 1_010, eventID: "e1") { _ in "Dia" })
    #expect(state.player == "company.thebrowser.dia" && state.playerName == "Dia")
    #expect(state.id == "company.thebrowser.dia:A talk:Someone")
    // Playing for ten seconds since the timestamp moves the position on.
    #expect(state.position == 17 && state.isPlaying && state.artwork == nil)
    // Paused: the position stays where MediaRemote left it.
    var paused = line; paused.playing = false; paused.rate = 0
    #expect(decoder.state(from: paused, now: 1_010, eventID: "e1") { _ in nil }?.position == 7)
    // Nothing playing, or no title, is no state.
    #expect(decoder.state(from: AdapterLine(type: "state"), now: 0, eventID: "e") { _ in nil } == nil)
    var untitled = line; untitled.title = ""
    #expect(decoder.state(from: untitled, now: 0, eventID: "e") { _ in nil } == nil)
    // Positions never pass the end.
    var late = line; late.elapsed = 1_820
    #expect(decoder.state(from: late, now: 1_100, eventID: "e") { _ in nil }?.position == 1825)
}

@Test func artworkIsKeptUntilTheAdapterSaysItChanged() throws {
    var decoder = NowPlayingDecoder()
    // A 1×1 PNG.
    let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    var line = AdapterLine(type: "state", bundle: "com.spotify.client", title: "Song", artwork: png)
    #expect(decoder.state(from: line, now: 0, eventID: "e") { _ in nil }?.artwork?.hasPrefix("data:image/jpeg;base64,") == true)
    line.artwork = nil
    #expect(decoder.state(from: line, now: 0, eventID: "e") { _ in nil }?.artwork != nil)
    line.artwork = ""
    #expect(decoder.state(from: line, now: 0, eventID: "e") { _ in nil }?.artwork == nil)
}

/// Runs the real adapter in perl against this Mac's Now Playing. Off by default:
/// it needs a built adapter and something playing or paused.
/// NOTCHNOTCH_NOWPLAYING_ADAPTER=.build/debug/libNowPlayingAdapter.dylib NOTCHNOTCH_LIVE_NOWPLAYING=1 swift test --filter live
@Test(.enabled(if: ProcessInfo.processInfo.environment["NOTCHNOTCH_LIVE_NOWPLAYING"] == "1"))
@MainActor func liveNowPlayingComesThroughPerl() async throws {
    let source = try #require(SystemNowPlaying())
    var states: [NowPlayingStateSummary] = []
    var unavailable = false
    source.onChange = { state in if let state { states.append(.init(player: state.player, title: state.title, artwork: state.artwork != nil)) } }
    source.onUnavailable = { unavailable = true }
    source.start()
    for _ in 0..<50 where states.isEmpty && !unavailable { try await Task.sleep(for: .milliseconds(100)) }
    source.stop()
    #expect(!unavailable)
    let first = try #require(states.first)
    print("LIVE now playing:", first)
    #expect(!first.player.isEmpty && !first.title.isEmpty)
}

struct NowPlayingStateSummary: CustomStringConvertible {
    let player: String, title: String, artwork: Bool
    var description: String { "\(player) · \(title) · artwork \(artwork)" }
}
