#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOW_LEVEL_PATTERN='\.((saveDose1|saveDose2|saveDoseSkipped|saveSnooze|saveDoseEvent|insertDoseEvent|upsertDoseEvent|clearDose1|clearDose2|clearSkip|updateDose1Time|updateDose2Time))[[:space:]]*\('
LIVE_COMMAND_PATTERN='\.(setDose1Time|setDose2Time|skipDose2|incrementSnooze)[[:space:]]*\('

violations=0

scan_swift() {
  local pattern="$1"
  git grep -nE "$pattern" -- 'ios/DoseTap/*.swift' 'ios/DoseTap/**/*.swift' 2>/dev/null || true
}

allowed_low_level_file() {
  local file="$1"
  case "$file" in
    ios/DoseTap/Storage/*) return 0 ;;
    ios/DoseTap/AppContainer.swift) return 0 ;;
    ios/DoseTap/Views/History/HistorySelectedDayView.swift) return 0 ;;
    *) return 1 ;;
  esac
}

allowed_live_command_file() {
  local file="$1"
  case "$file" in
    ios/DoseTap/DoseActionCoordinator.swift) return 0 ;;
    ios/DoseTap/Storage/SessionRepository.swift) return 0 ;;
    ios/DoseTap/Storage/SessionRepositorySync.swift) return 0 ;;
    *) return 1 ;;
  esac
}

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  if ! allowed_low_level_file "$file"; then
    echo "FAIL: direct dose storage mutation outside allowed boundary"
    echo "  $hit"
    violations=1
  fi
done < <(scan_swift "$LOW_LEVEL_PATTERN")

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  if ! allowed_live_command_file "$file"; then
    echo "FAIL: live dose command outside DoseActionCoordinator or SessionRepository boundary"
    echo "  $hit"
    violations=1
  fi
done < <(scan_swift "$LIVE_COMMAND_PATTERN")

if [[ "$violations" -ne 0 ]]; then
  echo ""
  echo "Dose state writes must follow docs/SSOT/dose-state-persistence.md."
  exit 1
fi

echo "Dose state write-path guard passed"
