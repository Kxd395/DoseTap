# GAP Closure Report — 2025-12-25

## Executive Summary

All 5 identified gaps from the prior audit have been successfully closed with comprehensive test coverage and documentation updates.

| Gap | Status | Tests Added | Files Modified/Created |
|-----|--------|-------------|----------------------|
| GAP A: HealthKit Protocol | ✅ CLOSED | 5 Xcode tests | 2 created, 1 modified |
| GAP B: Time Correctness | ✅ CLOSED | 14 SwiftPM tests | 2 created |
| GAP C: Export Integrity | ✅ CLOSED | 6 Xcode tests | 3 modified |
| GAP D: SSOT Regression | ✅ CLOSED | 2 SwiftPM tests | 1 modified |
| GAP E: Doc Hygiene | ✅ CLOSED | — | 3 modified |

---

## Verification Results

### SwiftPM Tests
```
Executed 262 tests, with 0 failures (0 unexpected) in 2.234 seconds
```

### Xcode Tests (iPhone 15, iOS 17.2)
```
32 tests passed:
  - SessionRepositoryTests: 12 tests
  - DataIntegrityTests: 9 tests
  - ExportIntegrityTests: 6 tests (NEW)
  - HealthKitProviderTests: 5 tests (NEW)
```

---

## GAP A: HealthKit Protocol Boundary

**Requirement:** Create `HealthKitProviding` protocol with no-op/fake implementation for test isolation.

**Solution:**
- Created `ios/DoseTap/Services/HealthKitProviding.swift`
- `HealthKitProviding` protocol with 4 methods: `requestAuthorization()`, `isAuthorized`, `saveSleepSample()`, `querySleepData()`
- `NoOpHealthKitProvider` class with call tracking (`authorizationCalls`, `saveCalls`, `queryCalls`)
- Modified `HealthKitService` to conform to `HealthKitProviding`

**Tests (5):**
```swift
HealthKitProviderTests:
  - test_healthKitService_conformsToProtocol
  - test_noOpProvider_returnsSafeDefaults
  - test_noOpProvider_canBeStubbed
  - test_noOpProvider_tracksCalls
  - test_noOpProvider_resetClearsCalls
```

---

## GAP B: Time Correctness Tests

**Requirement:** Add deterministic tests for 6 PM boundary, DST transitions, timezone changes, backdated edits.

**Solution:**
- Created `Tests/DoseCoreTests/TimeCorrectnessTests.swift`
- Added `sessionDateString(for:)` method to `DoseWindowState.swift`
- 6 PM boundary: events before 6 PM belong to previous day's session
- All tests inject time deterministically via `DoseWindowCalculator(now:)`

**Tests (14):**
```swift
TimeCorrectnessTests:
  // 6 PM Boundary (5)
  - test_6PM_boundary_12PM_belongsToPreviousDay
  - test_6PM_boundary_2AM_belongsToPreviousDay
  - test_6PM_boundary_559PM_belongsToPreviousDay
  - test_6PM_boundary_600PM_belongsToCurrentDay
  - test_6PM_boundary_601PM_belongsToCurrentDay
  
  // DST Transitions (4)
  - test_DST_forward_windowStaysCorrect
  - test_DST_forward_windowExpiresAtRealTime
  - test_DST_backward_windowStaysCorrect
  - test_DST_backward_noExtraWindowTime
  
  // Timezone Changes (2)
  - test_timezone_change_windowMathUnaffected
  - test_timezone_change_sessionDateStability
  
  // Backdated Edits (3)
  - test_backdatedEdit_noDuplicateSession
  - test_forwardEdit_sameSession
  - test_crossDayEdit_differentSessions
```

---

## GAP C: Export Integrity Tests

**Requirement:** Tests for export row counts matching database, support bundle excluding secrets.

**Solution:**
- Added `getAllSessions()` to `EventStorage` and `SessionRepository`
- Added `getSchemaVersion()` to `EventStorage` (PRAGMA user_version)
- Created 6 new tests in `DoseTapTests.swift`

