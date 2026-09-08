# Automatic Night Mode — DOSETAP-48

Status: Locally implemented and validated; device and owner acceptance pending
Date: 2026-09-07, America/New_York
Checkout: `/Volumes/Developer/projects/DoseTap-main`, `fix/locked-dose2-system-alarm`, based on `a76c7a4`

## Contract

The owner's request is an appearance-only automation using the existing red/amber Night Mode. The default is enabled, with a Settings → Theme toggle. A committed active Dose 1 enables it; the selected treatment night's Sleep Plan Wake by deadline ends it. A final wake or session closure ends it early. Dose 2, skips, Bathroom, Water, Noise, Dream, and Brief Wake do not end it or change how they are recorded.

Automation is a projection of active-session state, not a medication mutation. It never schedules an alarm, changes brightness/Focus, or implies a medication event. The saved appearance is not overwritten by automation. Manual theme selection suppresses automation for that session across restart; a different session is eligible again. Explicit final wake is also retained as a per-session suppression while awaiting the morning questionnaire. Toggling automation back on explicitly clears suppression.

The root reconciles at appearance, foreground, session notifications and once per second while visible. Relaunch after the wake deadline restores the saved appearance; background execution is not required. Nightly wake overrides and later plan edits are read from the same Sleep Plan source as Tonight's Wake by display. The setting follows that plan, not the separate Dose 2 target alarm or work-advisory cutoff.

The existing night filter now uses a stable modifier tree instead of replacing the entire content branch on theme changes. This preserves navigation and editor identity when automation starts or ends.

## Validation record

- Red: new app-layer tests failed to compile against the original ThemeManager because automatic-night reconciliation did not exist. `/tmp/dosetap-auto-night-red.log`.
- Final app-layer tests: seven injected-clock/defaults-isolated ThemeManager tests passed, including exact wake boundary, undo/closure, restart, explicit final-wake persistence, manual override, opt-out/re-enable, changed wake deadline and manual Night preference. `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:DoseTapTests/AutomaticNightModeTests CODE_SIGNING_ALLOWED=NO`; `/tmp/dosetap-auto-night-app-final.log`.
- Core regression: `swift build -q` and `swift test -q` passed: 646 XCTest cases plus 43 Swift Testing cases. Final repeat: `/tmp/dosetap-auto-night-core-final.log`.
- Guards: Plane workflow (10 tests, 64 assertions), SSOT, documentation lint, architecture boundaries, dose-state write guard, app-version check and `git diff --check` passed.
- Initial UI attempt failed because the test queried visible Dose 1 text instead of the established accessibility identifier; no automatic-night assertion had been reached. `/tmp/dosetap-auto-night-ui.log`.
- Intermediate fixture attempts used a dated wake override for a daytime test. The upcoming pre-sleep date differs from the active dose grouping date, and Tonight prunes inactive overrides before Dose 1. Runtime capture confirmed the real dose committed but the fixture's Wake by was already past. The fixture now uses the recurring schedule; it does not change production planning semantics. `/tmp/dosetap-auto-night-ui-retry.log`, `/tmp/dosetap-auto-night-ui-final.log`.
- The next run passed automatic start/restart/wake restoration and manual override/restart, but the Settings toggle's whole-row test tap did not switch its value. The final test targets the switch's own trailing control and waits for the resulting value. `/tmp/dosetap-auto-night-ui-verified.log`. Dose 2 cancel/background/confirmed-save/restart passed in both preceding runs.
- Three simulator journeys then passed (automatic start/restart/wake restoration, manual override/restart/Settings toggle, Dose 2 cancel/background/confirmation/restart). `/tmp/dosetap-auto-night-ui-accepted.log`. Screenshot inspection caught a remaining light-to-night Settings color-scheme mismatch despite those passing interactions. A root environment override also passed those three interactions but did not fix the Settings capture (`/tmp/dosetap-auto-night-ui-color.log`); it was removed. The Theme screen now explicitly sets its own effective color scheme.
- Final Theme-screen follow-up passed 1/1 after the local color-scheme correction: `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTapUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:DoseTapUITests/DoseTapUITests/testAutomaticNightModeManualOverrideSurvivesRestart CODE_SIGNING_ALLOWED=NO`; `/tmp/dosetap-auto-night-settings-final.log`. The dark background/red-amber foreground was visually verified from `settings-final/FB68F354-CCE6-4C14-8571-0270BC99FEB6.png` under `/tmp/dosetap-auto-night-proof.a94hsz/`. Earlier passing Tonight start/wake captures were also inspected. All simulator evidence uses iPhone 17 Pro, iOS 26.5, unsigned Debug; it is not phone-install evidence.

## Open gates and preservation

Signed-device and owner review of the automatic switch, overnight resume, color readability, VoiceOver and larger text remain open. This is reuse of the current Night Mode palette, not certification of its accessibility or sleep effects. No phone data was edited and no phone build installed. Existing medication confirmation and early-dose hold logic are unchanged.

The two pre-existing project/scheme diffs are excluded from this change. No push or main merge was performed; the existing integration HOLD and its separate device, credential/provider and hosted gates remain in place.
