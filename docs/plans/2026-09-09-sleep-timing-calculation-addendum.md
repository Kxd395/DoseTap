# DoseTap: sleep timing markers and calculation addendum

Date: 2026-09-09

Revision: 1.2, adopted implementation plan

Status: Accepted plan for DOSETAP-56/57. Only behavior promoted into SSOT is implemented; phone acceptance remains separate.

Related plan: `docs/plans/2026-09-08-sleep-markers-roadmap.md`

Location: `docs/plans/2026-09-09-sleep-timing-calculation-addendum.md`

## 1. Main requirement

Separate four different questions:

1. How long after Dose 1 did estimated sleep begin?
2. How long was the person awake before taking Dose 2?
3. How long after Dose 2 did estimated sleep resume?
4. How long was the entire awake episode around Dose 2?

The second and third durations add up to the fourth only when they refer to the same identifiable awake episode and compatible sources. None of these durations establishes when medication began working or how much sleep a dose caused.

Keep Apple Health sleep-stage detail and the existing event logs. Add markers and derived summaries rather than requiring more overnight interaction. Let the user review estimates in the morning.

## 2. Implementation status and evidence

**The complete dose-to-sleep feature is planned, not delivered.** Existing sleep totals and provider timelines are inputs to that feature, not proof that dose-linked sleep-onset or return-to-sleep calculations already exist.

This revision combines the earlier reviewed repository snapshot with the implementation-status update supplied by the user on September 9, 2026. No fresh live Plane query, repository fetch, installed-build check, or device test was performed for this revision. The supplied update reports DOSETAP-56 and DOSETAP-57 as Todo; treat that as a reported status, not independently reverified live state. The update's account of recent reporting fixes is also not new release evidence.

### Status matrix

| Capability | Status supported by the reviewed snapshot and supplied update | Action |
| --- | --- | --- |
| Apple Health sleep-stage timeline and provider-derived onset/wake information | Existing when usable provider observations are available; boundary/source interpretation still needs correction. | Preserve the stage detail and existing provider information. |
| Estimated total sleep after Dose 2 | Existing interval-based calculation with coverage fields. | Reuse it. Do not relabel it as time to fall back asleep. |
| Dose 1 to estimated initial sleep onset | Planned, not implemented as the complete dose-linked feature. | DOSETAP-57 after DOSETAP-56. |
| Awakening to actual Dose 2 | Planned, not implemented as the complete dose-linked feature. | Identify the awake episode containing the dose. |
| Dose 2 to estimated return to sleep | Planned, not implemented as the complete dose-linked feature. | Calculate from actual dose to the identifiable return from that episode. |
| Whole awake episode around Dose 2 | Planned as part of the new episode calculations. | Show pre-dose and post-dose portions plus total duration. |
| Identified awakening episodes, return markers and episode-based counts | Planned. A pre-existing raw wake count does not satisfy this contract. | Implement the counting and continuity rules in section 4. |
| Correct treatment-night totals, final-awakening semantics and source evidence | Prerequisite work, DOSETAP-56. | Correct and test before exposing new dose-linked metrics. |

The current-at-review `NightOutcome.swift` has food-to-dose intervals, explicit Dose 2 wake method, backup-alarm context, following-day type, final wake, one timestamped personal sleepiness rating, and an estimated post-Dose-2 sleep calculation with coverage fields. Reuse these rather than creating duplicate records. [R1]

The reviewed `HealthKitService.swift` derives sleep onset, first wake, final wake, time to first wake, sleep minutes and wake count. Its primary-night helper selects the largest cluster after splitting at a 90-minute gap. Its final-wake helper can use the end of a trailing awake segment. Those semantics need correction before the numbers below are trusted as treatment-night totals and awakening times. Existing helper outputs do not constitute complete dose-linked marker delivery. [R2]

The September 8 roadmap assigns measurement/source corrections to DOSETAP-56 and new dose/sleep markers to DOSETAP-57. Independent daytime observations are planned under DOSETAP-58, clinician reporting under DOSETAP-59, and a separate hazardous-activity elapsed-time specification under DOSETAP-60. These are document-defined ownership references. This addendum proposes implementation sequencing; it does not change live issue priorities, states, or dependencies. [R3]

