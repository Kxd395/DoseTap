# DoseTap Hypercritical Codebase Audit

**Date:** December 23, 2025  
**Auditor:** Automated Deep Scan  
**Severity Legend:** 🔴 Critical | 🟠 High | 🟡 Medium | 🔵 Low | ⚪ Info

---

## 🔧 FIXES APPLIED (December 23, 2025)

The following critical issues have been **resolved**:

| Issue | Status | Action Taken |
|-------|--------|--------------|
| Missing APIErrors.swift | ✅ Fixed | Created `ios/Core/APIErrors.swift` with proper extraction |
| Missing APIErrorsTests.swift | ✅ Fixed | Created `Tests/DoseCoreTests/APIErrorsTests.swift` (12 tests) |
| Duplicate DoseWindowState.swift | ✅ Fixed | Deleted `ios/DoseTap/DoseWindowState.swift` |
| Duplicate OfflineQueue.swift | ✅ Fixed | Deleted `ios/DoseTap/OfflineQueue.swift` |
| Duplicate RecommendationEngine.swift | ✅ Fixed | Deleted `ios/DoseTap/RecommendationEngine.swift` |
| DoseCoreIntegration broken init | ✅ Fixed | Corrected initializers to use proper types |
| Legacy ContentView files | ✅ Fixed | Deleted 4 unused ContentView variants |
| Misplaced test files | ✅ Fixed | Deleted 5 test files from app folder |
| Empty AppDelegate.swift | ✅ Fixed | Deleted |
| Package.swift.backup | ✅ Fixed | Deleted |
| Superseded docs | ✅ Fixed | Moved 8 files to `archive/docs_superseded/` |
| .gitignore for Secrets | ✅ Fixed | Added to both root and ios/DoseTap/.gitignore |

**Test Results After Fixes:** 41 tests passing (was 29 before fixes)

---

## Executive Summary

DoseTap is an iOS/watchOS medication timing application for XYWAV with a SwiftPM-based core module. While the architectural intent is solid (clean separation, SSOT-first, local-first), the codebase suffers from **severe fragmentation, duplication, and incomplete migrations**. The project appears to have undergone multiple architectural pivots without cleanup, resulting in 3-4 parallel implementations of the same concepts.

### Overall Health Score: **4/10**

| Category | Score | Status |
|----------|-------|--------|
| Architecture | 6/10 | Core clean, app fragmented |
| Code Quality | 4/10 | Massive duplication |
| Test Coverage | 5/10 | Core tested, app untested |
| Documentation | 7/10 | Extensive but conflicting |
| Security | 3/10 | Secrets in repo history |
| Build Health | 6/10 | Builds with warnings |

---

## 🔴 CRITICAL ISSUES (Immediate Action Required)

### 1. Missing Source Files in Package.swift

**Location:** `Package.swift` lines 19, 35  
**Impact:** Build warnings, broken documentation

```
warning: 'dosetap': Invalid Source '.../ios/Core/APIErrors.swift': File not found.
warning: 'dosetap': Invalid Source '.../Tests/DoseCoreTests/APIErrorsTests.swift': File not found.
```

The `Package.swift` references files that **do not exist**:
- `ios/Core/APIErrors.swift` — Referenced but missing
- `Tests/DoseCoreTests/APIErrorsTests.swift` — Referenced but missing

**Evidence:** The `APIError` enum is actually defined inline in `ios/Core/APIClient.swift` (lines 20-70), not in a separate file.

**Fix:** Either:
1. Remove these from `Package.swift` sources array, OR
2. Extract `APIError` to its own file as documented

---

### 2. Security: Secrets in Git History

**Location:** `ios/DoseTap/Config.plist`, Git history  
**Impact:** API key compromise possible

The `.gitignore` now excludes `Config.plist` and `Secrets.swift`, but these files were **previously committed**. The WHOOP client secret may still be in Git history.

**Evidence:**
```gitignore
# .gitignore (current)
ios/DoseTap/Config.plist
ios/DoseTap/Secrets.swift
```

But `Config.plist` exists and was modified (`M ios/DoseTap/Config.plist` in git status).

**Fix:**
1. Use `git filter-branch` or BFG Repo-Cleaner to purge history
2. Rotate ALL secrets in WHOOP Developer Portal
3. Implement proper secrets injection (Xcode schemes, CI/CD env vars)

---

