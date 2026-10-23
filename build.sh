#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/chargebar-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
output_dir="$source_dir/dist"
app_dir="$output_dir/ChargeBar.app"
if [ -e "$app_dir" ] || [ -e "$output_dir/ChargeBar.zip" ] || [ -e "$output_dir/ChargeBar.dmg" ]; then
    echo "Refusing to overwrite $output_dir. Move the existing build before rebuilding." >&2
    exit 1
fi
swiftc "$source_dir/Telemetry.swift" "$source_dir/PercentagePredictor.swift" "$source_dir/Layout.swift" "$source_dir/Tests/main.swift" -framework IOKit -o "$build_dir/checks"
"$build_dir/checks"
swiftc -parse-as-library "$source_dir/Telemetry.swift" "$source_dir/PercentagePredictor.swift" "$source_dir/BatteryMonitor.swift" \
    "$source_dir/Tests/MonitorChecks.swift" -framework AppKit -framework SwiftUI -framework IOKit -o "$build_dir/monitor-checks"
"$build_dir/monitor-checks"
mkdir -p "$build_dir/ChargeBar.app/Contents/MacOS"
swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
    "$source_dir/Telemetry.swift" "$source_dir/PercentagePredictor.swift" "$source_dir/BatteryMonitor.swift" "$source_dir/Layout.swift" "$source_dir/App.swift" \
    -framework AppKit -framework SwiftUI -framework IOKit \
    -o "$build_dir/ChargeBar.app/Contents/MacOS/ChargeBar"
cp "$source_dir/Info.plist" "$build_dir/ChargeBar.app/Contents/Info.plist"
codesign --force --sign - "$build_dir/ChargeBar.app"
codesign --verify --strict "$build_dir/ChargeBar.app"
mkdir -p "$output_dir"
ditto -c -k --norsrc --noextattr --keepParent "$build_dir/ChargeBar.app" "$output_dir/ChargeBar.zip"
mkdir "$build_dir/dmg"
ln -s /Applications "$build_dir/dmg/Applications"
mv "$build_dir/ChargeBar.app" "$build_dir/dmg/ChargeBar.app"
hdiutil create -volname ChargeBar -srcfolder "$build_dir/dmg" -fs HFS+ -format UDZO "$output_dir/ChargeBar.dmg"
hdiutil verify "$output_dir/ChargeBar.dmg"
mv "$build_dir/dmg/ChargeBar.app" "$app_dir"
echo "Built $app_dir"
