import Foundation
import IOKit.ps
import Testing
@testable import NotchCapabilities

@Test func batteryReadingsComeFromIOKitsDescription() {
    let discharging: [String: Any] = [kIOPSCurrentCapacityKey: 42, kIOPSMaxCapacityKey: 100, kIOPSIsChargingKey: false,
                                      kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue, kIOPSTimeToEmptyKey: 185]
    let reading = BatteryStatus.reading(discharging, providingAC: false, lowPowerMode: true)
    #expect(reading == .init(present: true, level: 0.42, charging: false, pluggedIn: false, charged: false,
                             minutesToEmpty: 185, minutesToFull: nil, lowPowerMode: true))
    // -1 means macOS is still estimating, so there's no time to show.
    let estimating: [String: Any] = [kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100, kIOPSIsChargingKey: true,
                                     kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSTimeToFullChargeKey: -1]
    let charging = BatteryStatus.reading(estimating, providingAC: true, lowPowerMode: false)
    #expect(charging.charging && charging.pluggedIn && charging.minutesToFull == nil && charging.minutesToEmpty == nil)
    // A Mac mini has no battery but can still say it's on power.
    #expect(BatteryStatus.reading(nil, providingAC: true, lowPowerMode: false)
        == .init(present: false, charging: false, pluggedIn: true, charged: false, lowPowerMode: false))
}

@Test func systemRatesComeFromTwoSamples() {
    #expect(SystemSample.cpuLoad(from: (busy: 100, total: 1000), to: (busy: 350, total: 2000)) == 0.25)
    #expect(SystemSample.cpuLoad(from: (busy: 100, total: 1000), to: (busy: 100, total: 1000)) == nil)
    // Interface counters are 32 bits and wrap.
    #expect(SystemSample.counterDelta(4_294_967_000, 200) == 496)
    let first = SystemSample(cpuTicks: (0, 0), networkBytes: (1_000, 500), time: 10)
    let second = SystemSample(cpuTicks: (0, 0), networkBytes: (5_000, 2_500), time: 12)
    #expect(SystemSample.rate(from: first, to: second) == .init(received: 2_000, sent: 1_000))
    #expect(SystemSample.rate(from: second, to: second) == nil)
    #expect(SystemSample.memoryUsed(anonymous: 100, purgeable: 20, wired: 30, compressed: 10, pageSize: 16_384) == 120 * 16_384)
}

@Test func liveSystemReadingsAreSane() {
    let memory = SystemSample.memory()
    #expect(memory.total > 0 && memory.used > 0 && memory.used <= memory.total)
    let disk = SystemSample.disk()
    #expect(disk.total > 0 && disk.used <= disk.total)
    #expect(["nominal", "fair", "serious", "critical"].contains(SystemSample.thermal()))
}

@Test func theLiveBatteryReadingIsConsistent() {
    let battery = BatteryStatus.current()
    if battery.present {
        #expect((0...1).contains(battery.level ?? -1))
        #expect(!(battery.charging && !battery.pluggedIn))
    } else {
        #expect(battery.level == nil)
    }
}
