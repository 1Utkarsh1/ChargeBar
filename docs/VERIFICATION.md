# ChargeBar verification

## 1.3.2 — DMG distribution

Checked locally on Apple Silicon with macOS 27 on 23 October 2026.

- The build passed all telemetry, predictor, runtime and placement assertions, including the discharge rebound regression and 200 simulated power transitions.
- The compressed DMG passed `hdiutil verify`, mounted read-only, contained ChargeBar and a correct `/Applications` shortcut, and ejected cleanly.
- The ZIP passed its integrity check. Every app file in the DMG and ZIP matched the local build; both packaged apps passed strict signature verification and reported version 1.3.2, build 8.
- The executable inside the mounted DMG successfully read live battery telemetry with `--sample`. The binary is arm64 and targets macOS 14 or later.

This release changes distribution packaging and screenshots. Battery prediction remains the 1.3.1 implementation, with the same physical sleep/resume and measurement limits described below. The app remains ad hoc signed and is not Apple notarized.

## 1.3.1 — Draining estimate correction

Checked locally on Apple Silicon with macOS 27 on 23 October 2026.

- Reproduced the old smoothing bug in a controlled test: the adjusted estimate fell from 17.50% to 16.91%, then increased to 16.96% after a lower raw reading while current remained -3600 mA.
- The same sequence no longer rebounds. Regression checks require the estimate to keep decreasing, rather than simply freeze, while valid negative current continues.
- Checks cover opposing raw-gauge changes, long polling gaps, brief loss of decimal capacity, expiry of the three-second fallback, positive charging current and genuine reconnection. System wake and complete data outages intentionally start fresh measurement baselines to account for unobserved charging.
- All telemetry/prediction assertions and the 200-transition live-run-loop monitor checks passed. The monitor test also verifies that an upward raw recalibration cannot raise a draining estimate.
- The final installed binary completed a 90-second panel-closed run: **184 logged readings**, all unplugged and not charging, **zero upward displayed steps**, and no failed reads. The adjusted estimate decreased from **13.41% to 12.76%**. Median interval: 0.500 seconds; maximum interval: 0.514 seconds. Raw upward steps observed in this run: 1.
- The open-panel layout and continued polling checks passed. Packaged and installed signatures verify, and the installed executable matches the packaged binary.

These are estimates with the documented +1 display adjustment. The live run covers one Mac and a short discharge interval. Actual system sleep/resume remains untested physically; lifecycle tests use process-local notifications.

## 1.3.0 — Initial public preview

Checked on the owner's Apple Silicon Mac running macOS 27 on 23 October 2026.

### Changes verified

- macOS power-source notifications trigger immediate refreshes, backed by the 0.5-second timer.
- Public connection/charging state overrides stale registry flags. Disconnect always clears charging. Instant current is preferred; current/power pointing in the old direction is withheld during transitions.
- The predictor preserves its value when the direction changes and keeps integrating valid current beyond the former 60-second cutoff. It stays within two percentage points of the raw gauge and labels that limit instead of drifting indefinitely. The requested +1 display adjustment remains capped at 100%.
- Display sleep no longer stops the timer. Duplicate system/display wake notifications do not create extra timers. Temporary read failures hold and label the last result for up to three seconds; longer failures clear it and later reads recover automatically.
- The open panel resizes when charging adds its time-to-full row and stays inside the usable screen area.

### Results

- All telemetry, prediction, bounds, runtime and placement assertions passed.
- The live-run-loop test passed 200 simulated connection changes, display/system sleep notifications, duplicate wake notifications, temporary and prolonged read failures, recovery and timer shutdown.
- Two separate 90-second runs with the panel closed completed successfully: 183 and 184 refreshes after the initial reading. Median interval: 0.500 seconds in each run. Longest observed interval: 0.534 seconds. No failed reads were observed.
- The physical cable check captured connected/charging → disconnected → connected → charging. Connection changes arrived through power notifications. On the observed reconnect, macOS reported charging approximately 5.82 seconds after reporting the connection; the app displayed the connected state during that interval.
- Panel-open checks passed both on battery and while charging, including the single-line menu title, content fit, screen bounds and continued polling. A panel screenshot is [the panel screenshot](../assets/panel.png).
- The packaged ZIP passed integrity checks. The installed executable matches the ZIP, its local signature verifies, and one normal instance is running from Applications.

### Limits before publication

The sleep/wake tests used process-local notifications; a physical lid-close/system-resume cycle was not performed. Cable insertion time was not independently timestamped, so this does not establish a hardware-to-display latency bound. Battery wattage/current can settle later than connection status. Decimal readings remain estimates, with the requested display offset, rather than measurements accurate to 0.01%.

The app is locally ad hoc signed and is not Apple notarized. This record describes local validation before the initial public release; GitHub Actions reports CI results separately.
