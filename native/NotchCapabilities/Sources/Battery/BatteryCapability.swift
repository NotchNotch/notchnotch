import Foundation
import IOKit.ps
import NotchProtocol

/// What `battery/getState` returns and `battery/state` sends.
struct BatteryStatus: Encodable, Equatable {
    /// False on a Mac without a battery; the other battery fields are then empty.
    var present: Bool
    /// Charge from 0 to 1.
    var level: Double?
    var charging: Bool
    var pluggedIn: Bool
    var charged: Bool
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    var lowPowerMode: Bool

    /// Reads one power source description as IOKit returns it. Pure, so it can be tested.
    static func reading(_ battery: [String: Any]?, providingAC: Bool, lowPowerMode: Bool) -> BatteryStatus {
        guard let battery else {
            return .init(present: false, charging: false, pluggedIn: providingAC, charged: false, lowPowerMode: lowPowerMode)
        }
        let current = battery[kIOPSCurrentCapacityKey] as? Int
        let maximum = battery[kIOPSMaxCapacityKey] as? Int
        let level = current.flatMap { value in maximum.flatMap { $0 > 0 ? min(1, max(0, Double(value) / Double($0))) : nil } }
        // IOKit reports -1 while it is still estimating.
        func minutes(_ key: String) -> Int? { (battery[key] as? Int).flatMap { $0 >= 0 ? $0 : nil } }
        let charging = battery[kIOPSIsChargingKey] as? Bool ?? false
        let onAC = (battery[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return .init(present: true, level: level, charging: charging, pluggedIn: onAC || providingAC,
                     charged: battery[kIOPSIsChargedKey] as? Bool ?? false,
                     minutesToEmpty: onAC ? nil : minutes(kIOPSTimeToEmptyKey),
                     minutesToFull: charging ? minutes(kIOPSTimeToFullChargeKey) : nil,
                     lowPowerMode: lowPowerMode)
    }

    static func current() -> BatteryStatus {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let battery = sources.lazy
            .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        return reading(battery, providingAC: providing == kIOPSACPowerValue,
                       lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

/// `battery`: the internal battery's charge and power state. No consent: it
/// says nothing personal. Updates come when macOS reports a change, not on a timer.
@MainActor
final class BatteryCapability: JSONRPCCapability {
    private var source: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
    private var last: BatteryStatus?

    override init(send: @escaping @MainActor (JSONValue) -> Void) {
        super.init(send: send)
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let capability = Unmanaged<BatteryCapability>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { capability.changed() }
        }, context)?.takeRetainedValue() {
            source = created
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
        }
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
    }

    override func finish() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
    }

    private func changed() {
        guard !stopped else { return }
        let status = BatteryStatus.current()
        guard status != last else { return }
        last = status
        notify("battery/state", Self.json(status))
    }

    override func handle(_ method: String, _ params: JSONValue?) async throws -> JSONValue {
        guard method == "battery/getState" else { throw CapabilityError.unknownMethod }
        let status = BatteryStatus.current()
        last = status
        return Self.json(status)
    }
}
