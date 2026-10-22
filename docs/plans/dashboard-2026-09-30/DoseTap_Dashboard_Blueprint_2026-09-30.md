# DoseTap: Dashboard and Interval-Explorer Blueprint

Date: September 30, 2026
Status: Proposed product specification. No app code, source data, alarms, or medication instructions have been changed.

## Purpose and evidence boundary

Organize the existing sleep, dose-event, context, and morning-check-in data into focused views. Extend those views when the proposed detailed medication, nap, and symptom logs become available.

The data mapping below is based on the supplied September 24 export, `insights_bundle(1).json`, and the September 30 dashboard screenshot. The screenshot establishes a display, not its implementation. The export does not establish the current production schema or any changes made after September 24. Validate current models and migrations before implementation.

The screenshot's circle/diamond legend denotes inside/outside a built-in spacing reference, not Dose 1 versus Dose 2. Its 150-240 minute reference is explicitly not a historical prescription. Preserve that distinction in every view and export. Do not call the band safe, compliant, optimal, or physician-approved.

## Product organization

Keep the existing bottom navigation. Add a Dashboard view picker instead of additional bottom tabs or an endless stack of equal-weight cards:

- Timing: session replay, aligned session comparison, interval explorer, sleep opportunity.
- Sleep & Naps: main sleep, nap episodes, and daily sleep totals.
- Patterns: selected context comparisons, morning outcomes, and treatment-period trends.
- Medications: logged administrations, schedule comparison, optional reviewed models.
- Physician Review: since-visit summaries, monthly trends, and selected event details.

Make data completeness available in every view and as a dedicated Review Data panel.

## Shared interaction contract

1. Show a single primary question and one focal visualization before secondary controls.
2. Preserve date range, selected session, source policy, and applicable filters across views. Explain when a filter does not apply.
3. Support 7 days, 28 days, 90 days, 6 calendar months, 12 calendar months, since last completed visit, and custom dates. These are product settings, not clinical instructions.
4. In portrait, display one chart at readable width with its key values underneath. Use a detail sheet for selection. On wider displays, the same selection can populate a side panel and linked charts.
5. Provide tap-to-select, previous/next observation controls, reset, and a table alternative. Do not require pixel-perfect taps or hover.
6. For overlapping points, present the candidate observations for explicit selection. Do not silently choose one or displace continuous values to fake separation.
7. Show date/timezone, units, source, data freshness, and eligible/available counts. Essential reference qualifications remain visible without opening a tooltip.
8. Keep plot marks, legend symbols, and accessible descriptions driven by the same semantic mapping. Do not use color alone.
9. Use separate panels for unlike units; do not place minutes, heart rate, and symptom scores on a misleading common scale.
10. Preserve last available data with an offline/stale indication. A refresh or late import must not erase a selected observation without explanation.
11. Export the same filter state, definitions, denominators, and source choices as the screen. Include an as-of time and derivation versions.

## Dashboard 1: Session Replay and Aligned Night Comparison

### Question
What happened within a sleep session, and how does its sequence compare with other sessions?

### Visual
A horizontal timeline for a single session, expanding to one row per session for a week or month. Label rows by treatment date plus a session discriminator if more than one session belongs to a date. Retain independent IDs; a date is not a unique session key.

Show:
- Dose 1 and Dose 2 as explicitly labeled event markers.
- Device-observed asleep and awake intervals, plus unobserved intervals as a distinct state.
- Separately labeled patient-reported wake and device last-observed-sleep-end markers.
- Optional food, recorded reminders, bathroom, and water events.
- Morning outcomes in a separate aligned column rather than more marker colors.

### Alignment modes
- Clock time, with day rollover labels: compare schedules.
- Elapsed since Dose 1: compare second-dose placement and subsequent observations.
- Elapsed since Dose 2: inspect post-dose sleep and wake endpoints.

Use one alignment mode at a time, clearly identified. Real duration uses UTC elapsed time; local clock rendering must show timezone/offset transitions.

