# Plane quick-win review

Date: September 9, 2026 (America/New_York)
Baseline: `aac05cdf65bb696b2b2d9af8d2a765df822ce88e`, shipping main
Scope: live backlog triage and DOSETAP-40 repository workflow safeguards. No app, medication, schema or build-number change.

## Inventory and selection

Plane returned 67 items, not the earlier 65: 36 In Progress, 9 Todo, 14 Backlog, 7 Done and 1 Cancelled. This means 59 open items, not 67 unfinished implementations. The inventory was read through the repository helper without displaying credentials. Main matched origin/main; the two pre-existing Xcode edits remained outside this work.

The review inspected the whole title/state roster and the detailed criteria or workpads for likely maintenance candidates 15, 17, 19, 22, 23, 27, 37, 38, 40, 44, 51, 60, 63 and 65. It did not repeat a full application audit or certify every other item.

| Candidate | Decision |
| --- | --- |
| DOSETAP-40 | Finish the repository-controlled safeguards and verify manual live readback. Unattended execution stays disabled. |
| DOSETAP-15, 37, 38, 44, 65 | Keep open for their signed-device, export/provider or accessibility requirements. A source merge is not that evidence. |
| DOSETAP-17, 19, 22, 23 | Documentation, architecture or export work still includes broader review/compatibility requirements. Backlog items were not silently claimed. |
| DOSETAP-27, 51, 60 | A forecast contract, unfinished consumption defaults and clinical activity-time specification are not small status-cleanup tasks. |
| DOSETAP-63 | The retained timeline branch still needs a substantial questionnaire/UI/migration comparison. Preserve it and the local Xcode edits. |

## DOSETAP-40 changes and acceptance mapping

The original acceptance contract requires verified manual repository wiring and explicitly fail-closed unattended use until a compatible adapter exists. It does not require enabling a scheduler. Its previous workpad left adapter/handoff readiness open. This slice resolves the repository-controlled part by enforcing refusal, not by claiming those future installation requirements have been met.

- `.agents/plane-workflow.yml` continues to name the exact project, workspace, work-items API and completion states; it explicitly records unattended execution as disabled.
- `unattended-preflight` unconditionally fails before contacting Plane. `WORKFLOW.md` invokes it in `before_run`; the validator checks the exact guarded hook. A test executes that hook and expects exit 1. No service, scheduler or host configuration was changed or started.
- Manual exact-ID preflight remains available and refreshes its inventory. Tests now cover missing and duplicate sequence IDs and ambiguous exact titles.
- A new red test exposed that an unchanged closeout marker could conceal an edited workpad. Verification now compares the summary, changed-file list, validation, open gates and acceptance outcome, as well as the marker and freshly read state. Generated update time and the verifier's Git branch are intentionally not treated as immutable evidence.
- Existing tests retain dry-run defaults, one-workpad upserts, Done validation/open-gate guards, local-host restrictions and exact-title idempotency. Repository CI continues to run the workflow validator; active workflow configuration remains Plane, not Linear.

Future unattended enablement still requires a reviewed native adapter, a non-dispatchable handoff and real installation validation. Removing the guard or flipping the YAML field is not an accepted enablement path. This review does not certify a third-party runner that ignores hooks. Product device, privacy, provider, recovery and release gates remain on their existing items.

## Evidence

The initial added-test run had three failures: absent unattended preflight, stale in-process inventory and marker-only content verification. After correction the workflow tests passed. The stronger verifier also read the existing DOSETAP-67 workpad successfully without rewriting it. Exact final test counts, hosted checks, integration and DOSETAP-40 state belong in its independently verified Plane workpad.

No work item was deleted, reprioritized or reassigned to manufacture progress. No historical health data, retained branch or pre-existing Xcode edit was changed. App version remains 0.4.19 (39).
