import Foundation
import Testing
import NotchCore

@Test func livenessFailsARunnerThatNeverStarts() {
    let start = Date(timeIntervalSince1970: 0)
    var liveness = RunnerLiveness(startedAt: start, startupTimeout: 15)
    #expect(liveness.tick(now: start) == .ping(1))
    #expect(liveness.tick(now: start.addingTimeInterval(14)) == .none)
    guard case .fail = liveness.tick(now: start.addingTimeInterval(15)) else { Issue.record("Expected failure"); return }
}

@Test func livenessPingsAndFailsWhenPongsStop() {
    let start = Date(timeIntervalSince1970: 0)
    var liveness = RunnerLiveness(startedAt: start, pingInterval: 5, responseTimeout: 10)
    liveness.received()
    #expect(liveness.tick(now: start) == .ping(1))
    #expect(liveness.tick(now: start.addingTimeInterval(3)) == .none)
    liveness.pong(1)
    #expect(liveness.tick(now: start.addingTimeInterval(4)) == .none)
    #expect(liveness.tick(now: start.addingTimeInterval(5)) == .ping(2))
    liveness.pong(99) // A stale or unknown answer does not count.
    #expect(liveness.tick(now: start.addingTimeInterval(14)) == .none)
    guard case .fail = liveness.tick(now: start.addingTimeInterval(15)) else { Issue.record("Expected failure"); return }
}

@Test func restartPolicyBacksOffAndGivesUp() {
    let now = Date(timeIntervalSince1970: 0)
    var policy = RestartPolicy(maximumRestarts: 3, window: 120, baseDelay: 1)
    #expect(policy.failed("a", now: now) == 1)
    #expect(policy.failed("a", now: now.addingTimeInterval(1)) == 2)
    #expect(policy.failed("a", now: now.addingTimeInterval(2)) == 4)
    #expect(policy.failed("a", now: now.addingTimeInterval(3)) == nil)
    #expect(policy.failed("b", now: now.addingTimeInterval(3)) == 1)
    // Old failures fall out of the window.
    #expect(policy.failed("a", now: now.addingTimeInterval(200)) == 1)
    policy.reset("b")
    #expect(policy.failed("b", now: now.addingTimeInterval(4)) == 1)
}

@Test func aPongDuringStartupProvesTheRunnerStarted() {
    let start = Date(timeIntervalSince1970: 0)
    var liveness = RunnerLiveness(startedAt: start, startupTimeout: 15, pingInterval: 5, responseTimeout: 10)
    #expect(liveness.tick(now: start) == .ping(1))
    liveness.pong(1)
    #expect(liveness.tick(now: start.addingTimeInterval(20)) == .ping(2))
}
