# Sleep markers and measurement roadmap

Date: 2026-09-08
Status: Planned work; not a claim that new markers are implemented
Authority: Plane owns live priority and state.
Related: [Food and Drink roadmap](2026-09-08-food-drink-roadmap.md)
Calculation contract: [Adopted timing addendum](2026-09-09-sleep-timing-calculation-addendum.md), including bounded delivery and per-metric evidence rules.

## Owner requirement

Keep the Apple Health sleep-stage detail and existing provider information in the app. Add actual dose, estimated sleep-onset, awakening, return-to-sleep and final-awakening markers, with episode durations and counts. Keep bathroom, water, noise, dream and other quick logs.

## Delivery order

1. DOSETAP-51 fresh-night answer repair, followed by DOSETAP-52 unit/default repair. Existing medication/alarm device acceptance remains independent.
2. DOSETAP-56 measurement corrections before DOSETAP-57 marker/count calculations.
3. DOSETAP-53/54 shared Food and Drink logging/review; do not hold manual logging for an external integration.
4. DOSETAP-58 daytime observations and DOSETAP-59 clinician reporting, after the relevant source definitions are stable.
5. DOSETAP-55 external intake prototype. DOSETAP-60 remains a separate safety-copy/specification review, not dosing policy approval.

DOSETAP-56/57 are High; DOSETAP-58/59/60 are Medium. All five start in Todo. Dependencies are written in Plane descriptions; no native dependency edges or assignees are implied.

## Missing information and chosen handling

| Question | Planned contract |
| --- | --- |
| What does time to sleep start from? | Dose-to-sleep uses the actual recorded dose. Time from trying to sleep requires a separate explicit observation; do not substitute a tap, planned bedtime or Lights Out without labeling its meaning. |
| Which awakening belongs to Dose 2? | The identifiable awake episode containing the dose. If uncertain, show unavailable. Keep wake-to-dose delay, dose-to-return and whole-episode duration separate. |
| What is one awakening? | One continuous observed awake episode following sleep. Sample splits and sleep-stage changes do not inflate counts. Unknown gaps do not prove continuity or another awakening. |
| What if the episode crosses Dose 2? | Count once for the night; show the spanning episode separately. After-Dose-2 awakening count uses episode start at/after Dose 2. |
| Is final wake counted? | Separate final-awakening marker. It is not a completed overnight return-to-sleep episode. In-progress or unobserved return is explicit. |
| What about brief events? | No invented minimum duration or assumed sleep latency. Review and version any qualifying threshold; disclose provider resolution and manual observations. |
| What if the watch says asleep during the dose? | Conflict or unresolved onset, never automatic zero-minute latency. The dose record is not changed. |
| No watch data or delayed sync? | Show coverage, last import and pending/unavailable state. Do not turn missing samples into zero awakenings or zero sleep. |
| Two sleep blocks separated by a long gap? | Keep primary episode separate from treatment-night total. Include eligible blocks within reviewed night bounds; do not absorb daytime naps because check-in was late. |
| Manual and provider times differ? | Keep both with source, revision and discrepancy information. No silent overwriting of provider evidence. |
| Multiple devices or corrected samples? | Deterministic source policy, original identity/provenance, idempotent import and visible conflicts. Source preference is not a device accuracy score. |
| How do old reports change? | Version the derivation and source revisions; recompute current results after corrections while retaining historical report provenance. |
| How do counts aggregate? | Show covered-night/usable-observation denominators. An incomplete night cannot assert a complete-night zero. Weight repeated observations by day for day-level summaries. |
| How does it look? | Add markers over existing stage bands, a compact summary and tap-to-explain detail. Preserve shared headers/theme/capture, accessibility text and VoiceOver; do not force charts into a clipped screen. |

Illustrative test: wake 02:40, actual Dose 2 02:48, estimated return 03:02 gives 8 minutes before dose, 14 minutes after dose and 22 minutes awake. These are synthetic fixture values, not owner observations.

## Plane tasks

### DOSETAP-56: Correct treatment-night sleep boundaries and preserve HealthKit source evidence

Keep all existing Apple Health sleep detail available. Define primary sleep episode separately from treatment-night totals; include eligible separated blocks without treating an open session or delayed morning check-in as unlimited sleep opportunity. Separate estimated final awakening, observation end and manual final wake. Preserve sample UUID, source/device revision when available, import time, conflicts and derivation version. Unknown categories are not asleep; valid unspecified-asleep stays supported. Query overlapping samples and clip, rather than dropping samples that start before the interval. Preserve all-awake zero versus unavailable and partial coverage end to end. Source selection must be deterministic on reorder/reimport, not presented as an accuracy score. Tests: 05:30 sleep end plus awake through 05:50; 22:00-01:00 plus 02:45-04:45; missing/gap/all-awake/duplicate/conflicting samples; DST/travel; manual/provider disagreement. Coordinate DOSETAP-10, DOSETAP-45 and DOSETAP-13. No dose/alarm/session writes. Source review is evidence, not device reproduction.

### DOSETAP-57: Add dose-to-sleep and return-to-sleep timeline markers with awakening counts

