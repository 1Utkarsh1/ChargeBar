import AppKit
import IOKit.ps

@main
enum MonitorChecks {
    @MainActor static func main() {
        func reading(plugged: Bool) -> BatterySnapshot {
            BatterySnapshot(properties: [
                "BatteryData": ["RemainingCapacity": 4000, "FullChargeCapacity": 10000],
                "ExternalConnected": !plugged, "IsCharging": !plugged,
                "Amperage": plugged ? 3600 : -3600, "Voltage": 12000
            ], powerSource: [
                kIOPSPowerSourceStateKey: plugged ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
                kIOPSIsChargingKey: plugged
            ])
        }
        var next: BatterySnapshot? = reading(plugged: true)
        let monitor = BatteryMonitor(read: { next })
        defer { monitor.stop() }
        let center = NSWorkspace.shared.notificationCenter
        func run(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

        let first = monitor.refreshCount
        for index in 0..<200 {
            let plugged = index % 2 == 0
            next = reading(plugged: plugged)
            monitor.powerSourceChanged()
            assert(monitor.snapshot?.isPluggedIn == plugged && monitor.snapshot?.isCharging == plugged)
            assert(abs(monitor.smoothedPercent! - 41) < 0.05, "Connection changes must not jump the percentage")
        }
        assert(monitor.refreshCount == first + 200 && monitor.powerChangeCount == 200)
        assert(monitor.history.count == 1, "Event bursts must not squeeze the chart's time range")

        var before = monitor.refreshCount
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        run(1.1)
        assert((2...3).contains(monitor.refreshCount - before), "Display sleep must not stop polling")
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        before = monitor.refreshCount
        monitor.powerSourceChanged()
        run(0.6)
        assert(monitor.refreshCount == before, "System sleep must suspend the timer")
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        let afterWake = monitor.smoothedPercent!
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        assert(abs(monitor.smoothedPercent! - afterWake) < 0.001)
        before = monitor.refreshCount
        run(1.1)
        assert((2...3).contains(monitor.refreshCount - before), "Repeated wake notifications must leave exactly one timer")

        let lastValue = monitor.smoothedPercent
        next = nil
        monitor.refresh()
        assert(monitor.snapshot != nil && monitor.smoothedPercent == lastValue && monitor.isStale)
        run(3.2)
        monitor.refresh()
        assert(monitor.snapshot == nil && monitor.smoothedPercent == nil && monitor.isStale)
        next = reading(plugged: false)
        monitor.powerSourceChanged()
        assert(monitor.snapshot?.state == "On battery" && !monitor.isStale)
        assert(monitor.smoothedPercent == 41)
        before = monitor.refreshCount
        monitor.stop()
        run(0.6)
        assert(monitor.refreshCount == before, "Shutdown must invalidate polling and observers")
        print("Passed: 200 immediate power transitions, display/system sleep, duplicate wake, one live timer, transient/prolonged read failure, recovery, and shutdown.")
    }
}
