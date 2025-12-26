# Independent Code Review: DoseTap v2.10.0
**Date:** 2025-12-25  
**Reviewer:** Codex (independent)  
**Readiness Score:** 45/100 (ship blocked: failing Xcode test + SSOT divergence)

## Readiness Summary
- SwiftPM suites are deterministic across required timezones (265 tests pass in default, UTC, and America/New_York runs).
- Xcode suite fails on device/simulator: timezone-change detection test is red.
- App surfaces multiple parallel state owners (SessionRepository vs DataStorageService/SQLiteStorage), so Tonight/Timeline/Settings can diverge from the tested source of truth.
- Support/export documentation overclaims privacy and implementation status.
- Shipping recommendation: **BLOCK** until P0 items are fixed and revalidated.

## Architecture Truth Table
| Layer | Actual source of truth | Notes |
|-------|-----------------------|-------|
| Data (sessions/doses) | `EventStorage` SQLite (`ios/DoseTap/Storage/EventStorage.swift:234`) plus separate `SQLiteStorage` and JSON `DataStorageService` stores | Multiple stores coexist; only EventStorage is covered by core tests. |
| State | `SessionRepository.shared` (DoseTap target) **and** `DataStorageService.shared` (DoseTapiOSApp ContentView/Inventory/Settings) | ContentView actions write to JSON, not SessionRepository. |
| View binding | Tonight (DoseTap target) binds SessionRepository via `ContentView`/`DoseTapCore`; Tonight (DoseTapiOSApp) uses `DoseCoreIntegration` for context but the main `ContentView` reads/writes `DataStorageService`; Timeline merges `SQLiteStorage` + `EventStorage` (`ios/DoseTapiOSApp/TimelineView.swift:435-488`); Settings/Dashboard use `DataStorageService`. |

## P0 Findings
1) **Xcode tests failing (timezone change detection)**  
   - Evidence: `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.2'` → `SessionRepositoryTests.test_timezoneChange_detectedAfterDose1()` failed (`/tmp/xcodebuild_test.log`). Test asserts timezone shift is detected (`ios/DoseTapTests/SessionRepositoryTests.swift:277-293`).
2) **Parallel state breaks single source of truth**  
   - Dose actions in DoseTapiOSApp `ContentView` call `DataStorageService.logEvent(.dose1/.dose2/.snooze/.bathroom)` instead of SessionRepository (`ios/DoseTapiOSApp/DoseTapiOSApp.swift:297-329`).  
   - `DataStorageService` persists sessions/events to JSON (`ios/DoseTapiOSApp/DataStorageService.swift:77-185`), and Timeline merges `SQLiteStorage` + `EventStorage` (`ios/DoseTapiOSApp/TimelineView.swift:435-488`). These paths bypass notification cancellation and tested deletion logic, so Tonight/History/Timeline/Settings can drift from SessionRepository.

## P1 Findings
- **Time correctness not resilient to timezone changes**: `currentSessionDate()` and `computeSessionDate(for:)` use `Date()` + `Calendar.current` with no injected timezone or stored offset (`ios/DoseTap/Storage/EventStorage.swift:234-249`, `ios/DoseTap/Storage/SessionRepository.swift:536-552`). After travel, session_date can rebind to a different day; the failing Xcode test shows the detection path is ineffective on simulator.
- **Support/export truth mismatch**: README claims “zero PII” support bundle (`docs/SSOT/README.md:1240-1246`), but `DataExportService` exports health + WHOOP data unredacted (`ios/DoseTapiOSApp/DataExportService.swift:86-198`) and `SupportBundleExport` is a mock zip with no redaction or real content (`ios/DoseTap/SupportBundleExport.swift:569-668`).
- **Documentation misstates ship gate**: `docs/PROD_READINESS_TODO.md:1-36` asserts Xcode tests are passing; current `xcodebuild` run fails.

## P2 Findings
- **Manual cascade coverage is fragile**: `EventStorage.deleteSession` deletes only a hardcoded table list (`ios/DoseTap/Storage/EventStorage.swift:1138-1162`), and `fetchRowCount` only checks those tables (`ios/DoseTap/Storage/EventStorage.swift:1071-1078`). Adding a new table without updating both lists would silently leave orphan rows; exports/timeline would show the drift but tests would not fail.

## Required Test Runs (evidence)
- `swift test --verbose` → `Executed 265 tests, with 0 failures` (`/tmp/swift_test_default.log`).
- `TZ=UTC swift test --verbose` → `Executed 265 tests, with 0 failures` (`/tmp/swift_test_utc.log`).
- `TZ=America/New_York swift test --verbose` → `Executed 265 tests, with 0 failures` (`/tmp/swift_test_est.log`).
- `xcodebuild test ... iPhone 15 iOS 17.2` → **FAIL** `SessionRepositoryTests.test_timezoneChange_detectedAfterDose1()` (`/tmp/xcodebuild_test.log`).
- `bash tools/ssot_check.sh` → PASS; `bash tools/doc_lint.sh` → PASS.

## Evidence Table
| Claim | File/line | Proof (command/output) |
|-------|-----------|------------------------|
| SwiftPM suites (required) executed 265 tests | n/a | `swift test --verbose` → `Executed 265 tests, with 0 failures` |
| Timezone-matrix determinism (UTC) | n/a | `TZ=UTC swift test --verbose` → `Executed 265 tests, with 0 failures` |
| Timezone-matrix determinism (America/New_York) | n/a | `TZ=America/New_York swift test --verbose` → `Executed 265 tests, with 0 failures` |
| Xcode suite failing timezone change test | `ios/DoseTapTests/SessionRepositoryTests.swift:277-293` | `xcodebuild test ...` → `Test case 'SessionRepositoryTests.test_timezoneChange_detectedAfterDose1()' failed` |
| Parallel state path bypasses SessionRepository | `ios/DoseTapiOSApp/DoseTapiOSApp.swift:297-329` | Code logs dose events via `DataStorageService.logEvent` (no SessionRepository/notification cancellation) |
| Support bundle privacy claim is inaccurate | `docs/SSOT/README.md:1240-1246`; `ios/DoseTapiOSApp/DataExportService.swift:86-198`; `ios/DoseTap/SupportBundleExport.swift:569-668` | Code exports health/WHOOP data and generates mock bundle without redaction, conflicting with “zero PII” claim |

## Shipping Recommendation
**BLOCK** until:
1. Fix timezone detection on device/simulator (SessionRepository + EventStorage should use injected/autoupdating timezone or stored offset; rerun `xcodebuild test`).
2. Remove or realign `DataStorageService`/`SQLiteStorage` so Tonight/Timeline/Settings read/write through SessionRepository and its tested storage/notification paths.
3. Update support/export to match privacy claims (or soften claims) and add redaction tests; broaden manual cascade tests for new tables.
