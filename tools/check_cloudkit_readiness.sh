#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ios/DoseTap.xcodeproj"
ENTITLEMENTS_PATH="$ROOT_DIR/ios/DoseTap/DoseTap.entitlements"
EXPECTED_ENTITLEMENTS="DoseTap/DoseTap.entitlements"
EXPECTED_BUNDLE_ID="com.dosetap.ios"
EXPECTED_CONTAINER="iCloud.com.dosetap.ios"

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

extract_setting() {
  local configuration="$1"
  local key="$2"
  /usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -target DoseTap \
    -configuration "$configuration" \
    -showBuildSettings 2>/dev/null | \
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
    '
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

print_header "Project Build Settings"
for configuration in Debug Release; do
  echo "$configuration:"
  bundle_id="$(extract_setting "$configuration" "PRODUCT_BUNDLE_IDENTIFIER")"
  entitlements="$(extract_setting "$configuration" "CODE_SIGN_ENTITLEMENTS")"
  cloud_flag="$(extract_setting "$configuration" "INFOPLIST_KEY_DoseTapCloudSyncEnabled")"

  assert_equals "$configuration bundle ID" "$bundle_id" "$EXPECTED_BUNDLE_ID"
  assert_equals "$configuration entitlements" "$entitlements" "$EXPECTED_ENTITLEMENTS"
  assert_equals "$configuration cloud flag" "$cloud_flag" "YES"
done

print_header "Entitlements File"
container="$(/usr/libexec/PlistBuddy -c "Print :'com.apple.developer.icloud-container-identifiers':0" "$ENTITLEMENTS_PATH" 2>/dev/null || true)"
service="$(/usr/libexec/PlistBuddy -c "Print :'com.apple.developer.icloud-services':0" "$ENTITLEMENTS_PATH" 2>/dev/null || true)"
healthkit="$(/usr/libexec/PlistBuddy -c "Print :'com.apple.developer.healthkit'" "$ENTITLEMENTS_PATH" 2>/dev/null || true)"

assert_equals "CloudKit container" "$container" "$EXPECTED_CONTAINER"
assert_equals "CloudKit service" "$service" "CloudKit"
assert_equals "HealthKit entitlement preserved" "$healthkit" "true"

print_header "Next Step"
if (( failures == 0 )); then
  echo "Local config looks CloudKit-ready. After Apple capability propagation, build to a real device and verify runtime sync."
else
  echo "CloudKit readiness check found $failures issue(s). Resolve them before runtime validation."
fi

exit "$failures"
