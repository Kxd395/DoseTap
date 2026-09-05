# Locked-phone Dose 2 alarm repair

## Status

- User authorized repair after the supply feature. Reported iPhone 15 Pro Max, iOS 26.6.1. No device identifiers are needed or retained here.
- Baseline: `f649f90`, branch `fix/locked-dose2-system-alarm`, based on the validated supply branch.
- Plane: DOSETAP-4 preflight verified In Progress; existing acceptance includes signed notification delivery.
- Current finding: wake notifications use UNUserNotificationCenter, while sustained sound/ringing UI runs through AVAudioPlayer and an in-app timer. Info.plist declares processing only. No AlarmKit integration or granted critical-alert capability exists in this checkout.
- Confirmed capability: Apple's current AlarmKit documentation supports iOS 26+ system alarms through Silent/Focus with user permission; the installed iOS 26.5 SDK exposes fixed-date alarms, query/readback, cancellation, and authorization. This does not bypass authentication or remove the OS Stop control.
- Next step: implement an injectable system-alarm backend for the wake role; preserve existing safety reminders and canonical snooze policy, then verify cancellation, readback, errors and simulator behavior.
- Open gate: actual signed-device locked/Silent/Focus delivery on the owner's phone. Simulator and source evidence cannot close that gate.

## Decisions

- No audio-background workaround, entitlement fabrication, dependency installation, OS upgrade, or phone-security change.
- AlarmService owns the absolute target. AlarmKit owns delivery on iOS 26+; earlier systems retain the existing notification fallback with a visible limitation.
- One stable Dose 2 system-alarm ID. Source intent, notification reminders, and the private supply reminder keep independent roles.
- OS Stop acknowledges an alarm only; it never logs a dose. Open DoseTap routes the user to the normal dose controls; snooze remains inside DoseTap where session/window/limit policy is available.
- Permission denial and failed/mismatched readback must remain visible. Cancellation must defeat an in-flight schedule, and session reset/deletion must cancel the system alarm without reentering repository initialization.

Sources: [Apple AlarmKit overview](https://developer.apple.com/videos/play/wwdc2025/230/), [scheduling sample](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit), [permission usage description](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAlarmKitUsageDescription), local AlarmKit.swiftinterface from the installed iOS Simulator 26.5 SDK.
