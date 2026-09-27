# iPad analytics: parity review and first expansion

DOSETAP-76 remains In Progress. Owner confirmed phone 0.4.19 (78) and iPad Dashboard
0.1.0 (3) connected and delivered a report. That is basic pairing/arrival acceptance,
not field-by-field parity, security certification or release acceptance.

## Evidence and priority

The phone dashboard reads provider sleep, local questionnaires and dose records.
The initial iPad reads a validated snapshot with local source rows and explicit
provider-unavailable sections. Its median-only chart and hidden date axis did not
use the available screen space or explain eligibility well enough.

| Area | Present in nearby report | Next treatment |
| --- | --- | --- |
| Dose events | Occurrence times, treatment dates, identity evidence | First expansion below |
| Medication logs | Actual occurrence, amounts, recording/source metadata | Search now; calendar/formulation timeline next |
| Questionnaires | Pre-sleep, morning and normalized source rows | Typed answer/provenance projection before trends |
| Symptoms and quick logs | Source events, body maps, audit/cache rows | Source-linked night detail; deduplicate source evidence |
| Work schedule | Stored schedule evidence | Separate planned demand, actual work and transition context |
| Apple Health/WHOOP | Explicitly unavailable | Provider evidence/provenance transport is a separate slice |

Do not copy the phone's current-window classification into historical analytics.
No historical regimen is reconstructed from today's settings. Dose occurrence is
not sleep onset; bathroom events are not measured awake durations.

## First expansion: iPad 0.1.0 (4)

- Dark, adaptive overview with average and median spacing, usable-pair denominator,
  and dates containing dose records. No adherence percentage is implied.
- Calendar-based interval scatter chart with visible dates, median reference and
  nearest-record selection. Gaps are not connected or treated as zero.
- One-hour interval distribution: lower-inclusive/upper-exclusive bands, with 6h+
  containing all longer intervals. These are descriptive bands, not dosing windows.
- Middle 50% uses linearly interpolated quantiles, position `p * (n - 1)`.
  Mean, median, shortest/longest, histogram and monthly summaries use the same
  eligible positive, unambiguous pairs. Empty groups have no calculated value.
- Monthly median rows expose their own n and explicitly allow partial months.
- Missing pair, explicitly skipped, conflicting and paired states remain separate.
  The denominator is dates with dose events, not all calendar days or expected doses.
- Night detail shows occurrence dates/times and spacing. Duplicate/ambiguous source
  records are not arbitrarily selected. The iPad offers no record correction action.
- Medication-name search retains formulation labels, actual calendar dates,
  unknown times and recorded/source metadata. It does not combine drug amounts.
- Report contents lists source-row counts, which are not distinct observations.
  Unavailable provider data and uncollected amendment data are not zero.

Range correction: the initial iPad used civil midnight. Selected dose ranges now
use the phone's 18:00 treatment-night rule, anchored at snapshot capture so a frozen
report does not masquerade as live data. The v1 envelope lacks the phone's timezone;
this view explicitly uses the iPad timezone. Travel/source-timezone parity needs a
versioned source-zone contract, not an assumed match. Independent medication dates
continue using saved occurrence offsets.

## Follow-on slices

1. Extend the report with reviewed provider evidence: source identity, stage/awake
   intervals, coverage, endpoint basis and derivation version. Then add treatment
   sleep totals, dose-to-first-sleep and return-to-sleep views using the shared
   reviewed sleep contracts. Preserve conflicts and gaps.
2. Project questionnaire answers with completion/confirmation provenance. Add
   pain, sleepiness and day-demand trends only with explicit usable-answer counts;
   do not count duplicate source rows or untouched historical defaults as confirmed.
3. Add an independent daytime medication calendar/timeline and links to preceding
   and following sleep episodes, without shifting administration into yesterday's
   treatment-night bucket or inventing medication effects.
4. Add work-before/work-after and transition comparisons after defining source-aware
   cohort membership. Keep inferred schedule separate from confirmed attendance.
5. Expand filters, date detail, accessible chart alternatives and physician review
   export from these shared calculations. Avoid a combined treatment score.

## Validation and remaining gates

Core tests cover empty/single samples, quartiles, histogram edges, denominators,
monthly counts, midnight/DST and the exact 18:00 transition. Projection tests verify
unique occurrence timestamps and refusal to select ambiguous session records.
Same snapshot bytes cannot gain an eligible post-capture dose merely because
the report is reopened later. Date detail is a summary; competing source IDs and
specific conflict reasons are a follow-on, not a delivered full source drilldown.
Native normal/largest-text journeys and signed iPad installation are required for
this slice. Owner visual usefulness, exact real-report parity, VoiceOver, privacy,
provider transfer and release gates remain open. The phone remains build 78.
