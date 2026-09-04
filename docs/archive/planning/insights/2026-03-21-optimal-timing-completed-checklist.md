# DoseTap Insights Optimal Timing TODO

> Archived on 2026-09-02. Every item in this dated checklist was marked complete, so it is retained as implementation history rather than an active TODO. Current validation status is in `docs/INSIGHTS_STATUS.md`.

Last updated: 2026-03-21
Owner: Product / Engineering
Status: Active

## Purpose

Turn DoseTap + DoseTapStudio into a trustworthy read-only insights system that helps answer:

`Within the prescribed 150-240 minute second-dose window, which timing bands are associated with better sleep and better next-day function for comparable nights?`

This work must remain observational and clinician-friendly.
It must not behave like a prescriptive drug dosage calculator.

---

## Product Goal

- [x] Build a high-confidence insights pipeline for second-dose timing analysis.
- [x] Export HealthKit and WHOOP nightly facts from iPhone into DoseTapStudio.
- [x] Classify nights by context so work nights, off nights, and shift-transition nights are not mixed together.
- [x] Add a confidence-scored recommendation layer based on historical comparable nights.
- [x] Add clinician/export-friendly summaries with provenance, exclusions, and missing-data flags.

## Non-Goals

- [x] Do not create a second write-capable tracker app.
- [x] Do not present recommendations as medical advice.
- [x] Do not recommend dosing outside the prescribed 150-240 minute window.
- [x] Do not use iCloud / CloudKit for identifiable protected health information.
- [x] Do not ship an opaque "AI score" without visible rationale.

---

## Phase 0: Contract And Trust First

- [x] Normalize event aliases at import and export boundaries.
- [x] Accept legacy event names: `dose1`, `dose2`, `lightsout`.
- [x] Export canonical event names: `dose1_taken`, `dose2_taken`, `lights_out`.
- [x] Reject impossible intervals such as negative values.
- [x] Reject or flag intervals above allowed bounds when they conflict with event timelines.
- [x] Flag session count mismatches between `sessions.csv` and `insights_bundle.json`.
- [x] Flag duplicate lights-out and duplicate wake-final events.
- [x] Add data-quality flags to every imported night.
- [x] Add source provenance for every metric: `manual`, `healthkit`, `whoop`, `derived`.
- [x] Update stale docs that still describe HealthKit as sleep-only.
- [x] Reconcile WHOOP token-refresh assumptions and scope requirements.

## Phase 1: Export Contract v2

- [x] Add versioned `insights_bundle_v2.json`.
- [x] Keep current CSV export stable for backward compatibility.
- [x] Include raw events and normalized events in the bundle.
- [x] Include app version, export version, schema version, device timezone, and local offset.
- [x] Include consent state for Apple Health and WHOOP at export time.
- [x] Include per-session data-quality flags.
- [x] Include per-session source availability flags.
- [x] Include import warnings summary for DoseTapStudio.

### `insights_bundle_v2.json` must include

- [x] Session identity and canonical session date.
- [x] Dose 1 / Dose 2 timestamps.
- [x] Dose 2 skipped / early / late / reconciled flags.
- [x] Raw event list for the night.
- [x] Pre-sleep form data.
- [x] Morning check-in data.
- [x] Medication log entries.
- [x] HealthKit nightly summary.
- [x] WHOOP nightly summary.
- [x] Night classification fields.
- [x] Data quality / provenance / exclusions.

---

## Phase 2: Gather The Right Data

### Core dosing context

- [x] Capture whether Dose 2 followed natural wake or alarm wake.
- [x] Capture alarm scheduled time, first fire time, acknowledgement time, and snooze count.
- [x] Capture why Dose 2 was early, late, or skipped.
- [x] Capture Dose 2 reason live at action time, not only during morning reconciliation.
- [x] Capture back-to-sleep latency after Dose 2.
- [x] Capture meal timing before Dose 1 and Dose 2.
- [x] Capture whether last meal was heavy meal vs snack.

### Patient context

- [x] Capture diagnosed sleep disorders and status.
- [x] Capture CPAP / oral appliance use and adherence when relevant.
- [x] Capture stimulant and sedating co-medications.
- [x] Capture pain burden, anxiety, congestion, reflux, restless legs symptoms, bathroom urgency.
- [x] Capture clinician-reviewed pharmacogenomic context as reference metadata, not dosing logic.

### Schedule / work context

- [x] Capture work night vs off night.
- [x] Capture shift start and end times.
- [x] Capture first night off after work block.
- [x] Capture transition into work block.
- [x] Capture next required wake time and commute burden.
- [x] Capture whether wake time was self-selected vs forced by work.

### Sleep context

- [x] Capture natural wake vs alarm wake vs forced wake.
- [x] Capture sleep inertia duration.
- [x] Capture next-day function relevant to work safety and driving confidence.
- [x] Capture cataplexy / daytime sleepiness burden if the product already supports it or can add it safely.

---

## Phase 3: Health Data Export

### Apple Health nightly summary

- [x] Export sleep onset, final wake, and time to first wake.
- [x] Export total sleep minutes.
- [x] Export awake minutes / wake count / WASO proxy.
- [x] Export deep / REM / core / in-bed durations.
- [x] Export average heart rate.
- [x] Export HRV SDNN.
- [x] Export resting heart rate.
- [x] Export respiratory rate.
- [x] Export source app / device when available.

### WHOOP nightly summary

