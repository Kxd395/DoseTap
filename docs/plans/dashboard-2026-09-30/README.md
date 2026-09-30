# September 30 dashboard consolidation and delivery roadmap

Date: 2026-09-30.
Status: proposed implementation roadmap; no dashboard feature is delivered by this documentation change.
Code review baseline: upstream `main` at `99914e4e77a0a0655e0c6a41383a5a274c39b91f`.
Authority: [SSOT](../../SSOT/README.md) defines implemented behavior; Plane owns live priority, assignment and acceptance. This roadmap consolidates requirements without changing medication, alarms, records or the SSOT.

## Preserved inputs

The four owner-supplied documents below are preserved unchanged. Their September 24 export observations and screenshots are historical evidence, not a current schema audit or proof of clinical validation. [Source manifest](SOURCE_MANIFEST.json) records file hashes.

- [Dashboard and interval-explorer blueprint](DoseTap_Dashboard_Blueprint_2026-09-30.md): shared views, interactions, metric eligibility and reporting.
- [Work-block addendum](DoseTap_Work_Block_Dashboard_Addendum_2026-09-30.md): effective schedules, work history and surrounding-sleep phases.
- [Single-dose and dose-pattern views](DoseTap_Single_Dose_and_Dose_Pattern_Views_2026-09-30.md): retain usable sleep independently of dose-spacing eligibility.
- [Daytime check-in and visit preparation](DoseTap_Daytime_CheckIn_and_ESS_Prep_2026-09-30.md): independent observations, prompt history and unscored visit context.

## Shared decisions before implementation

1. **Identity:** retain a stable treatment/session ID and a separate provider sleep-episode ID with an explicit association. A treatment date is a grouping label, never the unique observation ID. Multiple sessions on one date remain selectable; ambiguous associations stay unresolved. Provider-only or confirmed no-dose sleep can exist without creating a medication action.
2. **Metric contract:** one versioned domain contract owns units, occurrence timestamps, source policy, selected pair/endpoint IDs, eligible inputs, calculation version, coverage and exclusion reasons. Each result distinguishes available, partial, unavailable, not applicable and needs review. Record-count completeness and timestamp completeness are independent. Views, accessible tables, exports and Studio consume the same derivation.
3. **Sleep boundaries:** retain existing primary-episode sleep separately from reviewed-window sleep. Dashboard totals currently use the selected main provider episode; the reviewed projection is a checked, point-in-time coverage result and does not replace those totals. Apple Health sleep ending, an explicit diary final awakening, Wake Up capture and check-in completion remain different times. A later check-in cannot extend measured sleep.
4. **Coverage:** sum eligible deduplicated asleep intervals inside the declared window; keep awake, unmeasured and conflicting time explicit. Projection conflict minutes are already included in unmeasured minutes, so do not add them again. All-awake observed zero differs from absent data. Do not infer gaps are awake, reconstruct stages from totals or turn categorical duration answers into exact minutes.
5. **Ranges:** support 7/28/90-day views, 6/12 calendar months, since last completed visit and custom bounds with a declared timezone/cutoff. Six calendar months is not 180 days. Completed-visit history survives appointment cancellation/rescheduling; a future cutoff is invalid. Provider coverage can be shorter than the requested report and must be disclosed.
6. **Refresh:** preserve the last successful snapshot and stable selection on transient refresh failure, with its as-of time, query bounds and stale indication. Distinguish failure, empty success, disabled integration and revoked consent. Recheck current identity/window/records before publishing asynchronous results. A stale cache cannot certify current coverage or bypass consent controls.
7. **Dose patterns:** store historical regimen, session plan, reported administrations and explicit slot outcomes separately. Plan is not administration; patient-entered prescription is not clinician verification. Missing D2 is unresolved, not skipped. A completed check-in is not confirmation of administration count. Unknown actual amounts remain unknown, and raw/normalized representations do not double the count.
8. **Pairing:** D1–D2 spacing requires two distinct relevant administrations with usable occurrence times in the same resolved session. Single/no-dose sessions have no interval; missing times yield unavailable; nonpositive/conflicting pairs require review. No zero/sentinel/expected-time substitute. Post-D2 sleep is not applicable without D2 and unavailable when its occurrence is unknown; total sleep is a separate cross-pattern measure.
9. **Work context:** one versioned classification uses effective schedule dates, timezone, planned versus confirmed attendance, exceptions and explicit sleep/shift associations. The reported Tuesday–Thursday 13-hour schedule has no confirmed start/end or effective date. Preserve those unknowns; do not infer attendance, historic roster coverage or shift-midpoint clock time. Under the daytime-shift assumption, Monday night enters the block and Thursday night is first post-block sleep; naps do not advance that position.
10. **Chart semantics:** in the combined sleep-by-night view use dose-count marks and a labeled work-phase strip or separate phase panels. Do not assign both work phase and dose count to shape. A spacing-reference view has its own explicitly switched mapping and non-prescriptive reference label. Plot, legend, selected detail, accessibility and export derive from one mapping; missingness stays independent across dose, sleep and work dimensions.
11. **Daytime grain:** append one independent assessment ID per observation, with assessed-at, recorded-at, recall/review bounds, instrument/content version and optional prompt/event links. It must not require or create a night session. Keep scheduled, user-initiated and retrospective entries distinct; a delayed response assesses its actual current window, not the intended reminder time. Existing event links and evening review do not duplicate events.
12. **Instrument decision:** the [September 25 roadmap](../2026-09-25-daytime-treatment-roadmap.md) starts with a custom 0–10 diary; the new addendum proposes authorized KSS. Retain those as different instruments and require an explicit content/version decision before named-scale enablement. Do not convert old ratings to KSS, infer diagnosis, derive ESS from diary/KSS, interpolate missing formal items or combine scales. ESS/KSS/NSS content and electronic-use review remain separate release gates.

