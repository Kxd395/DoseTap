# DoseTap data dictionary

Status: Current field-meaning contract
Last verified: 2026-09-02
SQLite user_version: 5
DDL source: `ios/DoseTap/Storage/EventStorage+Schema.swift`
Exact column mirror: `docs/DATABASE_SCHEMA.md`

This dictionary defines how persisted fields are interpreted. It covers all 17 application tables plus the internal migration ledger. It does not redefine SQL types or migrations from the executable schema.

## Identity and time

WHOOP fetch evidence (Studio export 2.7/schema 2; DOSETAP-13): optional root
`whoopEnrichment` contains `version: 1`, `sleepStatus`, `recoveryStatus`, optional
`queryStartUTC`/`queryEndUTC`, `sleepRecordCount`, `recoveryRecordCount`,
`eligibleNightCount`, and `notAttemptedReason`. Status values are `not_attempted`,
`completed`, or `failed`; consumers retain future strings without treating them
as success. Completed counts can be zero; failed/not-attempted counts are absent.
Eligible count follows the existing scored non-nap filter and precedes per-date
export selection. These are request counts, not measurement denominators or proof
of permissions, complete provider coverage, or per-night availability. Reasons:
`feature_disabled`, `preference_disabled`, `disconnected`, `no_sessions`,
`invalid_range`. Successful sleep with failed recovery retains sleep data and
has absent recovery count. Sleep failure leaves recovery not attempted. Cancellation
produces no successful export. Old/local archives omit this field; existing local
warnings identify the no-fetch mode. Strict archive validation rejects malformed
fetch metadata and local-only declarations combined with attempted WHOOP fetches
or returned-query evidence. Validated failed/not-attempted fetches or completed
fetches with zero eligible nights explain absent WHOOP summaries as advisory;
positive eligible counts without exported summaries remain a strict audit failure.
SQLite and existing numeric data are unchanged.

Apple Health summary missingness (Studio export 2.6, schema 2; DOSETAP-13/56):
`healthKit.totalSleepMinutes` and `wakeCount` are optional. A biometrics-only
Health object does not establish sleep coverage. Without an eligible primary
sleep summary, its sleep/stage/awake/WASO/in-bed numeric fields are absent rather
than zero; received intervals/source names and independent bedtime evidence are
retained. Present primary-episode zero values stay numeric. Matching Studio
preserves missing facts and denominators, including mixed Health/WHOOP archives
under the existing Health-object preference. Raw WHOOP values remain separate.
Old numeric archives, including historical zeros, are not reinterpreted. Older
Studio versions with required total/count fields cannot decode new omissions.
This is an export/import correction; local SQLite and query selection are unchanged.

Local Studio archive metadata (DOSETAP-13 / DC-12): the local/scheduled writer
omits `consent` because it does not capture provider consent or fetch enrichment.
Its `exportWarnings` string array includes the exact element
`Local snapshot only; provider enrichment was not fetched.` The strict validator
accepts this omission only for known schema version 2 with a sessions array and
without contradictory structured provider evidence. Unknown layouts cannot use
the exception because their provider fields have not been validated.
Explicit `null` or another malformed consent value is invalid. Manual/provider
archives require a consent object with five boolean provider-state fields. Missing
local consent remains **not captured**; it does not establish false authorization
or disabled provider settings. Required export metadata and raw-questionnaire
coverage apply in both modes. This is a validator correction for the existing
archive format, not an app/schema change.

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

## Morning physical-symptom selection (DOSETAP-67/61)

`morning_checkins.has_physical_symptoms` and the legacy normalized key `pain.any` indicate that the physical-symptom section was selected. They are not proof of a localized pain entry. Headache, reflux, stiffness, soreness, restlessness and bathroom urgency may be saved without one. `painEntries` remains the source for separate localized entries; an empty array adds no derived localized symptom event.

For newly saved or explicitly edited answers, `physicalSymptomsJson.hasHeadache = false` omits `headacheSeverity`, `headacheLocation` and `isMigraine`. Normalized `headache.any` retains the explicit false; severity/location keys are absent. No localized entries means `painType` and `painSeverity` are absent, not default aching or a fabricated intensity. Unrelated payload fields remain intact. The current derived burden ignores disabled headache/physical branches; its existing scale is unchanged and is not a clinical score.

