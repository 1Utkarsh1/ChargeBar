# Building and verifying ChargeBar

## Requirements

- macOS with Apple's Command Line Tools and `swiftc` available.
- The application targets Apple Silicon and macOS 14 or later.
- Local builds from 1.3.0 through 1.3.3 were verified with Swift 6.4 on macOS 27. GitHub Actions checks the build separately on its configured macOS runner.

## Build

From the repository root, run `bash build.sh`.

The script runs the checks, compiles an optimized arm64 application, applies and verifies an ad hoc signature, then creates `dist/ChargeBar.app`, `dist/ChargeBar.dmg` and `dist/ChargeBar.zip`. It packages both downloads from a temporary directory before moving the app into the checkout, so cloud-managed file metadata cannot affect the packaged signature. The compressed DMG contains the app and an Applications shortcut. The script verifies the disk image's integrity after creation.

The script refuses to overwrite an existing app, DMG or ZIP. Move an existing `dist` directory before rebuilding.

The app uses Apple's AppKit, SwiftUI, Foundation and IOKit frameworks. No third-party dependency or REA installation is required.

## Automated checks

- `Tests/main.swift`: capacity parsing, signed current/power, public-state precedence, system-percentage anchoring, full/empty endpoints, stale samples, prediction continuity and bounds, runtime estimates, fallback display adjustment and screen placement.
- `Tests/MonitorChecks.swift`: 200 simulated power transitions, timer cadence, display/system sleep notifications, repeated wake, read failures, recovery and shutdown.

Assertions are enabled for these check executables. The application is compiled with optimization. CI uses the same build script; physical charger and system-resume behavior require hardware checks.

## One live sample

```bash
dist/ChargeBar.app/Contents/MacOS/ChargeBar --sample
```

This prints selected battery fields as JSON without opening the UI. It omits serial numbers and the full registry dump.

## Panel layout

With no other ChargeBar instance running:

```bash
CHARGEBAR_CAPTURE_PATH=/tmp/chargebar-panel.png \
  dist/ChargeBar.app/Contents/MacOS/ChargeBar --verify-layout
```

This opens the panel, checks screen bounds, content fit, the single-line title and continued polling, saves a capture of its own view, and quits. The view capture may have a transparent background. `--show-panel` opens the panel on launch without running assertions.

## Background polling

With no other ChargeBar instance running:

```bash
CHARGEBAR_VERIFY_SECONDS=90 \
  dist/ChargeBar.app/Contents/MacOS/ChargeBar --verify-background
```

Keep the panel closed during this check. It prints timestamped raw/predicted/macOS readings, connection state, power-event count and read health, verifies polling cadence, then quits. The default duration is 12 seconds; the allowed range is 12–180 seconds. Normal operation does not write these diagnostics.

## Hardware checks

Check charging and battery layouts, disconnect/reconnect the charger, watch changes with the panel open and closed, and perform a real system sleep/resume cycle. Record the distinction between connection detection and charging beginning after adapter negotiation. Verify that values remain between 0 and 100 and stale electrical samples do not retain the previous direction.

The [local verification record](VERIFICATION.md) states what has actually been checked and what remains unverified.
