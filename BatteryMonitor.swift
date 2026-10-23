import AppKit
import SwiftUI
import IOKit.ps

@MainActor
final class BatteryMonitor: NSObject, ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot?
    @Published private(set) var history: [Double] = []
    @Published private(set) var smoothedPercent: Double?
    @Published private(set) var isStale = false
    @Published private(set) var isWaitingForGauge = false
    private let read: () -> BatterySnapshot?
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private var activity: NSObjectProtocol?
    private var predictor = PercentagePredictor()
    private var lastGoodRead: TimeInterval?
    private var lastHistoryTime: TimeInterval?
    private(set) var refreshCount = 0
    private(set) var powerChangeCount = 0
    var onUpdate: (() -> Void)?

    var percentText: String {
        if let smoothedPercent { return String(format: "≈%.2f%%", smoothedPercent) }
        return snapshot?.percentText ?? "—%"
    }

    init(read: @escaping () -> BatterySnapshot? = BatteryReader.read) {
        self.read = read
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(wake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().powerSourceChanged()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        wake()
    }

    @objc func refresh() {
        let now = ProcessInfo.processInfo.systemUptime
        refreshCount += 1
        if let reading = read() {
            snapshot = reading
            lastGoodRead = now
            isStale = false
            _ = predictor.update(reading, at: now)
            smoothedPercent = predictor.displayValue
            isWaitingForGauge = predictor.isLimited
            // Power events can arrive between timer ticks; keep the chart on its half-second cadence.
            if lastHistoryTime.map({ now - $0 >= 0.45 }) ?? true {
                if let watts = reading.batteryWatts {
                    history.append(watts)
                    if history.count > 240 { history.removeFirst(history.count - 240) }
                }
                lastHistoryTime = now
            }
        } else {
            isStale = true
            predictor.pause(at: now)
            if lastGoodRead.map({ now - $0 > 3 }) ?? true {
                snapshot = nil
                predictor.reset()
                smoothedPercent = nil
                isWaitingForGauge = false
                history.removeAll()
            }
        }
        onUpdate?()
    }

    func powerSourceChanged() {
        powerChangeCount += 1
        if timer != nil { refresh() }
    }

    func stop() {
        sleep()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        powerSource = nil
        onUpdate = nil
    }

    @objc private func sleep() {
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        predictor.reset()
    }

    @objc private func wake() {
        // A display wake can follow system wake; never create two timers or reset a running prediction.
        guard timer == nil else { refresh(); return }
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                        reason: "Update the user's live battery menu bar display")
        history.removeAll()
        lastHistoryTime = nil
        refresh()
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
