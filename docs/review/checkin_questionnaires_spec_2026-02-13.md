# DoseTap Check-In Questionnaires Spec (Pre-Night + Morning)

## Purpose
This spec defines:
- exact question flow,
- question IDs,
- answer encoding/marking,
- storage shape,
- and pre-night to morning comparison rules.

This is intended to remove ambiguity for implementation and analytics.

## Non-negotiable rule
Pre-Night and Morning must use the same core pain structure and IDs so area-by-area deltas are valid.

## Check-In types
- `pre_night`
- `morning`

## Submission metadata (every save)
Each submission writes:
- `id`
- `source_record_id`
- `session_id`
- `session_date` (`yyyy-MM-dd`, app rollover model)
- `checkin_type` (`pre_night` | `morning`)
- `questionnaire_version`
- `user_id`
- `submitted_at_utc`
- `local_offset_minutes`
- `responses_json`

## Answer encoding (marking)
- Scale questions: integer (`Int`) values.
- Single choice: canonical string enum.
- Multi choice: string array.
- Booleans: `true`/`false`.
- Optional unanswered fields are omitted.

## Core mirrored question set (both check-ins)

### Global state
- `overall.wellbeing` (0-10)
- `overall.energy` (0-10)
- `overall.mood` (0-10)
- `overall.stress` (0-10)

### Pain core
- `pain.any` (bool)
- `pain.entries` (array, required when `pain.any = true`)
- `pain.overall_intensity` (0-10 optional summary)

### Function
- `stiffness.level` (0-10)
- `function.interference` (0-10)
- `function.movement_limit` (`none`, `little`, `moderate`, `a_lot`)

### Interventions + notes
- `interventions.used` (multi-select)
- `interventions.notes` (optional text)
- `notes.anything_else` (optional text)

## Substance detail model (granular, pre-night)

### Caffeine
- `pre.substances.caffeine.any` (bool)
- `pre.substances.caffeine.source` (`coffee` | `tea` | `soda` | `energy_drink` | `multiple` | `none`)
- `pre.substances.caffeine.last_time_utc` (ISO datetime)
- `pre.substances.caffeine.last_amount_mg` (int, `> 0`)
- `pre.substances.caffeine.daily_total_mg` (int, `>= last_amount_mg`)

### Alcohol
- `pre.substances.alcohol.any` (bool)
- `pre.substances.alcohol` (`none` | `1` | `2-3` | `4+`)
- `pre.substances.alcohol.last_time_utc` (ISO datetime)
- `pre.substances.alcohol.last_amount_drinks` (number, `> 0`)
- `pre.substances.alcohol.daily_total_drinks` (number, `>= last_amount_drinks`)

### Substance validation rules
- If caffeine source is not `none`, require last time, last amount, and daily total.
- If alcohol is not `none`, require last time, last amount, and daily total.
- Daily total cannot be less than last amount (normalize up if needed).
- If source is `none`, clear granular detail fields.

## Activity and nap detail model (granular, pre-night)

### Exercise
- `pre.day.exercise.any` (bool)
- `pre.day.exercise_level` (`none` | `light` | `moderate` | `intense`)
- `pre.day.exercise.type` (`walking` | `cardio` | `strength` | `yoga_mobility` | `sports` | `labor` | `other`)
- `pre.day.exercise.last_time_utc` (ISO datetime)
- `pre.day.exercise.duration_minutes` (int, `>= 5`)

### Naps
- `pre.day.nap.any` (bool)
- `pre.day.nap_duration` (`none` | `short` | `medium` | `long`)
- `pre.day.nap.count` (int, `>= 1`)
- `pre.day.nap.total_minutes` (int, `>= 5`)
- `pre.day.nap.last_end_time_utc` (ISO datetime)

### Activity/nap validation rules
- If exercise level is not `none`, require exercise type, last time, and duration.
- If nap duration is not `none`, require nap count, total minutes, and last nap end time.
- If exercise/nap is `none`, clear their granular detail fields.

## Pain detail model (critical)

## Why this is required
The app must support different pain values per region and side.

Example required behavior:
- Mid back = `2`, side `both`, sensation `throbbing`
- Lower back = `9`, side `right`, sensation `sharp` + `shooting`

These must be stored as separate entries and compared separately.

## Pain area taxonomy
Use canonical area codes (not free text):
- `head_face`
- `neck`
- `upper_back`
- `mid_back`
- `lower_back`
- `shoulder`
- `arm_elbow`
- `wrist_hand`
- `chest_ribs`
- `abdomen`
- `hip_glute`
- `knee`
- `ankle_foot`
- `other`