### Existing evidence
`dose1TimeUTC`, `dose2TimeUTC`, `normalizedEvents`, `healthKit.recordedIntervals`, `healthKit.finalWakeBasis`, `healthKit.finalWakeUTC`, and `context.wakeFinalLoggedAtUTC` are represented in the export.

### Limitations
The inspected `recordedIntervals` expose asleep flags, not stage labels for each interval. Aggregate core/deep/REM totals cannot reconstruct a stage-by-stage hypnogram. Render observed sleep/awake first. Add stages only from appropriately timestamped stage records.

A pre-sleep questionnaire completion is not confirmed lights out. Do not reuse the current event label without checking its originating details.

## Dashboard 2: Interval Explorer

### Question
How long was the gap between two specifically defined events, how variable was it, and which outcomes were recorded alongside it?

### Controls
Start event, end event, pairing policy, date range, eligible source choices, and one outcome to compare. Offer curated presets before a fully custom pairing control.

### Presets and dependency rules
| Preset | Definition | Dependency |
| --- | --- | --- |
| Dose 1 to Dose 2 | Occurrence of selected Dose 2 minus occurrence of selected Dose 1 within the same resolved session | Both administration times; pair review |
| Food to Dose 1 | Dose 1 minus last explicitly recorded food-finish event selected for that session | Verified relevant food timestamp |
| Dose 2 to subsequent observed sleep | First qualifying observed return-to-sleep boundary after the administration, under a documented boundary rule | Segments and coverage; not a medication-onset measure |
| Dose 2 to last observed sleep end | Device endpoint minus Dose 2 | Valid endpoint and source label |
| Dose 2 to reported final wake | Patient-reported wake minus Dose 2 | Confirmed occurrence, not submission time |
| Dose 2 to required wake | Required wake minus Dose 2 | Historical schedule source; negative means after the recorded requirement, not invalid arithmetic |
| Last caffeine to Dose 1 | Dose 1 minus relevant recorded last caffeine time | Timestamp; mass is not required for this timing view |
| XR administration to IR administration | Selected IR minus selected XR, with an explicit day/session association | Detailed administration events with formulation |
| Last daytime medication to next main sleep | Next selected main-sleep boundary minus selected administration | Defined association and sleep boundary |
| Nap end to next main sleep | Next main-sleep start minus nap end | Individual nap timestamps |
| Reminder deviation | Administration occurrence minus historical scheduled reminder | Saved schedule; not proof the alert fired |
| Delivered-alarm-to-administration | Administration occurrence minus recorded delivery event | Reliable delivery telemetry, distinct from schedule |

### View modes
- By date: individual dots with exact-value selection; do not connect over missing observations.
- Distribution: labeled duration bins and observation counts, with the individual source records reachable.
- Compare outcome: scatter plot with one paired observation per clearly stated unit and no automatic treatment recommendation.

For spacing references, use a visible source/version label. When comparing groups, keep below-reference and above-reference observations separate instead of combining them as one 'outside' group. Exact inclusive boundary logic is part of the reference definition.

### Pairing safeguards
Do not pair doses from unrelated sessions or automatically pick the nearest timestamp. Do not convert a missing/explicitly skipped dose into zero spacing. Do not silently repair nonpositive administration spacing. Preserve genuine unusual reports for review.

A reported duration category such as `lt_15m` remains a category or bounded observation, not exactly 7.5 or 15 minutes. If the person is already classified asleep across the administration timestamp, expose a source discrepancy rather than inventing zero return-to-sleep latency.

## Dashboard 3: Sleep & Naps

### Question
When does sleep occur across the full day, how much nap sleep is recorded, and which naps were planned or unplanned?

### Visuals
- Calendar-style time rows: one row per day with main sleep and individual nap intervals on a common clock axis.
- Daily main-sleep and nap-duration bars, separated by classification, with a completeness row.
- Optional paired pre/post-nap symptom display only when both observations were explicitly collected with compatible scales and timestamps.

### Data requirements
Existing coarse `preSleep.napToday` and pre-night nap answers may support a legacy reported-nap-status view. They are not substitutes for individual nap start/end times, estimated sleep duration, planned/unplanned status, or benefit ratings.

