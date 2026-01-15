# DoseTap Database Schema

Last updated: 2026-01-14
Source of truth: `ios/DoseTap/Storage/EventStorage.swift` (`createTables()` + `migrateDatabase()`).

## Tables

### sleep_events

```sql
CREATE TABLE IF NOT EXISTS sleep_events (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    session_date TEXT NOT NULL,
    session_id TEXT,
    color_hex TEXT,
    notes TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### dose_events

```sql
CREATE TABLE IF NOT EXISTS dose_events (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    session_date TEXT NOT NULL,
    session_id TEXT,
    metadata TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### current_session

```sql
CREATE TABLE IF NOT EXISTS current_session (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    dose1_time TEXT,
    dose2_time TEXT,
    snooze_count INTEGER DEFAULT 0,
    dose2_skipped INTEGER DEFAULT 0,
    session_date TEXT NOT NULL,
    session_id TEXT,
    session_start_utc TEXT,
    session_end_utc TEXT,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

Migration adds:
- `terminal_state` TEXT

### sleep_sessions

```sql
CREATE TABLE IF NOT EXISTS sleep_sessions (
    session_id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL,
    start_utc TEXT NOT NULL,
    end_utc TEXT,
    terminal_state TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### pre_sleep_logs

```sql
CREATE TABLE IF NOT EXISTS pre_sleep_logs (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    created_at_utc TEXT NOT NULL,
    local_offset_minutes INTEGER NOT NULL,
    completion_state TEXT NOT NULL DEFAULT 'partial',
    answers_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### morning_checkins

```sql
CREATE TABLE IF NOT EXISTS morning_checkins (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    session_date TEXT NOT NULL,

    sleep_quality INTEGER NOT NULL DEFAULT 3,
    feel_rested TEXT NOT NULL DEFAULT 'moderate',
    grogginess TEXT NOT NULL DEFAULT 'mild',
    sleep_inertia_duration TEXT NOT NULL DEFAULT 'fiveToFifteen',
    dream_recall TEXT NOT NULL DEFAULT 'none',

    has_physical_symptoms INTEGER NOT NULL DEFAULT 0,
    physical_symptoms_json TEXT,

    has_respiratory_symptoms INTEGER NOT NULL DEFAULT 0,
    respiratory_symptoms_json TEXT,

    mental_clarity INTEGER NOT NULL DEFAULT 5,
    mood TEXT NOT NULL DEFAULT 'neutral',
    anxiety_level TEXT NOT NULL DEFAULT 'none',
    readiness_for_day INTEGER NOT NULL DEFAULT 3,

    had_sleep_paralysis INTEGER NOT NULL DEFAULT 0,
    had_hallucinations INTEGER NOT NULL DEFAULT 0,
    had_automatic_behavior INTEGER NOT NULL DEFAULT 0,
    fell_out_of_bed INTEGER NOT NULL DEFAULT 0,
    had_confusion_on_waking INTEGER NOT NULL DEFAULT 0,

    used_sleep_therapy INTEGER NOT NULL DEFAULT 0,
    sleep_therapy_json TEXT,

    has_sleep_environment INTEGER NOT NULL DEFAULT 0,
    sleep_environment_json TEXT,

    notes TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### medication_events

```sql
CREATE TABLE IF NOT EXISTS medication_events (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    session_date TEXT NOT NULL,
    medication_id TEXT NOT NULL,
    dose_mg INTEGER NOT NULL,
    dose_unit TEXT NOT NULL DEFAULT 'mg',
    formulation TEXT NOT NULL DEFAULT 'ir',
    taken_at_utc TEXT NOT NULL,
    local_offset_minutes INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    confirmed_duplicate INTEGER DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

## Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_sleep_events_session ON sleep_events(session_date);
CREATE INDEX IF NOT EXISTS idx_sleep_events_timestamp ON sleep_events(timestamp);
CREATE INDEX IF NOT EXISTS idx_sleep_events_session_type ON sleep_events(session_date, event_type);
CREATE INDEX IF NOT EXISTS idx_sleep_events_session_id ON sleep_events(session_id);
CREATE INDEX IF NOT EXISTS idx_dose_events_session ON dose_events(session_date);
CREATE INDEX IF NOT EXISTS idx_dose_events_session_type ON dose_events(session_date, event_type);
CREATE INDEX IF NOT EXISTS idx_dose_events_session_id ON dose_events(session_id);
CREATE INDEX IF NOT EXISTS idx_morning_checkins_session ON morning_checkins(session_date);
CREATE INDEX IF NOT EXISTS idx_morning_checkins_session_id ON morning_checkins(session_id);
CREATE INDEX IF NOT EXISTS idx_pre_sleep_logs_session_id ON pre_sleep_logs(session_id);
CREATE INDEX IF NOT EXISTS idx_sleep_sessions_date ON sleep_sessions(session_date);
CREATE INDEX IF NOT EXISTS idx_medication_events_session ON medication_events(session_id);
CREATE INDEX IF NOT EXISTS idx_medication_events_session_date ON medication_events(session_date);
CREATE INDEX IF NOT EXISTS idx_medication_events_medication ON medication_events(medication_id);
CREATE INDEX IF NOT EXISTS idx_medication_events_taken_at ON medication_events(taken_at_utc);
```

## Migration Notes

Migrations are applied in `EventStorage.migrateDatabase()` and include:
- Adding `session_id` to existing tables.
- Adding `terminal_state` to `current_session`.
- Adding medication columns (`dose_unit`, `formulation`, `local_offset_minutes`).

