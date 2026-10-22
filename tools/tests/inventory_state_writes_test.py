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
        shutil.copyfile(ROOT / "tools/check_inventory_export_call.py",
                        self.root / "tools/check_inventory_export_call.py")
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

    def test_commented_or_literal_read_cannot_satisfy_required_call(self):
        examples = [
            "/*\n" + self.export + "*/\n",
            "/* outer\n/* nested */\n" + self.export + "*/\n",
            'let example = """\n' + self.export + '"""\n',
            'let example = #"""\n' + self.export + '"""#\n',
            'let example = """\n\\(format("label"))\n' + self.export + '"""\n',
        ]
        for example in examples:
            with self.subTest(example=example):
                self.write(EXPORT, example + "let rows = []\n")
                self.assert_rejected("must use the throwing repository inventoryExportRecords")

    def test_real_call_after_comments_and_strings_passes(self):
        examples = [
            "/* outer /* nested */ still comment */\n",
            'let url = "https://example.invalid/*not-a-comment*/"\n',
            'let example = #"quote: \" /* still a raw string */"#\n',
            'let example = """\n/* literal text */\n"""\n',
        ]
        for example in examples:
            with self.subTest(example=example):
                self.write(EXPORT, example + self.export)
                result = self.run_guard()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_regex_literal_cannot_satisfy_required_call(self):
        for hashes in ["#", "##", "###"]:
            with self.subTest(hashes=hashes):
                self.write(EXPORT, f"let ignored = {hashes}/\n"
                           "try repo.inventoryExportRecords(.+)\n"
                           f"/{hashes}\nlet rows = []\n")
                self.assert_rejected("must use the throwing repository inventoryExportRecords")

    def test_real_call_after_regex_literal_passes(self):
        for literal in ["#/abc/#", "##/slash /# remains literal/##",
                        r"#/escaped \/# remains literal/#",
                        "#/\n[/*] a quote \"\n/#"]:
            with self.subTest(literal=literal):
                self.write(EXPORT, "let pattern = " + literal + "\n" + self.export)
                result = self.run_guard()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_regex_interpolation_comment_cannot_supply_call(self):
        for hashes in ["#", "##", "###"]:
            for expression in ["piece", "identity((piece))"]:
                with self.subTest(hashes=hashes, expression=expression):
                    source = (f"let piece = {hashes}/safe/{hashes}\n"
                              f"let ignored = {hashes}/\n\\{hashes}(\n/*\n/{hashes}\n"
                              "try repo.inventoryExportRecords()\n*/\n"
                              f"{expression}\n)\n/{hashes}\n")
                    self.write(EXPORT, source + "let rows = []\n")
                    self.assert_rejected("must use the throwing repository inventoryExportRecords")

    def test_bare_regex_in_interpolation_cannot_expose_nested_string(self):
        source = ('let ignored = """\n\\(\n'
                  'String(describing: /[)]/ as Regex<Substring>) + """\n'
                  'try repo.inventoryExportRecords()\n"""\n)\n"""\n')
        self.write(EXPORT, source + "let rows = []\n")
        self.assert_rejected("must use the throwing repository inventoryExportRecords")

    def test_ambiguous_slash_interpolation_fails_even_with_real_call(self):
        for expression in ["1 / 2", "String(describing: /[)]/)"]:
            with self.subTest(expression=expression):
                self.write(EXPORT, 'let text = "\\(' + expression + ')"\n' + self.export)
                self.assert_rejected("bare slash inside interpolation requires guard review")

    def test_regex_interpolation_like_syntax_requires_review_even_with_real_call(self):
        for hashes in ["#", "##"]:
            with self.subTest(hashes=hashes):
                source = (f"let piece = {hashes}/safe/{hashes}\n"
                          f"let ignored = {hashes}/\n\\{hashes}(\n/*\n/{hashes}\n*/\n"
                          f"identity(({hashes}/[)]/{hashes}))\n)\n/{hashes}\n")
                self.write(EXPORT, source + self.export)
                self.assert_rejected("regex interpolation-like syntax requires guard review")

    def test_top_level_bare_regex_fails_closed_before_scanning_its_quotes(self):
        self.write(EXPORT, 'let pattern = /["()]/\n' + self.export)
        self.assert_rejected("bare regex or unspaced slash requires guard review")

    def test_spaced_division_outside_interpolation_passes(self):
        self.write(EXPORT, "let minutes = seconds / 60\n" + self.export)
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unterminated_comment_or_string_fails_closed(self):
        for prefix in ["/*\n", 'let text = """\n', "let pattern = #/\n"]:
            with self.subTest(prefix=prefix):
                self.write(EXPORT, prefix + self.export)
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
