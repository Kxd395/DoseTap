# Fix Plan — Audit Follow-Up

Date: 2026-01-19
Owner: Audit Follow-Up

## Goals
- Validate runtime issues in Simulator and capture evidence.
- Fix P0 data integrity issues before any release.
- Establish a phased plan with acceptance tests and sequencing.

## Phase 1: Validation (1-2 hours)

### Tasks
- [ ] Run iOS Simulator and launch DoseTap.
- [ ] Reproduce Timeline vs History mismatch (Dose 1/2 + Wake Final).
- [ ] Run CSV export and validate file contents.
- [ ] Capture evidence (screenshots/logs) and update `AUDIT_LOG.md`.

### Acceptance Tests
- Evidence captured for each repro attempt (logs or screenshots).
- `AUDIT_LOG.md` contains commands + outcomes.

## Phase 2: P0 Fixes (Ship Blockers)

### P0-1 Timeline/History Parity (8h) @storage
- **Scope**: Normalize event types and source tables for Timeline vs History.
- **Files**: `ios/DoseTap/SleepStageTimeline.swift`, `ios/DoseTap/Storage/EventStorage.swift`
- **Acceptance Tests**:
  - `test_timeline_summary_reads_dose1_dose2_from_dose_events()`
  - `test_timeline_reads_wake_final_from_sleep_events()`

### P0-2 Session ID Consistency (6h) @storage
- **Scope**: Replace session_date fallback with UUID session_id, migrate existing data.
- **Files**: `ios/DoseTap/Storage/EventStorage.swift`, `ios/DoseTap/Storage/SessionRepository.swift`
- **Acceptance Tests**:
  - `test_session_id_is_uuid_for_all_tables()`

### P0-3 Dose Event Duplication Removal (4h) @storage
- **Scope**: Remove dose logging to `sleep_events` and display dose data from `dose_events`.
- **Files**: `ios/DoseTap/ContentView.swift`
- **Acceptance Tests**:
  - `test_dose_buttons_do_not_write_sleep_events()`

## Phase 3: P1 Fixes (UX Critical)

### P1-1 CSV Export Robustness (4h) @export
- **Scope**: Async export, UI error handling, BOM, deterministic headers.
- **Files**: `ios/DoseTap/SettingsView.swift`, `ios/DoseTap/Storage/EventStorage.swift`
- **Acceptance Tests**:
  - `test_export_failure_shows_error_alert()`
  - `test_export_includes_utf8_bom()`

### P1-2 Event Type Normalization (6h) @validation
- **Scope**: Canonical snake_case types; map display names separately.
- **Files**: `ios/DoseTap/ContentView.swift`, `ios/DoseTap/UserSettingsManager.swift`, `ios/DoseTap/URLRouter.swift`
- **Acceptance Tests**:
  - `test_event_normalization_maps_display_names_to_wire_format()`

### P1-3 FK Constraints (3h) @schema
- **Scope**: Add FK constraints, cascade deletes, migration plan.
- **Files**: `ios/DoseTap/Storage/EventStorage.swift`
- **Acceptance Tests**:
  - `test_session_delete_cascades_events()`

## Phase 4: P2 Fixes (Performance/Maintenance)

### P2-1 Move DB off Main Thread (8h) @async
- **Scope**: Background actor/queue for SQLite and export.
- **Files**: `ios/DoseTap/Storage/EventStorage.swift`, callers
- **Acceptance Tests**:
  - `test_export_runs_off_main_thread()`

### P2-2 Remove CoreData Split (6h) @cleanup
- **Scope**: Remove or archive CoreData exporters/migrators.
- **Files**: `ios/DoseTap/Persistence/*`, `ios/DoseTap/Export/CSVExporter.swift`, `ios/DoseTap/Storage/JSONMigrator.swift`
- **Acceptance Tests**:
  - `test_csv_export_uses_event_storage()`

## Phase 5: Privacy Compliance (1 hour)

### P3-1 Privacy Manifest (1h) @compliance
- **Scope**: Add `PrivacyInfo.xcprivacy` with required reason codes.
- **Files**: `ios/DoseTap/PrivacyInfo.xcprivacy`
- **Acceptance Tests**:
  - `test_privacy_manifest_in_bundle()`

## Sequencing Notes
1. P0-1 and P0-2 first; they unblock data correctness and migrations.
2. P0-3 next; eliminates duplication and prepares normalization.
3. P1 fixes after core data integrity is stable.
4. P2 and P3 can proceed in parallel after P0s.

## Risks
- Session ID migration could orphan existing events; requires careful migration and validation queries.
- Event normalization touches multiple UI surfaces; regression risk for deep links and display names.

## Definition of Done
- All P0 tests passing.
- Timeline/History parity confirmed in Simulator with reproducible evidence.
- CSV export validated with stable schema and error handling.
- Privacy manifest included and reason codes verified.
