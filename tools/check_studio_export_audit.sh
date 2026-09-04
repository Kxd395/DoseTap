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

echo "Studio export audit guard passed"