### Terminology that must remain distinct

- **Estimated sleep after Dose 2:** amount of recorded asleep time afterward.
- **Dose 2 to estimated return to sleep:** elapsed delay before the associated awake episode ends in observed sleep.
- **Whole Dose 2 awake episode:** waking-to-dose delay plus post-dose return delay, when both refer to the same identifiable episode and compatible sources.

A reporting correction is not completion of any of these new marker requirements. Delivery requires implementation, cross-screen consistency, tests, and device acceptance.

## 3. Required event markers

These are logical field names. Map them to existing source records where possible; do not create a second medication ledger.

| Marker | Suggested field | Meaning and source |
| --- | --- | --- |
| In bed | `in_bed_at` | Actual reported start of the overnight bed window, not planned bedtime. |
| Started trying to sleep | `trying_to_sleep_at` | Explicit observation. Lights Out can supply this only when the user confirms that meaning. |
| Dose 1 | `dose1_taken_at` | Actual occurrence from the medication ledger, not alarm time or retrospective entry time. |
| Initial sleep onset | `initial_sleep_onset_at` | Source-labeled estimate of the first sleep onset associated with the reviewed night. |
| Each awakening | `awake_episode.started_at` | Start of one observed awake episode after sleep. |
| Awake episode associated with Dose 2 | `dose2_awake_episode_id` | Reference to the identifiable awake episode containing Dose 2. Not automatically the first awakening that night. |
| Dose 2 | `dose2_taken_at` | Actual occurrence from the medication ledger. |
| Return to sleep | `awake_episode.return_to_sleep_at` | Source-labeled estimated return from that specific awake episode. |
| Post-Dose-2 return to sleep | `post_dose2_sleep_onset_at` | Return from the Dose 2 awake episode, when identifiable and at/after Dose 2. |
| Final awakening | `final_wake_at` | Final awakening of the main overnight sleep period, separate from record end and getting out of bed. |
| Out of bed for the day | `out_of_bed_at` | Actual reported end of the overnight bed window. |

Keep `occurred_at`, `recorded_at`, source, original record/sample ID, named timezone and correction provenance separate. A bedtime tap records an action, not proof of the precise moment sleep began. Provider sleep timing remains an estimate; a recalled manual onset remains a recalled estimate.

For calculation notation below:

- D1 and D2 are actual dose times.
- S1 is estimated initial sleep onset.
- W2 is the start of the awake episode associated with D2.
- S2 is estimated return to sleep from that episode.
- F is final awakening.
- B and O are actual in-bed and out-of-bed markers.
- T is the explicit time the person started trying to sleep.

All differences use absolute timestamps. Display minutes, but preserve original timestamp precision.

## 4. Essential calculated metrics

| Display label | Proposed field | Calculation | Interpretation |
| --- | --- | --- | --- |
| Dose 1 to estimated sleep | `dose1_to_sleep_minutes` | `(S1 - D1) / 60` | Elapsed time after the actual first dose. Unavailable/conflict if the identified sleep onset precedes the dose. |
| Trying to sleep to estimated sleep | `sleep_onset_latency_minutes` | `(S1 - T) / 60` | Separate from dose-to-sleep. Requires an explicit attempt-to-sleep time. |
| Time to first observed awakening | `time_to_first_wake_minutes` | First qualifying observed awakening minus S1 | Describes the initial sleep episode. Keep final awakening distinct; no observed intermediate wake is not a zero-minute interval. |
| Time between doses | `dose_interval_minutes` | `(D2 - D1) / 60` | Medication timing only, not time asleep. |
| Awake before Dose 2 | `wake_to_dose2_minutes` | `(D2 - W2) / 60` | Time awake before the actual second dose. |
| Dose 2 to estimated sleep | `dose2_to_sleep_minutes` | `(S2 - D2) / 60` | Time after the second dose before estimated return to sleep. |
| Whole Dose 2 awake episode | `dose2_awake_episode_minutes` | `(S2 - W2) / 60` | Includes both the pre-dose and post-dose portions. Do not add this again to total overnight wake. |
| Estimated sleep between doses | `estimated_sleep_between_doses_minutes` | Union of resolved asleep intervals clipped to `[D1, D2)` | Excludes observed awake time and unmeasured gaps. Multiple sleep blocks can contribute. |
| Estimated sleep after Dose 2 | Existing `estimatedSleepAfterDose2Minutes` | Union of resolved asleep intervals clipped to `[D2, F)` | Extend/reuse the current interval calculation; do not substitute elapsed time. |
| Dose 2 to final awakening | `dose2_to_final_wake_minutes` | `(F - D2) / 60` | Elapsed window, not sleep quantity. |
| Overnight sleep-period span | `overnight_sleep_period_minutes` | `(F - S1) / 60` | Includes intervening sleep, awake time and any gaps. Not total sleep. |
| Estimated total overnight sleep | `estimated_total_sleep_minutes` | Union of resolved asleep intervals within reviewed overnight bounds | Include eligible separated blocks. Keep primary episode and treatment-night total separate. |
| Observed overnight awake time | `observed_waso_minutes` | Union of resolved awake intervals between S1 and F | Include the Dose 2 awake episode once; exclude initial sleep latency and final-wake-to-out-of-bed time. |
| Final awakening to out of bed | `final_wake_to_out_of_bed_minutes` | `(O - F) / 60` | Time remaining in the bed window after final wake. Not proof of grogginess or inability to get up. |

