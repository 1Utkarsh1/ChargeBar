# Changelog

## 1.3.3 — Match the macOS battery level

- Anchor the main percentage to the macOS battery level, with current-based decimal prediction between updates. The raw capacity ratio remains visible separately.
- Show exactly 100.00% when macOS reports 100%, including while unplugged, and respect the system's 0% endpoint. Leaving full charge resumes smooth discharge without dropping to the unrelated raw ratio.
- Apply the legacy +1 display adjustment only when the macOS level is unavailable and the raw gauge is used instead.
- Added regression checks for the reported macOS 100% / raw 94.59% mismatch, empty/full endpoints, and monitor polling through discharge from full.

## 1.3.2 — DMG download

- Added a compressed DMG with ChargeBar and an Applications shortcut for installation by dragging the app.
- Kept the ZIP download and included both formats in the build script and CI artifacts.
- Replaced the README's menu bar image with a clean capture and refreshed the battery panel image.
- Includes the discharge estimate correction from 1.3.1.

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
