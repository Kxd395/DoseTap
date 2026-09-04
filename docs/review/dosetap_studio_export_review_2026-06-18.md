# DoseTap Studio Export Review - 2026-06-18

Reviewed export folder:

`/Users/VScode_Projects/projects/DoseTap/docs/review/DoseTapStudioExport_2026-06-18_061140`

Source export metadata:

- App version: `0.4.12 (14)`
- Schema version: `2`
- Export version: `2.2`
- Exported at: `2026-06-18T10:11:57Z`
- Time zone: `America/New_York`
- Local offset minutes: `-240`
- Apple Health: available, enabled, and authorized
- WHOOP: enabled and connected

## Audit Result

Commands run:

```bash
bash tools/audit_studio_export.sh /Users/VScode_Projects/projects/DoseTap/docs/review/DoseTapStudioExport_2026-06-18_061140
bash tools/audit_studio_export.sh --strict /Users/VScode_Projects/projects/DoseTap/docs/review/DoseTapStudioExport_2026-06-18_061140
```

Strict mode failed because the export still has a P0 WHOOP coverage issue and one P1 morning raw payload coverage issue.

## Counts

- `events.csv`: `290` data rows
- `sessions.csv`: `122` data rows
- `inventory.csv`: `0` data rows
- `insights_bundle.json`: `124` sessions
- Unique bundle session dates: `124`
- Apple Health sessions: `124`
- WHOOP sessions: `0`
- Pre-sleep sessions: `54`
- Pre-sleep raw payload sessions: `54`
- Morning sessions: `27`
- Normalized check-in submissions: `82`
- Fractional morning sleep quality sessions: `0`

## Improvements Since 2026-06-17 Export

- Pre-sleep raw payloads improved from `0/54` to `54/54`.
- Normalized check-in submissions improved from `0` to `82`.
- Bundle session count increased from `123` to `124`.
- CSV session rows increased from `121` to `122`.
- Export metadata is present and traceable.

## Findings

### P0 - WHOOP is connected but no WHOOP session summaries export

The export-level consent state says WHOOP is enabled and connected, but the bundle contains `0` WHOOP-backed session summaries.

Impact: Studio can show a connected WHOOP state while all WHOOP recovery, sleep, and correlation analysis is absent. This is still the main unresolved split between app connection state and exported data state.

Next action: trace the iOS export path from WHOOP auth state through local WHOOP sleep/recovery storage into the `whoop` session summary builder. If no local WHOOP records exist, the UI should say connected but no imported sleep/recovery data instead of implying WHOOP was represented in the export.

Action taken after this export review: the iOS exporter now computes the WHOOP fetch window from the earliest start and latest end across all session query ranges, instead of using the first and last elements of a descending session list. It also maps WHOOP sleep start times through the same session rollover key used by the rest of the app, so after-midnight sleep starts attach to the prior night's session. This still requires a fresh device export to verify WHOOP records are now present in `insights_bundle.json`.

### P1 - One required morning physical raw payload is missing

Morning raw payload coverage across `27` morning sessions:

| Field | Raw payload sessions | Required by normalized answers |
| --- | ---: | ---: |
| `rawPhysicalSymptomsJson` | 6 | 7 |
| `rawRespiratorySymptomsJson` | 0 | 0 |
| `rawSleepTherapyJson` | 0 | 0 |
| `rawSleepEnvironmentJson` | 1 | 1 |
| `rawStressContextJson` | 7 | 7 |
| `rawTimingContextJson` | 2 | 2 |

The real gap is `2026-02-18`: one morning submission has normalized `pain.any=true`, but that session has no `rawPhysicalSymptomsJson`.

Impact: Studio can show normalized physical or pain answers for that session, but cannot audit the detailed raw physical payload that produced them.

Respiratory and sleep therapy are not a confirmed issue in this export. Every morning submission answered `respiratory.any=false` and `sleep_therapy.used=false`, so `rawRespiratorySymptomsJson` and `rawSleepTherapyJson` were not required by the normalized answers.

Action taken after this export review: `tools/audit_studio_export.sh` and the DoseTapStudio import validator now check morning raw payload coverage by required session date. A raw family present on one session can no longer mask a missing required raw family on another session.

### P2 - `inventory.csv` is still header-only

`inventory.csv` contains `0` data rows.

Impact: inventory-aware analysis remains unavailable from this export.

Current interpretation: this is expected if no Medication Supply snapshot was saved in the app before export. It should not be fabricated from dose events.

### P2 - CSV and bundle session counts still differ

`sessions.csv` has `122` rows. The bundle has `124` sessions.

Impact: this remains acceptable only if Studio keeps warning on count mismatch and can explain which sessions lack CSV rows.

## Current Status

Fixed in the fresh export:

- Pre-sleep raw payload persistence and export.
- Normalized check-in submission export.
- Export metadata traceability.
- Respiratory and sleep therapy raw payload false positives are suppressed when normalized answers show those optional sections were not used.

Still not fixed:

- The reviewed export still has no WHOOP session data. A code fix has landed for the reversed fetch window and session-key mapping, but the export must be regenerated to verify the data.
- `2026-02-18` is missing `rawPhysicalSymptomsJson` even though its normalized morning answer has `pain.any=true`.
- Inventory export remains empty until a real supply snapshot exists.
