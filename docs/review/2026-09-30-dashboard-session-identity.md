# Dashboard session identity and explicit provider matching

Date: 2026-09-30. Tracker: DOSETAP-45. Scope: local reporting; medication and alarm mutations are unchanged.

The dashboard now reads local contributors in one strict SQLite transaction, preserves exact session IDs, and retains unresolved date-only/orphan evidence separately. Multiple IDs on one date cannot supply each other's dose pair, questionnaires, events, naps or outcome. A read failure retains the prior dashboard with an error. The original regression returned one row for two session IDs; the corrected fixture returns two with no cross-session interval.

Apple Health episode IDs derive from the named source and original observed bounds; WHOOP retains its source sleep ID. The current provider queries still select one primary episode per treatment date. Complete multiple-episode discovery is not delivered by this change.

Date coincidence is never a provider match. An explicit local relationship is bound to the source episode fingerprint, the exact session and the complete local-source fingerprint. Freshness, access epoch and loading guards apply when saving; edited records or provider evidence invalidate use of the relationship. Optimistic revisions and per-provider/session uniqueness prevent stale overwrites. Removing a match does not change medication or provider sleep. Association metadata is stored locally. Any companion projection must separately obey the existing provider-sharing opt-in and validate current source/session evidence; this commit does not enable provider transport.

Automated evidence:

- 922 full core tests passed (879 XCTest and 43 Swift Testing).
- 63 focused iOS tests passed: 3 identity, 5 strict local storage, 10 explicit matching, 26 dashboard audit, 10 provider access and 9 provider snapshot tests.
- Destination: iPhone 17 Pro Max, iOS 26.5, simulator 59B53B2A-7736-488A-A6DD-838B0F7F648B. Derived data: `/tmp/dosetap-identities-tests`.
- Build-for-testing, the required generic simulator build, Plane workflow, architecture/dose-state guards, SSOT/doc checks and whitespace checks passed for the respective implementation commits.
- Local logs: `.build/identity-evidence/` in the identity feature checkout. `red.log` preserves the original runtime failure; `green2.log` and `matching-tests.log` preserve the passing focused suites.

A confirmation captures the displayed provider fingerprint, exact session fingerprint and displayed association revision (including an absent relationship). A concurrent writer cannot be silently overwritten. The runtime regression reproduced the old overwrite and then passed with the review-token gate. Refresh starts by disabling new associations and enables them only after complete publication, preventing a failed local read from leaving an older provider snapshot eligible for matching.

The native `ProviderSessionAssociationView(model:)` shows source, original observed bounds, declared timezone, same-date candidates, confirmation and revision-checked removal. It also lists stored relationships whose provider episode changed or disappeared, allowing removal before a new match. Only the exact unended `current_session` identity is active; historical unclosed sessions are not treated as pending Dose 2.

The isolated DEBUG simulator fixture uses an in-memory repository and injected synthetic provider data only when `-dashboard-provider-match-uitest` is supplied. The native journey passed: choose a specific session, review and save, observe the persisted relationship, confirm removal, and retain the unmatched provider episode. Three screenshots were exported and visually reviewed. Final logs are `/tmp/dosetap-identity-ui-final-tests.log`, `/tmp/dosetap-identity-native-match-final.log`, and `/tmp/dosetap-identity-final-core-tests.log`; xcresult bundles are in `/tmp/dosetap-identities-tests/Logs/Test/`.

The parent integration owns the production navigation entry. Provider permission/data acceptance, screen/export/Studio parity, signed-device/owner observation and release acceptance remain separate gates. This implementation evidence alone does not close DOSETAP-45.

Follow-up guard audit: the dose-state checker uses `git grep`, so its pre-staging pass did not inspect the then-untracked native fixture. Once tracked, the fixture's direct in-memory storage setup was correctly flagged outside the storage boundary. The B24 follow-up relocates this unchanged repository/storage factory from Services to Storage and updates Xcode membership. The final dose-state guard passed after staging, so newly added sources were included. The B24 native rerun passed all 68 targeted app tests; this relocation changes no fixture behavior.
