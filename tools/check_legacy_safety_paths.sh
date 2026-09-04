#!/usr/bin/env bash

set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: ripgrep (rg) is required; install it before running repository checks." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

failures=0

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  failures=1
}

retired_files=(
  ios/Core/APIClientQueueIntegration.swift
  ios/Core/TimeEngine.swift
  ios/DoseTap/Security/DatabaseSecurity.swift
  ios/DoseTap/Storage/EncryptedEventStorage.swift
)

for retired_file in "${retired_files[@]}"; do
  if [[ -e "$retired_file" ]]; then
    fail "retired safety-sensitive source returned: $retired_file"
  fi
done

for project_file in Package.swift ios/DoseTap.xcodeproj/project.pbxproj; do
  if grep -Eq 'APIClientQueueIntegration\.swift|TimeEngine\.swift|DatabaseSecurity\.swift|EncryptedEventStorage\.swift' "$project_file"; then
    fail "retired source is still referenced by $project_file"
  fi
done

if rg -n '/doses/(take|skip|snooze)' ios/Core ios/DoseTap --glob '*.swift' --glob '!**/Foundation/DevelopmentHelper.swift'; then
  fail "a remote medication endpoint exists in shipping source"
fi

if rg -n 'public[[:space:]]+func[[:space:]]+(takeDose|skipDose|snooze)' ios/Core --glob '*.swift'; then
  fail "a public medication mutation API exists in DoseCore"
fi

if rg -n '\b(DosingService|TimeEngine|SimpleDoseWindowState|EncryptedEventStorage|DatabaseSecurity|DoseTapSessionRepository)\b' ios/Core ios/DoseTap \
  --glob '*.swift' --glob '!**/Foundation/DevelopmentHelper.swift'; then
  fail "a retired safety-sensitive symbol exists in shipping source"
fi

if rg -n 'DoseTapCore\(isOnline:' ios Tests --glob '*.swift'; then
  fail "DoseTapCore still exposes the retired networking initializer"
fi

if rg --pcre2 -n 'core\.(dose1Time|dose2Time|isSkipped|snoozeCount)\s*=(?!=)' ios --glob '*.swift'; then
  fail "DoseTapCore read-only medication state is being assigned directly"
fi

if ! bash tools/check_dose_state_writes.sh; then
  failures=1
fi

if [[ $failures -ne 0 ]]; then
  exit 1
fi

printf 'Legacy safety-path guard passed: medication mutations are local/coordinated, conflicting timing is retired, and inactive encryption scaffolding is absent.\n'
