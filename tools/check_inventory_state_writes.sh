#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: ripgrep (rg) is required; install it before running repository checks." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

violations=0

scan_app_swift() {
  local pattern="$1"
  rg -n --glob '*.swift' "$pattern" ios/DoseTap 2>/dev/null || true
}

fail() {
  echo "FAIL: $1"
  if [[ -n "${2:-}" ]]; then
    echo "$2"
  fi
  violations=1
}

LOW_LEVEL_PATTERN='\.((upsertInventorySnapshot|fetchInventorySnapshots|fetchLatestInventorySnapshot|deleteInventorySnapshot))[[:space:]]*\('
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  case "$file" in
    ios/DoseTap/Storage/EventStorage+Exports.swift) ;;
    ios/DoseTap/Storage/SessionRepositoryMedication.swift) ;;
    *)
      fail "direct inventory storage access outside repository/storage boundary" "  $hit"
      ;;
  esac
done < <(scan_app_swift "$LOW_LEVEL_PATTERN")

TABLE_LITERAL_HITS="$(
  scan_app_swift 'inventory_snapshots' \
    | grep -v '^ios/DoseTap/Storage/EventStorage+Schema.swift:' \
    | grep -v '^ios/DoseTap/Storage/EventStorage+Exports.swift:' \
    | grep -v '^ios/DoseTap/Storage/EventStorage+DashboardSnapshot.swift:' \
    | grep -v '^ios/DoseTap/Storage/EventStorage+Maintenance.swift:' || true
)"
if [[ -n "$TABLE_LITERAL_HITS" ]]; then
  fail "inventory_snapshots table name leaked outside storage schema/accessors" "$TABLE_LITERAL_HITS"
fi

STUDIO_EXPORT="ios/DoseTap/SettingsStudioExport.swift"

# Exports require the uncapped, throwing reader. The compatibility list is capped
# and can return an empty array on failure, so it cannot establish export truth.
STATEMENT_PREFIX='^[[:space:]]*((let|var)[[:space:]]+[[:alnum:]_]+[[:space:]]*=[[:space:]]*|return[[:space:]]+)?try[[:space:]]+'
REPOSITORY_EXPORT="${STATEMENT_PREFIX}"'repo\.inventoryExportRecords[[:space:]]*\('
STORAGE_EXPORT="${STATEMENT_PREFIX}"'storage\.inventoryExportRecords[[:space:]]*\('
if ! python3 tools/check_inventory_export_call.py "$STUDIO_EXPORT"; then
  fail "Studio export must use the throwing repository inventoryExportRecords reader"
fi

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  statement="${hit#*:}"
  statement="${statement#*:}"
  case "$file" in
    ios/DoseTap/SettingsStudioExport.swift) expected="$REPOSITORY_EXPORT" ;;
    ios/DoseTap/Storage/SessionRepositoryQueries.swift) expected="$STORAGE_EXPORT" ;;
    *)
      fail "inventory export read outside reviewed repository/export owners" "  $hit"
      continue
      ;;
  esac
  if ! printf '%s\n' "$statement" | rg -q "$expected"; then
    fail "unchecked inventory export read; use ordinary try and the reviewed receiver" "  $hit"
  fi
done < <(scan_app_swift '\.inventoryExportRecords[[:space:]]*\(')

CAPPED_EXPORT_HITS="$(rg -n '\.listInventorySnapshots[[:space:]]*\(' "$STUDIO_EXPORT" || true)"
if [[ -n "$CAPPED_EXPORT_HITS" ]]; then
  fail "Studio export must not use a capped inventory listing" "$CAPPED_EXPORT_HITS"
fi

EXPORT_DERIVED_SOURCE_HITS="$(
  rg -n 'DoseTapUserConfig|dosesPerBottle|bottleMgTotal|LegacyPersistentStore|(^|[^[:alnum:]_])InventorySnapshot([^[:alnum:]_]|$)' "$STUDIO_EXPORT" 2>/dev/null || true
)"
if [[ -n "$EXPORT_DERIVED_SOURCE_HITS" ]]; then
  fail "Studio inventory export is reading a non-authoritative inventory source" "$EXPORT_DERIVED_SOURCE_HITS"
fi

LEGACY_ACTIVE_HITS="$(
  scan_app_swift 'LegacyPersistentStore|(^|[^[:alnum:]_])InventorySnapshot([^[:alnum:]_]|$)' \
    | grep -v '^ios/DoseTap/Legacy/' \
    | grep -v '^ios/DoseTap/Foundation/DevelopmentHelper.swift:' || true
)"
if [[ -n "$LEGACY_ACTIVE_HITS" ]]; then
  fail "legacy Core Data inventory reached active app code" "$LEGACY_ACTIVE_HITS"
fi

if [[ "$violations" -ne 0 ]]; then
  echo ""
  echo "Inventory reads/writes must remain behind SessionRepository and approved EventStorage owners."
  echo "Studio inventory export must use the uncapped throwing repository reader."
  echo "Do not derive current inventory from dose logs, setup wizard bottle capacity, or legacy Core Data."
  exit 1
fi

echo "Inventory state write-path guard passed"
