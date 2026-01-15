# Sleep Planner / Typical Week (v1)

**Goal:** Give the user a deterministic bedtime plan tied to the active DoseTap night session (6PM rollover). The wake-by time is taken from the *next morning* of the active session key.

## Data model
- `TypicalWeekEntry { weekdayIndex (1=Sun), wakeByHour, wakeByMinute, enabled }`
- `TypicalWeekSchedule` = 7 entries, defaults to 07:30 enabled for all days.
- `SleepPlanSettings { targetSleepMinutes, sleepLatencyMinutes=15, windDownMinutes=20 }`
- Stored in `UserDefaults` (v1 keys `sleepPlan.schedule.v1`, `sleepPlan.settings.v1`).
- One-night override stored in-memory per `sessionKey` (does not mutate schedule).

## Math (SleepPlanCalculator)
- `wakeByDateTime(forActiveSessionKey:D, schedule, tz)` => date for **D+1** at that weekday’s wake-by time.
- `recommendedInBedTime = wakeBy - (targetSleepMinutes + sleepLatencyMinutes)`
- `windDownStart = recommendedInBedTime - windDownMinutes`
- `expectedSleepIfInBedNow = max(0, wakeBy - now - sleepLatencyMinutes)`

## UX
- **Settings › Typical Week & Sleep Plan**
  - Per-weekday wake-by time + enabled toggle.
  - Sleep plan knobs: target sleep mins, sleep latency, wind down.
- **Tonight**
  - Shows Wake by, Recommended in bed, Wind down start, “If in bed now”.
  - “Just for tonight” override (hour/min picker). Applies to active session only; reset button restores schedule.

## Critical rules
- Session key D uses the next morning (D+1) weekday for wake-by.
- Explicit timezone is used for all calculations.
- Overrides are scoped to the active session key and cleared on rollover change.
