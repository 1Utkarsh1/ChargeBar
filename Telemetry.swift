import Foundation
import IOKit
import IOKit.ps

struct BatterySnapshot: Codable {
    let sampledAt: Date
    let estimatedPercent: Double?
    let officialPercent: Double?
    let remainingMAh: Double?
    let fullMAh: Double?
    let batteryWatts: Double?
    let batteryCurrentMA: Double?
    let adapterInputWatts: Double?
    let adapterRatedWatts: Double?
    let isPluggedIn: Bool
    let isCharging: Bool
    let isFullyCharged: Bool
    let minutesToFull: Int?
    let minutesToEmpty: Int?

    init(properties: [String: Any], sampledAt: Date = Date(), systemSecondsRemaining: TimeInterval? = nil,
         powerSource: [String: Any] = [:]) {
        self.sampledAt = sampledAt
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        let power = properties["PowerTelemetryData"] as? [String: Any] ?? [:]
        let adapter = properties["AdapterDetails"] as? [String: Any] ?? [:]
        func number(_ values: [String: Any], _ key: String) -> Double? {
            (values[key] as? NSNumber)?.doubleValue
        }
        func signed(_ values: [String: Any], _ key: String) -> Double? {
            // IORegistry can encode negative current/power as an unsigned 64-bit number.
            (values[key] as? NSNumber).map { Double($0.int64Value) }
        }
        func watts(_ value: Double?) -> Double? {
            guard let value, value.isFinite, abs(value) <= 500 else { return nil }
            return value
        }
        let pairs = [
            (number(properties, "AppleRawCurrentCapacity"), number(properties, "AppleRawMaxCapacity")),
            (number(data, "AppleRawCurrentCapacity"), number(data, "AppleRawMaxCapacity")),
            (number(data, "RemainingCapacity"), number(data, "FullChargeCapacity"))
        ]
        let capacity = pairs.first { current, maximum in
            guard let current, let maximum else { return false }
            return current.isFinite && maximum.isFinite && maximum > 100 && current >= 0 && current <= maximum
        }
        remainingMAh = capacity?.0
        fullMAh = capacity?.1
        if let current = remainingMAh, let maximum = fullMAh {
            estimatedPercent = 100 * current / maximum
        } else {
            estimatedPercent = nil
        }
        if let current = number(powerSource, kIOPSCurrentCapacityKey) ?? number(properties, "CurrentCapacity"),
           let maximum = number(powerSource, kIOPSMaxCapacityKey) ?? number(properties, "MaxCapacity"),
           current.isFinite, maximum.isFinite, maximum > 0,
           current >= 0, current <= maximum {
            officialPercent = 100 * current / maximum
        } else {
            officialPercent = nil
        }
        switch powerSource[kIOPSPowerSourceStateKey] as? String {
        case kIOPSACPowerValue: isPluggedIn = true
        case kIOPSBatteryPowerValue: isPluggedIn = false
        default:
            isPluggedIn = (properties["AppleRawExternalConnected"] as? NSNumber)?.boolValue
                ?? (properties["ExternalConnected"] as? NSNumber)?.boolValue ?? false
        }
        isCharging = isPluggedIn && ((powerSource[kIOPSIsChargingKey] as? NSNumber)?.boolValue
            ?? (properties["IsCharging"] as? NSNumber)?.boolValue ?? false)
        isFullyCharged = isPluggedIn && !isCharging && ((powerSource[kIOPSIsChargedKey] as? NSNumber)?.boolValue
            ?? (properties["FullyCharged"] as? NSNumber)?.boolValue ?? false)
        let voltage = number(properties, "Voltage")
        func validCurrent(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite && abs($0) <= 50_000 ? $0 : nil }
        }
        let amperage = validCurrent(signed(properties, "InstantAmperage"))
            ?? validCurrent(signed(properties, "Amperage"))
        let electricalWatts: Double? = if let voltage, let amperage {
            watts(voltage * amperage / 1_000_000)
        } else { nil }
        // shortcut: these diagnostic registry keys are not a stable public API; use V × A if they disappear.
        let reportedWatts = watts(signed(power, "BatteryPower").map { $0 / 1_000 })
            ?? electricalWatts
            ?? watts(signed(data, "BatteryPower").map { $0 / 1_000 })
        let current: Double?
        if let amperage { current = amperage }
        else if let voltage, voltage > 0, let reportedWatts { current = validCurrent(reportedWatts * 1_000_000 / voltage) }
        else { current = nil }
        // Current and watt samples can lag a cable event; wait for a compatible sign instead of showing the old direction.
        let chargingNow = isCharging
        func matchesState(_ value: Double) -> Bool {
            value == 0 || (value > 0 ? chargingNow : !chargingNow)
        }
        batteryCurrentMA = current.flatMap { matchesState($0) ? $0 : nil }
        if let current, !matchesState(current) {
            batteryWatts = nil
        } else if let reportedWatts, matchesState(reportedWatts),
                  current.map({ reportedWatts * $0 >= 0 }) ?? true {
            batteryWatts = reportedWatts
        } else {
            batteryWatts = electricalWatts.flatMap { matchesState($0) ? $0 : nil }
        }
        if isPluggedIn {
            adapterInputWatts = watts(signed(power, "SystemPowerIn").map { $0 / 1_000 }).flatMap { $0 >= 0 ? $0 : nil }
            adapterRatedWatts = watts(number(adapter, "Watts")).flatMap { $0 > 0 ? $0 : nil }
        } else {
            adapterInputWatts = nil
            adapterRatedWatts = nil
        }
        if isCharging, let minutes = number(properties, "AvgTimeToFull"), minutes > 0, minutes < 65_535 {
            minutesToFull = Int(minutes)
        } else {
            minutesToFull = nil
        }
        let isDraining = !isCharging && (!isPluggedIn || (batteryCurrentMA ?? 0) < -50)
        let runtime: Double?
        if isDraining, let seconds = systemSecondsRemaining, seconds.isFinite, seconds > 0 {
            runtime = seconds / 60
        } else if isDraining, let remainingMAh, let current = batteryCurrentMA, current < -50 {
            runtime = remainingMAh / -current * 60
        } else {
            runtime = nil
        }
        if let runtime, runtime.isFinite, runtime >= 0, runtime < Double(Int.max) {
            minutesToEmpty = Int(runtime)
        } else {
            minutesToEmpty = nil
        }
    }

    var percentText: String {
        if let estimatedPercent { return String(format: "%.2f%%", estimatedPercent) }
        if let officialPercent { return String(format: "%.0f%%", officialPercent) }
        return "—%"
    }

    var state: String {
        if !isPluggedIn { return "On battery" }
        if isFullyCharged { return "Fully charged" }
        if isCharging { return "Charging" }
        if let batteryWatts, batteryWatts < -0.1 { return "Plugged in · battery draining" }
        return "Plugged in · charging paused"
    }

    var timeText: String {
        guard let minutesToFull else { return "Calculating…" }
        return Self.durationText(minutesToFull)
    }

    var batteryTimeText: String {
        if let minutesToEmpty { return Self.durationText(minutesToEmpty) }
        if isCharging { return "Charging" }
        if isPluggedIn && (batteryCurrentMA ?? 0) >= -50 { return "Not draining" }
        return "Calculating…"
    }

    private static func durationText(_ totalMinutes: Int) -> String {
        if totalMinutes < 1 { return "Less than 1m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "About \(hours)h \(minutes)m" : "About \(minutes)m"
    }
}

enum BatteryReader {
    static func read() -> BatterySnapshot? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let source = sources.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType && ($0[kIOPSIsPresentKey] as? NSNumber)?.boolValue != false }
        var values: [String: Any] = [:]
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS {
                values = properties?.takeRetainedValue() as? [String: Any] ?? [:]
            }
        }
        guard source != nil || (!values.isEmpty && (values["BatteryInstalled"] as? NSNumber)?.boolValue != false) else { return nil }
        return BatterySnapshot(properties: values, systemSecondsRemaining: IOPSGetTimeRemainingEstimate(), powerSource: source ?? [:])
    }
}
