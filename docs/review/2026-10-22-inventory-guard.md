# Inventory architecture guard correction

Status: Local implementation, automated validation and independent source review passed; human integration review and main/hosted-CI integration remain pending.
Date: 2026-10-22
Tracker: [DOSETAP-83](http://plane.localhost:3301/dark-water-drones/browse/DOSETAP-83/), In Progress.

## Scope and diagnosis

Checkout: `/Volumes/Developer/projects/_DoseTap_Active/DoseTap-chart-inspection`, branch `feat/sleep-chart-inspection`, baseline `a8237de62cf7cfba751768339c85189b4e4c35c6`. Main and its upstream both resolved to `fac445c5133b4f7d32ed659796ceb828ae1b709e` before implementation. The preserved legacy checkout and main were not modified.

The two failures carried forward in the build 108 report were reproduced. Both came from stale guard assumptions:

- Studio already calls `try repo.inventoryExportRecords()`, which reads every stored inventory row and propagates invalid/unreadable-record errors. The guard required `listInventorySnapshots`, a compatibility API with a default 500-row cap and empty-on-read-error behavior. Restoring that API to exports would regress the existing contract.
- `EventStorage+DashboardSnapshot.swift` reads raw inventory rows inside its existing SQLite read transaction. It is a storage owner, not a view bypassing the repository. The table-name allowlist had not been updated for this owner.

The correction recognizes these exact paths, rejects capped export reads, and requires ordinary `try` through the expected receiver at the two reviewed export call sites. Other storage/table/derived-inventory/legacy restrictions remain. The main CI SSOT job now runs the guard and its isolated rejection fixtures. The release preflight continues using the same guard entry point.

This is a textual architecture guard, not a Swift parser or proof of all future code behavior. Runtime export and snapshot tests remain necessary. No app source, schema, questionnaire, persisted data, API behavior or version changed; this work does not produce a new phone build.

## Validation

Artifacts: `.build/inventory-guard-2026-10-22/` in the implementation checkout.

| Check | Verified result |
| --- | --- |
| Original guard with new fixtures | 12 cases ran; 8 failed assertions exposed the stale rules and missing new-path protection. `red-tests.log`. |
| Corrected guard fixtures | 12 passed. Includes exact valid owners and rejection of capped listing, missing checked reader, optional/forced try, direct storage access, unreviewed owners, leaked table names, derived data and active legacy stores. `guard-tests-final.log`. |
| Existing inventory/export/snapshot runtime | 11 passed, zero failures or skips on iPhone 17 Pro Max, iOS 26.5. `inventory-regression.xcresult`. |
| Core suite | 1,203 XCTest plus 43 Swift Testing cases passed. `swift-test.log`. |
| Static checks | Inventory guard, shell syntax, workflow YAML parse, SSOT, documentation lint and whitespace passed. Plane workflow: 15 tests, 80 assertions passed. |

The focused runtime command used `tools/dt-test all -parallel-testing-enabled NO`, destination `59B53B2A-7736-488A-A6DD-838B0F7F648B`, and these selectors:

- `DoseTapTests/ExportRecordFidelityTests/testInventoryExportsEveryStoredIdentityAndUnchangedNotes`
- `DoseTapTests/ExportRecordFidelityTests/testUnreadableInventoryOrMedicationAbortsExport`
- `DoseTapTests/DashboardSnapshotStorageTests`

These tests cover 501 distinct exported identities and unchanged notes; malformed/missing inventory rejection; raw source fidelity; and an intervening writer that cannot tear a single snapshot across datasets. They use synthetic databases. The temporary simulator was returned to its initial shutdown state.

## Review and tracker

Daybreak Blue round 1 verified immutable candidate `1285541b48be5f7ce7e24ec28f5782c713a02656afee3daafa5e66bebbfdc4ba` and found one P2: the documentation overstated swallowed-error protection because ordinary `try` inside a catch-and-default block satisfies the textual guard. Reviewer option 3 was applied: the guide now explicitly excludes surrounding `do`/`catch` analysis and proof of propagation, and the diagnostic describes the required ordinary `try` and receiver. Runtime failure propagation remains covered by the existing iOS test. No other actionable finding was reported.

Round 2 verified corrected immutable candidate `2e2e5951e7c1bca4f690ad256c38f7bfd6fca0984445ad39d8ace04f56f0f741` under `review2/`; recommendation `merge`, workflow label `human_review_required`. No actionable P0-P3 findings remained, and the prior P2 was confirmed resolved. The reviewer inspected the supplied validation logs without rerunning tests. Current source hashes match all four reviewed post-images. Both candidates contain the guard, its fixtures, CI wiring and testing guide; this dated evidence report is outside the source candidate. Implementation commit `0d0cb96` and the review-response wording commit `70ac9cd` passed normal commit hooks.

Final local-delivery workpad `21e205a577abf2b8` was applied and independently read back as In Progress using `final-closeout.json` in the artifact directory. The item remains open for human integration review, integration into main and hosted execution. Broader app release, physical questionnaire accessibility, owner usability, notification and provider acceptance remain separate.
