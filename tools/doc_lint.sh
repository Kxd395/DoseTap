#!/usr/bin/env bash
# DoseTap documentation lifecycle and drift checks.
# Run from any directory: bash tools/doc_lint.sh

set -uo pipefail

if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: ripgrep (rg) is required; install it before running repository checks." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

FAIL=0

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1"
  FAIL=1
}

section() {
  printf '\n%s\n' "$1"
}

section "Documentation lifecycle labels"

CURRENT_ROOT_DOCS=(
  "docs/README.md"
  "docs/PLANNING.md"
  "docs/FEATURE_TRIAGE.md"
  "docs/PRODUCTION_READINESS_CHECKLIST.md"
  "docs/RELEASE_CHECKLIST.md"
  "docs/TESTING_GUIDE.md"
  "docs/DATABASE_SCHEMA.md"
  "docs/DIAGNOSTIC_LOGGING.md"
  "docs/HOW_TO_READ_A_SESSION_TRACE.md"
  "docs/COMPANION_TARGET_STATUS.md"
  "docs/INSIGHTS_STATUS.md"
  "docs/INSIGHTS_DATA_GOVERNANCE.md"
  "docs/WHOOP_INTEGRATION.md"
  "docs/CLOUDKIT_GO_LIVE_CHECKLIST.md"
  "docs/CERTIFICATE_PINNING.md"
  "docs/APPLE_DEV_CLI_SETUP.md"
  "docs/TESTFLIGHT_GUIDE.md"
  "docs/BRANCH_PROTECTION.md"
  "docs/REPOSITORY_HYGIENE.md"
)

for file in "${CURRENT_ROOT_DOCS[@]}"; do
  if [[ ! -f "$file" ]]; then
    fail "required current document is missing: $file"
  elif ! sed -n '1,12p' "$file" | rg -q '^Status:'; then
    fail "required current document lacks a Status label near the top: $file"
  elif ! rg -Fq "\`$(basename "$file")\`" docs/README.md; then
    fail "docs/README.md does not classify $file"
  fi
done

DIRECTORY_INDEXES=(
  "docs/SSOT/README.md"
  "docs/architecture/README.md"
  "docs/MYWAV_DOSETAP/README.md"
  "docs/audit/README.md"
  "docs/archive/README.md"
  "docs/handoff/README.md"
  "docs/historical/README.md"
  "docs/icon/README.md"
  "docs/prompt/README.md"
  "docs/review/README.md"
)

for file in "${DIRECTORY_INDEXES[@]}"; do
  if [[ ! -f "$file" ]]; then
    fail "documentation directory lacks its lifecycle README: $file"
  elif ! sed -n '1,12p' "$file" | rg -q '^Status:'; then
    fail "directory README lacks a Status label near the top: $file"
  fi
done

if [[ -f docs/privacy-policy.html ]] && sed -n '1,5p' docs/privacy-policy.html | rg -q 'Status:'; then
  pass "privacy-policy.html is classified"
else
  fail "privacy-policy.html lacks a lifecycle comment"
fi

if [[ -f docs/support.html ]] && sed -n '1,5p' docs/support.html | rg -q 'Status:'; then
  pass "support.html is classified"
else
  fail "support.html lacks a lifecycle comment"
fi

if [[ "$FAIL" -eq 0 ]]; then
  pass "root documents and directory trees are classified"
fi

section "Moved and superseded paths"

