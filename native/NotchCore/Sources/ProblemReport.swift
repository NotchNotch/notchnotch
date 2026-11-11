import Foundation

/// Something that went wrong: an extension that failed or stopped, a Store
/// update that couldn't install, or a process that crashed.
public struct Problem: Codable, Equatable, Sendable {
    public var date: Date
    /// The extension id, or "NotchNotch" for the app itself.
    public var source: String
    public var message: String
    public init(date: Date, source: String, message: String) {
        self.date = date
        self.source = source
        self.message = message
    }
}

/// The opt-in record of problems that survives restarts. Bounded by count and
/// age, so it never grows into a history of how the Mac was used.
public struct ProblemJournal: Codable, Equatable, Sendable {
    public static let maximumCount = 200
    public static let maximumAge: TimeInterval = 14 * 24 * 3600
    public private(set) var problems: [Problem] = []
    /// Crash reports up to this date are already in the journal.
    public var crashesCheckedUntil: Date?

    public init() {}

    /// Adds `problem` unless the same source reported the same message in the
    /// last minute (a restart loop shouldn't fill the journal), then prunes.
    public mutating func record(_ problem: Problem) {
        let repeated = problems.last { $0.source == problem.source }.map {
            $0.message == problem.message && problem.date.timeIntervalSince($0.date) < 60
        } ?? false
        if !repeated { problems.append(problem) }
        prune(now: problem.date)
    }

    public mutating func prune(now: Date) {
        problems.removeAll { now.timeIntervalSince($0.date) > Self.maximumAge }
        if problems.count > Self.maximumCount { problems.removeFirst(problems.count - Self.maximumCount) }
    }

    public mutating func clear() {
        problems = []
    }

