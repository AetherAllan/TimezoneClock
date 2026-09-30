#!/bin/bash
set -euo pipefail
clock_project_dir="$(cd "$(dirname "$0")" && pwd)"
clock_check_dir="$(mktemp -d "${TMPDIR:-/tmp/}TimezoneClockChecks.XXXXXX")"
trap 'rm -rf "$clock_check_dir"' EXIT
clock_check_bundle="$clock_check_dir/TimezoneClockChecks.app/Contents"
mkdir -p "$clock_check_bundle/MacOS" "$clock_check_bundle/Resources"
cat > "$clock_check_bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.local.TimezoneClock.Checks</string>
<key>CFBundleExecutable</key><string>check</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
sed '/^@main/,$d' "$clock_project_dir/TimezoneClock/TimezoneClockApp.swift" > "$clock_check_dir/ClockStore.swift"
xcrun swiftc -swift-version 6 -strict-concurrency=complete "$clock_project_dir/TimezoneClock/ClockPreferences.swift" "$clock_project_dir/TimezoneClock/ClockModel.swift" \
    "$clock_project_dir/TimezoneClock/AppearanceController.swift" "$clock_check_dir/ClockStore.swift" \
    "$clock_project_dir/Checks.swift" -o "$clock_check_bundle/MacOS/check"
cp -R "$clock_project_dir/TimezoneClock/zh-Hans.lproj" "$clock_project_dir/TimezoneClock/zh-Hant.lproj" "$clock_project_dir/TimezoneClock/en.lproj" "$clock_check_bundle/Resources/"
"$clock_check_bundle/MacOS/check"
