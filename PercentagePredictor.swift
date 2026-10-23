import Foundation

struct PercentagePredictor {
    private var lastRaw: Double?
    private var lastTime: TimeInterval?
    private var lastGaugeTime: TimeInterval?
    private var integratedCharge: Double = 0
    private var correction: Double = 0
    private(set) var value: Double?
    private(set) var isLimited = false

    var displayValue: Double? { value.map { min(100, $0 + 1) } }

    mutating func reset() { self = PercentagePredictor() }

    mutating func pause(at time: TimeInterval) { lastTime = time }

    mutating func update(_ snapshot: BatterySnapshot?, at time: TimeInterval) -> Double? {
        guard let snapshot else { reset(); return nil }
        guard let raw = snapshot.estimatedPercent else {
            guard let lastGaugeTime, time - lastGaugeTime <= 3 else { reset(); return nil }
            lastTime = time
            isLimited = value != nil
            return value
        }
        lastGaugeTime = time
        let previous = value
        let current = snapshot.batteryCurrentMA ?? 0
        let isDraining = !snapshot.isPluggedIn || current < 0
        let isCharging = snapshot.isCharging && current > 0
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
            // Releasing an offset must not overwhelm the measured direction of charge flow.
            let wouldReverse = (isDraining && correction < 0) || (isCharging && correction > 0)
            if !wouldReverse { correction *= exp(-max(0, dt) / 5) }
        }
        lastTime = time
        let candidate = max(0, min(100, raw + max(-2, min(2, integratedCharge + correction))))
        if let previous, isDraining { value = min(previous, candidate) }
        else if let previous, isCharging { value = max(previous, candidate) }
        else { value = candidate }
        isLimited = abs((value ?? raw) - raw) >= 2 - 0.000000001
        return value
    }
}