**Tests (6):**
```swift
ExportIntegrityTests:
  - test_export_rowCountMatchesDatabaseSessions
  - test_export_noEmptyRows
  - test_export_includesSchemaVersion
  - test_supportBundle_excludesAPIKeys
  - test_supportBundle_redactsEmails
  - test_supportBundle_redactsDeviceIDs
```

**API Additions:**
```swift
// EventStorage.swift
func getAllSessions() -> [String]  // Returns unique session dates
func getSchemaVersion() -> Int     // Returns PRAGMA user_version

// SessionRepository.swift
func getAllSessions() -> [String]  // Wrapper around storage method
```

---

## GAP D: SSOT Regression Guards

**Requirement:** Test that fails if DoseTapCore reintroduces stored dose state.

**Solution:**
- Added 2 tests to `SSOTComplianceTests.swift`
- Guards against caching dose state (must delegate to repository)
- Guards against caching window context (must compute fresh)

**Tests (2):**
```swift
SSOTComplianceTests:
  - testSSOT_noStoredDoseState
  - testSSOT_doseWindowContext_computedNotCached
```

---

## GAP E: Documentation Hygiene

**Requirement:** Stop using exact test totals as permanent facts in docs.

**Files Updated:**
1. `docs/architecture.md` — Replaced "246" with CI reference
2. `README.md` — Replaced "207" counts (3 locations) with CI reference
3. `docs/FEATURE_ROADMAP.md` — Added note about checking CI for current counts

**Pattern Applied:**
```markdown
<!-- Before -->
- **Test coverage**: 207 unit tests

<!-- After -->
- **Test coverage**: See CI for current test counts
```

---

## Files Created/Modified

### New Files
| File | Purpose |
|------|---------|
| `ios/DoseTap/Services/HealthKitProviding.swift` | Protocol + NoOp fake for HealthKit isolation |
| `Tests/DoseCoreTests/TimeCorrectnessTests.swift` | 14 deterministic time tests |
| `docs/GAP_CLOSURE_LOG_2025-12-25.md` | Change ledger tracking all modifications |

### Modified Files
| File | Changes |
|------|---------|
| `ios/DoseTap/HealthKitService.swift` | Added `: HealthKitProviding` conformance |
| `ios/Core/DoseWindowState.swift` | Added `sessionDateString(for:)` method |
| `ios/DoseTap/Storage/EventStorage.swift` | Added `getAllSessions()`, `getSchemaVersion()` |
| `ios/DoseTap/Storage/SessionRepository.swift` | Added `getAllSessions()` |
| `ios/DoseTapTests/DoseTapTests.swift` | Added 11 tests (5 HealthKit + 6 Export) |
| `Tests/DoseCoreTests/SSOTComplianceTests.swift` | Added 2 regression guard tests |
| `Package.swift` | Added TimeCorrectnessTests.swift to sources |
| `ios/DoseTap.xcodeproj/project.pbxproj` | Added HealthKitProviding.swift references |
| `docs/architecture.md` | Removed hardcoded test count |
| `README.md` | Removed hardcoded test counts (3 locations) |
| `docs/FEATURE_ROADMAP.md` | Added dynamic counts note |

---

## Test Count Summary

| Suite | Before | After | Delta |
|-------|--------|-------|-------|
| SwiftPM (DoseCoreTests) | 246 | 262 | +16 |
| Xcode (DoseTapTests) | 21 | 32 | +11 |
| **Total** | **267** | **294** | **+27** |

---

## Remaining SSOT Warnings (Cosmetic)

The SSOT lint check shows warnings for:
- Component IDs not yet implemented (planned UI features)
- API endpoints not in OpenAPI spec (local-only for now)
- One stale Core Data reference in archived code review doc

These are expected for features in the roadmap and do not affect the core functionality or test coverage.

---

## Conclusion

All 5 gaps identified in the prior audit have been closed with:
- **27 new tests** providing regression protection
- **HealthKit protocol boundary** enabling isolated testing
- **Time correctness tests** with deterministic injection
- **Export integrity tests** verifying data consistency
- **SSOT regression guards** preventing state caching
- **Documentation** no longer contains hardcoded test counts

The codebase is now better protected against regressions in critical areas: HealthKit integration, time math edge cases, export data integrity, and SSOT compliance.
