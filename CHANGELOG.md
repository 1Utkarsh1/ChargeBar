# Changelog

## 1.3.1 — Discharge estimate correction

- Fixed an upward rebound in the estimated percentage while the battery was draining. The smoothing correction now follows the measured direction of charge flow.
- Preserve the estimate through gauge recalibration, polling gaps, brief missing decimal samples instead of resetting it upward. Actual system wake and complete data outages retain fresh-baseline behavior.
- Keep valid discharge prediction moving downward while reconciling earlier prediction error. Large gauge disagreements hold with a waiting label.
- Added regressions for the reported 17.50% → 16.91% pattern, charging symmetry, recovery and genuine reconnection.

## 1.3.0 — Initial public preview

- A single horizontal menu bar reading for estimated battery percentage and signed watts.
- A detail panel with raw and macOS percentages, adapter input/capacity, runtime and recent power history.
- Half-second polling with immediate refreshes on macOS power-source notifications.
- Continuous prediction across charging/discharging changes, with bounded drift and a visible waiting state for stale data.
- Display-sleep polling, system-wake recovery, duplicate-timer prevention and temporary read-failure recovery.
- A +1 percentage point display adjustment, capped at 100.00% and identified as approximate.

The binary targets Apple Silicon and macOS 14 or later. Local physical testing covered macOS 27. It is ad hoc signed and is not Apple notarized. See the [verification record](docs/VERIFICATION.md) for checks and remaining limits.
