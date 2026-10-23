import AppKit
import SwiftUI

struct PowerTrace: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geometry in
            let low = min(values.min() ?? 0, 0)
            let high = max(values.max() ?? 1, 1)
            Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(
                        x: geometry.size.width * Double(index) / Double(max(values.count - 1, 1)),
                        y: 4 + (geometry.size.height - 8) * (1 - (value - low) / (high - low))
                    )
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(.teal, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("Recent battery power history")
    }
}

struct ChargePanel: View {
    @ObservedObject var monitor: BatteryMonitor
    private func watts(_ value: Double?) -> String {
        value.map { String(format: "%.1f W", $0) } ?? "Unavailable"
    }
    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "bolt.circle.fill").font(.title2).foregroundStyle(.teal)
                Text("ChargeBar").font(.system(size: 14, weight: .semibold))
                Spacer()
                if let snapshot = monitor.snapshot {
                    Circle().fill(snapshot.isCharging ? .green : .secondary).frame(width: 6, height: 6)
                    Text(snapshot.state).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let snapshot = monitor.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    Text(monitor.smoothedPercent == nil ? "BATTERY LEVEL" : "ADJUSTED ESTIMATE")
                        .font(.system(size: 10, weight: .medium)).tracking(1.2).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(monitor.percentText)
                            .font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit()
                            .minimumScaleFactor(0.7).lineLimit(1)
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(watts(snapshot.batteryWatts.map(abs)))
                                .font(.system(size: 23, weight: .medium, design: .rounded))
                                .monospacedDigit().foregroundStyle(.teal)
                            Text(snapshot.batteryWatts == nil ? "measuring power…"
                                 : ((snapshot.batteryWatts ?? 0) < 0 ? "from battery" : "into battery"))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: monitor.smoothedPercent ?? snapshot.officialPercent ?? 0, total: 100)
                        .tint(.teal).accessibilityLabel("Battery charge")
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("BATTERY POWER").tracking(0.8)
                        Spacer()
                        Text("Recent 2 min · W")
                    }
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    PowerTrace(values: monitor.history).frame(height: 44)
                }
                .padding(12)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                VStack(spacing: 11) {
                    detail("Power into Mac", snapshot.isPluggedIn ? watts(snapshot.adapterInputWatts) : "Unplugged")
                    detail("Charger capacity", snapshot.isPluggedIn ? watts(snapshot.adapterRatedWatts) : "—")
                    detail("macOS battery level", snapshot.officialPercent.map { String(format: "%.0f%%", $0) } ?? "Unavailable")
                    if snapshot.estimatedPercent != nil { detail("Raw battery gauge", snapshot.percentText) }
                    detail("Battery time left", snapshot.batteryTimeText)
                        .help("Estimated until the battery runs out at current use. Workload changes affect this estimate; low-battery sleep may happen sooner.")
                    if snapshot.isCharging { detail("Until full", snapshot.timeText) }
                }
                Text(monitor.smoothedPercent == nil
                     ? "macOS exposes a whole percentage here. Power values update when the hardware reports them."
                     : "≈ includes a +1 percentage point display adjustment, capped at 100%. It predicts between gauge updates using battery current.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Battery data unavailable", systemImage: "battery.0percent")
                    .font(.headline).padding(.vertical, 12)
                Text("ChargeBar will keep checking for the built-in battery.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text(monitor.isStale ? "Waiting for battery data…"
                     : monitor.isWaitingForGauge ? "Waiting for battery gauge…"
                     : "Live · checks every 0.5 seconds")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh battery readings").accessibilityLabel("Refresh battery readings")
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(20)
        .frame(width: 350)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let monitor = BatteryMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep a second launch from adding a duplicate menu bar item.
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1 {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "ChargeBar"
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.animates = false
        let hosting = NSHostingController(rootView: ChargePanel(monitor: monitor))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        monitor.onUpdate = { [weak self] in
            self?.updateStatus()
            DispatchQueue.main.async { self?.keepPanelOnScreen() }
        }
        updateStatus()
        if CommandLine.arguments.contains("--verify-background") {
            let count = monitor.refreshCount
            let requested = Double(ProcessInfo.processInfo.environment["CHARGEBAR_VERIFY_SECONDS"] ?? "") ?? 12
            let duration = requested.isFinite ? max(12, min(180, requested)) : 12
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                precondition(!self.popover.isShown, "Background check requires the panel to stay closed")
                precondition(self.monitor.refreshCount - count >= Int(duration * 1.6), "Background polling is too slow")
                print("Background verified: \(self.monitor.refreshCount - count) polls in \(duration) seconds with the panel closed; \(self.monitor.powerChangeCount) power events")
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--show-panel") || CommandLine.arguments.contains("--verify-layout") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.togglePanel() }
        }
    }

    private func updateStatus() {
        guard let button = statusItem.button else { return }
        let snapshot = monitor.snapshot
        let power = snapshot?.batteryWatts.map { String(format: "%+.1f W", $0) } ?? "— W"
        button.attributedTitle = NSAttributedString(
            string: "\(monitor.percentText) · \(power)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)]
        )
        let symbol = snapshot?.isCharging == true ? "bolt.fill"
            : snapshot?.isPluggedIn == true ? "powerplug.fill" : "battery.100percent"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ChargeBar")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        button.image?.isTemplate = true
        button.toolTip = "ChargeBar · \(snapshot?.state ?? "Battery unavailable")\nAdjusted estimate (+1 percentage point): \(monitor.percentText) · \(power) battery power\nBattery time left: \(snapshot?.batteryTimeText ?? "Calculating…")\nRaw gauge: \(snapshot?.percentText ?? "—%")\nClick for details"
        button.setAccessibilityLabel(button.toolTip)
        if CommandLine.arguments.contains("--verify-background") {
            print("POLL \(ProcessInfo.processInfo.systemUptime) \(snapshot?.estimatedPercent ?? -1) \(monitor.smoothedPercent ?? -1) \(snapshot?.officialPercent ?? -1) plugged=\(snapshot?.isPluggedIn == true) charging=\(snapshot?.isCharging == true) current=\(snapshot?.batteryCurrentMA ?? 0) events=\(monitor.powerChangeCount) stale=\(monitor.isStale)")
            fflush(stdout)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { monitor.stop() }

    private func keepPanelOnScreen() {
        guard popover.isShown, let window = popover.contentViewController?.view.window,
              let screen = statusItem.button?.window?.screen ?? NSScreen.screens.first else { return }
        if let content = popover.contentViewController?.view {
            content.layoutSubtreeIfNeeded()
            if popover.contentSize != content.fittingSize { popover.contentSize = content.fittingSize }
        }
        let frame = panelFrameOnScreen(window.frame, visibleScreen: screen.visibleFrame)
        if frame != window.frame { window.setFrame(frame, display: true) }
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button, let content = popover.contentViewController?.view else { return }
        // Resolve SwiftUI's full height before AppKit chooses which side of the anchor fits.
        content.layoutSubtreeIfNeeded()
        popover.contentSize = content.fittingSize
        if CommandLine.arguments.contains("--verify-layout") {
            fputs("Fitting size: \(content.fittingSize); menu window: \(String(describing: button.window?.frame))\n", stderr)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async {
            guard let window = content.window, let screen = button.window?.screen ?? NSScreen.screens.first else {
                if CommandLine.arguments.contains("--verify-layout") {
                    fputs("Panel window or screen unavailable\n", stderr)
                    exit(1)
                }
                return
            }
            window.setFrame(panelFrameOnScreen(window.frame, visibleScreen: screen.visibleFrame), display: true)
            window.makeKey()
            if CommandLine.arguments.contains("--verify-layout") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    precondition(screen.visibleFrame.contains(window.frame), "Panel extends beyond the usable screen")
                    precondition(!button.attributedTitle.string.contains("\n"), "Menu bar title must fit on one line")
                    precondition(content.bounds.height >= content.fittingSize.height - 1, "Panel content is vertically clipped")
                    precondition(self.monitor.history.count >= 2, "Live polling did not continue with the panel open")
                    print("Layout verified: panel \(window.frame), content \(content.bounds.size), menu \(button.attributedTitle.string)")
                    if let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                        content.cacheDisplay(in: content.bounds, to: image)
                        if let png = image.representation(using: .png, properties: [:]) {
                            let destination = ProcessInfo.processInfo.environment["CHARGEBAR_CAPTURE_PATH"] ?? "chargebar-panel.png"
                            try? png.write(to: URL(fileURLWithPath: destination))
                        }
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

@main
enum ChargeBarMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--sample") {
            guard let snapshot = BatteryReader.read() else {
                fputs("Battery data unavailable\n", stderr)
                exit(1)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            do { print(String(decoding: try encoder.encode(snapshot), as: UTF8.self)) }
            catch { fputs("Cannot encode battery sample: \(error)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
