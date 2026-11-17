# DoseTap: Single-Dose Nights and Dose-Pattern Views

Date: September 30, 2026
Status: Proposed product and data specification. No app code, medication instructions, alarms, source records, or earlier specifications were changed.

## Decision

Keep single-administration, explicitly omitted-dose, and unresolved-dose nights visible in the dashboard. Do not manufacture a Dose 1-to-Dose 2 interval for them. Add a Sleep & Dose Pattern view with By date, Compare patterns, and Paired intervals modes inside the existing dashboard, not another bottom-navigation tab.

The shared unit is a resolved sleep/treatment session for the selected nighttime medication or treatment. Daytime Adderall XR/IR, unrelated medications, tablet counts, and nap events do not increment the nighttime dose count. An administration can comprise multiple tablets or measured portions and still be one administration.

## Evidence boundary

The inspected September 24 export includes separate dose occurrence fields, normalized dose events, raw dose records, historical pre-night plans, recorded sleep segments, total sleep, post-Dose-2 sleep/coverage, and export exclusion reasons. Some records explicitly say "Dose 2 skipped"; other records say "Missing Dose 2 outcome". These are different source states. The screenshot establishes a scatterplot with dose interval on its horizontal axis, not the current source-code implementation.

Do not interpret a global exclusion reason as grounds to discard otherwise usable sleep data from every view. Inspect current code and migrations before implementation. Do not use the number of matches across raw and normalized event collections as the number of administrations.

## 1. Separate facts from derived categories

Retain these concepts independently:

- Historical prescribed regimen, with effective dates, medication/formulation identity, and instruction source/verification.
- A session-specific recorded plan, which is not automatically a verified prescription.
- Each reported administration, its actual amount/unit if known, slot association, occurrence time, recording time, precision, confirmation, and revision lineage.
- Expected dose outcomes: reported taken, explicitly not taken, not expected, outcome unknown, or pending.
- Session closure/completeness and any contradictory evidence.
- Selected sleep episode, sleep-duration definition/source, endpoint, and observation coverage.

Here, confirmation means explicit patient report or a documented source under the app's evidence policy. It does not mean the administration was independently witnessed or clinically verified.

### Derived display groups

| Label | Required evidence | Interval behavior |
| --- | --- | --- |
| Two doses reported | Two distinct relevant administrations reported taken; a completed count requires confirmation that the session record is complete | Calculate only from a valid selected D1/D2 occurrence pair |
| One dose, one-dose plan recorded | One relevant administration, explicitly complete session count, and a dated one-dose plan; preserve prescription verification separately | Not applicable: no second administration |
| One dose, Dose 2 not taken | Dose 1 reported taken and an explicit omission of expected Dose 2, without unresolved evidence of another administration | Not applicable: no second administration |
| One dose confirmed, plan unknown | Exactly one administration explicitly confirmed for the completed session, but historical plan unavailable | Not applicable; do not label the reason as planned or missed |
| Dose history incomplete | For example, one logged dose and no outcome for an expected/possible second dose | Unavailable: outcome unknown, not a confirmed one-dose night |
| No doses reported taken | Explicit completed report of no administration of the selected treatment | Not applicable; no medication-free or washout claim |
| Other / needs review | Extra administrations, D2-only sequences, simultaneous reported events, conflicting identities, or conflicting outcomes | Separate pair review; preserve all evidence |
| In progress | An open session with unresolved future/pending outcomes | Do not finalize as single-dose or missed |

Two reported doses with missing occurrence times remain two reported doses, not a one-dose night. Dose-count completeness and timestamp completeness are independent.

Do not label a one-dose night as "missed" simply because the current default regimen has two doses. Use the historical plan and explicit outcome. A saved plan alone does not establish what was taken.

## 2. Numeric interval rules

A valid D1-to-D2 interval is the elapsed UTC time between the selected reported occurrence timestamps from distinct relevant administrations in the same resolved session.

- Single administration: interval value is null with state `not_applicable` and reason `single_administration`.
- Second outcome unknown: interval value is null with state `unavailable` and reason `dose_outcome_unknown`.
- Two administrations reported, time unknown: interval value is null with state `unavailable` and reason `occurrence_time_missing`.
- Conflicting or nonpositive pair: retain reported values and flag `needs_review`; do not silently repair, reinterpret, or include in routine interval summaries.
- Do not substitute zero, a negative sentinel, infinity, expected reminder spacing, time to wake, skip-entry timestamp, session-close time, or next night's dose.
- A genuine report of simultaneous administrations is different from a single administration. Preserve the report and require appropriate review rather than deduplicating solely because timestamps match.

Neither the mean/median interval nor a fitted relationship may include fabricated positions for sessions without a valid interval.

## 3. Default mode: Sleep by night

Horizontal axis: treatment/session date. Use a session discriminator when multiple main sleep sessions share a date.
Vertical axis: observed sleep duration in the selected main sleep episode, with the source and boundary policy shown.
One plotted mark represents one session, not one dose.