Detailed nap views depend on the new nap-event feature unless already implemented after the export. Duration-only naps belong in totals with clear precision, not at an invented clock time.

### Counting rules
Preserve rest-window duration separately from estimated asleep duration. Link duplicate manual/device records; never add overlapping observations twice. Count each episode once even when displaying it across midnight. Mark no-nap-confirmed, partial logging, and unreviewed day distinctly.

A fixed local-day total may cover 23 or 25 hours around daylight-saving changes. Do not label it a strict rolling 24-hour total. For rolling 24-hour views, use an explicit elapsed-time interval and clip/deduplicate episodes consistently. Episode counts and duration allocation may use different documented rules.

Ending a nap cannot reset dose history, main-wake association, nighttime session state, or medication alarms.

## Dashboard 4: Sleep Opportunity and Continuity

### Question
Was the available interval short, or was less of that interval recorded as sleep?

### Visual
For each selected session, show a horizontal span from Dose 2 to a named endpoint. Within an observed window, draw asleep, awake, and unobserved intervals at their actual locations. Show required wake as an independent marker when it differs from the observed endpoint.

Put exact interval length, recorded asleep minutes, recorded awake minutes, and coverage beside the row.

### Important accounting
For one common endpoint and window, asleep + awake + unobserved can partition elapsed time only after deduplication and conflict handling. Do not infer every gap is awake. Data before/after the observed window does not become measured awake time.

Do not stack time in bed, total sleep, and post-Dose-2 sleep as additive categories. They overlap. Do not use an absent or sentinel `inBedMinutes` value to calculate a sleep-efficiency percentage.

A later Dose 2 reduces time before a fixed required wake arithmetically. Present sleep opportunity beside post-dose sleep rather than labeling an association as reduced medication effectiveness.

## Dashboard 5: Context and Morning Outcomes

### Question
How do the recorded patterns differ across selected contexts without confusing association with cause?

### Context choices
Reported work demand versus off day, transition days, Dose 2 wake method, final-wake method, sleep duration, food timing, verified caffeine timing/amount, pain, stress, and confirmed regimen periods.

### Visual
Small groups of individual dots with a median and a clearly labeled middle-50% spread for numeric durations. Use category counts/distributions for categorical or ordinal responses where that is more appropriate. Display group counts and missing/unknown counts.

Offer a chronological set of separate panels for sleep quality, grogginess, recovery categories, and symptoms. Do not translate recovery categories into exact minutes or merge unlike rating scales. Compare compatible questionnaire versions only.

### Existing evidence and cautions
The export represents `morning.grogginess`, `sleepInertiaDuration`, `mentalClarity`, `sleepQuality`, `stressLevel`, explicit following-day demand, and inferred schedules. Reported and inferred schedules must remain distinguishable. Dose 2 awakening is different from the final morning awakening.

Use only valid, confirmed caffeine mass values in amount comparisons; do not assume beverage volume is caffeine milligrams.

Show the chosen outcome time relative to the exposure: preceding main sleep, following waking day, or next main-sleep episode. A variable observed after an outcome must not be described as an earlier predictor.

Do not display a 'best dose', 'ideal interval', automatic causal conclusion, or correlation ranker. A series with no variation cannot identify which timing works better. Counts from different context groups are not randomized comparisons; repeated observations come from the same individual.

## Dashboard 6: Medication Logs and Reminder Review

### Question
What was reported taken, when, and how did those logs compare with the saved schedule?

### Visual
Separate rows for named medication/formulation. Use labeled administration markers, documented scheduled markers, and separate nap/sleep/symptom rows on the same time axis. Amount remains text or a defined amount scale per medication, not one mixed-milligram axis.

Show actual-versus-scheduled deviation as a signed dot plot when the historical schedule is known. Positive/negative values describe timing, not safety or nonadherence by themselves.

### Optional estimates
A reviewed medication-specific estimate is a separately toggled model layer. Preserve XR/IR administration identities even if a reviewed compatible model produces a combined active-drug view. Model output must have defined units, version, assumptions, and history completeness. Do not add unrelated medications into one total or imply measured blood levels.

