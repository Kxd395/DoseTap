# Supply reminder implementation evidence

## Status

- Scope: user-authorized improvement of the missing local order reminder.
- Baseline: clean `DoseTap-main`, main `5d1fa4b48bec00007a0b6f8327a8edee7b096569`.
- Branch: `feat/local-order-reminder`; preserved `/Volumes/Developer/projects/DoseTap` is untouched.
- Plane: DOSETAP-30 preflight confirmed Backlog. State mismatch reported; user explicitly requested implementation. Closeout will retain physical/owner gates.
- Completed: source review, actual UI/storage/notification call-path review, current remote main readback, feature contract.
- Implemented: received-date + 21 calendar days, direct/cycle-end choices, correction history, atomic SQLite supply record, independent bottle starts, verified role-specific scheduling, permission/retry/handled/disable states, lifecycle reconciliation, Settings and Tonight controls, supply JSON export/restore.
- Remaining: signed-device and owner acceptance.
- Next step: owner acceptance of the supply feature; engineering continues separately in `locked-dose2-alarm.md`.

## Findings and decisions

- SUP-A01 (confirmed): the existing Next Refill snapshot date saves to SQLite only; it schedules no notification. Fix with a separately labeled order-reminder workflow.
- SUP-A02 (confirmed): the old inventory forecast is pure/disconnected, and the referenced proposal is explicitly superseded. Do not wire unconfirmed quantities into an alert.
- Decision: no dependency upgrade or rewrite is needed. Use existing SQLite, SwiftUI and notification boundary.
- Decision: preserve snapshot dates as historical notes, never auto-convert them into reminder intent.
- Owner clarification: manually enter last received date; remind 21 calendar days later. Add optional Started a new bottle action on Tonight. Bottle starts do not move reminder dates.
- Open gates: signed-device notification delivery, owner copy/privacy acceptance, assistive-technology review. No production/user database migration or deployment is authorized by this work.

## Action log

- Added this evidence record and `docs/SSOT/supply-reminder.md` before behavior changes.
- Core build/test passed: 634 XCTest cases and 43 Swift Testing cases. Six new manual-date fixtures cover +21 days, month boundaries, DST, timezone, invalid inputs and correction backup.
- Initial red check failed on missing SupplyReminder types as expected; implementation then passed.
- iOS storage tests: 2 passed, including query-only write failure and invalid restore preservation.
- iOS service/storage tests: 5 passed, including permission denial, missing/add failures, retry, role isolation, reset during add and bottle/reminder independence.
- Static SSOT, Plane workflow (10 tests/64 assertions), app-version and architecture guards passed.
- Initial UI build was attempted before new-file target membership was added and failed on missing SupplyBottleButton. Membership corrected. An initial combined test command used DoseTap, which excludes UI tests; switched to the existing DoseTapUITests scheme.
- Tests use a new isolated iPhone 17/iOS 26.5 simulator (829089F8-76D6-475A-A794-CFBD0BE9F43B), not the user's running iPhone 17 container.
- Expanded iOS checks: 51 passed (3 supply storage, 4 supply reminder, 28 existing storage integration, 16 existing alarm scheduling). This includes SQLite reopen, invalid restore, failed source write, overdue reminders, mismatched triggers, and an existing dose alarm retained through supply changes.
- An incremental UI run crashed constructing Settings. A clean build passed launch and reached the feature; no application rewrite was used to mask a generated-build problem. The next run confirmed scheduling and relaunch, then failed because the handled-status assertion addressed a scrolled-offscreen row. Read-only inspection of the isolated fixture database confirmed `enabled=false`, an acknowledgement timestamp, and one independent bottle record. The UI test now scrolls the status back into view before asserting it.
- Observed simulator UI: last received September 4, 2026 → reminder September 25, 2026 at 09:00 America/New_York; Scheduled was shown after OS readback and after relaunch. Bottle recording preserved the nightly dose action.
- The dose-notification toggle is now explicitly labeled for dose notifications. Supply reminders retain separate controls and standard iOS sound/Focus behavior; their default notification tap opens supply management.

## Validation commands

Run from `/Volumes/Developer/projects/DoseTap-main`:

```sh
swift build -q
swift test -q
bash tools/check_plane_workflow.sh
bash tools/ssot_check.sh
bash tools/check_app_version.sh
bash tools/check_architecture_boundaries.sh
git diff --check
xcodebuild -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,id=829089F8-76D6-475A-A794-CFBD0BE9F43B' -derivedDataPath /tmp/dosetap-supply-build CODE_SIGNING_ALLOWED=NO -only-testing:DoseTapTests/SupplyStorageTests -only-testing:DoseTapTests/SupplyReminderServiceTests -only-testing:DoseTapTests/AlarmSchedulingTests -only-testing:DoseTapTests/EventStorageIntegrationTests test
xcodebuild -project ios/DoseTap.xcodeproj -scheme DoseTapUITests -destination 'platform=iOS Simulator,id=829089F8-76D6-475A-A794-CFBD0BE9F43B' -derivedDataPath /tmp/dosetap-supply-build CODE_SIGNING_ALLOWED=NO -only-testing:DoseTapUITests/DoseTapUITests/testSupplyReceiptReminderAndOptionalBottleSurviveRelaunch clean test
```

Final logs: `/tmp/dosetap-supply-core-test.log`, `/tmp/dosetap-supply-final-app-test.log`, `/tmp/dosetap-supply-final-ui-test.log`. Local evidence does not prove signed-device delivery, notification-tap routing on a physical device, Files-provider import/export interaction, or assistive-technology acceptance. Supply JSON roundtrip, replacement validation and persistence were automated; the Files sheet itself remains an owner acceptance step.

Final clean simulator UI test: **passed**, one complete journey (66.35 seconds), including bottle start, unchanged dose action, verified scheduling, relaunch persistence and handled state. Screenshots: [Scheduled](supply-reminder-scheduled.png), [Handled](supply-reminder-handled.png).

Implementation commits: `f2ebf4c`, `a4bb2ac`, `7c113b4`, `f649f90`. DOSETAP-30 workpad and In Progress state were applied and independently verified (closeout `d88c994c8b04c3d2`). The initial Backlog state was explicitly promoted following the owner's implementation request, then the reviewed start/closeout helpers were used. Physical and owner gates remain open.
