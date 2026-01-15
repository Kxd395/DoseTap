# DoseTap Schema Evolution

> **Purpose**: Document all SQLite schema migrations and their rationale.
> 
> **Current Schema Version**: 6
> **Canonical Reference**: [DATABASE_SCHEMA.md](../../DATABASE_SCHEMA.md)

## Migration History

### Version 1 → 2 (2024-Q4)
**Change**: Added `dose_events` table
**Rationale**: Initial persistence layer for dose history
**Migration SQL**:
```sql
CREATE TABLE IF NOT EXISTS dose_events (
    id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL,
    event_type TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    metadata TEXT
);
CREATE INDEX IF NOT EXISTS idx_dose_events_session ON dose_events(session_date);
```

### Version 2 → 3 (2024-Q4)
**Change**: Added `sleep_events` table
**Rationale**: Track pre-sleep and nighttime events (bathroom, wake, etc.)
**Migration SQL**:
```sql
CREATE TABLE IF NOT EXISTS sleep_events (
    id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL,
    event_type TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    color_hex TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sleep_events_session ON sleep_events(session_date);
```

### Version 3 → 4 (2024-12)
**Change**: Added `terminal_state` column to `current_session`
**Rationale**: Track how sessions end (completed, skipped, expired, aborted)
**Migration SQL**:
```sql
ALTER TABLE current_session ADD COLUMN terminal_state TEXT;
```

### Version 4 → 5 (2024-12)
**Change**: Added `morning_checkins` table
**Rationale**: Store Morning Check-in questionnaire responses
**Migration SQL**:
```sql
CREATE TABLE IF NOT EXISTS morning_checkins (
    id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL UNIQUE,
    session_id TEXT,
    completed_at TEXT NOT NULL,
    overall_quality INTEGER NOT NULL,
    wake_count INTEGER NOT NULL,
    feeling_rested INTEGER NOT NULL,
    sleep_latency INTEGER,
    notes TEXT,
    sleep_therapy TEXT,
    has_sleep_therapy INTEGER DEFAULT 0,
    sleep_environment_json TEXT,
    has_sleep_environment INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_morning_checkins_session ON morning_checkins(session_date);
```

### Version 5 → 6 (2024-12)
**Change**: Added `pre_sleep_logs` table
**Rationale**: Store Pre-Sleep Log questionnaire responses (caffeine, stress, exercise)
**Migration SQL**:
```sql
CREATE TABLE IF NOT EXISTS pre_sleep_logs (
    id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL UNIQUE,
    completed_at TEXT NOT NULL,
    caffeine_cups INTEGER,
    caffeine_cutoff TEXT,
    alcohol_drinks INTEGER,
    exercise_type TEXT,
    exercise_duration INTEGER,
    stress_level INTEGER,
    notes TEXT
);
CREATE INDEX IF NOT EXISTS idx_pre_sleep_logs_session ON pre_sleep_logs(session_date);
```

## Current Schema (Version 6)

> **5 Tables**: current_session, dose_events, sleep_events, morning_checkins, pre_sleep_logs

### `current_session`
```sql
CREATE TABLE current_session (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    session_date TEXT NOT NULL,
    dose1_time TEXT,
    dose2_time TEXT,
    snooze_count INTEGER NOT NULL DEFAULT 0,
    dose2_skipped INTEGER NOT NULL DEFAULT 0,
    terminal_state TEXT,  -- v4: completed|skipped|expired|aborted|null
    updated_at TEXT
);
```

### `dose_events`
```sql
CREATE TABLE dose_events (
    id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL,
    event_type TEXT NOT NULL,  -- dose_1, dose_2, snooze, skip, extra_dose
    timestamp TEXT NOT NULL,   -- ISO8601
    metadata TEXT
);
CREATE INDEX idx_dose_events_session ON dose_events(session_date);
```

### `sleep_events`
```sql
CREATE TABLE sleep_events (
    id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL,
    event_type TEXT NOT NULL,  -- See constants.json for 13 valid types
    timestamp TEXT NOT NULL,   -- ISO8601
    color_hex TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX idx_sleep_events_session ON sleep_events(session_date);
```

