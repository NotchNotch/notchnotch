import Foundation

/// Detects runners that never start or stop responding.
///
/// The runner answers pings on its main thread, the same thread that executes
/// JavaScript, so a busy loop in extension code stops the answers. The host
/// calls `tick` periodically and acts on the result.
public struct RunnerLiveness: Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case ping(Int)
        case fail(String)
    }

    public let startupTimeout: TimeInterval
    public let pingInterval: TimeInterval
    public let responseTimeout: TimeInterval
    private let startedAt: Date
    private var started = false
    private var nextID = 0
    private var outstanding: (id: Int, sentAt: Date)?
    private var lastPingAt: Date?

    public init(startedAt: Date, startupTimeout: TimeInterval = 15, pingInterval: TimeInterval = 5,
                responseTimeout: TimeInterval = 10) {
        self.startedAt = startedAt; self.startupTimeout = startupTimeout
        self.pingInterval = pingInterval; self.responseTimeout = responseTimeout
    }

    /// Any valid message from the runner proves that it finished evaluating its bundle.
    public mutating func received() { started = true }

    public mutating func pong(_ id: Int) {
        started = true
        if outstanding?.id == id { outstanding = nil }
    }

    public mutating func tick(now: Date) -> Action {
        if !started, now.timeIntervalSince(startedAt) >= startupTimeout {
            return .fail("did not start within \(Int(startupTimeout)) seconds")
        }
        if let outstanding {
            // While the bundle is still evaluating, only the startup timeout applies.
            guard started else { return .none }
            return now.timeIntervalSince(outstanding.sentAt) >= responseTimeout
                ? .fail("stopped responding for \(Int(responseTimeout)) seconds") : .none
        }
        if let lastPingAt, now.timeIntervalSince(lastPingAt) < pingInterval { return .none }
        nextID += 1
        outstanding = (nextID, now)
        lastPingAt = now
        return .ping(nextID)
    }
}

/// Restarts crashed extensions with exponential backoff, giving up after
/// repeated failures inside a short window.
public struct RestartPolicy: Sendable {
    public let maximumRestarts: Int
    public let window: TimeInterval
    public let baseDelay: TimeInterval
    private var failures: [String: [Date]] = [:]

    public init(maximumRestarts: Int = 3, window: TimeInterval = 120, baseDelay: TimeInterval = 1) {
        self.maximumRestarts = maximumRestarts; self.window = window; self.baseDelay = baseDelay
    }

    /// Records a failure and returns the delay before the next restart, or nil to give up.
    public mutating func failed(_ id: String, now: Date) -> TimeInterval? {
        var recent = failures[id, default: []].filter { now.timeIntervalSince($0) < window }
        recent.append(now)
        failures[id] = recent
        guard recent.count <= maximumRestarts else { return nil }
        return baseDelay * pow(2, Double(recent.count - 1))
    }

    /// A manual restart, disable or successful reinstall starts fresh.
    public mutating func reset(_ id: String) { failures.removeValue(forKey: id) }
}
