# Agent Brief: DoseTap (XYWAV-Only)

## Goal
Implement a focused iOS/watchOS app for XYWAV dose timing that logs Dose 1 / Dose 2 / Bathroom events and schedules adaptive Dose 2 notifications strictly within 2.5–4 hours (150-240 minutes) after Dose 1.

## Core Features

### Primary Functionality
- **Single XYWAV regimen**: Dose 1 + adaptive Dose 2 with hard clamp 150-240 min
- **Event tracking**: dose1, dose2, bathroom, lights_out, wake_final, snooze
- **Night-first UI**: Dark theme with large countdown ring and 3-button interface
- **Adaptive timing**: Uses HealthKit sleep stages + HR/RR for optimal Dose 2 scheduling

### Routes & Navigation
- **Tonight** (primary): Dose 2 countdown with Take/Snooze/Skip actions
- **Timeline**: Merged night view with sleep stages, HR/RR, and event markers
- **Insights**: On-time %, natural-wake %, WASO metrics with CSV export
- **Devices**: Flic, HealthKit/WHOOP integration status
- **Settings → XYWAV**: Window configuration (150-240 min), defaults, nudge settings

## Design System

### Night-First Palette
- Base: `#0B1220` (ink)
- Surface: `#11192A`
- Cards: `#141F33` (6-8% elevation)
- Accent: `#22D3EE` (cyan-teal for primary actions)
- Positive: `#34D399`
- Warning: `#F59E0B`
- Danger: `#EF4444`

### Typography
- UI: Inter
- Countdown: SF Pro Rounded (tabular numerals)

## Data Model

```json
{
  "xywav_profile": {
    "dose1_time_local": "22:45",
    "dose2_window_min": 150,
    "dose2_window_max": 240,
    "dose2_default_min": 165,
    "nudge_enabled": true,
    "nudge_step_min": 10,
    "ttfw_median_min": 185
  },
  "dose_events": [
    {
      "type": "dose1|dose2|bathroom|lights_out|wake_final|snooze",
      "t": "ISO8601",
      "meta": {}
    }
  ]
}
```

## API Endpoints (Keep Only)
- `POST /doses/take`
- `POST /doses/skip`
- `POST /doses/snooze`
- `GET /doses/history`
- `GET /analytics/export`

## Removed Features
- ❌ Generic medication list/CRUD
- ❌ Add/Edit/Delete medication flows
- ❌ Pharmacy/refill actions
- ❌ Multi-drug adherence tracking
- ❌ All `/medications` endpoints

## Watch App
- Full-screen 3-button layout (Take/Snooze/Skip)
- Bold haptics for sleep-safe interaction
- Glance view with countdown ring

## Acceptance Criteria
1. No way to add/edit/view non-XYWAV medications
2. Tonight screen shows countdown ring with only Take/Snooze/Skip
3. Dose endpoints work end-to-end with insights rendering
4. Settings clearly states 2.5-4h rule with 150-240 min clamp
5. Timeline shows sleep stages with event markers
6. CSV export includes all XYWAV-specific metrics
7. Watch app has 3-button interface with haptics

## Component IDs for Testing
- `testid="btn-take"`
- `testid="btn-snooze"`
- `testid="btn-skip"`
- `testid="countdown-ring"`
- `testid="timeline-view"`
- `testid="insights-cards"`

## Constraints
- Never schedule outside [150, 240] minutes after Dose 1
- Default to 165 minutes if no adaptive data available
- Use HealthKit sleep for TTFW baseline calculation
- WHOOP API for historical data only (not live)

## Deliverables
- URL scheme: `dosetap://log?event=dose1|dose2|bathroom`
- Adaptive Dose 2 scheduler with hard clamps
- Night-first UI with countdown ring
- Timeline with sleep stage visualization
- XYWAV-specific insights and CSV export
- WatchOS 3-button interface
