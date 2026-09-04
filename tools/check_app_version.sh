#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ios/DoseTap.xcodeproj"
SHOW_BUILD_SETTINGS_TIMEOUT="${SHOW_BUILD_SETTINGS_TIMEOUT:-240}"
TARGETS=(DoseTap DoseTapStaging)
CONFIGURATIONS=(Debug Release)

failures=0
expected_version=""
expected_build=""

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
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

read_build_settings() {
  local target="$1"
  local configuration="$2"
  local output_file xcodebuild_pid cmd_status elapsed

  output_file="$(mktemp "${TMPDIR:-/tmp}/dosetap-build-settings.XXXXXX")"

  /usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -target "$target" \
    -configuration "$configuration" \
    -showBuildSettings >"$output_file" 2>/dev/null &
  xcodebuild_pid=$!

  elapsed=0
  while jobs -pr | grep -q "^${xcodebuild_pid}$"; do
    if (( elapsed >= SHOW_BUILD_SETTINGS_TIMEOUT )); then
      kill "$xcodebuild_pid" 2>/dev/null || true
      wait "$xcodebuild_pid" 2>/dev/null || true
      rm -f "$output_file"
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$xcodebuild_pid"
  cmd_status=$?

  if (( cmd_status == 0 )); then
    cat "$output_file"
  fi

  rm -f "$output_file"
  return "$cmd_status"
}

check_target_configuration() {
  local target="$1"
  local configuration="$2"
  local settings cmd_status version build generate_info_plist

  printf 'Checking %s %s build settings...\n' "$target" "$configuration"
  if settings="$(read_build_settings "$target" "$configuration")"; then
    :
  else
    cmd_status=$?
    if (( cmd_status == 124 )); then
      fail "$target $configuration build settings timed out after ${SHOW_BUILD_SETTINGS_TIMEOUT}s"
    else
      fail "$target $configuration build settings could not be read"
    fi
    return
  fi

  version="$(extract_setting "$settings" MARKETING_VERSION)"
  build="$(extract_setting "$settings" CURRENT_PROJECT_VERSION)"
  generate_info_plist="$(extract_setting "$settings" GENERATE_INFOPLIST_FILE)"

  if [[ -z "$version" ]]; then
    fail "$target $configuration MARKETING_VERSION is empty"
  elif [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "$target $configuration MARKETING_VERSION is not semver: $version"
  fi

  if [[ -z "$build" ]]; then
    fail "$target $configuration CURRENT_PROJECT_VERSION is empty"
  elif [[ ! "$build" =~ ^[0-9]+$ || "$build" -lt 1 ]]; then
    fail "$target $configuration CURRENT_PROJECT_VERSION must be a positive integer: $build"
  fi

  if [[ "$generate_info_plist" != "YES" ]]; then
    fail "$target $configuration GENERATE_INFOPLIST_FILE must be YES so Bundle version metadata is emitted"
  fi

  if [[ -n "$version" ]]; then
    if [[ -z "$expected_version" ]]; then
      expected_version="$version"
    elif [[ "$version" != "$expected_version" ]]; then
      fail "$target $configuration version mismatch: expected $expected_version, found $version"
    fi
  fi

  if [[ -n "$build" ]]; then
    if [[ -z "$expected_build" ]]; then
      expected_build="$build"
    elif [[ "$build" != "$expected_build" ]]; then
      fail "$target $configuration build mismatch: expected $expected_build, found $build"
    fi
  fi

  if [[ -n "$version" && -n "$build" ]]; then
    pass "$target $configuration -> $version ($build)"
  fi
}

for target in "${TARGETS[@]}"; do
  for configuration in "${CONFIGURATIONS[@]}"; do
    check_target_configuration "$target" "$configuration"
  done
done

if (( failures == 0 )); then
  printf 'Current app version: %s (%s)\n' "$expected_version" "$expected_build"
else
  printf 'App version check found %d issue(s).\n' "$failures"
fi

exit "$failures"
