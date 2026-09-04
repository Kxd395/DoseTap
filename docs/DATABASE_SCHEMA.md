# DoseTap database schema

Status: Current human-readable schema authority
Last verified: 2026-09-02
SQLite user_version: 4
Executable source: `ios/DoseTap/Storage/EventStorage+Schema.swift`
Version constant: `EventStorage.schemaUserVersion` in `ios/DoseTap/Storage/EventStorage.swift`

The executable DDL and migrations remain decisive if this document drifts. `EventStorage` uses system SQLite, enables foreign keys, and requests WAL journal mode when the database opens.

The current schema contains 16 application tables plus the internal `schema_migrations` ledger.

## Session and event tables

### `sleep_events`

| Column | SQLite declaration | Meaning |
| --- | --- | --- |
| `id` | `TEXT PRIMARY KEY` | Event identity |
| `event_type` | `TEXT NOT NULL` | Stored sleep-event value; SQLite does not enforce a closed enum |
| `timestamp` | `TEXT NOT NULL` | Absolute event instant, stored as ISO 8601 text |
| `session_date` | `TEXT NOT NULL` | Dosing-night grouping key |
| `session_id` | `TEXT` | Stable session identity when linked |
| `color_hex` | `TEXT` | Optional presentation color |
| `notes` | `TEXT` | Optional user text |
| `created_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` | Row creation time |

#### Event vocabulary

The table intentionally accepts forward-compatible strings. `SleepEventType` in `ios/Core/SleepEvent.swift` defines a 13-case DoseCore compatibility model, while `EventType` in `ios/DoseTap/EventType.swift` normalizes the broader app vocabulary and preserves unknown values. `UserSettingsManager.allAvailableEvents` defines the current Quick Log customization choices. `docs/SSOT/constants.json` mirrors the DoseCore subset and is not a database constraint.

| Swift case | Stored wire value | Category | Default cooldown seconds |
| --- | --- | --- | --- |
| `bathroom` | `bathroom` | physical | 60 |
| `water` | `water` | physical | 60 |
| `snack` | `snack` | physical | 60 |
| `inBed` | `in_bed` | sleep cycle | 0 |
| `lightsOut` | `lights_out` | sleep cycle | 0 |
| `wakeFinal` | `wake_final` | sleep cycle | 0 |
| `wakeTemp` | `wake_temp` | sleep cycle | 0 |
| `anxiety` | `anxiety` | mental | 0 |
| `dream` | `dream` | mental | 0 |
| `heartRacing` | `heart_racing` | mental | 0 |
| `noise` | `noise` | environment | 0 |
| `temperature` | `temperature` | environment | 0 |
| `pain` | `pain` | environment | 0 |

Nap tracking is represented by paired `nap_start` and `nap_end` event strings. Those values are supported by the app normalizer but are not cases in the DoseCore compatibility enum.

### `dose_events`

| Column | SQLite declaration | Meaning |
| --- | --- | --- |
| `id` | `TEXT PRIMARY KEY` | Medication action identity |
| `event_type` | `TEXT NOT NULL` | Dose 1, Dose 2, extra dose, skip, or snooze action |
| `timestamp` | `TEXT NOT NULL` | Absolute action instant |
| `session_date` | `TEXT NOT NULL` | Dosing-night grouping key |
| `session_id` | `TEXT` | Stable session identity |
| `metadata` | `TEXT` | JSON metadata, including policy and source fields when present |
| `created_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` | Row creation time |
| `is_hazard` | `INTEGER DEFAULT 0` | Added by migration for hazard classification |

### `current_session`

Single-row projection for the active session.

| Column | SQLite declaration |
| --- | --- |
| `id` | `INTEGER PRIMARY KEY CHECK (id = 1)` |
| `dose1_time` | `TEXT` |
| `dose2_time` | `TEXT` |
| `snooze_count` | `INTEGER DEFAULT 0` |
| `dose2_skipped` | `INTEGER DEFAULT 0` |
| `session_date` | `TEXT NOT NULL` |
| `session_id` | `TEXT` |
| `session_start_utc` | `TEXT` |
| `session_end_utc` | `TEXT` |
| `updated_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` |
| `terminal_state` | `TEXT` added by migration |

