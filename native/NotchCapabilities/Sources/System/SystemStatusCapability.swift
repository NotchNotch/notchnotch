import Darwin
import Foundation
import NotchProtocol

/// What `system/getState` returns and `system/state` sends every two seconds.
struct SystemStatus: Encodable, Equatable {
    struct Usage: Encodable, Equatable { var used: Double; var total: Double }
    struct Throughput: Encodable, Equatable { var received: Double; var sent: Double }
    /// Busy share of all cores, 0 to 1; nil until two samples exist.
    var cpu: Double?
    /// Bytes, as Activity Monitor's "Memory Used".
    var memory: Usage
    /// Bytes on the startup disk.
    var disk: Usage
    /// Bytes per second over every interface but loopback; nil until two samples exist.
    var network: Throughput?
    /// "nominal", "fair", "serious" or "critical".
    var thermal: String
    var uptime: Double
}

/// Counters read from the kernel, and the arithmetic that turns two readings
/// into rates. The arithmetic is pure so it can be tested.
struct SystemSample {
    var cpuTicks: (busy: UInt64, total: UInt64)
    var networkBytes: (received: UInt64, sent: UInt64)
    var time: TimeInterval

    static func cpuLoad(from old: (busy: UInt64, total: UInt64), to new: (busy: UInt64, total: UInt64)) -> Double? {
        guard new.total > old.total, new.busy >= old.busy else { return nil }
        return min(1, max(0, Double(new.busy - old.busy) / Double(new.total - old.total)))
    }

    /// Interface byte counters are 32 bits and wrap at 4 GiB.
    static func counterDelta(_ old: UInt64, _ new: UInt64) -> UInt64 {
        new >= old ? new - old : new + (1 << 32) - old
    }

    static func rate(from old: SystemSample, to new: SystemSample) -> SystemStatus.Throughput? {
        let seconds = new.time - old.time
        guard seconds > 0.2 else { return nil }
        return .init(received: Double(counterDelta(old.networkBytes.received, new.networkBytes.received)) / seconds,
                     sent: Double(counterDelta(old.networkBytes.sent, new.networkBytes.sent)) / seconds)
    }

    /// Activity Monitor's "Memory Used": app memory, wired and compressed.
    static func memoryUsed(anonymous: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> Double {
        Double((anonymous > purgeable ? anonymous - purgeable : 0) + wired + compressed) * Double(pageSize)
    }

    static func read() -> SystemSample {
        .init(cpuTicks: cpuTicks(), networkBytes: networkBytes(), time: ProcessInfo.processInfo.systemUptime)
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64) {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let user = UInt64(load.cpu_ticks.0), system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    private static func networkBytes() -> (received: UInt64, sent: UInt64) {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return (0, 0) }
        defer { freeifaddrs(first) }
        var received: UInt64 = 0, sent: UInt64 = 0
        for pointer in sequence(first: start, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0, let data = entry.ifa_data else { continue }
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(counters.ifi_ibytes)
            sent += UInt64(counters.ifi_obytes)
        }
        return (received, sent)
    }

    static func memory() -> SystemStatus.Usage {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return .init(used: 0, total: total) }
        let used = memoryUsed(anonymous: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
                              wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count),
                              pageSize: UInt64(getpagesize()))
        return .init(used: min(used, total), total: total)
    }

    static func disk() -> SystemStatus.Usage {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Double(values?.volumeTotalCapacity ?? 0)
        let available = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        return .init(used: max(0, total - available), total: total)
    }

    static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "nominal"
        }
    }
}

/// `system`: CPU, memory, disk, network and thermal state. No consent: it
/// says nothing personal. Samples every two seconds, only while a stream is open.
@MainActor
final class SystemStatusCapability: JSONRPCCapability {
    static let interval: Duration = .seconds(2)
    private var previous = SystemSample.read()
    private var latest: SystemStatus
    private var timer: Task<Void, Never>?

    override init(send: @escaping @MainActor (JSONValue) -> Void) {
        latest = Self.status(cpu: nil, network: nil)
        super.init(send: send)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: Self.interval) } catch { return }
                guard let self, !self.stopped else { return }
                self.sample()
                self.notify("system/state", Self.json(self.latest))
            }
        }
    }

    override func finish() { timer?.cancel(); timer = nil }

    private func sample() {
        let now = SystemSample.read()
        latest = Self.status(cpu: SystemSample.cpuLoad(from: previous.cpuTicks, to: now.cpuTicks),
                             network: SystemSample.rate(from: previous, to: now))
        previous = now
    }

    private static func status(cpu: Double?, network: SystemStatus.Throughput?) -> SystemStatus {
        .init(cpu: cpu, memory: SystemSample.memory(), disk: SystemSample.disk(), network: network,
              thermal: SystemSample.thermal(), uptime: ProcessInfo.processInfo.systemUptime)
    }

    override func handle(_ method: String, _ params: JSONValue?) async throws -> JSONValue {
        guard method == "system/getState" else { throw CapabilityError.unknownMethod }
        return Self.json(latest)
    }
}
