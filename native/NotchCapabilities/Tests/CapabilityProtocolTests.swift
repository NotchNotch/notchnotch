import Foundation
import Testing
import NotchProtocol
@testable import NotchCapabilities

/// Sends requests to a capability the way the broker does and collects its answers.
@MainActor private final class Client {
    var messages: [JSONValue] = []
    lazy var session = SystemCapabilities.session(for: capability, extensionID: "dev.test.capability") { [weak self] in
        self?.messages.append($0)
    }!
    let capability: SystemCapability
    init(_ capability: SystemCapability) { self.capability = capability }

    func request(_ id: String, _ method: String, _ params: JSONValue? = nil) async throws -> [String: JSONValue] {
        var fields: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method)]
        if let params { fields["params"] = params }
        session.receive(.object(fields))
        for _ in 0..<300 {
            if let answer = messages.lazy.compactMap({ value -> [String: JSONValue]? in
                if case let .object(fields) = value, fields["id"] == .string(id) { fields } else { nil }
            }).first { return answer }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("No answer to \(method)")
        return [:]
    }
}

private func errorCode(_ answer: [String: JSONValue]) -> Double? {
    guard case let .object(error)? = answer["error"], case let .number(code)? = error["code"] else { return nil }
    return code
}

@Test @MainActor func nowPlayingReportsStateWithoutPromptingAndRejectsAnythingElse() async throws {
    let client = Client(.nowPlaying)
    defer { client.session.stop() }
    let state = try await client.request("state", "music/getState")
    guard case let .object(result)? = state["result"], case .array? = result["authorized"], case .object? = result["errors"] else {
        Issue.record("Unexpected state: \(state)"); return
    }
    #expect(errorCode(try await client.request("unknown", "arbitraryScript", .object(["script": .string("do something")]))) == -32601)
    #expect(errorCode(try await client.request("player", "music/connect", .object(["player": .string("arbitrary.application")]))) == -32602)
    #expect(errorCode(try await client.request("command", "music/command", .object(["command": .string("runScript")]))) == -32602)
}

@Test @MainActor func calendarReportsStatusWithoutPromptingAndHasNoWriteMethods() async throws {
    let client = Client(.calendar)
    defer { client.session.stop() }
    let status = try await client.request("status", "calendar/getState")
    guard case let .object(result)? = status["result"], case let .string(authorization)? = result["authorization"],
          case let .array(events)? = result["events"], case .array? = result["calendars"] else {
        Issue.record("Unexpected status: \(status)"); return
    }
    #expect(["authorized", "notDetermined", "denied", "restricted", "writeOnly"].contains(authorization))
    if authorization != "authorized" { #expect(events.isEmpty) }
    #expect(errorCode(try await client.request("write", "calendar/deleteEvent", .object(["id": .string("anything")]))) == -32601)
    #expect(errorCode(try await client.request("selection", "calendar/select", .object(["ids": .array([.number(42)])]))) == -32602)
    #expect(errorCode(try await client.request("join", "calendar/join", .object(["id": .string("missing-event")]))) == -32602)
}

@Test @MainActor func invalidRequestsAreAnsweredAndAStoppedSessionStaysQuiet() async throws {
    let client = Client(.calendar)
    client.session.receive(.string("not a request"))
    #expect(client.messages.count == 1)
    client.session.stop()
    client.session.receive(.object(["jsonrpc": .string("2.0"), "id": .string("late"), "method": .string("calendar/getState")]))
    try await Task.sleep(for: .milliseconds(50))
    #expect(client.messages.count == 1)
}

@Test func uninstallingForgetsAnExtensionsCalendarSelection() {
    let id = "dev.test.forget-\(UUID().uuidString.lowercased())"
    CalendarSelections.set(["a", "b"], for: id)
    #expect(CalendarSelections.ids(for: id) == ["a", "b"])
    SystemCapabilities.forget(extensionID: id)
    #expect(CalendarSelections.ids(for: id) == nil)
}
