# 05 — Storage Layer

## SQLite Database

File: `ios/DoseTap/Storage/EventStorage.swift` (277 lines) + extensions

- Path: `Documents/dosetap_events.sqlite`
- Mode: WAL (Write-Ahead Logging)
- Foreign keys: ON
- Direct C API (`sqlite3_*` calls)
- In-memory mode for tests: `EventStorage.inMemory()`

## Schema (12 Tables)

File: `ios/DoseTap/Storage/EventStorage+Schema.swift` (681 lines)

```sql
-- Sleep events (bathroom, lights_out, anxiety, etc.)
CREATE TABLE sleep_events (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    timestamp TEXT NOT NULL,       -- ISO8601 UTC
    session_date TEXT NOT NULL,    -- "YYYY-MM-DD"
    session_id TEXT,
    color_hex TEXT,
    notes TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Dose events (dose1, dose2, extra_dose)
CREATE TABLE dose_events (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    session_date TEXT NOT NULL,
    session_id TEXT,
    metadata TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Current session singleton (id=1)
CREATE TABLE current_session (
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

-- Sleep session metadata (lifecycle)
CREATE TABLE sleep_sessions (
    session_id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL,
    start_utc TEXT NOT NULL,
    end_utc TEXT,
    terminal_state TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Pre-sleep log
CREATE TABLE pre_sleep_logs (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    created_at_utc TEXT NOT NULL,
    local_offset_minutes INTEGER NOT NULL,
    completion_state TEXT NOT NULL DEFAULT 'partial',
    answers_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Morning check-in
CREATE TABLE morning_checkins (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    session_date TEXT NOT NULL,
    answers_json TEXT NOT NULL DEFAULT '{}',
    created_at_utc TEXT NOT NULL,
    local_offset_minutes INTEGER NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Normalized check-in submissions
CREATE TABLE checkin_submissions (
    id TEXT PRIMARY KEY,
    source_record_id TEXT NOT NULL,
    session_id TEXT,
    session_date TEXT NOT NULL,
    checkin_type TEXT NOT NULL,
    questionnaire_version TEXT NOT NULL,
    user_id TEXT NOT NULL,
    submitted_at_utc TEXT NOT NULL,
    local_offset_minutes INTEGER NOT NULL,
    responses_json TEXT NOT NULL
);

-- Medication log
CREATE TABLE medication_log (
    id TEXT PRIMARY KEY,
    ...
);

-- Dosing amount schema
CREATE TABLE dosing_amounts (
    id TEXT PRIMARY KEY,
    ...
);

-- Diagnostic events (tier 1/2/3)
CREATE TABLE diagnostic_events (
    id TEXT PRIMARY KEY,
    ...
);

-- Nap tracking
CREATE TABLE nap_sessions (
    id TEXT PRIMARY KEY,
    ...
);

-- CloudKit tombstones (pending deletes)
CREATE TABLE cloudkit_tombstones (
    key TEXT PRIMARY KEY,
    ...
);
```

## EventStorage Extensions

| File | Purpose | Key Functions |
| ---- | ------- | ------------- |
| `EventStorage+Schema.swift` | DDL, migrations | `createTables()`, `openDatabase()` |
| `EventStorage+Dose.swift` | Dose CRUD | `saveDose1()`, `saveDose2()`, `saveDoseSkipped()`, `saveSnooze()` |
| `EventStorage+Session.swift` | Session CRUD | `loadCurrentSessionState()`, `currentSessionDate()`, `updateSessionState()` |
| `EventStorage+CheckIn.swift` | Survey persistence | `savePreSleepLog()`, `saveMorningCheckIn()`, `saveCheckInSubmission()` |
| `EventStorage+EventStore.swift` | Sleep events | `insertSleepEvent()`, `fetchSleepEvents()`, `deleteSleepEvent()` |
| `EventStorage+Exports.swift` | Data export | `exportAllSessions()`, `exportCSV()` |
| `EventStorage+Maintenance.swift` | Cleanup | `deleteOldDiagnostics()`, `vacuumDatabase()`, `databaseSizeBytes()` |
| `EncryptedEventStorage.swift` | Encryption wrapper | At-rest encryption support |

## Storage Models

File: `ios/DoseTap/Storage/StorageModels.swift` (867 lines)

### Key Types

```swift
struct StoredSleepEvent: Identifiable {
    let id: String
    let eventType: String        // "bathroom", "lights_out", etc.
    let timestamp: Date
    let sessionDate: String
    let colorHex: String?
    let notes: String?
}

struct StoredDoseLog {
    let sessionDate: String
    let dose1Time: Date?
    let dose2Time: Date?
    let snoozeCount: Int
    let dose2Skipped: Bool
}

struct StoredDoseEvent: Identifiable {
    let id: String
    let eventType: String         // "dose1", "dose2", "extra_dose"
    let timestamp: Date
    let sessionDate: String
    let metadata: String?
}

struct StoredPreSleepLog: Identifiable {
    let id: String
    let sessionId: String?
    let createdAtUtc: String
    let localOffsetMinutes: Int
    let completionState: String   // "partial" | "complete"
    let answers: PreSleepLogAnswers?
}

struct StoredMorningCheckIn: Identifiable {
    let id: String
    let sessionId: String?
    let sessionDate: String
    let answers: MorningCheckInAnswers?
}

struct StoredCheckInSubmission: Identifiable {
    // Normalized questionnaire submission
    let id: String
    let sourceRecordId: String
    let checkInType: EventStorage.CheckInType  // .preNight | .morning
    let questionnaireVersion: String
    let responsesJson: String
}
```

## Date Serialization

All dates stored as ISO8601 UTC with fractional seconds:

```swift
let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
```

## Database Security

File: `ios/DoseTap/Security/DatabaseSecurity.swift`

- File protection: `.completeUntilFirstUserAuthentication`
- Optional SQLCipher encryption wrapper
- Integrity checks on open