This changes optional payload content, not table layout. No migration rewrites existing rows or reinterprets old defaults. An explicit History correction still retains prior answers through the existing provenance path. Raw Studio exports carry the saved payload; legacy archived values are not silently repaired on import.

Morning saved pain reuse (DOSETAP-61): `saved_pain_patterns_v1` remains a local preference array with existing area/side keys. Use this morning reviews one preference with a fresh, explicitly chosen 0–10 intensity and blank daily notes. Confirmed values use existing `physicalSymptomsJson.painEntries`, normalized `pain.entries` and source-derived symptom records. Zero intensity is an explicit value and may coexist with selected sensations; an unanswered intensity cannot add a reused entry. There is no new field, SQL migration, retrospective rewrite, template export or scale conversion. Editing or deleting a morning observation does not mutate its source preference or pre-sleep answers.

## Caffeine amount record v1

`PreSleepLogAnswers.caffeineAmounts` is additive JSON, not a SQLite table migration. It contains required `version: 1` and `source` (`user_reported`, `label_reported`, `estimated`, `unknown`), plus optional `lastVolumeUSFlOz`, `dailyVolumeUSFlOz`, `lastCaffeineMg`, and `dailyCaffeineMg` numbers. Source applies to all values in the record; label-reported means the user's report, not independently verified label data. Amounts are finite/nonnegative; each answered daily total must be at least its corresponding last amount. Missing and explicit zero differ. No volume/mass conversion is defined.

Normalized answers store this object at `pre.substances.caffeine.amounts`. Legacy raw `caffeineLastAmountMg` and `caffeineDailyTotalMg` retain their original numbers without clamping, total substitution or unit inference. Their normalized keys are `pre.substances.caffeine.legacy.last_amount`, `.daily_total`, and `.unit = unverified`; new writes no longer duplicate them under `_mg` and `_oz` aliases. Explicit Clear can remove the current legacy values through the normal correction flow; merely reading or normalizing does not assign their units.

History text/CSV labels legacy values as unverified and uses the versioned record's separate unit-named fields. Manual/scheduled Studio exports share `caffeineAmounts`, `caffeineLegacyLastAmount`, and `caffeineLegacyDailyTotal`. New exports omit misleading old top-level Mg aliases but preserve raw source answers. Studio reads old archives without converting their Mg-named values and flags unverified legacy units. It flags unsupported/invalid amount records; new saves and History corrections reject them. Older Studio versions ignore the additive record and cannot display its new amounts; use the matching Studio source for review. No historical database rewrite or full-backup compatibility claim is made.

## Morning setup preferences

Morning preferences (`morningCheckIn.savedSettings` in UserDefaults) contain only `sleepTherapyDevice`, `sleepEnvironmentRoomTemp`, `sleepEnvironmentNoiseLevel` and `sleepEnvironmentSleepAid`. Legacy daily-answer keys are ignored on preference load and omitted on the next explicit preference save. Prior-check-in fallback uses the same whitelist. No historical source row or normalized response is migrated. These are reusable choices, not a new assertion of therapy use or this morning's conditions; the corresponding sections remain inactive until selected. Fixed rating/Boolean defaults elsewhere in the morning form remain unchanged and are not newly classified as confirmed or unanswered.

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

Morning `timing_context_json.dose2TakenReason` is optional. From build 47, a new
unanswered reason is omitted; explicit `unsure` remains a recorded answer. Existing
legacy `unsure` values are not bulk rewritten or claimed explicitly chosen. A new
live submission omits reason/notes hidden by a corrected in-window time or changed
outcome; History editing preserves existing annotations.
The exception prompt depends on actual early/late interval classification, not the
reminder target. This change adds no dose-outcome state, timestamp precision or SQL
migration; unknown-time outcomes and consistent recording provenance remain open.

Build 51 checks quick-log commit results, commits first-event session creation and explicit final-wake projections with their occurrence, and preserves failed in-process drafts for explicit retry. General-medication duplicate confirmation reaches `confirmed_duplicate`; a rejected write does not publish success. This changes no columns or historical values.

