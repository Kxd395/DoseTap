#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ios/DoseTap.xcodeproj"
CLOUD_ENTITLEMENTS_PATH="$ROOT_DIR/ios/DoseTap/DoseTap.Cloud.entitlements"
LOCAL_ENTITLEMENTS_PATH="$ROOT_DIR/ios/DoseTap/DoseTap.Local.entitlements"
EXPECTED_CLOUD_ENTITLEMENTS="DoseTap/DoseTap.Cloud.entitlements"
EXPECTED_LOCAL_ENTITLEMENTS="DoseTap/DoseTap.Local.entitlements"
EXPECTED_STAGING_BUNDLE_ID="com.dosetap.staging"
EXPECTED_LOCAL_BUNDLE_ID="com.dosetap.ios"
EXPECTED_CONTAINER="iCloud.com.dosetap.ios"
SHOW_BUILD_SETTINGS_TIMEOUT="${SHOW_BUILD_SETTINGS_TIMEOUT:-20}"

failures=0

print_header() {
  printf '\n== %s ==\n' "$1"
}

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

read_build_settings() {
  local target="$1"
  local configuration="$2"
  local output_file timeout_file watchdog_pid xcodebuild_pid cmd_status

  output_file="$(mktemp "${TMPDIR:-/tmp}/dosetap-cloudkit-settings.XXXXXX")"
  timeout_file="$(mktemp "${TMPDIR:-/tmp}/dosetap-cloudkit-settings-timeout.XXXXXX")"
  rm -f "$timeout_file"

  /usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -target "$target" \
    -configuration "$configuration" \
    -showBuildSettings >"$output_file" 2>/dev/null &
  xcodebuild_pid=$!

  (
    sleep "$SHOW_BUILD_SETTINGS_TIMEOUT"
    if kill -0 "$xcodebuild_pid" 2>/dev/null; then
      : > "$timeout_file"
      kill "$xcodebuild_pid" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!

  if wait "$xcodebuild_pid"; then
    cmd_status=0
  else
    cmd_status=$?
  fi

  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true

  if [[ -f "$timeout_file" ]]; then
    rm -f "$output_file" "$timeout_file"
    return 124
  fi

  if (( cmd_status == 0 )); then
    cat "$output_file"
  fi

  rm -f "$output_file" "$timeout_file"
  return "$cmd_status"
}

extract_setting() {
  local settings="$1"
  local key="$2"
  awk -F' = ' -v key="$key" '
    {
      lhs = $1
      rhs = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", rhs)
      if (lhs == key) {
        print rhs
        exit
      }
    }
  ' <<< "$settings"
}

assert_equals() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label -> $actual"
  else
    fail "$label -> expected '$expected' but found '$actual'"
  fi
}

check_project_settings() {
  local target="$1"
  local configuration="$2"
  local expected_bundle_id="$3"
  local expected_entitlements="$4"
  local expected_cloud_flag="$5"
  local settings cmd_status bundle_id entitlements cloud_flag

  echo "$target $configuration:"
  if settings="$(read_build_settings "$target" "$configuration")"; then
    bundle_id="$(extract_setting "$settings" "PRODUCT_BUNDLE_IDENTIFIER")"
    entitlements="$(extract_setting "$settings" "CODE_SIGN_ENTITLEMENTS")"
    cloud_flag="$(extract_setting "$settings" "INFOPLIST_KEY_DoseTapCloudSyncEnabled")"

    assert_equals "$target $configuration bundle ID" "$bundle_id" "$expected_bundle_id"
    assert_equals "$target $configuration entitlements" "$entitlements" "$expected_entitlements"
    assert_equals "$target $configuration cloud flag" "$cloud_flag" "$expected_cloud_flag"
  else
    cmd_status=$?
    if (( cmd_status == 124 )); then
      fail "$target $configuration build settings timed out after ${SHOW_BUILD_SETTINGS_TIMEOUT}s"
    else
      fail "$target $configuration build settings could not be read"
    fi
  fi
}

print_header "Project Build Settings"
for configuration in Debug Release; do
  check_project_settings DoseTapStaging "$configuration" "$EXPECTED_STAGING_BUNDLE_ID" "$EXPECTED_CLOUD_ENTITLEMENTS" "YES"
  check_project_settings DoseTap "$configuration" "$EXPECTED_LOCAL_BUNDLE_ID" "$EXPECTED_LOCAL_ENTITLEMENTS" "NO"
done

print_header "Entitlements File"
container="$(/usr/libexec/PlistBuddy -c "Print :'com.apple.developer.icloud-container-identifiers':0" "$CLOUD_ENTITLEMENTS_PATH" 2>/dev/null || true)"
service="$(/usr/libexec/PlistBuddy -c "Print :'com.apple.developer.icloud-services':0" "$CLOUD_ENTITLEMENTS_PATH" 2>/dev/null || true)"
documents_service="$(/usr/libexec/PlistBuddy -c "Print :'com.apple.developer.icloud-services':1" "$CLOUD_ENTITLEMENTS_PATH" 2>/dev/null || true)"
ubiquity_container="$(/usr/libexec/PlistBuddy -c "Print :'com.apple.developer.ubiquity-container-identifiers':0" "$CLOUD_ENTITLEMENTS_PATH" 2>/dev/null || true)"
healthkit="$(/usr/libexec/PlistBuddy -c "Print :'com.apple.developer.healthkit'" "$CLOUD_ENTITLEMENTS_PATH" 2>/dev/null || true)"
local_cloud_container="$(/usr/libexec/PlistBuddy -c "Print :'com.apple.developer.icloud-container-identifiers':0" "$LOCAL_ENTITLEMENTS_PATH" 2>/dev/null || true)"

assert_equals "CloudKit container" "$container" "$EXPECTED_CONTAINER"
assert_equals "CloudKit service" "$service" "CloudKit"
assert_equals "CloudDocuments not enabled" "$documents_service" ""
assert_equals "iCloud Documents ubiquity container not enabled" "$ubiquity_container" ""
assert_equals "HealthKit entitlement preserved" "$healthkit" "true"
assert_equals "Local entitlements have no CloudKit container" "$local_cloud_container" ""

print_header "Next Step"
if (( failures == 0 )); then
  echo "Local config looks CloudKit-ready. After Apple capability propagation, build to a real device and verify runtime sync."
else
  echo "CloudKit readiness check found $failures issue(s). Resolve them before runtime validation."
fi

exit "$failures"
