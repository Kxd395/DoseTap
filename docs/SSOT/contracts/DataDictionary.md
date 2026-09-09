# DoseTap data dictionary

Status: Current field-meaning contract
Last verified: 2026-09-02
SQLite user_version: 5
DDL source: `ios/DoseTap/Storage/EventStorage+Schema.swift`
Exact column mirror: `docs/DATABASE_SCHEMA.md`

This dictionary defines how persisted fields are interpreted. It covers all 17 application tables plus the internal migration ledger. It does not redefine SQL types or migrations from the executable schema.

## Identity and time

Bounded Apple Health evidence (DOSETAP-56): `SleepEvidenceSample` is an in-memory query snapshot, not a SQLite table or an added export. It retains optional `sampleID`, original `start`/`end`, `rawCategory`, adapter stage and `origin` (source name/bundle/version/product/OS; optional device description/version fields; provider timezone; query `receivedAt`). Device hardware identifiers and arbitrary HealthKit metadata are not copied. Missing fields stay nil. Provider timezone describes the sample's supplied metadata, not an inferred sleep location. The optional Codable model supports round-trip tests but does not itself establish a persistence or public-report contract.

`SleepEvidenceResolution` version `sleep_evidence_consensus_v1` returns the original observations plus clipped slices, supporting sample IDs, conflict minutes, rejected-invalid-sample count and `SleepIntervalCoverage`. Conflict time is included in unmeasured time, not added again to elapsed time. A conflict result can still contain measured nonconflicting portions; it is not a complete-night total. The coverage-only projection omits conflict reasons, so new reporting consumers must use the richer result. Current exports remain unchanged until privacy and consumer integration are implemented.

Apple Health export boundary metadata (DOSETAP-56): optional `observationEndUTC`, `finalWakeBasis` and `derivationVersion` accompany `finalWakeUTC` in the Studio bundle's HealthKit summary. Version `primary_episode_boundary_v2` estimates final wake at the selected primary episode's last asleep end. Basis `observed_sleep_to_awake` means contiguous awake evidence begins there; `last_observed_sleep_end` means that transition was not observed. Observation end is the latest end of the selected primary episode's observations, not a manually reported out-of-bed time or the whole query's endpoint. Older archives omit these fields; Studio retains them as missing. They do not imply treatment-night aggregation, full source provenance or device acceptance. Existing manual final wake remains independent.

### Last food in pre-sleep answers (DOSETAP-50)

`lastFood` is an optional JSON object with `finishedAt` (absolute Date), `kind` (optional `meal`, `snack`, `caloricDrink`), `highFat` (optional Boolean), and `notes` (optional, trimmed, at most 500 characters). No object means unrecorded, not no food. Missing fat means Unsure, never false. New-night carry-forward clears this object and legacy `lateMeal`/`lateMealEndedAt`; editing an existing questionnaire retains them.

Normalized responses are `pre.food.last.finished_at_utc` (ISO 8601), `pre.food.last.kind`, `pre.food.last.high_fat`, and `pre.food.last.notes`. Optional unanswered values are absent. These are additive responses in the existing pre-night questionnaire, not a database migration. Studio exports include the nested object in pre-sleep and session projections; their existing ISO 8601 date encoder applies. Legacy heavy-meal answers cannot establish high-fat content.

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

### Reviewed night window (DOSETAP-56)

`night_outcome.v1` may contain optional `answers.reviewedSleepWindow`; absent remains unanswered. Version 1 stores `sessionID`, absolute `start`/`end`, `reviewedAt`, `source = user_reviewed`, `entryTimeZoneID`, and `startUTCOffsetSeconds`/`endUTCOffsetSeconds` calculated in that entry zone. The zone describes date entry/review, not independently observed travel location. Window identity must match the submission's stable session identity. Ordered finite bounds end no later than review time, and review cannot be later than submission time.

This additive JSON field has no SQLite migration. Existing night-outcome revisions retain prior windows with correction reasons, including removal. Generic submission export includes the JSON and revisions. A window is independent of final awakening, provider samples and measured sleep; unresolved source, overlapping-session and nap conflicts still block future use as a resolved treatment-night range. Older app versions may ignore this new field; downgrade writing is not a supported preservation path.

The collected-night JSON also carries `reviewedSleepWindow`; flat `reviewed_window_*` columns contain version, source, start/end/review UTC timestamps, entry timezone and both offset-seconds values. Missing windows leave these columns empty. Studio retains the nested object on read/write and includes the flat fields in its existing reports; safe reports redact all three timestamps plus entry timezone/offsets. No new field supplies a sleep estimate or replaces final wake.

The additive `reviewedWindowAssessment` projection has `derivationVersion = reviewed_window_assessment_v1`, `status` (`missing`, `checked`, `needsReview`), ordered reason codes and optional absolute `assessedAt`. Flat fields are `reviewed_window_assessment_version`, `reviewed_window_assessment_status`, `reviewed_window_assessment_reasons` (semicolon-separated codes) and `reviewed_window_assessed_at_utc`. Older bundles omit the object; missing is not retrospectively treated as checked. The current export rechecks local bounds from a read snapshot. A saved report retains its assessment time and is not current after source corrections. Studio's existing timestamp redaction applies. This is not persisted in the nightly answer or a new schema migration.

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

## Local supply state (schema version 5)

`supply_state` contains one row (`id INTEGER PRIMARY KEY CHECK (id = 1)`, `payload TEXT NOT NULL`). The versioned SupplyBackup JSON owns optional reminder source and correction history, plus independent bottle-start IDs, opened-at and recorded-at timestamps. Reminder dates preserve Gregorian year/month/day and local hour/minute, mode, lead days, current-device-wall-clock policy, entry timezone, enabled and handled state. Received-date mode adds 21 calendar days. No quantity is inferred from bottle starts. A single upsert commits the complete supply document; load/validation/write errors are surfaced. Reminder-only deletion preserves bottle starts and all medication data. Supply export/restore includes both reminder and bottle records; Clear All Data clears the row. The additive table does not rewrite existing medication records.