Existing nighttime events can support a basic event timeline; detailed daytime schedules and actual administered amounts depend on the medication logging work discussed previously. Do not backfill amounts from the planned prescription.

### Reminder limitations
Scheduled, delivered, acknowledged, snoozed, and taken are separate facts. No acknowledgement is not proof of sleep or an omitted dose. An app calculation is not proof an operating-system alarm fired. Logging must not auto-send health information to a physician.

## Dashboard 7: Physician Review and Data Completeness

### Question
What changed over the actual interval between completed visits, and how complete is the evidence?

### Visuals
- Six-month or since-visit overview with treatment-change markers.
- Monthly medians/spread and counts for suitable durations, with rated outcomes shown on their original scales.
- Recent 14/28-day detail alongside the full interval, not replacing it.
- Bookmarked events and top visit questions.
- Completeness matrix: dates or months on one axis, data types on the other.

Completeness states: recorded, partially recorded, not recorded, not yet collected, needs review, and not applicable. Confirmed absence is a substantive response, not the same state as unrecorded. Integration disabled is not a repeated clinical failure.

The matrix must inspect actual values and relevant confirmation/source evidence, not only the presence of a metric name in `metricProvenance` or a source-level availability boolean.

Every metric has its own denominator. A missing morning check-in does not erase a valid dose-spacing observation, and a valid spacing observation does not imply a complete sleep/symptom record.

Add explicit source disagreement review for patient wake versus device last sleep end and session-identity conflicts. Analytical exclusion never silently deletes the raw report or hides a serious reported event from the review appendix.

### Export
A concise 1-2 page overview, monthly details, and optional event/CSV/JSON appendices. Preserve selected identifiers, timezone, coverage, reference source, filters, and model/derivation versions. Require preview and explicit share action. Preserve snapshots already shared; later corrections create a new version.

## Source mapping summary

| Domain | Observed source names | Do not infer |
| --- | --- | --- |
| Doses | `dose1TimeUTC`, `dose2TimeUTC`, `normalizedEvents` | Actual amount from a plan; taking from an alarm |
| Sleep | `healthKit.recordedIntervals`, `sleepOnsetUTC`, `finalWakeUTC`, `finalWakeBasis` | Full sleep-stage timeline from totals; all gaps are awake |
| Post-dose sleep | `collectedNight.estimatedSleepAfterDose2Minutes`, endpoint/coverage fields | Elapsed time equals sleep |
| Food/caffeine | `lastFoodFinishedAt`, `lastFoodToDose1Minutes`, `context.caffeineLastIntakeAtUTC` | Mass from beverage volume; missing food event means fasting |
| Morning | `morning`, `checkInSubmissions` | Defaults were explicitly answered; category midpoint is exact |
| Schedules | `explicitNextDayDemand`, `scheduleDayType`, `scheduledWakeByUTC` | Inferred schedule is confirmed attendance or prescribed dosing |
| Alarms | `context.alarm`, saved reminder details | Scheduled equals delivered or heard |
| Naps | `preSleep.napToday`, questionnaire nap fields | Individual episode times from a coarse daily answer |
| Quality | `identityResolution`, `dataQualityFlags`, `sourceAvailability`, `metricProvenance` | A listed provenance key guarantees a populated value |

## Proposed technical structure

Discover the actual project architecture before creating files. These are responsibilities, not claimed existing paths:

- One versioned metric registry owns units, eligible inputs, pairing, endpoints, missing states, and historical references.
- One interval derivation service calculates elapsed time from occurrence timestamps.
- One selected-source/identity policy is shared by screens and exports.
- Reusable components: session timeline, aligned time rows, numeric dot plot, distribution plot, comparison plot, coverage matrix, and observation detail sheet.
- On native iOS, evaluate Swift Charts against the project's deployment target and interaction needs. Web implementations should retain the same metric contract without assuming a particular renderer.
- Recompute on data edits/imports/filter changes. Do not continuously poll historical sleep data or recalculate every chart each second. A visible elapsed counter can have its own limited cadence.
- Keep the main view to one focal chart and no more than a few supporting panels. Aggregate the six-month overview by week/month and load daily detail on demand without discarding raw history.
- Preserve selections by stable IDs across refreshes. Cache derived results by source policy and derivation version.
- Protect raw health records from diagnostic/crash logs and public issue trackers. Use explicit user authorization for exports.

