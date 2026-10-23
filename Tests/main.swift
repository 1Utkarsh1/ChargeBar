import Foundation
import CoreGraphics
import IOKit.ps

func near(_ actual: Double?, _ expected: Double) -> Bool {
    actual.map { abs($0 - expected) < 0.00001 } ?? false
}

let charging = BatterySnapshot(properties: [
    "CurrentCapacity": 13, "MaxCapacity": 100,
    "ExternalConnected": true, "IsCharging": true, "AvgTimeToFull": 164,
    "BatteryData": ["RemainingCapacity": 1139, "FullChargeCapacity": 9487],
    "PowerTelemetryData": ["BatteryPower": 16901, "SystemPowerIn": 29267],
    "AdapterDetails": ["Watts": 35], "Voltage": 3819, "Amperage": 4504
])
assert(near(charging.estimatedPercent, 100 * 1139.0 / 9487))
assert(charging.percentText == "12.01%")
assert(near(charging.officialPercent, 13))
assert(near(charging.batteryWatts, 16.901))
assert(near(charging.batteryCurrentMA, 4504))
assert(near(charging.adapterInputWatts, 29.267))
assert(near(charging.adapterRatedWatts, 35))
assert(charging.state == "Charging" && charging.timeText == "About 2h 44m")

let olderMac = BatterySnapshot(properties: [
    "AppleRawCurrentCapacity": 1119, "AppleRawMaxCapacity": 10000,
    "CurrentCapacity": 11, "MaxCapacity": 100,
    "Voltage": 12000, "Amperage": NSNumber(value: UInt64.max - 999)
])
assert(olderMac.percentText == "11.19%")
assert(near(olderMac.batteryWatts, -12))
assert(near(olderMac.batteryCurrentMA, -1000))
assert(olderMac.state == "On battery")
assert(olderMac.adapterInputWatts == nil)

let nestedRaw = BatterySnapshot(properties: [
    "BatteryData": ["AppleRawCurrentCapacity": 1121, "AppleRawMaxCapacity": 10000],
    "PowerTelemetryData": ["BatteryPower": NSNumber(value: UInt64.max - 11999)]
])
assert(nestedRaw.percentText == "11.21%")
assert(near(nestedRaw.batteryWatts, -12))
let powerOnly = BatterySnapshot(properties: ["Voltage": 12000, "PowerTelemetryData": ["BatteryPower": -12000]])
assert(near(powerOnly.batteryCurrentMA, -1000))
let invalidCurrent = BatterySnapshot(properties: ["Amperage": 1_000_000])
assert(invalidCurrent.batteryCurrentMA == nil)

let wholeOnly = BatterySnapshot(properties: ["CurrentCapacity": 23, "MaxCapacity": 100])
assert(wholeOnly.percentText == "23%" && wholeOnly.estimatedPercent == nil)
assert(wholeOnly.batteryWatts == nil)

let invalid = BatterySnapshot(properties: [
    "AppleRawCurrentCapacity": 8000, "AppleRawMaxCapacity": 4000,
    "BatteryData": ["RemainingCapacity": 10, "FullChargeCapacity": 0],
    "PowerTelemetryData": ["BatteryPower": 999_999_999], "AvgTimeToFull": 65_535
])
assert(invalid.estimatedPercent == nil && invalid.batteryWatts == nil)
assert(invalid.percentText == "—%" && invalid.minutesToFull == nil)

let paused = BatterySnapshot(properties: ["ExternalConnected": true, "IsCharging": false])
assert(paused.state == "Plugged in · charging paused")
let draining = BatterySnapshot(properties: [
    "ExternalConnected": true, "Voltage": 12000, "Amperage": -1000
])
assert(draining.state == "Plugged in · battery draining")
let full = BatterySnapshot(properties: ["ExternalConnected": true, "FullyCharged": true])
assert(full.state == "Fully charged")
let empty = BatterySnapshot(properties: [
    "BatteryData": ["RemainingCapacity": 0, "FullChargeCapacity": 9487]
])
assert(empty.percentText == "0.00%")
let display = CGRect(x: 0, y: 60, width: 1408, height: 797)
let overflowingPanel = CGRect(x: 1200, y: 700, width: 350, height: 480)
let fittedPanel = panelFrameOnScreen(overflowingPanel, visibleScreen: display)
assert(display.contains(fittedPanel))
assert(fittedPanel.origin == CGPoint(x: 1050, y: 369))
let leftDisplay = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
let offscreenPanel = CGRect(x: -2100, y: -400, width: 350, height: 480)
assert(leftDisplay.contains(panelFrameOnScreen(offscreenPanel, visibleScreen: leftDisplay)))
print("Passed: decimal capacity, macOS level, nested/older keys, signed discharge, watts, missing/invalid data, and charging states.")
print("Passed: panel placement stays inside main and external display bounds.")