`medication_events` is a separate general medication log. It does not replace `dose_events` or drive the Dose 1/Dose 2 state machine.

## Sleep events

`sleep_events.event_type` is not constrained to a closed database enum. `SleepEventType` in `ios/Core/SleepEvent.swift` is a 13-case DoseCore compatibility model. The app-level `EventType` normalizer and `UserSettingsManager.allAvailableEvents` support a broader vocabulary, including paired nap start and end values, and retain unknown strings for forward compatibility. The current Quick Log choices are listed in `docs/SSOT/README.md`.

Medication event vocabulary must not be stored in `sleep_events`. Input routes must send medication actions through the medication coordinator and transaction boundary.

## Check-ins and derived symptoms

`pre_sleep_logs` and `morning_checkins` are editable source records. `checkin_submissions` stores normalized question-ID keyed responses and questionnaire versioning for analysis.

Sleeping setup (DOSETAP-70) adds optional JSON records without new SQL columns:

New submissions use `pre_night.v3.2026-09-10` and `morning.v3.2026-09-10`. Existing stored submissions retain their previous questionnaire version until explicitly edited and resubmitted.

| Source / normalized key | Version-1 fields | Meaning |
| --- | --- | --- |
| `pre_sleep_logs.answers_json.sleepingSetup` / `pre.sleeping_setup.v1` | `version`, optional `arrangement`, `sharedSpace`, `pets`, `location` | Planned context for the selected treatment night; labels are the enum strings in `SleepingSetup.swift`. Shared-space detail applies only to other-person/other arrangements. |
| `morning_checkins.sleep_environment_json.sleepingContext` / `sleeping_context.v1` | `version`, optional `plan`, `confirmation`, `actual`, `impact`, `factors` | Snapshot of the displayed plan plus explicitly confirmed actual context. Actual context is never a remembered preference; unknown and unanswered do not mean alone/no disruption. Factors apply only to Helped/Disrupted/Both. |

Occurrence, entry time, session/source identity and correction provenance come from the containing questionnaire record. Clearing an answer omits it; old records remain missing. Source JSON and normalized submission exports carry these records, including the existing Studio raw-payload view. No names, exact locations or free-text companion details are collected. These fields are sensitive sleep context even without direct identifiers and are not added to a safety score. Usual sleeping setup is a separate local preference, excluded from clinical event exports and the full-backup claim.

Symptom rows derived from an editable check-in use `source`, `source_record_id`, and `source_entry_key` so a later edit replaces the earlier derived facts instead of appending stale duplicates. Source save, normalized submission, and derived symptom replacement share one transaction where the current repository contract requires it.

`symptom_summaries` is rebuildable. It is not the source of truth for individual symptom facts.

### Reviewed night window (DOSETAP-56)

`night_outcome.v1` may contain optional `answers.reviewedSleepWindow`; absent remains unanswered. Version 1 stores `sessionID`, absolute `start`/`end`, `reviewedAt`, `source = user_reviewed`, `entryTimeZoneID`, and `startUTCOffsetSeconds`/`endUTCOffsetSeconds` calculated in that entry zone. The zone describes date entry/review, not independently observed travel location. Window identity must match the submission's stable session identity. Ordered finite bounds end no later than review time, and review cannot be later than submission time.

This additive JSON field has no SQLite migration. Existing night-outcome revisions retain prior windows with correction reasons, including removal. Generic submission export includes the JSON and revisions. A window is independent of final awakening, provider samples and measured sleep; unresolved source, overlapping-session and nap conflicts still block future use as a resolved treatment-night range. Older app versions may ignore this new field; downgrade writing is not a supported preservation path.

The collected-night JSON also carries `reviewedSleepWindow`; flat `reviewed_window_*` columns contain version, source, start/end/review UTC timestamps, entry timezone and both offset-seconds values. Missing windows leave these columns empty. Studio retains the nested object on read/write and includes the flat fields in its existing reports; safe reports redact all three timestamps plus entry timezone/offsets. No new field supplies a sleep estimate or replaces final wake.