## Acceptance checks

1. The screenshot's reference legend is never described as Dose 1 versus Dose 2.
2. The visible band qualification states built-in/reference-only rather than safe or prescribed.
3. Plot and legend obtain matching color/shape mappings from one source.
4. Each view identifies whether a mark is an event, session, day, or monthly aggregate.
5. A date containing multiple sessions is not collapsed without an explicit reviewed association.
6. Clock-time and dose-aligned views select the same underlying session and preserve true elapsed intervals.
7. A missing or skipped Dose 2 is not plotted at zero spacing.
8. Retrospective occurrence time, not submission time, drives intervals.
9. Nonpositive or conflicting administration timing remains available for review without fabricated correction.
10. Categorical return-to-sleep/recovery responses are not plotted as exact minutes.
11. An already-asleep segment crossing a dose timestamp is not silently labeled zero latency.
12. Manual and device observations overlapping one nap are not double-counted.
13. A duration-only nap contributes only to compatible totals, not an invented clock position.
14. Incomplete timers remain incomplete until resolved.
15. Confirmed no naps, partial nap logs, and an unreviewed day are distinguishable.
16. Asleep/awake/unknown segments reconcile within one declared window after source conflict handling.
17. Time in bed, total sleep, and post-dose sleep are not stacked as additive amounts.
18. Dose 2 wake method cannot be substituted for final-wake method.
19. Historical reminder settings are not overwritten by current preferences.
20. Reminder scheduling does not claim actual delivery or administration.
21. Reference grouping keeps shorter and longer spacing separate, with defined inclusive boundaries and uncertainty handling.
22. Each context comparison displays available and excluded counts and retains an unknown-context group.
23. No outcome-variation means no computed best-interval or misleading correlation result.
24. A medication or questionnaire change appears on relevant trends; incompatible periods are not silently merged.
25. A new feature's earlier history displays not collected rather than zero.
26. Six calendar months and 180 days are separate range definitions.
27. Cancelled/rescheduled appointments do not reset since-last-completed-visit history.
28. UTC elapsed calculations and local labels remain correct across midnight, daylight-saving changes, and travel.
29. Chart, accessible table, and exported numbers agree under identical filters and derivation versions.
30. Overlapping marks are inspectable without changing their true coordinates.
31. VoiceOver/keyboard/touch navigation can reveal exact values and move between observations without hover.
32. Static exports preserve essential labels, reference qualifications, denominators, and data-source distinctions.
33. Offline/partial/stale data is indicated without replacing known records with zeros.
34. A model layer cannot trigger dosing advice, a clearance countdown, or an unscheduled reminder.
35. No source-presence boolean alone determines whether a particular metric is complete.
36. Raw symptom/dose information is not sent to a clinician merely by viewing or saving a dashboard.

## Suggested delivery order

Phase 1: shared metric definitions, review states, session replay, aligned session rows, and interval-by-date view.

Phase 2: sleep opportunity, completeness matrix, interval distributions, and basic physician overview.

Phase 3: individual nap/daytime administration views once their underlying records are implemented and reliable.

Phase 4: selected context comparisons and optional reviewed medication-model displays, without causal or dosing optimization claims.

## Design references

The dashboard groupings, labels, priorities, and acceptance checks are proposed product decisions. The supplied export supports the source-field observations, not clinical validation of these dashboards.

Apple Human Interface Guidelines, Charts: `https://developer.apple.com/design/human-interface-guidelines/charts`

Apple's guidance supports readable axes, meaningful marks, full-width compact plots, non-color encodings, accessible descriptions, and selection that does not require exact finger targeting.
