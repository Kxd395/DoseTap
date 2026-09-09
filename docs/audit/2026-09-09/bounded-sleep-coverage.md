# Bounded sleep coverage

Date: 2026-09-09
Scope: DOSETAP-56 second implementation slice; DOSETAP-57 remains Todo.
Baseline: `19be29f1f640c39d590fffffc3404239a5f1acde`, shipping checkout `DoseTap-main`.
Candidate: 0.4.19 (34).

## Implemented and intentionally unchanged

`SleepIntervalCoverage` clips and unions resolved recorded intervals inside caller-supplied absolute bounds. It includes both blocks of split sleep without a 90-minute cluster cutoff. It reports sleep, awake, classified coverage, unmeasured time, coverage percentage and a derivation version. Any positive gap is partial coverage. No observations is unavailable with null sleep/awake amounts; observed all-awake coverage has a genuine zero sleep amount. Invalid windows and non-finite/reversed samples cannot invent duration.

The existing post-Dose-2 estimator delegates to this utility, retaining its optional result, awake-over-asleep overlap handling and one-second coverage-warning tolerance. Its existing callers and export fields are unchanged.

The separate opt-in `HealthKitService.fetchSleepCoverage(from:to:)` queries overlapping samples and clips before normalizing. Unknown and in-bed observations remain unclassified. It uses the existing conservative overlap policy, not a new device-accuracy ranking. Apple's [query options documentation](https://developer.apple.com/documentation/healthkit/hkqueryoptions) and the local iOS 26.5 `HKQuery.h` define empty options as overlap matching; strict-start matching excludes samples beginning before the query start. A synthetic HealthKit predicate test verifies that distinction.

No screen or export invokes this new query yet. The legacy primary-episode queries, cluster selection, biometric range and displays remain separate. The utility does not choose, persist or certify a treatment-night window. No medication, alarm, questionnaire, schema or personal-data changes were made.

## Validation

All fixtures are synthetic. Commands ran on the candidate worktree with two pre-existing unrelated Xcode edits preserved. Local temporary logs are diagnostic evidence, not repository artifacts or personal sleep records.

- Test-first core signal: the new focused suite failed because `SleepIntervalCoverage` did not exist, then all nine new tests passed. Logs: `/tmp/dosetap56-coverage-red.log`, `/tmp/dosetap56-coverage-green.log`.
- `swift build -q`: passed. `TZ=UTC swift test -q` and `TZ=America/New_York swift test -q`: each passed 664 XCTest cases plus 43 Swift Testing cases. Logs: `/tmp/dosetap56-coverage-core-utc.log`, `/tmp/dosetap56-coverage-core-ny.log`.
- Cases cover split blocks, clipping at both ends, outside naps, duplicate/reordered intervals, awake overlaps, missing versus all-awake data, invalid/non-finite timestamps, touching endpoints, a quarter-second gap, the DST repeated hour, Codable version round-trip and 256 combinations checked against an independent minute-grid oracle.
- `xcodebuild test`, DoseTap scheme, iPhone 17 Pro Max / iOS 26.5, signing disabled: 102 passed across `HealthKitProviderTests`, `DashboardAnalyticsAuditTests`, `DoseActionCoordinatorClockTests` and `MedicationMutationTransactionTests`. Four new adapter tests cover bounded split sleep, unknown/in-bed coverage, invalid data and query overlap semantics. Result: `/tmp/dosetap56-coverage-tests.xcresult`. This first pass used build 33 before the metadata-only bump.
- `swift test --package-path macos/DoseTapStudio`: 69 executed, 66 passed, three optional fixture/visual tests skipped, zero failures. Log: `/tmp/dosetap56-coverage-studio.log`.
- Generic iOS Simulator build of 0.4.19 (34), signing disabled: passed; built bundle readback reports 34. Log: `/tmp/dosetap56-coverage-build34.log`. App-version check passed for both configurations of DoseTap and DoseTapStaging.
- The same 102 targeted iOS tests were rerun on build 34 and passed: `/tmp/dosetap56-coverage-build34-tests.xcresult`.
- Plane workflow (10 tests / 64 assertions), SSOT, documentation lint, architecture, dose-state writes, legacy safety paths and whitespace checks passed. Commit-range whitespace checks also cover new files before handoff.

Targeted command: `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/dosetap56-derived -parallel-testing-enabled NO -only-testing:DoseTapTests/HealthKitProviderTests -only-testing:DoseTapTests/DashboardAnalyticsAuditTests -only-testing:DoseTapTests/DoseActionCoordinatorClockTests -only-testing:DoseTapTests/MedicationMutationTransactionTests CODE_SIGNING_ALLOWED=NO`.

## Open integration and acceptance

DOSETAP-56 remains In Progress. Reviewed-window storage still needs stable session identity, original timezone and boundary source. Full raw sample identity/revision retention, conflict reconciliation, permission/readiness wording, source edits/deletions, boundary corrections and overlapping-session/nap conflict handling remain open. Screens and exports still use their existing primary-episode paths; this slice does not fix their split-night totals by itself.

DOSETAP-57 remains Todo. Dose-to-sleep and return-to-sleep markers, associated awake episodes and completed counts, per-metric boundary evidence, and Timeline/History/Dashboard/export/Studio parity remain to implement after those prerequisites. Existing Apple Health information and quick logs stay in place.

Signed-device HealthKit queries, real-data parity, owner-observed interpretation and accessibility remain open. No live Health store query, phone installation, new UI validation or medication/alarm acceptance is claimed. The existing medication regression suite is not evidence that the historical unexpected Dose 2 report is resolved.

## Preservation and tracker

Reversing only the candidate's build 33-to-34 change reproduces the starting unrelated Xcode diff SHA-256 `b7f46c2c70439dbab08bf2eef0ef65e200b13f2c74ddec7be98fa16e1537d46f`. Only four build-number hunks are staged from the project; object-order and UI-test scheme edits remain excluded. The preserved feature checkout and historical branches remain untouched.

Exact DOSETAP-56 preflight confirmed In Progress. Its structured workpad records this slice and the open gates; Plane write/readback is required at closeout. Hosted checks and merge state are recorded in the PR and final Plane workpad, not inferred from these local test results.
