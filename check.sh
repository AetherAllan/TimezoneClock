#!/bin/bash
set -euo pipefail
clock_project_dir="$(cd "$(dirname "$0")" && pwd)"
clock_check_dir="$(mktemp -d "${TMPDIR:-/tmp/}TimezoneClockChecks.XXXXXX")"
trap 'rm -rf "$clock_check_dir"' EXIT
xcrun swiftc "$clock_project_dir/TimezoneClock/ClockModel.swift" "$clock_project_dir/Checks.swift" -o "$clock_check_dir/check"
"$clock_check_dir/check"
