# DoseTap Comprehensive Audit Report (V3)

## Environment
- macOS version: 15.7.4 (24G508)
- Xcode version: 26.2 (17C52)
- Swift version: 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
- iOS Simulator: iPhone 16 Pro, iOS 18.6 (available)
- Build scheme: DoseTap
- Build flags: SwiftPM default Debug (no explicit flags)

## Build/Test Baseline
- Build command: `swift build 2>&1 | tee build.log`
- Test command: `swift test -q 2>&1 | tee test.log`
- Build warnings: 1 (SwiftPM unhandled file: `ios/Core/CertificatePinning.swift`). Evidence: `build.log:1-2`
- Build errors: 0
- Tests: 277 passed. Warning logged: non-sensical interval. Evidence: `test.log:615`, source `ios/Core/TimeIntervalMath.swift:13-25`
- Coverage note: SwiftPM build covers `DoseCore` target only (not iOS app). Evidence: `Package.swift:14-46`

## Executive Summary
| Section | Content |
|---|---|
| **Top 10 Issues** | 1) **Critical** Timeline vs History mismatch: `SleepStageTimeline` expects `dose1_taken/dose2_taken` and `wake_final` in `dose_events`, but storage uses `dose1/dose2` and logs `wake_final` to `sleep_events`. Evidence: `ios/DoseTap/SleepStageTimeline.swift:583-590`, `ios/DoseTap/Storage/EventStorage.swift:906-935`, `ios/DoseTap/Storage/SessionRepository.swift:854-868`  2) **Critical** Event type normalization is inconsistent (Title Case vs camelCase vs snake_case) across QuickLog, URLRouter, InputValidator, and Timeline mappings. Evidence: `ios/DoseTap/UserSettingsManager.swift:142-175`, `ios/DoseTap/ContentView.swift:42-66`, `ios/DoseTap/Security/InputValidator.swift:22-35`, `ios/DoseTap/URLRouter.swift:276-303`, `ios/DoseTap/FullApp/TimelineView.swift:750-782`  3) **Critical** Dose actions write to `sleep_events` via `EventLogger`, duplicating dose data across tables. Evidence: `ios/DoseTap/ContentView.swift:1481-1550`, `ios/DoseTap/ContentView.swift:42-66`  4) **Critical** `session_id` split-brain: fallback uses `session_date` and backfills `session_id` from `session_date`, violating SSOT UUID identity. Evidence: `ios/DoseTap/Storage/EventStorage.swift:628-629`, `ios/DoseTap/Storage/EventStorage.swift:382-413`, `ios/DoseTap/Storage/SessionRepository.swift:410-417`, SSOT `docs/SSOT/README.md:27-29`  5) **Major** CSV export failure is silent: errors only printed, no user-visible failure handling; export runs on main thread. Evidence: `ios/DoseTap/SettingsView.swift:561-577`  6) **Major** Snooze rules diverge from SSOT: UI allows snooze in near-close and increments count even when AlarmService refuses. Evidence: `ios/DoseTap/ContentView.swift:1603-1605`, `ios/Core/DoseWindowState.swift:102-106`, `ios/DoseTap/AlarmService.swift:209-217`, `ios/DoseTap/URLRouter.swift:190-196`  7) **Major** Time edits do not update `session_date/session_id`, causing cross-session inconsistencies. Evidence: `ios/DoseTap/Storage/EventStorage.swift:1038-1103`, `ios/DoseTap/ContentView.swift:2723-2758`  8) **Major** No foreign key constraints despite `PRAGMA foreign_keys=ON`, allowing orphaned rows. Evidence: `ios/DoseTap/Storage/EventStorage.swift:63-68`, `ios/DoseTap/Storage/EventStorage.swift:84-187`  9) **Major** Database I/O on MainActor (EventStorage + export) risks UI stalls. Evidence: `ios/DoseTap/Storage/EventStorage.swift:13-14`, `ios/DoseTap/SettingsView.swift:561-577`, `ios/DoseTap/Storage/EventStorage.swift:2568-2655`  10) **Major** Split persistence layers (CoreData vs SQLite) create data fragmentation and unused exports. Evidence: `ios/DoseTap/Persistence/PersistentStore.swift:6-35`, `ios/DoseTap/Export/CSVExporter.swift:7-27`, `ios/DoseTap/Storage/JSONMigrator.swift:31-68`, `ios/DoseTap/Storage/EventStorage.swift:12-49` |
| **Root Cause Analysis** | **Timeline/History**: mismatched event type strings and tables (`dose_events` vs `sleep_events`) across UI/DB layers. Evidence: `ios/DoseTap/SleepStageTimeline.swift:583-590`, `ios/DoseTap/Storage/EventStorage.swift:906-935`, `ios/DoseTap/Storage/SessionRepository.swift:854-868`  **CSV Export**: synchronous, UI-thread file generation with no user-visible error path; failures appear as "nothing happens". Evidence: `ios/DoseTap/SettingsView.swift:561-577`  **Split-brain data**: CoreData artifacts still present while production uses SQLite, and `session_id` is backfilled from `session_date`. Evidence: `ios/DoseTap/Persistence/PersistentStore.swift:6-35`, `ios/DoseTap/Storage/EventStorage.swift:382-413` |
| **Risk Matrix** | Data loss: Medium likelihood / High impact (session_id mismatch + missing FKs). Wrong insights: High likelihood / High impact (timeline/history inconsistency). Crash: Medium likelihood / Medium impact (main-thread DB + large export). Privacy: Medium likelihood / High impact (missing privacy manifest, logs). Compliance: Medium likelihood / High impact (session identity + export format). |
| **Recommendation** | **Do not ship** until P0/P1 items are fixed: timeline/history parity, CSV export robustness, and session identity consistency. |

