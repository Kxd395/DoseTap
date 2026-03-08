#!/bin/bash

set -euo pipefail

dt_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

dt_repo_root() {
  cd "$(dt_script_dir)/.." && pwd
}

dt_project_path() {
  echo "${DT_PROJECT_PATH:-$(dt_repo_root)/ios/DoseTap.xcodeproj}"
}

dt_scheme() {
  echo "${DT_SCHEME:-DoseTap}"
}

dt_configuration() {
  echo "${DT_CONFIGURATION:-Debug}"
}

dt_default_simulator_name() {
  echo "${DT_SIMULATOR_NAME:-iPhone 16}"
}

dt_default_test_destination() {
  echo "${DT_TEST_DESTINATION:-platform=iOS Simulator,name=$(dt_default_simulator_name)}"
}

dt_require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
}

dt_resolve_simulator_udid() {
  local requested_name="${1:-$(dt_default_simulator_name)}"
  xcrun simctl list devices available |
    grep -F "    $requested_name (" |
    sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' |
    head -n 1
}

dt_print_xcode_context() {
  echo "Project: $(dt_project_path)"
  echo "Scheme:  $(dt_scheme)"
  echo "Config:  $(dt_configuration)"
}
