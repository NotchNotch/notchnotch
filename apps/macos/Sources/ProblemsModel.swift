import Foundation
import Observation
import NotchCore

/// Problems for the user's own report. Nothing here is sent anywhere: the
/// report is a text file the user reads, saves and attaches to an issue.
///
/// Problems from this session are always kept in memory, like extension logs.
/// Keeping them between launches, and noticing crashes from earlier runs, is
/// opt-in ("Remember problems").
@MainActor @Observable
final class ProblemsModel {
    static let maximumCrashesInReport = 5
    private let journalURL: URL
    private let crashFolder: URL
    private(set) var journal = ProblemJournal()
    private(set) var session: [Problem] = []
    /// The newest crash found since the journal last looked, until the user sees it.
    private(set) var unseenCrash: CrashSummary?
    @ObservationIgnored var onUnseenCrash: ((CrashSummary) -> Void)?

    var remembers: Bool = UserDefaults.standard.bool(forKey: "remembersProblems") {
        didSet {
            guard remembers != oldValue else { return }
            UserDefaults.standard.set(remembers, forKey: "remembersProblems")
            if remembers {
                for problem in session { journal.record(problem) }
                save()
                Task { await importCrashes() }
            } else {
                journal = ProblemJournal()
                unseenCrash = nil
                try? FileManager.default.removeItem(at: journalURL)
            }
        }
    }

    init(directory: URL, crashFolder: URL? = nil) {
        journalURL = directory.appendingPathComponent("Problems.json")
        self.crashFolder = crashFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
    }

    func start() {
        guard remembers else { return }
        journal = ProblemJournal.load(from: journalURL)
        journal.prune(now: .now)
        Task { await importCrashes() }
    }

    /// Problems the report lists: the journal when it's on, otherwise this session's.
    var problems: [Problem] { remembers ? journal.problems : session }

    func record(_ source: String, _ message: String) {
        let problem = Problem(date: .now, source: source, message: message)
        session.append(problem)
        if session.count > ProblemJournal.maximumCount { session.removeFirst() }
        guard remembers else { return }
        journal.record(problem)
        save()
    }

    func clear() {
        session = []
        journal.clear()
        unseenCrash = nil
        if remembers { save() }
    }

    func markCrashSeen() { unseenCrash = nil }

    /// Adds crashes of NotchNotch's processes that happened since the journal
    /// last looked (two weeks back the first time).
    private func importCrashes() async {
        // The first look goes two weeks back but announces nothing: those
        // crashes happened before the user asked to hear about them.
        let firstLook = journal.crashesCheckedUntil == nil
        let since = journal.crashesCheckedUntil ?? .now.addingTimeInterval(-ProblemJournal.maximumAge)
        let checked = Date.now
        let crashes = await Self.readCrashes(in: crashFolder, since: since, limit: 20)
        guard remembers else { return }
        for crash in crashes.reversed() {
            journal.record(Problem(date: crash.date, source: crash.process, message: crash.headline))
        }
        journal.crashesCheckedUntil = checked
        if !firstLook, let newest = crashes.first {
            unseenCrash = newest
            onUnseenCrash?(newest)
        }
        save()
    }

    /// The report's text. Crash reports are read fresh from macOS's folder.
    func report(extensions: [ProblemReport.ExtensionLine], recentErrors: [String: [String]]) async -> String {
        let crashes = await Self.readCrashes(in: crashFolder, since: .now.addingTimeInterval(-ProblemJournal.maximumAge),
                                             limit: Self.maximumCrashesInReport)
        let info = Bundle.main.infoDictionary ?? [:]
        let app = (info["CFBundleShortVersionString"] as? String).map { "\($0) (\(info["CFBundleVersion"] as? String ?? "1"))" }
            ?? "development build"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "Apple silicon"
        #else
        let architecture = "Intel"
        #endif
        let report = ProblemReport(appVersion: app, osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                                   architecture: architecture, created: .now, extensions: extensions, problems: problems,
                                   recentErrors: recentErrors, crashes: crashes)
        return report.text(home: NSHomeDirectory(), userName: NSUserName())
    }

    private nonisolated static func readCrashes(in folder: URL, since: Date, limit: Int) async -> [CrashSummary] {
        await Task.detached(priority: .utility) {
            CrashSummary.reports(in: folder, since: since).lazy
                .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                .compactMap(CrashSummary.init(ips:))
                .prefix(limit).map { $0 }
        }.value
    }

    private func save() {
        try? journal.save(to: journalURL)
    }
}
