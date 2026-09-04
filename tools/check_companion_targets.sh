#!/usr/bin/env bash

set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: ripgrep (rg) is required; install it before running repository checks." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

manifest="docs/SSOT/contracts/companion-targets.json"
project="ios/DoseTap.xcodeproj"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

jq -e '.schema_version == 1' "$manifest" >/dev/null || fail "unsupported companion manifest schema"
status="$(jq -r '.support_status' "$manifest")"
supported_count="$(jq '.supported_targets | length' "$manifest")"

[[ "$status" == "proposal_only" ]] || fail "companion support status must remain proposal_only until target activation is reviewed"
[[ "$supported_count" == "0" ]] || fail "supported companion targets require a CI build matrix and physical acceptance plan before manifest promotion"

active_paths=(
  watchos/DoseTapWatch
  ios/DoseTap/Widget
)
for active_path in "${active_paths[@]}"; do
  [[ ! -e "$active_path" ]] || fail "proposal source returned to the active shipping tree: $active_path"
done

watch_proposal="$(jq -r '.proposal_sources.watchos' "$manifest")"
widget_proposal="$(jq -r '.proposal_sources.widget' "$manifest")"
[[ -f "$watch_proposal/DoseTapWatchApp.swift" ]] || fail "watchOS proposal source is missing"
[[ -f "$widget_proposal/DoseTapWidgets.swift" ]] || fail "widget proposal source is missing"
[[ -f "$widget_proposal/SharedDoseState.swift" ]] || fail "widget shared-state proposal is missing"

if grep -Eq 'DoseTapWidgets|SharedDoseState|DoseTapWatch|WatchComplications' "$project/project.pbxproj"; then
  fail "proposal-only companion source is referenced by the shipping Xcode project"
fi

project_listing="$(xcodebuild -project "$project" -list -json 2>/dev/null)"
companion_targets="$(jq -r '.project.targets[]?, .project.schemes[]?' <<<"$project_listing" | grep -Ei 'watch|widget|complication' || true)"
if [[ -n "$companion_targets" ]]; then
  printf '%s\n' "$companion_targets" >&2
  fail "an undeclared companion target or scheme exists"
fi

if rg -n '\b(import WidgetKit|WatchConnectivity|WCSession|@main.*Widget)' ios/DoseTap --glob '*.swift'; then
  fail "companion-only framework or entry-point source exists in the phone app tree"
fi

printf 'Companion target contract passed: zero supported companion targets; watchOS and widget code are proposal-only and absent from the shipping project.\n'
