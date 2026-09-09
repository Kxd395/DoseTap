# Reviewed-window local assessment

Date: 2026-09-09
Plane: DOSETAP-56, In Progress
Baseline: `674be1c` in `/Volumes/Developer/projects/DoseTap-main`
Candidate: 0.4.19 (37), `feat/reviewed-window-assessment`

## Implemented

The saved window now has a read-only assessment against current dose rows, other reviewed windows and nap markers. It distinguishes missing, checked and needs-review states, with ordered reason codes. A taken dose at the window's exclusive end is outside it; touching adjacent windows do not overlap. Missing Dose 2 is not skipped and does not itself invalidate an observation window.

Nap markers are paired within their stored session identity (legacy date identities stay separate). Missing endpoints are not filled from the clock or another session. If an incomplete nap could overlap the reviewed window, the assessment conservatively requires review; an old unfinished nap can therefore require correction. Ambiguous starts and equal-time markers do not manufacture a duration.

The storage reader uses a SQLite read snapshot, checks statement completion and decodes evidence strictly. Supported ISO timestamp formats are accepted, but invalid times are never replaced by now. Existing general quick-log readers still have their old fallback behavior; this new assessment bypasses that path rather than claiming a repository-wide parser repair.

Wake & Next Day shows the assessment for unchanged saved bounds, refreshes after record changes and offers a manual recheck. Drafts do not inherit a saved assessment. JSON/CSV/Studio reports include version, status, reasons and assessment time, using existing timestamp redaction. Saved reports describe their assessment time, not current validity after a correction. No identifiers are added to these report fields.

No dose, alarm, session, stored window or provider record is changed by this assessment. Existing sleep charts and totals keep their prior semantics. Checked local bounds do not prove measured sleep or authorize medication.

## Validation and blockers

- Core test-first failure captured before the assessment type existed. `swift build -q`, UTC and New York `swift test -q` passed: 680 XCTest and 43 Swift Testing cases per timezone. New cases cover corrected/outside/orphan doses, missing bounds, identity, half-open overlap, incomplete/ambiguous naps and report round-trip.
- App test-first failure captured before the strict storage API existed. The first run exposed a synthetic fixture using the wrong dose-ledger timestamp format; the fixture was corrected to use the storage formatter. The report integration then exposed a missing Hashable conformance; adding the existing model requirement cleared that compiler blocker.
- Final build 37 simulator run passed 124 tests across medication transactions, dose-clock confirmation, HealthKit, dashboard and exports. `/tmp/dosetap56-assessment-final.xcresult`. Tests verify correction/recheck, malformed nap timestamps, unavailable tables, malformed other-night JSON, overlapping saved windows and unchanged medication/diary contents.
- Studio passed 66 tests; three optional fixture/visual cases skipped. New assertions verify assessment round-trip, report columns and safe timestamp redaction.
- Plane workflow (10 tests, 64 assertions), SSOT/doc lint, architecture, dose-write, legacy-safety, repository-hygiene, companion-target and version guards passed. All four app configurations and the built bundle report build 37. Diff checks passed.
- `DoseTapUITests/testReviewedNightWindow()` passed one simulator case (72.7 seconds): cancel/unconfirmed save, confirmed save, restart, visible saved assessment and reason-required removal. `/tmp/dosetap56-assessment-ui.xcresult`. Three exported screenshots were inspected; the saved assessment, explanation and recheck action are readable, and the cleared/draft states do not display a checked saved window. Warning-state layout and signed-phone accessibility remain separate acceptance work. Hosted CI/review and merge evidence belong in the PR and verified Plane workpad after completion.

## Remaining work

Combine current local-boundary checks with conflict-aware provider evidence and recheck snapshots after asynchronous queries before publishing treatment-night calculations. Durable source revision/deletion reconciliation, permission/read-readiness wording and consistent consumer/report provenance remain open. DOSETAP-57 owns dose-to-sleep, return-to-sleep and completed awakening markers/counts. No installed-phone, signed-device HealthKit, accessibility, historic unexpected Dose 2 resolution, privacy/release or complete backup/restore acceptance is claimed.

The separate preserved checkout and unrelated Xcode project/scheme edits remain untouched. Only four build-number hunks from the Xcode project belong to this change.
