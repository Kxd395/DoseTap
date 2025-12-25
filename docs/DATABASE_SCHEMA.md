# DoseTap Database Schema

> **CANONICAL**: This is THE authoritative reference for DoseTap's SQLite database schema.
> All tables, columns, relationships, and access patterns are defined here.

**Last Updated:** 2024-12-24  
**Version:** 6  
**Database Engine:** SQLite 3  
**Database File:** `dosetap_events.sqlite` (Documents directory)

---

## Table of Contents

1. [Overview](#overview)
2. [Entity Relationship Diagram](#entity-relationship-diagram)
3. [Tables](#tables)
   - [current_session](#current_session)
   - [dose_events](#dose_events)
   - [sleep_events](#sleep_events)
   - [morning_checkins](#morning_checkins)
   - [pre_sleep_logs](#pre_sleep_logs)
4. [Indexes](#indexes)
5. [JSON Schema Definitions](#json-schema-definitions)
6. [Access Patterns](#access-patterns)
7. [Migration History](#migration-history)
8. [Swift Connectors](#swift-connectors)

---

## Overview

DoseTap uses a local SQLite database for all persistent storage. The architecture follows these principles:

- **Local-first**: All data stored on device, no cloud sync required
- **Session-centric**: Data organized around nightly sleep sessions
- **Privacy-focused**: No PII leaves device without explicit export
- **Export-ready**: All tables designed for clean CSV export

### Session Date Convention

All tables use `session_date` (format: `YYYY-MM-DD`) as the primary grouping key. A session date represents a sleep night, where events from 6 PM to 6 AM the next day belong to the same session.

```
Session "2024-12-23" spans:
- 2024-12-23 18:00:00 → 2024-12-24 05:59:59
```

---

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        SESSION CONTEXT                          │
│                     (session_date: TEXT)                        │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ current_session │  │  dose_events    │  │  sleep_events   │
│ (singleton)     │  │  (1:N per sess) │  │  (1:N per sess) │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│ id = 1 (fixed)  │  │ id (UUID)       │  │ id (UUID)       │
│ dose1_time      │  │ event_type      │  │ event_type      │
│ dose2_time      │  │ timestamp       │  │ timestamp       │
│ snooze_count    │  │ session_date ◄──┼──┤ session_date    │
│ dose2_skipped   │  │ metadata (JSON) │  │ color_hex       │
│ session_date ◄──┤  │ created_at      │  │ notes           │
│ terminal_state  │  └─────────────────┘  │ created_at      │
│ updated_at      │                       └─────────────────┘
└─────────────────┘
          │
          │ session_id (1:1)
          ▼
┌─────────────────┐  ┌─────────────────┐
│morning_checkins │  │ pre_sleep_logs  │
│ (1:1 per sess)  │  │ (1:1 per sess)  │
├─────────────────┤  ├─────────────────┤
│ id (UUID)       │  │ id (UUID)       │
│ session_id ◄────┼──┤ session_id      │
│ session_date    │  │ created_at_utc  │
│ sleep_quality   │  │ local_offset    │
│ feel_rested     │  │ completion_state│
│ grogginess      │  │ answers_json    │
│ mental_clarity  │  │ created_at      │
│ mood            │  └─────────────────┘
│ ... (many more) │
│ sleep_env_json  │
│ created_at      │
└─────────────────┘
```

---

## Tables

### current_session

**Purpose:** Singleton table storing active session state. Only one row (id=1) ever exists.

```sql
CREATE TABLE current_session (
    id INTEGER PRIMARY KEY CHECK (id = 1),  -- Enforces singleton
    dose1_time TEXT,                         -- ISO8601 timestamp
    dose2_time TEXT,                         -- ISO8601 timestamp
    snooze_count INTEGER DEFAULT 0,          -- 0-3 (max_snoozes)
    dose2_skipped INTEGER DEFAULT 0,         -- Boolean: 0 or 1
    session_date TEXT NOT NULL,              -- YYYY-MM-DD format
    terminal_state TEXT,                     -- completed|skipped|expired|aborted|NULL
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | INTEGER | NO | - | Always 1 (singleton constraint) |
| `dose1_time` | TEXT | YES | NULL | ISO8601 timestamp of Dose 1 |
| `dose2_time` | TEXT | YES | NULL | ISO8601 timestamp of Dose 2 |
| `snooze_count` | INTEGER | NO | 0 | Number of snoozes used (0-3) |
| `dose2_skipped` | INTEGER | NO | 0 | Boolean flag for skip |
| `session_date` | TEXT | NO | - | Session identifier (YYYY-MM-DD) |
| `terminal_state` | TEXT | YES | NULL | How session ended |
| `updated_at` | TEXT | NO | CURRENT_TIMESTAMP | Last modification time |

**Terminal States:**
- `NULL` - Session still active
- `completed` - Dose 2 taken normally
- `skipped` - User explicitly skipped Dose 2
- `expired` - Window closed without action (240+ min)
- `aborted` - Session manually cleared

---

### dose_events

**Purpose:** Immutable log of all dose-related events.

```sql
CREATE TABLE dose_events (
    id TEXT PRIMARY KEY,                     -- UUID string
    event_type TEXT NOT NULL,                -- dose_1|dose_2|snooze|skip|extra_dose
    timestamp TEXT NOT NULL,                 -- ISO8601 when event occurred
    session_date TEXT NOT NULL,              -- YYYY-MM-DD grouping key
    metadata TEXT,                           -- JSON blob for extra data
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | TEXT | NO | - | UUID primary key |
| `event_type` | TEXT | NO | - | Event classification |
| `timestamp` | TEXT | NO | - | ISO8601 event time |
| `session_date` | TEXT | NO | - | Session identifier |
| `metadata` | TEXT | YES | NULL | JSON with extra context |
| `created_at` | TEXT | NO | CURRENT_TIMESTAMP | Record creation time |

**Event Types:**
| Type | Description | Metadata |
|------|-------------|----------|
| `dose_1` | First dose taken | `{}` |
| `dose_2` | Second dose taken | `{"is_early": bool, "is_extra_dose": bool}` |
| `snooze` | Snooze activated | `{"snooze_number": int}` |
| `skip` | Dose 2 skipped | `{"reason": string?}` |
| `extra_dose` | Additional dose logged | `{"is_extra_dose": true}` |

---

### sleep_events

**Purpose:** Timestamped log of sleep-related events for timeline visualization.

```sql
CREATE TABLE sleep_events (
    id TEXT PRIMARY KEY,                     -- UUID string
    event_type TEXT NOT NULL,                -- See event types below
    timestamp TEXT NOT NULL,                 -- ISO8601 when event occurred
    session_date TEXT NOT NULL,              -- YYYY-MM-DD grouping key
    color_hex TEXT,                          -- Optional UI color override
    notes TEXT,                              -- User-provided notes
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | TEXT | NO | - | UUID primary key |
| `event_type` | TEXT | NO | - | Event classification |
| `timestamp` | TEXT | NO | - | ISO8601 event time |
| `session_date` | TEXT | NO | - | Session identifier |
| `color_hex` | TEXT | YES | NULL | Custom color (#RRGGBB) |
| `notes` | TEXT | YES | NULL | User notes |
| `created_at` | TEXT | NO | CURRENT_TIMESTAMP | Record creation time |

**Event Types (13 total):**

> **Canonical Source:** `docs/SSOT/constants.json`

| Wire Format | Swift Enum | Icon | Color | Category | Cooldown |
|-------------|------------|------|-------|----------|----------|
| `bathroom` | `bathroom` | toilet.fill | #34C759 (Green) | Physical | 60s |
| `water` | `water` | drop.fill | #007AFF (Blue) | Physical | 60s |
| `snack` | `snack` | fork.knife | #FF9500 (Orange) | Physical | 60s |
| `in_bed` | `inBed` | bed.double.fill | #5856D6 (Indigo) | Sleep Cycle | 0 |
| `lights_out` | `lightsOut` | moon.fill | #5856D6 (Indigo) | Sleep Cycle | 0 |
| `wake_final` | `wakeFinal` | sunrise.fill | #FFD60A (Yellow) | Sleep Cycle | 0 |
| `wake_temp` | `wakeTemp` | moon.zzz.fill | #5856D6 (Indigo) | Sleep Cycle | 0 |
| `anxiety` | `anxiety` | brain.head.profile | #AF52DE (Purple) | Mental | 0 |
| `dream` | `dream` | cloud.fill | #5856D6 (Indigo) | Mental | 0 |
| `heart_racing` | `heartRacing` | heart.fill | #FF3B30 (Red) | Mental | 0 |
| `noise` | `noise` | speaker.wave.3.fill | #FF9500 (Orange) | Environment | 0 |
| `temperature` | `temperature` | thermometer | #FF9500 (Orange) | Environment | 0 |
| `pain` | `pain` | bandage.fill | #FF3B30 (Red) | Environment | 0 |

> **Note:** Only physical events (bathroom, water, snack) have 60s cooldowns to prevent accidental double-taps. All other events have no cooldown—log as often as experienced.

---

### morning_checkins

**Purpose:** Comprehensive morning questionnaire data for specialist reports. One per session.

```sql
CREATE TABLE morning_checkins (
    id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL UNIQUE,       -- YYYY-MM-DD (identity constraint)
    session_id TEXT,                         -- Optional link to session UUID
    completed_at TEXT NOT NULL,              -- When check-in completed
    
    -- Core sleep assessment (always captured)
    overall_quality INTEGER NOT NULL,        -- 1-5 stars
    wake_count INTEGER NOT NULL,             -- 0+ nighttime wakes
    feeling_rested INTEGER NOT NULL,         -- 1-5 scale
    sleep_latency INTEGER,                   -- Minutes to fall asleep (nullable)
    
    -- Sleep Therapy Device
    has_sleep_therapy INTEGER NOT NULL DEFAULT 0,
    sleep_therapy TEXT,                      -- JSON array of therapy types
    
    -- Sleep Environment (v2.4.1)
    has_sleep_environment INTEGER NOT NULL DEFAULT 0,
    sleep_environment_json TEXT,             -- JSON object with environment data
    
    -- Notes
    notes TEXT,
    
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | TEXT | NO | - | UUID primary key |
| `session_date` | TEXT | NO | - | YYYY-MM-DD (UNIQUE, identity) |
| `session_id` | TEXT | YES | NULL | Optional session UUID link |
| `completed_at` | TEXT | NO | - | ISO8601 completion timestamp |
| `overall_quality` | INTEGER | NO | - | 1-5 star rating |
| `wake_count` | INTEGER | NO | - | Nighttime wake count |
| `feeling_rested` | INTEGER | NO | - | 1-5 scale |
| `sleep_latency` | INTEGER | YES | NULL | Minutes to fall asleep |
| `has_sleep_therapy` | INTEGER | NO | 0 | Boolean flag |
| `sleep_therapy` | TEXT | YES | NULL | JSON array of therapies |
| `has_sleep_environment` | INTEGER | NO | 0 | Boolean flag |
| `sleep_environment_json` | TEXT | YES | NULL | JSON environment data |
| `notes` | TEXT | YES | NULL | Free-text notes |
| `created_at` | TEXT | NO | CURRENT_TIMESTAMP | Record creation time |

**Sleep Therapy Values** (JSON array):
```json
["cpap", "mouth_guard", "chin_strap", "nasal_strip", "positional_therapy"]
```

**Sleep Environment JSON Schema**:
```json
{
  "aids": ["dark_room", "eye_mask", "white_noise", "phone_in_bed"],
  "darknessLevel": "very_dark",
  "noiseLevel": "quiet",
  "screenTimeMinutes": 30,
  "soundType": "nature_sounds"
}
```

---

### pre_sleep_logs

**Purpose:** Context capture before sleep session begins. Structured columns for direct querying.

```sql
CREATE TABLE pre_sleep_logs (
    id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL UNIQUE,       -- YYYY-MM-DD grouping key (identity)
    completed_at TEXT NOT NULL,              -- ISO8601 timestamp of submission
    caffeine_cups INTEGER,                   -- 0+ cups of caffeine
    caffeine_cutoff TEXT,                    -- Time of last caffeine (ISO8601)
    alcohol_drinks INTEGER,                  -- 0+ alcoholic drinks
    exercise_type TEXT,                      -- none|light|moderate|intense
    exercise_duration INTEGER,               -- Minutes of exercise
    stress_level INTEGER,                    -- 1-10 scale
    notes TEXT,                              -- Free-text notes
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | TEXT | NO | - | UUID primary key |
| `session_date` | TEXT | NO | - | YYYY-MM-DD (UNIQUE constraint, identity) |
| `completed_at` | TEXT | NO | - | ISO8601 submission timestamp |
| `caffeine_cups` | INTEGER | YES | NULL | Cups of caffeine consumed |
| `caffeine_cutoff` | TEXT | YES | NULL | Last caffeine time |
| `alcohol_drinks` | INTEGER | YES | NULL | Alcoholic drinks count |
| `exercise_type` | TEXT | YES | NULL | Exercise intensity |
| `exercise_duration` | INTEGER | YES | NULL | Minutes of exercise |
| `stress_level` | INTEGER | YES | NULL | 1-10 stress scale |
| `notes` | TEXT | YES | NULL | Free-text notes |
| `created_at` | TEXT | NO | CURRENT_TIMESTAMP | Record creation time |

**Exercise Type Values:**
- `none` - No exercise
- `light` - Light activity (walking, stretching)
- `moderate` - Moderate activity (jogging, cycling)
- `intense` - Intense activity (HIIT, heavy lifting)

---

## Indexes

```sql
-- Performance indexes for common queries
CREATE INDEX idx_sleep_events_session ON sleep_events(session_date);
CREATE INDEX idx_sleep_events_timestamp ON sleep_events(timestamp);
CREATE INDEX idx_dose_events_session ON dose_events(session_date);
CREATE INDEX idx_morning_checkins_session ON morning_checkins(session_date);
CREATE INDEX idx_morning_checkins_session_id ON morning_checkins(session_id);
```

---

## JSON Schema Definitions

### dose_events.metadata

```json
{
  "is_early": false,        // Dose taken before window opened
  "is_extra_dose": false,   // Additional dose after first Dose 2
  "snooze_number": 1,       // Which snooze (1, 2, or 3)
  "reason": "string"        // Skip reason (optional)
}
```

### physical_symptoms_json

```json
{
  "painLocations": ["head", "neck", "shoulders"],
  "painSeverity": 5,        // 0-10
  "painType": "aching",     // aching|sharp|stiff|throbbing|burning|tingling|cramping
  "hasHeadache": true,
  "headacheSeverity": "moderate",
  "headacheLocation": "temples",
  "isMigraine": false,
  "muscleStiffness": "mild",
  "muscleSoreness": "none",
  "notes": "Optional pain notes"
}
```

### respiratory_symptoms_json

```json
{
  "congestion": "stuffyNose",   // none|stuffyNose|runnyNose|both
  "throatCondition": "dry",     // normal|dry|sore|scratchy
  "coughType": "none",          // none|dry|productive
  "sinusPressure": "mild",      // none|mild|moderate|severe
  "feelingFeverish": false,
  "sicknessLevel": "no",        // no|comingDown|activelySick|recovering
  "notes": "Optional respiratory notes"
}
```

### sleep_therapy_json

```json
{
  "device": "CPAP",         // CPAP|BiPAP|APAP|Oxygen|OralAppliance|Positional|Other
  "compliance": 85,         // 0-100 percentage
  "notes": "Mask leaked at 3am"
}
```

### sleep_environment_json

```json
{
  "sleep_aids_used": ["Dark room/blackout", "Eye mask", "White noise/sound"],
  "room_darkness": "dark",           // bright|dim|dark
  "noise_level": "quiet",            // quiet|some_noise|loud
  "screen_in_bed_minutes_bucket": "0_15",  // 0_15|15_45|45_plus|unknown
  "sound_type": "white_noise",       // white_noise|rain|fan|other|unknown
  "other_aid_text": "",              // Max 50 chars
  "same_as_usual": false
}
```

### pre_sleep_logs.answers_json

```json
{
  "timing_bedtime_intent": "22:30",
  "stress_level": 3,                  // 1-5
  "stress_drivers": ["work", "health"],
  "stimulants": ["caffeine"],
  "last_caffeine_hours": 6,
  "exercise_today": true,
  "exercise_intensity": "moderate",
  "pain_level": "mild",
  "pain_locations": ["lowerBack"],
  "notes": "Optional notes"
}
```

---

## Access Patterns

### Common Queries

**Get active session state:**
```swift
let (d1, d2, snooze, skipped) = storage.loadCurrentSession()
```

**Get all events for a session:**
```swift
let sleepEvents = storage.fetchSleepEvents(forSession: "2024-12-23")
let doseEvents = storage.fetchDoseEvents(forSession: "2024-12-23")
```

**Get recent sessions for history:**
```swift
let sessions = storage.fetchRecentSessions(limit: 30)
```

**Get morning check-in:**
```swift
let checkIn = storage.fetchMorningCheckIn(forSession: "2024-12-23")
```

**Delete a session:**
```swift
storage.deleteSession(sessionDate: "2024-12-23")  // Cascades to all related tables
```

---

## Migration History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-09 | Initial schema: sleep_events, dose_events, current_session |
| 2.0.0 | 2024-10 | Added pre_sleep_logs table |
| 2.5.0 | 2024-11 | Added morning_checkins table |
| 2.5.1 | 2024-12 | Added sleep_therapy columns to morning_checkins |
| 2.4.0 | 2024-12 | Added terminal_state to current_session |
| 2.4.1 | 2024-12 | Added sleep_environment columns to morning_checkins |

**Migration Strategy:**
- All migrations use `ALTER TABLE ADD COLUMN` which is safe to run multiple times
- SQLite ignores duplicate column additions
- No data migration required (new columns have defaults)

---

## Swift Connectors

### EventStorage (Primary Connector)

**Location:** `ios/DoseTap/Storage/EventStorage.swift`

```swift
@MainActor
public class EventStorage {
    public static let shared = EventStorage()
    
    // Session Operations
    func loadCurrentSession() -> (Date?, Date?, Int, Bool)
    func saveDose1(timestamp: Date)
    func saveDose2(timestamp: Date, isEarly: Bool, isExtraDose: Bool)
    func saveSnooze()
    func saveSkip(reason: String?)
    func clearCurrentSession()
    func deleteSession(sessionDate: String)
    
    // Sleep Events
    func saveSleepEvent(_ event: SleepEvent)
    func fetchSleepEvents(forSession: String) -> [SleepEvent]
    func deleteSleepEvent(id: String)
    
    // Dose Events
    func fetchDoseEvents(forSession: String) -> [DoseEvent]
    
    // Morning Check-ins
    func saveMorningCheckIn(_ checkIn: StoredMorningCheckIn)
    func saveMorningCheckIn(_ checkIn: StoredMorningCheckIn, forSession: String)
    func fetchMorningCheckIn(forSession: String) -> StoredMorningCheckIn?
    func hasTodaysMorningCheckIn() -> Bool
    
    // Pre-Sleep Logs
    func savePreSleepLog(_ log: PreSleepLog)
    func fetchPreSleepLog(forSession: String) -> PreSleepLog?
    
    // History/Export
    func fetchRecentSessions(limit: Int) -> [SessionSummary]
    func exportAllData() -> ExportData
}
```

### SessionRepository (State Manager)

**Location:** `ios/DoseTap/Storage/SessionRepository.swift`

```swift
@MainActor
public final class SessionRepository: ObservableObject {
    public static let shared = SessionRepository()
    
    // Published State (UI binds to these)
    @Published var activeSessionDate: String?
    @Published var dose1Time: Date?
    @Published var dose2Time: Date?
    @Published var snoozeCount: Int
    @Published var dose2Skipped: Bool
    
    // Change notification
    let sessionDidChange = PassthroughSubject<Void, Never>()
    
    // Operations
    func reload()
    func deleteSession(sessionDate: String)
    func clearActiveSession()
    
    // Computed
    var hasActiveSession: Bool
    func isActiveSession(_ date: String) -> Bool
}
```

### Usage Pattern

```swift
// ContentView.swift
struct ContentView: View {
    @StateObject private var sessionRepo = SessionRepository.shared
    @StateObject private var core = DoseTapCore()
    
    var body: some View {
        // UI binds to sessionRepo for state
        // Uses core for business logic
    }
    .onReceive(sessionRepo.sessionDidChange) {
        // Sync core from repository on changes
        syncCoreFromRepository()
    }
}
```

---

## Export Format

When exporting data, the following CSV columns are generated:

### sessions.csv
```
session_date,dose1_time,dose2_time,snooze_count,dose2_skipped,terminal_state
```

### sleep_events.csv
```
id,event_type,timestamp,session_date,notes
```

### morning_checkins.csv
```
session_date,sleep_quality,feel_rested,grogginess,mental_clarity,mood,
has_physical_symptoms,has_respiratory_symptoms,has_sleep_environment,
sleep_aids_used,room_darkness,noise_level,screen_minutes_bucket
```

---

## Data Integrity Rules

1. **Session Singleton**: `current_session` table can only have `id = 1`
2. **Cascade Delete**: Deleting a session removes all related events
3. **No Foreign Keys**: SQLite FKs disabled for simplicity; app enforces relationships
4. **Timestamps**: All stored as ISO8601 strings for portability
5. **UUIDs**: All IDs are UUID v4 strings
6. **Nullability**: Only explicitly optional fields can be NULL

---

*For the authoritative specification, see [SSOT/README.md](SSOT/README.md)*
