# DoseTap planning index

Status: Current tracking index
Last verified: 2026-09-12 (navigation; dated status snapshots below retain their original scope)
Tracker: Plane, Dark Water Drones workspace

Plane owns issue status, priority, assignment, and completion. This file is a repository map so a reader can find the active work without treating an old Markdown checklist as the tracker.

## Plane locations

- [DoseTap issues](http://plane.localhost:3301/dark-water-drones/projects/f2300d5b-01c5-4b0d-b930-34a954db2f2e/issues/)
- [Data Integrity and Dashboard Alignment module](http://plane.localhost:3301/dark-water-drones/projects/f2300d5b-01c5-4b0d-b930-34a954db2f2e/modules/0b6ed408-3432-453b-a030-c8193cf40ebd)
- [Supply-Cycle Reminder and Dose Safeguards module](http://plane.localhost:3301/dark-water-drones/projects/f2300d5b-01c5-4b0d-b930-34a954db2f2e/modules/d919c1d5-6b84-4405-8f3f-f25f0ad1a22c)

## Current delivery and data-review navigation

| Area | Evidence and next scope | Plane owner |
| --- | --- | --- |
| Collection, storage and export audit | [Reading guide and field inventory](audit/2026-09-12/README.md); findings are pinned to build 50 and must be read with subsequent deliveries. | DOSETAP-39; export findings DOSETAP-13 |
| Repository review and closeout | [Legacy patch dispositions](review/2026-09-12-legacy-patch-disposition.md) and [validator/acceptance review](review/2026-09-12-plane-closeout-review.md); retained branch and owner-gate decisions are explicit. | DOSETAP-63; DOSETAP-13/19/27 |
| Durable quick/general-medication logs | [Build 51 delivery](review/2026-09-12-durable-log-delivery.md): commit-before-success and explicit retry; broader CRUD, restart and physical acceptance remain separate. | DOSETAP-3 / DOSETAP-39 |
| Stored-record export fidelity | [Build 52 delivery](review/2026-09-12-export-fidelity-delivery.md): uncapped inventory and stored medication metadata, checked discovery/reads; complete archive/restore acceptance remains separate. | DOSETAP-13 |
| Work/off sleep averages and owner data review | [Inventory and dashboard plan](review/2026-09-11-dashboard-and-collected-data-review.md): following-workday groups, transitions and explicit denominators are proposed. | DOSETAP-45 |
| Dose/sleep and awakening inspection | [Build 46 metrics](review/2026-09-11-dose-sleep-metrics-delivery.md) and [build 48 Timeline inspection](review/2026-09-11-timeline-awakening-delivery.md); wider consumer adoption, counts and real-provider acceptance remain separate. | DOSETAP-57 |

These links identify bounded delivery evidence, not current issue states or release approval. Re-read each exact Plane item before starting or closing work.

## Earlier release-critical snapshot

The following table preserves the September 7 documentation snapshot with later linked notes. It is not a live backlog or an exhaustive list of subsequent deliveries; use the navigation above and Plane for current decisions.

The latest audit recommendation is `HOLD`. The current integration decision record is `docs/audit/2026-09-05/integration-readiness.md`; the preceding full data-integrity findings remain in `docs/audit/2026-09-01/findings.md`.

| Plane item | Status represented in repository evidence |
| --- | --- |
| DOSETAP-49 | High, In Progress. Dose 2 Natural / Alarm confirmation choices and a shared morning/History diary feed explicit-wake comparisons, timestamped next-day sleepiness, and measured post-dose sleep. Simulator/device acceptance is tracked in `docs/audit/2026-09-07/dose2-wake-outcomes.md`. |
| DOSETAP-50 | High, In Progress. Last-food timing, food type, optional high-fat/oily answer and notes in pre-sleep logging, with History and export support. Label research and acceptance evidence: `docs/audit/2026-09-07/pre-sleep-last-food.md`. |
| DOSETAP-15 | High, In Progress. Owner-requested September 7 reconciliation includes exactly 240 minutes in the window, using elapsed seconds rather than rounded displays. Reversed/invalid timestamps remain rejected; device/export/provider parity remains open. See the wake-outcomes audit. |
| DOSETAP-48 | Medium, In Progress. Automatic Night Mode follows committed active Dose 1 through the night's Wake by time, with an opt-out and session-scoped manual override. Device and owner acceptance remain open. See `docs/audit/2026-09-07/automatic-night-mode.md`. |
| DOSETAP-43 | High, In Progress. The September 7 layout follow-up puts History insights in one row and removes Tonight's duplicate bottom spacer and nested card inset. Standard portrait fit is simulator-tested; owner/device review remains open. See `docs/audit/2026-09-07/compact-tonight-layout.md`. |
| DOSETAP-47 | High, In Progress. Manual dose/sleep History entry and corrections, plus both full questionnaires for a selected past night, are implemented locally. Reviewed transactions preserve original evidence and keep questionnaire saves separate from medication and active-session effects. Signed-device, owner, accessibility, and broader integration gates remain open. See `docs/audit/2026-09-07/manual-history-entry.md`. |
| DOSETAP-46 | Urgent, In Progress. Unexpected durable Dose 2 record verified read-only on build 19; original activation remains unresolved. Session-bound explicit confirmation is locally committed and app/targeted simulator tests passed on 2026-09-07. Signed-device acceptance remains open; no historical medication data was changed and no new build was installed. See `docs/audit/2026-09-07/dose2-recording-incident.md`. |
| DOSETAP-1 | Urgent, In Progress. Current-tree credential material is excluded, but Plane key rotation, old-key failure readback, WHOOP provider-side revocation confirmation, and a reviewed history-retention or rewrite decision remain open. |
| DOSETAP-4 | Urgent, In Progress. AlarmKit scheduling is verified locally and overlapping wake-alarm updates now fail closed; locked/Silent/Focus signed-device delivery and owner acceptance remain open. |
| DOSETAP-30 | High, In Progress. Local supply reminders, independent bottle records, bounded restore reads, and reconciliation tests exist. The 2026-09-07 UI recheck still failed to show Handled after the test action; signed-device delivery, Files-provider restore, privacy, and accessibility acceptance remain open. |
| DOSETAP-17 | Documentation and schema reconciliation refreshed on 2026-09-02; lifecycle, schema, constants, and SSOT static checks pass. The Plane item remains in Backlog pending tracker triage. |
| DOSETAP-34 | P0 partial. Warning-first retrospective Dose 2 recording exists; recovery review and signed-device capture remain open. The separate wake-date work warning is tracked by DOSETAP-41. |
| DOSETAP-35 | P0 automated evidence complete. Cross-midnight export and Studio identity were corrected. |
| DOSETAP-10 | P1 partial. Deterministic Apple Health work exists; signed-device grant, denial, no-data, and parity checks remain open. |
| DOSETAP-36 | P1 automated evidence complete. Dashboard denominators and source labels were corrected. |
| DOSETAP-37 | P1 partial. Current timezone UI exists; per-event historical timezone provenance and physical validation remain open. |
| DOSETAP-38 | P1 partial. Failure and retry correlation tests exist; signed-device diagnostic evidence remains open. |
| DOSETAP-39 | P1 partial. CRUD inventory exists; clear-all, sync convergence, and content-equal restore evidence remain open. |
| DOSETAP-40 | Repository preflight/closeout and evidence-content readback are implemented. The workflow before_run hook refuses unattended execution. Future enablement still requires a reviewed native Plane adapter and non-dispatchable handoff; no runner has been enabled. See the September 9 quick-win audit and Plane for closure evidence. |
| DOSETAP-41 | High, In Progress. Wake-date work warnings and persistent one-day nonworking exceptions are integrated; owner/device review remains separate from local evidence. |
| DOSETAP-42 | Urgent, In Progress. UUID-scoped medication writes and mixed-authority protections are integrated; historical-data and signed-device acceptance remain open. |
| DOSETAP-44 | Urgent, In Progress. HealthKit status work no longer blocks the main actor during startup; signed-device grant, denial, stall, and provider observations remain open. |
| DOSETAP-45 | High, In Progress. Dashboard calculations, missingness, source labels, full-view visibility, and build-14 presentation parity are locally tested in 0.4.17; owner comparison across 3–5 real nights, provider parity, accessibility, iPad, and release-performance checks remain open. |

Always re-read Plane before changing an issue state. The table above is a documentation snapshot, not authority to close work.

## Agent completion wiring

Repository agents use `.agents/plane-workflow.yml`, `AGENTS.md`, and `tools/plane_tracker.rb` for exact-key Plane preflight and closeout. The helper is dry-run by default, uses the current `/work-items/` API, updates one internal workpad comment, guards `Done` behind green validation and no open gates, and verifies state plus workpad content with a post-write readback.

`WORKFLOW.md` now selects Plane rather than the archived Linear project. A Symphony runner must provide a compatible Plane tracker adapter and a non-dispatchable handoff policy for items waiting on human or external gates before polling this workflow. If either is unavailable, startup must fail closed; it must never fall back to Linear, continuously re-run gated work, or treat repository-only progress as a Plane update.

The repository enforces the disabled execution path with `ruby tools/plane_tracker.rb unattended-preflight` in the workflow's `before_run` hook. That command always exits nonzero before any Plane request or agent execution. Manual helper commands remain available. This is not a compatible adapter or permission to start polling: future enablement requires reviewed code and installation evidence, not changing a YAML flag or removing the hook. The helper verifies stable workpad contents as well as the closeout marker and state.

The [September 9 quick-win review](audit/2026-09-09/plane-quick-wins.md) records the live inventory and why external acceptance items were not bulk-closed.

## Proposed next version

`docs/MYWAV_DOSETAP/` describes proposed vNext behavior. The supply-cycle feature is a local notification and alarm that helps a user order medication before a cycle ends. It is not a refill request, order, pharmacy acknowledgement, insurance status, shipment status, or clinical eligibility decision.

The proposal remains downstream of the data-integrity foundation and its explicit acceptance gates. See `docs/MYWAV_DOSETAP/README.md` and the supply-cycle Plane module.

## Food and Drink follow-up

The [questionnaire delivery plan](plans/2026-09-10-questionnaire-delivery-plan.md), DOSETAP-69, qualifies the supplied revision and maps delivery to existing items. It prioritizes medication defaults and save reliability before additional questions. Durable draft/skip semantics and broader recurring-symptom identity remain separate work. The later [sleeping-arrangement delivery](review/2026-09-10-sleeping-arrangement-delivery.md), DOSETAP-70, supersedes earlier proposed wording for its implemented planned/actual setup scope; its phone, accessibility and privacy/release gates remain separate.

The [September 10 questionnaire review packet](review/2026-09-10-sleep-questionnaire-review.md), tracked by DOSETAP-68, inventories current pre-sleep/morning choices, independent save boundaries, planned collection and owner-feedback prompts. Its [independent findings](review/2026-09-10-questionnaire-independent-findings.md) identify source/UX issues for scoped follow-up; documentation completion does not close their implementation or device gates.

The [September 8 roadmap](plans/2026-09-08-food-drink-roadmap.md) defines five planned slices: DOSETAP-51 fresh nightly answers, DOSETAP-52 explicit caffeine units, DOSETAP-53 shared daytime intake history, DOSETAP-54 pre-sleep review, and DOSETAP-55 a one-way Foodnoms/Apple Health prototype. Plane owns their live state and priority. DOSETAP-50 keeps the existing last-food scope; DOSETAP-45 and DOSETAP-13 retain analytics/export ownership. This is planned work, not a claim that imports or AI capture are implemented.

## Insights implementation

The [sleep markers roadmap](plans/2026-09-08-sleep-markers-roadmap.md) preserves Apple Health detail and defines DOSETAP-56 measurement corrections, DOSETAP-57 dose/sleep/wake markers and counts, DOSETAP-58 independent daytime observations, DOSETAP-59 clinician reporting and DOSETAP-60 activity-time specification review. The roadmap is a dated plan. DOSETAP-56 has a measurement foundation, and the linked DOSETAP-57 deliveries above add read-only dose/sleep and awakening inspection. They do not complete awakening counts, work/off averages, independent daytime observations or provider/phone acceptance. New analytics depend on corrected boundaries and explicit missingness.

DoseTap Studio is implemented, but product claims remain limited by import quality, data-source parity, physical Apple Health verification, and whole-lifecycle restore evidence. Current source and validation status are in `docs/INSIGHTS_STATUS.md`.

## Archived planning material

Completed and superseded plans are retained under `docs/archive/planning/`. They are useful for rationale and history but do not own current priority or completion state.