### `morning_checkins`
```sql
CREATE TABLE morning_checkins (
    id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL UNIQUE,
    session_id TEXT,
    completed_at TEXT NOT NULL,
    overall_quality INTEGER NOT NULL,     -- 1-5 scale
    wake_count INTEGER NOT NULL,          -- 0+
    feeling_rested INTEGER NOT NULL,      -- 1-5 scale
    sleep_latency INTEGER,                -- minutes (nullable)
    notes TEXT,
    sleep_therapy TEXT,                   -- JSON array
    has_sleep_therapy INTEGER DEFAULT 0,
    sleep_environment_json TEXT,          -- JSON object
    has_sleep_environment INTEGER DEFAULT 0
);
CREATE INDEX idx_morning_checkins_session ON morning_checkins(session_date);
```

### `pre_sleep_logs`
```sql
CREATE TABLE pre_sleep_logs (
    id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL UNIQUE,
    completed_at TEXT NOT NULL,
    caffeine_cups INTEGER,
    caffeine_cutoff TEXT,
    alcohol_drinks INTEGER,
    exercise_type TEXT,
    exercise_duration INTEGER,
    stress_level INTEGER,
    notes TEXT
);
CREATE INDEX idx_pre_sleep_logs_session ON pre_sleep_logs(session_date);
```

## Migration Strategy

### Additive-Only Policy
DoseTap uses **additive-only migrations**:
- ✅ Add new columns with `ALTER TABLE ... ADD COLUMN`
- ✅ Add new tables
- ✅ Add indexes
- ❌ Never drop columns
- ❌ Never rename columns
- ❌ Never change column types

**Rationale**: SQLite doesn't support `DROP COLUMN` in older versions, and users may downgrade.

### Migration Execution

Migrations run automatically on app launch:

```swift
// ios/DoseTap/Storage/EventStorage.swift

func runMigrations() {
    let currentVersion = getUserVersion()
    
    if currentVersion < 4 {
        // v3 → v4: Add terminal_state
        try? execute("ALTER TABLE current_session ADD COLUMN terminal_state TEXT")
    }
    if currentVersion < 5 {
        // v4 → v5: Add morning_checkins table
        createMorningCheckinsTable()
    }
    if currentVersion < 6 {
        // v5 → v6: Add pre_sleep_logs table
        createPreSleepLogsTable()
    }
    setUserVersion(6)
}
```

### Testing Migrations

Test coverage in `Tests/DoseCoreTests/`:
- Fresh install (empty DB)
- Upgrade from each prior version
- Data integrity after migration

## Event Type Taxonomy

> **Canonical Source**: `docs/SSOT/constants.json`

### Dose Events (`dose_events.event_type`)
| Value | Wire Format | Description |
|-------|-------------|-------------|
| `dose_1` | `dose_1` | First dose taken |
| `dose_2` | `dose_2` | Second dose taken |
| `snooze` | `snooze` | Snooze action |
| `skip` | `skip` | Skip second dose |
| `extra_dose` | `extra_dose` | Additional dose (rare) |

### Sleep Events (`sleep_events.event_type`)
| Swift Enum | Wire Format | Description |
|------------|-------------|-------------|
| `bathroom` | `bathroom` | Bathroom visit |
| `water` | `water` | Drink water |
| `snack` | `snack` | Light snack |
| `inBed` | `in_bed` | Got in bed |
| `lightsOut` | `lights_out` | Lights turned off |
| `wakeFinal` | `wake_final` | Final morning wake |
| `wakeTemp` | `wake_temp` | Temporary night wake |
| `anxiety` | `anxiety` | Anxiety noted |
| `dream` | `dream` | Dream/nightmare |
| `heartRacing` | `heart_racing` | Heart racing |
| `noise` | `noise` | Noise disturbance |
| `temperature` | `temperature` | Too hot/cold |
| `pain` | `pain` | Pain noted |

## Schema Validation

Use `PRAGMA table_info(table_name)` to verify schema:

```sql
-- Verify current_session (8 columns expected)
PRAGMA table_info(current_session);

-- Verify all 5 tables exist
SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;
-- Expected: current_session, dose_events, morning_checkins, pre_sleep_logs, sleep_events
```

## References

- [DATABASE_SCHEMA.md](../../DATABASE_SCHEMA.md) - Complete schema documentation with ERD
- [DataDictionary.md](DataDictionary.md) - Field definitions and constraints
- [constants.json](../constants.json) - Canonical enum definitions
- [SSOT README](../README.md) - Canonical behavior specification
