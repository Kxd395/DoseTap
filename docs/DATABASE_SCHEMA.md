# DoseTap Database Schema

Last updated: 2026-06-13
Source of truth: `ios/DoseTap/Storage/EventStorage.swift` (`createTables()` + `migrateDatabase()`).
SQLite user_version: 3

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

#### Event Types (13 total)

Source of truth: `docs/SSOT/constants.json` and `ios/Core/SleepEvent.swift`.

| rawValue | wire format | category | default cooldown seconds |
| --- | --- | --- | --- |
| `bathroom` | `bathroom` | physical | 60 |
| `water` | `water` | physical | 60 |
| `snack` | `snack` | physical | 60 |
| `inBed` | `in_bed` | sleepCycle | 0 |
| `lightsOut` | `lights_out` | sleepCycle | 0 |
| `wakeFinal` | `wake_final` | sleepCycle | 0 |
| `wakeTemp` | `wake_temp` | sleepCycle | 0 |
| `anxiety` | `anxiety` | mental | 0 |
| `dream` | `dream` | mental | 0 |
| `heartRacing` | `heart_racing` | mental | 0 |
| `noise` | `noise` | environment | 0 |
| `temperature` | `temperature` | environment | 0 |
| `pain` | `pain` | environment | 0 |

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

### symptom_events

Durable, non-diagnostic symptom facts for future Body Map Symptom Check-in flows. Questionnaire answers remain context; these rows are the rebuildable symptom event log.

```sql
CREATE TABLE IF NOT EXISTS symptom_events (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    session_date TEXT NOT NULL,
    phase TEXT NOT NULL,
    source TEXT NOT NULL,
    source_record_id TEXT,
    source_entry_key TEXT,
    kind TEXT NOT NULL,
    noticed_at TEXT NOT NULL,
    severity_0_10 INTEGER CHECK (severity_0_10 IS NULL OR severity_0_10 BETWEEN 0 AND 10),
    sleep_disruption INTEGER NOT NULL DEFAULT 0 CHECK (sleep_disruption IN (0, 1)),
    still_present INTEGER NOT NULL DEFAULT 0 CHECK (still_present IN (0, 1)),
    functional_impact TEXT,
    note TEXT,
    schema_version INTEGER NOT NULL DEFAULT 1,
    app_version TEXT NOT NULL,
    created_at TEXT NOT NULL
);
```

### symptom_locations

```sql
CREATE TABLE IF NOT EXISTS symptom_locations (
    id TEXT PRIMARY KEY,
    event_id TEXT NOT NULL,
    body_side TEXT NOT NULL,
    body_region_id TEXT NOT NULL,
    anatomy_layer TEXT NOT NULL,
    precision TEXT NOT NULL,
    confidence TEXT NOT NULL,
    FOREIGN KEY(event_id) REFERENCES symptom_events(id) ON DELETE CASCADE
);
```

### body_map_points

```sql
CREATE TABLE IF NOT EXISTS body_map_points (
    id TEXT PRIMARY KEY,
    location_id TEXT NOT NULL,
    map_id TEXT NOT NULL,
    normalized_x REAL NOT NULL CHECK (normalized_x >= 0.0 AND normalized_x <= 1.0),
    normalized_y REAL NOT NULL CHECK (normalized_y >= 0.0 AND normalized_y <= 1.0),
    zoom_level REAL NOT NULL DEFAULT 1.0 CHECK (zoom_level > 0.0),
    body_view TEXT NOT NULL,
    FOREIGN KEY(location_id) REFERENCES symptom_locations(id) ON DELETE CASCADE
);
```

### symptom_command_log

Idempotency ledger for symptom writes. The same command key must return the originally created event instead of creating a duplicate symptom event.

```sql
CREATE TABLE IF NOT EXISTS symptom_command_log (
    idempotency_key TEXT PRIMARY KEY,
    command_type TEXT NOT NULL,
    source TEXT NOT NULL,
    source_record_id TEXT,
    source_entry_key TEXT,
    session_id TEXT,
    session_date TEXT,
    status TEXT NOT NULL,
    created_event_id TEXT,
    error_code TEXT,
    created_at TEXT NOT NULL,
    completed_at TEXT
);
```

### symptom_summaries

Rebuildable session-level symptom summary derived from `symptom_events`.

```sql
CREATE TABLE IF NOT EXISTS symptom_summaries (
    session_date TEXT PRIMARY KEY,
    session_id TEXT,
    symptom_count INTEGER NOT NULL,
    highest_severity INTEGER,
    sleep_disruption_count INTEGER NOT NULL,
    still_present_count INTEGER NOT NULL,
    summary_hash TEXT NOT NULL,
    rebuilt_at TEXT NOT NULL
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
CREATE INDEX IF NOT EXISTS idx_symptom_events_session_date ON symptom_events(session_date);
CREATE INDEX IF NOT EXISTS idx_symptom_events_session_id ON symptom_events(session_id);
CREATE INDEX IF NOT EXISTS idx_symptom_events_phase_kind ON symptom_events(phase, kind);
CREATE INDEX IF NOT EXISTS idx_symptom_events_source_record ON symptom_events(source, source_record_id);
CREATE INDEX IF NOT EXISTS idx_symptom_locations_event ON symptom_locations(event_id);
CREATE INDEX IF NOT EXISTS idx_body_map_points_location ON body_map_points(location_id);
CREATE INDEX IF NOT EXISTS idx_symptom_command_log_status ON symptom_command_log(status);
CREATE INDEX IF NOT EXISTS idx_symptom_command_log_source_record ON symptom_command_log(source, source_record_id);
```

### schema_migrations

```sql
CREATE TABLE IF NOT EXISTS schema_migrations (
    id TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

## Migration Notes

Migrations are applied in `EventStorage.migrateDatabase()` and include:
- Adding `session_id` to existing tables.
- Adding `terminal_state` to `current_session`.
- Adding medication columns (`dose_unit`, `formulation`, `local_offset_minutes`).
- Adding native symptom event tables, child location/point tables, idempotency command log, and rebuildable summaries.
- Adding `source_record_id` and `source_entry_key` to symptom events and command logs so derived rows from editable check-ins can be replaced by source record instead of duplicated.
- Checking existing columns before additive `ALTER TABLE` statements so already-migrated databases do not rely on duplicate-column failures.
- Applying one-time data migrations through the SQLite `schema_migrations` ledger.