The transactional consistency rules between this projection and `dose_events` are in `docs/SSOT/dose-state-persistence.md`.

### `sleep_sessions`

| Column | SQLite declaration |
| --- | --- |
| `session_id` | `TEXT PRIMARY KEY` |
| `session_date` | `TEXT NOT NULL` |
| `start_utc` | `TEXT NOT NULL` |
| `end_utc` | `TEXT` |
| `terminal_state` | `TEXT` |
| `created_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` |
| `updated_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` |

## Check-in tables

### `pre_sleep_logs`

| Column | SQLite declaration |
| --- | --- |
| `id` | `TEXT PRIMARY KEY` |
| `session_id` | `TEXT` |
| `created_at_utc` | `TEXT NOT NULL` |
| `local_offset_minutes` | `INTEGER NOT NULL` |
| `completion_state` | `TEXT NOT NULL DEFAULT 'partial'` |
| `answers_json` | `TEXT NOT NULL DEFAULT '{}'` |
| `created_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` |

### `morning_checkins`

| Column | SQLite declaration |
| --- | --- |
| `id` | `TEXT PRIMARY KEY` |
| `session_id` | `TEXT NOT NULL` |
| `timestamp` | `TEXT NOT NULL` |
| `session_date` | `TEXT NOT NULL` |
| `sleep_quality` | `REAL NOT NULL DEFAULT 3` |
| `feel_rested` | `TEXT NOT NULL DEFAULT 'moderate'` |
| `grogginess` | `TEXT NOT NULL DEFAULT 'mild'` |
| `sleep_inertia_duration` | `TEXT NOT NULL DEFAULT 'fiveToFifteen'` |
| `dream_recall` | `TEXT NOT NULL DEFAULT 'none'` |
| `has_physical_symptoms` | `INTEGER NOT NULL DEFAULT 0` |
| `physical_symptoms_json` | `TEXT` |
| `has_respiratory_symptoms` | `INTEGER NOT NULL DEFAULT 0` |
| `respiratory_symptoms_json` | `TEXT` |
| `mental_clarity` | `INTEGER NOT NULL DEFAULT 5` |
| `mood` | `TEXT NOT NULL DEFAULT 'neutral'` |
| `anxiety_level` | `TEXT NOT NULL DEFAULT 'none'` |
| `stress_level` | `INTEGER` |
| `stress_context_json` | `TEXT` |
| `readiness_for_day` | `INTEGER NOT NULL DEFAULT 3` |
| `had_sleep_paralysis` | `INTEGER NOT NULL DEFAULT 0` |
| `had_hallucinations` | `INTEGER NOT NULL DEFAULT 0` |
| `had_automatic_behavior` | `INTEGER NOT NULL DEFAULT 0` |
| `fell_out_of_bed` | `INTEGER NOT NULL DEFAULT 0` |
| `had_confusion_on_waking` | `INTEGER NOT NULL DEFAULT 0` |
| `used_sleep_therapy` | `INTEGER NOT NULL DEFAULT 0` |
| `sleep_therapy_json` | `TEXT` |
| `timing_context_json` | `TEXT` |
| `notes` | `TEXT` |
| `created_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` |

### `checkin_submissions`

Normalized, versioned questionnaire responses.

| Column | SQLite declaration |
| --- | --- |
| `id` | `TEXT PRIMARY KEY` |
| `source_record_id` | `TEXT NOT NULL` |
| `session_id` | `TEXT` |
| `session_date` | `TEXT NOT NULL` |
| `checkin_type` | `TEXT NOT NULL` |
| `questionnaire_version` | `TEXT NOT NULL` |
| `user_id` | `TEXT NOT NULL` |
| `submitted_at_utc` | `TEXT NOT NULL` |
| `local_offset_minutes` | `INTEGER NOT NULL` |
| `responses_json` | `TEXT NOT NULL` |
| `created_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` |

