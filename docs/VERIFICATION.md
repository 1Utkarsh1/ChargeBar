# ChargeBar 1.3.0 verification

Checked on the owner's Apple Silicon Mac running macOS 27 on 23 October 2026.

## Changes verified

- macOS power-source notifications trigger immediate refreshes, backed by the 0.5-second timer.
- Public connection/charging state overrides stale registry flags. Disconnect always clears charging. Instant current is preferred; current/power pointing in the old direction is withheld during transitions.
- The predictor preserves its value when the direction changes and keeps integrating valid current beyond the former 60-second cutoff. It stays within two percentage points of the raw gauge and labels that limit instead of drifting indefinitely. The requested +1 display adjustment remains capped at 100%.
- Display sleep no longer stops the timer. Duplicate system/display wake notifications do not create extra timers. Temporary read failures hold and label the last result for up to three seconds; longer failures clear it and later reads recover automatically.
- The open panel resizes when charging adds its time-to-full row and stays inside the usable screen area.

## Results

- All telemetry, prediction, bounds, runtime and placement assertions passed.
- The live-run-loop test passed 200 simulated connection changes, display/system sleep notifications, duplicate wake notifications, temporary and prolonged read failures, recovery and timer shutdown.
- Two separate 90-second runs with the panel closed completed successfully: 183 and 184 refreshes after the initial reading. Median interval: 0.500 seconds in each run. Longest observed interval: 0.534 seconds. No failed reads were observed.
- The physical cable check captured connected/charging → disconnected → connected → charging. Connection changes arrived through power notifications. On the observed reconnect, macOS reported charging approximately 5.82 seconds after reporting the connection; the app displayed the connected state during that interval.
- Panel-open checks passed both on battery and while charging, including the single-line menu title, content fit, screen bounds and continued polling. A panel screenshot is [the panel screenshot](../assets/panel.png).
- The packaged ZIP passed integrity checks. The installed executable matches the ZIP, its local signature verifies, and one normal instance is running from Applications.

## Limits before publication

The sleep/wake tests used process-local notifications; a physical lid-close/system-resume cycle was not performed. Cable insertion time was not independently timestamped, so this does not establish a hardware-to-display latency bound. Battery wattage/current can settle later than connection status. Decimal readings remain estimates, with the requested display offset, rather than measurements accurate to 0.01%.

The app is locally ad hoc signed and is not Apple notarized. This record describes local validation before the initial public release; GitHub Actions reports CI results separately.
