#!/usr/bin/env bash
set -euo pipefail

STRICT=0
if [[ "${1:-}" == "--strict" ]]; then
  STRICT=1
  shift
fi

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 [--strict] /path/to/DoseTapStudioExport_*[.zip]"
  exit 2
fi

EXPORT_INPUT="$1"
if [[ ! -e "$EXPORT_INPUT" ]]; then
  echo "FAIL: export path not found: $EXPORT_INPUT"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 is required for JSON and CSV audit"
  exit 2
fi

python3 - "$EXPORT_INPUT" "$STRICT" <<'PY'
import csv
import json
import sys
import tempfile
import zipfile
from collections import Counter
from datetime import datetime
from pathlib import Path

export_input = Path(sys.argv[1])
strict = sys.argv[2] == "1"
temp_root = None

required = [
    "events.csv",
    "sessions.csv",
    "inventory.csv",
    "insights_bundle.json",
]

def contains_required_files(path):
    return path.is_dir() and all((path / name).is_file() for name in required)

def find_export_dir(root):
    if contains_required_files(root):
        return root

    candidates = [
        path for path in root.rglob("*")
        if path.is_dir() and path.name != "__MACOSX" and contains_required_files(path)
    ]
    if not candidates:
        return None
    return sorted(candidates, key=lambda path: (len(path.parts), str(path)))[0]

def safe_extract_zip(zip_path, destination):
    destination = destination.resolve()
    with zipfile.ZipFile(zip_path) as archive:
        for member in archive.infolist():
            member_path = (destination / member.filename).resolve()
            if destination != member_path and destination not in member_path.parents:
                print(f"FAIL: zip entry escapes export directory: {member.filename}")
                sys.exit(2)
        archive.extractall(destination)

if export_input.is_dir():
    export_dir = find_export_dir(export_input)
elif export_input.is_file() and zipfile.is_zipfile(export_input):
    temp_root = tempfile.TemporaryDirectory(prefix="dosetap-studio-export-")
    extracted_root = Path(temp_root.name)
    safe_extract_zip(export_input, extracted_root)
    export_dir = find_export_dir(extracted_root)
else:
    print(f"FAIL: export path must be a folder or zip archive: {export_input}")
    sys.exit(2)

if export_dir is None:
    print("FAIL: no Studio export folder with required files found in input")
    sys.exit(2)

missing = [name for name in required if not (export_dir / name).is_file()]
if missing:
    print("FAIL: missing required export files: " + ", ".join(missing))
    sys.exit(2)

issues = []

def issue(priority, message):
    issues.append((priority, message))

def is_blank(value):
    return value is None or (isinstance(value, str) and value.strip() == "")