Never report `sleep between doses + sleep after Dose 2` as the complete-night total unless the reviewed night contains no additional eligible sleep outside those windows. Preserve pre-dose sleep separately when present.

### Counting and continuity

Calculate completed overnight awakening count, observed awake duration by episode, and longest observed continuous sleep episode. Merge adjacent sleep-stage changes as sleep continuity; a Core-to-REM transition is not an awakening. Apple represents sleep stages using separate samples, including unspecified sleep. [A1]

Count an awake episode spanning Dose 2 once for the night. Its pre-dose and post-dose portions can appear separately as durations. A count labeled "awakenings beginning after Dose 2" uses episode start at/after D2; the spanning episode remains a separate item. Do not count final awakening as a completed overnight wake-and-return episode. [R3]

Do not merge across unknown gaps as though continuous sleep were observed. A single bathroom button press establishes an event, not the full duration of an awake episode.

## 5. Other useful timing calculations

| Calculation | Required input and definition | Important limitation |
| --- | --- | --- |
| Last food to each dose | Each dose minus the latest known food/caloric-drink finish before that dose. | Re-evaluate separately for D2. A recorded overnight snack can make the pre-bed meal no longer the last intake. A snack timestamp without a finish time is incomplete, not exact. |
| Last caffeine to trying to sleep | T minus latest recorded caffeine use. Keep amount and occurrence time when known. | Elapsed time is not a measured caffeine concentration or proof of cause. |
| Last caffeine to estimated sleep | S1 minus latest recorded caffeine use. | Keep distinct from the previous metric; missing onset means unavailable. |
| Each daytime medication to bedtime/sleep | T or S1 minus that medication's actual occurrence time, with product/formulation identity. | Separate IR and XR. No drug-clearance, half-life, effectiveness or dosing recommendation. Multi-medication analytics remains separately scoped in the roadmap. [R3] |
| Natural wake before a backup alarm | Planned alarm time minus explicitly reported natural W2. | Positive means before the planned alarm. A scheduled alarm or no snooze does not establish wake method or delivery. |
| Final wake versus planned wake | Actual F minus planned wake, as a signed difference. | Do not clamp early waking to zero. Preserve the plan version used that night. |
| Planned sleep opportunity | Planned wake minus planned trying-to-sleep time. | A plan is not actual sleep. Do not insert the planner's assumed latency into measured history. |
| Nap opportunity versus estimated nap sleep | Nap End minus Nap Start for the logged window; asleep-interval union for estimated sleep, when available. | A nap attempt is not proof of continuous sleep. Missing ends/overlap require review. |
| Daytime sleepiness observation timing | Each independent observation's actual assessment time, linked optionally to the preceding night. | Keep repeated assessments independent rather than correcting the night's one existing rating. [R1, R3] |
| Last recorded dose to planned driving/hazardous work | Planned activity time minus latest actual relevant medication administration. | Separate specification and clinical-copy review. Never display a clearance or safe-to-drive status. Do not use work start when the commute begins earlier. [R3] |

