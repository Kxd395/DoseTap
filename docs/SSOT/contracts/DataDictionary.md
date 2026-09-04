# DoseTap data dictionary

Status: Current field-meaning contract
Last verified: 2026-09-02
SQLite user_version: 4
DDL source: `ios/DoseTap/Storage/EventStorage+Schema.swift`
Exact column mirror: `docs/DATABASE_SCHEMA.md`

This dictionary defines how persisted fields are interpreted. It covers all 16 application tables plus the internal migration ledger. It does not redefine SQL types or migrations from the executable schema.

## Identity and time

| Field | Meaning |
| --- | --- |
| `id` | Stable row or event identity within its table |
| `session_id` | Stable UUID identity for one treatment-night session; nullable where pre-session or legacy data can exist |
| `session_date` | `YYYY-MM-DD` dosing-night grouping key, normally computed with an 18:00 local rollover; it is not a midnight closure rule |
| absolute timestamp fields | ISO 8601 text representing an instant unless a field-specific contract says otherwise |
| `local_offset_minutes` | UTC offset captured with a record; it does not identify the original named timezone |
| `created_at` | Row creation time; not necessarily the clinical or user action time |

Historical per-event IANA timezone identity is not complete. DOSETAP-37 owns the prospective provenance gap.

## Table inventory

| Table | Record owner and purpose | Canonical identity |
| --- | --- | --- |
| `sleep_events` | User-recorded sleep-cycle, physical, mental, and environment events | `id` |
| `dose_events` | Dose 1, Dose 2, extra-dose, skip, and snooze history | `id` |
| `current_session` | Single-row active-session projection | fixed `id = 1` |
| `sleep_sessions` | Durable session lifecycle metadata | `session_id` |
| `pre_sleep_logs` | Source pre-night questionnaire payload | `id` |
| `morning_checkins` | Source morning assessment payload | `id`, linked to `session_id` |
| `checkin_submissions` | Normalized, questionnaire-versioned responses | `id`; unique source record plus check-in type |
| `medication_events` | Other local medication log entries | `id` |
| `inventory_snapshots` | Point-in-time inventory data used by export and Studio | `id` |
| `symptom_events` | Durable non-diagnostic symptom facts | `id` |
| `symptom_locations` | Structured body location for a symptom event | `id`, parent `event_id` |
| `body_map_points` | Normalized point for a symptom location | `id`, parent `location_id` |
| `symptom_command_log` | Idempotency and result ledger for symptom writes | `idempotency_key` |
| `symptom_summaries` | Rebuildable per-night symptom aggregate | `session_date` |
| `cloudkit_tombstones` | Pending outbound deletion records for the staging sync path | `key` |
| `schema_migrations` | Database-scoped one-time migration ledger | migration `id` |

## Medication records

`dose_events` owns the canonical medication action history for the two-dose treatment flow. `current_session` is a projection used by active UI state and must agree with that history after each committed mutation. The transaction and failure contract is `docs/SSOT/dose-state-persistence.md`.

Common `dose_events.event_type` values include `dose1`, `dose2`, `extra_dose`, `dose2_skipped`, and `snooze`. Metadata may carry registration surface, early/late/extra classification, action correlation, or snooze count. A metadata field is meaningful only when the writing contract defines it; consumers must tolerate missing legacy keys.

`medication_events` is a separate general medication log. It does not replace `dose_events` or drive the Dose 1/Dose 2 state machine.

## Sleep events

`sleep_events.event_type` is not constrained to a closed database enum. `SleepEventType` in `ios/Core/SleepEvent.swift` is a 13-case DoseCore compatibility model. The app-level `EventType` normalizer and `UserSettingsManager.allAvailableEvents` support a broader vocabulary, including paired nap start and end values, and retain unknown strings for forward compatibility. The current Quick Log choices are listed in `docs/SSOT/README.md`.

Medication event vocabulary must not be stored in `sleep_events`. Input routes must send medication actions through the medication coordinator and transaction boundary.

## Check-ins and derived symptoms

`pre_sleep_logs` and `morning_checkins` are editable source records. `checkin_submissions` stores normalized question-ID keyed responses and questionnaire versioning for analysis.

Symptom rows derived from an editable check-in use `source`, `source_record_id`, and `source_entry_key` so a later edit replaces the earlier derived facts instead of appending stale duplicates. Source save, normalized submission, and derived symptom replacement share one transaction where the current repository contract requires it.

`symptom_summaries` is rebuildable. It is not the source of truth for individual symptom facts.

## Inventory boundary

`inventory_snapshots` records a point-in-time local estimate or imported inventory state. The legacy column name `next_refill_date` does not grant DoseTap authority to refill, order, verify eligibility, contact a pharmacy, or report shipment state.

The proposed supply-cycle feature is a local reminder to order before medication runs out. It remains proposed under `docs/MYWAV_DOSETAP/` until implemented and accepted.

## CloudKit boundary

`cloudkit_tombstones` supports delete convergence in the cloud-enabled staging target. The shipping `DoseTap` target remains local-first and has cloud sync disabled. Table presence is not evidence that a record was uploaded, acknowledged, or deleted remotely.

## Delete and restore scope

SQLite is only part of the app-owned data lifecycle. User defaults, sleep-plan data, diagnostics, Keychain credentials, generated files, optional staging CloudKit copies, and external Apple Health or WHOOP provider records have separate ownership and deletion semantics. The current lifecycle inventory and gaps are in `docs/audit/2026-09-01/crud-matrix.md`.

### Medication correction metadata

A replacement event retains `correction.previous_events`, an array of the replaced rows with their original `id`, `event_type`, `timestamp`, `session_date`, `session_id`, raw `metadata`, and `created_at`. `correction.corrected_at_utc` records entry time and `correction.source` identifies the correction surface. Nested earlier correction metadata is preserved. These fields are committed with the replacement, exported in raw event details, and contain medication history; they must not enter diagnostic logs. See the dose-state persistence contract.

## Work/wake schedule (schema 4)

`work_wake_schedule` stores one row (`id = 1`): `payload TEXT NOT NULL` is the versioned WorkWakeSchedule JSON, and `updated_at TEXT NOT NULL` is UTC. Creation is additive and existing medication rows are unchanged. Its payload owns explicit recurring work identity, advisory-mode parameters, timezone, revision, and dated overrides; Typical Week enabled flags are not migrated to work identity. Whole-database backups include this table. Clear All Data clears it; session deletion does not. Schedule load/validation failures are surfaced to the user.