## Pain entry schema (repeatable)
Each element in `pain.entries[]`:
- `entry_key` (string, deterministic key: `area|side`)
- `area` (enum)
- `side` (`left` | `right` | `center` | `both` | `na`)
- `intensity` (`0...10`, required)
- `sensations` (array, required min 1)
  - allowed values: `aching`, `sharp`, `shooting`, `stabbing`, `burning`, `throbbing`, `cramping`, `tightness`, `radiating`, `pins_needles`, `numbness`, `other`
- `pattern` (`constant` | `intermittent` | `unknown`, optional)
- `aggravators` (array optional)
- `relievers` (array optional)
- `notes` (optional text)

## Side rules
- If both sides have the same intensity/details, one entry with `side = both` is allowed.
- If left and right differ, store two entries:
  - `area|left`
  - `area|right`
- Do not collapse differing sides into `both`.

## Validation rules
- `pain.any = true` requires at least one `pain.entries` item.
- Every entry must have `area`, `side`, `intensity`, and at least one `sensation`.
- No duplicate `entry_key` inside one submission.
- `intensity` must be integer 0...10.

## UI flow for pain questions
1. Ask `pain.any`.
2. If yes, show area picker (multi-select).
3. For each selected area, open a detail popover/sheet.
4. User sets side + intensity + sensations.
5. Show completed chips in parent form.

Chip examples:
- `Mid Back (Both) 2/10`
- `Lower Back (Right) 9/10`

Submit is blocked until required area details are complete.

## Example payload (your case)
```json
{
  "pain.any": true,
  "pain.entries": [
    {
      "entry_key": "mid_back|both",
      "area": "mid_back",
      "side": "both",
      "intensity": 2,
      "sensations": ["throbbing"],
      "pattern": "intermittent"
    },
    {
      "entry_key": "lower_back|right",
      "area": "lower_back",
      "side": "right",
      "intensity": 9,
      "sensations": ["sharp", "shooting"],
      "pattern": "constant"
    }
  ],
  "pain.overall_intensity": 9
}
```

## Example payload (same area, different sides)
```json
{
  "pain.any": true,
  "pain.entries": [
    {
      "entry_key": "lower_back|left",
      "area": "lower_back",
      "side": "left",
      "intensity": 3,
      "sensations": ["aching"]
    },
    {
      "entry_key": "lower_back|right",
      "area": "lower_back",
      "side": "right",
      "intensity": 8,
      "sensations": ["sharp", "shooting"]
    }
  ]
}
```
This must not be stored as `lower_back|both` because left and right are different.

## Pre-Night-only add-ons
- `pre.day.activity_level`
- `pre.day.unusual_strain`
- `pre.sleep.planned_bedtime`
- `pre.sleep.position_planned`
- `pre.sleep.aids_planned`
- `pre.substances.caffeine.*` (all fields above)
- `pre.substances.alcohol.*` (all fields above)

## Morning-only add-ons
- `sleep.bedtime_actual`
- `sleep.wake_time`
- `sleep.latency`
- `sleep.awakenings`
- `sleep.quality`
- `sleep.rested`
- `sleep.position_actual`
- `morning.stiffness_duration`

## Comparison logic (Pre-Night -> Morning)

## Pairing
Compare records using the same `session_id` / `session_date`.

## Pain delta key
Pain is compared by `entry_key` (`area|side`).

## Delta calculation
For every `entry_key` in union(pre keys, morning keys):
- exists in both: `delta = morning.intensity - pre.intensity`
- only in morning: status `new`
- only in pre-night: status `resolved`

Examples:
- `mid_back|both: -1` (improved)
- `lower_back|right: +2` (worse)
- `neck|left: new`
- `upper_back|both: resolved`

## Delta persistence shape (computed layer)
Store or compute at read:
- `pain.delta.by_entry_key`
- `pain.delta.net`
- `pain.delta.max_worsened_entry`
- `pain.delta.max_improved_entry`

## Storage requirements for analytics
- Keep raw `pain.entries[]` in `responses_json`.
- Also write flattened indexes for easy querying (optional but recommended):
  - `pain.entry.mid_back|both.intensity = 2`
  - `pain.entry.lower_back|right.intensity = 9`

## Versioning rules
- Bump `questionnaire_version` when question IDs, enums, or validation rules change.
- Never mutate historical submissions in-place.
- If enums change, maintain migration mapping for trend continuity.

## Acceptance criteria
- Pre-Night and Morning both capture per-area, per-side pain independently.
- Different areas can hold different intensities and sensations in same submission.
- Morning view can display `+/-` delta by `area|side`.
- Stored data supports trend queries without losing area detail.