Optional sleep efficiency should be introduced only with an explicit denominator. For example, an app-specific overnight bed-window ratio is `estimated sleep in [B,O) / (O-B) * 100`. Label the denominator and temporary out-of-bed handling. Do not substitute D1 for B, confuse this with a device accuracy score, or present a complete-night percentage when coverage is incomplete. A clinically named metric requires its definition to be reviewed before release.

## 6. Coverage and source rules

For each analyzed interval, maintain:

| Field | Meaning |
| --- | --- |
| `interval_minutes` | Full requested elapsed interval. |
| `covered_minutes` | Union of time with usable resolved sleep or awake observations. In-bed-only data is not classified coverage. |
| `unknown_minutes` | Requested interval minus classified coverage, including unresolved source conflicts when excluded by policy. |
| `coverage_percent` | `covered_minutes / interval_minutes * 100`, only for a valid positive interval. |
| `result_status` | `available`, `partial`, `unavailable`, `conflict`, or `pending_sync`. |
| `derivation_version` | Version of the calculation/source policy. |
| `source_revision_ids` | Input sample or event revisions used. |

HealthKit can contain overlapping in-bed and detailed sleep samples. Treat those categories according to their distinct meaning; do not sum in-bed duration into sleep totals. [A2]

Preserve raw provider records and manual observations. Use a deterministic, reviewed source policy before forming the resolved interval union. Do not silently rewrite Apple Health evidence to agree with a manual entry, or replace a recorded medication time to make it agree with a watch estimate.

For a complete, consistently classified sleep-period interval, `sleep + awake = elapsed span`. With gaps, `sleep + awake + unknown = elapsed span`. Never calculate awake time as elapsed minus sleep when missing coverage is possible.

An explicit all-awake interval with full coverage can legitimately produce zero sleep. No samples produce unavailable, not zero. Partial awake-only samples do not prove no sleep during the rest of the night.

If an asleep sample spans D2 and no identifiable wake/return is available, retain the sample and dose, flag the inconsistency, and leave dose-to-return unresolved. Do not create a zero-minute latency by clipping the sample's start to D2. A reported failure to return to sleep should remain a distinct outcome, not an invented sleep-onset timestamp.

## 7. Worked synthetic example

These values are a calculation fixture, not the user's observations or a recommended schedule. Assume complete coverage and no other wakes.

| Event | Time |
| --- | --- |
| In bed | 23:35 |
| Trying to sleep and actual Dose 1 | 23:40 |
| Estimated sleep onset | 23:52 |
| Awakening associated with Dose 2 | 02:40 next day |
| Actual Dose 2 | 02:48 next day |
| Estimated return to sleep | 03:02 next day |
| Final awakening | 06:30 next day |
| Out of bed | 06:40 next day |

Expected results:

- Dose 1 to sleep: 12 minutes.
- Time between doses: 188 minutes, or 3 hours 8 minutes.
- Awake before Dose 2: 8 minutes.
- Dose 2 to return to sleep: 14 minutes.
- Whole Dose 2 awake episode: 22 minutes, not 14 minutes.
- Estimated sleep before that awakening: 168 minutes.
- Estimated sleep after Dose 2: 208 minutes, or 3 hours 28 minutes.
- Dose 2 to final wake: 222 minutes, not 208 minutes.
- Estimated total sleep: 376 minutes, or 6 hours 16 minutes.
- Sleep-period span: 398 minutes, or 6 hours 38 minutes.
- Observed overnight awake time: 22 minutes.
- Completed overnight awakening count: 1; final awakening is separate.
- Final wake to out of bed: 10 minutes.

## 8. Implementation order and acceptance

First reconcile night bounds and provider evidence under DOSETAP-56. Then implement dose-linked markers and episode calculations under DOSETAP-57. Reuse the current post-Dose-2 estimator and collected-night exports, with additive versioned fields. [R1, R3]

### Delivery gates

