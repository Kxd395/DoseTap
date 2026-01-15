# DoseTap Data Dictionary

Last updated: 2026-01-14
Source of truth: `ios/DoseTap/Storage/EventStorage.swift` (table creation and migrations)

## Session Identity Model

- `session_id`: UUID string. The real session identity.
- `session_date`: grouping key (YYYY-MM-DD) computed by `sessionKey(for:timeZone:rolloverHour:)` with default rollover hour 18 (6 PM). It is not a boundary for session closure.

## Tables

### 1) current_session

Live state for the active session. Single-row table (id = 1).

Columns:
- `id` INTEGER PRIMARY KEY CHECK (id = 1)
- `dose1_time` TEXT (ISO8601)
- `dose2_time` TEXT (ISO8601)
- `snooze_count` INTEGER DEFAULT 0
- `dose2_skipped` INTEGER DEFAULT 0
- `session_date` TEXT NOT NULL
- `session_id` TEXT
- `session_start_utc` TEXT
- `session_end_utc` TEXT
- `terminal_state` TEXT (added via migration)
- `updated_at` TEXT DEFAULT CURRENT_TIMESTAMP

### 2) sleep_sessions

Session metadata with explicit start/end timestamps (non-calendar lifecycle).

Columns:
- `session_id` TEXT PRIMARY KEY
- `session_date` TEXT NOT NULL
- `start_utc` TEXT NOT NULL
- `end_utc` TEXT
- `terminal_state` TEXT
- `created_at` TEXT DEFAULT CURRENT_TIMESTAMP
- `updated_at` TEXT DEFAULT CURRENT_TIMESTAMP

### 3) dose_events

Permanent record of dose actions.

Columns:
- `id` TEXT PRIMARY KEY
- `event_type` TEXT NOT NULL (`dose1`, `dose2`, `extra_dose`, `dose2_skipped`, `snooze`)
- `timestamp` TEXT NOT NULL (ISO8601)
- `session_date` TEXT NOT NULL
- `session_id` TEXT
- `metadata` TEXT (JSON string)
- `created_at` TEXT DEFAULT CURRENT_TIMESTAMP

Metadata keys (when present):
- `is_early` (bool) for early override dose 2
- `is_late` (bool) for late dose 2
- `is_extra_dose` (bool) for extra dose
- `count` (int) for snooze

### 4) sleep_events

User-logged events (local only). Event types are strings passed by the UI.

Columns:
- `id` TEXT PRIMARY KEY
- `event_type` TEXT NOT NULL
- `timestamp` TEXT NOT NULL (ISO8601)
- `session_date` TEXT NOT NULL
- `session_id` TEXT
- `color_hex` TEXT
- `notes` TEXT
- `created_at` TEXT DEFAULT CURRENT_TIMESTAMP

Standard event names from Quick Log (current UI):
- Bathroom
- Water
- Snack
- Nap Start
- Nap End
- Lights Out
- Brief Wake
- In Bed
- Anxiety
- Dream
- Heart Racing
- Noise
- Temperature
- Pain

### 5) morning_checkins

Morning survey responses (one per session). Saved via `SessionRepository.saveMorningCheckIn(...)`.

Columns:
- `id` TEXT PRIMARY KEY
- `session_id` TEXT NOT NULL
- `timestamp` TEXT NOT NULL
- `session_date` TEXT NOT NULL
- `sleep_quality` INTEGER NOT NULL DEFAULT 3
- `feel_rested` TEXT NOT NULL DEFAULT 'moderate'
- `grogginess` TEXT NOT NULL DEFAULT 'mild'
- `sleep_inertia_duration` TEXT NOT NULL DEFAULT 'fiveToFifteen'
- `dream_recall` TEXT NOT NULL DEFAULT 'none'
- `has_physical_symptoms` INTEGER NOT NULL DEFAULT 0
- `physical_symptoms_json` TEXT
- `has_respiratory_symptoms` INTEGER NOT NULL DEFAULT 0
- `respiratory_symptoms_json` TEXT
- `mental_clarity` INTEGER NOT NULL DEFAULT 5
- `mood` TEXT NOT NULL DEFAULT 'neutral'
- `anxiety_level` TEXT NOT NULL DEFAULT 'none'
- `readiness_for_day` INTEGER NOT NULL DEFAULT 3
- `had_sleep_paralysis` INTEGER NOT NULL DEFAULT 0
- `had_hallucinations` INTEGER NOT NULL DEFAULT 0
- `had_automatic_behavior` INTEGER NOT NULL DEFAULT 0
- `fell_out_of_bed` INTEGER NOT NULL DEFAULT 0
- `had_confusion_on_waking` INTEGER NOT NULL DEFAULT 0
- `used_sleep_therapy` INTEGER NOT NULL DEFAULT 0
- `sleep_therapy_json` TEXT
- `has_sleep_environment` INTEGER NOT NULL DEFAULT 0
- `sleep_environment_json` TEXT
- `notes` TEXT

### 6) pre_sleep_logs

Pre-sleep questionnaire responses.

Columns:
- `id` TEXT PRIMARY KEY
- `session_id` TEXT
- `created_at_utc` TEXT NOT NULL
- `local_offset_minutes` INTEGER NOT NULL
- `completion_state` TEXT NOT NULL DEFAULT 'partial'
- `answers_json` TEXT NOT NULL DEFAULT '{}'
- `created_at` TEXT DEFAULT CURRENT_TIMESTAMP

### 7) medication_events

Medication logging entries (local only).

Columns:
- `id` TEXT PRIMARY KEY
- `session_id` TEXT
- `session_date` TEXT NOT NULL
- `medication_id` TEXT NOT NULL
- `dose_mg` INTEGER NOT NULL
- `dose_unit` TEXT NOT NULL DEFAULT 'mg'
- `formulation` TEXT NOT NULL DEFAULT 'ir'
- `taken_at_utc` TEXT NOT NULL
- `local_offset_minutes` INTEGER NOT NULL DEFAULT 0
- `notes` TEXT
- `confirmed_duplicate` INTEGER NOT NULL DEFAULT 0
- `created_at` TEXT DEFAULT CURRENT_TIMESTAMP

