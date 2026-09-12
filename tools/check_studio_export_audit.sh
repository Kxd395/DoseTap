#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f "tools/audit_studio_export.sh" ]]; then
  echo "FAIL: tools/audit_studio_export.sh not found"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 is required for Studio export audit checks"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

EXPORT_DIR="$TMP_DIR/DoseTapStudioExport_Test"
MISSING_METADATA_DIR="$TMP_DIR/DoseTapStudioExport_MissingMetadata"
OPTIONAL_FALSE_DIR="$TMP_DIR/DoseTapStudioExport_OptionalFalseRaw"
MISSING_REQUIRED_RAW_DIR="$TMP_DIR/DoseTapStudioExport_MissingRequiredRaw"
mkdir -p "$EXPORT_DIR"
mkdir -p "$MISSING_METADATA_DIR"
mkdir -p "$OPTIONAL_FALSE_DIR"
mkdir -p "$MISSING_REQUIRED_RAW_DIR"

printf 'event_type,occurred_at_utc,details,device_time\n' > "$EXPORT_DIR/events.csv"
printf 'started_utc,ended_utc,window_target_min,window_actual_min,adherence_flag,whoop_recovery,avg_hr,sleep_efficiency,notes\n2026-06-17T01:15:00.000Z,2026-06-17T04:45:00.000Z,210,210,ok,,,,\n' > "$EXPORT_DIR/sessions.csv"
printf 'as_of_utc,bottles_remaining,doses_remaining,estimated_days_left,next_refill_date,notes\n2026-06-17T11:00:00.000Z,2,28,14,2026-06-30T12:00:00.000Z,source=active_sqlite\n' > "$EXPORT_DIR/inventory.csv"
cp "$EXPORT_DIR"/*.csv "$MISSING_METADATA_DIR"/
cp "$EXPORT_DIR"/*.csv "$OPTIONAL_FALSE_DIR"/
cp "$EXPORT_DIR"/*.csv "$MISSING_REQUIRED_RAW_DIR"/

cat > "$EXPORT_DIR/insights_bundle.json" <<'JSON'
{"schemaVersion":2,"exportVersion":"2.2","appVersion":"0.4.12 (14)","exportedAtUTC":"2026-06-17T10:00:00Z","timeZoneIdentifier":"America/New_York","localOffsetMinutes":-240,"consent":{"appleHealthEnabled":false,"appleHealthAuthorized":false,"whoopEnabled":false,"whoopConnected":false},"sessions":[{"sessionDate":"2026-06-16","preSleep":{"rawAnswersJson":"{}"},"morning":{"sleepQuality":4.25,"rawPhysicalSymptomsJson":"{}","rawRespiratorySymptomsJson":"{}","rawSleepTherapyJson":"{}","rawSleepEnvironmentJson":"{}","rawStressContextJson":"{}","rawTimingContextJson":"{}"},"checkInSubmissions":[{"checkInType":"pre_night"},{"checkInType":"morning"}],"sourceAvailability":{}}]}
JSON

cat > "$MISSING_METADATA_DIR/insights_bundle.json" <<'JSON'
{"schemaVersion":2,"exportVersion":"2.2","exportedAtUTC":"2026-06-17T10:00:00Z","consent":{"appleHealthEnabled":false,"appleHealthAuthorized":false,"whoopEnabled":false,"whoopConnected":false},"sessions":[{"sessionDate":"2026-06-16","preSleep":{"rawAnswersJson":"{}"},"morning":{"sleepQuality":4.25,"rawPhysicalSymptomsJson":"{}","rawRespiratorySymptomsJson":"{}","rawSleepTherapyJson":"{}","rawSleepEnvironmentJson":"{}","rawStressContextJson":"{}","rawTimingContextJson":"{}"},"checkInSubmissions":[{"checkInType":"pre_night"},{"checkInType":"morning"}],"sourceAvailability":{}}]}
JSON

cat > "$OPTIONAL_FALSE_DIR/insights_bundle.json" <<'JSON'
{"schemaVersion":2,"exportVersion":"2.2","appVersion":"0.4.12 (14)","exportedAtUTC":"2026-06-17T10:00:00Z","timeZoneIdentifier":"America/New_York","localOffsetMinutes":-240,"consent":{"appleHealthEnabled":false,"appleHealthAuthorized":false,"whoopEnabled":false,"whoopConnected":false},"sessions":[{"sessionDate":"2026-06-16","morning":{"sleepQuality":3},"checkInSubmissions":[{"checkInType":"morning","responsesJson":"{\"respiratory.any\":false,\"sleep_therapy.used\":false,\"sleep.quality\":3}"}],"sourceAvailability":{}}]}
JSON

cat > "$MISSING_REQUIRED_RAW_DIR/insights_bundle.json" <<'JSON'
{"schemaVersion":2,"exportVersion":"2.2","appVersion":"0.4.12 (14)","exportedAtUTC":"2026-06-17T10:00:00Z","timeZoneIdentifier":"America/New_York","localOffsetMinutes":-240,"consent":{"appleHealthEnabled":false,"appleHealthAuthorized":false,"whoopEnabled":false,"whoopConnected":false},"sessions":[{"sessionDate":"2026-06-16","morning":{"sleepQuality":3,"rawPhysicalSymptomsJson":"{}"},"checkInSubmissions":[{"checkInType":"morning","responsesJson":"{\"pain.any\":true}"}],"sourceAvailability":{}},{"sessionDate":"2026-06-17","morning":{"sleepQuality":3},"checkInSubmissions":[{"checkInType":"morning","responsesJson":"{\"pain.any\":true}"}],"sourceAvailability":{}}]}
JSON

python3 - "$TMP_DIR" <<'PY'
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])

for folder_name in ("DoseTapStudioExport_Test", "DoseTapStudioExport_MissingMetadata", "DoseTapStudioExport_OptionalFalseRaw", "DoseTapStudioExport_MissingRequiredRaw"):
    export_dir = root / folder_name
    with zipfile.ZipFile(root / f"{folder_name}.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for path in export_dir.rglob("*"):
            archive.write(path, path.relative_to(root))

with zipfile.ZipFile(root / "DoseTapStudioExport_Escape.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("../escape.txt", "bad")
PY

bash tools/audit_studio_export.sh "$EXPORT_DIR" >/dev/null
bash tools/audit_studio_export.sh --strict "$TMP_DIR/DoseTapStudioExport_Test.zip" >/dev/null
bash tools/audit_studio_export.sh --strict "$TMP_DIR/DoseTapStudioExport_OptionalFalseRaw.zip" >/dev/null

if bash tools/audit_studio_export.sh --strict "$TMP_DIR/DoseTapStudioExport_MissingRequiredRaw.zip" >/dev/null 2>&1; then
  echo "FAIL: Studio export audit accepted a missing required morning raw payload"
  exit 1
fi

if bash tools/audit_studio_export.sh --strict "$TMP_DIR/DoseTapStudioExport_MissingMetadata.zip" >/dev/null 2>&1; then
  echo "FAIL: Studio export audit accepted missing export metadata in strict mode"
  exit 1
fi

if bash tools/audit_studio_export.sh "$TMP_DIR/DoseTapStudioExport_Escape.zip" >/dev/null 2>&1; then
  echo "FAIL: Studio export audit accepted a zip archive with path traversal"
  exit 1
fi

python3 - "$TMP_DIR" "$ROOT/tools/audit_studio_export.sh" <<'PY'
import copy
import csv
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

root, auditor = Path(sys.argv[1]), sys.argv[2]
base_dir = root / "DoseTapStudioExport_Test"
base = json.loads((base_dir / "insights_bundle.json").read_text())
marker = "Local snapshot only; provider enrichment was not fetched."
local = copy.deepcopy(base)
local.pop("consent")
local["exportWarnings"] = [marker]
local["sessions"][0]["sourceAvailability"] = {"healthKit": False, "whoop": False}
cases = []

def case(name, expected, mutate=lambda value: None, *, seed=local, csv_value=None):
    value = copy.deepcopy(seed)
    mutate(value)
    cases.append((name, expected, value, csv_value))

case("local", 0)
case("ordinary-consent", 0, seed=base)
case("local-note", 0, lambda b: b["sessions"][0].update(notes="WHOOP and Apple Health were discussed"))
case("local-unknown-schema", 1, lambda b: b.update(schemaVersion=999))
case("local-missing-sessions", 2, lambda b: b.pop("sessions"))
case("local-malformed-sessions", 2, lambda b: b.update(sessions={}))
case("missing-marker", 1, lambda b: b.pop("exportWarnings"))
case("marker-substring", 1, lambda b: b.update(exportWarnings=[marker + " maybe"]))
case("marker-string", 1, lambda b: b.update(exportWarnings=marker))
case("marker-array-type", 1, lambda b: b.update(exportWarnings=[marker, {}]))
for value in [None, [], {}, "false", 0, True]:
    case(f"invalid-consent-{len(cases)}", 1, lambda b, v=value: b.update(consent=v))
for key in ["appleHealthEnabled", "appleHealthAuthorized", "whoopEnabled", "whoopConnected"]:
    case(f"missing-{key}", 1, lambda b, k=key: b["consent"].pop(k), seed=base)
    case(f"string-{key}", 1, lambda b, k=key: b["consent"].update({k: "false"}), seed=base)
case("numeric-consent", 1, lambda b: b["consent"].update(appleHealthEnabled=1), seed=base)
for key in ["sourceAvailability", "metricProvenance", "collectedNight"]:
    case(f"malformed-{key}", 1, lambda b, k=key: b["sessions"][0].update({k: []}))
case("malformed-provenance-value", 1, lambda b: b["sessions"][0].update(metricProvenance={"total_sleep_minutes": ["healthkit"]}))
for provider in ["healthKit", "whoop"]:
    case(f"local-{provider}-payload", 1, lambda b, p=provider: b["sessions"][0].update({p: {}}))
    for value in [True, "false", 0, None]:
        case(f"local-{provider}-flag-{len(cases)}", 1,
             lambda b, p=provider, v=value: b["sessions"][0]["sourceAvailability"].update({p: v}))
    case(f"local-{provider}-provenance", 1,
         lambda b, p=provider: b["sessions"][0].update(metricProvenance={"total_sleep_minutes": p.lower()}))
    def enriched(b, p=provider):
        b["sessions"][0][p] = {"totalSleepMinutes": 1}
        keys = ["appleHealthEnabled", "appleHealthAuthorized"] if p == "healthKit" else ["whoopEnabled", "whoopConnected"]
        b["consent"].update({key: True for key in keys})
    case(f"enriched-{provider}", 0, enriched, seed=base)
    case(f"enriched-{provider}-local-marker", 1, lambda b, fn=enriched: (fn(b), b.update(exportWarnings=[marker])), seed=base)
    case(f"enriched-{provider}-missing-consent", 1,
         lambda b, p=provider: (b.pop("consent"), b["sessions"][0].update({p: {}})), seed=base)
for key, value in [("sleepAfterDose2Source", "apple_health_recorded_segments"), ("estimatedSleepAfterDose2Minutes", 0),
                   ("sleepAfterDose2CoveredMinutes", 0), ("sleepAfterDose2IntervalMinutes", 0),
                   ("sleepAfterDose2FinalWakeAt", "2026-06-17T10:00:00Z")]:
    case(f"local-collected-{key}", 1, lambda b, k=key, v=value: b["sessions"][0].update(collectedNight={k: v}))
for column in ["whoop_recovery", "avg_hr", "sleep_efficiency"]:
    case(f"local-csv-{column}", 1, csv_value=("sessions.csv", column, "0"))
for column in ["estimated_sleep_after_dose2_minutes", "sleep_after_dose2_covered_minutes",
               "sleep_after_dose2_interval_minutes", "sleep_after_dose2_final_wake_at_utc", "sleep_after_dose2_source"]:
    case(f"local-csv-{column}", 1, csv_value=("collected_nights.csv", column, "0"))
case("local-missing-metadata", 1, lambda b: b.pop("appVersion"))
case("local-missing-raw", 1, lambda b: (b["sessions"][0]["morning"].pop("rawPhysicalSymptomsJson"),
     b["sessions"][0]["checkInSubmissions"][-1].update(responsesJson='{"pain.any":true}')))

failures = []
for name, expected, value, csv_value in cases:
    folder = root / name
    folder.mkdir()
    for path in base_dir.glob("*.csv"):
        shutil.copyfile(path, folder / path.name)
    (folder / "insights_bundle.json").write_text(json.dumps(value))
    if csv_value:
        path = folder / csv_value[0]
        rows, fields = [{}], [csv_value[1]]
        if path.exists():
            with path.open(newline="") as handle:
                reader = csv.DictReader(handle)
                rows, fields = list(reader), reader.fieldnames
        rows[0][csv_value[1]] = csv_value[2]
        with path.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader(); writer.writerows(rows)
    inputs = [folder]
    if name == "local":
        archive = folder.with_suffix(".zip")
        with zipfile.ZipFile(archive, "w") as output:
            for path in folder.iterdir():
                output.write(path, f"local/{path.name}")
        inputs.append(archive)
    for path in inputs:
        result = subprocess.run(["bash", auditor, "--strict", str(path)], capture_output=True, text=True)
        if result.returncode != expected:
            failures.append(f"{name}: expected {expected}, got {result.returncode}")
        if name == "local" and "Provider consent: not captured" not in result.stdout:
            failures.append("local: missing consent was presented as known state")
if failures:
    raise SystemExit("FAIL: " + "; ".join(failures))
print(f"Local-only consent checks passed: {len(cases)} cases plus ZIP input")
PY

echo "Studio export audit guard passed"
