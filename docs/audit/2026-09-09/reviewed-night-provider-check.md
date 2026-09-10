# Reviewed-night Apple Health coverage check

Date: September 9, 2026
Plane: DOSETAP-56, In Progress
Baseline: `bc5042e`, shipping checkout `/Volumes/Developer/projects/DoseTap-main`
Candidate: 0.4.19 (38)

## Change

Wake & Next Day now offers **Check Apple Health coverage** for an unchanged saved window whose local assessment is checked. The action uses the existing bounded, conflict-aware provider query. It shows estimated sleep, recorded awake time, unmeasured time, conflicts and check time without replacing existing charts or export totals. The HealthKit preference must be enabled; this action never requests authorization or interprets an empty query as permission proof.

The storage assessment reader now returns its exact calculation inputs from the same SQLite read snapshot: selected identity, dose projection, raw outcome answers, reviewed windows and nap markers. The loader reads these inputs again after the asynchronous query. Changed, unreadable or newly invalid inputs cannot publish the earlier result. A cancellation or disabled preference also discards a late callback. No database transaction stays open while waiting for HealthKit.

Empty provider observations remain unavailable; complete all-awake observations can produce valid zero sleep. Conflicting time remains unmeasured under the existing consensus rule. Mismatched bounds or malformed provider observations fail the check. Raw provider evidence and its derivation version stay in the transient result. No medication, alarm, session, diary or provider record is written by the loader.

The view clears the result when bounds, local records or the HealthKit preference change, when the scene becomes inactive, and when the editor disappears. Cancellation discards a late callback; it does not claim to stop an already submitted HealthKit query. Each new check fetches current provider evidence. This is a point-in-time review, not continuous import monitoring or a durable source ledger.

## Validation

- Test-first app run failed because the loader/input reader did not exist. Initial green run passed 75 HealthKit/medication tests. An incorrect ExportTests selector matched no suite; export coverage was subsequently run with the actual ExportIntegrityTests and ExportImportRoundTripTests selectors.
- Expanded iPhone 17 Pro / iOS 26.5 run passed 112 tests across medication transactions, HealthKit, exports and dashboard analytics. Cases include separated sleep blocks, unchanged medication/diary records, valid zero versus empty observations, conflicts, query errors, wrong bounds, preference changes, cancellation with a late callback, and changes to doses, bounds, naps, another night or readable storage while a query is suspended. Result: `/tmp/dosetap-provider-check-final.xcresult`.
- Full iOS app regression passed 404 tests with no failures: `/tmp/dosetap-provider-all-app.xcresult`. Studio ran 69 tests with 3 existing skips and no failures; the skipped cases are not claimed as validated.
- Core builds and UTC/New York runs each passed 682 XCTest plus 43 Swift Testing cases. The only core change is value equality for nap evidence; no interval policy changed.
- Standard and largest accessibility-size synthetic summaries were rendered and inspected. Text wraps without truncation; the containing form remains scrollable. This is bounded visual evidence, not VoiceOver or signed-phone acceptance.
- The UI test first failed at the missing button. The first implemented run failed to locate the response below the viewport. Screenshot and accessibility evidence placed the action at the bottom edge; the test was corrected to scroll the complete action into view and then reveal its response. No calculation or lifecycle behavior was changed to accommodate that failure. Native Simulator computer-control reads timed out; test screenshots and accessibility artifacts provided the inspection evidence.
- The corrected UI journey passed one test in 97 seconds: `/tmp/dosetap-provider-ui-visible.xcresult`. It covers saving/reopening the window, the disabled-HealthKit response and clearing the result after an edit. Its final response screenshot was inspected; real provider responses remain a device gate.
- All four app configurations report 0.4.19 (38). Plane, SSOT, architecture, dose-write, documentation and whitespace guards passed. Hosted integration evidence is tracked separately in the Plane workpad and PR.

## Remaining acceptance

This check does not deliver DOSETAP-57's onset/return markers or completed awakening counts. Existing History, Timeline, dashboard and export totals retain their current definitions. Shared report integration, durable provider revision/deletion handling, source provenance and permission/read-readiness wording remain under DOSETAP-56. The strict reader does not repair the older general quick-log timestamp fallback.

Real signed-phone HealthKit grant/deny/no-data/import behavior, provider corrections, timezone travel, accessibility and owner acceptance remain open. So do the independent historical unexpected Dose 2 investigation, medication/alarm/background/restart device checks, privacy/release and complete backup/restore gates. No phone installation or real HealthKit-record inspection occurred.

The original preserved checkout and unrelated Xcode project ordering/UI-test scheme changes are excluded. Only loader membership and four build-number changes belong to this slice's Xcode project diff. Revert the scoped implementation commit to remove the optional check; there is no data migration to reverse.