The additive `reviewedWindowAssessment` projection has `derivationVersion = reviewed_window_assessment_v1`, `status` (`missing`, `checked`, `needsReview`), ordered reason codes and optional absolute `assessedAt`. Flat fields are `reviewed_window_assessment_version`, `reviewed_window_assessment_status`, `reviewed_window_assessment_reasons` (semicolon-separated codes) and `reviewed_window_assessed_at_utc`. Older bundles omit the object; missing is not retrospectively treated as checked. The current export rechecks local bounds from a read snapshot. A saved report retains its assessment time and is not current after source corrections. Studio's existing timestamp redaction applies. This is not persisted in the nightly answer or a new schema migration.

## Dose/sleep event export provenance (DOSETAP-13)

Studio export 2.5 retains schema version 2 and adds `id`, `sourceTable`, nullable
`sessionId`, `sessionDate`, `timestampStoredUTC`, nullable `createdAtStoredUTC`
and nullable `colorHex` to both raw and normalized event JSON. Table plus ID is
row identity; a date may contain multiple session identities. Original event
strings remain in raw JSON; normalization changes vocabulary only. `details`
retains dose metadata or sleep-event notes unchanged; absent source text stays
absent instead of becoming an invented source annotation.

`occurredAtUTC` is the parsed occurrence; `timestampStoredUTC` retains its exact
SQLite text. `createdAtStoredUTC` retains row creation text, not administration
or proven recording time. Explicit `recorded_at_utc` remains separate inside dose
metadata when present. `deviceTime` remains the legacy date alias, not device time.
The CSV keeps `event_type,occurred_at_utc,details,device_time` first, then appends
`id,source_table,session_id,session_date,timestamp_stored_utc,created_at_stored_utc,color_hex`.
CSV empty cells cannot distinguish NULL from empty text. Older bundles lack the
additive provenance. Studio's typed CSV importer still excludes unknown event
strings; the JSON archive retains them. Shared dose reads accept whole-second or
fractional absolute ISO times and order them by instant, so existing rows are not
ignored by History/state checks. Malformed-time and identity guards remain.
No source rows or SQL schema are changed.

## Inventory boundary

Studio export 2.4 appends `id`, `medication_name`, `created_at_stored_utc` and
`source` to the existing six inventory CSV columns. Source is `active_sqlite`;
notes are the stored text, without appended source commentary. Every snapshot
is included without the former 500-row cap. CSV empty cells still cannot prove
NULL versus empty text; this remains a report, not a restorable database image.

The medication JSON preserves stored `doseUnit` and `formulation` and adds
`sessionId`, `sessionDate`, `localOffsetMinutes`, `confirmedDuplicate`,
`takenAtStoredUTC` and `createdAtStoredUTC`. The latter two retain the exact
SQLite text, including fractional precision and legacy creation formatting;
`takenAtUTC` remains the compatible parsed occurrence. Creation is not dose
administration. Nullable creation/confirmation remain absent, not today's time
or an invented negative. Old archives lack these additive fields. No source
rows are rewritten. SQLite/row-decoding failure in either new export projection
prevents archive publication; broader snapshot/read-error coverage is separate.

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

### Dose 1 reminder review metadata (DOSETAP-71)

New confirmed Dose 1 reviews retain `recorded_at_utc`, `source` (registration
surface), and `reminder_interval_minutes` in existing `dose_events.metadata`.
The event timestamp remains the reported occurrence. These additive keys do not
backfill old events or change SQL schema. The alarm service's existing absolute
deadline reconstruction is separate from the usual target preference.

### Dose 1 No alarm preference (build 50)

Dose 1 metadata includes `dose2_reminder_enabled` (Boolean). False records an
explicit No alarm choice and omits `reminder_interval_minutes`; it is not zero
latency or a skipped medication outcome. Older metadata remains unchanged.
The local `dose2_reminder_enabled` usual preference defaults true and changes only
after successful dose persistence when explicitly requested. Alarm-only opt-out
is retained by session UUID in local alarm preferences to prevent History from
recreating reminders; it does not rewrite the original medication metadata.