**Gate A: DOSETAP-56, correct the input measurements.** Preserve existing stage detail while reconciling primary episode versus treatment-night boundaries, final awakening versus observation end, overlapping samples, source evidence, and missing/conflicting coverage. The same corrected inputs must be usable by the timeline and derived metrics. Do not replace source estimates with medication timestamps.

Concrete acceptance examples:

| Synthetic input | Required result |
| --- | --- |
| Sleep ends at 05:30; a following awake sample extends to 05:50. | Keep estimated final awakening at the reviewed sleep-to-wake boundary, not automatically at observation end 05:50. Retain both meanings. |
| Sleep 22:00-01:00 and 02:45-04:45, both inside reviewed treatment-night bounds. | Treatment-night recorded sleep is 300 minutes. Do not discard the shorter block or count the 105-minute gap as sleep. Classify the gap from evidence or leave it unmeasured. |
| No usable provider samples. | Show unavailable, not zero sleep or zero awakenings. |
| Provider reports asleep through an actual dose time. | Preserve both records, expose the conflict, and do not fabricate dose-linked zero latency. |

**Gate B: DOSETAP-57, add the dose-linked calculations and markers.** Implement Dose 1-to-sleep, waking-to-Dose-2, Dose-2-to-return, whole-episode duration, and episode-based awakening counts. Place markers over the existing Apple Health chart and preserve quick logs. Reuse the existing post-Dose-2 sleep-total calculation, with corrected inputs and coverage labels.

**Gate C: validate the feature end to end.** The 02:40 awakening / 02:48 dose / 03:02 return fixture must produce 8, 14, and 22 minutes everywhere the metric is presented. Changes to source records must recompute the same versioned result across Timeline, History, dashboard, and export/Studio consumers. Passing core tests alone does not verify the installed phone build or Apple Health import behavior. Retain medication/alarm invariants and complete signed-device and accessibility acceptance before claiming the feature is delivered.

The first slice does not need new caffeine analytics, medication comparisons, extra questionnaires, a new clinical score, or a redesigned clinician report. Keep those separately scoped. Existing export/Studio consistency for the new timings is part of this feature's acceptance, not a reason to defer correctness to the later reporting project.

### User-visible missingness and explanation

Do not collapse every missing result into an unexplained dash. Preserve the existing result status and include a reason where applicable: missing start/end, no observed return, incomplete coverage around a boundary, conflicting source observations, or invalid time order. A confirmed report of not returning to sleep is a separate diary outcome, not a sleep-onset timestamp. No observed return in partial data does not establish that no sleep occurred.

A marker's detail view should explain the actual dose time, associated estimated sleep/wake boundary, source, coverage, and calculation. Proposed dose-to-sleep wording must describe a timing estimate, not when the medication started working or whether it was effective.

### Recommended file responsibilities


| File | Proposed work |
| --- | --- |
| `ios/DoseTap/HealthKitService.swift` | Query/clip overlapping samples, preserve provenance, and correct primary-episode versus treatment-night/final-wake semantics. |
| `ios/Core/NightOutcome.swift` | Extend collected-night results without overwriting existing diary meanings. |
| `ios/Core/SleepTimingCalculator.swift` (proposed) | Pure, versioned marker and episode calculations with explicit unavailable/conflict states. |
| `Tests/DoseCoreTests/SleepTimingCalculatorTests.swift` (proposed) | Synthetic interval, missingness and boundary tests. |
| Existing timeline, History, dashboard and export/Studio consumers | Use the same calculated values and definitions, not local reimplementations. |

Minimum acceptance cases: the synthetic example above; several brief wakes before D2; one awake episode spanning D2; missing D2; no observed post-dose return; sleep sample spanning a dose; no watch data; partial coverage; fully observed all-awake interval; duplicate/reordered samples; two long-separated sleep blocks; trailing awake data after final wake; midnight/DST/travel; retrospective edits; corrected/deleted provider samples; export parity; and unchanged medication/alarm state after analytics work.

Store absolute timestamps and named-zone provenance; do not repair reversed instants by adding 24 hours. Use stable session identity and reviewed overnight bounds, not the duration for which the app happened to stay in an open session. Recompute derived results when inputs change without rewriting medication history.