def truthy(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        normalized = value.strip().lower()
        return normalized not in {"", "0", "false", "none", "no", "off", "nil", "null"}
    return value is not None

def json_dict(value):
    if is_blank(value):
        return {}
    try:
        parsed = json.loads(value)
    except (TypeError, ValueError):
        return {}
    return parsed if isinstance(parsed, dict) else {}

def has_truthy_key(payload, key):
    return key in payload and truthy(payload.get(key))

def has_detail_key(payload, prefix, excluded_keys=None):
    excluded_keys = excluded_keys or set()
    for key, value in payload.items():
        if key in excluded_keys:
            continue
        if key.startswith(prefix) and truthy(value):
            return True
    return False

def expected_morning_raw_fields(payload):
    expected = set()

    if (
        has_truthy_key(payload, "pain.any")
        or has_truthy_key(payload, "headache.any")
        or has_detail_key(payload, "pain.", {"pain.any"})
        or has_detail_key(payload, "headache.", {"headache.any"})
        or has_detail_key(payload, "soreness.")
        or has_detail_key(payload, "stiffness.")
        or has_truthy_key(payload, "sleep.reflux_burden")
        or has_truthy_key(payload, "sleep.restless_legs_burden")
        or has_truthy_key(payload, "wake.bathroom_urgency_burden")
    ):
        expected.add("rawPhysicalSymptomsJson")

    if has_truthy_key(payload, "respiratory.any") or has_detail_key(payload, "respiratory.", {"respiratory.any"}):
        expected.add("rawRespiratorySymptomsJson")

    if has_truthy_key(payload, "sleep_therapy.used") or has_detail_key(payload, "sleep_therapy.", {"sleep_therapy.used"}):
        expected.add("rawSleepTherapyJson")

    if has_truthy_key(payload, "sleep_environment.any") or has_detail_key(payload, "sleep_environment.", {"sleep_environment.any"}):
        expected.add("rawSleepEnvironmentJson")

    if has_truthy_key(payload, "overall.stress") or has_detail_key(payload, "morning.stress."):
        expected.add("rawStressContextJson")

    timing_prefixes = ("night.", "wake.", "dose2.", "day_demand.")
    if any(key.startswith(timing_prefixes) and truthy(value) for key, value in payload.items()):
        expected.add("rawTimingContextJson")

    return expected

def read_csv_rows(name):
    path = export_dir / name
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        return list(reader), reader.fieldnames or []

events, _ = read_csv_rows("events.csv")
sessions_csv, _ = read_csv_rows("sessions.csv")
inventory, _ = read_csv_rows("inventory.csv")

try:
    bundle = json.loads((export_dir / "insights_bundle.json").read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    print(f"FAIL: insights_bundle.json is invalid JSON: {exc}")
    sys.exit(2)

if not isinstance(bundle, dict):
    print("FAIL: insights_bundle.json is not an object")
    sys.exit(2)
sessions_json = bundle.get("sessions")
if not isinstance(sessions_json, list) or any(not isinstance(s, dict) for s in sessions_json):
    print("FAIL: insights_bundle.json sessions is not an array of objects")
    sys.exit(2)

unique_json_dates = {
    session.get("sessionDate")
    for session in sessions_json
    if session.get("sessionDate")
}

schema_version = bundle.get("schemaVersion")
if isinstance(schema_version, bool) or not isinstance(schema_version, int) or schema_version <= 0:
    issue("P1", "Missing or invalid export metadata: schemaVersion must be a positive integer")

missing_metadata = [
    field for field in [
        "exportVersion",
        "appVersion",
        "exportedAtUTC",
        "timeZoneIdentifier",
    ]
    if is_blank(bundle.get(field))
]
if missing_metadata:
    issue("P1", "Missing export metadata fields: " + ", ".join(missing_metadata))

exported_at = bundle.get("exportedAtUTC")
if not is_blank(exported_at):
    try:
        parsed_exported_at = datetime.fromisoformat(str(exported_at).replace("Z", "+00:00"))
        if parsed_exported_at.tzinfo is None:
            issue("P1", "Invalid export metadata: exportedAtUTC must include a timezone")
    except ValueError:
        issue("P1", "Invalid export metadata: exportedAtUTC is not ISO-8601")

local_offset = bundle.get("localOffsetMinutes")
if local_offset is None or isinstance(local_offset, bool) or not isinstance(local_offset, int):
    issue("P2", "Missing or invalid export metadata: localOffsetMinutes should be an integer")

local_marker = "Local snapshot only; provider enrichment was not fetched."
warnings = bundle.get("exportWarnings")
local_only = (schema_version == 2 and isinstance(warnings, list) and all(isinstance(w, str) for w in warnings)
              and local_marker in warnings)
consent_value = bundle.get("consent")
if isinstance(consent_value, dict):
    consent = consent_value
    for field in ["appleHealthEnabled", "appleHealthAvailable", "appleHealthAuthorized", "whoopEnabled", "whoopConnected"]:
        if not isinstance(consent.get(field), bool):
            issue("P1", f"Missing or invalid consent metadata: {field} must be a boolean")
else:
    consent = {}
    if "consent" in bundle or not local_only:
        issue("P1", "Missing or invalid export metadata: consent must be an object unless explicitly local-only")

def consent_flag(field):
    value = consent.get(field)
    return value if isinstance(value, bool) else None

whoop_enabled = consent_flag("whoopEnabled")
whoop_connected = consent_flag("whoopConnected")
health_enabled = consent_flag("appleHealthEnabled")
health_authorized = consent_flag("appleHealthAuthorized")

whoop_fetch = bundle.get("whoopEnrichment")
whoop_fetch_valid = False
if "whoopEnrichment" in bundle:
    try:
        if not isinstance(whoop_fetch, dict):
            raise ValueError("expected an object")
        count_phases = {"sleepRecordCount": "sleepStatus", "eligibleNightCount": "sleepStatus", "recoveryRecordCount": "recoveryStatus"}
        query_keys = ["queryStartUTC", "queryEndUTC"]
        known_keys = {"version", "sleepStatus", "recoveryStatus", "notAttemptedReason", *count_phases, *query_keys}
        if set(whoop_fetch) - known_keys or type(whoop_fetch.get("version")) is not int or whoop_fetch["version"] != 1:
            raise ValueError("unknown fields or version")
        phases = [whoop_fetch.get(key) for key in ["sleepStatus", "recoveryStatus"]]
        if any(phase not in ("not_attempted", "completed", "failed") for phase in phases):
            raise ValueError("unknown or missing fetch status")
        attempted = any(phase != "not_attempted" for phase in phases)
        if phases[0] != "completed" and phases[1] != "not_attempted":
            raise ValueError("recovery requires completed sleep retrieval")
        for key, phase in count_phases.items():
            if key in whoop_fetch and (type(whoop_fetch[key]) is not int or whoop_fetch[key] < 0 or whoop_fetch[phase] != "completed"):
                raise ValueError(f"{key} requires a nonnegative integer and completed retrieval")
        if "eligibleNightCount" in whoop_fetch and "sleepRecordCount" in whoop_fetch and whoop_fetch["eligibleNightCount"] > whoop_fetch["sleepRecordCount"]:
            raise ValueError("eligible nights exceed returned sleep records")
        if attempted or any(key in whoop_fetch for key in query_keys):
            bounds = [datetime.fromisoformat(whoop_fetch[key].replace("Z", "+00:00"))
                      if isinstance(whoop_fetch.get(key), str) else None for key in query_keys]
            if not attempted or any(bound is None or bound.utcoffset() is None or bound.utcoffset().total_seconds() != 0 for bound in bounds) or bounds[0] >= bounds[1]:
                raise ValueError("attempted retrieval requires ordered UTC query bounds")
        if "notAttemptedReason" in whoop_fetch:
            if attempted or whoop_fetch["notAttemptedReason"] not in ("feature_disabled", "preference_disabled", "disconnected", "no_sessions", "invalid_range"):
                raise ValueError("invalid not-attempted reason")
        if local_only and (attempted or any(key in whoop_fetch for key in [*count_phases, *query_keys])):
            raise ValueError("local-only declaration conflicts with WHOOP query evidence")
        whoop_fetch_valid = True
    except (TypeError, ValueError):
        issue("P1", "Invalid whoopEnrichment metadata or conflicting local-only declaration")

health_sessions = 0
whoop_sessions = 0
pre_sleep_sessions = 0
pre_sleep_raw_sessions = 0
morning_sessions = 0
morning_raw_counts = Counter()
morning_expected_raw_counts = Counter()
morning_submission_count = 0
checkin_submission_count = 0
checkin_types = Counter()
fractional_sleep_quality = 0
data_quality_flags = Counter()
exclusion_reasons = Counter()

raw_morning_fields = [
    "rawPhysicalSymptomsJson",
    "rawRespiratorySymptomsJson",
    "rawSleepTherapyJson",
    "rawSleepEnvironmentJson",
    "rawStressContextJson",
    "rawTimingContextJson",
]
morning_raw_sessions = {field: set() for field in raw_morning_fields}
morning_expected_raw_sessions = {field: set() for field in raw_morning_fields}

for session in sessions_json:
    session_date = str(session.get("sessionDate") or "missing")
    source = session.get("sourceAvailability", {})
    if not isinstance(source, dict):
        issue("P1", "Invalid sourceAvailability: expected an object")
        source = {}
    if local_only:
        # Inspect named provider evidence only; notes and questionnaire text are not claims.
        provider_evidence = any(session.get(p) is not None for p in ["healthKit", "whoop"])
        for provider in ["healthKit", "whoop"]:
            if provider in source and source[provider] is not False:
                provider_evidence = True
        provenance = session.get("metricProvenance", {})
        collected = session.get("collectedNight", {})
        if not isinstance(provenance, dict) or not isinstance(collected, dict):
            issue("P1", "Local-only export has invalid provider-evidence containers")
        else:
            if any(not isinstance(v, str) for v in provenance.values()):
                issue("P1", "Local-only export has invalid metric provenance values")
            provider_evidence |= any(isinstance(v, str) and v.lower() in {"healthkit", "whoop"}
                                     for v in provenance.values())
            provider_evidence |= any(collected.get(k) is not None for k in [
                "estimatedSleepAfterDose2Minutes", "sleepAfterDose2CoveredMinutes",
                "sleepAfterDose2IntervalMinutes", "sleepAfterDose2FinalWakeAt", "sleepAfterDose2Source"])
        if provider_evidence:
            issue("P1", "Local-only declaration conflicts with provider data or availability/provenance claims")

    if session.get("healthKit") is not None or source.get("healthKit") is True:
        health_sessions += 1

    if session.get("whoop") is not None or source.get("whoop") is True:
        whoop_sessions += 1

    pre_sleep = session.get("preSleep")
    if pre_sleep is not None:
        pre_sleep_sessions += 1
        if pre_sleep.get("rawAnswersJson"):
            pre_sleep_raw_sessions += 1

    morning = session.get("morning")
    if morning is not None:
        morning_sessions += 1
        value = morning.get("sleepQuality")
        if isinstance(value, float) and value != int(value):
            fractional_sleep_quality += 1
        for field in raw_morning_fields:
            if morning.get(field):
                morning_raw_counts[field] += 1
                morning_raw_sessions[field].add(session_date)

    submissions = session.get("checkInSubmissions") or []
    checkin_submission_count += len(submissions)
    for submission in submissions:
        checkin_type = str(submission.get("checkInType") or "missing")
        checkin_types[checkin_type] += 1
        if checkin_type == "morning":
            morning_submission_count += 1
            for field in expected_morning_raw_fields(json_dict(submission.get("responsesJson"))):
                morning_expected_raw_counts[field] += 1
                morning_expected_raw_sessions[field].add(session_date)

    for flag in session.get("dataQualityFlags") or []:
        data_quality_flags[str(flag)] += 1

    for reason in session.get("exportExclusionReasons") or []:
        exclusion_reasons[str(reason)] += 1

if local_only:
    if any(not is_blank(row.get(key)) for row in sessions_csv
           for key in ["whoop_recovery", "avg_hr", "sleep_efficiency"]):
        issue("P1", "Local-only declaration conflicts with provider values in sessions.csv")
    if (export_dir / "collected_nights.csv").is_file():
        collected_rows, _ = read_csv_rows("collected_nights.csv")
        if any(not is_blank(row.get(key)) for row in collected_rows for key in [
            "estimated_sleep_after_dose2_minutes", "sleep_after_dose2_covered_minutes",
            "sleep_after_dose2_interval_minutes", "sleep_after_dose2_final_wake_at_utc", "sleep_after_dose2_source"]):
            issue("P1", "Local-only declaration conflicts with provider values in collected_nights.csv")

if len(sessions_csv) != len(sessions_json):
    issue(
        "P2",
        f"Session count mismatch: sessions.csv has {len(sessions_csv)} rows, insights bundle has {len(sessions_json)} sessions",
    )

if whoop_sessions > 0 and whoop_fetch_valid and (whoop_fetch["sleepStatus"] != "completed" or whoop_fetch.get("eligibleNightCount") == 0):
    issue("P1", "WHOOP summaries conflict with fetch status or zero eligible nights")
if whoop_enabled or whoop_connected:
    if whoop_sessions == 0:
        explained_absence = whoop_fetch_valid and (whoop_fetch["sleepStatus"] != "completed" or whoop_fetch.get("eligibleNightCount") == 0)
        issue("P2" if explained_absence else "P0", "WHOOP is enabled or connected but no WHOOP session summaries are present"
              + ("; validated fetch metadata explains the absence" if explained_absence else ""))

if len(inventory) == 0:
    issue("P2", "inventory.csv is header-only; save a Medication Supply snapshot before expecting inventory rows")

if pre_sleep_sessions and pre_sleep_raw_sessions != pre_sleep_sessions:
    issue(
        "P1",
        f"Pre-sleep raw payload coverage is incomplete: {pre_sleep_raw_sessions}/{pre_sleep_sessions}",
    )

if morning_sessions:
    if morning_submission_count == 0:
        missing_raw_fields = [
            field for field in raw_morning_fields
            if morning_raw_counts[field] == 0
        ]
    else:
        missing_raw_fields = []
        for field in raw_morning_fields:
            expected_sessions = morning_expected_raw_sessions[field]
            if not expected_sessions:
                continue
            present_required_sessions = morning_raw_sessions[field].intersection(expected_sessions)
            missing_sessions = sorted(expected_sessions.difference(morning_raw_sessions[field]))
            if missing_sessions:
                sample = ", ".join(missing_sessions[:5])
                if len(missing_sessions) > 5:
                    sample += f", +{len(missing_sessions) - 5} more"
                missing_raw_fields.append(
                    f"{field} {len(present_required_sessions)}/{len(expected_sessions)} missing {sample}"
                )
    if missing_raw_fields:
        if morning_submission_count == 0:
            issue("P1", "Morning raw payload fields missing from every session: " + ", ".join(missing_raw_fields))
        else:
            issue(
                "P1",
                "Morning raw payload coverage is incomplete for required normalized answers: "
                + "; ".join(missing_raw_fields),
            )

if (pre_sleep_sessions or morning_sessions) and checkin_submission_count == 0:
    issue("P1", "No normalized check-in submissions are present despite pre-sleep or morning data")

print("DoseTap Studio export audit")
print(f"Input: {export_input}")
print(f"Resolved folder: {export_dir}")
print("")
print("Files")
for name in required:
    path = export_dir / name
    print(f"- {name}: {path.stat().st_size} bytes")

print("")
print("Metadata")
print(f"- schemaVersion: {bundle.get('schemaVersion', 'missing')}")
print(f"- exportVersion: {bundle.get('exportVersion', 'missing')}")
print(f"- appVersion: {bundle.get('appVersion', 'missing')}")
print(f"- exportedAtUTC: {bundle.get('exportedAtUTC', 'missing')}")
print(f"- timeZoneIdentifier: {bundle.get('timeZoneIdentifier', 'missing')}")
print(f"- localOffsetMinutes: {bundle.get('localOffsetMinutes', 'missing')}")
if local_only and "consent" not in bundle:
    print("- Provider consent: not captured (declared local-only export)")
else:
    print(f"- Apple Health enabled/authorized: {health_enabled}/{health_authorized}")
    print(f"- WHOOP enabled/connected: {whoop_enabled}/{whoop_connected}")

print("")
print("Counts")
print(f"- events.csv rows: {len(events)}")
print(f"- sessions.csv rows: {len(sessions_csv)}")
print(f"- inventory.csv rows: {len(inventory)}")
print(f"- bundle sessions: {len(sessions_json)}")
print(f"- unique bundle session dates: {len(unique_json_dates)}")
print(f"- Apple Health sessions: {health_sessions}")
print(f"- WHOOP sessions: {whoop_sessions}")
print(f"- pre-sleep sessions: {pre_sleep_sessions}")
print(f"- pre-sleep raw payload sessions: {pre_sleep_raw_sessions}")
print(f"- morning sessions: {morning_sessions}")
print(f"- normalized check-in submissions: {checkin_submission_count}")
print(f"- fractional morning sleep quality sessions: {fractional_sleep_quality}")

if checkin_types:
    print("")
    print("Check-in Types")
    for key, count in sorted(checkin_types.items()):
        print(f"- {key}: {count}")

if morning_raw_counts:
    print("")
    print("Morning Raw Payload Coverage")
    for field in raw_morning_fields:
        print(f"- {field}: {morning_raw_counts[field]}")

if any(morning_expected_raw_sessions[field] for field in raw_morning_fields):
    print("")
    print("Morning Raw Payload Required By Normalized Answers")
    for field in raw_morning_fields:
        expected_sessions = morning_expected_raw_sessions[field]
        if expected_sessions:
            present_required_sessions = morning_raw_sessions[field].intersection(expected_sessions)
            print(
                f"- {field}: {len(present_required_sessions)}/{len(expected_sessions)} required sessions "
                f"({morning_expected_raw_counts[field]} submissions)"
            )
        else:
            print(f"- {field}: 0 required sessions")

if data_quality_flags:
    print("")
    print("Data Quality Flags")
    for key, count in data_quality_flags.most_common():
        print(f"- {key}: {count}")

if exclusion_reasons:
    print("")
    print("Export Exclusion Reasons")
    for key, count in exclusion_reasons.most_common():
        print(f"- {key}: {count}")

print("")
if issues:
    print("Issues")
    for priority, message in issues:
        print(f"- [{priority}] {message}")
else:
    print("Issues")
    print("- None detected by export audit")

if strict and any(priority in {"P0", "P1"} for priority, _ in issues):
    sys.exit(1)

sys.exit(0)
PY
