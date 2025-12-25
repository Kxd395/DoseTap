# DoseTap Data Dictionary

> **Canonical Reference**: This document defines all data structures, fields, and relationships.
> **Persistence**: SQLite via `EventStorage.swift`
> **Schema Version**: 6 (see [SchemaEvolution.md](SchemaEvolution.md))
> 
> **Primary Key**: All entities use `session_date` (YYYY-MM-DD format) as the spine.
> A "night" starts at 6 PM and ends at 6 AM next day. Sessions belong to the start date.

## Session Identity Model

### The Spine: `session_date`

Every record in DoseTap links to a session via `session_date` (string, YYYY-MM-DD format).

```
session_date = 2025-01-07
    ├── current_session (singleton, holds live state for current night)
    ├── dose_events[] (historical: dose_1, dose_2, snooze, skip)
    ├── sleep_events[] (bathroom, wake, etc.)
    ├── morning_checkins (post-wake questionnaire)
    └── pre_sleep_logs (pre-sleep questionnaire)
```

**Date Assignment Rule**: 
- 6:00 PM to 5:59 AM → session_date = the evening date
- Example: 2:00 AM on Jan 8 → session_date = "2025-01-07"

---

## Tables (5 Total)

### 1. `current_session` (Singleton)

**Purpose**: Holds live state for the current night only. Gets overwritten each new session.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | INTEGER | ✓ | Always 1 (enforced by CHECK constraint) |
| `session_date` | TEXT | ✓ | YYYY-MM-DD of this session |
| `dose1_time` | TEXT | | ISO8601 timestamp of Dose 1 |
| `dose2_time` | TEXT | | ISO8601 timestamp of Dose 2 |
| `snooze_count` | INTEGER | ✓ | Number of snoozes used (0-3) |
| `dose2_skipped` | INTEGER | ✓ | 0 or 1 boolean |
| `terminal_state` | TEXT | | How session ended: `completed`, `skipped`, `expired`, `aborted` (null if in-progress) |
| `updated_at` | TEXT | | Last modification time |

**Terminal State Values**:
| Value | Description |
|-------|-------------|
| `completed` | Both doses taken successfully |
| `skipped` | User explicitly skipped Dose 2 |
| `expired` | Window closed without dose or skip action |
| `aborted` | User cancelled mid-session (rare) |
| `null` | Session still in progress |

**Constraint**: `id = 1` enforced. Only one row can exist.

**Not Stored Here**: Historical sessions. Use `dose_events` grouped by `session_date`.

---

### 2. `dose_events` (Historical)

**Purpose**: Permanent record of all dose-related actions across all sessions.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | TEXT | ✓ | UUID string |
| `event_type` | TEXT | ✓ | `dose_1`, `dose_2`, `snooze`, `skip`, `extra_dose` |
| `timestamp` | TEXT | ✓ | ISO8601 UTC timestamp of action |
| `session_date` | TEXT | ✓ | YYYY-MM-DD this event belongs to |
| `metadata` | TEXT | | JSON blob (e.g., `{"count": 2}` for snooze) |
| `created_at` | TEXT | | Record creation time |

**Dose Event Types**:
| Value | Description |
|-------|-------------|
| `dose_1` | First dose taken |
| `dose_2` | Second dose taken |
| `snooze` | Snooze action (metadata contains count) |
| `skip` | User skipped Dose 2 |
| `extra_dose` | Rare: additional dose taken |

**Query for History**:
```sql
SELECT session_date, 
       MAX(CASE WHEN event_type='dose_1' THEN timestamp END) as dose1_time,
       MAX(CASE WHEN event_type='dose_2' THEN timestamp END) as dose2_time
FROM dose_events
GROUP BY session_date
ORDER BY session_date DESC
```

---

### 3. `sleep_events` (Local-Only)

**Purpose**: User-logged sleep events. **Never sent to API.** Included in export bundles.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | TEXT | ✓ | UUID string |
| `event_type` | TEXT | ✓ | One of 13 types (see below) |
| `timestamp` | TEXT | ✓ | ISO8601 UTC timestamp |
| `session_date` | TEXT | ✓ | YYYY-MM-DD this event belongs to |
| `color_hex` | TEXT | | Display color for UI |
| `created_at` | TEXT | ✓ | Record creation time |

**Event Types** (13 total - canonical source: `constants.json`):

| Swift Enum | Wire Format | Category | Cooldown |
|------------|------------|----------|----------|
| `bathroom` | `bathroom` | physical | 60s |
| `water` | `water` | physical | 300s |
| `snack` | `snack` | physical | 900s |
| `inBed` | `in_bed` | sleepCycle | 3600s |
| `lightsOut` | `lights_out` | sleepCycle | 3600s |
| `wakeFinal` | `wake_final` | sleepCycle | 3600s |
| `wakeTemp` | `wake_temp` | sleepCycle | 300s |
| `anxiety` | `anxiety` | mental | 300s |
| `dream` | `dream` | mental | 60s |
| `heartRacing` | `heart_racing` | mental | 300s |
| `noise` | `noise` | environment | 60s |
| `temperature` | `temperature` | environment | 300s |
| `pain` | `pain` | environment | 300s |

**Naming Convention**:
- Swift code: camelCase (`lightsOut`, `inBed`)
- SQLite storage: snake_case (`lights_out`, `in_bed`)
- Export files: snake_case (`lights_out`, `in_bed`)

---

### 4. `morning_checkins`