For weekly or 14-day reports, show medians, middle-50% ranges and usable counts separately for each metric. Display partial and missing nights. Do not mix diary scales or label an observational timing difference as a medication benefit.

## 9. Review/action log

**Original review:** The prior addendum documented reads of `NightOutcome.swift`, the relevant `HealthKitService.swift` calculation section, the September 8 sleep-markers roadmap, and Apple primary documentation on sleep-sample categories. It included a synthetic arithmetic check. The source links and hashes below preserve that review context, not a new assertion about the current branch or installed build.

**Revision 1.1:** Read the existing addendum and the user-supplied status clarification. Added an explicit existing-versus-planned matrix, distinguished raw helper outputs from the completed marker feature, made DOSETAP-56 then DOSETAP-57 delivery gates explicit, added boundary fixtures, and separated first-slice scope from later analytics/reporting. Core formulas remain unchanged.

**Artifact created:** `DoseTap_Sleep_Timing_Calculations_v2.md`. The original `DoseTap_Sleep_Timing_Calculations.md` was preserved.

**Repository files changed:** None. No issues were created or updated. No fresh live Plane verification, repository fetch, iPhone build, or app test suite was run for this revision. User-supplied status text is review input, not independent execution evidence.

## Sources

[R1]: https://github.com/Kxd395/DoseTap/blob/ced7ab13dc68d81a01b65f88ab5cfce86e43360a/ios/Core/NightOutcome.swift
[R2]: https://github.com/Kxd395/DoseTap/blob/ced7ab13dc68d81a01b65f88ab5cfce86e43360a/ios/DoseTap/HealthKitService.swift
[R3]: https://github.com/Kxd395/DoseTap/blob/ced7ab13dc68d81a01b65f88ab5cfce86e43360a/docs/plans/2026-09-08-sleep-markers-roadmap.md
[A1]: https://developer.apple.com/videos/play/wwdc2022/10005/
[A2]: https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis

