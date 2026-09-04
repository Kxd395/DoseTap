#!/usr/bin/env bash
# DoseTap SSOT integrity checks. Passing proves only the local static contract checks below.

set -uo pipefail

if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: ripgrep (rg) is required; install it before running repository checks." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

ERRORS=0

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1"
  ERRORS=$((ERRORS + 1))
}

SSOT="docs/SSOT/README.md"
OPENAPI="docs/SSOT/contracts/api.openapi.yaml"
CLIENT="ios/Core/APIClient.swift"

printf 'DoseTap SSOT integrity check\n'

REQUIRED_FILES=(
  "$SSOT"
  "docs/SSOT/navigation.md"
  "docs/SSOT/constants.json"
  "docs/SSOT/dose-state-persistence.md"
  "docs/SSOT/alarm-scheduling.md"
  "docs/SSOT/encryption-at-rest.md"
  "docs/SSOT/contracts/DataDictionary.md"
  "$OPENAPI"
  "docs/DATABASE_SCHEMA.md"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    fail "required SSOT file is missing: $file"
  fi
done

if [[ ! -f "$SSOT" ]]; then
  exit 1
fi

REQUIRED_SECTIONS=(
  "## Canonical References"
  "## Domain Entities and Invariants"
  "## State Machines and Transitions"
  "## Event Flow (UI -> Domain -> Storage -> Diagnostics -> UI)"
  "## Time Boundary Model"
  "## Storage and Persistence Truth"
  "## Known Limitations (Truth, Not Plans)"
  "## HealthKit Interaction Diagram"
  "## Alarm and Notification System"
  "## Channel Parity (Dose Entry Surfaces)"
)

for heading in "${REQUIRED_SECTIONS[@]}"; do
  if ! rg -Fq "$heading" "$SSOT"; then
    fail "SSOT section is missing: $heading"
  fi
done

if rg -Fq '150 minutes inclusive through 240 minutes exclusive' "$SSOT" && rg -qi 'default target interval is 165' "$SSOT" && rg -qi 'rolls over at 18:00' "$SSOT" && rg -qi 'undo window is 5 seconds' "$SSOT"; then
  pass "medication window, default target, rollover, and undo constraints are present"
else
  fail "one or more core safety constraints are absent from the SSOT"
fi

if rg -Fq 'docs/SSOT/README.md' README.md && rg -Fq 'docs/README.md' README.md; then
  pass "root README points to documentation governance and the SSOT"
else
  fail "root README does not expose the documentation authority chain"
fi

if [[ -f "$CLIENT" && -f "$OPENAPI" ]]; then
  CLIENT_PATHS="$(mktemp -t dosetap-client-paths.XXXXXX)"
  CONTRACT_PATHS="$(mktemp -t dosetap-contract-paths.XXXXXX)"
  trap 'rm -f "$CLIENT_PATHS" "$CONTRACT_PATHS"' EXIT

  sed -nE 's/.*case [A-Za-z0-9_]+ = "(\/[^\"]+)".*/\1/p' "$CLIENT" | sort -u > "$CLIENT_PATHS"
  sed -nE 's/^  (\/[^:]+):.*/\1/p' "$OPENAPI" | sort -u > "$CONTRACT_PATHS"

  if diff -u "$CLIENT_PATHS" "$CONTRACT_PATHS" >/dev/null; then
    pass "APIClient endpoints match the OpenAPI placeholder"
  else
    fail "APIClient endpoints differ from the OpenAPI placeholder"
    diff -u "$CLIENT_PATHS" "$CONTRACT_PATHS" || true
  fi
fi

printf '\nSSOT check result\n'
if [[ "$ERRORS" -ne 0 ]]; then
  printf 'SSOT integrity check failed with %s local static issue(s).\n' "$ERRORS"
  exit 1
fi

printf 'SSOT local static checks passed. Runtime, signed-device, hosted-service, privacy, and owner-review gates remain separate.\n'
