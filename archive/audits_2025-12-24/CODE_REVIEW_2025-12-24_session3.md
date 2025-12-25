# Code Review: DoseTap Safety & Correctness Audit

**Date:** 2025-12-24  
**Verified on commit:** `3158dea9e89d023490b528cb8485cb962d27da90`  
**Supersedes:** `docs/CODE_REVIEW_2025-12-24_session2.md` (contained pre-fix state)  
**Reviewer:** Automated Code Audit  
**Focus:** Two-sources-of-truth risk, persistence integrity, timing edge cases, dose safety

---

## Readiness Score: 🟢 90/100

| Category | Score | Notes |
| -------- | ----- | ----- |
| State Management | 95 | P0 fixed: DoseTapCore delegates to SessionRepository |
| Persistence | 90 | SQLite uses transactions for multi-table operations |
| Notifications | 95 | Session deletion cancels pending notifications correctly |
| Export/Support | 85 | PII minimized but honest disclaimer "not guaranteed zero-PII" |
| Test Coverage | 90 | 207 SwiftPM + 13 Xcode tests, P0-fix regression tests exist |

---

## P0 Status: ✅ FIXED

### Evidence: No @Published dose state in DoseTapCore

```bash
$ grep -n "@Published" ios/Core/DoseTapCore.swift
# OUTPUT: (none)
```

### Evidence: DoseTapCore properties delegate to SessionRepository

```bash
$ grep -A2 "public var dose1Time" ios/Core/DoseTapCore.swift
    public var dose1Time: Date? {
        get { sessionRepository?.dose1Time }
        set { 

$ grep -A2 "public var dose2Time" ios/Core/DoseTapCore.swift
    public var dose2Time: Date? {
        get { sessionRepository?.dose2Time }
        set {

$ grep -A2 "public var snoozeCount" ios/Core/DoseTapCore.swift
    public var snoozeCount: Int {
        get { sessionRepository?.snoozeCount ?? 0 }
        set { 

$ grep -A2 "public var isSkipped" ios/Core/DoseTapCore.swift
    public var isSkipped: Bool {
        get { sessionRepository?.dose2Skipped ?? false }
        set {
```

### Evidence: ContentView wires DoseTapCore to SessionRepository

```bash
$ grep -A1 "P0 FIX" ios/DoseTap/ContentView.swift
            // P0 FIX: Wire DoseTapCore to SessionRepository (single source of truth)
            // All state reads/writes now flow through SessionRepository
            core.setSessionRepository(sessionRepo)
```

### Evidence: Tests pass

```
$ swift test -q
Executed 207 tests, with 0 failures

$ xcodebuild test -only-testing:DoseTapTests
** TEST SUCCEEDED **
Test suite 'SessionRepositoryTests' - 12 tests passed
Test case 'DoseTapTests/example()' - passed
```

---

## Architecture After Fix

```
┌─────────────────────────────────────────────────────────────────┐
│                        ContentView                               │
│  @StateObject core = DoseTapCore()                              │
│  @StateObject sessionRepo = SessionRepository.shared            │
│                                                                  │
│  .onAppear { core.setSessionRepository(sessionRepo) }           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DoseTapCore                                 │
│  (No @Published vars - all computed from sessionRepository)     │
│                                                                  │
│  var dose1Time: Date? { sessionRepository?.dose1Time }          │
│  var currentStatus: DoseStatus { /* computed from repo */ }     │
│                                                                  │
│  func takeDose() { sessionRepository?.setDose1Time(now) }       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   SessionRepository                              │
│  (Single Source of Truth - @Published vars here)                │
│                                                                  │
│  @Published dose1Time: Date?                                    │
│  @Published dose2Time: Date?                                    │
│  @Published snoozeCount: Int                                    │
│  @Published dose2Skipped: Bool                                  │
│                                                                  │
│  let sessionDidChange = PassthroughSubject<Void, Never>()       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      EventStorage                                │
│  (SQLite persistence layer)                                     │
│                                                                  │
│  current_session table                                          │
│  dose_events table                                              │
│  sleep_events table                                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Remaining Findings

### P1-1: SSOT Lint Has 25 Warnings

**Status:** Known - non-blocking  
**Details:** Roadmap items (component IDs, API endpoints) not yet implemented.  
**Fix:** Mark items as `TODO` or implement them.

### P1-2: SSOT Contradictions (documentation bugs)

**A) `didMigrateToCoreData` naming**  
Line 1011 references CoreData but app uses SQLite. Rename to `didMigrateToSQLite`.

**B) `target_interval_minutes: 150-240 range` comment**  
Line 895 conflicts with discrete targets `{165, 180, 195, 210, 225}`.  
Fix: Change comment to `// 165 default, must be one of {165,180,195,210,225}`.

**C) API Contract marked as implemented but uses mock**  
API endpoints documented but `DoseTapCore` uses `MockAPITransport`.  
Fix: Add `🔄 PLANNED` marker to API section.

### P1-3: Missing Medication Logger

**Status:** Not implemented  
**Evidence:** No `medication_events` table, no medication picker UI.  
**Fix:** Implement medication logger feature (separate task).

---

## Definition of Done Checklist

| Criterion | Status | Evidence |
| --------- | ------ | -------- |
| No stale UI state sources remain | ✅ PASS | DoseTapCore delegates to SessionRepository |
| All safety critical dose flows tested | ✅ PASS | SessionRepositoryTests cover delete/ghost dose |
| SQLite operations transactional where needed | ✅ PASS | `deleteSession()` uses BEGIN/COMMIT |
| Notifications cannot fire for deleted sessions | ✅ PASS | `deleteSession()` calls `cancelPendingNotifications()` |
| Export and support bundles safe and truthful | ✅ PASS | PII minimized, honest disclaimer |

---

## Files Changed in P0 Fix

| File | Change |
| ---- | ------ |
| `ios/Core/DoseTapCore.swift` | Removed @Published vars, added delegation via DoseTapSessionRepository protocol |
| `ios/DoseTap/Storage/SessionRepository.swift` | Conforms to DoseTapSessionRepository |
| `ios/DoseTap/ContentView.swift` | Calls `core.setSessionRepository(sessionRepo)` on appear |

---

*Review verified on commit 3158dea. Manual verification recommended before release.*
