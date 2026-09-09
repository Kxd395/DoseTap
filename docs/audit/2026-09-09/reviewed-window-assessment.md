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

## PR review follow-up

PR #19 review found two assessment gaps: legacy dose aliases were ignored, and skipped-dose timestamps were not validated. Both reproduced in regression tests before the fixes. The storage projection now uses the existing `CanonicalDoseEventType` contract without changing raw records; unknown types require review. Skipped outcomes receive timestamp and sequence validation, but do not count as administrations outside the window.

After these fixes, UTC and New York core runs each passed 681 XCTest and 43 Swift Testing cases. The simulator rerun passed 125 targeted app tests (`/tmp/dosetap56-assessment-review-fixes.xcresult`), including legacy/orphan/outside-window aliases and unchanged raw ledger assertions. Studio again passed 66 tests with three optional skips. The earlier UI screenshot proof remains applicable to the unchanged view. Final hosted checks and merge are recorded in the PR and Plane workpad.

## Export batch follow-up

The next review identified repeated full-history evidence reads during multi-night export. The batch API now decodes shared window and nap evidence once inside one SQLite read snapshot, then passes each result into the collected-night builder. Nothing is cached across exports. A three-night regression verifies single-night parity, one shared nap query in both the batch API and actual Studio bundle export, and a fresh unavailable result after a later source-table failure. The final targeted simulator run passed 126 tests (`/tmp/dosetap56-assessment-batch-final.xcresult`). No core or UI behavior changed in this export follow-up; the corrected core and UI validations above remain applicable. In-memory overlap calculations still compare each selected window with shared evidence; this change removes repeated database reads/decoding, not all history-size-dependent computation.

## Snooze invariant follow-up

Review also found that an orphan snooze could pass the new assessment despite the existing ledger rule requiring Dose 1. A red/green core regression now covers that dependency, pre-dose/future/nonfinite snooze times, valid non-administration events outside the window, unknown event types and correction-audit timestamp validity. Storage alias coverage includes both `snooze` and `dose2_snoozed`, with unchanged raw rows. UTC and New York each passed 682 XCTest and 43 Swift Testing cases; the simulator passed 126 targeted cases (`/tmp/dosetap56-assessment-snooze-green.xcresult`); Studio passed 66 with three optional skips. These checks do not compare every historic session with the active-session projection or claim to replace the medication invariant checker.

## Remaining work

Combine current local-boundary checks with conflict-aware provider evidence and recheck snapshots after asynchronous queries before publishing treatment-night calculations. Durable source revision/deletion reconciliation, permission/read-readiness wording and consistent consumer/report provenance remain open. DOSETAP-57 owns dose-to-sleep, return-to-sleep and completed awakening markers/counts. No installed-phone, signed-device HealthKit, accessibility, historic unexpected Dose 2 resolution, privacy/release or complete backup/restore acceptance is claimed.

The separate preserved checkout and unrelated Xcode project/scheme edits remain untouched. Only four build-number hunks from the Xcode project belong to this change.