### 3. DoseEvent Definition Collision

**Locations:**
- `ios/DoseTapiOSApp/DataStorageService.swift:4` — `struct DoseEvent`
- `ios/DoseTapiOSApp/DoseCoreIntegration.swift:205` — `struct DoseEvent`
- `macos/DoseTapStudio/Sources/Models/Models.swift:20` — `struct DoseEvent`

**Impact:** Type ambiguity, compile errors when modules interact

Three completely different `DoseEvent` structs exist with incompatible shapes:

```swift
// DataStorageService.swift
public struct DoseEvent {
    public let id: UUID
    public let type: DoseEventType
    public let timestamp: Date
    public let metadata: [String: String]
}

// DoseCoreIntegration.swift  
public struct DoseEvent {
    public let type: DoseEventType
    public let timestamp: Date
}

// Models_Event.swift
struct Event {  // Different name, different shape
    var type: LogEvent
    var ts: Date
    var source: String
    var meta: [String:String]
}
```

**Fix:** Consolidate to a single canonical `DoseEvent` in `DoseCore` and use throughout.

---

### 4. DoseEventType Definition Collision

**Locations:**
- `ios/DoseTapiOSApp/DataStorageService.swift:18`
- `ios/DoseTapiOSApp/DoseCoreIntegration.swift:216`

Two incompatible enums with similar names:

```swift
// DataStorageService.swift
public enum DoseEventType: String, Codable {
    case dose1, dose2, snooze, skip, bathroom, lightsOut, wakeFinal
}

// DoseCoreIntegration.swift
public enum DoseEventType: String {
    case dose1, dose2, snooze, skip, bathroom, lights_out, wake_final
}
```

Note the snake_case vs camelCase inconsistency (`lightsOut` vs `lights_out`).

---

## 🟠 HIGH SEVERITY ISSUES

### 5. Duplicate Implementations Everywhere

The codebase contains **at least 3 parallel implementations** of core concepts:

| Concept | ios/Core/ | ios/DoseTap/ | ios/DoseTapiOSApp/ |
|---------|-----------|--------------|-------------------|
| DoseWindowState | ✅ Public | ✅ Duplicate (160 lines) | — |
| OfflineQueue | ✅ Actor-based | ✅ File-based (199 lines) | — |
| RecommendationEngine | ✅ 27 lines | ✅ 33 lines (identical) | — |
| TimeEngine | ✅ Public | Legacy ref | — |
| Event Models | — | Models_Event.swift | DataStorageService.swift |

**Specific duplicates:**

```
ios/Core/DoseWindowState.swift (98 lines)
ios/DoseTap/DoseWindowState.swift (160 lines) — DUPLICATE with internal visibility

ios/Core/OfflineQueue.swift (72 lines) — Actor + protocol
ios/DoseTap/OfflineQueue.swift (199 lines) — Class + Combine + file persistence

ios/Core/RecommendationEngine.swift (27 lines)
ios/DoseTap/RecommendationEngine.swift (33 lines) — Nearly identical
```

**Impact:** Changes must be made in multiple places; risk of behavioral divergence.

---

### 6. DoseCoreIntegration Uses Non-Existent Initializers

**Location:** `ios/DoseTapiOSApp/DoseCoreIntegration.swift:27-32`

```swift
self.dosingService = DosingService(
    client: APIClient(baseURL: URL(string: "https://api.dosetap.com")!),
    queue: OfflineQueue(),  // ❌ Wrong: OfflineQueue is a protocol
    limiter: EventRateLimiter()  // ❌ Wrong: Requires cooldowns parameter
)
```

**Problems:**
1. `OfflineQueue` is a **protocol**, not a struct — cannot be instantiated directly
2. `EventRateLimiter` requires `cooldowns: [String: TimeInterval]` parameter
3. `APIClient` requires a `transport` conforming to `APITransport`

**Fix:** Use correct initializers:
```swift
let transport = URLSessionTransport()
let client = APIClient(baseURL: url, transport: transport)
let queue = InMemoryOfflineQueue(isOnline: { NetworkMonitor.shared.isOnline })
let limiter = EventRateLimiter(cooldowns: ["bathroom": 60])
```

---

### 7. EventStoreProtocol Referenced But Not Defined in Core

**Location:** `ios/DoseTap/EventStoreAdapter.swift:11`

```swift
let shared: EventStoreProtocol
```

