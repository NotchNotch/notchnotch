import Foundation

/// Limits on what one extension runner may consume, so a leak, a hidden busy
/// loop or a flood of messages stops that extension instead of slowing the Mac.
///
/// Liveness pings catch a runner that stops answering. These limits catch one
/// that keeps answering while it grows, spins with `setTimeout(0)` or sends
/// snapshots faster than anyone can see. The host samples the runner about
/// once a second and reports each message; time is passed in for testing.
public struct RunnerResources: Sendable {
    public struct Limits: Sendable {
        /// Physical memory footprint, in bytes.
        public var memoryBytes: UInt64 = 400 * 1024 * 1024
        /// Consecutive samples over the memory limit before stopping.
        public var memorySamples = 2
        /// Share of one CPU core, averaged over `cpuWindow`.
        public var cpuShare = 0.9
        public var cpuWindow: TimeInterval = 30
        /// Messages may burst up to `messageBurst`, then refill at `messagesPerSecond`.
        public var messagesPerSecond = 30.0
        public var messageBurst = 120.0
        public init() {}
    }

    public let limits: Limits
    private var overMemory = 0
    private var cpuSamples: [(at: Date, cpu: TimeInterval)] = []
    private var tokens: Double
    private var refilledAt: Date

    public init(limits: Limits = Limits(), now: Date = .now) {
        self.limits = limits
        tokens = limits.messageBurst
        refilledAt = now
    }

    /// A sample of the runner: its memory footprint and total CPU time so far.
    /// Returns why the runner must stop, or nil.
    public mutating func sample(memoryBytes: UInt64, cpuTime: TimeInterval, now: Date) -> String? {
        overMemory = memoryBytes > limits.memoryBytes ? overMemory + 1 : 0
        if overMemory >= limits.memorySamples {
            return "used more than \(limits.memoryBytes / 1024 / 1024) MB of memory"
        }
        let window = limits.cpuWindow
        cpuSamples.append((now, cpuTime))
        cpuSamples.removeAll { now.timeIntervalSince($0.at) > window }
        if let first = cpuSamples.first, now.timeIntervalSince(first.at) >= limits.cpuWindow * 0.9 {
            let share = (cpuTime - first.cpu) / now.timeIntervalSince(first.at)
            if share > limits.cpuShare {
                return "kept the processor busy (\(Int(share * 100))% for \(Int(limits.cpuWindow)) seconds)"
            }
        }
        return nil
    }

    /// One message from the runner. Returns why the runner must stop, or nil.
    public mutating func message(now: Date) -> String? {
        tokens = min(limits.messageBurst, tokens + now.timeIntervalSince(refilledAt) * limits.messagesPerSecond)
        refilledAt = now
        guard tokens >= 1 else { return "sent more than \(Int(limits.messagesPerSecond)) messages a second" }
        tokens -= 1
        return nil
    }
}