This shared date axis permits two-dose, confirmed one-dose, confirmed zero-dose, and incomplete-dose-history sessions to coexist without pretending they have a between-dose interval.

If sleep duration is unavailable, retain the session in an aligned status strip or table and the coverage count. Do not plot it at zero sleep. Do not connect lines across missing observations as though sleep was observed.

### Display roles

- Prefer a single neutral plotted color plus a separate labeled work-phase strip for the default view.
- Use distinct, consistent count marks for fully reported counts: circle for two, square for one. Use an outlined diamond for unresolved dose history. A clearly labeled 0 badge can identify a confirmed no-dose session.
- Put the exact subtype in a visible selected-session badge/detail: `1: planned`, `1: D2 not taken`, `1: plan unknown`, `2`, `0`, or `?`.
- Do not use an icon that depicts two pills to mean two administrations; pill quantity and administration count differ.
- Do not use red/green as good/bad treatment outcome judgments.
- Work phase remains a labeled strip or filter by default. In an optional combined view, work-phase color can coexist with count shape, but the role assignment must be explicit and accessible. Do not simultaneously encode spacing-reference status or wake method into more marker variations.
- The old scatterplot's circle/diamond meaning was reference status. Do not reuse that legend unchanged when switching to dose-count encoding. Generate the legend and plotted styles from the same view-specific mapping.
- Unknown dose history is not unknown sleep, and unknown work phase is not unknown dose count. Do not conflate those dimensions.

## 4. Comparison mode: Sleep by dose pattern

Use labeled categorical groups with individual sleep observations. On mobile, horizontal rows allow longer labels; use one common duration scale across groups. On larger screens, categorical columns are also acceptable.

Primary groups: two doses; one dose with a recorded one-dose plan; one dose with D2 explicitly not taken; one dose with plan unknown. Show confirmed no-dose and other reviewed patterns when present. Keep unresolved histories in a separate, clearly labeled section rather than pooling them with known one-dose nights.

For usable numeric durations, show the number of contributing sessions and a median plus a labeled middle-50% spread where meaningful. Retain individual observations when groups are small; no hard-coded clinical minimum or recommendation threshold.

Provide filters for the selected medication/formulation, historical regimen period, work phase, sleep source/boundary policy, and date range. Avoid comparisons that silently change the definition of sleep between groups.

A single administration does not imply a particular total amount or a reduced dose. Show known actual amounts separately and mark unknown totals. Do not compute actual nightly totals from prescribed or pre-night planned amounts.

## 5. Keep the original interval plot with a companion

The numerical scatterplot remains restricted to valid paired occurrence times and an available selected sleep measure.

In the same dashboard card or section, provide a clearly separate categorical panel titled `Nights without a usable D1-to-D2 interval`.

- Place it beside the scatterplot on wide screens and below it on phones.
- Use the same sleep metric, source policy, and numeric sleep scale so vertical/length comparisons remain valid.
- Its category axis is explicitly categorical. It is not an extension, zero point, or broken section of the numerical interval axis.
- Separate structural absence of an interval from incomplete dose timing/outcome evidence.
- Provide counts and navigation for sessions whose sleep is also unavailable.
- Filter and selection state stays synchronized across both panels.

If the selected outcome is `sleep after Dose 2`, no value exists for a session without Dose 2. Do not insert that session's total sleep as a substitute. Offer total main-sleep duration as the cross-pattern comparison metric instead.

## 6. Sleep definitions

Default cross-pattern outcome: recorded asleep duration within a consistently selected main sleep episode, independent of how many medication events exist.

Separately label:

- Observed main-sleep duration.
- Patient-estimated main-sleep duration, when available and selected as a separate source.
- Observed sleep after Dose 1 within the defined episode.
- Observed sleep after Dose 2, only when Dose 2 was reported taken and its occurrence time is usable.
- Elapsed time from an administration to a named endpoint, which is not sleep duration.
- Sleep opportunity and observation coverage.

Sleep before the first dose can legitimately belong to an independently reviewed main-sleep episode, but is not post-dose sleep. Naps are separate unless the user selects a separately defined whole-day measure. No-dose sessions must remain possible without triggering a medication session.

Do not infer awake time from missing device segments, reconstruct stage sequences from stage totals, or call a patient-confirmed sleep window clinically verified. Deduplicate overlapping source segments under one documented policy.

## 7. Data fields to map or add

Proposed names, not claims about the current codebase:

- `session_id`, `treatment_id`, `medication_id`, `formulation`, `historical_regimen_version_id`.
- `planned_administration_count`, `plan_source`, `plan_recorded_at`, `plan_verification`.
- `reported_administration_count`, `count_completeness`, `count_confirmed_at`, `report_source`.
- Per-slot `expected`, `outcome`, `outcome_reason`, `occurrence_time`, `recorded_at`, `precision`, `source_event_id`, and `revision_id`.
- Per-administration actual amount/unit and amount-confirmation state.
- `dose_pattern`, `pattern_derivation_version`, `pattern_evidence_ids`, `conflict_reasons`.
- `interval_value_minutes`, `interval_state`, `interval_reason`, and selected pair IDs.
- `main_sleep_episode_id`, `sleep_metric_id`, `sleep_source`, `boundary_basis`, `coverage`, `sleep_minutes`.
- Work-phase label, source, and version; next-day outcome links with explicit date/assessment time.

Reuse existing outcome/reconciliation machinery where possible. Inspect current normalized events and their relationship to raw event records; never count both representations.

## 8. Reconciliation without another questionnaire

When a completed session has one administration logged and no final second-dose outcome, offer a short review inside the existing morning flow:

`Only Dose 1 is logged. What happened with Dose 2?`

Answers should support: taken (enter/confirm occurrence and amount if known), not taken (optional reason), no second dose was planned (preserve source as patient report and reconcile the historical plan), unsure, or answer later.

Do not preselect an answer or ask again when an explicit, nonconflicting outcome already exists. A reminder dismissal, absent device wake signal, and a questionnaire completion are not proof of administration or omission.

A retrospective omission's recording time is not a fictitious administration timestamp. When a later correction changes the outcome, recompute display categories and all affected summaries from the revised evidence, preserve the original report, and do not generate retrospective catch-up alarms.

## 9. Interpretation and physician export

Use descriptive wording such as `Sleep on nights when D2 was reported not taken`, not `Sleep gained by skipping D2`.

A reported reason such as sleeping through a reminder can relate to the same sleep outcome being compared. A longer sleep observation on an omission night therefore does not establish benefit from the omission. Do not encourage deliberate skipping to create a comparison group.

Include per-pattern night counts, metric-specific sleep/outcome coverage, actual amounts when known, work phase, documented omission reasons, and next-day symptoms/naps when collected. Comparisons of nighttime duration are not the same as comparisons of treatment benefit or safety.

Keep ambiguous and serious reported events visible in review/appendix even when excluded from numeric analyses. Provide since-visit and six-calendar-month ranges with subgroup counts and historical regimen-change markers.

## 10. Acceptance checks

1. A completed report of one administration produces no numerical D1-to-D2 interval.
2. One log plus an unresolved D2 outcome stays incomplete, not confirmed one-dose.
3. A historical one-dose plan is not labeled a missed second dose.
4. Two reported administrations with one unknown time retain the count but have unavailable spacing.
5. Confirmed no-dose sleep remains visible without requiring a dose event to create a sleep record.
6. Missing sleep is absent/unknown in the metric, never zero.
7. Total main-sleep duration uses the same definition and source policy across dose-pattern groups.
8. Post-D2 sleep is not applicable for a night without D2, never replaced with total sleep or zero.
9. Unknown D2 timing produces unavailable post-D2 sleep rather than an invented boundary.
10. The interval chart has no fake x=0, negative, expected-time, or wake-time point for omitted doses.
11. Categorical companion categories remain visually separate from the numeric interval axis.
12. Interval and sleep summaries have independent eligibility and displayed denominators.
13. A `Dose 2 skipped` export reason does not automatically suppress valid sleep from all dashboards.
14. Raw and normalized versions of the same administration do not double the count.
15. Revision/correction recomputes classification while preserving source lineage and earlier shared reports.
16. Work-phase colors and dose-pattern marks have explicit, nonconflicting legends and text alternatives.
17. A dose-pattern legend cannot inherit the old reference-status semantics silently.
18. Group taps or previous/next controls reveal exact values without pixel-perfect selection.
19. Midnight, travel, and daylight-saving changes do not pair unrelated sessions or change real elapsed intervals.
20. Open sessions remain pending until the relevant outcomes are resolved or explicitly left unknown.
21. Extra administrations and identical timestamps are flagged without inventing a clean one-dose or two-dose history.
22. Known count with unknown actual amount does not generate a total from the plan.
23. Morning reconciliation does not repeat already answered nonconflicting questions or automatically select omissions.
24. Exports match screen filters, definitions, category rules, source policy, and versioned calculations; no dose-change recommendation is generated.

## Source notes

Observed inputs: September 24 `insights_bundle(1).json` and supplied dashboard screenshot. This is a proposed display/data contract, not a clinical validation or implementation audit of the current app.

Design references consulted September 30, 2026:

- Apple Human Interface Guidelines, Charts: https://developer.apple.com/design/human-interface-guidelines/charts
- W3C WCAG 2.2 Understanding 1.4.1, Use of Color: https://www.w3.org/WAI/WCAG22/Understanding/use-of-color

## Action log

Created this standalone addendum. Preserved all prior files. No production code, health data, medication plan, alarm, or appointment was changed.
