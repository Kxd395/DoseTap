#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/dosetap-inventory-guard.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/tools" "$SCRATCH/ios/DoseTap/Storage"
cp "$ROOT/tools/check_inventory_state_writes.sh" "$SCRATCH/tools/"
cp "$ROOT/ios/DoseTap/SettingsStudioExport.swift" "$SCRATCH/ios/DoseTap/"
cp "$ROOT/ios/DoseTap/Storage/EventStorage+DashboardSnapshot.swift" "$SCRATCH/ios/DoseTap/Storage/"
CHECK="$SCRATCH/tools/check_inventory_state_writes.sh"
bash "$CHECK" >/dev/null
expect_rejection() {
  if bash "$CHECK" >"$SCRATCH/check.log" 2>&1; then
    echo "FAIL: inventory guard accepted $1" >&2
    exit 1
  fi
}
printf '%s\n' 'let records = storage.fetchInventorySnapshots(limit: 10)' > "$SCRATCH/ios/DoseTap/BadView.swift"
expect_rejection 'direct UI storage read'
printf '%s\n' 'let table = "inventory_snapshots"' > "$SCRATCH/ios/DoseTap/BadView.swift"
expect_rejection 'UI table literal'
printf '%s\n' 'let value: InventorySnapshot' > "$SCRATCH/ios/DoseTap/BadView.swift"
expect_rejection 'legacy Core Data inventory'
rm "$SCRATCH/ios/DoseTap/BadView.swift"
printf '%s\n' 'let records = repo.listInventorySnapshots()' > "$SCRATCH/ios/DoseTap/SettingsStudioExport.swift"
expect_rejection 'unchecked export accessor'
printf '%s\n' 'let records = repo.inventoryExportRecords()' 'let quantity = DoseTapUserConfig.shared.dosesPerBottle' > "$SCRATCH/ios/DoseTap/SettingsStudioExport.swift"
expect_rejection 'derived setup quantity'
cp "$ROOT/ios/DoseTap/SettingsStudioExport.swift" "$SCRATCH/ios/DoseTap/"
bash "$CHECK" >/dev/null
echo 'Inventory guard regression checks passed (authoritative path and five rejected regressions)'
