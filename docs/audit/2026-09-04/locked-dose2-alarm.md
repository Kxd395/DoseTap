# Locked-phone Dose 2 alarm repair

## Status

- User authorized repair after the supply feature. Reported iPhone 15 Pro Max, iOS 26.6.1. No device identifiers are needed or retained here.
- Baseline: `f649f90`, branch `fix/locked-dose2-system-alarm`, based on the validated supply branch.
- Plane: DOSETAP-4 preflight verified In Progress; existing acceptance includes signed notification delivery.
- Current finding: wake notifications use UNUserNotificationCenter, while sustained sound/ringing UI runs through AVAudioPlayer and an in-app timer. Info.plist declares processing only. No AlarmKit integration or granted critical-alert capability exists in this checkout.
- Confirmed capability: Apple's current AlarmKit documentation supports iOS 26+ system alarms through Silent/Focus with user permission; the installed iOS 26.5 SDK exposes fixed-date alarms, query/readback, cancellation, and authorization. This does not bypass authentication or remove the OS Stop control.
- Implemented in `aec8ce5`: injectable AlarmKit wake backend, fixed-date readback, separate permission, replacement rollback, cancellation generation guards, in-app snooze policy, explicit system Stop/open behavior, and a separate one-minute test alarm under Settings.
- Checks so far: system backend/legacy alarm/supply suites passed (23 cases); Swift build and 634 XCTest + 43 Swift Testing cases passed; static SSOT/workflow/version/architecture guards passed. The initial new test compile failed on an actor-isolated default argument and was corrected.
- Next step: apply/verify DOSETAP-4 closeout, then signed-device owner acceptance. The one-minute test alarm was verified through real AlarmManager readback and the app was backgrounded by XCTest. A CUA Sleep/Wake action was attempted, but retained evidence establishes Home-screen/background presentation, not a confirmed locked state.
- Open gate: actual signed-device locked/Silent/Focus delivery on the owner's phone. Simulator and source evidence cannot close that gate.

## Decisions

- No audio-background workaround, entitlement fabrication, dependency installation, OS upgrade, or phone-security change.
- AlarmService owns the absolute target. AlarmKit owns delivery on iOS 26+; earlier systems retain the existing notification fallback with a visible limitation.
- One stable Dose 2 system-alarm ID. Source intent, notification reminders, and the private supply reminder keep independent roles.
- OS Stop acknowledges an alarm only; it never logs a dose. Open DoseTap routes the user to the normal dose controls; snooze remains inside DoseTap where session/window/limit policy is available.
- Permission denial and failed/mismatched readback must remain visible. Cancellation must defeat an in-flight schedule, and session reset/deletion must cancel the system alarm without reentering repository initialization.

Sources: [Apple AlarmKit overview](https://developer.apple.com/videos/play/wwdc2025/230/), [scheduling sample](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit), [permission usage description](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAlarmKitUsageDescription), local AlarmKit.swiftinterface from the installed iOS Simulator 26.5 SDK.

Runtime result: **2 UI tests passed**: expired-session launch/relaunch (9.87 seconds) and system-alarm authorization, verified scheduling, background delivery/presentation (83.99 seconds), repeated on the final clean build. Evidence: [verified schedule](system-alarm-verified.png), [system presentation with app backgrounded](system-alarm-background.png). Actual locked-phone sound, Silent/Focus and physical-device controls remain owner gates.

Final app-layer result: **55 passed, 0 failed, 0 skipped**, independently read from the xcresult summary. Suites: system-alarm tests (4), alarm scheduling (17), notification center integration (2), storage integration (28), supply reminder service (4). Cancellation failures now remain visible after reset, and unsupported Critical Alerts are hidden behind the existing capability flag. Native wake delivery does not activate or depend on the in-app AVAudioSession.

## Validation commands and limits

All commands run in `/Volumes/Developer/projects/DoseTap-main`, on the isolated iPhone 17/iOS 26.5 simulator `829089F8-76D6-475A-A794-CFBD0BE9F43B`:

```sh
swift build -q
swift test -q
bash tools/check_plane_workflow.sh
bash tools/ssot_check.sh
bash tools/check_app_version.sh
bash tools/check_architecture_boundaries.sh
git diff --check
xcodebuild -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,id=829089F8-76D6-475A-A794-CFBD0BE9F43B' -derivedDataPath /tmp/dosetap-supply-build CODE_SIGNING_ALLOWED=NO -only-testing:DoseTapTests/SystemDoseAlarmTests -only-testing:DoseTapTests/AlarmSchedulingTests -only-testing:DoseTapTests/NotificationCenterIntegrationTests -only-testing:DoseTapTests/EventStorageIntegrationTests -only-testing:DoseTapTests/SupplyReminderServiceTests test
xcodebuild -project ios/DoseTap.xcodeproj -scheme DoseTapUITests -destination 'platform=iOS Simulator,id=829089F8-76D6-475A-A794-CFBD0BE9F43B' -derivedDataPath /tmp/dosetap-supply-build CODE_SIGNING_ALLOWED=NO -only-testing:DoseTapUITests/DoseTapUITests/testSystemAlarmPermissionAndBackgroundDelivery -only-testing:DoseTapUITests/DoseTapUITests/testExpiredSessionLaunchDoesNotReenterRepository clean test
```

Logs: `/tmp/dosetap-system-core-tests.log`, `/tmp/dosetap-system-alarm-final-tests.log`, `/tmp/dosetap-system-alarm-final-ui-tests.log`. No signed build was installed on the owner's phone, no dependencies/SDKs were installed or upgraded, and no shared/production database was modified.

## Owner acceptance

Install the reviewed signed build, then open Settings > Locked-phone alarm setup & test. Grant Alarms permission, schedule the separate one-minute test, lock the phone, and verify sound and system controls. Repeat with Silent mode and the intended Focus, then confirm Stop silences without recording a dose and Open DoseTap leads to the explicit dose controls. Verify a normal scheduled Dose 2 alarm and a permitted in-app snooze before treating the device acceptance gate as closed.

## Action log

- Added `SystemDoseAlarm.swift` for the AlarmKit boundary and distinct test alarm.
- Updated `AlarmService.swift` for backend selection, verification, rollback, cancellation and error persistence.
- Updated `SessionRepository.swift` cancellation adapter; cold-launch/reentry regression passes.
- Added `SystemAlarmSettingsView.swift`; updated Settings labels, Info.plist permission description and Xcode target membership.
- Added system-alarm unit and UI tests, updated the normative alarm contract, and retained the two simulator screenshots above.
- Changes are local commits on `fix/locked-dose2-system-alarm`, based on the supply feature commits. The preserved original checkout and the owner phone install remain untouched.
