import AppKit
import NotchCore
import NotchProtocol

/// One line from the Now Playing adapter (native/NowPlayingAdapter).
struct AdapterLine: Decodable {
    let type: String
    var bundle: String?
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsed: Double?
    var timestamp: Double?
    var rate: Double?
    var playing: Bool?
    var shuffle: Bool?
    var `repeat`: Bool?
    /// Base64 of the picture, only when it changed; empty when there is none.
    var artwork: String?
}

/// Splits a byte stream into lines. The pipe's readability handler calls it
/// serially on one queue, which is what makes the unchecked Sendable safe.
final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    /// The complete lines in `chunk`, keeping a partial last line for the next call.
    /// A runaway line can't grow without bound.
    func lines(adding chunk: Data, limit: Int = 4_000_000) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            lines.append(Data(pending[pending.startIndex..<newline]))
            pending.removeSubrange(pending.startIndex...newline)
        }
        if pending.count > limit { pending.removeAll() }
        return lines
    }
}

/// Turns adapter lines into now-playing states. Pure apart from the clock and
/// the app name it is given, so it can be tested.
struct NowPlayingDecoder {
    private(set) var artwork: String?

    mutating func state(from line: AdapterLine, now: Double, eventID: String, appName: (String) -> String?) -> NowPlayingState? {
        if let encoded = line.artwork {
            artwork = Data(base64Encoded: encoded).flatMap(artworkThumbnail).map { "data:image/jpeg;base64," + $0.base64EncodedString() }
        }
        guard line.type == "state", let bundle = line.bundle, !bundle.isEmpty,
              let title = line.title.map({ String($0.prefix(256)) }), !title.isEmpty else { return nil }
        let artist = String((line.artist ?? "").prefix(256))
        let album = String((line.album ?? "").prefix(256))
        let rate = line.rate ?? 0
        let playing = line.playing ?? (rate > 0)
        func bounded(_ value: Double) -> Double { value.isFinite ? min(604_800, max(0, value)) : 0 }
        let duration = bounded(line.duration ?? 0)
        // MediaRemote gives the position at `timestamp`; it has moved on since if the item is playing.
        var position = line.elapsed ?? 0
        if playing, let timestamp = line.timestamp { position += max(0, now - timestamp) * (rate > 0 ? rate : 1) }
        position = duration > 0 ? min(duration, bounded(position)) : bounded(position)
        let state = NowPlayingState(
            id: String("\(bundle):\(title):\(artist)".prefix(512)), eventID: eventID,
            player: String(bundle.prefix(128)), playerName: appName(bundle).map { String($0.prefix(128)) },
            title: title, artist: artist, album: album, artwork: artwork, duration: duration, position: position,
            isPlaying: playing, volume: 1, shuffle: line.shuffle ?? false, repeating: line.repeat ?? false, updatedAt: now)
        return (try? state.validate()) == nil ? nil : state
    }
}

/// Now Playing for every app macOS shows there: Spotify, Apple Music,
/// browsers, Plex, VLC… It needs no Automation permission. MediaRemote answers
/// only Apple's processes, so the adapter runs inside /usr/bin/perl as a child
/// process; if that keeps failing, `onUnavailable` hands over to the players'
/// own Automation.
@MainActor
final class SystemNowPlaying {
    private(set) var state: NowPlayingState?
    private(set) var lastCommandError: String?
    var onChange: ((NowPlayingState?) -> Void)?
    var onUnavailable: (() -> Void)?

    static let maximumRestarts = 3
    private let adapter: URL
    private var process: Process?
    private var input: FileHandle?
    private var decoder = NowPlayingDecoder()
    private var feedback = PlaybackFeedback()
    private var confirmed: NowPlayingState?
    private var eventID = UUID().uuidString
    private var restarts = 0
    private var stopping = false
    private var settleTask: Task<Void, Never>?

    /// Loads the adapter's exported function into perl and calls it.
    static let script = """
    use DynaLoader;
    my $library = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $symbol = DynaLoader::dl_find_symbol($library, "notchnotch_now_playing_run") or die "missing symbol";
    DynaLoader::dl_install_xsub("main::run", $symbol);
    run();
    """
    static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    /// The adapter beside the app: in the app bundle, next to a development
    /// build, or where NOTCHNOTCH_NOWPLAYING_ADAPTER says. Nil when it or perl is missing.
    static func adapterURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                           bundle: Bundle = .main) -> URL? {
        let candidates = [
            environment["NOTCHNOTCH_NOWPLAYING_ADAPTER"].map { URL(fileURLWithPath: $0) },
            bundle.bundleURL.appendingPathComponent("Contents/Helpers/NowPlayingAdapter.dylib"),
            bundle.executableURL?.deletingLastPathComponent().appendingPathComponent("libNowPlayingAdapter.dylib"),
        ].compactMap { $0 }
        guard FileManager.default.isExecutableFile(atPath: perl.path) else { return nil }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    init?(adapter: URL? = SystemNowPlaying.adapterURL()) {
        guard let adapter else { return nil }
        self.adapter = adapter
    }

    func start() {
        stopping = false
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = ["-e", Self.script, adapter.path]
        let output = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        let buffer = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
            for line in buffer.lines(adding: chunk) {
                guard let decoded = try? JSONDecoder().decode(AdapterLine.self, from: line) else { continue }
                // The main queue keeps lines in order; artwork arrives only on change.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(decoded) } }
            }
        }
        process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.ended() } }
        do {
            try process.run()
            self.process = process
            self.input = input.fileHandleForWriting
        } catch {
            ended()
        }
    }

    func stop() {
        stopping = true
        settleTask?.cancel()
        // Closing stdin makes the adapter exit by itself.
        try? input?.close()
        input = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
    }

    private func ended() {
        process = nil
        input = nil
        guard !stopping else { return }
        restarts += 1
        guard restarts <= Self.maximumRestarts else { onUnavailable?(); return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !self.stopping else { return }
            self.start()
        }
    }

    private func receive(_ line: AdapterLine) {
        guard !stopping else { return }
        if line.type == "unavailable" { stop(); onUnavailable?(); return }
        // A working adapter earns its restarts back.
        restarts = 0
        let id = confirmed?.id
        var next = decoder.state(from: line, now: Date.now.timeIntervalSince1970, eventID: eventID) { bundle in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        }
        if line.type != "state" { return }
        if next?.id != id { eventID = UUID().uuidString; next?.eventID = eventID }
        confirmed = next
        state = feedback.receive(next)
        onChange?(state)
    }

    func perform(_ request: MediaRequest) {
        guard let state, (try? request.validate()) != nil else { return }
        let command: [String: JSONValue]
        switch request.command {
        case .openPlayer:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: state.player) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            return
        case .playPause: command = ["command": .string("togglePlayPause")]
        case .next: command = ["command": .string("next")]
        case .previous: command = ["command": .string("previous")]
        case .seek: command = ["command": .string("seek"), "value": .number((request.value ?? 0) * state.duration)]
        case .volume, .shuffle, .repeatMode:
            lastCommandError = "\(state.playerName ?? "This app") can’t be changed from the notch for that. Use the app."
            onChange?(self.state)
            return
        }
        guard let input, let data = try? JSONEncoder().encode(JSONValue.object(command)) else { return }
        lastCommandError = nil
        try? input.write(contentsOf: data + Data([0x0A]))
        // Show the change at once; the adapter's next line confirms it or the overlay expires.
        feedback.begin(request, state: state)
        self.state = feedback.displayed(state)
        onChange?(self.state)
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.state = self.feedback.receive(self.confirmed)
            self.onChange?(self.state)
        }
    }
}