func gauge(_ percent: Double, current: Double? = 3600, charging: Bool = true) -> BatterySnapshot {
    var properties: [String: Any] = [
        "BatteryData": ["RemainingCapacity": percent * 100, "FullChargeCapacity": 10000],
        "IsCharging": charging, "ExternalConnected": charging
    ]
    if let current { properties["Amperage"] = current }
    return BatterySnapshot(properties: properties)
}

var predictor = PercentagePredictor()
assert(near(predictor.update(gauge(28), at: 0), 28))
assert(near(predictor.update(gauge(28), at: 0.5), 28.005))
assert(near(predictor.update(gauge(28), at: 1), 28.01))
assert(near(predictor.update(gauge(28.02), at: 1.5), 28.01))
let reconciled = predictor.update(gauge(28.02), at: 2)!
assert(reconciled > 28.01 && reconciled < 28.025)

predictor.reset()
_ = predictor.update(gauge(28), at: 0)
for step in 1...180 { _ = predictor.update(gauge(28), at: Double(step) * 0.5) }
assert(near(predictor.value, 28.9), "Valid current must keep prediction moving beyond the old 60-second limit")

var slowCurrent = PercentagePredictor()
_ = slowCurrent.update(gauge(28, current: 100), at: 0)
for step in 1...180 { _ = slowCurrent.update(gauge(28, current: 100), at: Double(step) * 0.5) }
assert(near(slowCurrent.value, 28 + 100.0 / 10000 * 100 * 90 / 3600))

assert(near(predictor.update(gauge(28, current: -3600, charging: false), at: 91), 28.89), "Unplugging must reverse prediction without resetting the displayed percentage")
assert(near(predictor.update(gauge(28, current: -3600, charging: false), at: 91.5), 28.885))
assert(near(predictor.update(gauge(28, current: 3600, charging: false), at: 92), 28.885), "Ignore positive current left over after disconnect")
assert(near(predictor.update(gauge(28, current: 3600, charging: false), at: 92.5), 28.885))
assert(near(predictor.update(gauge(28, current: nil), at: 93), 28.885))
assert(near(predictor.update(gauge(28, current: nil), at: 93.5), 28.885))
assert(near(predictor.update(gauge(29), at: 110), 29), "Long gaps must reanchor rather than extrapolate through sleep")
assert(near(predictor.update(wholeOnly, at: 111), 29) && predictor.isLimited)
assert(predictor.update(nil, at: 112) == nil)
predictor.reset()
_ = predictor.update(gauge(99.99), at: 113)
assert(predictor.update(gauge(99.99), at: 114)! <= 100)
_ = predictor.update(gauge(0.001, current: -3600, charging: false), at: 115)
assert(predictor.update(gauge(0.001, current: -3600, charging: false), at: 116)! >= 0)
let beforeGaugeJump = predictor.value!
assert(predictor.update(gauge(50, current: -3600, charging: false), at: 116.5)! <= beforeGaugeJump)
assert(predictor.isLimited, "An opposing gauge jump must wait instead of reversing discharge")
var limited = PercentagePredictor()
_ = limited.update(gauge(28), at: 0)
for step in 1...1200 { _ = limited.update(gauge(28), at: Double(step) * 0.5) }
assert(near(limited.value, 30) && limited.isLimited, "A frozen gauge must not allow unlimited prediction drift")
_ = limited.update(gauge(30), at: 600.5)
assert(!limited.isLimited)
limited.pause(at: 601)
assert(near(limited.update(gauge(30), at: 601.5), 30.005), "A failed poll must not integrate unobserved time")
print("Passed: continuous charge/discharge handoff, prediction beyond 60 seconds, fresh-data correction, missing-current behavior, drift limits, sleep gaps, and percentage bounds.")