Unique constraint: `UNIQUE(source_record_id, checkin_type)`.

## Medication and inventory tables

### `medication_events`

| Column | SQLite declaration |
| --- | --- |
| `id` | `TEXT PRIMARY KEY` |
| `session_id` | `TEXT` |
| `session_date` | `TEXT NOT NULL` |
| `medication_id` | `TEXT NOT NULL` |
| `dose_mg` | `INTEGER NOT NULL` |
| `dose_unit` | `TEXT NOT NULL DEFAULT 'mg'` |
| `formulation` | `TEXT NOT NULL DEFAULT 'ir'` |
| `taken_at_utc` | `TEXT NOT NULL` |
| `local_offset_minutes` | `INTEGER NOT NULL DEFAULT 0` |
| `notes` | `TEXT` |
| `confirmed_duplicate` | `INTEGER DEFAULT 0` |
| `created_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` |

### `inventory_snapshots`

This is an export and Studio inventory snapshot. Its legacy `next_refill_date` field does not mean DoseTap requests or manages refills.

| Column | SQLite declaration |
| --- | --- |
| `id` | `TEXT PRIMARY KEY` |
| `as_of_utc` | `TEXT NOT NULL` |
| `medication_name` | `TEXT NOT NULL` |
| `bottles_remaining` | `INTEGER NOT NULL DEFAULT 0 CHECK (bottles_remaining >= 0)` |
| `doses_remaining` | `INTEGER NOT NULL DEFAULT 0 CHECK (doses_remaining >= 0)` |
| `estimated_days_left` | `INTEGER` |
| `next_refill_date` | `TEXT` |
| `notes` | `TEXT` |
| `created_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` |

The proposed supply-cycle notification is specified separately under `docs/MYWAV_DOSETAP/`. It is not a refill transaction.

## Symptom tables

### `symptom_events`

| Column | SQLite declaration |
| --- | --- |
| `id` | `TEXT PRIMARY KEY` |
| `session_id` | `TEXT` |
| `session_date` | `TEXT NOT NULL` |
| `phase` | `TEXT NOT NULL` |
| `source` | `TEXT NOT NULL` |
| `source_record_id` | `TEXT` |
| `source_entry_key` | `TEXT` |
| `kind` | `TEXT NOT NULL` |
| `noticed_at` | `TEXT NOT NULL` |
| `severity_0_10` | `INTEGER`, null or 0 through 10 |
| `sleep_disruption` | `INTEGER NOT NULL DEFAULT 0`, constrained to 0 or 1 |
| `still_present` | `INTEGER NOT NULL DEFAULT 0`, constrained to 0 or 1 |
| `functional_impact` | `TEXT` |
| `note` | `TEXT` |
| `schema_version` | `INTEGER NOT NULL DEFAULT 1` |
| `app_version` | `TEXT NOT NULL` |
| `created_at` | `TEXT NOT NULL` |

### `symptom_locations`

| Column | SQLite declaration |
| --- | --- |
| `id` | `TEXT PRIMARY KEY` |
| `event_id` | `TEXT NOT NULL` |
| `body_side` | `TEXT NOT NULL` |
| `body_region_id` | `TEXT NOT NULL` |
| `anatomy_layer` | `TEXT NOT NULL` |
| `precision` | `TEXT NOT NULL` |
| `confidence` | `TEXT NOT NULL` |

Foreign key: `event_id` references `symptom_events(id)` with cascade delete.

### `body_map_points`

| Column | SQLite declaration |
| --- | --- |
| `id` | `TEXT PRIMARY KEY` |
| `location_id` | `TEXT NOT NULL` |
| `map_id` | `TEXT NOT NULL` |
| `normalized_x` | `REAL NOT NULL`, constrained to 0 through 1 |
| `normalized_y` | `REAL NOT NULL`, constrained to 0 through 1 |
| `zoom_level` | `REAL NOT NULL DEFAULT 1.0 CHECK (zoom_level > 0.0)` |
| `body_view` | `TEXT NOT NULL` |

