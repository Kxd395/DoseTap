#!/usr/bin/env python3
"""Verify the shipped ZIP and Excel bytes against the build-108 synthetic SQLite rows."""
from collections import Counter, defaultdict
import json
from pathlib import Path
import sqlite3
import sys
from xml.etree import ElementTree as XML
from zipfile import ZipFile

from export_studio_fixtures import find_attachment

FIXTURE = Path(__file__).resolve().parents[1] / "ios/DoseTapTests/Fixtures/Build108SyntheticUpgrade.sql"
TABLES = ("daytime_checkins", "daytime_events", "daytime_prompt_state", "nap_diary",
          "work_block_context", "physician_review_records", "dashboard_dose_reviews",
          "dashboard_provider_associations")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def expected_rows():
    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    try:
        db.executescript(FIXTURE.read_text())
        expected = {table: [dict(row) for row in db.execute(f"SELECT * FROM {table}")] for table in TABLES}
        dose_id, = db.execute("SELECT id FROM dose_events").fetchone()
        checkins = [json.loads(row["payload"]) for row in expected["daytime_checkins"]]
        original = next(c for c in checkins if c.get("predecessorID") is None)
        correction = next(c for c in checkins if c.get("predecessorID") == original["revisionID"])
        require(original["response"] == 0 and correction.get("response") is None, "Invalid correction fixture")
        return expected, dose_id
    finally:
        db.close()


def bundle(zip_path):
    with ZipFile(zip_path) as archive:
        names = [n for n in archive.namelist() if Path(n).name == "insights_bundle.json"]
        require(len(names) == 1, f"Expected one insights bundle in {zip_path.name}")
        return json.loads(archive.read(names[0]))


def compare_records(actual, expected):
    for table in TABLES:
        observed = Counter(json.dumps(row, sort_keys=True) for row in actual[table])
        original = Counter(json.dumps(row, sort_keys=True) for row in expected[table])
        require(observed == original, f"Missing, duplicated, or different source row in {table}")


def compare_manual(root, expected):
    require(root["schemaVersion"] == 6 and root["archiveScope"] == "manual_full_local_records"
            and root["independentRecordsIncluded"] is True, "Invalid full manual export scope")
    rows = defaultdict(list)
    for record in root["independentSourceRecords"]:
        table = record["sourceTable"]
        require(table in TABLES, "Unexpected independent collection")
        values = {}
        for name, col in record["columns"].items():
            kind = col["type"]
            require(kind in ("integer", "text"), f"Unexpected storage type in {table}.{name}")
            values[name] = col[kind]
        rows[table].append(values)
    compare_records(rows, expected)


def check_night(root, dose_id):
    groups = root["dateGroups"]
    require([g["sessionDate"] for g in groups] == ["2026-09-20"], "Incorrect treatment-night grouping")
    rows = groups[0]["rawSourceRecords"]
    require(all(r["sourceTable"] not in TABLES for r in rows), "A diary record was attached to a night")
    doses = [r for r in groups[0]["rawEvents"] if r["sourceTable"] == "dose_events"]
    require(len(doses) == 1 and doses[0]["id"] == dose_id, "Ordinary dose changed")
    sessions = [r for r in rows if r["sourceTable"] == "sleep_sessions"]
    require(len(sessions) == 1 and sessions[0]["columns"]["end_utc"] == {"type": "null"},
            "The open source session acquired an end time")


def compare_workbook(path, expected):
    with ZipFile(path) as archive:
        workbook = XML.fromstring(archive.read("xl/workbook.xml"))
        sheet = next(s for s in workbook.findall(".//{*}sheet") if s.get("name") == "Source Fields")
        relation_id = sheet.attrib["{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"]
        rels = XML.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        target = next(r.attrib["Target"] for r in rels if r.get("Id") == relation_id)
        sheet_xml = XML.fromstring(archive.read("xl/" + target))
    by_record = defaultdict(dict)
    for row in sheet_xml.findall(".//{*}row"):
        # The iPhone workbook writer serializes all cells, including blanks, as inline text or numbers.
        cells = ["".join(c.itertext()) for c in row.findall("{*}c")]
        if len(cells) < 12 or cells[1] not in TABLES or cells[2] != "Original typed SQLite row":
            continue
        require(cells[3:6] == ["", "", "Independent of treatment dates"], "Workbook inferred a night")
        parts = cells[7].split("/")
        if len(parts) == 4 and parts[1] == "columns" and parts[3] in ("text", "integer"):
            values = by_record[cells[1], cells[0]]
            require(parts[2] not in values, "Duplicate source column in workbook")
            values[parts[2]] = int(cells[11]) if parts[3] == "integer" else cells[11]
    observed = defaultdict(list)
    for (table, _), columns in by_record.items():
        observed[table].append(columns)
    compare_records(observed, expected)


def verify(attachments):
    manifest = json.loads((attachments / "manifest.json").read_text())
    expected, dose_id = expected_rows()
    manual = bundle(find_attachment(attachments, manifest, "build108-upgrade-manual.zip"))
    scheduled = bundle(find_attachment(attachments, manifest, "build108-upgrade-scheduled.zip"))
    compare_manual(manual, expected)
    check_night(manual, dose_id)
    compare_workbook(find_attachment(attachments, manifest, "build108-upgrade.xlsx"), expected)
    require(scheduled["archiveScope"] == "local_subset" and scheduled["independentRecordsIncluded"] is False
            and "independentSourceRecords" not in scheduled, "Scheduled archive scope changed")
    require(any("independent" in s.lower() and "excludes" in s.lower()
                for s in scheduled["exportWarnings"]), "Scheduled subset disclosure missing")
    check_night(scheduled, dose_id)


if __name__ == "__main__":
    verify(Path(sys.argv[1]).resolve(strict=True))
    print("Build-108 fixture verified: all nine revisions/records across eight collections matched in "
          "manual ZIP and Excel. Scheduled scope, source dose and independent date grouping passed.")