var adjusted = PercentagePredictor()
assert(adjusted.displayValue == nil)
for (raw, expected) in [(56.89, 57.89), (56.90, 57.90), (98.99, 99.99), (99.0, 100.0), (99.99, 100.0), (100.0, 100.0)] {
    adjusted.reset()
    _ = adjusted.update(gauge(raw), at: 0)
    assert(near(adjusted.value, raw), "Display adjustment must leave the underlying estimate intact")
    assert(near(adjusted.displayValue, expected))
}
adjusted.reset()
_ = adjusted.update(gauge(98.99), at: 0)
for step in 1...180 {
    _ = adjusted.update(gauge(98.99), at: Double(step) * 0.5)
    assert(adjusted.displayValue! <= 100)
}
assert(String(format: "%.2f%%", adjusted.displayValue!) == "100.00%")
assert(adjusted.update(wholeOnly, at: 91) != nil && adjusted.displayValue == 100 && adjusted.isLimited)
adjusted.reset()
assert(adjusted.update(wholeOnly, at: 92) == nil && adjusted.displayValue == nil)
print("Passed: +1 percentage point display adjustment, exact example values, unchanged raw estimate, and 100.00% ceiling.")

var dischargeRegression = PercentagePredictor()
_ = dischargeRegression.update(gauge(16.5, current: -3600, charging: false), at: 0)
for step in 1...118 {
    _ = dischargeRegression.update(gauge(16.5, current: -3600, charging: false), at: Double(step) * 0.5)
}
assert(near(dischargeRegression.displayValue, 16.91))
_ = dischargeRegression.update(gauge(16.49, current: -3600, charging: false), at: 59.5)
for step in 120...180 {
    let previous = dischargeRegression.value!
    let next = dischargeRegression.update(gauge(16.49, current: -3600, charging: false), at: Double(step) * 0.5)!
    assert(next < previous, "Discharge must continue downward while reconciling an overshot prediction")
}
for (time, reading) in [(90.5, gauge(17, current: -3600, charging: false)),
                         (100.0, gauge(17.2, current: -3600, charging: false)),
                         (100.5, wholeOnly),
                         (101.0, gauge(17.3, current: nil, charging: false))] {
    let previous = dischargeRegression.value!
    assert(dischargeRegression.update(reading, at: time)! <= previous,
           "Gauge recalibration, long gaps and missing fine data must not increase an unplugged estimate")
}
let beforeGap = dischargeRegression.value!
assert(dischargeRegression.update(gauge(18, current: -3600, charging: false), at: 200)! <= beforeGap)
assert(dischargeRegression.update(nil, at: 200.5) == nil)
assert(dischargeRegression.update(gauge(19, current: -3600, charging: false), at: 201) == 19,
       "A complete data outage starts a new measurement baseline")
let beforeReconnect = dischargeRegression.value!
assert(dischargeRegression.update(gauge(19, current: 3600, charging: true), at: 201.5)! >= beforeReconnect)
assert(dischargeRegression.update(wholeOnly, at: 202) != nil && dischargeRegression.isLimited)
assert(dischargeRegression.update(wholeOnly, at: 205) == nil,
       "Fine estimates must not remain stale indefinitely after losing the raw gauge")
assert(dischargeRegression.update(gauge(20, current: -3600, charging: false), at: 205.5) == 20)

var chargingRegression = PercentagePredictor()
_ = chargingRegression.update(gauge(50), at: 0)
for step in 1...118 { _ = chargingRegression.update(gauge(50), at: Double(step) * 0.5) }
_ = chargingRegression.update(gauge(50.01), at: 59.5)
for step in 120...180 {
    let previous = chargingRegression.value!
    assert(chargingRegression.update(gauge(50.01), at: Double(step) * 0.5)! > previous)
}
print("Passed: reproduced 17.50 → 16.91 rebound, monotonic discharge/charge, gauge recalibration, polling gaps, brief gauge loss, new measurement baselines and genuine reconnect.")