`EventStoreProtocol` is referenced but **not defined anywhere** in the searchable codebase. `JSONEventStore` is also used but undefined.

**Evidence:** `grep_search` for both terms returns only usage sites, not definitions.

---

### 8. AppDelegate.swift is Empty

**Location:** `ios/DoseTap/AppDelegate.swift`

The file exists but is completely empty. If an AppDelegate is needed for push notifications or lifecycle events, this is incomplete. If not needed, delete it.

---

### 9. TODO/FIXME Debt

**Count:** 20+ unresolved TODOs

Critical ones:
```swift
// ios/Core/OfflineQueue.swift:65
// TODO: Implement proper backoff delay when needed

// ios/DoseTap/OfflineQueue.swift:171-195
// TODO: Implement actual API call to APIClient.takeDose("dose1")
// TODO: Implement actual API call to APIClient.takeDose("dose2")
// TODO: Implement actual API call to APIClient.skipDose()
// TODO: Implement actual API call to APIClient.snoozeDose()
// TODO: Implement actual API call to APIClient.logEvent()
```

The legacy `OfflineQueue` has **no actual API integration** — all network calls are stubbed.

---

## 🟡 MEDIUM SEVERITY ISSUES

### 10. Inconsistent Visibility Modifiers

**ios/Core/** uses `public` for all types (correct for a library).  
**ios/DoseTap/** uses `internal` (default) for duplicate types.

This creates a situation where:
- UI code cannot use `DoseCore.DoseWindowConfig` properties if needed
- Duplicate internal types shadow the public ones

---

### 11. Tests Only Cover Core Module

**Test Files:**
```
Tests/DoseCoreTests/
├── APIClientTests.swift (11 tests)
├── DoseWindowEdgeTests.swift (6 tests)
├── DoseWindowStateTests.swift (7 tests)
├── EventRateLimiterTests.swift (1 test)
├── OfflineQueueTests.swift (4 tests)

Tests/DoseTapTests/
├── DoseWindowStateTests.swift (tests duplicate, not core)
```

**Coverage Gaps:**
- No integration tests
- No UI tests
- EventStoreAdapter untested
- WHOOP.swift (639 lines) completely untested
- ErrorHandler.swift (460 lines) untested
- InventoryManagement.swift (606 lines) untested

---

### 12. Multiple ContentView Files

**Location:** `ios/DoseTap/`

```
ContentView.swift          — Current (uses DoseCore)
ContentView_New.swift      — Alternative implementation
ContentView_Original.swift — Legacy
ContentView_Simple.swift   — Minimal version
```

Four different implementations of the main view. Only one is active.

---

### 13. Documentation Sprawl

**26 markdown files** in `/docs/`, many conflicting or redundant:

| File | Status | Notes |
|------|--------|-------|
| `SSOT/README.md` | ✅ Authoritative | 528 lines, current |
| `SSOT.md` | ❓ Duplicate? | Separate from SSOT folder |
| `SSOT_NAV.md` | ❓ Navigation copy | May be outdated |
| `api-documentation.md` | ⚠️ Superseded | SSOT says this is replaced |
| `button-logic-mapping.md` | ⚠️ Superseded | SSOT says this is replaced |
| `ui-ux-specifications.md` | ⚠️ Superseded | SSOT says this is replaced |
| `product-description.md` | ⚠️ Conflicting | vs `product_description.md` |
| `product-description-updated.md` | ⚠️ Conflicting | Third version |

---

### 14. Shadcn-UI MCP Server in iOS Repo

**Location:** `shadcn-ui/`

A TypeScript Model Context Protocol server is included in the repo. This appears to be tooling for AI code generation and is unrelated to the iOS app.

**Recommendation:** Move to separate repo or `.tools/` directory with clear README.

---

### 15. Archive Folder Contains Important Context

**Location:** `archive/`

Contains `CODEBASE_AUDIT_REPORT.md` marked as "inaccurate" but has valuable historical context. The audit claims issues that were supposedly fixed, but some still exist.

---

## 🔵 LOW SEVERITY ISSUES

### 16. Unused Test Warning

```swift
// Tests/DoseCoreTests/APIClientTests.swift:99
let transport = StubTransport { req in return (Data(), HTTPURLResponse()) }
// warning: initialization of immutable value 'transport' was never used
```

### 17. DoseTapApp Comment Mismatch

```swift
// File named: DoseTapApp.swift
// Comment says: DoseTapApp_Simple.swift
```

### 18. ISO8601DateFormatter Created Repeatedly

`APIClient.swift` creates new `ISO8601DateFormatter()` on every request. Should be a static constant.

### 19. Force Unwrap in Production Code

```swift
// DoseCoreIntegration.swift:27
client: APIClient(baseURL: URL(string: "https://api.dosetap.com")!)
```

---

## ⚪ RECOMMENDATIONS

### Immediate (This Week)

1. **Fix Package.swift** — Remove or create missing `APIErrors.swift` references
2. **Purge Git History** — Remove secrets from all commits
3. **Delete Duplicates** — Choose either Core or DoseTap versions, not both
4. **Define EventStoreProtocol** — In Core or delete references
5. **Fix DoseCoreIntegration** — Use correct initializers

### Short-Term (This Month)

6. **Consolidate Event Models** — Single `DoseEvent` struct in Core
7. **Delete Legacy ContentViews** — Keep only one
8. **Archive Superseded Docs** — Move deprecated docs to `archive/docs/`
9. **Add Integration Tests** — Test Core ↔ UI boundary
10. **Implement OfflineQueue API Calls** — Replace TODOs with real implementation

### Long-Term (This Quarter)

11. **Establish Module Boundaries** — Clear dependency graph:
    ```
    DoseCore (pure logic, no UI)
        ↓
    DoseTapShared (view models, observers)
        ↓
    DoseTap (iOS) / DoseTapWatch (watchOS)
    ```

12. **WHOOP Integration Audit** — 639-line file needs review for:
    - Error handling completeness
    - Token refresh reliability
    - Offline behavior

13. **SQLite Schema Migration** — Currently no versioning strategy (see SchemaEvolution.md)

14. **Accessibility Audit** — SSOT claims WCAG AAA but no code evidence

---

## File-by-File Recommendations

### Keep As-Is (Core Module ✅)
- `ios/Core/DoseWindowState.swift`
- `ios/Core/APIClient.swift`
- `ios/Core/OfflineQueue.swift`
- `ios/Core/EventRateLimiter.swift`
- `ios/Core/APIClientQueueIntegration.swift`
- All `Tests/DoseCoreTests/*.swift`

### Delete or Archive 🗑️
- `ios/DoseTap/DoseWindowState.swift` (duplicate)
- `ios/DoseTap/OfflineQueue.swift` (duplicate, incomplete)
- `ios/DoseTap/RecommendationEngine.swift` (duplicate)
- `ios/DoseTap/ContentView_New.swift`
- `ios/DoseTap/ContentView_Original.swift`
- `ios/DoseTap/ContentView_Simple.swift`
- `ios/DoseTap/DoseTapApp_Original.swift`
- `Package.swift.backup`
- All superseded docs per SSOT

### Needs Major Work 🔧
- `ios/DoseTap/ErrorHandler.swift` — 460 lines, untested
- `ios/DoseTap/WHOOP.swift` — 639 lines, untested
- `ios/DoseTap/InventoryManagement.swift` — 606 lines, untested
- `ios/DoseTapiOSApp/DoseCoreIntegration.swift` — Broken initializers
- `ios/DoseTap/EventStoreAdapter.swift` — Missing protocol definition

### Clarify Purpose ❓
- `ios/DoseTapiOSApp/` vs `ios/DoseTap/` — Which is the real app?
- `ios/DoseTapNative/`, `ios/DoseTapWorking/`, `ios/TempProject/` — Zombie directories?
- `macos/DoseTapStudio/` — Separate product or dead code?

---

## Build & Test Status

```bash
$ swift build
# ✅ Build complete (warnings only)

$ swift test
# ✅ 29 tests passed (0 failures)
```

The **Core module is healthy**. The **App layer is the problem**.

---

## Conclusion

DoseTap has a solid foundation in `DoseCore` with proper testing and clean architecture. However, the application layer (`ios/DoseTap/`, `ios/DoseTapiOSApp/`) is in disarray from apparent migration attempts that were never completed.

**Priority 1:** Establish a single source of truth for the application code, not just documentation.

**Priority 2:** Delete everything that isn't actively used or clearly planned.

**Priority 3:** Write tests for the remaining 1,700+ lines of untested application code.

---

*Audit generated by comprehensive file analysis. For questions, refer to the linked code locations.*
