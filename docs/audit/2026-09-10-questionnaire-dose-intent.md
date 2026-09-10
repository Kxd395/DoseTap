# Morning questionnaire medication-intent repair

Date: 2026-09-10
Scope: DOSETAP-67; delivery plan DOSETAP-69
Baseline: `5e34032207d8410a99587b98922d024143163aa6`, build 39. Candidate: 0.4.19 (40).

## Finding and change

New synthetic repository tests reproduced IR-01: a missing Dose 1 initialized selected, a missing Dose 2 initialized Taken, and an existing skip initialized a new skip action. Saving could create an administration or replace skip evidence using a suggested time. An unconditional annotation update also removed existing reasons/notes when the morning fields were unanswered.

Missing-dose controls now initialize unselected/Leave as-is. A questionnaire with no selected medication action performs no medication reconciliation or annotation update. Its reasons remain questionnaire answers; existing ledger reasons are edited through History. Explicitly selected retrospective actions remain supported and include their selected reason data. No-op reconciliation returns no receipt, not an invented committed mutation. Retry copy no longer claims a medication write when none occurred.

This does not establish the cause of the owner's earlier unexpected Dose 2 record or prove that all recurring check-in reports are resolved on the installed phone. The full separate medication-action flow and draft/skip semantics remain planned in the [delivery plan](../plans/2026-09-10-questionnaire-delivery-plan.md).

## Validation

All records were synthetic; no personal medication or Health records were edited.

| Check | Result and evidence class |
| --- | --- |
| New app regressions before repair | Expected failure: three test methods detected missing-dose/default or ledger-preservation defects; explicit Dose 2 selection control passed |
| `DT_SIMULATOR_NAME='iPhone 17 Pro' tools/dt-test all -only-testing:DoseTapTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | 414 tests passed, automated iOS 26.5 simulator; includes failure/retry, ledger preservation and explicit recording |
| `swift build -q`; `swift test -q` | Build passed; 682 XCTest and 43 Swift Testing cases passed, automated |
| `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTapUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DoseTapUITests/DoseTapUITests/testMorningDefaultDoseIntent -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO` | One test passed on build 40; visible Leave as-is selection and successful questionnaire dismissal. Exported screenshots inspected: unchanged Dose 2, then Tonight with one unrecorded second dose |
| `xcodebuild build -quiet -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` | Build 40 passed, automated |
| `bash tools/check_app_version.sh` | DoseTap and Staging Debug/Release all report 0.4.19 (40) |
| Plane workflow, docs, SSOT, architecture, dose-write and legacy-safety guards; `git diff --check` | Passed locally; hosted integration evidence is recorded in the PR and Plane workpad |

Local logs use `/tmp/dosetap-qrev-*`; UI attachments and manifest are in `/tmp/dosetap-qrev-ui-proof/`. The result bundle is `Test-DoseTapUITests-2026.09.10_07-21-47--0400.xcresult` in the local DoseTap DerivedData test logs. Temporary paths are workstation evidence, not permanent repository artifacts.

The documentation guard initially found generated `docs/.DS_Store`; it was moved recoverably to `/tmp/dosetap-qrev-finder.gCeGJZ/docs.DS_Store` and the guard passed on rerun. Existing Xcode project formatting and UI-test scheme edits were preserved and excluded; only the four app build-number settings are included from the project file.

## Open acceptance

- Signed-phone/owner readback of morning save, restart and exact-night reminder behavior; capture the exact error/build if it recurs.
- Other questionnaire findings, full separate medication confirmation, partial multi-action failure recovery, durable draft/skip state and broad freshness repairs are not closed by this slice.
- No signed phone installation, Apple Health parity, accessibility audit or clinical approval is claimed. Alarm behavior and three-second confirmation policies were not changed.

DOSETAP-67 remains In Progress. DOSETAP-69 can close as a planning deliverable without closing its downstream implementation or external gates. Plane post-write readback is required for either status claim.
