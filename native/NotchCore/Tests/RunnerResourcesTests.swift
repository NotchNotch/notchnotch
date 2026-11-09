import Foundation
import Testing
@testable import NotchCore

private let start = Date(timeIntervalSinceReferenceDate: 0)
private let megabyte: UInt64 = 1024 * 1024

@Test func memoryStopsARunnerOnlyAfterRepeatedSamplesOverTheLimit() {
    var resources = RunnerResources(now: start)
    #expect(resources.sample(memoryBytes: 500 * megabyte, cpuTime: 0, now: start) == nil, "one spike is allowed")
    #expect(resources.sample(memoryBytes: 100 * megabyte, cpuTime: 0, now: start + 1) == nil)
    #expect(resources.sample(memoryBytes: 500 * megabyte, cpuTime: 0, now: start + 2) == nil)
    #expect(resources.sample(memoryBytes: 500 * megabyte, cpuTime: 0, now: start + 3)?.contains("400 MB") == true)
}

@Test func cpuStopsASpinningRunnerButNotAShortBurst() {
    var busy = RunnerResources(now: start)
    var reason: String?
    for second in 0...30 where reason == nil {
        reason = busy.sample(memoryBytes: 0, cpuTime: Double(second) * 0.98, now: start + Double(second))
    }
    #expect(reason?.contains("processor") == true)

    var bursty = RunnerResources(now: start)
    var cpu = 0.0
    for second in 0...60 {
        cpu += second % 10 < 3 ? 1 : 0.05 // three busy seconds in every ten
        #expect(bursty.sample(memoryBytes: 0, cpuTime: cpu, now: start + Double(second)) == nil)
    }
}

@Test func messagesMayBurstButNotFloodForLong() {
    var resources = RunnerResources(now: start)
    for _ in 0..<120 { #expect(resources.message(now: start) == nil) }
    #expect(resources.message(now: start)?.contains("messages") == true, "the burst is spent")

    var steady = RunnerResources(now: start)
    for tick in 0..<600 { #expect(steady.message(now: start + Double(tick) / 25) == nil, "25 a second is fine") }

    var flood = RunnerResources(now: start)
    var stoppedAt: Int?
    for tick in 0..<2000 where stoppedAt == nil {
        if flood.message(now: start + Double(tick) / 100) != nil { stoppedAt = tick }
    }
    #expect(stoppedAt != nil, "100 a second is stopped once the burst runs out")
}
