import Darwin

/// Memory and CPU use of a child process, from the kernel's resource accounting.
enum ProcessUsage {
    private static let ticksToSeconds: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    /// Physical memory footprint in bytes, and total user and system CPU time in seconds.
    static func sample(pid: pid_t) -> (memoryBytes: UInt64, cpuTime: Double)? {
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard status == 0 else { return nil }
        // CPU times are in Mach ticks, which differ from nanoseconds on Apple silicon.
        return (info.ri_phys_footprint, Double(info.ri_user_time + info.ri_system_time) * ticksToSeconds)
    }
}
