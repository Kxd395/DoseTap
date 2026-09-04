#!/usr/bin/env bash
set -euo pipefail

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
    | grep -v '^ios/DoseTap/Storage/EventStorage+Maintenance.swift:' || true
)"
if [[ -n "$TABLE_LITERAL_HITS" ]]; then
  fail "inventory_snapshots table name leaked outside storage schema/accessors" "$TABLE_LITERAL_HITS"
fi

STUDIO_EXPORT="ios/DoseTap/SettingsStudioExport.swift"

if ! rg -q 'repo.listInventorySnapshots' "$STUDIO_EXPORT"; then
  fail "Studio export must read inventory through SessionRepository.listInventorySnapshots"
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
  echo "Inventory must flow: MedicationSettingsView -> SessionRepository -> EventStorage.inventory_snapshots -> SettingsStudioExport."
  echo "Do not derive current inventory from dose logs, setup wizard bottle capacity, or legacy Core Data."
  exit 1
fi

echo "Inventory state write-path guard passed"
