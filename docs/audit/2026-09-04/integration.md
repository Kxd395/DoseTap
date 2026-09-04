# Integrity and branch consolidation

Status: Current integration evidence; release remains on hold
Date: 2026-09-04

The owner authorized consolidation of PRs #3-#5 and reviewed uncommitted repository work into main. The integration branch descends from the existing feature history and current remote main. PR #5's retrospective recovery intent and shared UI-test scheme are retained; its obsolete prospective late-dose override and Axxess tracker selection are superseded by the current SSOT and local Plane. Raw review drafts remain in the original checkout.

## Findings and repairs

- DOSETAP-15: one elapsed-second classifier owns the 150-inclusive/240-exclusive medication boundary in live state, policy, analytics, scores, history and exports. Negative absolute intervals no longer become next-day positive intervals.
- DOSETAP-34: correction metadata retains the original rows inside the replacement transaction. History resolves an explicitly identified prior session without reopening it or replacing the active snapshot.
- DOSETAP-41: explicitly saved work identity and three selectable advisory modes are persisted together with dated overrides in SQLite schema 4. The same selected target applies to live actions and actual retrospective occurrence times. Revision checks reject stale editors and stale dose acknowledgements. Date changes never create medication events.
- DOSETAP-42: UUID-scoped dose reads and reconciliation do not match another UUID by date. Legacy NULL/date-string identity remains readable. The coordinator cannot mix repository state with another core projection. Review extended this boundary to skips, undo, annotations and time edits; ambiguous date-only edits are rejected. Database migrations use the SQLite ledger exclusively, commit the operation and ledger together, and preserve unmatched legacy medication rows.
- Clean-checkout validation found ignored public certificate fixtures; exact fixture exceptions are now tracked. Two archived credential snippets were removed. Revocation/history remediation remains DOSETAP-1.

## Acceptance boundaries

This is an engineering integration, not release approval. Signed-device medication/restart/notification/accessibility checks, owner-reviewed historical recovery, lossless whole-project restore, provider acceptance, and credential revocation remain separate Plane gates. Weekly schedule confirmation is deferred and never controls dose eligibility. Current work/wake data is included in whole-database backup; full restore acceptance remains DOSETAP-39.

Tests must run against this integration checkout and remote CI must pass the protected main checks before merge. Final command results and exact commit/PR identity are recorded in Plane closeouts and the PR.
