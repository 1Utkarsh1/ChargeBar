# Contributing to ChargeBar

Use the issue forms for bugs and feature requests. For a larger change, open an issue first so its scope can be discussed.

Run `bash build.sh` on macOS with Apple's Command Line Tools. This runs the assert-based telemetry and predictor checks, the live-run-loop monitor checks, and an optimized Apple Silicon build. Outputs go into `dist/`. Move an existing build before rebuilding; the script refuses to overwrite it.

Keep changes focused. Update the relevant checks when changing telemetry parsing, prediction, connection handling or lifecycle behavior. UI changes should include a screenshot or short recording and an open-panel check.

Describe the problem, resulting behavior and checks performed in your pull request. Include your macOS version and Mac model/chip for hardware-dependent changes. Distinguish simulated notification tests from physical charger and sleep/resume checks. See [BUILDING.md](docs/BUILDING.md) for diagnostic launch arguments.

Use sample values without battery serial numbers or other personal identifiers. Include only diagnostics relevant to the report.
