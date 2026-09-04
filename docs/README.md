# DoseTap documentation index

Status: Current documentation governance
Last verified: 2026-09-02

This file classifies the complete `docs/` tree. A directory status applies to every descendant unless a file has a more specific status notice. A dated report remains valid evidence for the date it records, but it is not evidence of current behavior.

## Authority order

Use these sources in this order:

1. `docs/SSOT/README.md` and its current contracts define intended shipping behavior and safety rules.
2. Compiled source, Xcode target membership, migrations, and tests show what the checked-out build actually does.
3. Current architecture and operations documents explain those sources without replacing them.
4. Plane owns work status, priority, assignment, and completion state.
5. Audit, review, handoff, proposed, and archived documents provide context only.

If the SSOT and the compiled implementation disagree, treat that as a defect. Do not hide it by declaring either side correct without reconciliation and evidence.

## Lifecycle labels

| Label | Meaning |
| --- | --- |
| Current authority | Maintained contract for intended behavior. Changes require matching code and tests. |
| Current reference | Maintained explanation or source map. It may summarize authority but cannot override it. |
| Current runbook | Maintained procedure. A successful local command does not prove external or physical acceptance. |
| Tracking index | Maintained pointer to Plane and evidence. Plane remains the status owner. |
| Planned or proposed | Approved for consideration or implementation, but not shipped behavior. |
| Point-in-time evidence | Accurate only for the named date, commit, device, or run. |
| Historical or superseded | Retained for traceability. Paths, counts, and claims may be obsolete. |
| Design asset | Source material, not proof that a UI or target ships. |

## Current documents at `docs/` root

| File | Lifecycle | Purpose |
| --- | --- | --- |
| `README.md` | Current reference | Documentation governance and complete tree classification |
| `PLANNING.md` | Tracking index | Plane projects, modules, release blockers, and proposed work |
| `FEATURE_TRIAGE.md` | Current reference | Code-backed feature status with validation limits |
| `PRODUCTION_READINESS_CHECKLIST.md` | Current runbook | Release gates; it does not grant release approval |
| `RELEASE_CHECKLIST.md` | Current runbook | Per-release automated and manual checks |
| `TESTING_GUIDE.md` | Current runbook | Test discovery, commands, and evidence classes |
| `DATABASE_SCHEMA.md` | Current authority | Human-readable mirror of the SQLite schema source |
| `DIAGNOSTIC_LOGGING.md` | Current reference | Diagnostic contract and privacy boundary |
| `HOW_TO_READ_A_SESSION_TRACE.md` | Current runbook | Diagnostic trace review procedure |
| `COMPANION_TARGET_STATUS.md` | Current authority | iPhone-only shipping status and proposal promotion gates |
| `INSIGHTS_STATUS.md` | Current reference | DoseTap Studio implementation and open validation gates |
| `INSIGHTS_DATA_GOVERNANCE.md` | Current authority | Insights export, retention, deletion, sharing, and language rules |
| `WHOOP_INTEGRATION.md` | Current reference | Implemented integration boundary and unverified live-service gates |
| `CLOUDKIT_GO_LIVE_CHECKLIST.md` | Planned validation runbook | Staging-only sync validation; not shipping sync status |
| `CERTIFICATE_PINNING.md` | Current runbook | Pin configuration and release validation procedure |
| `APPLE_DEV_CLI_SETUP.md` | Current runbook | Repository-owned Apple command helpers |
| `TESTFLIGHT_GUIDE.md` | Current runbook | Distribution procedure with external portal gates |
| `BRANCH_PROTECTION.md` | Current runbook | Recommended GitHub configuration; remote state must be re-read |
| `REPOSITORY_HYGIENE.md` | Current runbook | Repository and generated-cache checks |
| `privacy-policy.html` | Current publication source | Policy page source; deployed content must be checked separately |
| `support.html` | Current publication source | Support page source; deployed content must be checked separately |

## Directory classification

| Directory | Inherited lifecycle | Notes |
| --- | --- | --- |
| `SSOT/` | Current authority | Current behavior contracts. Contract-specific exceptions are listed in `SSOT/contracts/README.md`. |
| `architecture/` | Current reference | Maintained decision records and boundary maps only. Old inventories were archived. |
| `MYWAV_DOSETAP/` | Planned or proposed | Possible vNext product and partner package. Nothing in this folder is shipping merely because it is in the repository. |
| `audit/` | Point-in-time evidence | Dated audit output. The latest audit recommendation remains a release input until its Plane gates close. |
| `review/` | Point-in-time evidence | Dated reviews and design decisions. A review becomes current authority only when promoted into SSOT or code. |
| `handoff/` | Planned or proposed | Dated rebuild package and ADR proposal. Not the current implementation plan. |
| `prompt/` | Current audit tooling | Reusable prompts. Examples and expected paths must be verified before each run. |
| `icon/` | Design asset | SVG and notes. The Xcode asset catalog determines the shipping icon. |
| `historical/` | Historical or superseded | Older retained materials. New superseded work belongs under `archive/`. |
| `archive/` | Historical or superseded | Dated snapshots, retired reports, obsolete plans, and replaced architecture inventories. |

## Current planning and evidence

- Plane index: `docs/PLANNING.md`
- Latest full audit: `docs/audit/2026-08-31/`
- Latest data-integrity delta audit: `docs/audit/2026-09-01/`
- Whole-project CRUD matrix: `docs/audit/2026-09-01/crud-matrix.md`
- Proposed vNext package: `docs/MYWAV_DOSETAP/README.md`

## Maintenance rules

- Do not publish hardcoded test totals or source line counts as evergreen facts. Use discovery commands and date any captured result.
- Do not use `Implemented`, `Complete`, `Production Ready`, or `Shipped` when runtime, signed-device, privacy, legal, external-service, or owner-observed gates remain open.
- Move completed checklists and superseded reports into `docs/archive/` with a direct archive notice.
- Put dated evidence in `docs/audit/` or `docs/review/`; do not rewrite it to describe a later checkout.
- Add proposed product behavior to a clearly labeled proposal. Promote it into SSOT only with an approved implementation slice.
- Run `bash tools/doc_lint.sh` and `bash tools/ssot_check.sh` after changing current documentation.