    public static func load(from url: URL) -> ProblemJournal {
        guard let data = try? Data(contentsOf: url) else { return ProblemJournal() }
        return (try? decoder.decode(ProblemJournal.self, from: data)) ?? ProblemJournal()
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(self).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// What matters in a macOS crash report (`.ips`): which process, what killed
/// it and where. The rest of the report (hardware identifiers, every thread,
/// memory maps) stays out of a problem report.
public struct CrashSummary: Equatable, Sendable {
    /// The processes NotchNotch ships, whose crashes belong in a report.
    public static let processes: Set<String> = ["NotchNotch", "ExtensionRunner"]
    public static let maximumFrames = 12

    public var process: String
    public var date: Date
    public var appVersion: String
    public var osVersion: String
    /// For example "EXC_BREAKPOINT (SIGTRAP)".
    public var exception: String
    /// For example "Trace/BPT trap: 5".
    public var termination: String
    /// Messages the process left before it stopped, such as Swift's "Fatal error: Index out of range".
    public var notes: [String]
    /// The crashed thread, innermost first: "image  symbol".
    public var frames: [String]

    /// Reads an `.ips` file: one line of JSON metadata, then the JSON report.
    /// Nil for other report types (hangs, resource use) and unreadable files.
    public init?(ips text: String) {
        guard let newline = text.firstIndex(of: "\n"),
              let header = Self.object(text[..<newline]), header["bug_type"] as? String == "309",
              let body = Self.object(text[text.index(after: newline)...]) else { return nil }
        process = header["app_name"] as? String ?? body["procName"] as? String ?? "Unknown"
        date = (header["timestamp"] as? String).flatMap(Self.parseDate) ?? .distantPast
        appVersion = header["app_version"] as? String ?? ""
        osVersion = header["os_version"] as? String ?? ""
        let exception = body["exception"] as? [String: Any]
        self.exception = [exception?["type"] as? String, (exception?["signal"] as? String).map { "(\($0))" }]
            .compactMap { $0 }.joined(separator: " ")
        termination = (body["termination"] as? [String: Any])?["indicator"] as? String ?? ""
        var notes: [String] = []
        if let asi = body["asi"] as? [String: Any] {
            for case let lines as [String] in asi.values { notes += lines }
        }
        if let message = (body["crashInfo"] as? [String: Any])?["message"] as? String { notes.append(message) }
        self.notes = notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let images = (body["usedImages"] as? [[String: Any]])?.map { $0["name"] as? String ?? "???" } ?? []
        let threads = body["threads"] as? [[String: Any]] ?? []
        let faulting = body["faultingThread"] as? Int ?? threads.firstIndex { $0["triggered"] as? Bool == true } ?? 0
        let frames = threads.indices.contains(faulting) ? threads[faulting]["frames"] as? [[String: Any]] ?? [] : []
        self.frames = frames.prefix(Self.maximumFrames).map { frame in
            let index = frame["imageIndex"] as? Int ?? -1
            let image = images.indices.contains(index) ? images[index] : "???"
            return "\(image)  \(frame["symbol"] as? String ?? "0x" + String(frame["imageOffset"] as? Int ?? 0, radix: 16))"
        }
    }

    /// `.ips` files for NotchNotch's processes, newest first, judged by name
    /// (`Process-2026-11-11-012325.ips`) so nothing else is opened.
    public static func reports(in folder: URL, since: Date) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { url in
            guard url.pathExtension == "ips", let process = url.lastPathComponent.split(separator: "-").first,
                  processes.contains(String(process)) else { return false }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return modified > since
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// One line for the journal.
    public var headline: String {
        "\(process) quit unexpectedly: \([exception, notes.first].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", "))"
    }

    private static func object(_ text: Substring) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    private static func parseDate(_ text: String) -> Date? {
        // "2026-11-11 01:23:25.00 +0330"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return formatter.date(from: text)
    }
}

/// A plain-text problem report the user reads, saves and attaches to an
/// issue themselves. Nothing is sent anywhere.
public struct ProblemReport: Sendable {
    public struct ExtensionLine: Sendable {
        public var id: String
        public var version: String
        public var origin: String
        public var enabled: Bool
        public var error: String?
        public init(id: String, version: String, origin: String, enabled: Bool, error: String? = nil) {
            self.id = id
            self.version = version
            self.origin = origin
            self.enabled = enabled
            self.error = error
        }
    }

    public var appVersion: String
    public var osVersion: String
    public var architecture: String
    public var created: Date
    public var extensions: [ExtensionLine]
    /// From the journal when it's on, otherwise from this session.
    public var problems: [Problem]
    /// Error lines from each extension's log in this session.
    public var recentErrors: [String: [String]]
    public var crashes: [CrashSummary]

    public init(appVersion: String, osVersion: String, architecture: String, created: Date, extensions: [ExtensionLine],
                problems: [Problem], recentErrors: [String: [String]], crashes: [CrashSummary]) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.architecture = architecture
        self.created = created
        self.extensions = extensions
        self.problems = problems
        self.recentErrors = recentErrors
        self.crashes = crashes
    }

    public func text(home: String, userName: String) -> String {
        var lines = ["NotchNotch problem report", "",
                     "App: \(appVersion)", "macOS: \(osVersion)", "Architecture: \(architecture)",
                     "Created: \(Self.format(created))", ""]
        lines.append("Extensions (\(extensions.count))")
        for item in extensions.sorted(by: { $0.id < $1.id }) {
            var line = "  \(item.id) \(item.version), \(item.origin)\(item.enabled ? "" : ", disabled")"
            if let error = item.error { line += "\n    Error: " + error.replacingOccurrences(of: "\n", with: "\n    ") }
            lines.append(line)
        }
        lines += ["", "Problems (\(problems.count))"]
        if problems.isEmpty { lines.append("  None recorded.") }
        for problem in problems.sorted(by: { $0.date < $1.date }) {
            lines.append("  \(Self.format(problem.date))  \(problem.source): " + problem.message.replacingOccurrences(of: "\n", with: " "))
        }
        let errors = recentErrors.filter { !$0.value.isEmpty }
        if !errors.isEmpty {
            lines += ["", "Recent extension errors"]
            for (id, messages) in errors.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(id)")
                lines += messages.map { "    " + $0.replacingOccurrences(of: "\n", with: "\n    ") }
            }
        }
        lines += ["", "Crashes (\(crashes.count))"]
        if crashes.isEmpty { lines.append("  None in the last two weeks.") }
        for crash in crashes {
            lines += ["  \(Self.format(crash.date))  \(crash.process) \(crash.appVersion)",
                      "    \(crash.exception)\(crash.termination.isEmpty ? "" : ", \(crash.termination)")"]
            lines += crash.notes.map { "    " + $0 }
            lines += crash.frames.enumerated().map { "    \($0.offset)  \($0.element)" }
        }
        return Self.redact(lines.joined(separator: "\n") + "\n", home: home, userName: userName)
    }

    /// Replaces the home folder with `~` and the account name with `user`, so
    /// paths in error messages don't name the person who sends the report.
    public static func redact(_ text: String, home: String, userName: String) -> String {
        var text = text
        if home.count > 1 { text = text.replacingOccurrences(of: home, with: "~") }
        if userName.count >= 3 {
            let pattern = "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: userName) + "(?![A-Za-z0-9])"
            text = text.replacingOccurrences(of: pattern, with: "user", options: [.regularExpression, .caseInsensitive])
        }
        return text
    }

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