let dischargeProperties: [String: Any] = [
    "BatteryData": ["RemainingCapacity": 4000, "FullChargeCapacity": 8000],
    "Amperage": -1000, "Voltage": 12000, "IsCharging": false
]
let currentRuntime = BatterySnapshot(properties: dischargeProperties)
assert(currentRuntime.minutesToEmpty == 240 && currentRuntime.batteryTimeText == "About 4h 0m")
assert(olderMac.minutesToEmpty == 67 && olderMac.batteryTimeText == "About 1h 7m")
let systemRuntime = BatterySnapshot(properties: dischargeProperties, systemSecondsRemaining: 6000)
assert(systemRuntime.minutesToEmpty == 100 && systemRuntime.batteryTimeText == "About 1h 40m")
for unavailable in [-1.0, -2.0, Double.nan, Double.infinity] {
    assert(BatterySnapshot(properties: dischargeProperties, systemSecondsRemaining: unavailable).minutesToEmpty == 240)
}
var pluggedDischarge = dischargeProperties
pluggedDischarge["ExternalConnected"] = true
assert(BatterySnapshot(properties: pluggedDischarge, systemSecondsRemaining: -2).minutesToEmpty == 240)
let nearlyEmpty = BatterySnapshot(properties: [
    "BatteryData": ["RemainingCapacity": 5, "FullChargeCapacity": 8000], "Amperage": -1000
])
assert(nearlyEmpty.minutesToEmpty == 0 && nearlyEmpty.batteryTimeText == "Less than 1m")
assert(charging.minutesToEmpty == nil && charging.batteryTimeText == "Charging")
let chargingWithStaleRuntime = BatterySnapshot(properties: ["IsCharging": true, "ExternalConnected": true], systemSecondsRemaining: 6000)
assert(chargingWithStaleRuntime.minutesToEmpty == nil)
assert(paused.minutesToEmpty == nil && paused.batteryTimeText == "Not draining")
assert(powerOnly.minutesToEmpty == nil && powerOnly.batteryTimeText == "Calculating…")
assert(BatterySnapshot(properties: ["Amperage": -1]).minutesToEmpty == nil)
let systemOnly = BatterySnapshot(properties: [:], systemSecondsRemaining: 5700)
assert(systemOnly.minutesToEmpty == 95)
print("Passed: battery runtime, macOS seconds-to-minutes conversion, current-based fallback, unavailable readings, weak-adapter drain, charging/paused states, and nearly empty battery.")

let staleCharging: [String: Any] = [
    "ExternalConnected": true, "IsCharging": true, "FullyCharged": true,
    "CurrentCapacity": 40, "MaxCapacity": 100, "Amperage": 3000, "Voltage": 12000,
    "PowerTelemetryData": ["BatteryPower": 36000, "SystemPowerIn": 60000], "AdapterDetails": ["Watts": 60]
]
let disconnected = BatterySnapshot(properties: staleCharging, powerSource: [
    kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue, kIOPSIsChargingKey: true,
    kIOPSCurrentCapacityKey: 41, kIOPSMaxCapacityKey: 100
])
assert(!disconnected.isPluggedIn && !disconnected.isCharging && !disconnected.isFullyCharged)
assert(disconnected.state == "On battery" && disconnected.officialPercent == 41)
assert(disconnected.batteryCurrentMA == nil && disconnected.batteryWatts == nil)
assert(disconnected.adapterInputWatts == nil && disconnected.adapterRatedWatts == nil)
let chargingWithStaleFull = BatterySnapshot(properties: staleCharging, powerSource: [
    kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: true
])
assert(chargingWithStaleFull.isCharging && !chargingWithStaleFull.isFullyCharged && chargingWithStaleFull.state == "Charging")
let connected = BatterySnapshot(properties: dischargeProperties, powerSource: [
    kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: true
])
assert(connected.isPluggedIn && connected.isCharging && connected.state == "Charging")
assert(connected.batteryCurrentMA == nil && connected.batteryWatts == nil && connected.minutesToEmpty == nil)
let rawUnplug = BatterySnapshot(properties: ["ExternalConnected": true, "AppleRawExternalConnected": false, "IsCharging": true])
assert(!rawUnplug.isPluggedIn && !rawUnplug.isCharging)
let instant = BatterySnapshot(properties: [
    "ExternalConnected": false, "Voltage": 12000, "Amperage": 3000,
    "InstantAmperage": NSNumber(value: UInt64.max - 999), "PowerTelemetryData": ["BatteryPower": 36000]
])
assert(near(instant.batteryCurrentMA, -1000) && near(instant.batteryWatts, -12))
let fallbackCurrent = BatterySnapshot(properties: ["InstantAmperage": 1000000, "Amperage": -1000, "Voltage": 12000])
assert(fallbackCurrent.batteryCurrentMA == -1000)
let publicOnly = BatterySnapshot(properties: [:], powerSource: [
    kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: false,
    kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100
])
assert(publicOnly.isPluggedIn && !publicOnly.isCharging && publicOnly.percentText == "80%")
print("Passed: public power-state precedence, stale charging flags/current/watts, immediate unplug, instant-current fallback, and public-only telemetry.")
