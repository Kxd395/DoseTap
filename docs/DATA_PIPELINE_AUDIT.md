# Data Pipeline Audit

Date: 2026-03-08

## Scope

This audit covers the DoseTap local storage and CloudKit sync pipeline for session-scoped data:

- `current_session`
- `sleep_sessions`
- `dose_events`
- `sleep_events`
- `morning_checkins`
- `pre_sleep_logs`
- `checkin_submissions`
- `medication_events`
- `cloudkit_tombstones`

## Current Collection Coverage

The app currently captures and persists these major data groups:

- Sleep events
- Dose events
- Morning check-ins
- Pre-sleep logs
- Medication events

The CloudKit pipeline now uploads and imports:

- Session summary records
- Sleep events
- Dose events
- Morning check-ins
- Pre-sleep logs
- Medication events

## Completed Fixes

### Session discovery

Session discovery now unions all tables that can anchor session-scoped data. This fixes cases where sessions containing only morning check-ins, medication events, or pre-sleep logs were stored locally but omitted from history and sync enumeration.

Primary code:

- `ios/DoseTap/Storage/EventStorage+Session.swift`
- `ios/DoseTap/Storage/EventStorage+Maintenance.swift`

### Medication field persistence

Medication logging now persists derived storage metadata instead of placeholders:

- `dose_unit = "mg"`
- `formulation` derived from `MedicationConfig`
- `local_offset_minutes` derived from the entry timestamp timezone

Primary code:

- `ios/DoseTap/Storage/SessionRepository.swift`

### Pre-sleep and medication sync support

CloudKit storage plumbing now supports import, upsert, delete, and tombstone handling for:

- `DoseTapPreSleepLog`
- `DoseTapMedicationEvent`

Primary code:

- `ios/DoseTap/Storage/EventStorage+CheckIn.swift`
- `ios/DoseTap/Storage/EventStorage+Exports.swift`
- `ios/DoseTap/Storage/EventStorage+Maintenance.swift`
- `ios/DoseTap/Storage/SessionRepository.swift`
- `ios/DoseTap/Views/Dashboard/DashboardModels.swift`

## Validation

Targeted local tests passed for:

- session discoverability
- medication metadata persistence
- pre-sleep sync import
- sync delete cleanup
- storage integrity and cascade behavior

Command used:

```bash
xcodebuild test -project /Volumes/Developer/projects/DoseTap/ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,id=00188B7D-0ECC-41A1-825B-AE23140FED27' -only-testing:DoseTapTests/EventStorageIntegrationTests -only-testing:DoseTapTests/SessionRepositoryTests -only-testing:DoseTapTests/DataIntegrityTests
```

## Remaining Limitations

These items are not fully closed yet:

1. Live CloudKit validation is still pending Apple-side availability and device testing.
2. `checkin_submissions` remains a derived local mirror, not an independently synced source of truth.
3. `sleep_sessions` and `current_session` are still local persistence concepts, not first-class synced records.
4. Dose conflict resolution is still UUID-based rather than logical-event-based, which can still allow duplicate logical doses across devices.
5. Medication capture still treats `dose_unit` as fixed app behavior rather than a user-entered field.

## Recommended Next Steps

1. Run two-device CloudKit validation after capability propagation finishes.
2. Add reconciliation rules for logical dose identity per session.
3. Decide whether `sleep_sessions` and `current_session` should remain local-only or become explicit sync entities.
4. Promote any high-value analytics fields out of JSON blobs into indexed columns where query performance matters.
