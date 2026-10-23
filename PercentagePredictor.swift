import Foundation

struct PercentagePredictor {
    private var lastRaw: Double?
    private var lastTime: TimeInterval?
    private var integratedCharge: Double = 0
    private var correction: Double = 0
    private(set) var value: Double?
    private(set) var isLimited = false

    var displayValue: Double? { value.map { min(100, $0 + 1) } }

    mutating func reset() { self = PercentagePredictor() }

    mutating func pause(at time: TimeInterval) { lastTime = time }

    mutating func update(_ snapshot: BatterySnapshot?, at time: TimeInterval) -> Double? {
        guard let snapshot, let raw = snapshot.estimatedPercent else { reset(); return nil }
        let current = snapshot.batteryCurrentMA ?? 0
        let dt = lastTime.map { time - $0 } ?? 0
        if lastRaw == nil || dt < 0 || dt > 5 {
            lastRaw = raw
            integratedCharge = 0
            correction = 0
            value = raw
        } else if lastRaw != raw {
            // Keep the number continuous, then reconcile to the new gauge reading over a few seconds.
            correction = max(-2, min(2, (value ?? raw) - raw))
            lastRaw = raw
            integratedCharge = 0
        } else {
            if let full = snapshot.fullMAh {
                integratedCharge += current / full * 100 * dt / 3_600
            }
            // shortcut: stop beyond two percentage points of gauge disagreement; revisit with measured calibration data.
            integratedCharge = max(-2, min(2, integratedCharge))
            correction *= exp(-max(0, dt) / 5)
        }
        lastTime = time
        isLimited = abs(integratedCharge + correction) >= 2
        value = max(0, min(100, raw + max(-2, min(2, integratedCharge + correction))))
        return value
    }
}
