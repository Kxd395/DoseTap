# Code Review: DoseTap Safety & Correctness Audit

> ⚠️ **SUPERSEDED**: This document shows pre-fix state. See `CODE_REVIEW_2025-12-24_session3.md` for verified post-fix state.

**Date:** 2025-12-24  
**Reviewer:** Automated Code Audit  
**Focus:** Two-sources-of-truth risk, persistence integrity, timing edge cases, dose safety

---

## Readiness Score: 🟡 75/100

| Category | Score | Notes |
|----------|-------|-------|
| State Management | 60 | P0: Two active state containers in ios/DoseTap/ContentView.swift |
| Persistence | 90 | SQLite uses transactions for multi-table operations |
| Notifications | 95 | Session deletion cancels pending notifications correctly |
| Export/Support | 85 | PII minimized but honest disclaimer "not guaranteed zero-PII" |
| Test Coverage | 90 | 207 SwiftPM + 13 Xcode tests, P0-fix regression tests exist |

---

## P0 Findings (Release Blockers)

### P0-1: Two Sources of Truth in ContentView.swift

**File:** `ios/DoseTap/ContentView.swift`  
**Lines:** 98-145

**Evidence:**
```swift
// Line 98 - Creates separate state container
@StateObject private var core = DoseTapCore()

// Line 101 - Also has SessionRepository
@StateObject private var sessionRepo = SessionRepository.shared

// Line 137-145 - Sync attempt (fragile bridge)
private func syncCoreFromRepository() {
    core.dose1Time = sessionRepo.dose1Time  // one-way sync
    core.dose2Time = sessionRepo.dose2Time
    core.snoozeCount = sessionRepo.snoozeCount
    core.isSkipped = sessionRepo.dose2Skipped
}
```

**Root Cause:** `DoseTapCore` (`ios/Core/DoseTapCore.swift` lines 37-41) has its own `@Published` dose state:
```swift
@Published public var dose1Time: Date?
@Published public var dose2Time: Date?
@Published public var snoozeCount: Int = 0
@Published public var isSkipped: Bool = false
```

**Impact:** 
- Views call `core.takeDose()` which writes to `DoseTapCore`, NOT `SessionRepository`
- Sync is one-way (repo → core) but writes go the other way (core → API)
- State can desync: delete session in History → repo clears → core still has ghost dose

**Fix Required:**
1. Eliminate `DoseTapCore` from `ContentView.swift`
2. Make views read from `SessionRepository.shared.currentContext`
3. Make dose actions call `SessionRepository` methods (like `DoseCoreIntegration` does)

---

### P0-2: DoseTapCore Still Has Own State (Should Be Stateless Bridge)

**File:** `ios/Core/DoseTapCore.swift`  
**Lines:** 35-90

**Evidence:** The `takeDose()` method writes directly to local `@Published` vars:
```swift
public func takeDose(earlyOverride: Bool = false) async {
    await MainActor.run {
        if dose1Time == nil {
            dose1Time = now  // Writes to DoseTapCore, not SessionRepository
        }
        // ...
    }
}
```

**Fix Required:** Refactor `DoseTapCore` to be a stateless bridge that:
1. Calls `SessionRepository.shared.setDose1Time()`
2. Derives `currentStatus` from `SessionRepository.shared.currentContext.phase`

---

## P1 Findings (Should Fix Before Production)

### P1-1: SSOT Lint Has 25 Warnings

**Evidence:** `bash tools/ssot_check.sh` reports:
- 15 component IDs in SSOT not found in codebase (roadmap items)
- 7 API endpoints not in OpenAPI spec
- 1 broken link to `../CHANGELOG.md`

**Fix:** Either implement roadmap items or mark them as TODO in SSOT README.

---

### P1-2: Missing Stimulant Logger UI

**Evidence:** User reported "app still has no way for me to add [stimulant medication]"

**Missing Features:**
- No `MedicationEntry` model
- No medication logging UI
- SSOT mentions it in roadmap but not implemented

**Fix:** Implement medication logger (separate task, spec exists).

---

## P2 Findings (Nice to Have)

### P2-1: EventStorage Uses Raw SQLite Without ORM

**File:** `ios/DoseTap/Storage/EventStorage.swift`

**Observation:** 1675 lines of manual SQLite with `sqlite3_prepare_v2`, `sqlite3_bind_text`, etc.

**Risk:** Error handling is inconsistent; some paths don't check `SQLITE_OK`.

**Recommendation:** Consider migrating to GRDB or SQLite.swift for type safety.

---

### P2-2: Support Bundle PII Disclaimer

**File:** `ios/DoseTap/SupportBundleExport.swift` Line 155

**Evidence:**
```swift
Text("Review before sharing • PII minimized, not guaranteed zero-PII")
```

**Status:** Acceptable — honest disclosure is better than false promise.

---

## Verification Log

### SwiftPM Tests
```
$ swift test -q
Executed 207 tests, with 0 failures (0 unexpected) in 2.325 seconds
```

### Xcode Tests
```
$ xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap ...
Test suite 'SessionRepositoryTests' started
  ✓ test_deleteActiveSession_clearsTonightState (0.012s)
  ✓ test_currentContext_returnsNoDose1_afterDeletion (0.012s)
  ✓ test_deleteSession_broadcastsChangeSignal (0.011s)
  ... 10 more tests ...
** TEST SUCCEEDED **
Executed 13 tests, with 0 failures
```

### SSOT Lint
```
$ bash tools/ssot_check.sh
Found 25 issues that need attention
Exit code: 1 (expected - roadmap items not yet implemented)
```

---

## Definition of Done Checklist

| Criterion | Status | Evidence |
|-----------|--------|----------|
| No stale UI state sources remain | ❌ FAIL | `DoseTapCore` still has own @Published vars |
| All safety critical dose flows tested | ✅ PASS | SessionRepositoryTests cover delete/ghost dose |
| SQLite operations transactional where needed | ✅ PASS | `deleteSession()` uses BEGIN/COMMIT |
| Notifications cannot fire for deleted sessions | ✅ PASS | `SessionRepository.deleteSession()` calls `cancelPendingNotifications()` |
| Export and support bundles safe and truthful | ✅ PASS | PII minimized, honest disclaimer |

---

## Recommended Fix Order

1. **P0-1 + P0-2:** Eliminate `DoseTapCore` state in `ContentView.swift` → replace with `SessionRepository` calls
2. **P1-1:** Clean up SSOT warnings (add TODOs or implement)
3. **P1-2:** Implement medication logger (separate feature task)
4. **P2-1:** Consider ORM migration (low priority)

---

## Files Requiring Changes

| File | Change Type | Priority |
|------|-------------|----------|
| `ios/DoseTap/ContentView.swift` | Remove `DoseTapCore`, use `SessionRepository` | P0 |
| `ios/Core/DoseTapCore.swift` | Archive or make stateless | P0 |
| `docs/SSOT/README.md` | Add TODO markers for roadmap items | P1 |
| `docs/SSOT/CHANGELOG.md` | Create file (broken link) | P1 |

---

*Review generated by automated audit. Manual verification recommended before merge.*
