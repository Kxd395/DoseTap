# Pre-Sleep Log Contract

> **Purpose**: Context capture before sleep session. Turns nightly timeline into experiment journal.
>
> **Core Rule**: Optional, fast (≤30s), never blocking.

## Design Principles

| Principle | Implementation |
|-----------|----------------|
| Optional | Always skippable, never required for Dose 1 |
| Fast | 3 cards, single-tap answers, ≤30 seconds |
| One-handed | Large tap targets, bottom-aligned actions |
| Structured | Fixed keys, no required free text |
| Linked | Attaches to session within 2hr window |

## Flow Position

```
[Start Tonight] → [Pre-Sleep Log (optional)] → [Dose 1] → [Normal flow]
```

**Entry Points**:
1. Automatic prompt after "Start Tonight"
2. Quick action button on main screen
3. Notification: "Planning to sleep soon?"
4. Shortcuts action: "Pre Sleep Check-In"

**Exit Points**:
- Complete all 3 cards
- "Skip for tonight" (any card)
- System back/dismiss

## Card Structure

### Card 1: Timing + Stress

| Question | Type | Options |
|----------|------|---------|
| Intended sleep time | Single | Now, Within 30 min, 30-60 min, Later |
| Stress level | Scale | 1-5 |

### Card 2: Body + Substances

| Question | Type | Options |
|----------|------|---------|
| Body pain right now | Single | None, Mild, Moderate, Severe |
| Stimulants after 2pm | Single | None, Caffeine, Nicotine, Both |
| Alcohol today | Single | None, 1-2, 3+ |

### Card 3: Activity + Naps

| Question | Type | Options |
|----------|------|---------|
| Exercise today | Single | None, Light, Moderate, Hard |
| Nap today | Single | None, Short (<30), Medium (30-90), Long (90+) |

## Smart Expanders

**Show conditionally based on core answers:**

| Trigger | Expander Questions |
|---------|-------------------|
| Pain ≠ None | Pain location (multi), Pain type (single) |
| Stress ≥ 4 | Main driver (Work/Family/Health/Money/Other) |
| Intended = Later | Why later (Social/Work/Screen/Restless/Other) |

**Optional toggle: "Add more details"**
- Late meal (None, Within 2hr, Within 1hr)
- Screens in bed (None, Some, A lot)
- Room temp feels (Cool, Ok, Warm)
- Noise level (Quiet, Some, Loud)

## UI Requirements

### Per Card
- Progress indicator (1/3, 2/3, 3/3)
- "Skip for tonight" always visible
- Big tap targets (44pt minimum)
- One-handed friendly (bottom-aligned actions)

### Smart Features
- "Use last answers" for stable items (environment only)
- Never auto-copy: alcohol, caffeine, stimulants

## Data Model

### SQLite Table: `pre_sleep_logs`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | TEXT | ✓ | UUID string |
| session_id | TEXT | | Linked session (nullable until linked) |
| created_at_utc | TEXT | ✓ | ISO8601 timestamp |
| local_offset_minutes | INTEGER | ✓ | Timezone offset at creation |
| completion_state | TEXT | ✓ | `partial`, `complete`, `skipped` |
| answers_json | TEXT | ✓ | JSON object with fixed keys |

### Answer Keys (JSON)

```json
{
  "intendedSleepTime": "within30",
  "stressLevel": 3,
  "bodyPain": "mild",
  "stimulants": "caffeine",
  "alcohol": "none",
  "exercise": "moderate",
  "napToday": "none",
  "painLocation": ["head", "neck"],
  "painType": "aching",
  "stressDriver": null,
  "laterReason": null
}
```

## Session Linking

### Algorithm

```
1. When session starts (Dose 1 taken):
2. Find pre_sleep_logs WHERE session_id IS NULL
   AND created_at_utc > (now - 2 hours)
   ORDER BY created_at_utc DESC
   LIMIT 1
3. If found: UPDATE set session_id = current_session_id
4. If not found: session has no pre-sleep log (valid state)
```

### Edge Cases

| Case | Handling |
|------|----------|
| Log started, phone locked, returned later | Save as `partial` |
| Log completed, no session starts | Keep as `Unlinked` |
| Two logs in one night | Most recent links, others stay separate |
| Timezone change between log and session | Store offset with each record |

## Export Format

### `pre_sleep_logs.csv`

```csv
id,session_id,created_at_utc,local_offset_minutes,completion_state,intended_sleep_time,stress_level,body_pain,stimulants,alcohol,exercise,nap_today,pain_location,pain_type,stress_driver,later_reason
abc123,sess_456,2025-01-07T22:30:00Z,-300,complete,within30,3,mild,caffeine,none,moderate,none,"head,neck",aching,,
def789,,2025-01-07T21:00:00Z,-300,partial,now,2,none,none,none,,,,,,
```

### Join Keys
- `session_id` → links to `sessions.csv`
- Enables correlation with: dose1_time, window_open, dose2_time, wake_final, morning_check_in

## Dashboard Correlations (No ML)

| Correlation | Query |
|-------------|-------|
| Missed Dose 2 vs "Later" bedtime | WHERE dose2_taken = false AND intended_sleep_time = 'later' |
| Wake events vs high stress | JOIN sleep_events WHERE stress_level >= 4 |
| Sleep quality vs late caffeine | JOIN morning_checkins WHERE stimulants IN ('caffeine', 'both') |
| Pain severity vs wake count | GROUP BY body_pain, COUNT(wake_temp) |

## Acceptance Criteria

- [ ] Complete pre-sleep log in ≤30 seconds one-handed
- [ ] Skipping never blocks session start
- [ ] Data fully structured, no required free text
- [ ] Export includes logs with schema version
- [ ] Linker correctly links log created ≤2hr before session
- [ ] Two logs in one night: only one links
- [ ] DST/timezone: local date grouping correct

## Test Plan

| Test | Expected |
|------|----------|
| Log at T, session at T+90min | Link succeeds |
| Two logs exist, session starts | Links to most recent in window |
| Log at T, session at T+150min | No link (outside 2hr window) |
| User skips on Card 1 | completion_state = 'skipped', session can start |
| App killed on Card 2 | Saved as 'partial' on next launch |
| Export includes unlinked log | Row has empty session_id |
