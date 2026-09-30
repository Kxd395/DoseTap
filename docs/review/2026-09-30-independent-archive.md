# Independent roadmap records in manual archives

Status: consumer validation passed; app producer integration and acceptance remain open.
Scope: DOSETAP-45. The explicit manual ZIP/Excel archive gains original typed rows for daytime assessments/events, naps, prompts, physician-review history, work context and dashboard review/association metadata. No new clinical summary is inferred from these rows.

- Schema 6 requires `archiveScope=manual_full_local_records`, `independentRecordsIncluded=true`, and `independentSourceRecords` (including an empty array when every source read succeeded but no rows exist).
- Rows preserve original identifiers, revision payloads, SQLite types, nulls, zero, text and blobs. A failed source read or invalid identity stops publication.
- Studio imports/re-exports the same rows. Workbook Source Fields displays the originals without creating a nighttime session or treating a revision as another current observation.
- Each payload retains its owning date codec. Daytime assessments/events use Unix seconds; prompts use UTC ISO8601 with millisecond precision; nap, physician-review, work-context and dose-review payloads use Foundation reference-date seconds. The Field Guide states this distinction.
- Provider fingerprints and physician report payloads remain confined to the explicit local full archive. This change does not expand nearby consent or introduce background/provider sharing.
- Scheduled archives retain the existing schema 5 local subset. Their scope metadata, warning and Settings disclosure must state that independent diary/review records require the full manual export.

Scheduled exports therefore remain an incomplete preservation path for the new roadmap records. This existing backup acceptance limitation stays open; neither scheduled archives nor manual reporting archives establish a tested full-app restore. Signed-device export, owner inspection, privacy acceptance and restore acceptance remain separate gates.

Producer activation depends on all eight source-table migrations. Consumer support and the strict source reader can be integrated before activation; the manual export must not be enabled against a checkout missing those tables.

Consumer checkpoint validation (2026-09-30, automated macOS evidence):

- `swift test --jobs 2 --filter StudioWorkbookProjectionTests`: 18 passed; the preceding red run had two expected schema/retention failures.
- `swift build --jobs 2 -q` and `swift test --jobs 2 -q`: build passed; 882 XCTest and 43 Swift tests passed.
- `swift test --package-path macos/DoseTapStudio --jobs 2`: 89 passed, four existing opt-in fixture/native-preview tests skipped, zero failures. The new schema 6 import/re-export test passed.
- `bash tools/check_studio_export_audit.sh`: 208 cases plus ZIP input passed.
- Plane workflow guard, SSOT guard and `git diff --check` passed.

The iOS source-reader tests, integrated manual producer, Settings disclosure, actual archive fixtures and signed-device/manual review require subsequent integration validation. The four skipped Studio tests depend on explicit iOS archive or native-preview inputs and were not silently counted as passes.