## Repository Map
├── Tests/ — Folder [Active]
│   └── DoseCoreTests/ — Folder [Active]
│       ├── APIClientTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── APIErrorsTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── CRUDActionTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── CSVExporterTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── DataRedactorTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── Dose2EdgeCaseTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── DoseUndoManagerTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── DoseWindowEdgeTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── DoseWindowStateTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── EventRateLimiterTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── MedicationLoggerTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── OfflineQueueTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── SSOTComplianceTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── SessionIdBackfillTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── SleepEnvironmentTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── SleepEventTests.swift — Swift source [Active] (reviewed: shallow)
│       ├── SleepPlanCalculatorTests.swift — Swift source [Active] (reviewed: shallow)
│       └── TimeCorrectnessTests.swift — Swift source [Active] (reviewed: shallow)
├── agent/ — Audit prompts and agent instructions. [Spec-only]
│   ├── AUDIT_PROMPT_V3.md — Markdown document [Spec-only] (reviewed: deep)
│   ├── agent_brief.md — Markdown document [Spec-only] (reviewed: shallow)
│   └── tasks_backlog.md — Markdown document [Spec-only] (reviewed: shallow)
├── archive/ — Archived/deprecated artifacts and snapshots. [Legacy]
│   ├── audits_2025-12-24/ — Folder [Legacy]
│   │   ├── AUDIT_LOG_2025-12-24.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── AUDIT_LOG_2025-12-24_session2.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── AUDIT_LOG_2025-12-24_session3.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── AUDIT_LOG_2025-12-24_session4.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── AUDIT_LOG_2025-12-24_session5.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── AUDIT_REPORT_2025-12-24.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── AUDIT_REPO_2025-12-24.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── AUDIT_REPO_FIXES_2025-12-24.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── AUDIT_TODO.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── CODE_REVIEW_2025-12-24_session3.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── FIX_PLAN_2025-12-24_session3.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── FIX_PLAN_2025-12-24_session4.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── FIX_PLAN_2025-12-24_session5.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── HYPERCRITICAL_AUDIT_2025-12.md — Markdown document [Legacy] (reviewed: shallow)
│   │   └── use_case.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── audits_2026-01/ — Folder [Legacy]
│   │   ├── AUDIT_LOG.md — Project document [Legacy] (reviewed: shallow)
│   │   └── TEST_FIX_SUMMARY_2025-12-25.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── docs/ — Folder [Legacy]
│   │   ├── BUILD_SUMMARY.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── SETUP_WIZARD_COMPLETE.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── implementation-roadmap.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── product-description-old.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── progress-roadmap-clean.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── progress-roadmap-fixed.md — Markdown document [Legacy] (reviewed: shallow)
│   │   └── progress-roadmap.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── docs_superseded/ — Folder [Legacy]
│   │   ├── DoseTap_Spec.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── DoseTap_Spec.rtf — RTF file [Legacy] (reviewed: shallow)
│   │   ├── SSOT.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── SSOT_NAV.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── api-documentation.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── button-logic-mapping.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── product-description-updated.md — Markdown document [Legacy] (reviewed: shallow)
│   │   └── ui-ux-specifications.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── ios_review_2025-12-24/ — Folder [Legacy]
│   │   ├── ASCII.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── DoseTap_Application_Description_SSOT_v1.0.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── DoseTap_SSOT_Advise.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── ReviewUpdate.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── dashboard.md — Markdown document [Legacy] (reviewed: shallow)
│   │   └── whoop_OpenAIP.json — JSON data/spec [Legacy] (reviewed: shallow)
│   ├── legacy_app_entries/ — Folder [Legacy]
│   │   ├── AppMinimal_DoseTapApp.swift — Swift source [Legacy] (reviewed: shallow)
│   │   ├── DoseTapWorkingApp.swift — Swift source [Legacy] (reviewed: shallow)
│   │   ├── DoseTapiOSApp_nested_DoseTapiOSApp.swift — Swift source [Legacy] (reviewed: shallow)
│   │   ├── DoseTapiOS_DoseTapApp.swift — Swift source [Legacy] (reviewed: shallow)
│   │   ├── DoseTapiOS_DoseTapMiniApp.swift — Swift source [Legacy] (reviewed: shallow)
│   │   └── DoseTapiOS_Sources_DoseTapMiniApp.swift — Swift source [Legacy] (reviewed: shallow)
│   ├── legacy_docs/ — Folder [Legacy]
│   │   ├── AUDIT_REPORT_2025.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── MindMap.txt — Text file [Legacy] (reviewed: shallow)
│   │   ├── product-description.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── product_description.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── project-review.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── scaffolding-improvements.md — Markdown document [Legacy] (reviewed: shallow)
│   │   └── upgrades.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── root_cleanup/ — Folder [Legacy]
│   │   ├── api_specification.md — Markdown document [Legacy] (reviewed: shallow)
│   │   ├── test_whoop_api.sh — Shell script [Legacy] (reviewed: shallow)
│   │   ├── ui_preview.html — HTML file [Legacy] (reviewed: shallow)
│   │   ├── ui_specification.md — Markdown document [Legacy] (reviewed: shallow)
│   │   └── verify_inventory.sh — Shell script [Legacy] (reviewed: shallow)
│   ├── tools_whoop/ — Folder [Legacy]
│   │   ├── oauth_callback.py — Python script [Legacy] (reviewed: shallow)
│   │   ├── whoop_8888.py — Python script [Legacy] (reviewed: shallow)
│   │   ├── whoop_9090.py — Python script [Legacy] (reviewed: shallow)
│   │   ├── whoop_curl.py — Python script [Legacy] (reviewed: shallow)
│   │   ├── whoop_fetch.py — Python script [Legacy] (reviewed: shallow)
│   │   ├── whoop_oauth.py — Python script [Legacy] (reviewed: shallow)
│   │   ├── whoop_oauth_v2.py — Python script [Legacy] (reviewed: shallow)
│   │   ├── whoop_simple.py — Python script [Legacy] (reviewed: shallow)
│   │   └── whoop_test.py — Python script [Legacy] (reviewed: shallow)
│   ├── CODEBASE_AUDIT_REPORT.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── CORE_DATA_MIGRATION_SUMMARY.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── DEVELOPMENT_GUIDE.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── ENHANCED_COMPONENTS_STATUS.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── EventStoreCoreData.swift — Swift source [Legacy] (reviewed: shallow)
│   ├── IMPLEMENTATION_STATUS.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── LOCAL_DEVELOPMENT_COMPLETE.md — Markdown document [Legacy] (reviewed: shallow)
│   ├── LOCAL_DEVELOPMENT_PLAN.md — Markdown document [Legacy] (reviewed: shallow)
│   └── SSOT_v2.md — Markdown document [Legacy] (reviewed: shallow)
├── build/ — Local build artifacts (generated). [Dead]
│   ├── Debug-iphoneos/ — Folder [Dead]
│   │   ├── DoseCore.swiftmodule/ — Folder [Dead]
│   │   │   ├── Project/ — Folder [Dead]
│   │   │   │   └── arm64-apple-ios.swiftsourceinfo — SWIFTSOURCEINFO file [Dead] (skipped: generated)
│   │   │   ├── arm64-apple-ios.abi.json — JSON data/spec [Dead] (skipped: generated)
│   │   │   ├── arm64-apple-ios.swiftdoc — SWIFTDOC file [Dead] (skipped: generated)
│   │   │   └── arm64-apple-ios.swiftmodule — SWIFTMODULE file [Dead] (skipped: generated)
│   │   └── DoseCore.o — O file [Dead] (skipped: generated)
│   ├── DoseTap.build/ — Folder [Dead]
│   │   └── Debug-iphoneos/ — Folder [Dead]
│   │       └── DoseCore.build/ — Folder [Dead]
│   │           ├── Objects-normal/ — Folder [Dead]
│   │           │   └── arm64/ — Folder [Dead]
│   │           │       ├── APIClient.d — D file [Dead] (skipped: generated)
│   │           │       ├── APIClient.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── APIClient.o — O file [Dead] (skipped: generated)
│   │           │       ├── APIClient.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── APIClient.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── APIClientQueueIntegration.d — D file [Dead] (skipped: generated)
│   │           │       ├── APIClientQueueIntegration.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── APIClientQueueIntegration.o — O file [Dead] (skipped: generated)
│   │           │       ├── APIClientQueueIntegration.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── APIClientQueueIntegration.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── APIErrors.d — D file [Dead] (skipped: generated)
│   │           │       ├── APIErrors.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── APIErrors.o — O file [Dead] (skipped: generated)
│   │           │       ├── APIErrors.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── APIErrors.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── CSVExporter.d — D file [Dead] (skipped: generated)
│   │           │       ├── CSVExporter.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── CSVExporter.o — O file [Dead] (skipped: generated)
│   │           │       ├── CSVExporter.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── CSVExporter.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── DataRedactor.d — D file [Dead] (skipped: generated)
│   │           │       ├── DataRedactor.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── DataRedactor.o — O file [Dead] (skipped: generated)
│   │           │       ├── DataRedactor.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── DataRedactor.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── DiagnosticEvent.d — D file [Dead] (skipped: generated)
│   │           │       ├── DiagnosticEvent.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── DiagnosticEvent.o — O file [Dead] (skipped: generated)
│   │           │       ├── DiagnosticEvent.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── DiagnosticEvent.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── DiagnosticLogger.d — D file [Dead] (skipped: generated)
│   │           │       ├── DiagnosticLogger.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── DiagnosticLogger.o — O file [Dead] (skipped: generated)
│   │           │       ├── DiagnosticLogger.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── DiagnosticLogger.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── DoseCore-OutputFileMap.json — JSON data/spec [Dead] (skipped: generated)
│   │           │       ├── DoseCore-Swift.h — H file [Dead] (skipped: generated)
│   │           │       ├── DoseCore-dependencies-1.json — JSON data/spec [Dead] (skipped: generated)
│   │           │       ├── DoseCore-linker-args.resp — RESP file [Dead] (skipped: generated)
│   │           │       ├── DoseCore-primary-emit-module.d — D file [Dead] (skipped: generated)
│   │           │       ├── DoseCore-primary-emit-module.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── DoseCore-primary.priors — PRIORS file [Dead] (skipped: generated)
│   │           │       ├── DoseCore.LinkFileList — LINKFILELIST file [Dead] (skipped: generated)
│   │           │       ├── DoseCore.SwiftConstValuesFileList — SWIFTCONSTVALUESFILELIST file [Dead] (skipped: generated)
│   │           │       ├── DoseCore.SwiftFileList — SWIFTFILELIST file [Dead] (skipped: generated)
│   │           │       ├── DoseCore.abi.json — JSON data/spec [Dead] (skipped: generated)
│   │           │       ├── DoseCore.swiftdoc — SWIFTDOC file [Dead] (skipped: generated)
│   │           │       ├── DoseCore.swiftmodule — SWIFTMODULE file [Dead] (skipped: generated)
│   │           │       ├── DoseCore.swiftsourceinfo — SWIFTSOURCEINFO file [Dead] (skipped: generated)
│   │           │       ├── DoseCore_const_extract_protocols.json — JSON data/spec [Dead] (skipped: generated)
│   │           │       ├── DoseCore_dependency_info.dat — DAT file [Dead] (skipped: generated)
│   │           │       ├── DoseTapCore.d — D file [Dead] (skipped: generated)
│   │           │       ├── DoseTapCore.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── DoseTapCore.o — O file [Dead] (skipped: generated)
│   │           │       ├── DoseTapCore.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── DoseTapCore.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── DoseUndoManager.d — D file [Dead] (skipped: generated)
│   │           │       ├── DoseUndoManager.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── DoseUndoManager.o — O file [Dead] (skipped: generated)
│   │           │       ├── DoseUndoManager.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── DoseUndoManager.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── DoseWindowState.d — D file [Dead] (skipped: generated)
│   │           │       ├── DoseWindowState.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── DoseWindowState.o — O file [Dead] (skipped: generated)
│   │           │       ├── DoseWindowState.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── DoseWindowState.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── EventRateLimiter.d — D file [Dead] (skipped: generated)
│   │           │       ├── EventRateLimiter.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── EventRateLimiter.o — O file [Dead] (skipped: generated)
│   │           │       ├── EventRateLimiter.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── EventRateLimiter.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── EventStore.d — D file [Dead] (skipped: generated)
│   │           │       ├── EventStore.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── EventStore.o — O file [Dead] (skipped: generated)
│   │           │       ├── EventStore.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── EventStore.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── ExtractedAppShortcutsMetadata.stringsdata — STRINGSDATA file [Dead] (skipped: generated)
│   │           │       ├── MedicationConfig.d — D file [Dead] (skipped: generated)
│   │           │       ├── MedicationConfig.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── MedicationConfig.o — O file [Dead] (skipped: generated)
│   │           │       ├── MedicationConfig.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── MedicationConfig.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── MorningCheckIn.d — D file [Dead] (skipped: generated)
│   │           │       ├── MorningCheckIn.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── MorningCheckIn.o — O file [Dead] (skipped: generated)
│   │           │       ├── MorningCheckIn.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── MorningCheckIn.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── OfflineQueue.d — D file [Dead] (skipped: generated)
│   │           │       ├── OfflineQueue.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── OfflineQueue.o — O file [Dead] (skipped: generated)
│   │           │       ├── OfflineQueue.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── OfflineQueue.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── RecommendationEngine.d — D file [Dead] (skipped: generated)
│   │           │       ├── RecommendationEngine.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── RecommendationEngine.o — O file [Dead] (skipped: generated)
│   │           │       ├── RecommendationEngine.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── RecommendationEngine.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── SessionKey.d — D file [Dead] (skipped: generated)
│   │           │       ├── SessionKey.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── SessionKey.o — O file [Dead] (skipped: generated)
│   │           │       ├── SessionKey.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── SessionKey.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── SleepEvent.d — D file [Dead] (skipped: generated)
│   │           │       ├── SleepEvent.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── SleepEvent.o — O file [Dead] (skipped: generated)
│   │           │       ├── SleepEvent.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── SleepEvent.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── SleepPlan.d — D file [Dead] (skipped: generated)
│   │           │       ├── SleepPlan.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── SleepPlan.o — O file [Dead] (skipped: generated)
│   │           │       ├── SleepPlan.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── SleepPlan.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── TimeEngine.d — D file [Dead] (skipped: generated)
│   │           │       ├── TimeEngine.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── TimeEngine.o — O file [Dead] (skipped: generated)
│   │           │       ├── TimeEngine.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── TimeEngine.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── TimeIntervalMath.d — D file [Dead] (skipped: generated)
│   │           │       ├── TimeIntervalMath.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── TimeIntervalMath.o — O file [Dead] (skipped: generated)
│   │           │       ├── TimeIntervalMath.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── TimeIntervalMath.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── UnifiedSleepSession.d — D file [Dead] (skipped: generated)
│   │           │       ├── UnifiedSleepSession.dia — DIA file [Dead] (skipped: generated)
│   │           │       ├── UnifiedSleepSession.o — O file [Dead] (skipped: generated)
│   │           │       ├── UnifiedSleepSession.swiftconstvalues — SWIFTCONSTVALUES file [Dead] (skipped: generated)
│   │           │       ├── UnifiedSleepSession.swiftdeps — SWIFTDEPS file [Dead] (skipped: generated)
│   │           │       ├── supplementaryOutputs-1 — File [Dead] (skipped: generated)
│   │           │       └── supplementaryOutputs-2 — File [Dead] (skipped: generated)
│   │           ├── DoseCore.DependencyMetadataFileList — DEPENDENCYMETADATAFILELIST file [Dead] (skipped: generated)
│   │           ├── DoseCore.DependencyStaticMetadataFileList — DEPENDENCYSTATICMETADATAFILELIST file [Dead] (skipped: generated)
│   │           └── DoseCore.modulemap — MODULEMAP file [Dead] (skipped: generated)
│   ├── GeneratedModuleMaps-iphoneos/ — Folder [Dead]
│   │   ├── DoseCore-Swift.h — H file [Dead] (skipped: generated)
│   │   └── DoseCore.modulemap — MODULEMAP file [Dead] (skipped: generated)
│   └── SwiftExplicitPrecompiledModules/ — Folder [Dead]
│       ├── M5IW76Z2T989/ — Folder [Dead]
│       │   ├── Accessibility-3023XW2GDFKZB.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── CFNetwork-2DJ4SFMT45RVS.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── CoreData-1B7AE6UNAASA3.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── CoreFoundation-1J0LT3LDE14Q8.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── CoreGraphics-28543OYJD5C1P.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── CoreImage-3NNIR13S2YEWV.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── CoreText-3GNIK615V1B3M.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── CoreTransferable-2APLEJH8EJY7U.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── CoreVideo-3CQEDIILRC21T.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── Darwin-G2Y11T43LRTH.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── DataDetection-2JMEZ07VPH6BE.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── DeveloperToolsSupport-16H87D9VYMG5.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── Dispatch-2KF172U2OZMDV.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── FileProvider-1W023U3WBIXHX.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── Foundation-3UW4O16M9QZ8Z.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── IOSurface-275M90XWUJP9N.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── ImageIO-1TSABV2ZWXUPO.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── LocalAuthentication-2JSYTCIHGK9OC.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── MachO-1MI62Y2X09P8X.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── Metal-1SO2RABYYA75K.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── OSLog-3VXWGBANPGOCD.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── ObjectiveC-2V6UCFNUDCE2F.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── OpenGLES-3BWLQQ0VGXP6.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── QuartzCore-2O4MHLM13Q5DI.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── Security-2U6Q4AU4HGEO6.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── Spatial-3LB0GU0MEUFFQ.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── SwiftShims-MES685MCQ1TG.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── SwiftUI-16WWMDBOV5PTR.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── SwiftUICore-AJPGNAQ5NHH0.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── Symbols-3OGOICZSJW4GL.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── UIKit-3Q08RQRGCOEV8.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── UIUtilities-2DTNKC9PEJHDN.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── UniformTypeIdentifiers-5JX310ZQEHL4.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── UserNotifications-3HOTM52AQ808M.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── XPC-3PCU4RRSYM5DC.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _AvailabilityInternal-2ZE9LA36FCKP4.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _Builtin_float-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _Builtin_intrinsics-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _Builtin_inttypes-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _Builtin_limits-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _Builtin_stdarg-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _Builtin_stdatomic-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _Builtin_stdbool-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _Builtin_stddef-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _Builtin_stdint-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _Builtin_tgmath-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _DarwinFoundation1-2ZE9LA36FCKP4.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _DarwinFoundation2-3PVF5Z1VXDKJP.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _DarwinFoundation3-27I8BW41VCGP9.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── _SwiftConcurrencyShims-MES685MCQ1TG.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── os-1GI5LJPABKRT6.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── os_object-1GI5LJPABKRT6.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── os_workgroup-1GI5LJPABKRT6.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── ptrauth-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── ptrcheck-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│       │   ├── simd-5NDC7H3PW2C0.pcm — PCM file [Dead] (skipped: generated)
│       │   └── sys_types-3PVF5Z1VXDKJP.pcm — PCM file [Dead] (skipped: generated)
│       ├── Accessibility-475SLZCG6IPF367J13WDMA07W.pcm — PCM file [Dead] (skipped: generated)
│       ├── CFNetwork-570EVYEBB67778EJ2IYDN7O78.pcm — PCM file [Dead] (skipped: generated)
│       ├── CoreData-5CO597LL7LWRCGDG1OIFBNVOQ.pcm — PCM file [Dead] (skipped: generated)
│       ├── CoreFoundation-9A18RD12DJ3VJUT06RVJUMVV4.pcm — PCM file [Dead] (skipped: generated)
│       ├── CoreGraphics-22PTOVPHMCWZA7YDGSDAGN0RE.pcm — PCM file [Dead] (skipped: generated)
│       ├── CoreImage-8LA2NR5OF4W11OEFRH7W5CWKY.pcm — PCM file [Dead] (skipped: generated)
│       ├── CoreText-A5M4CH4B94N618LMNE7F0DNXZ.pcm — PCM file [Dead] (skipped: generated)
│       ├── CoreTransferable-8R1FC4FY54579FQ8PAMGT3VKY.pcm — PCM file [Dead] (skipped: generated)
│       ├── CoreVideo-3HN6CO44NUVBA6WEYCM3V3EAF.pcm — PCM file [Dead] (skipped: generated)
│       ├── Darwin-E17YA9C37QSMM4BIIH08J50LG.pcm — PCM file [Dead] (skipped: generated)
│       ├── DataDetection-8BYIXUBFYCI605VA4JAPYYH26.pcm — PCM file [Dead] (skipped: generated)
│       ├── DeveloperToolsSupport-BC3G95A0XCUL13ZDJ0UL70NKA.pcm — PCM file [Dead] (skipped: generated)
│       ├── Dispatch-8M9NOYXIBR4MQZMX1351GGZXM.pcm — PCM file [Dead] (skipped: generated)
│       ├── FileProvider-8ZLSYD7CB0KT36QXXYJZGLSFY.pcm — PCM file [Dead] (skipped: generated)
│       ├── Foundation-3X3D5PLTJW1W5GKES8OUZF0Y4.pcm — PCM file [Dead] (skipped: generated)
│       ├── IOSurface-BJ29WB8HKLBPBVY7JXYGYBWD0.pcm — PCM file [Dead] (skipped: generated)
│       ├── ImageIO-F4DJB3ZUEUS4FVYIEXPYAON8B.pcm — PCM file [Dead] (skipped: generated)
│       ├── LocalAuthentication-6WPP3C2ZYMG276C69JHUKOWW1.pcm — PCM file [Dead] (skipped: generated)
│       ├── MachO-10T21WC0SZXNN45IAIRN1RSCY.pcm — PCM file [Dead] (skipped: generated)
│       ├── Metal-3FELY0021Z79NW4YJ0XZ621RW.pcm — PCM file [Dead] (skipped: generated)
│       ├── OSLog-IB55QX6VDILUKG1WU74TGE32.pcm — PCM file [Dead] (skipped: generated)
│       ├── ObjectiveC-EB8M02V0A4P0AOCAV3ASYMGX4.pcm — PCM file [Dead] (skipped: generated)
│       ├── OpenGLES-DKHV6SZVVMP1JSPUCVMUCRFME.pcm — PCM file [Dead] (skipped: generated)
│       ├── QuartzCore-CWMY5TZQHGD0ZA6IAS6LQPWSI.pcm — PCM file [Dead] (skipped: generated)
│       ├── Security-70TIHPODCR1P2KZ4C8OPXC28I.pcm — PCM file [Dead] (skipped: generated)
│       ├── Spatial-7RCUOEKRMPGNOWLM07I9YSK8H.pcm — PCM file [Dead] (skipped: generated)
│       ├── SwiftShims-7UA574LR16EYC2XEADST2NKAO.pcm — PCM file [Dead] (skipped: generated)
│       ├── SwiftUI-ANNJJ3BJMBKRVT9SDYGG8C4LS.pcm — PCM file [Dead] (skipped: generated)
│       ├── SwiftUICore-93IO33ZF5KNZYTZWH67P2J3IP.pcm — PCM file [Dead] (skipped: generated)
│       ├── Symbols-2X47SM3FPV7OS2647W4Z0ROUB.pcm — PCM file [Dead] (skipped: generated)
│       ├── UIKit-3EUBJ3P6SW9UE6S4W8KMAV1NO.pcm — PCM file [Dead] (skipped: generated)
│       ├── UIUtilities-26JICLI4I898N7ZMRVW64B7RO.pcm — PCM file [Dead] (skipped: generated)
│       ├── UniformTypeIdentifiers-BEQ460IEYIIN016FIDCJ2IC3D.pcm — PCM file [Dead] (skipped: generated)
│       ├── UserNotifications-B6FH88YHTHIVSL1RD4TAVGE6F.pcm — PCM file [Dead] (skipped: generated)
│       ├── XPC-3LZQ2T6HLWHT3DXCBD48IVVFY.pcm — PCM file [Dead] (skipped: generated)
│       ├── _AvailabilityInternal-9PU2QREWS05EMO1HSKI4ZK535.pcm — PCM file [Dead] (skipped: generated)
│       ├── _Builtin_float-CZGQTOHEEAQJH35N5HABMQ1MH.pcm — PCM file [Dead] (skipped: generated)
│       ├── _Builtin_intrinsics-BBXTDOTK65C6SR1YLV6ZRNSD9.pcm — PCM file [Dead] (skipped: generated)
│       ├── _Builtin_inttypes-63YIAXY4K7LHE2U8BPZ25LTOE.pcm — PCM file [Dead] (skipped: generated)
│       ├── _Builtin_limits-E5IHA8GYTKN75SWKMB3PYD3TG.pcm — PCM file [Dead] (skipped: generated)
│       ├── _Builtin_stdarg-7AZ92VSOHTMDBGD8NP49KOVIQ.pcm — PCM file [Dead] (skipped: generated)
│       ├── _Builtin_stdatomic-BQS1VN5ZGNV3SSE2F0XCF639D.pcm — PCM file [Dead] (skipped: generated)
│       ├── _Builtin_stdbool-90JMTPIGDNGCL00DX0X3E86ZI.pcm — PCM file [Dead] (skipped: generated)
│       ├── _Builtin_stddef-AUPMPW7O95M17OSAI3JJ01INR.pcm — PCM file [Dead] (skipped: generated)
│       ├── _Builtin_stdint-EZM7I5N8V26KFQ06DBWHINNMS.pcm — PCM file [Dead] (skipped: generated)
│       ├── _Builtin_tgmath-1JEUSH2OH0D2RFC8P5GWOYRFS.pcm — PCM file [Dead] (skipped: generated)
│       ├── _DarwinFoundation1-ED5B1H5VUEZZPQKPA3T2888YU.pcm — PCM file [Dead] (skipped: generated)
│       ├── _DarwinFoundation2-DRJJHX3GE63EWQ4W6CPHMJ6E3.pcm — PCM file [Dead] (skipped: generated)
│       ├── _DarwinFoundation3-9BYFAWBQG53WEL5PT9XXI9NPF.pcm — PCM file [Dead] (skipped: generated)
│       ├── _SwiftConcurrencyShims-EY0EBI5Y0Z23JBJW98GU11UWS.pcm — PCM file [Dead] (skipped: generated)
│       ├── modules.timestamp — TIMESTAMP file [Dead] (skipped: generated)
│       ├── os-94URTVEABOWGPBRZY81XZZ8WB.pcm — PCM file [Dead] (skipped: generated)
│       ├── os_object-368U25HB1177ZA1DPKRVAZGDV.pcm — PCM file [Dead] (skipped: generated)
│       ├── os_workgroup-4TJOP6FPRVFHQQGU4U0FZMJ1P.pcm — PCM file [Dead] (skipped: generated)
│       ├── ptrauth-B436LZ98DNXKF5UC07IC838NR.pcm — PCM file [Dead] (skipped: generated)
│       ├── ptrcheck-6AOSC1BI3T611UK7UPSGN330A.pcm — PCM file [Dead] (skipped: generated)
│       ├── simd-8S37UJZVK9G5RLJQ11ND6WY2P.pcm — PCM file [Dead] (skipped: generated)
│       └── sys_types-3YBNZA2DM1N3HHR0HMB4PVGZ2.pcm — PCM file [Dead] (skipped: generated)
├── docs/ — Documentation and SSOT references. [Spec-only]
│   ├── SSOT/ — Folder [Spec-only]
│   │   ├── contracts/ — Folder [Spec-only]
│   │   │   └── DataDictionary.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── README.md — Project document [Spec-only] (reviewed: deep)
│   │   ├── constants.json — JSON data/spec [Spec-only] (reviewed: deep)
│   │   └── navigation.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── archive/ — Folder [Spec-only]
│   │   ├── audit_sessions_2025-12/ — Folder [Spec-only]
│   │   │   ├── AUDIT_LOG_2025-12-24_session4.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── AUDIT_LOG_2025-12-24_session5.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── CODE_AUDIT_2025-12-24.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── CODE_AUDIT_LOG_2025-12-24.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── CODE_REVIEW_2025-12-24_session2.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── FIX_PLAN_2025-12-24_session4.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── FIX_PLAN_2025-12-24_session5.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── GAP_CLOSURE_LOG_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── GAP_CLOSURE_REPORT_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── HYPERCRITICAL_AUDIT_2025-12.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── INDEPENDENT_CODE_REVIEW_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── INDEPENDENT_CODE_REVIEW_LOG_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── POST_GAP_AUDIT_LOG_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── POST_GAP_AUDIT_REPORT_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── PRESLEEP_BUGFIX_LOG_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── PRESLEEP_BUGFIX_REPORT_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── ROLLOVER_FIX_LOG_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── ROLLOVER_FIX_LOG_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── ROLLOVER_FIX_REPORT_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── ROLLOVER_FIX_REPORT_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── TEST_READINESS_REPORT_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── TEST_REASSESSMENT_LOG_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   └── TEST_REASSESSMENT_REPORT_2025-12-25.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── audits_2025-12/ — Folder [Spec-only]
│   │   │   ├── ADVERSARIAL_AUDIT_REPORT_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── COMPREHENSIVE_AUDIT_REPORT_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── DOCS_CONSISTENCY_REPORT_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── STORAGE_ENFORCEMENT_REPORT_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   └── STORAGE_UNIFICATION_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── audits_2026-01/ — Folder [Spec-only]
│   │   │   ├── 2026-01-14_ADVERSARIAL_AUDIT_REPORT_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_RED_TEAM_AUDIT_2026-01-02.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_SECURITY_REMEDIATION_2026-01-02.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── NIGHT_MODE_IMPLEMENTATION_2026-01-03.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── RED_TEAM_AUDIT_2026-01-02.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   └── SECURITY_REMEDIATION_2026-01-02.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── contracts/ — Folder [Spec-only]
│   │   │   ├── 2026-01-14_ascii/ — Folder [Spec-only]
│   │   │   │   ├── EnhancedComponents.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   │   └── SetupWizard.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_diagrams/ — Folder [Spec-only]
│   │   │   │   └── state_tonight.mmd — MMD file [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_schemas/ — Folder [Spec-only]
│   │   │   │   └── core.json — JSON data/spec [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_Inventory.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_MedicationLogger.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_PreSleepLog.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_ProductGuarantees.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_SchemaEvolution.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_SetupWizard.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_SupportBundle.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   └── 2026-01-14_api.openapi.yaml — YAML config [Spec-only] (reviewed: shallow)
│   │   ├── design/ — Folder [Spec-only]
│   │   │   ├── 2026-01-14_APP_ICON_FIX_FINAL.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_APP_ICON_RESOLUTION.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_APP_ICON_TROUBLESHOOTING.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_NIGHT_MODE.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   └── 2026-01-14_NIGHT_MODE_IMPLEMENTATION_2026-01-03.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── planning/ — Folder [Spec-only]
│   │   │   ├── 2026-01-14_APP_SETTINGS_CONFIGURATION.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_FEATURE_ROADMAP.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_PENDING_ITEMS.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_PRD.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_PRODUCT_DESCRIPTION.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_SLEEP_PLANNER_SPEC.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_TESTING_GUIDE_FIXES.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_TODO.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_USE_CASES.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_accessibility-implementation.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── 2026-01-14_user-guide.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── FUTURE_ROADMAP.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── IMPLEMENTATION_PLAN.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   ├── PROD_READINESS_TODO.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   │   └── use_case.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── ASCII_UI_DESIGNS.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── DOCS_CONSISTENCY_REPORT_2025-12-26.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   └── codebase.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── icon/ — Folder [Spec-only]
│   │   └── dosetap-liquid-glass-window/ — Folder [Spec-only]
│   │       ├── dosetap-liquid-glass-window/ — Folder [Spec-only]
│   │       │   ├── dosetap-liquid-glass-window-bg.svg — SVG file [Spec-only] (reviewed: shallow)
│   │       │   ├── dosetap-liquid-glass-window-fg1.svg — SVG file [Spec-only] (reviewed: shallow)
│   │       │   ├── dosetap-liquid-glass-window-fg2.svg — SVG file [Spec-only] (reviewed: shallow)
│   │       │   └── dosetap-liquid-glass-window-notes.md — Markdown document [Spec-only] (reviewed: shallow)
│   │       ├── dosetap-liquid-glass-window-bg.svg — SVG file [Spec-only] (reviewed: shallow)
│   │       ├── dosetap-liquid-glass-window-fg1.svg — SVG file [Spec-only] (reviewed: shallow)
│   │       ├── dosetap-liquid-glass-window-fg2.svg — SVG file [Spec-only] (reviewed: shallow)
│   │       └── dosetap-liquid-glass-window-notes.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── DATABASE_SCHEMA.md — Markdown document [Spec-only] (reviewed: deep)
│   ├── DIAGNOSTIC_LOGGING.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── DIAGNOSTIC_SESSION_ROLLOVER.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── FEATURE_THEME_TOGGLE.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── FEATURE_TRIAGE.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── HOW_TO_READ_A_SESSION_TRACE.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── PLAN_DOCS_AND_SSOT_REFRESH.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── PLAN_DOSE_AND_ROLLOVER_FIX.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── README.md — Project document [Spec-only] (reviewed: shallow)
│   ├── RELEASE_CHECKLIST.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── TESTFLIGHT_GUIDE.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── TESTING_GUIDE.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── THEME_TOGGLE_BUILD_FIX.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── architecture.md — Markdown document [Spec-only] (reviewed: shallow)
│   └── privacy-policy.html — HTML file [Spec-only] (reviewed: shallow)
├── ios/ — iOS app source, storage, and UI. [Active]
│   ├── Core/ — Folder [Active]
│   │   ├── APIClient.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── APIClientQueueIntegration.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── APIErrors.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── CSVExporter.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── CertificatePinning.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── DataRedactor.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── DiagnosticEvent.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── DiagnosticLogger.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── DoseTapCore.swift — Swift source [Active] (reviewed: deep)
│   │   ├── DoseUndoManager.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── DoseWindowState.swift — Swift source [Active] (reviewed: deep)
│   │   ├── EventRateLimiter.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── EventStore.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── MedicationConfig.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── MorningCheckIn.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── OfflineQueue.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── RecommendationEngine.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── SessionKey.swift — Swift source [Active] (reviewed: deep)
│   │   ├── SleepEvent.swift — Swift source [Active] (reviewed: deep)
│   │   ├── SleepPlan.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── TimeEngine.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── TimeIntervalMath.swift — Swift source [Active] (reviewed: deep)
│   │   └── UnifiedSleepSession.swift — Swift source [Active] (reviewed: shallow)
│   ├── DoseTap/ — Folder [Active]
│   │   ├── Assets.xcassets/ — Folder [Active]
│   │   │   ├── AccentColor.colorset/ — Folder [Active]
│   │   │   │   └── Contents.json — JSON data/spec [Active] (reviewed: shallow)
│   │   │   └── AppIcon.appiconset/ — Folder [Active]
│   │   │       ├── Contents.json — JSON data/spec [Active] (reviewed: shallow)
│   │   │       ├── icon-1024.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-20@1x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-20@2x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-20@3x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-29@1x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-29@2x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-29@3x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-40@1x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-40@2x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-40@3x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-60@2x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-60@3x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-76@1x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       ├── icon-76@2x.png — PNG file [Active] (skipped: binary/asset)
│   │   │       └── icon-83.5@2x.png — PNG file [Active] (skipped: binary/asset)
│   │   ├── DoseTap.xcdatamodeld/ — Folder [Active]
│   │   │   └── DoseTap.xcdatamodel/ — Folder [Active]
│   │   │       └── contents — File [Active] (reviewed: shallow)
│   │   ├── Export/ — Folder [Active]
│   │   │   └── CSVExporter.swift — Swift source [Active] (reviewed: deep)
│   │   ├── Foundation/ — Folder [Active]
│   │   │   ├── DevelopmentHelper.swift — Swift source [Active] (reviewed: shallow)
│   │   │   └── TimeZoneMonitor.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── FullApp/ — Folder [Duplicate]
│   │   │   ├── DashboardView.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── DataExportService.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── DataStorageService.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── DoseCoreIntegration.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── DoseModels.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── EnhancedNotificationService.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── HealthIntegrationService.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── HealthKitManager.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── InventoryService.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── KeychainHelper.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── QuickLogPanel.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── SQLiteStorage.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── SetupWizardService.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── SetupWizardView.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── TimelineView.swift — Swift source [Duplicate] (reviewed: deep)
│   │   │   ├── TonightView.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   ├── UIUtils.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   └── UserConfigurationManager.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   ├── Persistence/ — Folder [Duplicate]
│   │   │   ├── FetchHelpers.swift — Swift source [Duplicate] (reviewed: shallow)
│   │   │   └── PersistentStore.swift — Swift source [Duplicate] (reviewed: deep)
│   │   ├── Security/ — Folder [Active]
│   │   │   ├── DatabaseSecurity.swift — Swift source [Active] (reviewed: deep)
│   │   │   ├── InputValidator.swift — Swift source [Active] (reviewed: deep)
│   │   │   └── SecureLogger.swift — Swift source [Active] (reviewed: deep)
│   │   ├── Services/ — Folder [Active]
│   │   │   └── HealthKitProviding.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── Storage/ — Folder [Active]
│   │   │   ├── EncryptedEventStorage.swift — Swift source [Active] (reviewed: deep)
│   │   │   ├── EventStorage.swift — Swift source [Active] (reviewed: deep)
│   │   │   ├── JSONMigrator.swift — Swift source [Active] (reviewed: deep)
│   │   │   └── SessionRepository.swift — Swift source [Active] (reviewed: deep)
│   │   ├── Theme/ — Folder [Active]
│   │   │   └── AppTheme.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── Views/ — Folder [Active]
│   │   │   ├── DiagnosticExportView.swift — Swift source [Active] (reviewed: shallow)
│   │   │   ├── EditDoseTimeView.swift — Swift source [Active] (reviewed: shallow)
│   │   │   ├── MedicationPickerView.swift — Swift source [Active] (reviewed: shallow)
│   │   │   ├── MedicationSettingsView.swift — Swift source [Active] (reviewed: shallow)
│   │   │   ├── MorningCheckInView.swift — Swift source [Active] (reviewed: shallow)
│   │   │   ├── MorningCheckInViewV2.swift — Swift source [Active] (reviewed: shallow)
│   │   │   ├── NightReviewView.swift — Swift source [Active] (reviewed: deep)
│   │   │   ├── PainTrackingUI.swift — Swift source [Active] (reviewed: shallow)
│   │   │   ├── PreSleepLogView.swift — Swift source [Active] (reviewed: shallow)
│   │   │   ├── PreSleepLogViewV2.swift — Swift source [Active] (reviewed: shallow)
│   │   │   ├── ThemeSettingsView.swift — Swift source [Active] (reviewed: shallow)
│   │   │   └── UndoSnackbarView.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── legacy/ — Folder [Legacy]
│   │   │   ├── ActionableNotifications.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── ContentView_Clean.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── ContentView_Enhanced.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── DashboardConfig.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── EnhancedSettings.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── ErrorDisplayView.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── ErrorHandler.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── EventLogger.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── EventStoreAdapter.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── EventStoreWithSync.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── ExportView.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── Health.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── HistoryView.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── InventoryManagement.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── Models_Event.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── NightAnalyzer.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── ReminderScheduler.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── SetupWizardEnhanced.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── SnoozeController.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── Storage_Store.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── SupportBundleExport.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── TimeZoneUI.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── UndoSnackbar.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── UnifiedModels.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   ├── UnifiedStore.swift — Swift source [Legacy] (reviewed: shallow)
│   │   │   └── WHOOP.swift — Swift source [Legacy] (reviewed: shallow)
│   │   ├── AlarmService.swift — Swift source [Active] (reviewed: deep)
│   │   ├── AnalyticsService.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── Config-Development.plist — Property list [Active] (reviewed: shallow)
│   │   ├── ContentView.swift — Swift source [Active] (reviewed: deep)
│   │   ├── DiagnosticLoggingSettingsView.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── DoseTap.entitlements — Entitlements [Active] (reviewed: shallow)
│   │   ├── DoseTapApp.swift — Swift source [Active] (reviewed: deep)
│   │   ├── EnhancedSettings.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── FlicButtonService.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── HealthKitService.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── HighContrastColors.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── Info.plist — Property list [Active] (reviewed: shallow)
│   │   ├── InsightsCalculator.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── Package.swift — SwiftPM manifest [Active] (reviewed: shallow)
│   │   ├── ReducedMotionSupport.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── Secrets.template.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── SecureConfig.swift — Swift source [Active] (reviewed: deep)
│   │   ├── SettingsView.swift — Swift source [Active] (reviewed: deep)
│   │   ├── SleepPlanDetailView.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── SleepStageTimeline.swift — Swift source [Active] (reviewed: deep)
│   │   ├── SleepTimelineOverlays.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── SupportBundleExport.swift — Swift source [Active] (reviewed: deep)
│   │   ├── TimeIntervalMath.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── URLRouter.swift — Swift source [Active] (reviewed: deep)
│   │   ├── UndoStateManager.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── UserSettingsManager.swift — Swift source [Active] (reviewed: deep)
│   │   ├── WHOOP.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── WHOOPDataFetching.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── WHOOPService.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── WHOOPSettingsView.swift — Swift source [Active] (reviewed: shallow)
│   │   ├── WeeklyPlanner.swift — Swift source [Active] (reviewed: shallow)
│   │   └── demo_data.json — JSON data/spec [Active] (reviewed: shallow)
│   ├── DoseTap.xcodeproj/ — Folder [Active]
│   │   ├── project.xcworkspace/ — Folder [Active]
│   │   │   └── contents.xcworkspacedata — XCWORKSPACEDATA file [Active] (reviewed: shallow)
│   │   ├── xcshareddata/ — Folder [Active]
│   │   │   └── xcschemes/ — Folder [Active]
│   │   │       └── DoseTap.xcscheme — XCSCHEME file [Active] (reviewed: shallow)
│   │   ├── project.pbxproj — Xcode project file [Active] (reviewed: shallow)
│   │   ├── project.pbxproj.backup — BACKUP file [Active] (reviewed: shallow)
│   │   └── project.pbxproj.backup3 — BACKUP3 file [Active] (reviewed: shallow)
│   ├── DoseTap.xcworkspace/ — Folder [Active]
│   │   └── contents.xcworkspacedata — XCWORKSPACEDATA file [Active] (reviewed: shallow)
│   ├── DoseTapNative/ — Folder [Active]
│   │   └── Package.swift — SwiftPM manifest [Active] (reviewed: shallow)
│   ├── DoseTapTests/ — Folder [Active]
│   │   ├── DoseTapTests.swift — Swift source [Active] (reviewed: shallow)
│   │   └── SessionRepositoryTests.swift — Swift source [Active] (reviewed: shallow)
│   ├── build/ — Folder [Dead]
│   │   ├── DoseTap.build/ — Folder [Dead]
│   │   │   └── Debug-iphoneos/ — Folder [Dead]
│   │   │       ├── DoseTap-56ea82861c86e08488026e452d0cb254-VFS-iphoneos/ — Folder [Dead]
│   │   │       │   └── all-product-headers.yaml — YAML config [Dead] (skipped: generated)
│   │   │       └── DoseTap.build/ — Folder [Dead]
│   │   │           ├── DerivedSources/ — Folder [Dead]
│   │   │           │   ├── GeneratedAssetSymbols-Index.plist — Property list [Dead] (skipped: generated)
│   │   │           │   ├── GeneratedAssetSymbols.h — H file [Dead] (skipped: generated)
│   │   │           │   └── GeneratedAssetSymbols.swift — Swift source [Dead] (skipped: generated)
│   │   │           ├── Objects-normal/ — Folder [Dead]
│   │   │           │   └── arm64/ — Folder [Dead]
│   │   │           │       ├── DoseTap-OutputFileMap.json — JSON data/spec [Dead] (skipped: generated)
│   │   │           │       ├── DoseTap-dependencies-1.json — JSON data/spec [Dead] (skipped: generated)
│   │   │           │       ├── DoseTap-primary.priors — PRIORS file [Dead] (skipped: generated)
│   │   │           │       ├── DoseTap.LinkFileList — LINKFILELIST file [Dead] (skipped: generated)
│   │   │           │       ├── DoseTap.SwiftConstValuesFileList — SWIFTCONSTVALUESFILELIST file [Dead] (skipped: generated)
│   │   │           │       ├── DoseTap.SwiftFileList — SWIFTFILELIST file [Dead] (skipped: generated)
│   │   │           │       ├── DoseTap_const_extract_protocols.json — JSON data/spec [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-1 — File [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-10 — File [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-11 — File [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-12 — File [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-2 — File [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-3 — File [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-4 — File [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-5 — File [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-6 — File [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-7 — File [Dead] (skipped: generated)
│   │   │           │       ├── supplementaryOutputs-8 — File [Dead] (skipped: generated)
│   │   │           │       └── supplementaryOutputs-9 — File [Dead] (skipped: generated)
│   │   │           ├── assetcatalog_output/ — Folder [Dead]
│   │   │           │   └── thinned/ — Folder [Dead]
│   │   │           │       ├── AppIcon60x60@2x.png — PNG file [Dead] (skipped: generated)
│   │   │           │       ├── AppIcon76x76@2x~ipad.png — PNG file [Dead] (skipped: generated)
│   │   │           │       └── Assets.car — CAR file [Dead] (skipped: generated)
│   │   │           ├── DoseTap-all-non-framework-target-headers.hmap — HMAP file [Dead] (skipped: generated)
│   │   │           ├── DoseTap-all-target-headers.hmap — HMAP file [Dead] (skipped: generated)
│   │   │           ├── DoseTap-generated-files.hmap — HMAP file [Dead] (skipped: generated)
│   │   │           ├── DoseTap-own-target-headers.hmap — HMAP file [Dead] (skipped: generated)
│   │   │           ├── DoseTap-project-headers.hmap — HMAP file [Dead] (skipped: generated)
│   │   │           ├── DoseTap.DependencyMetadataFileList — DEPENDENCYMETADATAFILELIST file [Dead] (skipped: generated)
│   │   │           ├── DoseTap.DependencyStaticMetadataFileList — DEPENDENCYSTATICMETADATAFILELIST file [Dead] (skipped: generated)
│   │   │           ├── DoseTap.hmap — HMAP file [Dead] (skipped: generated)
│   │   │           ├── assetcatalog_dependencies_thinned — File [Dead] (skipped: generated)
│   │   │           ├── assetcatalog_generated_info.plist_thinned — PLIST_THINNED file [Dead] (skipped: generated)
│   │   │           └── assetcatalog_signature — File [Dead] (skipped: generated)
│   │   ├── SwiftExplicitPrecompiledModules/ — Folder [Dead]
│   │   │   ├── 35CS5UZ5UOX22/ — Folder [Dead]
│   │   │   │   ├── AVFAudio-RAJTYIFKI1RB.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── AVFoundation-13QDT18M1Q4LG.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── AVRouting-2HTBDVNXNHFMS.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── Accessibility-3023XW2GDFKZB.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── AudioToolbox-1IV80OLC5MJXE.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── AuthenticationServices-1DT4NL8DSG38V.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CFNetwork-2DJ4SFMT45RVS.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreAudio-1U3HRX3H2X0QE.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreAudioTypes-23K22HSB4ZP2O.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreData-1B7AE6UNAASA3.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreFoundation-1J0LT3LDE14Q8.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreGraphics-28543OYJD5C1P.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreImage-3NNIR13S2YEWV.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreLocation-9P4JBK975Y8X.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreMIDI-2J2ERNQPDSNOD.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreMedia-2WVHD60J4JU30.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreText-3GNIK615V1B3M.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreTransferable-2APLEJH8EJY7U.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── CoreVideo-3CQEDIILRC21T.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── Darwin-G2Y11T43LRTH.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── DataDetection-2JMEZ07VPH6BE.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── DeveloperToolsSupport-16H87D9VYMG5.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── Dispatch-2KF172U2OZMDV.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── FileProvider-1W023U3WBIXHX.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── Foundation-3UW4O16M9QZ8Z.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── HealthKit-1WSBU7EENK4BL.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── IOSurface-275M90XWUJP9N.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── ImageIO-1TSABV2ZWXUPO.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── LocalAuthentication-2JSYTCIHGK9OC.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── MachO-1MI62Y2X09P8X.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── MediaToolbox-11ZIJAEM5ZUW4.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── Metal-1SO2RABYYA75K.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── Network-3R52MCF34G9YN.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── OSLog-3VXWGBANPGOCD.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── ObjectiveC-2V6UCFNUDCE2F.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── OpenGLES-3BWLQQ0VGXP6.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── QuartzCore-2O4MHLM13Q5DI.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── SQLite3-2SSW2ZSHLDULT.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── Security-2U6Q4AU4HGEO6.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── Spatial-3LB0GU0MEUFFQ.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── SwiftShims-MES685MCQ1TG.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── SwiftUI-16WWMDBOV5PTR.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── SwiftUICore-AJPGNAQ5NHH0.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── Symbols-3OGOICZSJW4GL.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── UIKit-3Q08RQRGCOEV8.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── UIUtilities-2DTNKC9PEJHDN.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── UniformTypeIdentifiers-5JX310ZQEHL4.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── UserNotifications-3HOTM52AQ808M.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── XPC-3PCU4RRSYM5DC.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _AvailabilityInternal-2ZE9LA36FCKP4.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _Builtin_float-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _Builtin_intrinsics-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _Builtin_inttypes-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _Builtin_limits-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _Builtin_stdarg-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _Builtin_stdatomic-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _Builtin_stdbool-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _Builtin_stddef-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _Builtin_stdint-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _Builtin_tgmath-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _DarwinFoundation1-2ZE9LA36FCKP4.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _DarwinFoundation2-3PVF5Z1VXDKJP.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _DarwinFoundation3-27I8BW41VCGP9.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _LocationEssentials-2IXXJTMAR5DRT.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── _SwiftConcurrencyShims-MES685MCQ1TG.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── dnssd-18TJHV2NGM89U.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── os-1GI5LJPABKRT6.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── os_object-1GI5LJPABKRT6.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── os_workgroup-1GI5LJPABKRT6.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── ptrauth-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── ptrcheck-2C6A0UR9YBOSY.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   ├── simd-5NDC7H3PW2C0.pcm — PCM file [Dead] (skipped: generated)
│   │   │   │   └── sys_types-3PVF5Z1VXDKJP.pcm — PCM file [Dead] (skipped: generated)
│   │   │   └── modules.timestamp — TIMESTAMP file [Dead] (skipped: generated)
│   │   └── XCBuildData/ — Folder [Dead]
│   │       ├── 4afdebd3fadc596deeee45096ba59ba0.xcbuilddata/ — Folder [Dead]
│   │       │   ├── attachments/ — Folder [Dead]
│   │       │   │   ├── 33db26df277b8ff7d62c31d0b99e90ae — File [Dead] (skipped: generated)
│   │       │   │   ├── 344f1dafdf1a6b324a3f211b56ac5205 — File [Dead] (skipped: generated)
│   │       │   │   ├── 50aec717dd0364b43a8983c2ef60a7dd — File [Dead] (skipped: generated)
│   │       │   │   ├── 676aa844356cc1552fde17160b1c92ab — File [Dead] (skipped: generated)
│   │       │   │   ├── 79632875ea28995e7db9b28f44d910a2 — File [Dead] (skipped: generated)
│   │       │   │   ├── 7b9a18d4d2e5c046b779850ea738fba9 — File [Dead] (skipped: generated)
│   │       │   │   ├── 8179f49763c39c1369bd6be2fd93a7ae — File [Dead] (skipped: generated)
│   │       │   │   ├── 83a976b937c4c9552696eeb18a76ec2c — File [Dead] (skipped: generated)
│   │       │   │   ├── 8bba4233626f64a7ea772bb94a08a1a9 — File [Dead] (skipped: generated)
│   │       │   │   ├── 9b50331a187e5d9107286f0ff8622919 — File [Dead] (skipped: generated)
│   │       │   │   ├── a12a9b837fca324fa3d6ceb4ba30a45b — File [Dead] (skipped: generated)
│   │       │   │   ├── a8837f06a943a4dcbf0c27d851e8b1b6 — File [Dead] (skipped: generated)
│   │       │   │   ├── d3034434a773062dd02f37ddc70c49f3 — File [Dead] (skipped: generated)
│   │       │   │   ├── d41d8cd98f00b204e9800998ecf8427e — File [Dead] (skipped: generated)
│   │       │   │   ├── fd8314defc70a8778956f026c0ddfd19 — File [Dead] (skipped: generated)
│   │       │   │   └── feedf7e445a6d5a53dce4fe46f8c9b78 — File [Dead] (skipped: generated)
│   │       │   ├── build-request.json — JSON data/spec [Dead] (skipped: generated)
│   │       │   ├── description.msgpack — MSGPACK file [Dead] (skipped: generated)
│   │       │   ├── manifest.json — JSON data/spec [Dead] (skipped: generated)
│   │       │   ├── target-graph.txt — Text file [Dead] (skipped: generated)
│   │       │   └── task-store.msgpack — MSGPACK file [Dead] (skipped: generated)
│   │       ├── 7e688fec5046abf2f47d5ea56490cfe9.xcbuilddata/ — Folder [Dead]
│   │       │   ├── attachments/ — Folder [Dead]
│   │       │   │   ├── 33db26df277b8ff7d62c31d0b99e90ae — File [Dead] (skipped: generated)
│   │       │   │   ├── 344f1dafdf1a6b324a3f211b56ac5205 — File [Dead] (skipped: generated)
│   │       │   │   ├── 50aec717dd0364b43a8983c2ef60a7dd — File [Dead] (skipped: generated)
│   │       │   │   ├── 676aa844356cc1552fde17160b1c92ab — File [Dead] (skipped: generated)
│   │       │   │   ├── 79632875ea28995e7db9b28f44d910a2 — File [Dead] (skipped: generated)
│   │       │   │   ├── 7b9a18d4d2e5c046b779850ea738fba9 — File [Dead] (skipped: generated)
│   │       │   │   ├── 8179f49763c39c1369bd6be2fd93a7ae — File [Dead] (skipped: generated)
│   │       │   │   ├── 83a976b937c4c9552696eeb18a76ec2c — File [Dead] (skipped: generated)
│   │       │   │   ├── 8bba4233626f64a7ea772bb94a08a1a9 — File [Dead] (skipped: generated)
│   │       │   │   ├── 9b50331a187e5d9107286f0ff8622919 — File [Dead] (skipped: generated)
│   │       │   │   ├── a12a9b837fca324fa3d6ceb4ba30a45b — File [Dead] (skipped: generated)
│   │       │   │   ├── a8837f06a943a4dcbf0c27d851e8b1b6 — File [Dead] (skipped: generated)
│   │       │   │   ├── d3034434a773062dd02f37ddc70c49f3 — File [Dead] (skipped: generated)
│   │       │   │   ├── d41d8cd98f00b204e9800998ecf8427e — File [Dead] (skipped: generated)
│   │       │   │   ├── fd8314defc70a8778956f026c0ddfd19 — File [Dead] (skipped: generated)
│   │       │   │   └── feedf7e445a6d5a53dce4fe46f8c9b78 — File [Dead] (skipped: generated)
│   │       │   ├── build-request.json — JSON data/spec [Dead] (skipped: generated)
│   │       │   ├── description.msgpack — MSGPACK file [Dead] (skipped: generated)
│   │       │   ├── manifest.json — JSON data/spec [Dead] (skipped: generated)
│   │       │   ├── target-graph.txt — Text file [Dead] (skipped: generated)
│   │       │   └── task-store.msgpack — MSGPACK file [Dead] (skipped: generated)
│   │       ├── b8018b018a0da35ff01b94470bd69b6c.xcbuilddata/ — Folder [Dead]
│   │       │   ├── attachments/ — Folder [Dead]
│   │       │   │   ├── 33db26df277b8ff7d62c31d0b99e90ae — File [Dead] (skipped: generated)
│   │       │   │   ├── 344f1dafdf1a6b324a3f211b56ac5205 — File [Dead] (skipped: generated)
│   │       │   │   ├── 50aec717dd0364b43a8983c2ef60a7dd — File [Dead] (skipped: generated)
│   │       │   │   ├── 676aa844356cc1552fde17160b1c92ab — File [Dead] (skipped: generated)
│   │       │   │   ├── 79632875ea28995e7db9b28f44d910a2 — File [Dead] (skipped: generated)
│   │       │   │   ├── 7b9a18d4d2e5c046b779850ea738fba9 — File [Dead] (skipped: generated)
│   │       │   │   ├── 8179f49763c39c1369bd6be2fd93a7ae — File [Dead] (skipped: generated)
│   │       │   │   ├── 83a976b937c4c9552696eeb18a76ec2c — File [Dead] (skipped: generated)
│   │       │   │   ├── 8bba4233626f64a7ea772bb94a08a1a9 — File [Dead] (skipped: generated)
│   │       │   │   ├── 9b50331a187e5d9107286f0ff8622919 — File [Dead] (skipped: generated)
│   │       │   │   ├── a12a9b837fca324fa3d6ceb4ba30a45b — File [Dead] (skipped: generated)
│   │       │   │   ├── a8837f06a943a4dcbf0c27d851e8b1b6 — File [Dead] (skipped: generated)
│   │       │   │   ├── d3034434a773062dd02f37ddc70c49f3 — File [Dead] (skipped: generated)
│   │       │   │   ├── d41d8cd98f00b204e9800998ecf8427e — File [Dead] (skipped: generated)
│   │       │   │   ├── fd8314defc70a8778956f026c0ddfd19 — File [Dead] (skipped: generated)
│   │       │   │   └── feedf7e445a6d5a53dce4fe46f8c9b78 — File [Dead] (skipped: generated)
│   │       │   ├── build-request.json — JSON data/spec [Dead] (skipped: generated)
│   │       │   ├── description.msgpack — MSGPACK file [Dead] (skipped: generated)
│   │       │   ├── manifest.json — JSON data/spec [Dead] (skipped: generated)
│   │       │   ├── target-graph.txt — Text file [Dead] (skipped: generated)
│   │       │   └── task-store.msgpack — MSGPACK file [Dead] (skipped: generated)
│   │       └── build.db — DB file [Dead] (skipped: generated)
│   ├── TestBuild.swift — Swift source [Active] (reviewed: shallow)
│   ├── add_assets_catalog.py — Python script [Active] (reviewed: shallow)
│   ├── add_eventstore.py — Python script [Active] (reviewed: shallow)
│   ├── add_files_to_xcode.sh — Shell script [Active] (reviewed: shallow)
│   ├── add_missing_files.py — Python script [Active] (reviewed: shallow)
│   ├── add_new_settings_files.py — Python script [Active] (reviewed: shallow)
│   ├── add_pr1_files.py — Python script [Active] (reviewed: shallow)
│   ├── add_presleeplog.py — Python script [Active] (reviewed: shallow)
│   ├── add_swift_files.py — Python script [Active] (reviewed: shallow)
│   ├── clean_project.py — Python script [Active] (reviewed: shallow)
│   ├── dedupe_sources.py — Python script [Active] (reviewed: shallow)
│   ├── fix_all_missing_files.py — Python script [Active] (reviewed: shallow)
│   ├── fix_project.py — Python script [Active] (reviewed: shallow)
│   ├── fix_project_files.py — Python script [Active] (reviewed: shallow)
│   ├── fix_storage_scope.py — Python script [Active] (reviewed: shallow)
│   ├── rebuild_project.py — Python script [Active] (reviewed: shallow)
│   └── remove_duplicates.py — Python script [Active] (reviewed: shallow)
├── macos/ — macOS app target source. [Active]
│   └── DoseTapStudio/ — Folder [Active]
│       ├── Sources/ — Folder [Active]
│       │   ├── App/ — Folder [Active]
│       │   │   └── DoseTapStudioApp.swift — Swift source [Active] (reviewed: shallow)
│       │   ├── Import/ — Folder [Active]
│       │   │   ├── FolderMonitor.swift — Swift source [Active] (reviewed: shallow)
│       │   │   └── Importer.swift — Swift source [Active] (reviewed: shallow)
│       │   ├── Models/ — Folder [Active]
│       │   │   ├── DoseTapAnalytics.swift — Swift source [Active] (reviewed: shallow)
│       │   │   └── Models.swift — Swift source [Active] (reviewed: shallow)
│       │   ├── Store/ — Folder [Active]
│       │   │   └── DataStore.swift — Swift source [Active] (reviewed: shallow)
│       │   └── Views/ — Folder [Active]
│       │       ├── ContentView.swift — Swift source [Active] (reviewed: shallow)
│       │       ├── DashboardView.swift — Swift source [Active] (reviewed: shallow)
│       │       ├── EnhancedInventoryView.swift — Swift source [Active] (reviewed: shallow)
│       │       ├── NotificationBanners.swift — Swift source [Active] (reviewed: shallow)
│       │       ├── PlaceholderViews.swift — Swift source [Active] (reviewed: shallow)
│       │       ├── RefillManagementSheets.swift — Swift source [Active] (reviewed: shallow)
│       │       ├── SetupWizardView.swift — Swift source [Active] (reviewed: shallow)
│       │       ├── SidebarView.swift — Swift source [Active] (reviewed: shallow)
│       │       ├── SupportViews.swift — Swift source [Active] (reviewed: shallow)
│       │       ├── TimeZoneViews.swift — Swift source [Active] (reviewed: shallow)
│       │       └── WelcomeView.swift — Swift source [Active] (reviewed: shallow)
│       ├── Tests/ — Folder [Active]
│       │   └── ImporterTests.swift — Swift source [Active] (reviewed: shallow)
│       └── Package.swift — SwiftPM manifest [Active] (reviewed: shallow)
├── shadcn-ui/ — Design system assets and experiments. [Spec-only]
│   ├── src/ — Folder [Spec-only]
│   │   └── index.ts — TS file [Spec-only] (reviewed: shallow)
│   ├── README.md — Project document [Spec-only] (reviewed: shallow)
│   ├── package-lock.json — JSON data/spec [Spec-only] (reviewed: shallow)
│   ├── package.json — JSON data/spec [Spec-only] (reviewed: shallow)
│   └── tsconfig.json — JSON data/spec [Spec-only] (reviewed: shallow)
├── specs/ — Product/technical specs (non-code). [Spec-only]
│   ├── 001-speckit-repo-review/ — Folder [Spec-only]
│   │   ├── analysis-report.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── plan.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── spec.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   └── tasks.md — Markdown document [Spec-only] (reviewed: shallow)
│   ├── 002-cloudkit-sync/ — Folder [Spec-only]
│   │   ├── analysis-report.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── plan.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   ├── spec.md — Markdown document [Spec-only] (reviewed: shallow)
│   │   └── tasks.md — Markdown document [Spec-only] (reviewed: shallow)
│   └── 003-manual-dose-entry/ — Folder [Spec-only]
│       ├── plan.md — Markdown document [Spec-only] (reviewed: shallow)
│       ├── spec.md — Markdown document [Spec-only] (reviewed: shallow)
│       └── tasks.md — Markdown document [Spec-only] (reviewed: shallow)
├── tools/ — Developer tooling/scripts. [Active]
│   ├── sidecar-ledger/ — Folder [Active]
│   │   ├── docs/ — Folder [Active]
│   │   │   └── PIPELINE_SSOT.md — Markdown document [Active] (reviewed: shallow)
│   │   ├── ledger/ — Folder [Active]
│   │   │   └── manifest_schema.sql — SQL file [Active] (reviewed: shallow)
│   │   ├── scripts/ — Folder [Active]
│   │   │   └── folder_structure.sh — Shell script [Active] (reviewed: shallow)
│   │   ├── sidecar_ledger/ — Folder [Active]
│   │   │   ├── __pycache__/ — Folder [Active]
│   │   │   │   ├── __init__.cpython-314.pyc — PYC file [Active] (skipped: binary/asset)
│   │   │   │   ├── __main__.cpython-314.pyc — PYC file [Active] (skipped: binary/asset)
│   │   │   │   └── cli.cpython-314.pyc — PYC file [Active] (skipped: binary/asset)
│   │   │   ├── commands/ — Folder [Active]
│   │   │   │   ├── __pycache__/ — Folder [Active]
│   │   │   │   │   ├── ingest.cpython-314.pyc — PYC file [Active] (skipped: binary/asset)
│   │   │   │   │   └── init.cpython-314.pyc — PYC file [Active] (skipped: binary/asset)
│   │   │   │   ├── ingest.py — Python script [Active] (reviewed: shallow)
│   │   │   │   └── init.py — Python script [Active] (reviewed: shallow)
│   │   │   ├── core/ — Folder [Active]
│   │   │   │   ├── __pycache__/ — Folder [Active]
│   │   │   │   │   ├── hashing.cpython-314.pyc — PYC file [Active] (skipped: binary/asset)
│   │   │   │   │   ├── ledger.cpython-314.pyc — PYC file [Active] (skipped: binary/asset)
│   │   │   │   │   ├── paths.cpython-314.pyc — PYC file [Active] (skipped: binary/asset)
│   │   │   │   │   └── util.cpython-314.pyc — PYC file [Active] (skipped: binary/asset)
│   │   │   │   ├── hashing.py — Python script [Active] (reviewed: shallow)
│   │   │   │   ├── ledger.py — Python script [Active] (reviewed: shallow)
│   │   │   │   ├── paths.py — Python script [Active] (reviewed: shallow)
│   │   │   │   └── util.py — Python script [Active] (reviewed: shallow)
│   │   │   ├── __init__.py — Python script [Active] (reviewed: shallow)
│   │   │   ├── __main__.py — Python script [Active] (reviewed: shallow)
│   │   │   └── cli.py — Python script [Active] (reviewed: shallow)
│   │   ├── tests/ — Folder [Active]
│   │   │   ├── __pycache__/ — Folder [Active]
│   │   │   │   └── test_init_and_ingest.cpython-314-pytest-9.0.2.pyc — PYC file [Active] (skipped: binary/asset)
│   │   │   └── test_init_and_ingest.py — Python script [Active] (reviewed: shallow)
│   │   ├── README.md — Project document [Active] (reviewed: shallow)
│   │   ├── TODO.md — Markdown document [Active] (reviewed: shallow)
│   │   └── pyproject.toml — TOML file [Active] (reviewed: shallow)
│   ├── doc_lint.sh — Shell script [Active] (reviewed: shallow)
│   ├── doc_lint_strict.py — Python script [Active] (reviewed: shallow)
│   ├── generate_cert_pins.sh — Shell script [Active] (reviewed: shallow)
│   ├── generate_icons.sh — Shell script [Active] (reviewed: shallow)
│   ├── install_to_device.sh — Shell script [Active] (reviewed: shallow)
│   ├── regenerate_app_icons.sh — Shell script [Active] (reviewed: shallow)
│   ├── regenerate_app_icons_macos.sh — Shell script [Active] (reviewed: shallow)
│   └── ssot_check.sh — Shell script [Active] (reviewed: shallow)
├── watchos/ — watchOS app target source. [Active]
│   └── DoseTapWatch/ — Folder [Active]
│       ├── Assets.xcassets/ — Folder [Active]
│       │   └── AppIcon.appiconset/ — Folder [Active]
│       │       ├── Contents.json — JSON data/spec [Active] (reviewed: shallow)
│       │       ├── watch-1024.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-108@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-117@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-129@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-24@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-27.5@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-29@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-29@3x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-33@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-40@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-44@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-46@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-50@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-51@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-54@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       ├── watch-86@2x.png — PNG file [Active] (skipped: binary/asset)
│       │       └── watch-98@2x.png — PNG file [Active] (skipped: binary/asset)
│       ├── ContentView.swift — Swift source [Active] (reviewed: shallow)
│       └── DoseTapWatchApp.swift — Swift source [Active] (reviewed: shallow)
├── AUDIT_LOG.md — Project document [Active] (reviewed: shallow)
├── CHANGELOG.md — Project document [Active] (reviewed: shallow)
├── PRIVACY_POLICY.md — Project document [Active] (reviewed: shallow)
├── Package.swift — SwiftPM manifest [Active] (reviewed: deep)
└── README.md — Project document [Active] (reviewed: shallow)
## Issues

## [CRITICAL] Timeline vs History mismatch (dose events + wake_final)

**Evidence**: `ios/DoseTap/SleepStageTimeline.swift:583-590`, `ios/DoseTap/Storage/EventStorage.swift:906-935`, `ios/DoseTap/Storage/SessionRepository.swift:854-868`

**Root Cause**: Timeline reads `dose_events` using `dose1_taken/dose2_taken/wake_final`, but persistence writes `dose1/dose2` into `dose_events` and writes `wake_final` to `sleep_events`. The timeline never sees the persisted values.

**Reproduction**:
1. HYPOTHESIS: Take Dose 1 and Dose 2 from Tonight tab.
2. HYPOTHESIS: Tap Wake Up & End Session.
3. Expected: Timeline summary shows both doses and wake time.
4. Actual: Timeline summary missing dose/wake (History shows them).

**Fix**:
- File: `ios/DoseTap/SleepStageTimeline.swift`
- Lines: 583-590
- Change: Query `dose1`/`dose2` from `dose_events`, and load `wake_final` from `sleep_events` (or unify event types in storage to match timeline expectations).

**Tests to Add**:
- `test_timeline_summary_reads_dose1_dose2_from_dose_events()` in `Tests/DoseCoreTests/TimeCorrectnessTests.swift`
- `test_timeline_reads_wake_final_from_sleep_events()` in `Tests/DoseCoreTests/TimeCorrectnessTests.swift`

**Acceptance Criteria**:
- [ ] Timeline summary shows Dose 1, Dose 2, and Wake Final for a session with logged events.
- [ ] History and Timeline show the same timestamps for the same session.

## [CRITICAL] Event type normalization mismatch (QuickLog/URLRouter/InputValidator/Timeline)

**Evidence**: `ios/DoseTap/UserSettingsManager.swift:142-175`, `ios/DoseTap/ContentView.swift:42-66`, `ios/DoseTap/Security/InputValidator.swift:22-35`, `ios/DoseTap/URLRouter.swift:276-303`, `ios/DoseTap/FullApp/TimelineView.swift:750-782`, `ios/Core/SleepEvent.swift:5-18`

**Root Cause**: There is no canonical event naming scheme. QuickLog stores Title Case display strings, InputValidator expects camel/snake variants, URLRouter maps to different lowercase strings, and Timeline mapping expects camelCase. Storage persists raw strings without normalization.

**Reproduction**:
1. HYPOTHESIS: Log “Lights Out” from QuickLog.
2. HYPOTHESIS: View History and Timeline.
3. Expected: Consistent label/icon/color across views.
4. Actual: Inconsistent display names or missing mappings; deep links may be rejected.

**Fix**:
- File: `ios/DoseTap/ContentView.swift`
- Lines: 42-66
- Change: Normalize `eventType` to canonical snake_case before persistence; store display name separately if needed.
- File: `ios/DoseTap/UserSettingsManager.swift`
- Lines: 142-175
- Change: Use `id` (canonical) for persistence and `name` for display.
- File: `ios/DoseTap/URLRouter.swift`
- Lines: 276-303
- Change: Map to canonical event type strings; deprecate aliases.

**Tests to Add**:
- `test_event_normalization_maps_display_names_to_wire_format()` in `Tests/DoseCoreTests/SleepEventTests.swift`

**Acceptance Criteria**:
- [ ] All event writes store canonical snake_case values.
- [ ] All UI display names are derived from canonical values.

## [CRITICAL] Dose actions write into `sleep_events` (duplicate persistence)

**Evidence**: `ios/DoseTap/ContentView.swift:1481-1550`, `ios/DoseTap/ContentView.swift:42-66`, `ios/DoseTap/Storage/SessionRepository.swift:531-601`

**Root Cause**: Dose buttons call `eventLogger.logEvent(...)`, which persists to `sleep_events` while dose actions already write to `dose_events` via `SessionRepository`.

**Reproduction**:
1. HYPOTHESIS: Take Dose 1 and Dose 2.
2. HYPOTHESIS: Inspect exported CSV or DB.
3. Expected: Dose events only in `dose_events` table.
4. Actual: Duplicate dose entries in `sleep_events`.

**Fix**:
- File: `ios/DoseTap/ContentView.swift`
- Lines: 1481-1550
- Change: Remove dose logging through EventLogger; add a Details view section that reads from `dose_events`.

**Tests to Add**:
- `test_dose_buttons_do_not_write_sleep_events()` in `Tests/DoseCoreTests/SSOTComplianceTests.swift`

**Acceptance Criteria**:
- [ ] Dose actions only write to `dose_events` and `current_session`.
- [ ] `sleep_events` contains only sleep-related events.

## [CRITICAL] `session_id` split-brain (UUID spec violated)

**Evidence**: `ios/DoseTap/Storage/EventStorage.swift:628-629`, `ios/DoseTap/Storage/EventStorage.swift:382-413`, `ios/DoseTap/Storage/SessionRepository.swift:410-417`, SSOT `docs/SSOT/README.md:27-29`

**Root Cause**: Storage uses `session_date` as a fallback for `session_id` and backfills missing `session_id` with `session_date`, violating SSOT UUID identity.

**Reproduction**:
1. HYPOTHESIS: Log events without session_id.
2. HYPOTHESIS: Inspect `session_id` in DB.
3. Expected: UUID `session_id` for all session-scoped rows.
4. Actual: `session_id` equals `session_date`.

**Fix**:
- File: `ios/DoseTap/Storage/SessionRepository.swift`
- Lines: 410-417
- Change: Always generate a UUID for a new session and persist it in `current_session`/`sleep_sessions`.
- File: `ios/DoseTap/Storage/EventStorage.swift`
- Lines: 382-413, 628-629
- Change: Remove `sessionId ?? sessionDate` fallback; backfill using `sleep_sessions.session_id`.

**Tests to Add**:
- `test_session_id_is_uuid_for_all_tables()` in `Tests/DoseCoreTests/SessionIdBackfillTests.swift`

**Acceptance Criteria**:
- [ ] All rows with `session_id` use UUID values.
- [ ] Backfill migration leaves no `session_id == session_date` rows.

## [MAJOR] CSV export failures are silent + synchronous on UI thread

**Evidence**: `ios/DoseTap/SettingsView.swift:561-577`, `ios/DoseTap/Storage/EventStorage.swift:2568-2655`

**Root Cause**: Export is synchronous and errors are only printed; UI shows no failure when write fails. Large exports run on the main thread.

**Reproduction**:
1. HYPOTHESIS: Attempt export with low disk space or large dataset.
2. Expected: User-facing error with remediation.
3. Actual: No UI error; export appears to do nothing.

**Fix**:
- File: `ios/DoseTap/SettingsView.swift`
- Lines: 561-577
- Change: Wrap export in background Task, surface errors to an alert, show progress.

**Tests to Add**:
- `test_export_failure_shows_error_alert()` in `ios/DoseTapTests/SettingsViewTests.swift`

**Acceptance Criteria**:
- [ ] Export failures surface a user-visible error message.
- [ ] Export runs off the main thread and remains responsive.

## [MAJOR] Snooze rules inconsistent with SSOT (near-close + count)

**Evidence**: `ios/DoseTap/ContentView.swift:1603-1605`, `ios/Core/DoseWindowState.swift:102-106`, `ios/DoseTap/AlarmService.swift:209-217`, `ios/DoseTap/URLRouter.swift:190-196`

**Root Cause**: UI enables snooze in `.nearClose`, but AlarmService rejects near-close snoozes; URLRouter increments snooze even when AlarmService refuses.

**Reproduction**:
1. HYPOTHESIS: Trigger snooze within 15 minutes of window close.
2. Expected: Snooze disabled and count unchanged.
3. Actual: Snooze count increments despite no alarm reschedule.

**Fix**:
- File: `ios/DoseTap/ContentView.swift`
- Lines: 1603-1605, 3392-3394
- Change: Drive snooze enablement from `DoseWindowCalculator` state.
- File: `ios/DoseTap/URLRouter.swift`
- Lines: 190-196
- Change: Only increment snooze if AlarmService succeeds.

**Tests to Add**:
- `test_snooze_disallowed_near_close_does_not_increment()` in `Tests/DoseCoreTests/DoseWindowEdgeTests.swift`

**Acceptance Criteria**:
- [ ] Snooze cannot be triggered when <15 minutes remain.
- [ ] Snooze count matches actual scheduled snoozes.

## [MAJOR] Time edits do not update `session_date/session_id`

**Evidence**: `ios/DoseTap/Storage/EventStorage.swift:1038-1103`, `ios/DoseTap/ContentView.swift:2723-2758`

**Root Cause**: Editing a timestamp updates only `timestamp` fields; session key and `session_id` are not recomputed. Cross-boundary edits orphan events in the wrong session.

**Reproduction**:
1. HYPOTHESIS: Edit Dose 1 time to cross 6 PM boundary.
2. Expected: Event moves to correct session with updated `session_date` and `session_id`.
3. Actual: Event remains in original session.

**Fix**:
- File: `ios/DoseTap/Storage/EventStorage.swift`
- Lines: 1038-1103
- Change: Recompute `session_date` and `session_id` on edits; move row if changed.

**Tests to Add**:
- `test_edit_dose_time_rekeys_session()` in `Tests/DoseCoreTests/TimeCorrectnessTests.swift`

**Acceptance Criteria**:
- [ ] Editing times across boundaries reassigns events to the correct session.

## [MAJOR] Foreign keys not defined despite PRAGMA enabling

**Evidence**: `ios/DoseTap/Storage/EventStorage.swift:63-68`, `ios/DoseTap/Storage/EventStorage.swift:84-187`

**Root Cause**: `PRAGMA foreign_keys = ON` is set, but no FK constraints are defined in DDL. Orphaned rows are possible for session-scoped data.

**Reproduction**:
1. HYPOTHESIS: Delete a session from `sleep_sessions`.
2. Expected: Cascade deletes for events.
3. Actual: Orphaned `sleep_events/dose_events` rows remain.

**Fix**:
- File: `ios/DoseTap/Storage/EventStorage.swift`
- Lines: 84-187
- Change: Add FK constraints for `session_id` to `sleep_sessions(session_id)` with ON DELETE CASCADE.

**Tests to Add**:
- `test_session_delete_cascades_events()` in `Tests/DoseCoreTests/CRUDActionTests.swift`

**Acceptance Criteria**:
- [ ] Deleting a session removes dependent events.

## [MAJOR] SQLite access on MainActor causes UI stalls

**Evidence**: `ios/DoseTap/Storage/EventStorage.swift:13-14`, `ios/DoseTap/Storage/EventStorage.swift:2568-2655`, `ios/DoseTap/SettingsView.swift:561-577`

**Root Cause**: EventStorage is `@MainActor` and performs heavy SQL and CSV generation on the main thread.

**Reproduction**:
1. HYPOTHESIS: Export CSV with 10K+ events while scrolling UI.
2. Expected: UI remains responsive.
3. Actual: UI hangs during export.

**Fix**:
- File: `ios/DoseTap/Storage/EventStorage.swift`
- Lines: 13-14
- Change: Move DB access to a dedicated background actor/queue; expose async APIs.

**Tests to Add**:
- `test_export_runs_off_main_thread()` in `ios/DoseTapTests/ExportTests.swift`

**Acceptance Criteria**:
- [ ] Long-running DB operations do not block UI.

## [MAJOR] Split persistence layers (CoreData vs SQLite)

**Evidence**: `ios/DoseTap/Persistence/PersistentStore.swift:6-35`, `ios/DoseTap/Export/CSVExporter.swift:7-27`, `ios/DoseTap/Storage/JSONMigrator.swift:31-68`, `ios/DoseTap/Storage/EventStorage.swift:12-49`

**Root Cause**: CoreData-based exporters and migrators coexist with SQLite SSOT. This risks export/migration reading from a different store than runtime data.

**Reproduction**:
1. HYPOTHESIS: Use CSVExporter-based export in a build that includes it.
2. Expected: Export reflects SQLite data.
3. Actual: Export may be empty or inconsistent.

**Fix**:
- File: `ios/DoseTap/Export/CSVExporter.swift`
- Lines: 7-27
- Change: Remove CoreData export or re-implement using EventStorage.

**Tests to Add**:
- `test_csv_export_uses_event_storage()` in `Tests/DoseCoreTests/CSVExporterTests.swift`

**Acceptance Criteria**:
- [ ] Only one persistence layer is used in production paths.

## [MAJOR] Encryption-at-rest not wired (HYPOTHESIS)

**Evidence**: `ios/DoseTap/Security/DatabaseSecurity.swift:15-119`, `ios/DoseTap/Storage/EncryptedEventStorage.swift:15-129`

**Root Cause**: Encryption primitives exist but are not invoked in EventStorage initialization. No call sites found in app paths (HYPOTHESIS; confirm via `rg -n DatabaseSecurity`).

**Reproduction**:
1. HYPOTHESIS: Inspect DB file on device.
2. Expected: Encrypted SQLite content.
3. Actual: Plaintext SQLite DB.

**Fix**:
- File: `ios/DoseTap/Storage/EventStorage.swift`
- Lines: 41-49
- Change: Integrate SQLCipher setup and use DatabaseSecurity key.

**Tests to Add**:
- `test_database_encryption_enabled_when_key_present()` in `ios/DoseTapTests/SecurityTests.swift`

**Acceptance Criteria**:
- [ ] Database is encrypted at rest when SQLCipher is available.

## [MAJOR] Privacy manifest missing (HYPOTHESIS)

**Evidence**: `rg --files -g '*xcprivacy*'` returned no files (see `AUDIT_LOG.md`).

**Root Cause**: Privacy manifest file not present in repo.

**Reproduction**:
1. HYPOTHESIS: Build app for iOS 17+.
2. Expected: Privacy manifest included.
3. Actual: App has no PrivacyInfo.xcprivacy.

**Fix**:
- File: `ios/DoseTap/PrivacyInfo.xcprivacy` (new)
- Change: Add required privacy manifest entries for system APIs.

**Tests to Add**:
- `test_privacy_manifest_in_bundle()` in `ios/DoseTapTests/ComplianceTests.swift`

**Acceptance Criteria**:
- [ ] App bundle contains PrivacyInfo.xcprivacy with declared API usage.

## [MINOR] `session_closed` event type is not in validation/display mappings

**Evidence**: `ios/DoseTap/Views/MorningCheckInViewV2.swift:185-213`, `ios/DoseTap/Security/InputValidator.swift:22-35`, `ios/DoseTap/ContentView.swift:110-138`

**Root Cause**: Internal diagnostic event is stored as a sleep event but not whitelisted or mapped for display.

**Reproduction**:
1. HYPOTHESIS: Complete Morning Check-In V2.
2. Expected: Event either hidden or displayed consistently.
3. Actual: Event may appear as raw string or be rejected in deep link validation.

**Fix**:
- File: `ios/DoseTap/Views/MorningCheckInViewV2.swift`
- Lines: 185-213
- Change: Store system events in a diagnostics table or extend mappings/filters.

**Tests to Add**:
- `test_system_events_are_filtered_from_sleep_events_ui()` in `ios/DoseTapTests/HistoryTests.swift`

**Acceptance Criteria**:
- [ ] `session_closed` does not pollute user-facing sleep event lists.

## [MINOR] Duplicate ActivityViewController definitions (HYPOTHESIS)

**Evidence**: `ios/DoseTap/Views/NightReviewView.swift:676-688`, `ios/DoseTap/SupportBundleExport.swift:445-460`

**Root Cause**: Two top-level structs with the same name in the same module can cause compile-time conflicts (HYPOTHESIS; SwiftPM build doesn’t compile iOS target).

**Reproduction**:
1. HYPOTHESIS: Build iOS app target.
2. Expected: No duplicate symbol errors.
3. Actual: Duplicate type definition error if both files are in target.

**Fix**:
- File: `ios/DoseTap/Views/NightReviewView.swift`
- Lines: 676-688
- Change: Rename or centralize ActivityViewController in a shared utility file.

**Tests to Add**:
- `test_activity_view_controller_single_definition()` in `ios/DoseTapTests/BuildSanityTests.swift`

**Acceptance Criteria**:
- [ ] iOS app target compiles without duplicate type errors.

## [MINOR] TimeIntervalMath warning indicates negative intervals

**Evidence**: `test.log:615`, `ios/Core/TimeIntervalMath.swift:13-25`

**Root Cause**: Negative intervals are allowed and returned as negative minutes after logging a warning; tests trigger this path.

**Reproduction**:
1. HYPOTHESIS: Run TimeCorrectness tests.
2. Expected: No negative interval warnings.
3. Actual: Warning printed for negative delta.

**Fix**:
- File: `ios/Core/TimeIntervalMath.swift`
- Lines: 13-25
- Change: Decide on strict enforcement or clamp; update tests to avoid invalid inputs.

**Tests to Add**:
- `test_negative_interval_handling_is_consistent()` in `Tests/DoseCoreTests/TimeCorrectnessTests.swift`

**Acceptance Criteria**:
- [ ] Negative intervals are handled deterministically and tests reflect policy.

## Page-by-Page UI Audit

### ContentView (Tab Root)
- **File location**: `ios/DoseTap/ContentView.swift:239-299`
- **Data inputs**: `DoseTapCore`, `UserSettingsManager`, `EventLogger`, `SessionRepository`, `URLRouter` via `@StateObject/@ObservedObject`. Evidence: `ios/DoseTap/ContentView.swift:241-248`
- **Data outputs**: Wires `DoseTapCore` to `SessionRepository`, sets URLRouter dependencies. Evidence: `ios/DoseTap/ContentView.swift:288-296`
- **State management**: `@StateObject` for core/settings/eventLogger/sessionRepo/undoState/themeManager.
- **Lifecycle triggers**: `.onAppear` sets dependencies. Evidence: `ios/DoseTap/ContentView.swift:288-299`
- **Refresh triggers**: `SessionRepository.sessionDidChange` observed by EventLogger. Evidence: `ios/DoseTap/ContentView.swift:21-25`
- **Caching**: EventLogger caches `events` in memory.
- **Failure modes**: Deep links before `core`/`eventLogger` are set show “App not ready”. Evidence: `ios/DoseTap/URLRouter.swift:246-249`.
- **Fix plan**: Ensure URLRouter dependencies are injected earlier or guard with a ready state.

### LegacyTonightView (Tonight tab)
- **File location**: `ios/DoseTap/ContentView.swift:380-520`
- **Data inputs**: `DoseTapCore`, `EventLogger`, `SessionRepository`, `SleepPlanStore`. Evidence: `ios/DoseTap/ContentView.swift:381-388`
- **Data outputs**: Writes overrides to SleepPlanStore. Evidence: `ios/DoseTap/ContentView.swift:452-460`
- **State management**: Multiple `@State` fields for override, check-in, pre-sleep log.
- **Lifecycle triggers**: `.onAppear`, `.onChange`, `.onReceive` for session updates. Evidence: `ios/DoseTap/ContentView.swift:663-674`
- **Refresh triggers**: `sessionRepo.sessionDidChange` used to reload pre-sleep log. Evidence: `ios/DoseTap/ContentView.swift:673-675`
- **Caching**: Pre-sleep log cached in state.
- **Failure modes**: Pre-sleep log may stale if `sessionDidChange` not fired for some insert paths.
- **Fix plan**: Ensure all inserts that affect pre-sleep logs emit `sessionDidChange`.

### DetailsView (Timeline tab)
- **File location**: `ios/DoseTap/ContentView.swift:2316-2429`
- **Data inputs**: `DoseTapCore`, `EventLogger`, `UserSettingsManager`. Evidence: `ios/DoseTap/ContentView.swift:2317-2319`
- **Data outputs**: Logs events via `FullEventLogGrid` and `EventLogger`. Evidence: `ios/DoseTap/ContentView.swift:3029-3063`
- **Lifecycle triggers**: Uses `NavigationView` with static content; no explicit refresh beyond EventLogger.
- **Failure modes**: EventLogger uses display names, causing type mismatch with History/Timeline.
- **Fix plan**: Canonicalize event types and map to display names in UI.

### HistoryView
- **File location**: `ios/DoseTap/ContentView.swift:2439-2800`
- **Data inputs**: `SessionRepository` for dose logs/events. Evidence: `ios/DoseTap/ContentView.swift:2447-2449`, `ios/DoseTap/ContentView.swift:2780-2785`
- **Data outputs**: Deletes sessions, edits dose/event times. Evidence: `ios/DoseTap/ContentView.swift:2502-2506`, `ios/DoseTap/ContentView.swift:2787-2799`
- **Lifecycle triggers**: `onAppear`, `onChange` for date/refresh. Evidence: `ios/DoseTap/ContentView.swift:2486-2490`, `ios/DoseTap/ContentView.swift:2719-2721`
- **Failure modes**: Edits don’t re-key sessions; event types displayed as raw strings.
- **Fix plan**: Re-key on edit; map display names from canonical event types.

### SettingsView
- **File location**: `ios/DoseTap/SettingsView.swift:240-392`, `ios/DoseTap/SettingsView.swift:561-577`
- **Data inputs**: `UserSettingsManager` and `URLRouter`. Evidence: `ios/DoseTap/SettingsView.swift:306-369`
- **Data outputs**: Export CSV, clear data, change settings. Evidence: `ios/DoseTap/SettingsView.swift:274-298`, `ios/DoseTap/SettingsView.swift:561-577`
- **Failure modes**: Export errors are silent.
- **Fix plan**: Add error alerts and async export.

### HealthKitSettingsView
- **File location**: `ios/DoseTap/SettingsView.swift:611-620`
- **Inputs**: `HealthKitService.shared`, settings. Evidence: `ios/DoseTap/SettingsView.swift:611-614`
- **Outputs**: Toggles `settings.healthKitEnabled`.
- **Failure modes**: Authorization and preference can diverge (SSOT warns). Evidence: `docs/SSOT/README.md:99-103`.
- **Fix plan**: Add explicit “authorization required” state and prompt.

### MorningCheckInView
- **File location**: `ios/DoseTap/Views/MorningCheckInView.swift:218-408`
- **Data inputs**: `sessionId`, `sessionDate` in view model. Evidence: `ios/DoseTap/Views/MorningCheckInView.swift:219-227`
- **Data outputs**: Saves check-in + pain snapshot. Evidence: `ios/DoseTap/Views/MorningCheckInView.swift:406-449`
- **Failure modes**: Writes to `EventStorage` directly for pain snapshots, bypassing sessionDidChange.
- **Fix plan**: Route all storage writes through SessionRepository or add change notifications.

### MorningCheckInViewV2
- **File location**: `ios/DoseTap/Views/MorningCheckInViewV2.swift:17-213`
- **Data inputs**: `sessionId`, `sessionDate`, `SessionRepository`. Evidence: `ios/DoseTap/Views/MorningCheckInViewV2.swift:30-34`
- **Data outputs**: Saves wake survey, pain snapshot, inserts `session_closed`. Evidence: `ios/DoseTap/Views/MorningCheckInViewV2.swift:162-213`
- **Failure modes**: Inserts non-SSOT event type; duplicate write path.
- **Fix plan**: Move diagnostics to separate storage or whitelist event type.

### PreSleepLogView
- **File location**: `ios/DoseTap/Views/PreSleepLogView.swift:180-233`
- **Data inputs**: `SessionRepository.shared`, `SleepPlanStore.shared`. Evidence: `ios/DoseTap/Views/PreSleepLogView.swift:219-233`
- **Data outputs**: Saves pain snapshots via EventStorage. Evidence: `ios/DoseTap/Views/PreSleepLogView.swift:185-207`
- **Failure modes**: Pain snapshots bypass `sessionDidChange`.
- **Fix plan**: Route through SessionRepository or add observer hooks.

### PreSleepLogViewV2
- **File location**: `ios/DoseTap/Views/PreSleepLogViewV2.swift:205-222`
- **Data outputs**: Saves pain snapshot via EventStorage. Evidence: `ios/DoseTap/Views/PreSleepLogViewV2.swift:209-221`
- **Fix plan**: Same as PreSleepLogView.

### MedicationPickerView
- **File location**: `ios/DoseTap/Views/MedicationPickerView.swift:22-388`
- **Data inputs**: `SessionRepository.shared`. Evidence: `ios/DoseTap/Views/MedicationPickerView.swift:25-26`
- **Data outputs**: `logMedicationEntry` writes to DB. Evidence: `ios/DoseTap/Views/MedicationPickerView.swift:369-375`
- **Failure modes**: Duplicate guard only checks 5-minute window, no UI error on DB failure.
- **Fix plan**: surface errors and enforce session_id validity.

### MedicationSettingsView
- **File location**: `ios/DoseTap/Views/MedicationSettingsView.swift:12-116`
- **Data inputs**: `UserSettingsManager.shared`. Evidence: `ios/DoseTap/Views/MedicationSettingsView.swift:12-15`
- **Data outputs**: UserDefaults-backed settings updates.
- **Fix plan**: None (settings-only).

### ThemeSettingsView
- **File location**: `ios/DoseTap/Views/ThemeSettingsView.swift:4-26`
- **Data inputs**: `ThemeManager.shared`. Evidence: `ios/DoseTap/Views/ThemeSettingsView.swift:4-15`
- **Outputs**: Theme application (in-memory + UserDefaults). Evidence: `ios/DoseTap/Views/ThemeSettingsView.swift:11-15`

### DiagnosticExportView
- **File location**: `ios/DoseTap/Views/DiagnosticExportView.swift:16-154`
- **Data inputs**: `DiagnosticLogger.shared`. Evidence: `ios/DoseTap/Views/DiagnosticExportView.swift:122-151`
- **Data outputs**: Export zip and share sheet. Evidence: `ios/DoseTap/Views/DiagnosticExportView.swift:134-151`

### NightReviewView
- **File location**: `ios/DoseTap/Views/NightReviewView.swift:640-672`
- **Data outputs**: Generates share content (TODO). Evidence: `ios/DoseTap/Views/NightReviewView.swift:670-672`
- **Failure modes**: TODO export content not implemented.

### SleepStageTimeline
- **File location**: `ios/DoseTap/SleepStageTimeline.swift:540-631`
- **Data inputs**: `SessionRepository.fetchDoseEvents` + `fetchSleepEvents`. Evidence: `ios/DoseTap/SleepStageTimeline.swift:583-631`
- **Failure modes**: Event type mismatch (see Issue 1).

### SleepPlanDetailView
- **File location**: `ios/DoseTap/SleepPlanDetailView.swift:4-34`
- **Data outputs**: `SleepPlanStore.updateEntry`. Evidence: `ios/DoseTap/SleepPlanDetailView.swift:12-17`

### WHOOPSettingsView
- **File location**: `ios/DoseTap/WHOOPSettingsView.swift:4-128`
- **Data inputs**: `WHOOPService.shared`. Evidence: `ios/DoseTap/WHOOPSettingsView.swift:4-12`
- **Data outputs**: `whoop.disconnect()` and sync calls. Evidence: `ios/DoseTap/WHOOPSettingsView.swift:115-117`

### DiagnosticLoggingSettingsView
- **File location**: `ios/DoseTap/DiagnosticLoggingSettingsView.swift:5-90`
- **Data outputs**: Updates DiagnosticLogger settings. Evidence: `ios/DoseTap/DiagnosticLoggingSettingsView.swift:14-21`

### EditDoseTimeView / EditEventTimeView (Modal)
- **File location**: `ios/DoseTap/Views/EditDoseTimeView.swift:3-129`
- **Data outputs**: Calls `onSave` callbacks that write via SessionRepository. Evidence: `ios/DoseTap/Views/EditDoseTimeView.swift:118-126`, `ios/DoseTap/ContentView.swift:2787-2799`

### FullApp Views (Duplicate UI)
- **File location**: `ios/DoseTap/FullApp/TimelineView.swift:635-703`, `ios/DoseTap/FullApp/DashboardView.swift`, `ios/DoseTap/FullApp/TonightView.swift`, `ios/DoseTap/FullApp/SetupWizardView.swift`
- **Status**: Duplicate/alternate UI not used by `ContentView` (Active tab uses `DetailsView`, not `FullApp/TimelineView`). Evidence: `ios/DoseTap/ContentView.swift:252-259`
- **Fix plan**: Remove or gate behind feature flag to avoid split-brain UI.

## Data Flow Tracing

| Flow | UI | Validation | Persistence | Query | Display |
|---|---|---|---|---|---|
| lightsOut | `ios/DoseTap/ContentView.swift:3029-3063` | `ios/DoseTap/UserSettingsManager.swift:258-276` | `ios/DoseTap/ContentView.swift:42-66` → `ios/DoseTap/Storage/SessionRepository.swift:1589-1601` → `ios/DoseTap/Storage/EventStorage.swift:711-729` | `ios/DoseTap/ContentView.swift:2780-2785` | `ios/DoseTap/ContentView.swift:2380-2393`, `ios/DoseTap/ContentView.swift:2664-2678` |
| Dose 1 | `ios/DoseTap/ContentView.swift:1481-1496` | `ios/Core/DoseTapCore.swift:147-175` | `ios/DoseTap/Storage/SessionRepository.swift:531-549` → `ios/DoseTap/Storage/EventStorage.swift:907-912` | `ios/DoseTap/ContentView.swift:2783-2785` | `ios/DoseTap/ContentView.swift:2585-2635` |
| Dose 2 | `ios/DoseTap/ContentView.swift:1531-1540` | `ios/Core/DoseTapCore.swift:157-175` | `ios/DoseTap/Storage/SessionRepository.swift:561-601` → `ios/DoseTap/Storage/EventStorage.swift:919-934` | `ios/DoseTap/ContentView.swift:2783-2785` | `ios/DoseTap/ContentView.swift:2607-2635` |
| wake_final | `ios/DoseTap/ContentView.swift:2136-2155` | N/A (confirmation only) | `ios/DoseTap/Storage/SessionRepository.swift:854-868` → `ios/DoseTap/Storage/EventStorage.swift:600-629` | `ios/DoseTap/SleepStageTimeline.swift:583-590` | `ios/DoseTap/SleepStageTimeline.swift:613-626` |
| Session rollover | N/A | `ios/Core/SessionKey.swift:10-46` | `ios/DoseTap/Storage/SessionRepository.swift:225-252` | `ios/DoseTap/Storage/SessionRepository.swift:1328-1352` | `ios/DoseTap/ContentView.swift:2468-2506` |
| CSV export | `ios/DoseTap/SettingsView.swift:271-392` | N/A | `ios/DoseTap/Storage/SessionRepository.swift:1466-1467` → `ios/DoseTap/Storage/EventStorage.swift:2568-2655` | N/A | `ios/DoseTap/SettingsView.swift:388-391` |

## Data Model and Persistence Audit

### Table Inventory

| Table | Columns | PK | FK | Constraints | Indexes | Issues |
|---|---|---|---|---|---|---|
| sleep_events | id, event_type, timestamp, session_date, session_id, color_hex, notes, created_at | id | None | NOT NULL on event_type/timestamp/session_date | `idx_sleep_events_*` | No FK; session_id may be session_date. Evidence: `ios/DoseTap/Storage/EventStorage.swift:84-99`, `ios/DoseTap/Storage/EventStorage.swift:190-194` |
| dose_events | id, event_type, timestamp, session_date, session_id, metadata, created_at | id | None | NOT NULL on event_type/timestamp/session_date | `idx_dose_events_*` | No FK; inconsistent event_type strings. Evidence: `ios/DoseTap/Storage/EventStorage.swift:98-107`, `ios/DoseTap/Storage/EventStorage.swift:195-197` |
| current_session | id, dose1_time, dose2_time, snooze_count, dose2_skipped, session_date, session_id, session_start_utc, session_end_utc, updated_at | id | None | CHECK id=1 | N/A | session_id optional. Evidence: `ios/DoseTap/Storage/EventStorage.swift:109-121` |
| sleep_sessions | session_id, session_date, start_utc, end_utc, terminal_state, created_at, updated_at | session_id | None | NOT NULL on session_date/start_utc | `idx_sleep_sessions_date` | No FK relationships. Evidence: `docs/DATABASE_SCHEMA.md:57-69` |
| pre_sleep_logs | id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json, created_at | id | None | NOT NULL fields | `idx_pre_sleep_logs_session_id` | No FK; session_id optional. Evidence: `ios/DoseTap/Storage/EventStorage.swift:134-143` |
| morning_checkins | id, session_id, timestamp, session_date, ... | id | None | Many NOT NULL defaults | `idx_morning_checkins_*` | No FK; session_id optional. Evidence: `ios/DoseTap/Storage/EventStorage.swift:145-187` |
| medication_events | id, session_id, session_date, medication_id, dose_mg, dose_unit, formulation, taken_at_utc, local_offset_minutes, notes, confirmed_duplicate, created_at | id | None | NOT NULL fields | `idx_medication_events_*` | No FK; session_id optional. Evidence: `docs/DATABASE_SCHEMA.md:128-145` |

### Event Type Normalization

Event types in CODE (non-exhaustive):
- SleepEventType raw values: `bathroom`, `inBed`, `lightsOut`, `wakeFinal`, `wakeTemp`, `snack`, `water`, `anxiety`, `dream`, `noise`, `temperature`, `pain`, `heartRacing`. Evidence: `ios/Core/SleepEvent.swift:5-18`
- QuickLog display names: `Bathroom`, `Water`, `Lights Out`, `Brief Wake`, `In Bed`, `Nap Start`, `Nap End`, `Anxiety`, `Dream`, `Heart Racing`, `Noise`, `Temperature`, `Pain`. Evidence: `ios/DoseTap/UserSettingsManager.swift:142-175`
- InputValidator whitelist: camel/snake variants (`lightsOut`, `lights_out`, `wakeTemp`, `wake_temp`, etc). Evidence: `ios/DoseTap/Security/InputValidator.swift:22-35`
- URLRouter map outputs: `lights_out`, `wake`, `temp`, `restless`. Evidence: `ios/DoseTap/URLRouter.swift:276-303`
- Timeline mapping: camelCase (`lightsOut`, `wakeFinal`, `wakeTemp`). Evidence: `ios/DoseTap/FullApp/TimelineView.swift:750-782`
- Dose events: `dose1`, `dose2`, `extra_dose`, `dose2_skipped`, `snooze`. Evidence: `docs/SSOT/README.md:46-48`

Event types in DATABASE:
- HYPOTHESIS: derived from stored values in `sleep_events.event_type` and `dose_events.event_type`. Need `SELECT DISTINCT event_type FROM sleep_events` and `dose_events` on a device DB.

MISMATCHES:
- Display names are persisted as event types (Title Case) while code expects camel/snake. Evidence: `ios/DoseTap/ContentView.swift:42-66`, `ios/DoseTap/UserSettingsManager.swift:142-175`
- URLRouter normalizes to lowercased strings that aren’t in whitelist (`restless`, `temp`). Evidence: `ios/DoseTap/URLRouter.swift:276-303`, `ios/DoseTap/Security/InputValidator.swift:22-35`

### Migration Plan
```sql
-- Normalization migration (no data loss)
BEGIN TRANSACTION;

-- 1) Add canonical type column (optional) or normalize in-place
UPDATE sleep_events
SET event_type = CASE lower(event_type)
    WHEN 'lights out' THEN 'lights_out'
    WHEN 'lightsout' THEN 'lights_out'
    WHEN 'wake up' THEN 'wake_final'
    WHEN 'wake' THEN 'wake_final'
    WHEN 'brief wake' THEN 'wake_temp'
    WHEN 'nap start' THEN 'nap_start'
    WHEN 'nap end' THEN 'nap_end'
    ELSE lower(replace(event_type, ' ', '_'))
END;

UPDATE dose_events
SET event_type = CASE lower(event_type)
    WHEN 'dose1_taken' THEN 'dose1'
    WHEN 'dose2_taken' THEN 'dose2'
    ELSE lower(event_type)
END;

-- 2) Move dose events out of sleep_events if present
INSERT INTO dose_events (id, event_type, timestamp, session_date, session_id, metadata)
SELECT id, event_type, timestamp, session_date, session_id, NULL
FROM sleep_events
WHERE event_type IN ('dose1', 'dose2', 'dose2_skipped', 'snooze', 'extra_dose');

DELETE FROM sleep_events
WHERE event_type IN ('dose1', 'dose2', 'dose2_skipped', 'snooze', 'extra_dose');

COMMIT;

-- Rollback if needed
BEGIN TRANSACTION;
-- Reverse: move back from dose_events to sleep_events if necessary
-- (Implementation depends on backup strategy.)
COMMIT;

-- Validation queries
SELECT event_type FROM sleep_events WHERE event_type LIKE '% %';
SELECT event_type FROM dose_events WHERE event_type LIKE '%taken%';
```

## CSV Export Audit

### Current Code Path
```
UI Button: ios/DoseTap/SettingsView.swift:271-277
  → Export function: ios/DoseTap/SettingsView.swift:561-577
    → Data fetch: ios/DoseTap/Storage/SessionRepository.swift:1466-1467
      → CSV generation: ios/DoseTap/Storage/EventStorage.swift:2568-2655
        → File write: ios/DoseTap/SettingsView.swift:566-572
          → Share sheet: ios/DoseTap/SettingsView.swift:388-391
```

### Failure Mode Analysis

| Failure Mode | Likelihood | Impact | Current Handling | Required Fix |
|---|---|---|---|---|
| Permission denied | Low | High | None | Alert with remediation |
| Disk full | Low | High | None | Alert + free space check |
| Invalid characters | Medium | Medium | Minimal CSV escaping | RFC 4180 compliance |
| Concurrent exports | Low | Medium | None | Disable button while exporting |
| Large dataset | Medium | Medium | Sync string build on main | Stream/paginate, background queue |
| Encoding issues | Low | High | UTF-8 w/o BOM | Add UTF-8 BOM |

### Corrected Schema Specification
```csv
# DoseTap Export V3 | schema_version=3 | exported_at=ISO8601
# === SLEEP_EVENTS ===
column1,column2,...
...
```
Rules:
- Stable header order (documented)
- ISO8601 UTC timestamps
- Booleans as 0/1
- Nulls as empty string
- RFC 4180 escaping
- UTF-8 with BOM

### Implementation Plan
1. Build CSV via streaming writer (avoid large in-memory string)
2. Validate required fields before writing
3. Write to `FileManager.temporaryDirectory`
4. Present UIActivityViewController
5. Delete temp file after share
6. On error, show alert + log error

### Diagnostics Plan
```swift
Logger.export.info("Export started: tables=\(tables), eventCount=\(count)")
Logger.export.info("Export complete: fileSize=\(bytes), duration=\(ms)ms")
Logger.export.error("Export failed: error=\(error.code), stage=\(stage)")
```

## Concurrency and Reliability Audit

### Mutable State Owners

| Type | File | Thread Safety | MainActor | Issues | Fix |
|---|---|---|---|---|---|
| SessionRepository | `ios/DoseTap/Storage/SessionRepository.swift:35-70` | Main-thread only | Yes | DB calls on main | Move DB to background, keep UI state on main |
| EventStorage | `ios/DoseTap/Storage/EventStorage.swift:13-19` | Main-thread only | Yes | SQLite on main | Background actor/queue |
| EventLogger | `ios/DoseTap/ContentView.swift:7-66` | Main-thread only | Yes | Persists display-name events | Canonicalize types + emit sessionDidChange |
| AlarmService | `ios/DoseTap/AlarmService.swift:198-229` | Mixed | No | Snooze count diverges | Gate snooze on success |

### Race Condition Inventory

| Race Condition | Trigger | Impact | Reproduction | Fix |
|---|---|---|---|---|
| Snooze count increments after AlarmService failure | Near-close snooze | Incorrect snooze count | HYPOTHESIS: snooze within 15 min | Increment only after schedule success |
| Session key change during edit | Timezone/DST change | Edits saved to wrong session | HYPOTHESIS: change device TZ during edit | Recompute sessionId on save |
| Missing sessionDidChange on some inserts | EventLogger insertSleepEvent | Stale UI | HYPOTHESIS: History not refreshed | Emit sessionDidChange in insert path |

### Thread Safety Checklist
- [x] UI updates on MainActor (SessionRepository/EventStorage are MainActor)
- [ ] DB operations off main thread
- [ ] No unhandled `Task { }` blocks (multiple unstructured tasks exist)
- [ ] Combine publishers properly managed (EventLogger uses `AnyCancellable`)
- [ ] `sessionDidChange` fired on all mutations (missing for EventLogger inserts)

## Testing Plan

### Current Test Inventory

| Test File | Count | Coverage Area | Quality |
|---|---|---|---|
| `Tests/DoseCoreTests/SleepEventTests.swift` | 29 | SleepEvent models + mapping | Good |
| `Tests/DoseCoreTests/CRUDActionTests.swift` | 25 | Core CRUD invariants | Good |
| `Tests/DoseCoreTests/DataRedactorTests.swift` | 25 | PII redaction | Good |
| `Tests/DoseCoreTests/DoseWindowEdgeTests.swift` | 26 | Dose window edges | Good |
| `Tests/DoseCoreTests/Dose2EdgeCaseTests.swift` | 17 | Dose 2 edges | Good |
| `Tests/DoseCoreTests/EventRateLimiterTests.swift` | 19 | Rate limiting | Good |
| `Tests/DoseCoreTests/MedicationLoggerTests.swift` | 19 | Med logging | Good |
| `Tests/DoseCoreTests/CSVExporterTests.swift` | 16 | CSV v2 core | Good |
| `Tests/DoseCoreTests/SSOTComplianceTests.swift` | 15 | SSOT compliance | Good |
| `Tests/DoseCoreTests/TimeCorrectnessTests.swift` | 14 | Time correctness | Good |
| `Tests/DoseCoreTests/SleepEnvironmentTests.swift` | 13 | Sleep env | Good |
| `Tests/DoseCoreTests/DoseUndoManagerTests.swift` | 12 | Undo state | Good |
| `Tests/DoseCoreTests/APIErrorsTests.swift` | 12 | API errors | Good |
| `Tests/DoseCoreTests/APIClientTests.swift` | 11 | API client | Good |
| `Tests/DoseCoreTests/OfflineQueueTests.swift` | 7 | Offline queue | Good |
| `Tests/DoseCoreTests/SessionIdBackfillTests.swift` | 7 | Session id backfill | Good |
| `Tests/DoseCoreTests/DoseWindowStateTests.swift` | 7 | DoseWindow state | Good |
| `Tests/DoseCoreTests/SleepPlanCalculatorTests.swift` | 3 | Sleep plan | OK |

### Missing Coverage (by Risk)

| Area | Risk | Tests Needed |
|---|---|---|
| 6 PM rollover | Critical | SessionKey + SessionRepository integration |
| DST transitions | Critical | timezone change edges |
| Timeline/History parity | High | end-to-end event normalization tests |
| CSV schema stability | High | export header/order tests + BOM |
| Duplicate prevention | High | dose event duplication tests |
| Concurrent writes | Medium | multi-threaded DB access |
| UI refresh on sessionDidChange | Medium | view update tests |

### High-Value Tests to Add (15+)
1. `test_timeline_summary_reads_dose1_dose2_from_dose_events()` in `Tests/DoseCoreTests/TimeCorrectnessTests.swift`
2. `test_timeline_reads_wake_final_from_sleep_events()` in `Tests/DoseCoreTests/TimeCorrectnessTests.swift`
3. `test_event_normalization_maps_display_names_to_wire_format()` in `Tests/DoseCoreTests/SleepEventTests.swift`
4. `test_dose_buttons_do_not_write_sleep_events()` in `Tests/DoseCoreTests/SSOTComplianceTests.swift`
5. `test_session_id_is_uuid_for_all_tables()` in `Tests/DoseCoreTests/SessionIdBackfillTests.swift`
6. `test_export_failure_shows_error_alert()` in `ios/DoseTapTests/SettingsViewTests.swift`
7. `test_export_includes_utf8_bom()` in `Tests/DoseCoreTests/CSVExporterTests.swift`
8. `test_snooze_disallowed_near_close_does_not_increment()` in `Tests/DoseCoreTests/DoseWindowEdgeTests.swift`
9. `test_edit_dose_time_rekeys_session()` in `Tests/DoseCoreTests/TimeCorrectnessTests.swift`
10. `test_session_delete_cascades_events()` in `Tests/DoseCoreTests/CRUDActionTests.swift`
11. `test_export_runs_off_main_thread()` in `ios/DoseTapTests/ExportTests.swift`
12. `test_csv_headers_stable_order()` in `Tests/DoseCoreTests/CSVExporterTests.swift`
13. `test_timezone_change_triggers_session_refresh()` in `Tests/DoseCoreTests/TimeCorrectnessTests.swift`
14. `test_deep_link_event_validation_accepts_canonical_types()` in `Tests/DoseCoreTests/SleepEventTests.swift`
15. `test_session_closed_event_filtered_from_history()` in `ios/DoseTapTests/HistoryTests.swift`
16. `test_privacy_manifest_in_bundle()` in `ios/DoseTapTests/ComplianceTests.swift`

## Security, Privacy, Accessibility, Performance

### Security & Privacy

| Area | Status | Evidence | Issues | Fix |
|---|---|---|---|---|
| Encryption at rest | Not wired (HYPOTHESIS) | `ios/DoseTap/Security/DatabaseSecurity.swift:15-119`, `ios/DoseTap/Storage/EncryptedEventStorage.swift:15-129` | DB likely plaintext | Wire SQLCipher or remove unused code |
| Keychain usage | Present but unused | `ios/DoseTap/Security/DatabaseSecurity.swift:32-119` | Not integrated | Integrate or remove |
| Privacy manifest | Missing (HYPOTHESIS) | `rg --files -g '*xcprivacy*'` returned none | Compliance risk | Add PrivacyInfo.xcprivacy |
| PII in logs | Risk | `ios/DoseTap/ContentView.swift:39-40` | Console prints may leak | Replace with os.Logger and redact |
| Certificate pinning | Not in build | `build.log:1-2` | Pinning file not in target | Add to target or remove |

### Accessibility

| Screen | VoiceOver | Dynamic Type | Contrast | Issues |
|---|---|---|---|---|
| Tonight/Details/History | Unknown | Partial | Mixed | Fixed font sizes + color-only signals (HYPOTHESIS) |
| Settings | Unknown | Partial | Mixed | Needs audit in Simulator |

### Performance

| Area | Threshold | Current | Issues | Fix |
|---|---|---|---|---|
| Cold launch | <2s | HYPOTHESIS | No metrics | Add Instruments baseline |
| Timeline scroll | 60fps | HYPOTHESIS | DB queries on main | Move DB to background |
| DB query (1K events) | <100ms | HYPOTHESIS | No indexes on FK | Add FK + query profiling |
| Memory baseline | <100MB | HYPOTHESIS | CSV export builds full string | Stream to file |

## Fix Roadmap

### Phase 1: Hotfix (24-48 hours)
| Issue | Severity | Effort | Risk | Acceptance Criteria |
|---|---|---|---|---|
| Timeline vs History mismatch | Critical | M | Medium | Timeline shows dose/wake for current session |
| Event type normalization | Critical | M | Medium | Canonical event types stored and displayed |
| Snooze rule mismatch | Major | S | Low | Snooze disabled near close, count matches alarms |
| CSV export error handling | Major | S | Low | User sees error on export failure |

### Phase 2: Stabilization (1-2 weeks)
| Issue | Severity | Effort | Risk | Acceptance Criteria |
|---|---|---|---|---|
| session_id UUID migration | Critical | M | High | All rows have UUID session_id |
| FK constraints + cleanup | Major | M | Medium | No orphaned rows; cascades work |
| Time edit re-keying | Major | M | Medium | Edits move events to correct session |
| Remove CoreData split-brain | Major | M | Medium | Only SQLite used |

### Phase 3: Hardening (1 month)
| Issue | Severity | Effort | Risk | Acceptance Criteria |
|---|---|---|---|---|
| Move DB off main thread | Major | L | Medium | UI responsive under export |
| Encryption at rest | Major | L | Medium | SQLCipher enabled |
| Privacy manifest | Major | S | Low | Manifest included in build |

### Phase 4: Future Enhancements
| Enhancement | Priority | Effort | Dependencies | Value |
|---|---|---|---|---|
| CloudKit Sync | Medium | L | Session identity fix | Multi-device continuity |
| Widgets | Medium | M | Timeline parity | At-a-glance status |
| HealthKit Integration | High | L | Data normalization | Sleep insights |
| Siri Shortcuts | Medium | M | Event normalization | Hands-free logging |

## Future Implementation Roadmap

### Near-Term (Next Release)
1. CloudKit Sync
2. Apple Watch Complications
3. HealthKit Integration
4. Widgets

### Medium-Term (3-6 months)
1. Manual Dose Entry
2. Medication Inventory
3. Doctor Report Export
4. Siri Shortcuts

### Long-Term (6-12 months)
1. Multi-Medication Support
2. Analytics Dashboard
3. Caregiver Mode
4. Clinical Trial Integration

### Technical Debt Priorities
1. Remove legacy code in `ios/DoseTap/legacy/`
2. Consolidate duplicate models (DoseCore vs app layer)
3. Migrate to SwiftData when stable for iOS 18+
4. Add comprehensive UI tests with snapshot testing
5. Implement structured error handling
6. Add telemetry/analytics for production debugging

## Repro Attempts
- Timeline vs History mismatch: Manual UI actions on iPhone 17 Pro (Dose 1, Dose 2 Early, Bathroom, Lights Out). SQLite populated with mixed event_type casing across `dose_events` vs `sleep_events`, confirming duplication and normalization drift. UI screenshots show the same events in both Timeline and History, but strings differ in DB (see Runtime Validation Addendum).
- CSV export failure: Export completed via Settings and CSV inspected. No runtime failure observed, but schema concerns remain (no BOM, mixed event_type casing, duplicate dose events across tables).

## Runtime Validation Addendum (Simulator, CLI-only)
- Built and launched iOS app on Simulator. Verified `com.dosetap.ios` installed and launched. Evidence: `ios_build.log`, `simctl listapps`.
- Manual UI actions performed on iPhone 17 Pro (Dose 1, Dose 2 Early, Bathroom, Lights Out). User screenshots show these events in Timeline and History.
- SQLite evidence (iPhone 17 Pro container `Documents/dosetap_events.sqlite`):
  - Counts: `dose_events`=8, `sleep_events`=38, `current_session`=1.
  - `dose_events` recent types: `dose1`, `dose2`.
  - `sleep_events` recent types: `Dose 1`, `Dose 2 (Early)`, `Bathroom`, `lightsOut`.
  - Distinct event types include mixed casing and duplicates: `dose1`, `dose2`, `Dose 1`, `Dose 2 (Early)`, `lightsOut`, `wakeFinal`, `wake_final`, etc.
- Conclusion: event types are not normalized and dose events are duplicated into `sleep_events`, matching the P0 audit findings. Timeline/History parity is now validated with runtime data.

## Runtime Validation Addendum (Post-Fix)
- After normalization + dedupe changes, new events are stored as canonical lowercase/snake_case:
  - `sleep_events` latest entries: `bathroom`, `water`, `lights_out`, `brief_wake`, `snack`, `pain`, `dream`, `heart_racing`, `in_bed`.
  - `dose_events` latest entries: `dose1`, `dose2` with `metadata` indicating early dose.
- Legacy mixed-case entries remain from pre-fix data (`Dose 1`, `Dose 2 (Early)`, `lightsOut`, `wakeFinal`), confirming a migration is still required to normalize historical rows.
- No new dose entries were written into `sleep_events` after the fix; dose actions now appear only in `dose_events`.
## CSV Export Validation (Runtime)
Export file: `docs/review/DoseTap_Export_2026-01-19_145947.csv`
- File exists and parses correctly; 85 lines with 7 sections.
- Section row counts: sleep_events=29, dose_events=9, sessions=5, morning_checkins=5, pre_sleep_logs=6, medication_events=0, sleep_sessions=8.
- No UTF-8 BOM (export is UTF-8 without BOM).
- Event type divergence persists in export:
  - `sleep_events`: `Bathroom`, `Dose 1`, `Dose 2`, `Dose 2 (Late)`, `Pain`, `lightsOut`, `pain.pre_sleep`, `pain.wake`, `wake_final`.
  - `dose_events`: `dose1`, `dose2`, `dose2_skipped`.
- CSV rows are well-formed; JSON fields are properly quoted; no column count mismatches.

Conclusion: Export succeeds but reflects inconsistent event_type normalization and duplication across tables. No silent failure observed in this run.
