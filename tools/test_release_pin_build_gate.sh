#!/usr/bin/env bash
# Regression-test that Release builds reject missing and malformed pins through
# the Xcode target's pre-packaging build phase, not only through a standalone CI call.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_ROOT="${RELEASE_PIN_GATE_TEST_DIR:-$(mktemp -d /tmp/dosetap-pin-build-gate.XXXXXX)}"
mkdir -p "$TEST_ROOT"

expect_release_build_failure() {
  local case_name="$1"
  local pins="$2"
  local expected_message="$3"
  local case_dir="$TEST_ROOT/$case_name"
  local log_path="$case_dir/xcodebuild.log"
  mkdir -p "$case_dir"

  set +e
  xcodebuild build -quiet \
    -project ios/DoseTap.xcodeproj \
    -scheme DoseTap \
    -configuration Release \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$case_dir/DerivedData" \
    DOSETAP_CERT_PINS="$pins" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    >"$log_path" 2>&1
  local build_status=$?
  set -e

  if [[ "$build_status" -eq 0 ]]; then
    echo "ERROR: Release build unexpectedly accepted $case_name pins."
    exit 1
  fi
  if ! grep -Fq "$expected_message" "$log_path"; then
    echo "ERROR: Release build failed for an unrelated reason in case: $case_name"
    echo "Log: $log_path"
    exit 1
  fi
  if find "$case_dir/DerivedData" -path '*/Release-iphonesimulator/DoseTap.app/DoseTap' -type f -print -quit \
      | grep -q .; then
    echo "ERROR: Release executable was packaged despite rejected pins: $case_name"
    exit 1
  fi

  echo "Expected Release build rejection passed: $case_name"
}

expect_release_build_failure \
  "missing" \
  "" \
  "DOSETAP_CERT_PINS is required for Release builds"

expect_release_build_failure \
  "malformed" \
  "sha256/not-base64,sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=" \
  "Invalid SPKI pin format"

echo "Release pin Xcode build-gate tests passed."
