#!/usr/bin/env python3
"""Regression tests for the XCTest fixture handoff and unsafe archive rejection."""
import json
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import export_studio_fixtures as fixtures


class FixtureExtractionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.attachments = self.root / "attachments"
        self.attachments.mkdir()
        self.output = self.root / "output"
        self.manifest = []
        for label, name in fixtures.ARCHIVES.items():
            archive = f"{label}.zip"
            with zipfile.ZipFile(self.attachments / archive, "w") as source:
                source.writestr(f"Wrapper-{label}/insights_bundle.json", json.dumps({"label": label}))
                source.writestr(f"Wrapper-{label}/events.csv", "id,timestamp\n")
            self.manifest.append({"attachments": [{"suggestedHumanReadableName": name, "exportedFileName": archive}]})
        self.write_manifest()

    def write_manifest(self):
        (self.attachments / "manifest.json").write_text(json.dumps(self.manifest))

    def assert_rejected(self):
        with self.assertRaises((ValueError, OSError)):
            fixtures.extract(self.attachments, self.output)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob("studio-fixtures-*")))

    def test_real_xctest_names_and_wrapped_payloads_keep_each_archive_identity(self):
        for item in self.manifest:
            attachment = item["attachments"][0]
            attachment["suggestedHumanReadableName"] = attachment["suggestedHumanReadableName"].replace(
                ".zip", "_0_01234567-89AB-CDEF-0123-456789ABCDEF.zip")
        self.write_manifest()
        fixtures.extract(self.attachments, self.output)
        for label in fixtures.ARCHIVES:
            self.assertEqual(json.loads((self.output / label / "insights_bundle.json").read_text()), {"label": label})
            self.assertTrue((self.output / label / "events.csv").is_file())

    def test_missing_or_ambiguous_archive_cannot_silently_skip_roundtrip(self):
        self.manifest.pop()
        self.write_manifest()
        self.assert_rejected()
        self.manifest.append(self.manifest[0])
        self.write_manifest()
        self.assert_rejected()

    def test_attachment_path_cannot_escape_manifest_directory(self):
        (self.root / "outside.zip").write_bytes(b"outside")
        self.manifest[0]["attachments"][0]["exportedFileName"] = "../outside.zip"
        self.write_manifest()
        self.assert_rejected()

    def test_zip_traversal_cannot_write_outside_staging(self):
        with zipfile.ZipFile(self.attachments / "collected.zip", "w") as source:
            source.writestr("../escape", "bad")
        self.assert_rejected()
        self.assertFalse((self.root / "escape").exists())

    def test_zip_symlinks_are_rejected(self):
        link = zipfile.ZipInfo("link")
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(self.attachments / "collected.zip", "w") as source:
            source.writestr(link, "../outside")
        self.assert_rejected()

    def test_expansion_limit_and_existing_output_fail_closed(self):
        with patch.object(fixtures, "MAX_SIZE", 1):
            self.assert_rejected()
        self.output.mkdir()
        marker = self.output / "keep"
        marker.write_text("preserved")
        with self.assertRaises(ValueError):
            fixtures.extract(self.attachments, self.output)
        self.assertEqual(marker.read_text(), "preserved")


if __name__ == "__main__":
    unittest.main()
