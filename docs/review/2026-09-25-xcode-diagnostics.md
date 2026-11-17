# Xcode compiler diagnostic cleanup

Status: Local compiler fixes validated; integration tracked in Plane DOSETAP-25.

The owner reported Xcode 27 warnings in the build-71 project. This compiler
maintenance slice keeps version 0.4.19 (71); it does not install a phone build or
change medication, questionnaire, schedule, storage or alarm behavior.

## Changes

- Import Combine explicitly in the three timer-owning SwiftUI files.
- Resolve shared repositories and alarm services inside main-actor initializers
  and methods instead of in nonisolated default-argument expressions. Injected
  dependencies remain supported.
- Declare the immutable supply-reminder request identifier nonisolated. The
  reminder service itself remains main-actor isolated.
- Read the numeric iOS version through ProcessInfo from the diagnostic actor,
  without reaching into UIDevice. The diagnostic metadata field remains a string.
- Copy the evaluated certificate chain with SecTrustCopyCertificateChain and
  check each certificate's SPKI pin. System trust evaluation still happens first;
  mismatch/fallback rules and production pins are unchanged.
- Remove redundant public modifiers within the public repository extension.

## Recommended-settings notice

Inspected the actual Xcode dialog. It proposes raising all four targets to the
SDK's recommended minimum iOS, inheriting the signing team, enabling string
catalog symbol generation, and parallelizing command-line -target builds.
Cancelled the dialog: these are separate project-policy changes. Existing iOS 16
support, signing, and language mode remain intact. The notice may remain visible;
it is not a compiler error and was not suppressed by falsifying review metadata.

## Protected local changes

The project and Info.plist were already dirty before this work. Xcode had
reordered project entries, moved Photos usage text into two target settings, and
removed three usage strings from Info.plist. Those edits were inspected and
preserved, and are excluded from this maintenance commit. No reset, stash,
uninstall or data deletion was used.

## Validation

- `swift build -q`: passed.
- `swift test -q`: 789 XCTest and 43 Swift Testing cases passed.
- Fresh generic iOS Simulator app build with isolated DerivedData: passed, with
  no compiler warning or error lines.
- Full `DoseTapTests` on iPhone 17 Pro / iOS 26.5: 527 tests passed.
- Native Xcode build of the open project: succeeded at 18:28 on September 25;
  its Build Results panel explicitly displayed **No issues**. Older build reports
  retain their historical warnings.
- Plane workflow checks (15 tests, 80 assertions), SSOT check, documentation lint,
  and whitespace check: passed.
- Existing project and Info.plist hashes stayed unchanged during Xcode inspection.

The app-test build still emits two SDK linker warnings: the local XCTest and
XCTestSwiftSupport libraries target iOS Simulator 17 while the test target
supports 16. No source warning remains in the fresh app build. Adjusting test
platform policy is deferred rather than raising the app minimum just to hide it.
The broader DOSETAP-25 shellcheck, stale validation-message and Studio warning
acceptance remains open; this bounded iOS slice does not close the whole item.

Local evidence: `/tmp/dosetap-xcode-diagnostics-build.log`,
`/tmp/dosetap-xcode-diagnostics-core.log`,
`/tmp/dosetap-xcode-diagnostics-tests.log`, and the isolated DerivedData test
result under `/tmp/dosetap-xcode-diagnostics/Logs/Test/`. These temporary files
are not durable acceptance records; the counts and scope above are the record.
Phone installation and owner acceptance are not claimed. The weekly-schedule
build-71 post-merge Documentation CI, Swift CI and CI runs were also checked and
all passed before this maintenance slice began.
