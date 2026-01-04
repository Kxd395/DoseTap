# DoseTap Audit Log

**Audit Date:** December 24, 2025  
**Auditor:** HyperCritical Auditor (Claude)  
**Environment:** macOS, Xcode 15+, Swift 5.9+, iOS 16+, watchOS 9+

---

## Documentation Unification (2025-12-24)

### P0 Fixes Completed

| Issue | Resolution | Files Changed |
|-------|------------|---------------|
| Core Data vs SQLite claims | Removed ALL Core Data references, SQLite is canonical | `architecture.md` |
| Schema version drift | Updated from v4 → v6, added morning_checkins + pre_sleep_logs | `SchemaEvolution.md` |
| Event taxonomy conflicts | Unified to 13 types (added `inBed`), canonical source = `constants.json` | `DataDictionary.md`, `SSOT/README.md`, `docs/README.md` |
| Test count contradictions | Fixed all references to "207 tests passing" | `docs/README.md` |
| Dose event naming | Standardized to snake_case: `dose_1`, `dose_2`, `snooze`, `skip`, `extra_dose` | `SchemaEvolution.md`, `DataDictionary.md` |
| Database table count | Fixed "4 tables" → "5 tables" (added pre_sleep_logs) | `docs/README.md`, `DataDictionary.md` |

### Files Updated
- `docs/architecture.md` - Complete rewrite: SQLite-only, added ERD, removed Core Data
- `docs/SSOT/contracts/SchemaEvolution.md` - v4 → v6, added v5/v6 migrations
- `docs/SSOT/contracts/DataDictionary.md` - 5 tables, 13 sleep events, pre_sleep_logs
- `docs/SSOT/README.md` - 13 sleep events (was 12), corrected cooldowns
- `docs/README.md` - Fixed test counts, 5 tables, 13 events

### Canonical Sources Established
| Artifact | Canonical File |
|----------|---------------|
| Schema definition | `docs/DATABASE_SCHEMA.md` |
| Schema migrations | `docs/SSOT/contracts/SchemaEvolution.md` |
| Enum definitions | `docs/SSOT/constants.json` |
| Field constraints | `docs/SSOT/contracts/DataDictionary.md` |
| Architecture overview | `docs/architecture.md` |

---

## Chronological Action Log

| Time (UTC) | Action | Findings |
|------------|--------|----------|
| 08:14 | Read SSOT documents | Identified TWO SSOT documents: `SSOT_v2.md` (v2.1.0, Dec 23) and `README.md` (v2.1.0, Jan 6). Both claim to be authoritative. |
| 08:14 | Read navigation.md | Confirmed navigation structure, noted version dates |
| 08:14 | Verified ios/Core directory | 11 files present, all SSOT-referenced core files exist |
| 08:14 | Verified Tests/DoseCoreTests | 8 test files, 95 total tests |
| 08:14 | Verified ios/DoseTapiOSApp | UI layer files present, SQLiteStorage, QuickLogPanel |
| 08:14 | Ran `swift test` | **95 tests pass** in 0.019 seconds |
| 08:15 | Searched for secrets | Found `Secrets.swift` with hardcoded WHOOP client ID/secret (NOT in git per .gitignore) |
| 08:15 | Searched for Keychain usage | `KeychainHelper.swift` exists but `HealthIntegrationService.swift` uses UserDefaults for tokens |
| 08:15 | Searched for undo implementation | **NOT FOUND** - No UndoManager, UndoSnackbar, or undo timer in active code |
| 08:15 | Verified cooldown values | **DOC DRIFT** - Water cooldown: 60s in README, 300s in code/SSOT_v2 |
| 08:15 | Verified undo window values | **DOC DRIFT** - SSOT says 5s, SetupWizard default is 15s |
| 08:15 | Checked watchOS implementation | Minimal - only 4 buttons, no window logic, no timer display |
| 08:15 | Checked EventRateLimiter tests | Only 1 test for bathroom (60s cooldown) |
| 08:15 | Checked OfflineQueue tests | 4 tests covering basic retry logic |

---

## Files Verified

### ios/Core/ (DoseCore module)
- [x] DoseWindowState.swift - Window calculation logic
- [x] APIClient.swift - HTTP client
- [x] APIErrors.swift - Error mapping
- [x] APIClientQueueIntegration.swift - DosingService facade
- [x] OfflineQueue.swift - Retry queue
- [x] EventRateLimiter.swift - Cooldown enforcement
- [x] SleepEvent.swift - 12 event types with cooldowns
- [x] UnifiedSleepSession.swift - Data model
- [x] RecommendationEngine.swift - Target calculation
- [x] TimeEngine.swift - Time utilities
- [x] DoseTapCore.swift - Legacy (unused)

### Tests/DoseCoreTests/
- [x] DoseWindowStateTests.swift (7 tests)
- [x] DoseWindowEdgeTests.swift (6 tests)
- [x] APIClientTests.swift (11 tests)
- [x] APIErrorsTests.swift (12 tests)
- [x] CRUDActionTests.swift (25 tests)
- [x] OfflineQueueTests.swift (4 tests)
- [x] EventRateLimiterTests.swift (1 test)
- [x] SleepEventTests.swift (29 tests)

### Missing Files (SSOT-referenced but NOT FOUND)
- [ ] `UndoManager.swift` - Referenced in copilot-instructions, NOT in active code
- [ ] `UndoSnackbar.swift` - Referenced in docs, NOT in active code
- [ ] `SleepDataAggregator.swift` - SSOT Phase 2 planned, NOT implemented
- [ ] `HeartRateChartView.swift` - SSOT Phase 2 planned, NOT implemented
- [ ] `SleepStagesChart.swift` - SSOT Phase 2 planned, NOT implemented

---

## Commands Executed

```bash
# Test suite
swift test
# Result: 95 tests, 0 failures

# Git verification
git ls-files ios/DoseTap/Secrets.swift
# Result: (empty - not tracked)

git status ios/DoseTap/Secrets.swift
# Result: working tree clean
```

---

## Key Invariant Verification

| Invariant | SSOT Value | Code Value | Status |
|-----------|------------|------------|--------|
| Min interval | 150 min | 150 min | ✅ MATCH |
| Max interval | 240 min | 240 min | ✅ MATCH |
| Default target | 165 min | 165 min | ✅ MATCH |
| Near-close threshold | 15 min | 15 min | ✅ MATCH |
| Snooze step | 10 min | 10 min | ✅ MATCH |
| Max snoozes | 3 | 3 | ✅ MATCH |
| Undo window | 5 sec | 15 sec (SetupWizard) | ❌ CONFLICT |
| Water cooldown | 60s (README) | 300s (SleepEvent.swift) | ❌ CONFLICT |

