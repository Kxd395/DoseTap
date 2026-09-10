# Morning setup carry-forward repair

Date: 2026-09-10
Owner: DOSETAP-51. Related: questionnaire IR-02; DOSETAP-52 and DOSETAP-61 remain separate.
Baseline: `c728068493ba74c3e0e33e4d48daf9ea0576310b`, build 41.
Candidate: 0.4.19 (42). Integration evidence is recorded in the PR and verified Plane workpad.

## Scope

Both saved-settings loading and the previous-check-in fallback now restore only the therapy device, room temperature, noise setup and sleep aid. They do not restore daily ratings, symptoms, therapy use/compliance, notes, work context or clinical answers. The equipment/room sections remain inactive until selected for this morning. The preference label explains this narrower scope.

Newly saved preferences contain only those four fields. Old preference JSON remains readable; additional daily-answer keys are ignored. Opening a form does not rewrite that preference payload or any historical questionnaire. Explicit existing-night editing still hydrates that night's observations. Turning remembering off leaves current answers intact and removes only the reusable preference payload.

This is the cross-night copying portion of IR-02. The existing fixed morning rating/Boolean defaults remain unchanged. They are not newly classified as confirmed or unanswered. Optional-answer storage and provenance, substance/activity default precision (IR-04), and beverage volume/caffeine mass semantics (DOSETAP-52) remain open. Shared recurring morning pain patterns are not delivered here. Apple Health, dose records, alarms and questionnaire transaction boundaries are unchanged.

## Verification

- Test-first reproduction: the six-test `CheckInCarryForwardTests` suite failed with 35 assertions across the two morning cases before implementation. Legacy preference and prior-row loading restored daily observations; preference saving also included daily-answer keys.
- After implementation, all six focused tests passed on iPhone 17 Pro / iOS 26.5. Tests cover both loading paths, saved preference keys, reconstructed view models, remember-off behavior and existing-night editing.
- `swift build -q` and `swift test -q` passed: 682 XCTest and 43 Swift Testing cases.
- Full build-42 app suite passed: 418 tests, zero failures. Command: `DT_SIMULATOR_NAME='iPhone 17 Pro' tools/dt-test all -only-testing:DoseTapTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`.
- Two simulator UI tests passed in 77.97 seconds: `testMorningPhysicalSymptomsWithoutPain` (including the revised setup label) and `testMorningDefaultDoseIntent`, using the `DoseTapUITests` scheme on iPhone 17 Pro / iOS 26.5 with parallel testing and signing disabled. Screenshot `966DCBC0-7A5D-4106-BF40-46770ACE6A34.png` in `/tmp/dosetap-morning-setup-proof` was inspected; the revised text and enabled Complete button are readable. This is a standard-size screenshot, not full accessibility acceptance.
- Generic iOS Simulator build passed: `xcodebuild build -quiet -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Plane workflow, app version/build (all four configurations), documentation, SSOT, architecture, dose-write, legacy-path and whitespace guards passed locally.

Local logs: `/tmp/dosetap-morning-setup-{red,green,app,ui,swift}.log`. Synthetic test data only; no phone installation or owner-data inspection.

## Remaining gates and preservation

- Signed-phone save/reopen/restart, owner confirmation, full VoiceOver and largest Dynamic Type acceptance remain open. Local tests do not resolve the prior unexpected Dose 2 incident or establish the installed phone's behavior.
- Further work: true unanswered morning observations, explicit quantity/time certainty, legacy units, shared recurring patterns and independent questionnaire actions. No claim that DOSETAP-51 or IR-02 is fully complete.
- The pre-existing Xcode project/scheme edits and untracked icon-review folder are excluded. A generated patch briefly targeted two matching blocks in the legacy preservation checkout; both were restored exactly before validation. Final implementation is confined to DoseTap-main. No unrelated legacy content was changed or committed.
- No migration or historical-data rewrite; reverting this source commit would restore the old copying behavior and should not be treated as a preferred user-facing rollback.
