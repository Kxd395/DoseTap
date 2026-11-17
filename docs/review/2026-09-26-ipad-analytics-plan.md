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

## First expansion: iPad 0.1.0 (5)

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

### Owner feedback: the dashboard needs a full overhaul

After the interval expansion, the owner confirmed the connection works but said
the dashboard is still missing too much. The two attached examples show the same
iPhone dashboard, including current/prior sleep, sleep quality, interval-versus-
sleep and natural/alarm comparisons. They are requirements examples, not proof
of iPad parity or acceptance. The interval-only delivery is not the completed
dashboard overhaul.

The revised information architecture starts with a cross-domain Overview, then
dedicated Dose timing, Medications, Sleep & check-ins, and Night review workspaces.
Data availability belongs beside the measurements, not only in an audit page.
Daytime symptoms and work context become additional workspaces once their typed,
source-aware projection is available. No empty chart may imply observed zero.

The first follow-on uses questionnaire rows already present in the saved report.
Legacy morning ratings may contain defaults: show stored ratings with explicit
unknown confirmation provenance, not freshly confirmed outcomes or a clinical
effectiveness score. Preserve completed, partial, skipped and conflicting states.
Provider sleep remains a separate, necessary transport addition.

Provider implementation contract is refined by the
[collection/comparison inventory](2026-09-26-dashboard-data-comparison-inventory.md):
prepare bounded raw HealthKit samples with original IDs, boundaries, categories
and provenance before the nearby request deadline. Do not run the current
`fetchSleepEvidence` interval resolver across months of samples; resolve bounded
reviewed windows after transfer. Retain unknown coverage and conflicts. WHOOP source sleep and
recovery records must preserve nullable values, naps, scoring state and separate
endpoint failures. Ask for inclusion on the phone, query outside the SQLite
transaction, declare query bounds and query times, and fence cancellation or
connection changes. Do not infer awake intervals from WHOOP aggregate stages.
Cross-provider averages and guessed sleep endpoints are excluded. The direct
nearby transport does not authorize or require cloud storage.

Source audit also confirmed the phone aggregate accepts an equal-timestamp dose
pair (`exactIntervalMinutes >= 0`), while iPad eligibility requires positive
spacing. The screenshot cannot distinguish exact zero from a positive subminute
pair. Correct shared phone eligibility and test subminute, zero, reversed, missing
and midnight cases separately. Duplicate/skip precedence also differs and needs
an explicit shared policy before claiming calculation parity.

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

Local validation: 817 core XCTest,20 nearby XCTest and43 Swift Testing passed;
7 iPad cache tests and2 expanded native UI journeys passed. Journeys cover medication
filtering, night detail, report inventory and largest text. Screenshot review found
narrow metric columns at accessibility sizes; those now use a single column and
range selection becomes a menu. Both native journeys passed again after that fix.
Signed iPad build4 succeeded. Real-record visual usefulness and parity stay open.

PR review caught an All time upper-bound gap. Build 5 applies the captured-night
cutoff to All time as well, with tests on both sides of 18:00. Build 4 was installed
as the earlier candidate; build 5 supersedes it. Source rows are not rewritten.

## Overhaul stage 1: answer-aware navigation

The next iPad candidate is 0.1.0 (6); phone remains 0.4.19 (78).
Overview becomes a navigation summary with separate dose timing, medication,
sleep/check-in and record-review cards. Dose timing retains the existing detailed
charts in its own workspace. Sleep & check-ins reads the original morning,
pre-sleep and night-outcome records, never duplicate normalized copies as extra
observations. Stored quality points carry an explicit confirmation-unknown warning;
no effectiveness comparison is derived from those historical ratings.

This stage does not deliver wearable sleep charts, previous-period comparisons,
work cohorts, symptom timelines or full source parity. These remain required
stages of the requested overhaul, not owner acceptance closed by navigation work.
PR #68's interval checkpoint merged as 4c7fcdeaadec2c2e9589bfa19cf4c71cec150f4b
with all required checks passing before this follow-on.

Stage-1 local validation: 825 core XCTest, 20 nearby XCTest and 43 Swift Testing
passed; 8 native cache tests and 2 normal/largest-text UI journeys passed. Native
screenshots were inspected for the new home, questionnaire chart and large text.
An initial fixture compatibility failure led to preserving unassigned rows; a
subsequent simulator preflight launch failure was resolved by explicitly booting
the dedicated iPad and running tests serially. Neither failed run counts as a pass.
Final result: Test-DoseTapDashboard-2026.09.26_21-36-27--0400.xcresult.
Signed iPad build 6 succeeded. Installation and owner acceptance are separate.