- [x] Export recovery score.
- [x] Export resting heart rate.
- [x] Export HRV RMSSD.
- [x] Export respiratory rate.
- [x] Export sleep efficiency percentage.
- [x] Export sleep performance percentage.
- [x] Export sleep consistency percentage.
- [x] Export disturbance count.
- [x] Export stage durations and total awake time.
- [x] Export sleep debt / sleep needed components when available.
- [x] Export SpO2 percentage.
- [x] Export skin temperature.

---

## Phase 4: Night Classification

- [x] Add a night classification model in the shared insights layer.
- [x] Separate `work_night` from `off_night`.
- [x] Add `transition_into_work_block`.
- [x] Add `transition_out_of_work_block`.
- [x] Add `post_shift_recovery_night`.
- [x] Add `natural_wake_night`.
- [x] Add `alarm_dependent_night`.
- [x] Add `high_pain_night`.
- [x] Add `high_stress_night`.
- [x] Add `high_sleep_disruption_night`.

### Required rule outputs per night

- [x] Comparable cohort key.
- [x] Exclusion reasons.
- [x] Confidence bucket: `high`, `medium`, `low`, `insufficient`.
- [x] Whether the night should count toward recommendation training.

---

## Phase 5: Recommendation Engine v2

- [x] Keep recommendation framing observational.
- [x] Only compare candidate timing bands inside 150-240 minutes.
- [x] Start with timing bands: `150-165`, `166-180`, `181-210`, `211-240`.
- [x] Compare bands only within comparable night cohorts.
- [x] Require minimum sample sizes before surfacing a recommendation.
- [x] Surface "not enough evidence" instead of low-confidence output.
- [x] Add explanation output listing matched nights and excluded nights.
- [x] Add separate modes:
- [x] `best_restful_sleep`
- [x] `best_natural_wake_probability`
- [x] `best_next_day_function`
- [x] `best_work_night_safety`

### Ranking inputs

- [x] Morning sleep quality.
- [x] Morning readiness.
- [x] Natural wake probability.
- [x] Alarm dependence rate.
- [x] Sleep inertia severity.
- [x] Skip / late risk.
- [x] Total sleep.
- [x] Deep / REM / core balance.
- [x] Disturbance count / awakenings.
- [x] HRV.
- [x] Resting HR.
- [x] Respiratory rate.
- [x] Sleep efficiency.

### Required recommendation output

- [x] Recommended timing band.
- [x] Confidence score and confidence label.
- [x] Comparable cohort description.
- [x] Nights used / nights excluded.
- [x] Top factors associated with better outcomes.
- [x] Clear statement that this is not prescribing guidance.

---

## Phase 6: DoseTapStudio UX

- [x] Add a data-quality dashboard before any recommendation card.
- [x] Add an availability matrix showing which nights have HealthKit, WHOOP, pre-sleep, and morning data.
- [x] Add a "night type" filter.
- [x] Add a "work schedule" filter.
- [x] Add a "natural wake vs alarm" filter.
- [x] Add a recommendation details screen.
- [x] Add matched-night comparison tables.
- [x] Add clinician-facing summary export.
- [x] Add confidence and exclusion callouts to charts and cards.

### Studio screens to add or extend

- [x] Library: quality and source badges.
- [x] Night Detail: source provenance + comparable cohort key.
- [x] Trends: segmented by night type.
- [x] Correlations: segmented by work pattern and wake type.
- [x] Export Desk: clinician and self-review packages.

---

## Phase 7: Enterprise-Grade Data Controls

- [x] Keep iPhone as the only HealthKit / WHOOP ingestion point.
- [x] Keep Studio read-only.
- [x] Add immutable raw export payloads.
- [x] Add normalized fact tables in the insights layer.
- [x] Add provenance tags for every derived metric.
- [x] Add anomaly detection and surfaced warnings.
- [x] Add redaction support for clinician exports.
- [x] Add audit-friendly generation metadata to exports.
- [x] Encrypt local persisted exports where appropriate.
- [x] Document retention, deletion, and sharing behavior.

---

## Phase 8: Validation And Testing

- [x] Add importer tests for alias normalization.
- [x] Add tests for impossible intervals and mismatched bundle counts.
- [x] Add tests for timezone and DST edge cases.
- [x] Add tests for work-night classification.
- [x] Add tests for natural-wake vs alarm-wake logic.
- [x] Add tests for recommendation minimum-sample thresholds.
- [x] Add tests ensuring recommendations never leave the 150-240 minute window.
- [x] Add fixture bundles for:
- [x] clean nights
- [x] shift-work nights
- [x] missing-data nights
- [x] duplicate-event nights
- [x] contradictory-data nights

---

## Immediate Next Coding Pass

- [x] Normalize event aliases in Studio import.
- [x] Add data-quality validator for sessions and bundles.
- [x] Extend bundle schema to include HealthKit and WHOOP nightly summaries.
- [x] Add availability and quality badges in Studio.
- [x] Add recommendation v2 schema and placeholder confidence model.

---

## Product Constraints

- [x] Keep language as "insight", "pattern", or "historically associated with".
- [x] Do not present this as a dosage calculator.
- [x] Remind users to follow prescriber guidance before making medication decisions.
- [x] Keep all second-dose recommendations inside the prescribed window.
- [x] Do not store identifiable PHI in iCloud / CloudKit.

---

## Reference Sources

- WHOOP API docs: https://developer.whoop.com/api/
- WHOOP webhooks docs: https://developer.whoop.com/docs/developing/webhooks/
- XYWAV prescribing information PDF: https://www.xywav.com/pdf/xywav.en.USPI.pdf
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple Developer Program License Agreement: https://developer.apple.com/support/terms/apple-developer-program-license-agreement/
- Sodium oxybate overview: https://www.ncbi.nlm.nih.gov/books/NBK562283/
