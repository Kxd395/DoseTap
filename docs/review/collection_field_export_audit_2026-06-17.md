# Collection Field and Export Audit - 2026-06-17

## Scope

Reviewed the collection path for the active nightly data surfaces:

- Dose and sleep events
- Pre-sleep check
- Morning check-in
- Medication entries
- Apple Health and WHOOP enrichment
- Studio export files: `events.csv`, `sessions.csv`, `inventory.csv`, `insights_bundle.json`

Also checked the supplied export folder:
`/Users/VScode_Projects/projects/DoseTap/docs/review/DoseTapStudioExport_2026-06-17_210007`

## Verdict

The app was collecting and storing more check-in data than Studio export preserved.

The main gap was not the UI collection path. It was the export schema. Pre-sleep and morning check-ins both write full structured payloads into storage, but Studio export only carried selected summary fields. Any newer detailed fields, such as pain entries, stress progression, timing context, therapy context, and fractional wake score details, could be silently unavailable to Studio analysis.

## Export Evidence From Existing Folder

The supplied export is pre-fix evidence:

- `insights_bundle.json` has 123 sessions.
- The first session has a `preSleep` summary, but not full raw pre-sleep answers.
- `checkInSubmissions` is missing from the session payload.
- `inventory.csv` has 1 line, meaning it is header-only.
- `events.csv` has 289 lines.
- `sessions.csv` has 122 lines.

That export should be regenerated from a build containing this fix before using it as proof that the field chain is complete.

## Field Chain

| Surface | Collection | Store | Export status after this change |
| --- | --- | --- | --- |
| Dose events | Dose action paths | `dose_events`, `sleep_sessions` projections | Present in `events.csv`, `sessions.csv`, and bundle events |
| Sleep events | Sleep event logging | `sleep_events` | Present in `events.csv` and bundle events |
| Pre-sleep summary | `PreSleepLogAnswers` | `pre_sleep_logs.answers_json` | Summary still present, full raw answers now exported as `preSleep.rawAnswersJson` |
| Pre-sleep normalized answers | Pre-sleep response mapper | `checkin_submissions.responses_json` | Now exported in `checkInSubmissions` |
| Morning core fields | Morning check-in model | `morning_checkins` core columns | Present in `morning` summary |
| Morning symptom, respiratory, therapy, environment, stress, and timing details | Morning check-in sections | `morning_checkins.*_json` columns | Raw JSON blobs now exported on `morning` |
| Morning normalized answers | Morning response mapper | `checkin_submissions.responses_json` | Now exported in `checkInSubmissions` |
| Medication entries | Medication logging/settings | medication event store | Present in bundle `medications` |
| Apple Health | Export enrichment query | Not app-owned persisted data in this path | Present in bundle `healthKit` when available and authorized |
| WHOOP | Export enrichment query | Not app-owned persisted data in this path | Present in bundle `whoop` when connected and data is returned |
| Inventory | Medication supply settings | `inventory_snapshots` | Present in `inventory.csv` once the user saves a supply snapshot |

## Fixed

- Added `SessionRepository.fetchCheckInSubmissions(for:)` so export reads normalized pre-sleep and morning submissions through the repository boundary.
- Added full `checkInSubmissions` to each exported bundle session.
- Added `preSleep.rawAnswersJson` so every current and future `PreSleepLogAnswers` field can survive export.
- Added raw morning JSON fields for physical symptoms, respiratory symptoms, sleep therapy, sleep environment, stress context, and timing context.
- Changed Studio morning sleep quality from `Int` to `Double` so 4.25 and 4.5 scores import without failure or rounding.
- Updated Studio recommendation, correlation, report, and CSV paths to keep decimal sleep quality values.
- Added a Studio importer regression test for fractional sleep quality plus raw check-in payloads.
- Added an active SQLite `inventory_snapshots` source, a Medication Supply settings section, and Studio export rows for saved snapshots.
- Added a Studio raw check-in payload section so preserved raw fields are visible and selectable.
- Added `tools/check_inventory_state_writes.sh` to prevent inventory split-brain regressions across settings, storage, and Studio export.
- Added `tools/check_checkin_export_fields.sh` and wired both export guards into release preflight.
- Added `tools/audit_studio_export.sh` to validate generated Studio export folders or ZIP archives and summarize missing payloads, WHOOP coverage, inventory rows, and count drift.
- Added `tools/check_studio_export_audit.sh` and wired it into release preflight so folder input, ZIP input, and ZIP path-traversal rejection stay covered.
- Added strict export metadata validation for schema version, export version, app version, export timestamp, time zone, local offset, and consent provenance.
- Added Studio import validation warnings and regression tests for missing raw check-in payloads and missing normalized check-in submissions.
- Added an iOS export regression test that seeds dose events, pre-sleep, morning, and inventory rows through SQLite, writes the actual Studio export folder, and verifies raw payloads plus `inventory.csv`, `sessions.csv`, and `insights_bundle.json` content are present.

## Remaining Gaps

- Existing exports remain historical evidence and still show header-only `inventory.csv`.
- A regenerated export from the rebuilt iOS app is still needed to confirm the live user dataset now contains the new keys, WHOOP summaries, and any saved inventory snapshots.
- After regenerating, run `tools/audit_studio_export.sh /path/to/DoseTapStudioExport_*.zip` or `tools/audit_studio_export.sh /path/to/DoseTapStudioExport_*` and compare the result against this review.
- `inventory.csv` will remain header-only until a real supply snapshot exists in the app. It is no longer fabricated from dose events.
