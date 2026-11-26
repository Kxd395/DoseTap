# Local reset integration — build 106

Date: 2026-10-10 (America/New_York). Plane: DOSETAP-39, In Progress.
Checkout: `/Volumes/Developer/projects/_DoseTap_Active/DoseTap-chart-inspection`.
Branch: `feat/sleep-chart-inspection`; source baseline: `2cb4abb`.
Source commits: `32cccd4` (atomic reset) and `9537f5c` (daytime cleanup/recovery).
The port adapts `b0960d3` from open PR #74; that PR is not merged and its separate schema-initialization repair is excluded.

## Bounded implementation

The current 26 clinical tables clear in one checked transaction. Failed resets retain source records, session, preferences and reminder intent after successful rollback. Failed rollback disables the handle and preserves the restart-required error on repeated attempts.
Successful commit advances reset generation before publication. Daytime cleanup drains older OS work, cancels and verifies owned pending/delivered requests, preserves unrelated identifiers, and chains cleanup for later reset generations.
Post-commit cleanup warnings persist at app root across setup and relaunch until acknowledgment. A new medication session cannot hide an independent daytime cleanup failure.
No owner-data reset was performed. Exports, diagnostics, credentials, provider-owned records and staging tombstones remain outside this bounded reset and are disclosed.

## Reproductions and review

- A real SQLite reject-delete trigger reproduced six integrity assertion failures before repair: `/tmp/dosetap106-reset-red.log`.
- A suspended pending-notification read reproduced the consecutive-reset race: one test with four assertion failures in `/tmp/dosetap106-repeat-reset-red.log`. Xcode lingered after the test and was terminated with exit 143; this is red-test evidence, not a completed build receipt.
- Daybreak Blue round 1 identified three accepted findings: transient cleanup warning, independent daytime failure hidden by a new medication session, and stale cleanup reuse after another reset. Round 2 cleared those fixes and identified the repeated-rollback recovery-message defect. All four were repaired.
- Round 3 found **zero actionable product-code/SSOT findings**, with no unresolved prior objections. Its immutable patch is `.build/dosetap106-reset-review-round3.patch`, SHA-256 `17429456b60f4bda9a60ec40b8a6673028d2e93a0bcfec1a30b4c58acddb1913`.
- The final source patch is `.build/dosetap106-reset-final-source.patch`, SHA-256 `30974fb1a6b2a33c365ff5e027c45281ad7e925a3f554cb2ceb98e7a77b49b5a`. It matches baseline-to-`9537f5c` exactly. Compared with round 3, only two UI-test label locators changed to predicates to avoid XCTest's 128-character identifier limit; production source is identical. Daybreak explicitly required truthful artifact binding, with no production rereview needed for this exact test-only change.

## Validation

- Final focused run: **88 tests, zero failures**, including repeat attempts after rollback failure; `/tmp/dosetap106-reset-final-v4.log` and `.xcresult`. This run used the final source identity above.
- Core validation: **1,203 XCTest + 43 Swift Testing cases passed** in `/tmp/dosetap106-swift-test.log`. Core was unchanged after the first atomic port. Normal precommit hooks independently confirmed SwiftPM build and unsigned generic-simulator build success for both source commits.
- Six UI cases passed in `/tmp/dosetap106-ui-v2.xcresult`: actual Settings failed-reset journeys at normal/largest text retained both original daytime observations after relaunch without reseeding, plus reminder controls/status and sleep-evidence sections at both text sizes. These ran on the earlier candidate before the final backend recovery guard and mechanical helper extraction.
- The seventh UI case hit two long-label locator exceptions. After the selector-only correction, `/tmp/dosetap106-ui-warning-final.log` and `.xcresult` passed on final source: root warning appears before setup, survives relaunch without reseeding, and remains dismissed after acknowledgment and another relaunch. Seven scenarios have passing evidence across these runs; no single final seven-case suite pass is claimed. UI v1 was interrupted for a scrolling-helper issue.
- Final repository guards passed: Plane workflow (15 tests/80 assertions), SSOT, documentation, architecture boundaries, dose-state writes, app version and whitespace checks. Receipt: `/tmp/dosetap106-final-guards.log`.
- Final signed device build passed: `/tmp/dosetap106-device-build-final.log`; strict codesign verification and app metadata confirmed `com.dosetap.ios`, `0.4.19 (106)`. Final normal commit receipt: `/tmp/dosetap106-integration-commit.log`.

## Phone and tracker

Build 106 was installed in place on the iPhone 15 Pro Max. Independent app metadata confirmed version/build and the new installed bundle: `/tmp/dosetap106-installed-app.json`. Launch succeeded after one retry for a transient CoreDevice connection failure. Independent process readback matched PID 35979 and executable to that installed bundle: `/tmp/dosetap106-phone-launch-retry.json` and `/tmp/dosetap106-phone-processes-retry.json`. Installation is not physical alarm/reset acceptance.
Final Plane closeouts were applied and independently read back: DOSETAP-39 `e23010a9734b6f43` and DOSETAP-58 `18516157fde180a4`, both In Progress. DOSETAP-58 records the current build 106 phone evidence and the next historic check-in correction wording improvement, which remains unimplemented.

## Open acceptance

Keep DOSETAP-39 In Progress. Real pending/delivered notifications and native alarms, owner-observed restart/background behavior, full store coverage and content-equal backup/restore, legacy migration dependencies, staging convergence, provider/privacy/accessibility, merge and release acceptance remain open. The owner's real daytime reminders are still untested. The full earlier Plane gate list is retained.