- [R1: DoseTap collected-night models and interval estimator][R1]. Reviewed blob `fc3b9e565db2f8e6a05cf783b8ef728aedc1f066`.
- [R2: DoseTap HealthKit sleep processing][R2]. Reviewed blob `0a3e3d2494634a6c66f98d5b5d37864607ede241`.
- [R3: DoseTap sleep-marker roadmap][R3]. Reviewed at commit `ced7ab13dc68d81a01b65f88ab5cfce86e43360a`; roadmap blob `4097ca1bba79350c277c3ddc9b9d425fbac56e5b`.
- [A1: Apple, What's new in HealthKit, sleep-stage section][A1].
- [A2: Apple, HKCategoryValueSleepAnalysis][A2].

- User-supplied implementation-status clarification, provided in this conversation on September 9, 2026. Used for the status summary; live Plane state was not independently reverified for revision 1.1.

## 10. Adopted decisions, September 9

The sections above preserve the supplied v2 review and its historical evidence limits. This section records the implementation decisions adopted after reading main at `ced7ab13` and live Plane DOSETAP-56/57. DOSETAP-56 is now In Progress; DOSETAP-57 remains Todo. Plane remains the live status authority.

### Bounded delivery

The first correction separates the last observed sleep end, estimated final awakening and observation end, and prevents unknown HealthKit categories from becoming sleep or awake. It keeps the existing primary-episode selector explicitly identified as such. It does **not** claim to fix treatment-night aggregation, source reconciliation, or deliver dose-linked markers.

Next, complete reviewed treatment-night bounds and source reconciliation under DOSETAP-56. Then implement DOSETAP-57's shared calculator and wire all consumers to it. Do not introduce new questionnaires to obtain information already present in dose records or provider intervals.

**Second slice, bounded coverage:** `SleepIntervalCoverage` now supplies the common clip/union arithmetic, with separate sleep, awake, covered and unmeasured durations. The existing post-Dose-2 estimator delegates to it. An opt-in HealthKit query retains samples crossing an explicit window's edges and all eligible blocks inside it. It is not yet a treatment-night consumer: no screen/export invokes that query, and no reviewed-window record has been added. The legacy primary-episode selector remains separate. See [the bounded-coverage audit](../audit/2026-09-09/bounded-sleep-coverage.md).

The next integration must persist reviewed bounds with session identity, boundary source and original zone; retain conflicting provider evidence; and test revisions, deletion and overlapping-session/nap conflicts. Only then should History, Timeline, Dashboard and exports share treatment-night results. DOSETAP-57 still owns dose-linked onset/return markers and completed awakening counts. Do not present this calculation foundation as delivery of those screens.

### Treatment-night bounds

A resolved treatment-night calculation must receive an explicit start and end with stable session identity, original timezone and boundary source. Do not use the current clock, an open-session lifetime, or the date grouping key as measured sleep bounds.

Prefer an explicitly reviewed overnight window. Otherwise retain the current primary-episode result as a separately labeled fallback, with treatment-night totals unavailable until a bounded window is resolved. Do not silently declare the generic 18:00-to-noon provider query to be the user's overnight window. Planned wake and check-in submission time are not actual final awakening.

Include every eligible sleep block within the reviewed window, even across a gap longer than 90 minutes. Clip overlapping samples at both ends. Preserve a later separately identified nap outside it. If an identified nap overlaps the overnight window or two sessions claim the same window, report a boundary conflict for review; do not discard or double-count it silently. Missing morning check-in must not expand the window to include afternoon sleep.

### Boundaries and honest precision

Use half-open observation intervals `[start,end)`. A sleep sample's end is the last observed sleep end. It is an estimated sleep-to-wake transition only when a usable awake interval begins there; without that transition, retain the sleep-end estimate with its distinct basis, not proof of final waking. The provider observation end is separate.

For Dose 2 episode association use `wake <= dose < return`. At an exactly observed return instant, a zero post-dose delay is allowed only as an explicitly identified endpoint match to that preceding completed episode, with observed continuous awake coverage ending there. A sample merely spanning the dose cannot produce zero. At exactly observed waking, the pre-dose delay can be zero. If input precision cannot establish the order, disclose that limitation rather than choosing an ordering.

Final awakening remains a separate marker. A wake-and-return count requires observed sleep immediately before the awake episode and an observed return at its end. Sample splitting does not increase counts; gaps break evidence of continuity. Report incomplete episodes separately. No arbitrary onset-duration threshold is introduced.

### Per-metric evidence and refresh

Each metric carries its own status, reason, boundary source and derivation version. Whole-night coverage alone cannot establish an onset near a missing boundary. Reasons include missing dose, missing observed onset, missing return, boundary gap, invalid order, unresolved source conflict and unresolved night bounds. `pending_sync` requires an actual in-flight import; an empty successful query alone means unavailable.

Keep provider sample identity, revision, timezone when present, device/source metadata, and import time apart from clinical occurrence time. Preserve missing provenance as missing. Late arrivals, source edits/deletions, dose corrections and reviewed-boundary edits must invalidate the affected derived results. Saved reports retain their calculation version and generation time; current summaries recompute.

Before consumer integration, define deterministic source selection without claiming a source is more accurate. Retain conflicting raw evidence, including unknown categories, and exclude unresolved classifications from measured sleep/awake coverage. Valid unspecified-asleep observations remain sleep. Duplicate/reordered imports must yield identical results. Do not persist new derived medication or alarm state.

### Additional acceptance cases

- Dose exactly at awake start, exactly at return, and one second on either side; preserve genuine zero versus clipping artifacts.
- Sleep ending without a following awake observation; sleep/awake separated by an unmeasured gap; trailing in-bed-only data.
- Split same-night sleep, late/missing check-in, an outside nap and a conflicting overlapping nap.
- High overall coverage with a gap precisely at dose/onset; a successful empty query versus an actual pending import.
- Same-night manual/provider disagreement, corrected/deleted source samples, repeat/reordered imports, and report regeneration after correction.
- No new mandatory overnight taps; optional trying-to-sleep/out-of-bed entries must not block saving existing logs.
- Existing medication confirmation, cancellation, backgrounding and persistence tests remain independent release gates.

These decisions refine the supplied formulas; they do not turn estimates into medication-effectiveness measures. The original two review files remain unchanged in the preserved checkout.
