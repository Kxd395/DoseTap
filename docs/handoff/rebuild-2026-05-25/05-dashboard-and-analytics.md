# 05 — Dashboard and Analytics

## Dashboard Product Goal

The dashboard should answer: "What happened, how consistent was my dose timing, and what patterns are worth discussing with a clinician?"

It must not answer: "What medical decision should I make?" DoseTap can surface patterns; it must not prescribe changes.

## Required Cards

### Dose Timing Summary

- Dose 1 time distribution.
- Dose 2 interval distribution.
- In-window, early, late, skipped, and extra-dose counts.
- Target interval adherence.
- Week-over-week trend.

### Dose Effectiveness

- Correlation between dose interval zone and sleep/morning outcomes.
- Minimum sample threshold before showing conclusions.
- Clearly label data as observational.
- Segment by optimal, acceptable, and non-compliant intervals.

### Night Score

- Keep a transparent score breakdown.
- Show component weights.
- Do not hide missing data behind a single score.

### Sleep Summary

- Total sleep.
- Sleep efficiency.
- Wake events.
- Naps.
- Sleep stages when available from HealthKit/WHOOP.

### Morning Outcomes

- Sleep quality.
- Rested/grogginess.
- Readiness for day.
- Anxiety, symptoms, sleep inertia, notable safety flags.

### Integration Data Quality

- HealthKit connected/missing/revoked.
- WHOOP connected/missing/stale/rate-limited.
- Manual-only nights.
- Completeness percentage by week.

### Medication and Context

- Medication entries.
- Pre-sleep caffeine/alcohol/exercise/stress.
- Sleep therapy usage.
- Notes presence without exposing notes on dashboard cards.

## Analytics Rules

- Use UTC for storage and local timezone for user-facing grouping.
- Group by session ID where available; use session date only as a fallback.
- Do not compute cross-night trends on fewer than 3 nights.
- Do not show correlation claims on fewer than 7 pairable nights.
- Show confidence/data-quality warnings for sparse data.
- If integration data conflicts, show source-specific values and prefer user-visible provenance over silent merging.

## Data Model Needs

Create or formalize a nightly aggregate object:

- `sessionId`
- `sessionDate`
- `dose1At`
- `dose2At`
- `doseIntervalMinutes`
- `dose2State`: on-time, early, late, skipped, extra
- `sleepEvents`
- `preSleepLog`
- `morningCheckIn`
- `medicationEvents`
- `healthKitSummary`
- `whoopSummary`
- `dataCompleteness`
- `diagnosticFlags`

The aggregate should be deterministic, cacheable, and invalidated only by changed source records.

## Dashboard Testing

Required tests:

- No-data dashboard.
- Manual-only dashboard.
- HealthKit-only dashboard.
- WHOOP-only dashboard.
- Conflicting HealthKit/WHOOP values.
- Missing check-in.
- Skipped dose 2.
- Late dose 2.
- Extra dose.
- DST and timezone boundary nights.
- Large dataset performance.
