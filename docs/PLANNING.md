# DoseTap planning index

Status: Current tracking index
Last verified: 2026-09-04
Tracker: Plane, Dark Water Drones workspace

Plane owns issue status, priority, assignment, and completion. This file is a repository map so a reader can find the active work without treating an old Markdown checklist as the tracker.

## Plane locations

- [DoseTap issues](http://plane.localhost:3301/dark-water-drones/projects/f2300d5b-01c5-4b0d-b930-34a954db2f2e/issues/)
- [Data Integrity and Dashboard Alignment module](http://plane.localhost:3301/dark-water-drones/projects/f2300d5b-01c5-4b0d-b930-34a954db2f2e/modules/0b6ed408-3432-453b-a030-c8193cf40ebd)
- [Supply-Cycle Reminder and Dose Safeguards module](http://plane.localhost:3301/dark-water-drones/projects/f2300d5b-01c5-4b0d-b930-34a954db2f2e/modules/d919c1d5-6b84-4405-8f3f-f25f0ad1a22c)

## Release-critical work

The latest audit recommendation is `HOLD`. The decision record is `docs/audit/2026-09-01/findings.md`.

| Plane item | Status represented in repository evidence |
| --- | --- |
| DOSETAP-17 | Documentation and schema reconciliation refreshed on 2026-09-02; lifecycle, schema, constants, and SSOT static checks pass. The Plane item remains in Backlog pending tracker triage. |
| DOSETAP-34 | P0 partial. Warning-first retrospective Dose 2 recording exists; recovery review and signed-device capture remain open. The separate wake-date work warning is tracked by DOSETAP-41. |
| DOSETAP-35 | P0 automated evidence complete. Cross-midnight export and Studio identity were corrected. |
| DOSETAP-10 | P1 partial. Deterministic Apple Health work exists; signed-device grant, denial, no-data, and parity checks remain open. |
| DOSETAP-36 | P1 automated evidence complete. Dashboard denominators and source labels were corrected. |
| DOSETAP-37 | P1 partial. Current timezone UI exists; per-event historical timezone provenance and physical validation remain open. |
| DOSETAP-38 | P1 partial. Failure and retry correlation tests exist; signed-device diagnostic evidence remains open. |
| DOSETAP-39 | P1 partial. CRUD inventory exists; clear-all, sync convergence, and content-equal restore evidence remain open. |
| DOSETAP-40 | P1 partial. Repository agent preflight/closeout, guarded state changes, and Plane readback are implemented; unattended Symphony polling still needs a compatible Plane adapter. |
| DOSETAP-41 | P1 Todo. Add the wake-date-specific work warning and persistent one-day nonworking exception without turning historical recordability into permission to take medication now. |

Always re-read Plane before changing an issue state. The table above is a documentation snapshot, not authority to close work.

## Agent completion wiring

Repository agents use `.agents/plane-workflow.yml`, `AGENTS.md`, and `tools/plane_tracker.rb` for exact-key Plane preflight and closeout. The helper is dry-run by default, uses the current `/work-items/` API, updates one internal workpad comment, guards `Done` behind green validation and no open gates, and verifies state plus workpad content with a post-write readback.

`WORKFLOW.md` now selects Plane rather than the archived Linear project. A Symphony runner must provide a compatible Plane tracker adapter and a non-dispatchable handoff policy for items waiting on human or external gates before polling this workflow. If either is unavailable, startup must fail closed; it must never fall back to Linear, continuously re-run gated work, or treat repository-only progress as a Plane update.

## Proposed next version

`docs/MYWAV_DOSETAP/` describes proposed vNext behavior. The supply-cycle feature is a local notification and alarm that helps a user order medication before a cycle ends. It is not a refill request, order, pharmacy acknowledgement, insurance status, shipment status, or clinical eligibility decision.

The proposal remains downstream of the data-integrity foundation and its explicit acceptance gates. See `docs/MYWAV_DOSETAP/README.md` and the supply-cycle Plane module.

## Insights work

DoseTap Studio is implemented, but product claims remain limited by import quality, data-source parity, physical Apple Health verification, and whole-lifecycle restore evidence. Current source and validation status are in `docs/INSIGHTS_STATUS.md`.

## Archived planning material

Completed and superseded plans are retained under `docs/archive/planning/`. They are useful for rationale and history but do not own current priority or completion state.