Foreign key: `location_id` references `symptom_locations(id)` with cascade delete.

### `symptom_command_log`

| Column | SQLite declaration |
| --- | --- |
| `idempotency_key` | `TEXT PRIMARY KEY` |
| `command_type` | `TEXT NOT NULL` |
| `source` | `TEXT NOT NULL` |
| `source_record_id` | `TEXT` |
| `source_entry_key` | `TEXT` |
| `session_id` | `TEXT` |
| `session_date` | `TEXT` |
| `status` | `TEXT NOT NULL` |
| `created_event_id` | `TEXT` |
| `error_code` | `TEXT` |
| `created_at` | `TEXT NOT NULL` |
| `completed_at` | `TEXT` |

### `symptom_summaries`

| Column | SQLite declaration |
| --- | --- |
| `session_date` | `TEXT PRIMARY KEY` |
| `session_id` | `TEXT` |
| `symptom_count` | `INTEGER NOT NULL` |
| `highest_severity` | `INTEGER` |
| `sleep_disruption_count` | `INTEGER NOT NULL` |
| `still_present_count` | `INTEGER NOT NULL` |
| `summary_hash` | `TEXT NOT NULL` |
| `rebuilt_at` | `TEXT NOT NULL` |

## Sync and migration tables

### `cloudkit_tombstones`

| Column | SQLite declaration |
| --- | --- |
| `key` | `TEXT PRIMARY KEY` |
| `record_type` | `TEXT NOT NULL` |
| `record_name` | `TEXT NOT NULL` |
| `created_at` | `TEXT NOT NULL` |

This table supports the staging CloudKit path. Its presence does not mean CloudKit is enabled in the shipping `DoseTap` target.

### `schema_migrations`

| Column | SQLite declaration |
| --- | --- |
| `id` | `TEXT PRIMARY KEY` |
| `applied_at` | `TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP` |

This ledger is the sole authority for one-time data migration state. App preferences never skip a missing database migration. Each operation commits atomically with its ledger entry; failure rolls back and remains eligible for retry. Legacy medication rows in sleep_events are removed only when an exact canonical dose event already represents them; unmatched rows remain available for owner review.

## Indexes

Current indexes cover session date, session ID, event type, timestamps, normalized submission type/time, tombstone creation, medication identity/time, inventory snapshot time/medication, and symptom source/parent/status fields. The exact list is the `CREATE INDEX` block in `EventStorage+Schema.swift` and is checked by storage integration tests.

## Migration behavior

Initialization currently:

1. creates missing tables and indexes;
2. adds supported missing columns after checking `PRAGMA table_info`;
3. backfills missing session IDs;
4. normalizes legacy event aliases and removes medication vocabulary from `sleep_events`;
5. converts legacy date-shaped session IDs to deterministic UUIDs;
6. deduplicates legacy sleep and dose rows;
7. records one-time migrations in `schema_migrations`;
8. raises `PRAGMA user_version` to 3.

Named timezone provenance is not yet stored on every historical event row. Existing offset fields and absolute timestamps do not fully replace an IANA timezone identifier. This remains tracked by DOSETAP-37.

## Work/wake schedule (schema 4)

`work_wake_schedule` stores one row (`id = 1`): `payload TEXT NOT NULL` is the versioned WorkWakeSchedule JSON, and `updated_at TEXT NOT NULL` is UTC. Creation is additive and existing medication rows are unchanged. Its payload owns explicit recurring work identity, advisory-mode parameters, timezone, revision, and dated overrides; Typical Week enabled flags are not migrated to work identity. Whole-database backups include this table. Clear All Data clears it; session deletion does not. Schedule load/validation failures are surfaced to the user.
