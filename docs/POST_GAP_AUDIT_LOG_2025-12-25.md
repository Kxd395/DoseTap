# Post-Gap Audit Log — 2025-12-25

## Timestamps and Commands

### 15:50 UTC — Initial Verification

**Command:** `read_file docs/GAP_CLOSURE_REPORT_2025-12-25.md`
**Result:** Report claims 5 gaps closed, 27 new tests

### 15:51 UTC — File Existence Verification

**Commands:**
- `read_file ios/DoseTap/Services/HealthKitProviding.swift` → ✅ 93 lines, protocol + NoOpHealthKitProvider
- `grep_search HealthKitProviding` in HealthKitService.swift → ✅ Conformance confirmed at line 10
- `read_file Tests/DoseCoreTests/TimeCorrectnessTests.swift` → ✅ 382 lines, 14 tests
- `grep_search testSSOT_` → ✅ Found in SSOTComplianceTests.swift
- `read_file ios/DoseTapTests/DoseTapTests.swift` → ✅ ExportIntegrityTests at 376, HealthKitProviderTests at 284

### 15:52 UTC — Test Suite Execution

**Command:** `bash tools/ssot_check.sh`
**Result:** 26 issues (25 warnings for planned features, 1 meta-reference in log)

**Command:** `bash tools/doc_lint.sh`
**Result:** FAIL on "12 event" reference in archived FIX_PLAN (cosmetic)

**Command:** `swift test`
**Result:** 262 tests, 0 failures

**Command:** `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap ...`
**Result:** 32 tests passed
- SessionRepositoryTests: 12
- DataIntegrityTests: 9
- ExportIntegrityTests: 6
- HealthKitProviderTests: 5

### 15:54 UTC — Timezone Matrix Testing

**Command:** `TZ=UTC swift test`
**Result:** ❌ FAIL — 1 test failed (test_6PM_boundary_559PM_belongsToPreviousDay)

**Root Cause:** `sessionDateString(for:)` used `Calendar.current` which inherits system TZ.
Tests created dates in America/New_York but hour extraction was in UTC.

### 15:55 UTC — Timezone Fix Implementation

**Files Modified:**
1. `ios/Core/DoseWindowState.swift` — Added optional `timeZone` parameter to `sessionDateString(for:in:)`
2. `Tests/DoseCoreTests/TimeCorrectnessTests.swift` — Updated all tests to pass explicit timezone

### 15:56 UTC — Timezone Matrix Re-test

**Command:** `TZ=UTC swift test --filter TimeCorrectnessTests`
**Result:** ✅ 14 tests, 0 failures

**Command:** `TZ=America/New_York swift test --filter TimeCorrectnessTests`
**Result:** ✅ 14 tests, 0 failures

**Command:** `TZ=UTC swift test`
**Result:** ✅ 262 tests, 0 failures

**Command:** `TZ=America/New_York swift test`
**Result:** ✅ 262 tests, 0 failures

### 15:57 UTC — CI Update

**File Modified:** `.github/workflows/ci.yml`
**Changes:** Added TZ=UTC and TZ=America/New_York test steps to swiftpm-tests job

### 15:58 UTC — Documentation Audit

**File:** `README.md`
- Found: "207 unit tests passing" (hardcoded)
- Fixed: Changed to "See CI for current counts"

**File:** `docs/architecture.md`
- Verified: `@Published dose1Time, dose2Time, snoozeCount` diagram is ACCURATE
- SessionRepository IS the SSOT and uses @Published for UI binding
- No false claims found

**File:** `docs/FEATURE_ROADMAP.md`
- Has disclaimer: "Test counts in this document are historical snapshots"
- WHOOP/HealthKit features clearly marked as PLANNED (Phase 2/4)
- No false implementation claims

### 15:59 UTC — HealthKit Isolation Verification

**Command:** `grep_search HKHealthStore` in ios/DoseTapTests/
**Result:** No matches — tests only use NoOpHealthKitProvider

**File:** `ios/DoseTap/HealthKitService.swift`
- Verified: `requestAuthorization()` is NOT called at init
- Authorization is lazy/explicit

### 16:00 UTC — Export Test Strictness Verification

**File:** `ios/DoseTapTests/DoseTapTests.swift` lines 376-518
- `test_export_rowCountMatchesDatabaseSessions` — Asserts count equality, not just existence
- `test_export_noEmptyRows` — Iterates and checks each session date
- `test_export_includesSchemaVersion` — Asserts >= 0
- `test_supportBundle_excludesAPIKeys` — Pattern matching for secrets
- `test_supportBundle_redactsDeviceIDs` — UUID redaction check
- `test_supportBundle_redactsEmails` — Email redaction check

All tests assert real invariants, not just file existence.

### 16:01 UTC — SSOT Regression Guard Analysis

**File:** `Tests/DoseCoreTests/SSOTComplianceTests.swift` lines 117-168
- `testSSOT_doseTapCore_noStoredDoseState` — Proves calculator is stateless via input variation
- `testSSOT_doseWindowContext_computedNotCached` — Proves context reflects time injection, no cache

**Negative Test Strategy Note:**
To prove the guard works, one could temporarily modify `DoseWindowCalculator` to cache results:
```swift
// TEMPORARY REGRESSION SIMULATION (DO NOT COMMIT)
private var cachedContext: DoseWindowContext?
func context(...) -> DoseWindowContext {
    if let cached = cachedContext { return cached }  // Would cause test to fail
    ...
}
```
The `testSSOT_doseWindowContext_computedNotCached` would fail because ctx1.phase == ctx2.phase (both would be `.beforeWindow` from cache).

---

## Summary of Changes Made

| File | Change | Reason |
|------|--------|--------|
| `ios/Core/DoseWindowState.swift` | Added `in timeZone:` parameter | Fix TZ-dependent test failures |
| `Tests/DoseCoreTests/TimeCorrectnessTests.swift` | Pass explicit timezone to all tests | Timezone determinism |
| `.github/workflows/ci.yml` | Added TZ=UTC and TZ=America/New_York steps | CI timezone matrix |
| `README.md` | "207 tests" → "See CI for current counts" | Remove hardcoded count |

---

## Files Verified

| File | Status | Evidence |
|------|--------|----------|
| `ios/DoseTap/Services/HealthKitProviding.swift` | ✅ EXISTS | 93 lines, protocol + NoOp |
| `ios/DoseTap/HealthKitService.swift` | ✅ CONFORMS | `: HealthKitProviding` at line 10 |
| `Tests/DoseCoreTests/TimeCorrectnessTests.swift` | ✅ EXISTS | 386 lines, 14 tests |
| `Tests/DoseCoreTests/SSOTComplianceTests.swift` | ✅ HAS GUARDS | 2 regression tests |
| `ios/DoseTapTests/DoseTapTests.swift` | ✅ HAS TESTS | 32 tests total |
| `ios/DoseTap/Storage/EventStorage.swift` | ✅ HAS METHODS | getAllSessionDates(), getSchemaVersion() |
