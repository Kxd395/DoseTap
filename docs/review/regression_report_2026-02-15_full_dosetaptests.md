# DoseTap Regression Report — Full DoseTapTests Sweep

Date: 2026-02-15
Runner: Local macOS
Xcode: 26.2 (Build 17C52)
Destination: iPhone 16 simulator (OS 18.6, id=00188B7D-0ECC-41A1-825B-AE23140FED27)
Scheme: DoseTap
Target Scope: DoseTapTests only

## Command Executed

```bash
xcodebuild \
  -project /Volumes/Developer/projects/DoseTap/ios/DoseTap.xcodeproj \
  -scheme DoseTap \
  -destination 'id=00188B7D-0ECC-41A1-825B-AE23140FED27' \
  -derivedDataPath /Volumes/Developer/projects/DoseTap/.xcode-derived \
  test -only-testing:DoseTapTests
```

Log file:
- `/tmp/dosetap-full-tests-1771181827.log`

Result bundle:
- `/Volumes/Developer/projects/DoseTap/.xcode-derived/Logs/Test/Test-DoseTap-2026.02.15_13-57-09--0500.xcresult`

## Summary

- Overall result: **PASS** (`** TEST SUCCEEDED **`)
- Passed test cases: **132**
- Failed test cases: **0**
- Suites started: **17** (plus TimelineFilteringTests line interleaved/corrupted in xcodebuild stdout, but its test case passed)

## Suite Coverage Snapshot

- `SessionRepositoryTests`: 31 passed
- `URLRouterTests`: 23 passed
- `DataIntegrityTests`: 13 passed
- `UIStateTests`: 13 passed
- `ExportIntegrityTests`: 11 passed
- `AlarmAndSetupRegressionTests`: 8 passed
- `HealthKitProviderTests`: 7 passed
- `E2EIntegrationTests`: 7 passed
- `NavigationFlowTests`: 4 passed
- `UISmokeTests`: 3 passed
- `EventStorageIntegrationTests`: 2 passed
- `NotificationCenterIntegrationTests`: 2 passed
- `PreSleepCardStateTests`: 2 passed
- `SleepPlanStoreTemplateTests`: 2 passed
- `APIContractTests`: 1 passed
- `ExportImportRoundTripTests`: 1 passed
- `WatchOSSmokeTests`: 1 passed
- `TimelineFilteringTests`: 1 passed (stdout suite name line was split by xcodebuild timing output)

## Targeted Defect Areas Confirmed by Full Sweep

The full run included and passed tests that cover the implemented alarm/dose fixes:
- Notification ID cancellation parity:
  - `NotificationCenterIntegrationTests.test_deleteSession_cancelsPendingUNNotifications`
  - `NotificationCenterIntegrationTests.test_skipDose_cancelsWakeAlarms`
- URL override behavior:
  - `URLRouterTests.test_dose2_deepLink_allowsLateOverride_whenWindowClosed`
  - `URLRouterTests.test_dose2_deepLink_rejectsBeforeWindow_withoutOverride`
- EventStorage integration:
  - `EventStorageIntegrationTests.test_fetchDoseLog_returnsCurrentAndHistoricalSessionData`
  - `EventStorageIntegrationTests.test_fetchRecentSessionsLocal_handlesSleepOnlyDoseOnlyAndMixedSessions`

## Residual Risk

- This is simulator validation; physical-device behavior for critical alerts still depends on Apple entitlement approval and provisioning configuration.
