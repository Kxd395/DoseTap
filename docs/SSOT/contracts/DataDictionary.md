# DoseTap Data Dictionary

> **Canonical Reference**: This document defines all data structures, fields, and relationships.
> 
> **Primary Key**: All entities use `session_date` (YYYY-MM-DD format) as the spine.
> A "night" starts at 6 PM and ends at 6 AM next day. Sessions belong to the start date.

## Session Identity Model

### The Spine: `session_date`

Every record in DoseTap links to a session via `session_date` (string, YYYY-MM-DD format).

```
session_date = 2025-01-07
    ├── current_session (singleton, holds live state for current night)
    ├── dose_events[] (historical: dose1, dose2, snooze, skip)
    ├── sleep_events[] (bathroom, wake, etc.)
    └── morning_checkins[] (post-wake questionnaire)
```

**Date Assignment Rule**: 
- 6:00 PM to 5:59 AM → session_date = the evening date
- Example: 2:00 AM on Jan 8 → session_date = "2025-01-07"

---

## Tables

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
| `updated_at` | TEXT | | Last modification time |

**Constraint**: `id = 1` enforced. Only one row can exist.

**Not Stored Here**: Historical sessions. Use `dose_events` grouped by `session_date`.

---

### 2. `dose_events` (Historical)

**Purpose**: Permanent record of all dose-related actions across all sessions.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | TEXT | ✓ | UUID string |
| `event_type` | TEXT | ✓ | `dose1`, `dose2`, `snooze`, `dose2_skipped` |
| `timestamp` | TEXT | ✓ | ISO8601 UTC timestamp of action |
| `session_date` | TEXT | ✓ | YYYY-MM-DD this event belongs to |
| `metadata` | TEXT | | JSON blob (e.g., `{"count": 2}` for snooze) |
| `created_at` | TEXT | | Record creation time |

**Query for History**:
```sql
SELECT session_date, 
       MAX(CASE WHEN event_type='dose1' THEN timestamp END) as dose1_time,
       MAX(CASE WHEN event_type='dose2' THEN timestamp END) as dose2_time
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
| `event_type` | TEXT | ✓ | One of 12 types (see below) |
| `timestamp` | TEXT | ✓ | ISO8601 UTC timestamp |
| `session_date` | TEXT | ✓ | YYYY-MM-DD this event belongs to |
| `color_hex` | TEXT | | Display color for UI |
| `notes` | TEXT | | User-entered notes |

**Event Types** (12 total - see `constants.json` for authoritative list):

| Type | Wire Format | Category | Cooldown |
|------|------------|----------|----------|
| bathroom | `bathroom` | physical | 60s |
| water | `water` | physical | 300s |
| snack | `snack` | physical | 900s |
| lightsOut | `lights_out` | sleepCycle | 3600s |
| wakeFinal | `wake_final` | sleepCycle | 3600s |
| wakeTemp | `wake_temp` | sleepCycle | 300s |
| anxiety | `anxiety` | mental | 300s |
| dream | `dream` | mental | 60s |
| heartRacing | `heart_racing` | mental | 300s |
| noise | `noise` | environment | 60s |
| temperature | `temperature` | environment | 300s |
| pain | `pain` | environment | 300s |

**Naming Convention**:
- Swift code: camelCase (`lightsOut`)
- SQLite storage: snake_case (`lights_out`)
- Export files: snake_case (`lights_out`)

---

### 4. `morning_checkins`

**Purpose**: Post-wake questionnaire data.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | TEXT | ✓ | | UUID string |
| `session_id` | TEXT | ✓ | | Links to session |
| `timestamp` | TEXT | ✓ | | When check-in was completed |
| `session_date` | TEXT | ✓ | | YYYY-MM-DD |
| `sleep_quality` | INTEGER | ✓ | 3 | 1-5 scale |
| `feel_rested` | TEXT | ✓ | "moderate" | `poor`, `moderate`, `good`, `excellent` |
| `grogginess` | TEXT | ✓ | "mild" | `none`, `mild`, `moderate`, `severe` |
| `sleep_inertia_duration` | TEXT | ✓ | "fiveToFifteen" | Duration enum |
| `dream_recall` | TEXT | ✓ | "none" | `none`, `vague`, `vivid` |
| `has_physical_symptoms` | INTEGER | ✓ | 0 | Boolean |
| `physical_symptoms_json` | TEXT | | | JSON blob |
| `has_respiratory_symptoms` | INTEGER | ✓ | 0 | Boolean |
| `respiratory_symptoms_json` | TEXT | | | JSON blob |
| `mental_clarity` | INTEGER | ✓ | 5 | 1-10 scale |

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
├── settings.json         # User preferences (no secrets)
├── schema_version.json   # Version info for parsing
└── readme.txt            # Column definitions
```

### `schema_version.json`
```json
{
  "schema_version": "1.0.0",
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
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
    dose_events      sleep_events    morning_checkins
    (many per         (many per         (one per
     session)          session)          session)
         │
         │ aggregated
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
