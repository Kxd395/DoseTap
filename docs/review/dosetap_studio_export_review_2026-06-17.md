# DoseTap Studio Export Review - 2026-06-17

Reviewed export folder:

`/Users/VScode_Projects/projects/DoseTap/docs/review/DoseTapStudioExport_2026-06-17_210007`

Source export metadata:

- App version: `0.4.12 (14)`
- Schema version: `2`
- Export version: `2.2`
- Exported at: `2026-06-18T01:00:46Z`
- Time zone: `America/New_York`
- Apple Health: available, enabled, and authorized
- WHOOP: enabled and connected

## Findings

### Automated export audit added

Added `tools/audit_studio_export.sh` so generated Studio export folders or ZIP archives can be checked without hand-counting CSV and JSON fields.

Command run:

```bash
tools/audit_studio_export.sh /Users/VScode_Projects/projects/DoseTap/docs/review/DoseTapStudioExport_2026-06-17_210007
```

Result on the supplied export:

- `events.csv`: 288 data rows
- `sessions.csv`: 121 data rows
- `inventory.csv`: 0 data rows
- `insights_bundle.json`: 123 sessions
- Apple Health sessions: 123
- WHOOP sessions: 0
- Pre-sleep sessions: 54
- Pre-sleep raw payload sessions: 0
- Morning sessions: 27
- Normalized check-in submissions: 0

The supplied export is still pre-fix evidence. Regenerate the export from a build containing the current check-in and inventory export changes, then rerun this script.

### P0 - WHOOP is marked connected but no WHOOP session data is present

The export-level consent state says WHOOP is enabled and connected, but the insights bundle has `0` WHOOP-backed sessions. Apple Health is present on all 123 sessions, so this is not a general wearable import absence.

Impact: Studio can imply WHOOP is represented while all WHOOP recovery, sleep, and correlation surfaces are empty or HealthKit-only. This matches the reported symptom that WHOOP looks connected but does not display data reliably.

Action taken: Studio import validation now adds a global warning when WHOOP is enabled or connected and the bundle contains no WHOOP summaries.

Follow-up needed: verify the iOS app can fetch and export WHOOP sleep or recovery records after the OAuth refresh fix, then rerun this export path from device.

### P1 - Most sessions are not analysis-ready

The bundle has 123 unique session dates, but 109 sessions carry export exclusion reasons. The largest blockers are missing morning check-ins and missing Dose 2 outcomes.

Impact: recommendations and trend analysis will be biased toward the small subset of complete nights unless Studio clearly separates recorded nights from analysis-ready nights.

### P1 - One session has impossible dose ordering

Session `2026-02-18` is flagged with:

- `Dose 2 event occurs before Dose 1`
- `Impossible negative interval`
- `Session ended before it started`

Impact: this night should be quarantined from timing recommendations and used as a reconciliation case for event ordering.

### P2 - CSV and insights bundle counts intentionally differ, but must remain visible

`sessions.csv` contains 121 data rows. `insights_bundle.json` contains 123 sessions. The two missing CSV rows are the sessions without Dose 1 records:

- `2026-03-02`
- `2026-03-18`

Impact: this is acceptable only if Studio keeps warning on count mismatch. The existing validator already does that.

### P2 - Inventory export is empty

`inventory.csv` contains only the header row.

Impact: inventory-aware analysis is not possible from this export. Either implement inventory export or explicitly label inventory as unavailable in Studio.

Current implementation note: inventory now has an active `inventory_snapshots` source and export guard. This folder will remain header-only until a fresh app export is generated after saving a Medication Supply snapshot.

### P1 - Raw check-in payloads are absent in this export

The automated audit found:

- Pre-sleep raw payload coverage: `0/54`
- Morning raw payload fields present on every raw field: `0`
- Normalized check-in submissions: `0`

Impact: Studio cannot inspect the detailed pre-sleep and morning payloads from this export.

Current implementation note: the iOS exporter now writes `preSleep.rawAnswersJson`, raw morning JSON fields, and `checkInSubmissions`; Studio imports and displays those fields. A focused iOS regression test now seeds SQLite, writes an actual Studio export folder, and verifies those fields in `insights_bundle.json`, `sessions.csv`, and `inventory.csv`. This still needs a regenerated export to verify live device data.

Studio validation now also reports this class of old-export drift directly:

- `Pre-sleep raw payloads missing: X of Y pre-sleep sessions`
- `Morning raw payload fields missing from every session: ...`
- `No normalized check-in submissions were imported despite pre-sleep or morning summaries`

These warnings are covered by `ImportValidatorTests` and protected by `tools/check_checkin_export_fields.sh`.

## Aggregate Counts

- JSON sessions: `123`
- Unique JSON session dates: `123`
- CSV session data rows: `121`
- CSV event data rows: `288`
- HealthKit sessions: `123`
- WHOOP sessions: `0`
- Dose-event sessions: `121`
- Sleep-event sessions: `59`
- Pre-sleep sessions: `54`
- Morning check-in sessions: `27`
- Alarm diagnostic sessions: `79`
- Missing Dose 1 sessions: `2`
- Missing Dose 2 sessions: `57`
- Missing Dose 2 without skip outcome: `37`
- Sessions with export exclusion reasons: `109`

## Event Counts

- `dose1_taken`: `121`
- `dose2_taken`: `66`
- `lights_out`: `57`
- `dose2_skipped`: `18`
- `wake_final`: `17`
- `bathroom`: `4`
- `extra_dose`: `3`
- `water`: `2`

## Data Quality Flags

- `Session marked ok but Dose 2 outcome is missing`: `37`
- `Extreme interval exceeds 360 minutes`: `3`
- `Duplicate lights-out logs`: `2`
- `Dose 2 event occurs before Dose 1`: `1`
- `Duplicate wake-final logs`: `1`
- `Impossible negative interval`: `1`
- `Session ended before it started`: `1`

## Export Exclusion Reasons

- `Missing morning check-in`: `96`
- `Missing Dose 2 outcome`: `37`
- `Session marked ok but Dose 2 outcome is missing`: `37`
- `Dose 2 skipped`: `18`
- `Extreme interval exceeds 360 minutes`: `3`
- `Duplicate lights-out logs`: `2`
- `Dose 2 event occurs before Dose 1`: `1`
- `Duplicate wake-final logs`: `1`
- `Impossible negative interval`: `1`
- `Session ended before it started`: `1`

## Validation Added

Studio now reports:

`WHOOP is enabled or connected but no WHOOP session summaries were imported`

This is a global import warning, not a per-session warning, because the failure is at the integration/export level.

## Regression Coverage Added

- `ExportIntegrityTests.test_studioExport_preservesCheckInPayloadsAndInventoryRows` verifies iOS Studio export writes a complete filesystem package and preserves raw pre-sleep answers, raw morning payloads, normalized check-in submissions, fractional sleep quality, session CSV rows, and active inventory CSV rows.
- `ImportValidatorTests` verifies Studio warns when an imported export is missing raw check-in payloads or normalized check-in submissions.
- `tools/check_checkin_export_fields.sh` and `tools/check_inventory_state_writes.sh` are wired into `tools/release_preflight.sh`.
