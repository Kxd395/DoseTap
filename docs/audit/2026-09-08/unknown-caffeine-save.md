# Unanswered caffeine save repair

Date: 2026-09-08
Status: Implemented and locally tested; DOSETAP-51 remains In Progress
Checkout: DoseTap-main, fix/fresh-night-observations, following 25d8f4e
Candidate: 0.4.19 (27)

The storage normalizer converted an unanswered caffeine question into an explicit
None answer. This also produced a false `pre.substances.caffeine.any` response in
the normalized questionnaire. Saving now preserves nil separately from None.
There is no migration of historical answers: an older stored None cannot reliably
be identified as either a user answer or a generated default.

Three regression cases cover blank answers through save/reload, explicit negative
answers, and affirmative answers with missing detail fields. The latter verifies
storage behavior, not the current form, which still fills substance details.

## Evidence

- Before the fix: three focused simulator tests ran; the unanswered case failed
  three assertions, while the explicit-negative and affirmative cases passed.
- After the fix: 101 simulator tests passed, comprising 55 SessionRepository,
  five CheckInCarryForward and 41 MedicationMutationTransaction tests.
- `swift build -q` and `swift test -q`: 655 XCTest and 43 Swift Testing cases passed.
- Plane workflow, SSOT, architecture, dose-write, legacy-path, documentation and
  whitespace guards passed. The Plane guard ran 10 tests with 64 assertions.
- App and staging Debug/Release settings all report 0.4.19 (27).
- App test command: `DT_SIMULATOR_NAME='iPhone 17 Pro' tools/dt-test all
  -derivedDataPath /tmp/dosetap-fresh-night.kbRCDW/derived
  -resultBundlePath /tmp/dosetap-unknown-save.5iZ8zW/green.xcresult
  -parallel-testing-enabled NO -only-testing:DoseTapTests/SessionRepositoryTests
  -only-testing:DoseTapTests/CheckInCarryForwardTests
  -only-testing:DoseTapTests/MedicationMutationTransactionTests CODE_SIGNING_ALLOWED=NO`.
  Destination: iPhone 17 Pro, iOS 26.5 simulator. Logs and result bundles are in
  `/tmp/dosetap-unknown-save.5iZ8zW` and are disposable local evidence.

## Remaining work

The earlier carry-forward repair is documented in `fresh-pre-sleep-answers.md`.
The form's automatic substance quantities/times, optional unknown detail entry,
and legacy boolean adapter defaults still need repair under DOSETAP-51. Explicit
beverage-volume/caffeine-mass units and legacy interpretation remain DOSETAP-52.
This slice does not change Apple Health records, dose actions, alarms or quick logs.
Sleep timing markers and counts remain planned under DOSETAP-56/57.

No full iOS/UI regression, fresh visual acceptance, signed-phone installation,
owner acceptance, hosted CI or main merge was performed for this storage slice.
Pre-existing Xcode project ordering and UI-test scheme changes were present during
testing and remain excluded from this commit. Build metadata is the only intended
project-file change.
