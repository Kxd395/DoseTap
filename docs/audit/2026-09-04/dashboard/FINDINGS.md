# Dashboard findings

Authoritative record for this follow-up. Severity: P1 misleading analytics/correctness, P2 workflow/maintainability. Initial evidence is code-reviewed; each correction will record tests and runtime limits.

| ID | Severity | Evidence and impact | Correction / verification |
| --- | --- | --- | --- |
| DA-01 | P1 | DashboardTypes cutoff retains time-of-day while stored night keys parse at midnight; All claims all history but refresh generates 730 dates. Period edges and scope disagree. | Civil-night inclusive ranges, actual discovered history, boundary/DST/all-history fixtures. |
| DA-02 | P1 | Refresh combines SessionSummary, current-session DoseLog and separately normalized/inferred event timestamps; an orphan Dose 2 can become Dose 1. Canonical pre-sleep fallback exists in repository but refresh bypasses it. | Canonical recorded dose events and pre-sleep repository accessor; no inferred doses; identity ambiguity tests. |
| DA-03 | P1 | averageBathroomWakeMinutes assumes 5 minutes/event and UI presents measured awake time. Weekday/cohort charts use zero for missing groups and hide genuine all-zero results. | Show counts actually recorded; distinguish zero from unavailable. |
| DA-04 | P1 | Lifestyle control cohorts include missing answers as No. Skipped pre-sleep logs count as completed. Recurring stress driver counts count bedtime and morning twice yet say nights. | Explicit answered cohorts, completed logs only, per-night deduplication and sample counts. |
| DA-05 | P1 | Dose Effectiveness view labels arbitrary interval subgroups Optimal/Acceptable, includes all populated nights in denominator, and shorter intervals are colored improving. Period comparisons color every increase green. | Neutral recorded timing descriptions, observed populations, no treatment recommendation or unearned better/worse claims. |
| DA-06 | P1 | Combined sleep metrics silently prefer WHOOP over Health; sleep-stage bar shows only Deep+REM as entire sleep. | Explicit source choice/attribution, separate source coverage and full valid stage composition. |
| DA-07 | P2 | Refresh performs repeated SQLite reads across 730 dates on MainActor; cancellation can leave loading true and pull-to-refresh returns before work. Provider errors buried/log-only. | Read populated dates only, cooperative cancellation and single refresh ownership, visible source/error state. |
| DA-08 | P2 | Dashboard stacks all cards plus developer metric inventory; recent-night row fixed widths exceed phone content. Confidence describes completeness, not statistical confidence. | Clear sections, readable rows, coverage terminology, meaningful empty/partial states and UI proof. |
