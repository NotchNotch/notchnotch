import Foundation
import Testing
@testable import NotchCore

/// Shaped like a real macOS 26 `.ips`: a metadata line, then the report.
private let crashIPS = """
{"app_name":"ExtensionRunner","timestamp":"2026-11-11 01:23:25.00 +0330","app_version":"0.8.0","bug_type":"309","os_version":"macOS 26.5.1 (25F80)","name":"ExtensionRunner"}
{
  "procName" : "ExtensionRunner",
  "modelCode" : "MacBookPro18,3",
  "crashReporterKey" : "SECRET-KEY",
  "exception" : {"type" : "EXC_BREAKPOINT", "signal" : "SIGTRAP"},
  "termination" : {"indicator" : "Trace/BPT trap: 5"},
  "asi" : {"libswiftCore.dylib" : ["Fatal error: Index out of range"]},
  "faultingThread" : 1,
  "threads" : [
    {"frames" : [{"imageOffset" : 16, "imageIndex" : 1}]},
    {"triggered" : true, "frames" : [
      {"imageOffset" : 1144, "symbol" : "Runtime.render()", "imageIndex" : 0},
      {"imageOffset" : 4096, "imageIndex" : 2},
      {"imageOffset" : 130560, "symbol" : "start", "imageIndex" : 1}
    ]}
  ],
  "usedImages" : [{"name" : "ExtensionRunner"}, {"name" : "dyld"}, {"source" : "A"}]
}
"""

@Test func crashSummaryKeepsWhatKilledTheProcessAndWhere() throws {
    let crash = try #require(CrashSummary(ips: crashIPS))
    #expect(crash.process == "ExtensionRunner")
    #expect(crash.appVersion == "0.8.0")
    #expect(crash.osVersion == "macOS 26.5.1 (25F80)")
    #expect(crash.exception == "EXC_BREAKPOINT (SIGTRAP)")
    #expect(crash.termination == "Trace/BPT trap: 5")
    #expect(crash.notes == ["Fatal error: Index out of range"])
    #expect(crash.frames == ["ExtensionRunner  Runtime.render()", "???  0x1000", "dyld  start"])
    #expect(crash.date == ISO8601DateFormatter().date(from: "2026-11-10T21:53:25Z"))
    #expect(crash.headline == "ExtensionRunner quit unexpectedly: EXC_BREAKPOINT (SIGTRAP), Fatal error: Index out of range")
}

@Test func otherDiagnosticReportsAreNotCrashes() {
    #expect(CrashSummary(ips: #"{"bug_type":"211","app_name":"NotchNotch"}"# + "\n{}") == nil)
    #expect(CrashSummary(ips: "not json\n{}") == nil)
    #expect(CrashSummary(ips: "") == nil)
}

@Test func onlyNotchNotchCrashReportsAreFound() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["NotchNotch-2026-11-10-100000.ips", "ExtensionRunner-2026-11-11-090000.ips", "Safari-2026-11-11-090000.ips",
                 "NotchNotchHelper-2026-11-11-090000.ips", "NotchNotch-2026-11-11-090000.diag"] {
        try Data().write(to: folder.appendingPathComponent(name))
    }
    let found = CrashSummary.reports(in: folder, since: .distantPast).map(\.lastPathComponent)
    #expect(found == ["NotchNotch-2026-11-10-100000.ips", "ExtensionRunner-2026-11-11-090000.ips"])
    #expect(CrashSummary.reports(in: folder, since: .now.addingTimeInterval(60)).isEmpty)
}

@Test func journalSkipsRestartLoopsAndForgetsOldProblems() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var journal = ProblemJournal()
    journal.record(Problem(date: start, source: "weather", message: "Runner exited"))
    journal.record(Problem(date: start.addingTimeInterval(5), source: "weather", message: "Runner exited"))
    journal.record(Problem(date: start.addingTimeInterval(6), source: "music", message: "Runner exited"))
    journal.record(Problem(date: start.addingTimeInterval(120), source: "weather", message: "Runner exited"))
    #expect(journal.problems.map(\.source) == ["weather", "music", "weather"])

    journal.prune(now: start.addingTimeInterval(ProblemJournal.maximumAge + 10))
    #expect(journal.problems.map(\.source) == ["weather"])

    for index in 0..<(ProblemJournal.maximumCount + 5) {
        journal.record(Problem(date: start.addingTimeInterval(200 + Double(index)), source: "s\(index)", message: "m"))
    }
    #expect(journal.problems.count == ProblemJournal.maximumCount)
    #expect(journal.problems.first?.source == "s5")
}

@Test func journalRoundTripsThroughItsFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Problems.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var journal = ProblemJournal()
    journal.record(Problem(date: Date(timeIntervalSince1970: 1_800_000_000), source: "NotchNotch", message: "Store update failed"))
    journal.crashesCheckedUntil = Date(timeIntervalSince1970: 1_800_000_100)
    try journal.save(to: url)
    #expect(ProblemJournal.load(from: url) == journal)
    #expect(ProblemJournal.load(from: url.appendingPathExtension("missing")) == ProblemJournal())
}

@Test func reportNamesNobody() throws {
    let crash = try #require(CrashSummary(ips: crashIPS))
    let report = ProblemReport(
        appVersion: "0.8.0 (42)", osVersion: "macOS 26.5.1", architecture: "arm64",
        created: Date(timeIntervalSince1970: 1_800_000_000),
        extensions: [.init(id: "weather", version: "1.0.0", origin: "Store", enabled: true,
                           error: "Couldn’t read /Users/amir/Library/Application Support/x.json"),
                     .init(id: "music", version: "0.8.0", origin: "included", enabled: false)],
        problems: [Problem(date: Date(timeIntervalSince1970: 1_799_999_000), source: "weather", message: "Stopped\nafter repeated failures")],
        recentErrors: ["weather": ["TypeError: amir is not defined"], "music": []],
        crashes: [crash])
    let text = report.text(home: "/Users/amir", userName: "amir")
    #expect(!text.contains("amir"))
    #expect(text.contains("Couldn’t read ~/Library/Application Support/x.json"))
    #expect(text.contains("TypeError: user is not defined"))
    #expect(text.contains("music 0.8.0, included, disabled"))
    #expect(text.contains("weather: Stopped after repeated failures"))
    #expect(text.contains("    0  ExtensionRunner  Runtime.render()"))
    #expect(!text.contains("SECRET-KEY") && !text.contains("MacBookPro18,3"))
    // Extension ids are listed in order, music first.
    #expect(text.range(of: "  music")!.lowerBound < text.range(of: "  weather 1.0.0")!.lowerBound)
}

@Test func redactionLeavesLongerWordsAlone() {
    #expect(ProblemReport.redact("Amir and amirhossein at /Users/amir/x", home: "/Users/amir", userName: "amir") == "user and amirhossein at ~/x")
    #expect(ProblemReport.redact("a b", home: "/", userName: "a") == "a b")
}
