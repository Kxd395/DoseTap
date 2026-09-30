# Dashboard session identity and explicit provider matching

Date: 2026-09-30. Tracker: DOSETAP-45. Scope: local reporting; medication and alarm mutations are unchanged.

The dashboard now reads local contributors in one strict SQLite transaction, preserves exact session IDs, and retains unresolved date-only/orphan evidence separately. Multiple IDs on one date cannot supply each other's dose pair, questionnaires, events, naps or outcome. A read failure retains the prior dashboard with an error. The original regression returned one row for two session IDs; the corrected fixture returns two with no cross-session interval.

Apple Health episode IDs derive from the named source and original observed bounds; WHOOP retains its source sleep ID. The current provider queries still select one primary episode per treatment date. Complete multiple-episode discovery is not delivered by this change.

Date coincidence is never a provider match. An explicit local relationship is bound to the source episode fingerprint, the exact session and the complete local-source fingerprint. Freshness, access epoch and loading guards apply when saving; edited records or provider evidence invalidate use of the relationship. Optimistic revisions and per-provider/session uniqueness prevent stale overwrites. Removing a match does not change medication or provider sleep. Association metadata remains local-only pending the provider transport consent gate.

Automated evidence:

- 922 full core tests passed (879 XCTest and 43 Swift Testing).
- 60 focused iOS tests passed: 3 identity, 4 strict local storage, 8 explicit matching, 26 dashboard audit, 10 provider access and 9 provider snapshot tests.
- Destination: iPhone 17 Pro Max, iOS 26.5, simulator 59B53B2A-7736-488A-A6DD-838B0F7F648B. Derived data: `/tmp/dosetap-identities-tests`.
- Build-for-testing, the required generic simulator build, Plane workflow, architecture/dose-state guards, SSOT/doc checks and whitespace checks passed for the respective implementation commits.
- Local logs: `.build/identity-evidence/` in the identity feature checkout. `red.log` preserves the original runtime failure; `green2.log` and `matching-tests.log` preserve the passing focused suites.

Integration into the final dashboard UI, provider permission/data acceptance, screen/export/Studio parity, signed-device/owner observation and release acceptance remain separate gates. This implementation evidence alone does not close DOSETAP-45.