Depends on the sleep-boundary/source correction task. Retain Apple Health stage bands, existing provider information and quick logs. Add actual Dose 1 and Dose 2 markers, estimated initial sleep onset, observed awakenings, returns to sleep and separate final awakening. Show Dose 1-to-sleep, waking-to-Dose 2, Dose 2-to-return and whole awake-episode duration separately. One continuous awake episode is counted once even when it spans Dose 2; stage changes are not awakenings. After-Dose-2 awakening count is based on episode onset at/after Dose 2; the spanning episode remains visible separately. Final awakening is excluded from overnight return-to-sleep counts, and unresolved/partial episodes are explicit. Watch sleep spanning a dose, missed wear, delayed sync and gaps yield conflict/unavailable, never forced zero latency or inferred wake method. No arbitrary sleep-onset duration threshold: review/version any qualifying rule before release. Manual observed corrections preserve raw provider evidence and source labels. Marker tap explains times, sources and coverage; larger text and VoiceOver remain usable. Dose corrections and new samples recompute/version derived values without rewriting medication. Test boundary timestamps, multiple wakes, split samples, synthetic 02:40 wake/02:48 dose/03:02 sleep example, source gaps, midnight/DST, and Timeline/History/dashboard/export/Studio parity.

### DOSETAP-58: Add independent daytime sleepiness observations and explicit dozing events

After data-freshness repairs, extend DOSETAP-49 without overwriting its single nightly diary answer. Timestamped independent observations have stable ID, occurrence/entry times, timezone provenance, optional related night, context and audited revisions. Start with optional personal 0-10 sleepiness and unintended sleep/dozing; fatigue and concentration stay separate optional future answers, not a combined clinical score. Reuse nap events and expose missing ends/overlapping starts without fabricated duration. No reminders during sleep or prompts encouraging interaction while driving; user-selected schedules require separate acceptance. Unknown medication use is not skipped. Tests: repeated same-day observations, daily weighting, backdate/edit/restart/failed write, no implicit night creation, export/Studio parity. Epworth remains separate, dated and deferred pending authorized instrument/use review. No medication comparisons until constitution/product scope is reconciled.

### DOSETAP-59: Add a clinician report preset with sleep timing and observation coverage

Extend DOSETAP-45 analytics and DOSETAP-13 export pipeline after corrected sleep metrics and daytime observations. Selectable 14-day default is a convenience, not diagnostic sufficiency. Include source/app/derivation versions, night and per-metric usable counts, missing/partial observations, dose/sleep marker intervals, explicit wake-method counts, daytime observations and optional patient questions. Preserve raw event provenance, unit/amount scope, corrections and null values. Preview content, allow excluding notes, redact unnecessary identifiers and protect formula-like free text without breaking round trip. Individual readings and medians/IQR where appropriate; no best-medication or efficacy score. Tests: synthetic same-night iOS-to-archive-to-Studio parity, corrected-dose invalidation, timezone ranges, redaction/CSV quoting/formula strings and usable-day weighting. Device/owner/privacy review remains required; export is not whole-app restore.

### DOSETAP-60: Specify a separate last-recorded-dose to planned hazardous-activity readout

Specification and safety-copy review before implementation. Use an explicitly entered planned driving/hazardous activity instant and the most recent actual XYWAV administration, including corrected/extra-dose records. If no reliable last dose or incomplete recording, show uncertainty; never infer from an alarm or planned schedule. Follow the reviewed current XYWAV label's six-hour minimum warning; at/after the boundary show elapsed time only, never fitness-to-drive clearance. No stimulant or sleepiness score overrides this warning. Keep work start distinct from earlier travel time. Absolute times and correction invalidation required. Tests: just below/exactly/above boundary, missing/revised last dose, cross-midnight/DST and cancelled activity. No dose scheduling/amount/extra-dose advice, and no automatic medication writes. Clinical wording, owner choice and signed-device/accessibility acceptance remain open. This planning item does not authorize a new medication policy.

## Existing ownership and scope limits

- DOSETAP-10: query readiness/data availability, not proof of HealthKit read permission.
- DOSETAP-45 and DOSETAP-13: dashboard/Studio calculations and export parity; use the same versioned definitions.
- DOSETAP-47: stable-ID manual edits and retained correction history.
- DOSETAP-39: full lifecycle/clear-all/restore. A report is not a complete backup.
- DOSETAP-17: documentation reconciliation. The stale SSOT version paragraph has been replaced with executable-schema references; continue checking migrations against code, not a historical roadmap version. Do not infer installed database migration state from prose.
- Multi-medication analytics is deferred until the XYWAV-only constitution and existing broader catalog are reconciled. Integer mg can represent fractional grams exactly; audit precision and per-administration versus nightly-total scope, not merely numeric type.
- Epworth, cloud photo processing and clinical interpretation require their separate instrument/privacy/product review. No automatic medication, alarm, dose-adjustment or fitness-to-drive claim.

## Evidence and acceptance

The supplied agent review's four implementation hashes matched baseline eae0f7ad: HealthKitService 0a3e3d2494634a6c66f98d5b5d37864607ede241; NightOutcome fc3b9e565db2f8e6a05cf783b8ef728aedc1f066; storage a566b2054c5562c79baecee26147d64395c4743b; MedicationConfig ef4bf745bf693ebe3d0e3213b3dc90f3a2ad9c7e. This is source evidence, not phone reproduction.

Required tests include trailing-awake final wake, separated blocks, sample clipping, unknown categories, all-awake zero, missing/partial coverage, duplicate/reordered sources, dose inside wearable sleep, spanning wake episodes, exact boundary timestamps, restart/corrections, midnight/DST/travel and iOS-to-export-to-Studio parity. Preserve all existing dose-confirmation tests. Device Apple Health reconciliation and owner accessibility/workflow acceptance remain open.

## First implementation slice

DOSETAP-51 begins with an allowlist for remembered room temperature, noise setup and non-medication sleep aids. Daily observations and questionnaire dose-plan amounts do not copy from the last night. Applying room setup fills only unanswered setup fields and leaves current/History answers unchanged. The new unit regression first failed against the old code.

Quantity/time bootstrap, optional substance amounts, legacy adapter defaults and morning-questionnaire carry-forward remain explicit follow-up audits. Do not call the entire freshness/default problem closed based on this slice.