**Purpose**: Post-wake questionnaire data. One per session.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | TEXT | ✓ | | UUID string |
| `session_date` | TEXT | ✓ | | YYYY-MM-DD (UNIQUE constraint) |
| `session_id` | TEXT | | | Optional link to session UUID |
| `completed_at` | TEXT | ✓ | | ISO8601 timestamp of submission |
| `overall_quality` | INTEGER | ✓ | | 1-5 scale |
| `wake_count` | INTEGER | ✓ | | 0+ nighttime wakes |
| `feeling_rested` | INTEGER | ✓ | | 1-5 scale |
| `sleep_latency` | INTEGER | | | Minutes to fall asleep (nullable) |
| `notes` | TEXT | | | Free-text notes |
| `sleep_therapy` | TEXT | | | JSON array of therapy types |
| `has_sleep_therapy` | INTEGER | | 0 | Boolean flag |
| `sleep_environment_json` | TEXT | | | JSON object with environment data |
| `has_sleep_environment` | INTEGER | | 0 | Boolean flag |

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

### 5. `pre_sleep_logs`

**Purpose**: Pre-sleep questionnaire data (caffeine, stress, exercise). One per session.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | TEXT | ✓ | | UUID string |
| `session_date` | TEXT | ✓ | | YYYY-MM-DD (UNIQUE constraint) |
| `completed_at` | TEXT | ✓ | | ISO8601 timestamp of submission |
| `caffeine_cups` | INTEGER | | | 0+ cups of caffeine |
| `caffeine_cutoff` | TEXT | | | Time of last caffeine (ISO8601) |
| `alcohol_drinks` | INTEGER | | | 0+ alcoholic drinks |
| `exercise_type` | TEXT | | | `none`, `light`, `moderate`, `intense` |
| `exercise_duration` | INTEGER | | | Minutes of exercise |
| `stress_level` | INTEGER | | | 1-10 scale |
| `notes` | TEXT | | | Free-text notes |

---

## Timestamp Rules

### Storage
- **All timestamps stored in UTC ISO8601**: `2025-01-07T22:30:00Z`
- **Timezone offset preserved for display**: Original local time zone stored where needed

### Display
- **UI shows local time**: Convert UTC to device timezone for display
- **Export includes both**: UTC timestamp + original timezone offset

### Edge Cases

| Scenario | Handling |
|----------|----------|
| DST spring forward | Gap hour (2:00-3:00 AM) → use post-transition time |
| DST fall back | Ambiguous hour (1:00-2:00 AM) → use wall clock + offset |
| User changes device time | Warn if >1 hour change during session |
| User travels timezones | Warn on first app open if >2 hour timezone shift |
| Midnight boundary | Session date = evening date, not calendar date at 2 AM |

---

## Session State Lifecycle

```
NoSession (no dose1_time)
    │
    ▼ Take Dose 1
SessionActiveBeforeWindow (dose1 taken, <150min elapsed)
    │
    ▼ 150 minutes pass
WindowOpen (150-225min elapsed, snooze available)
    │
    ├──▶ Snooze (up to 3x, +10min each)
    │
    ▼ 225+ minutes pass
WindowNearClose (225-240min, snooze disabled)
    │
    ├──▶ Take Dose 2 ──▶ Dose2Taken (TERMINAL)
    ├──▶ Skip Dose 2 ──▶ Dose2Skipped (TERMINAL)
    └──▶ 240min pass ──▶ WindowExpired (TERMINAL)
```

**Terminal States**: `Dose2Taken`, `Dose2Skipped`, `WindowExpired`
- Once terminal, session cannot change (except via manual correction with audit trail)
- Next session starts at 6 PM or when user takes new Dose 1

---

## Export Schema

### `DoseTap_Export_YYYY-MM-DD.zip`

```
├── sessions.csv          # One row per session
├── dose_events.csv       # All dose actions
├── sleep_events.csv      # All sleep events
├── morning_checkins.csv  # All check-ins
├── pre_sleep_logs.csv    # All pre-sleep logs
├── settings.json         # User preferences (no secrets)
├── schema_version.json   # Version info for parsing
└── readme.txt            # Column definitions
```

### `schema_version.json`
```json
{
  "schema_version": "6",
  "app_version": "2.3.0",
  "export_timestamp": "2025-01-07T15:30:00Z",
  "timezone": "America/New_York"
}
```

---

## Relationships Diagram

```
                    session_date (YYYY-MM-DD)
                           │
    ┌──────────────────────┼──────────────────────┐
    │            │         │         │            │
    ▼            ▼         ▼         ▼            ▼
dose_events  sleep_events  │    morning_     pre_sleep_
(many per    (many per     │    checkins     logs
 session)     session)     │    (one per     (one per
                           │     session)     session)
                           │
                           ▼
                    current_session
                    (singleton - latest only)
```

---

## Migration Policy

### Version Bumps

| Change Type | Version Bump | Migration Required |
|-------------|--------------|-------------------|
| New optional field | Patch (x.x.+1) | No |
| New required field with default | Minor (x.+1.0) | Yes, set defaults |
| Remove field | Major (+1.0.0) | Yes, drop column |
| Change field type | Major (+1.0.0) | Yes, transform data |
| New table | Minor (x.+1.0) | Yes, create table |

### Migration Steps

1. Check `schema_version` in database
2. If older, run migration scripts in order
3. Update `schema_version` after success
4. Never delete old data during migration (archive first)

### Rollback

- Migrations are one-way (no automated rollback)
- Keep backup before major migrations
- Support bundle includes raw database for recovery

---

## References

- [DATABASE_SCHEMA.md](../../DATABASE_SCHEMA.md) - Complete schema with ERD
- [SchemaEvolution.md](SchemaEvolution.md) - Migration history
- [constants.json](../constants.json) - Canonical enum definitions
