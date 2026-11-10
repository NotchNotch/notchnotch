import Foundation
import Testing
import NotchProtocol
@testable import NotchExtensions

private func package(at folder: URL, id: String) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("""
    {"id":"\(id)","name":"\(id)","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[]}
    """.utf8).write(to: folder.appendingPathComponent("notchnotch.json"))
    try Data("void 0;".utf8).write(to: folder.appendingPathComponent("bundle.js"))
}

private func register(_ registry: DevelopmentRegistry, id: String, folder: URL, pid: Int32 = getpid()) throws {
    try FileManager.default.createDirectory(at: registry.directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: ["path": folder.path, "pid": pid])
        .write(to: registry.directory.appendingPathComponent("\(id).json"))
}

@Test func registrationsCountOnlyWhileTheirProcessAndFolderExist() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-dev-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = DevelopmentRegistry(directory: root.appendingPathComponent("Development"))
    #expect(registry.entries().isEmpty)
    try package(at: root.appendingPathComponent("live"), id: "dev.test.live")
    try register(registry, id: "dev.test.live", folder: root.appendingPathComponent("live"))
    try register(registry, id: "dev.test.gone", folder: root.appendingPathComponent("missing"))
    try register(registry, id: "dev.test.dead", folder: root.appendingPathComponent("live"), pid: 999_999)
    #expect(registry.entries().map(\.id) == ["dev.test.live"])

    registry.appendLog(id: "dev.test.live", level: "log", message: "ignored without a log file")
    #expect(!FileManager.default.fileExists(atPath: registry.directory.appendingPathComponent("dev.test.live.log").path))
    try Data().write(to: registry.directory.appendingPathComponent("dev.test.live.log"))
    registry.appendLog(id: "dev.test.live", level: "error", message: "two\nlines")
    let log = try String(contentsOf: registry.directory.appendingPathComponent("dev.test.live.log"), encoding: .utf8)
    #expect(log == "error\ttwo\n\tlines\n")
}

@Test func aDevelopmentFolderStandsInForAnInstalledCopyButNotForAnIncludedOne() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-dev-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let included = root.appendingPathComponent("included"), installed = root.appendingPathComponent("installed")
    try package(at: included.appendingPathComponent("music"), id: "dev.test.music")
    try package(at: installed.appendingPathComponent("dev.test.weather"), id: "dev.test.weather")
    try package(at: root.appendingPathComponent("project/dist"), id: "dev.test.weather")
    try package(at: root.appendingPathComponent("fake/dist"), id: "dev.test.music")
    try package(at: root.appendingPathComponent("renamed/dist"), id: "dev.test.other")
    let store = ExtensionStore(directory: installed)
    let scan = store.scan(included: included, developing: [
        .init(id: "dev.test.weather", folder: root.appendingPathComponent("project/dist")),
        .init(id: "dev.test.music", folder: root.appendingPathComponent("fake/dist")),
        .init(id: "dev.test.claimed", folder: root.appendingPathComponent("renamed/dist")),
    ])
    let weather = try #require(scan.extensions.first { $0.id == "dev.test.weather" })
    #expect(weather.origin == .development)
    #expect(weather.directory.path.hasSuffix("project/dist"))
    #expect(scan.extensions.filter { $0.id == "dev.test.weather" }.count == 1)
    #expect(scan.extensions.first { $0.id == "dev.test.music" }?.origin == .bundled)
    #expect(scan.issues.keys.contains { $0.hasSuffix("fake/dist") })
    #expect(scan.issues.keys.contains { $0.hasSuffix("renamed/dist") })
    #expect(!scan.issues.keys.contains { $0.contains("installed") })
}

@Test func screenshotRequestsAreAnsweredWithTheirFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-dev-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = DevelopmentRegistry(directory: root.appendingPathComponent("Development"))
    try package(at: root.appendingPathComponent("built"), id: "dev.test.shot")
    try FileManager.default.createDirectory(at: registry.directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: ["path": root.appendingPathComponent("built").path, "pid": getpid(), "source": root.path])
        .write(to: registry.directory.appendingPathComponent("dev.test.shot.json"))
    #expect(registry.entries().first?.source == root.standardizedFileURL)

    #expect(registry.screenshotRequests().isEmpty)
    try Data().write(to: registry.directory.appendingPathComponent("dev.test.shot.screenshot"))
    #expect(registry.screenshotRequests() == ["dev.test.shot"])
    registry.finishScreenshots(id: "dev.test.shot", files: [root.appendingPathComponent("metadata/1.png")], error: nil)
    #expect(registry.screenshotRequests().isEmpty)
    let result = try JSONSerialization.jsonObject(with: Data(contentsOf: registry.directory.appendingPathComponent("dev.test.shot.screenshot-result"))) as? [String: Any]
    #expect(result?["files"] as? [String] == [root.appendingPathComponent("metadata/1.png").path])
}
