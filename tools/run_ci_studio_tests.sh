#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fixtures="$(cd "${1:?A fixture directory is required}" && pwd)"
output="${2:?An output directory is required}"
mkdir -p "$output"
for label in collected raw-only medication events whoop health; do
  if [[ ! -f "$fixtures/$label/insights_bundle.json" ]]; then
    echo "Missing required iOS fixture: $label" >&2; exit 1
  fi
done
export DOSETAP_IOS_EXPORT_FIXTURE="$fixtures/collected"
export DOSETAP_IOS_RAW_ONLY_FIXTURE="$fixtures/raw-only"
export DOSETAP_IOS_MEDICATION_EXPORT_FIXTURE="$fixtures/medication"
export DOSETAP_IOS_EVENT_EXPORT_FIXTURE="$fixtures/events"
export DOSETAP_IOS_WHOOP_EXPORT_FIXTURE="$fixtures/whoop"
export DOSETAP_IOS_HEALTH_EXPORT_FIXTURE="$fixtures/health"
swift build --package-path macos/DoseTapStudio 2>&1 | tee "$output/build.log"
swift test --package-path macos/DoseTapStudio 2>&1 | tee "$output/tests.log"
for method in testIOSArchiveRoundTrip testIOSRawOnlyArchiveRoundTrip; do
  if ! grep -Eq "Test [Cc]ase .*${method}.* passed" "$output/tests.log"; then
    echo "Required iOS-to-Studio round-trip did not pass: $method" >&2; exit 1
  fi
done
