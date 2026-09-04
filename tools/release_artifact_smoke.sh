#!/usr/bin/env bash
# Build one Release simulator artifact, inspect that exact product, then fresh-install
# and launch it until the SwiftUI root writes its explicit first-UI marker.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for command_name in xcodebuild xcrun plutil shasum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: Required command is unavailable: $command_name"
    exit 1
  fi
done

CONFIGURATION=Release bash tools/validate_release_pins.sh >/dev/null

select_simulator() {
  local booted
  local available
  booted="$(
    xcrun simctl list devices available \
      | sed -nE '/iPhone/ s/^[[:space:]]*.* \(([0-9A-Fa-f-]{36})\) \(Booted\).*$/\1/p' \
      | sed -n '1p'
  )"
  if [[ -n "$booted" ]]; then
    printf '%s' "$booted"
    return
  fi

  available="$(
    xcrun simctl list devices available \
      | sed -nE '/iPhone/ s/^[[:space:]]*.* \(([0-9A-Fa-f-]{36})\) \([^)]*\).*$/\1/p' \
      | sed -n '1p'
  )"
  printf '%s' "$available"
}

SIMULATOR_UDID="${SIMULATOR_UDID:-$(select_simulator)}"
if [[ -z "$SIMULATOR_UDID" ]]; then
  echo "ERROR: No available iPhone simulator was found."
  exit 1
fi

xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b >/dev/null

if [[ -n "${RELEASE_ARTIFACT_DIR:-}" ]]; then
  ARTIFACT_BASE="$RELEASE_ARTIFACT_DIR"
  mkdir -p "$ARTIFACT_BASE"
else
  ARTIFACT_BASE="$(mktemp -d /tmp/dosetap-release-artifact.XXXXXX)"
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_DIR="$ARTIFACT_BASE/$RUN_ID"
DERIVED_DATA="$RUN_DIR/DerivedData"
EVIDENCE_DIR="$RUN_DIR/evidence"
BUILD_LOG="$EVIDENCE_DIR/xcodebuild-release.log"
mkdir -p "$EVIDENCE_DIR"

echo "Building one Release simulator artifact..."
set +e
xcodebuild build -quiet \
  -project ios/DoseTap.xcodeproj \
  -scheme DoseTap \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  DOSETAP_CERT_PINS="$DOSETAP_CERT_PINS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  >"$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e

if [[ "$BUILD_STATUS" -ne 0 ]]; then
  echo "ERROR: Release artifact build failed. Log: $BUILD_LOG"
  exit "$BUILD_STATUS"
fi

APP_PATH="$DERIVED_DATA/Build/Products/Release-iphonesimulator/DoseTap.app"
INFO_PLIST="$APP_PATH/Info.plist"
EXECUTABLE="$APP_PATH/DoseTap"
if [[ ! -d "$APP_PATH" || ! -f "$INFO_PLIST" || ! -f "$EXECUTABLE" ]]; then
  echo "ERROR: Final Release app product is incomplete: $APP_PATH"
  exit 1
fi

BUILT_PINS="$(plutil -extract DOSETAP_CERT_PINS raw -o - "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "$BUILT_PINS" ]]; then
  echo "ERROR: Final Release Info.plist does not contain DOSETAP_CERT_PINS."
  exit 1
fi
CONFIGURATION=Release DOSETAP_CERT_PINS="$BUILT_PINS" \
  bash tools/validate_release_pins.sh >/dev/null

normalize_pins() {
  tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | sed '/^$/d' \
    | sort -u \
    | paste -sd ',' -
}

EXPECTED_NORMALIZED="$(printf '%s' "$DOSETAP_CERT_PINS" | normalize_pins)"
BUILT_NORMALIZED="$(printf '%s' "$BUILT_PINS" | normalize_pins)"
if [[ "$EXPECTED_NORMALIZED" != "$BUILT_NORMALIZED" ]]; then
  echo "ERROR: Final Release Info.plist pins do not match the reviewed build input."
  exit 1
fi

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")"
if [[ -z "$BUNDLE_ID" ]]; then
  echo "ERROR: Final Release artifact has no bundle identifier."
  exit 1
fi

cp "$INFO_PLIST" "$EVIDENCE_DIR/final-Info.plist"
{
  printf 'artifact=%s\n' "$APP_PATH"
  printf 'bundle_id=%s\n' "$BUNDLE_ID"
  printf 'configuration=Release\n'
  printf 'executable_sha256=%s\n' "$(shasum -a 256 "$EXECUTABLE" | awk '{print $1}')"
  printf 'info_plist_sha256=%s\n' "$(shasum -a 256 "$INFO_PLIST" | awk '{print $1}')"
  printf 'pin_count=%s\n' "$(printf '%s' "$BUILT_NORMALIZED" | tr ',' '\n' | wc -l | tr -d ' ')"
} >"$EVIDENCE_DIR/artifact-manifest.txt"

echo "Fresh-installing the exact inspected Release artifact..."
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"

DATA_CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data)"
MARKER_PATH="$DATA_CONTAINER/Documents/release-artifact-first-ui-v1.txt"
if [[ -e "$MARKER_PATH" ]]; then
  echo "ERROR: First-UI marker existed before launch; fresh-install proof is invalid."
  exit 1
fi

LAUNCH_OUTPUT="$(
  xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" --release-artifact-smoke 2>&1
)"
APP_PID="$(printf '%s' "$LAUNCH_OUTPUT" | sed -nE 's/^.*: ([0-9]+)$/\1/p' | sed -n '1p')"
if [[ -z "$APP_PID" ]]; then
  echo "ERROR: Simulator did not return a process ID for the Release artifact."
  exit 1
fi

MARKER_FOUND=false
for _ in $(seq 1 20); do
  if [[ -f "$MARKER_PATH" ]] && grep -qx 'first-ui-v1' "$MARKER_PATH"; then
    MARKER_FOUND=true
    break
  fi
  sleep 1
done

if [[ "$MARKER_FOUND" != true ]]; then
  echo "ERROR: Exact Release artifact did not reach the first SwiftUI root within 20 seconds."
  exit 1
fi
if ! ps -p "$APP_PID" >/dev/null 2>&1; then
  echo "ERROR: Exact Release artifact exited after writing the first-UI marker."
  exit 1
fi

xcrun simctl io "$SIMULATOR_UDID" screenshot "$EVIDENCE_DIR/first-ui.png" >/dev/null
printf 'first_ui_marker=first-ui-v1\nprocess_id=%s\n' "$APP_PID" \
  >"$EVIDENCE_DIR/runtime-smoke.txt"

echo "Release artifact gate passed."
echo "Artifact: $APP_PATH"
echo "Evidence: $EVIDENCE_DIR"