## Current implementation mapping

These are reuse/audit entry points at the baseline, not claims that all proposed contracts exist.

| Responsibility | Existing source | Required follow-on |
| --- | --- | --- |
| Aggregate identity and provider refresh | [DashboardAnalyticsRefresh.swift](../../../ios/DoseTap/Views/Dashboard/DashboardAnalyticsRefresh.swift), [DashboardTypes.swift](../../../ios/DoseTap/Views/Dashboard/DashboardTypes.swift) | Replace date-key aggregate identity/joins with reviewed session/episode associations. Current WHOOP fetch caps at 30 days; current 6M is 180 dates. Define historical loading and stale-snapshot behavior. |
| Main provider episode and source choice | [HealthKitService.swift](../../../ios/DoseTap/HealthKitService.swift), [DashboardAnalyticsSupport.swift](../../../ios/DoseTap/Views/Dashboard/DashboardAnalyticsSupport.swift) | Preserve primary-episode definition and named Apple Health/WHOOP sources. Broader reviewed-night adoption requires explicit metric/version reconciliation. |
| Reviewed bounds, coverage and dose/sleep markers | [ReviewedNightSleepProjection.swift](../../../ios/Core/ReviewedNightSleepProjection.swift), [ReviewedNightSleepLoader.swift](../../../ios/DoseTap/Services/ReviewedNightSleepLoader.swift), [ReviewedDoseSleepMetrics.swift](../../../ios/Core/ReviewedDoseSleepMetrics.swift) | Reuse current-input checks and invalidation. Add consumer/export parity deliberately; do not claim durable provider revision/deletion reconciliation or complete awakening counts. |
| Explicit diary versus session lifecycle | [NightOutcome.swift](../../../ios/Core/NightOutcome.swift), [SessionRepositoryCheckIn.swift](../../../ios/DoseTap/Storage/SessionRepositoryCheckIn.swift), [SessionRepository.swift](../../../ios/DoseTap/Storage/SessionRepository.swift) | Preserve final-awakening provenance and session closure. Add explicit count/outcome reconciliation without retrospective catch-up alarms. |
| Schedule and dated exceptions | [SessionRepositorySchedule.swift](../../../ios/DoseTap/Storage/SessionRepositorySchedule.swift), [weekly schedule SSOT](../../SSOT/README.md#weekly-wake-schedule-dosetap-41-build-71) | Audit source anchors; add effective roster versions/shift occurrences and shared phase derivation. Existing wake requirements are not attendance. |
| Medication identities and actual amounts | [MedicationPreset.swift](../../../ios/Core/MedicationPreset.swift), [SessionRepositoryMedication.swift](../../../ios/DoseTap/Storage/SessionRepositoryMedication.swift) | Reuse immutable prescription/admin snapshots where applicable; keep daytime ledger separate from nighttime dose patterns. Do not invent actual amount from a plan. |
| Daytime and report foundations | [daytime delivery roadmap](../2026-09-25-daytime-treatment-roadmap.md), [sleep-marker roadmap](../2026-09-08-sleep-markers-roadmap.md) | New independent observations, prompt/review records, completed-visit anchor and reproducible report snapshots remain required. |

## Delivery stages and acceptance

Each stage begins with the exact Plane preflight and a bounded SSOT contract, followed by failing domain tests before code. Reuse existing tracker ownership; search for equivalent scope before creating new work. Stages below are an implementation sequence, not committed delivery dates.

| Stage | Deliverable | Acceptance before advancing |
| --- | --- | --- |
| 1. Foundations | Shared session/episode association, metric state/version contract, ranges and provider freshness. | Two sessions on one date never collapse; ambiguous joins remain visible; UTC duration/DST/travel fixtures pass; 6-calendar-month and 180-day fixtures differ; failure retains correctly labeled prior data; edited inputs invalidate derived results. |
| 2. Sleep by night and dose pattern | Default nightly sleep view, explicit count subtypes and categorical companion to valid paired intervals. | Planned one-dose, explicitly omitted D2, incomplete history, two doses with unknown time, extra/conflicting reports and confirmed zero-dose retain separate states. Valid sleep survives missing interval; unavailable sleep is never zero. Corrections recompute with source lineage; historical plans are not current defaults. |
| 3. Replay and coverage | Session replay, dose-aligned inspection and one declared-window coverage panel; curated interval presets first. | Primary-episode and reviewed-window totals are visibly distinguished; sample splits do not inflate awakenings; gaps/conflicts/overlapping sources preserve accounting; manual and provider endpoints remain separate; current screen/table/export/Studio values agree under identical definitions. |
| 4. Work block | Shared planned/confirmed phase classification, block profile and matrix. | Entering/between/first-post-block/off-block synthetic cases, missing main sleep, cancelled/extra shifts, effective schedule changes and unknown actual times pass. No invented attendance, midpoint or recovery status; distinct-block and per-metric counts visible. |
| 5. Optional daytime check-in | One user-selected routine reminder, independent current assessment, optional activity/coping and linked event review. | No implicit night creation; repeated observations/failed-save retry/revisions preserve identity; delayed/skip/defer/nonresponse stays explicit; sleep/quiet settings and permission states respected; morning/evening questions are reused without duplicate assessments; usability target tested with the owner. |
| 6. Physician review | Full-period, monthly and recent-detail layers plus patient-reviewed unscored visit notes and preview/share snapshot. | Since-visit anchor ignores cancelled bookings; instrument/regimen/source changes remain visible; every metric has eligible/available counts and assessed-day coverage; serious/ambiguous reports remain in selected review detail; redaction/formula-safe round trip and screen/export parity pass. Sharing requires explicit action. |

Keep the fully custom interval explorer, predictive/medication models, causal rankings, automatic dose adjustments, wear-off/clearance displays and automated physician sharing out of these stages. Optional medication estimates require a separate reviewed specification under DOSETAP-75; they are not measured drug levels or a dependency for the first dashboard.

## Tracker ownership and open gates

Plane preflight on 2026-09-30 returned the states below. This is a dated navigation snapshot, not a replacement for live preflight. DOSETAP-79 owns this documentation consolidation/main-workspace reconciliation; it does not claim implementation of the dashboard stages.

| Exact item | State at readback | Related scope and gates |
| --- | --- | --- |
| DOSETAP-45 | In Progress | Dashboard calculations, representation, source labels and consumer/export parity; owner comparison across real nights, accessibility, iPad and release performance remain open. |
| DOSETAP-56 | In Progress | Sleep boundaries/evidence, reviewed-window coverage and wider consumer adoption; durable provider reconciliation and real Apple Health/device evidence remain separate. |
| DOSETAP-57 | In Progress | Dose/sleep/wake markers and forthcoming [awakening-count contract](../../SSOT/contracts/reviewed-awakening-counts.md); delivered inspection is not complete counts or wider screen/report acceptance. |
| DOSETAP-58 | Todo | Independent daytime observations, event/day review and nap/rest scope; reminder/device/privacy/owner acceptance and instrument authorization remain open. Do not start merely to record this plan. |
| DOSETAP-59 | Todo | Clinician report preset; report-period contract, parity, privacy/owner review and explicit sharing acceptance remain open. |
| DOSETAP-75 | In Progress | Medication-estimate profiles and independent regimen-alarm specification; model/content approval and any later implementation are separate from descriptive dashboards. |

Before the work-block or dose-pattern stages, record their reviewed bounded scope in the matching existing item or create an exact deduplicated item if needed. A proposed chart alone cannot close a measurement, phone, provider, instrument or release gate.

## Verification and closeout

For this documentation slice, run `bash tools/doc_lint.sh`, `bash tools/ssot_check.sh`, `bash tools/check_plane_workflow.sh`, `git diff --check`, local link checks and original-file SHA-256 comparisons. These prove source preservation/navigation, not implementation.

For future behavior slices follow [TESTING_GUIDE.md](../../TESTING_GUIDE.md) and [WORKFLOW.md](../../../WORKFLOW.md): core/domain tests, touched-area storage/app tests, UI accessibility/table inspection, export/Studio parity, provider permission/offline/partial coverage, and signed-device/owner gates as applicable. Record commit, exact commands, destination, outcomes and evidence class. Apply structured closeout and verify independent Plane readback; keep In Progress while any acceptance gate remains.