ACTIVE_DOC_TARGETS=(
  README.md
  .github/copilot-instructions.md
  docs/*.md
  docs/SSOT
  docs/architecture
  docs/MYWAV_DOSETAP
  docs/prompt
)

MOVED_PATH_PATTERN='docs/(architecture\.md|AUDIT_PROMPT_V2\.md|DATA_PIPELINE_AUDIT\.md|IMPROVEMENT_ROADMAP\.md|INSIGHTS_OPTIMAL_TIMING_TODO\.md|INSIGHTS_VIEWER_IMPLEMENTATION_PLAN\.md|INSIGHTS_VIEWER_MVP\.md|ROADMAP_TODO\.md|SYMPHONY_SETUP\.md|governance_setup_report_2-9-2026\.md)'
MOVED_HITS="$(rg -n "$MOVED_PATH_PATTERN" "${ACTIVE_DOC_TARGETS[@]}" --glob '*.md' 2>/dev/null || true)"
if [[ -n "$MOVED_HITS" ]]; then
  fail "active documentation references a superseded path"
  printf '%s\n' "$MOVED_HITS"
else
  pass "active documentation does not reference moved root documents"
fi

if [[ -d docs/icon/dosetap-liquid-glass-window/dosetap-liquid-glass-window ]]; then
  fail "byte-identical nested icon source still exists in the active design tree"
else
  pass "duplicate nested icon bundle is archived"
fi

DOC_METADATA="$(find docs -type f -name '.DS_Store' -print)"
if [[ -n "$DOC_METADATA" ]]; then
  fail "generated .DS_Store files exist under docs"
  printf '%s\n' "$DOC_METADATA"
else
  pass "no generated .DS_Store file exists under docs"
fi

section "Schema and contract alignment"

DB_VERSION="$(awk -F': *' 'tolower($1) == "sqlite user_version" { print $2; exit }' docs/DATABASE_SCHEMA.md)"
DICTIONARY_VERSION="$(awk -F': *' 'tolower($1) == "sqlite user_version" { print $2; exit }' docs/SSOT/contracts/DataDictionary.md)"
SOURCE_VERSION="$(sed -nE 's/.*schemaUserVersion[^=]*=[[:space:]]*([0-9]+).*/\1/p' ios/DoseTap/Storage/EventStorage.swift | head -n 1)"

if [[ -n "$DB_VERSION" && "$DB_VERSION" == "$DICTIONARY_VERSION" && "$DB_VERSION" == "$SOURCE_VERSION" ]]; then
  pass "SQLite user_version $DB_VERSION agrees across code, schema, and dictionary"
else
  fail "SQLite user_version differs: code=${SOURCE_VERSION:-missing}, schema=${DB_VERSION:-missing}, dictionary=${DICTIONARY_VERSION:-missing}"
fi

CONSTANTS_DOC_VERSION="$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' docs/SSOT/constants.json | head -n 1)"
CONSTANTS_CODE_VERSION="$(sed -nE 's/.*constantsVersion[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' ios/DoseTap/Storage/EventStorage.swift | head -n 1)"
if [[ -n "$CONSTANTS_DOC_VERSION" && "$CONSTANTS_DOC_VERSION" == "$CONSTANTS_CODE_VERSION" ]]; then
  pass "constants version $CONSTANTS_DOC_VERSION agrees with export metadata"
else
  fail "constants version differs: code=${CONSTANTS_CODE_VERSION:-missing}, document=${CONSTANTS_DOC_VERSION:-missing}"
fi

TABLES=(
  sleep_events
  dose_events
  current_session
  sleep_sessions
  pre_sleep_logs
  morning_checkins
  checkin_submissions
  cloudkit_tombstones
  schema_migrations
  medication_events
  inventory_snapshots
  symptom_events
  symptom_locations
  body_map_points
  symptom_command_log
  symptom_summaries
)

for table in "${TABLES[@]}"; do
  if ! rg -Fq "CREATE TABLE IF NOT EXISTS $table" ios/DoseTap/Storage/EventStorage+Schema.swift; then
    fail "expected table is absent from executable schema: $table"
  fi
  if ! rg -Fq "$table" docs/DATABASE_SCHEMA.md; then
    fail "DATABASE_SCHEMA.md omits table: $table"
  fi
  if ! rg -Fq "$table" docs/SSOT/contracts/DataDictionary.md; then
    fail "DataDictionary.md omits table: $table"
  fi
done

if [[ "$FAIL" -eq 0 ]]; then
  pass "all executable tables appear in both current schema documents"
fi

section "Machine-readable contracts"

if command -v python3 >/dev/null 2>&1; then
  for json_file in docs/SSOT/constants.json docs/SSOT/contracts/companion-targets.json; do
    if python3 -m json.tool "$json_file" >/dev/null 2>&1; then
      pass "valid JSON: $json_file"
    else
      fail "invalid JSON: $json_file"
    fi
  done

  if python3 - ios/DoseTap/UserSettingsManager.swift ios/DoseTap/FullApp/SetupWizardStepViews.swift docs/SSOT/constants.json <<'PY'
import json
import re
import sys

settings_path, setup_path, contract_path = sys.argv[1:]
settings = open(settings_path, encoding="utf-8").read()
setup = open(setup_path, encoding="utf-8").read()
with open(contract_path, encoding="utf-8") as handle:
    contract = json.load(handle)

errors = []

def scalar(pattern, label, cast=int):
    match = re.search(pattern, settings)
    if not match:
        errors.append(f"cannot discover {label} from UserSettingsManager.swift")
        return None
    return cast(match.group(1))

def integer_array(pattern, label):
    match = re.search(pattern, settings)
    if not match:
        errors.append(f"cannot discover {label} from UserSettingsManager.swift")
        return None
    return [int(float(value.strip())) for value in match.group(1).split(",")]

def picker_choices(setting, label):
    match = re.search(
        rf'Picker\("", selection: \$config\.{setting}\) \{{(.*?)\n\s*\}}\n\s*\.pickerStyle',
        setup,
        re.S,
    )
    if not match:
        errors.append(f"cannot discover {label} from SetupWizardStepViews.swift")
        return None
    return [int(value) for value in re.findall(r'\.tag\((\d+)\)', match.group(1))]

snooze_default = scalar(r'snoozeDurationMinutes: Int = (\d+)', "snooze default")
snooze_range_match = re.search(r'snoozeDurationMinutes = max\((\d+), min\((\d+),', settings)
max_snoozes_default = scalar(r'maxSnoozes: Int = (\d+)', "maximum snooze default")
max_snoozes_range_match = re.search(r'maxSnoozes = max\((\d+), min\((\d+),', settings)
undo_default = scalar(r'undoWindowSeconds: Double = ([0-9.]+)', "undo default", float)
undo_options = integer_array(r'validUndoWindowOptions: \[Double\] = \[([^]]+)\]', "undo options")
snooze_setup_choices = picker_choices("snoozeStepMinutes", "snooze setup choices")
max_snoozes_setup_choices = picker_choices("maxSnoozes", "maximum snooze setup choices")

quick_log_match = re.search(
    r'private let defaultQuickLogButtons: \[QuickLogButtonConfig\] = \[(.*?)\n\s*\]',
    settings,
    re.S,
)
if quick_log_match:
    quick_log_defaults = re.findall(r'QuickLogButtonConfig\(id: "([^"]+)"', quick_log_match.group(1))
else:
    quick_log_defaults = None
    errors.append("cannot discover default Quick Log buttons from UserSettingsManager.swift")

if snooze_default != contract["snooze"]["durationMinutes"]["default"]:
    errors.append("snooze duration default differs")
if snooze_range_match and [int(value) for value in snooze_range_match.groups()] != contract["snooze"]["durationMinutes"]["persistenceNormalizationRange"]:
    errors.append("snooze duration persistence normalization range differs")
if not snooze_range_match:
    errors.append("cannot discover snooze duration range from UserSettingsManager.swift")
if max_snoozes_default != contract["snooze"]["maxCount"]["default"]:
    errors.append("maximum snooze default differs")
if max_snoozes_range_match and [int(value) for value in max_snoozes_range_match.groups()] != contract["snooze"]["maxCount"]["persistenceNormalizationRange"]:
    errors.append("maximum snooze persistence normalization range differs")
if not max_snoozes_range_match:
    errors.append("cannot discover maximum snooze range from UserSettingsManager.swift")
if undo_default != contract["undo"]["windowSeconds"]["default"]:
    errors.append("undo default differs")
if undo_options != contract["undo"]["windowSeconds"]["validOptions"]:
    errors.append("undo options differ")
if snooze_setup_choices != contract["snooze"]["durationMinutes"]["setupChoices"]:
    errors.append("snooze setup choices differ")
if max_snoozes_setup_choices != contract["snooze"]["maxCount"]["setupChoices"]:
    errors.append("maximum snooze setup choices differ")
if quick_log_defaults != contract["quickLogPanel"]["defaultSlots"]:
    errors.append("default Quick Log buttons differ")

if errors:
    print("; ".join(errors))
    raise SystemExit(1)
PY
  then
    pass "timing defaults, setup choices, persistence tolerance, and Quick Log defaults agree with code"
  else
    fail "constants.json differs from shipping configurable defaults"
  fi
else
  fail "python3 is required to validate current JSON contracts"
fi

section "Evergreen claim hygiene"

COUNT_HITS="$(rg -n '\b[0-9][0-9]*\+?[[:space:]]+(tests|test cases|test files|Swift files|source files)\b' "${ACTIVE_DOC_TARGETS[@]}" --glob '*.md' 2>/dev/null || true)"
if [[ -n "$COUNT_HITS" ]]; then
  fail "active documentation contains an evergreen test or source count; use a discovery command or dated evidence"
  printf '%s\n' "$COUNT_HITS"
else
  pass "active documentation avoids mutable test and source totals"
fi

if rg -Fq 'Event Types (13 total)' docs/DATABASE_SCHEMA.md; then
  fail "DATABASE_SCHEMA.md treats the DoseCore enum as a closed storage taxonomy"
else
  pass "schema documentation distinguishes the core enum from the forward-compatible stored vocabulary"
fi

section "Documentation lint result"

if [[ "$FAIL" -ne 0 ]]; then
  printf 'Documentation lint failed.\n'
  exit 1
fi

printf 'Documentation lint passed.\n'
