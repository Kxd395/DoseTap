#!/usr/bin/env python3
"""Exercise the inventory guard against isolated allowed and forbidden paths."""

import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
GUARD = ROOT / "tools/check_inventory_state_writes.sh"
EXPORT = "ios/DoseTap/SettingsStudioExport.swift"


class InventoryGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dosetap-inventory-guard-")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        (self.root / "tools").mkdir()
        shutil.copyfile(GUARD, self.root / "tools/check_inventory_state_writes.sh")
        self.export = "let rows = try repo.inventoryExportRecords().map { row in row }\n"
        self.write(EXPORT, self.export)
        self.write("ios/DoseTap/Storage/SessionRepositoryQueries.swift",
                   "return try storage.inventoryExportRecords()\n")
        self.write("ios/DoseTap/Storage/EventStorage+DashboardSnapshot.swift",
                   'let rows = try dashboardRows("inventory_snapshots")\n')
        for owner in ["Schema", "Exports", "Maintenance"]:
            self.write(f"ios/DoseTap/Storage/EventStorage+{owner}.swift",
                       'let table = "inventory_snapshots"\n')

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def run_guard(self, root=None):
        return subprocess.run(["bash", "tools/check_inventory_state_writes.sh"],
                              cwd=root or self.root, text=True, capture_output=True,
                              timeout=30, check=False)

    def assert_rejected(self, message):
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stdout + result.stderr)

    def test_current_checkout_passes(self):
        result = self.run_guard(ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_checked_export_and_exact_storage_owners_pass(self):
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_capped_listing_is_rejected_even_with_checked_read_present(self):
        self.write(EXPORT, self.export + "let other = repo.listInventorySnapshots()\n")
        self.assert_rejected("capped inventory listing")

    def test_missing_checked_read_is_rejected(self):
        self.write(EXPORT, "// try repo.inventoryExportRecords()\nlet rows = []\n")
        self.assert_rejected("must use the throwing repository inventoryExportRecords")

    def test_optional_or_forced_try_is_rejected(self):
        for operator in ["try?", "try!"]:
            with self.subTest(operator=operator):
                self.write(EXPORT, self.export + f"let other = {operator} repo.inventoryExportRecords()\n")
                self.assert_rejected("unchecked inventory export read")

    def test_export_cannot_bypass_repository(self):
        self.write(EXPORT, self.export + "let other = try storage.inventoryExportRecords()\n")
        self.assert_rejected("unchecked inventory export read")

    def test_checked_accessor_cannot_move_to_unreviewed_owner(self):
        self.write("ios/DoseTap/Views/Unexpected.swift", "let rows = try storage.inventoryExportRecords()\n")
        self.assert_rejected("inventory export read outside reviewed repository/export owners")

    def test_low_level_inventory_calls_remain_rejected(self):
        for method in ["upsertInventorySnapshot", "fetchInventorySnapshots",
                       "fetchLatestInventorySnapshot", "deleteInventorySnapshot"]:
            with self.subTest(method=method):
                self.write("ios/DoseTap/Views/Unexpected.swift", f"storage.{method}()\n")
                self.assert_rejected("direct inventory storage access")

    def test_table_literal_allowlist_is_not_all_storage(self):
        self.write("ios/DoseTap/Storage/EventStorage+Unexpected.swift",
                   'let table = "inventory_snapshots"\n')
        self.assert_rejected("table name leaked")

    def test_table_literal_in_view_is_rejected(self):
        self.write("ios/DoseTap/Views/Unexpected.swift", 'let table = "inventory_snapshots"\n')
        self.assert_rejected("table name leaked")

    def test_derived_inventory_sources_remain_rejected(self):
        for source in ["DoseTapUserConfig", "dosesPerBottle", "bottleMgTotal", "InventorySnapshot"]:
            with self.subTest(source=source):
                self.write(EXPORT, self.export + f"let derived = {source}\n")
                self.assert_rejected("non-authoritative inventory source")

    def test_active_legacy_store_remains_rejected(self):
        self.write("ios/DoseTap/Views/Unexpected.swift", "let store = LegacyPersistentStore.shared\n")
        self.assert_rejected("legacy Core Data inventory reached active app code")


if __name__ == "__main__":
    unittest.main()
