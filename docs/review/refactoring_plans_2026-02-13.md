# Refactoring Plans — 2026-02-13

Evidence-based plans derived from static analysis of `004-dosing-amount-model` branch at `e3cfbe2`.

---

## 1. FullApp Safe Deletion Matrix

**18 files total** in `ios/DoseTap/FullApp/`. 7 compiled, 11 on-disk-only.

### 11 files NOT in Compile Sources — safe to delete immediately

These exist on disk but have **zero** pbxproj Sources-phase entries. Deleting them + removing their PBXFileReference/group entries is low compile-risk for app builds.

| File | Lines | Status | Notes |
|------|-------|--------|-------|
| `DashboardView.swift` | — | ✅ DELETE | Superseded by `Views/Dashboard/DashboardViews.swift` |
| `DataExportService.swift` | — | ✅ DELETE | Not compiled, no external refs |
| `DataStorageService.swift` | — | ✅ DELETE | Not compiled. Has file ref in pbxproj but not in Sources |
| `HealthIntegrationService.swift` | — | ✅ DELETE | Not compiled |
| `HealthKitManager.swift` | — | ✅ DELETE | Not compiled. `HealthKitService.swift` is the live version |
| `InventoryService.swift` | — | ✅ DELETE | Not compiled |
| `QuickLogPanel.swift` | — | ✅ DELETE | Not compiled |
| `SQLiteStorage.swift` | — | ✅ DELETE | Not compiled. `EventStorage` is the live storage layer |
| `TimelineView.swift` | — | ✅ DELETE | Not compiled. `Views/Timeline/TimelineReviewViews.swift` is live |
| `TonightView.swift` | — | ✅ DELETE | Not compiled. `ContentView.swift:399` defines `LegacyTonightView` independently |
| `UserConfigurationManager.swift` | — | ✅ DELETE | Not compiled |

### 7 files IN Compile Sources — disposition per file

| File | External Refs | Verdict | Dependency Detail |
|------|--------------|---------|-------------------|
| **SetupWizardService.swift** | 5 (2 in DoseTapApp, 3 in tests) | 🔴 KEEP | `DoseTapApp.swift:12` reads `setupCompletedKey`; `:211` reads it again. 3 test cases in `DoseTapTests.swift`. |
| **SetupWizardView.swift** | 1 | 🔴 KEEP | `DoseTapApp.swift:81` instantiates it. |
| **KeychainHelper.swift** | 27+ | 🔴 KEEP | `SecureConfig.swift:73,:128,:136`, `WHOOP.swift:53,56,58,64,67,69,76,84,86,103,105,111,112,130,131`, `legacy/WHOOP.swift:49,52,54,60,63,65,72,80,82`. Deeply wired. |
| **DoseModels.swift** | 3 | 🔴 KEEP | `SessionRepository.swift:1155,1157` uses `SQLiteStoredMorningCheckIn`. `MorningCheckInView.swift:302,369` constructs it. |
| **UIUtils.swift** | 0 outside FullApp | 🟡 PROBE | Defines `ShareSheet` + `ActivityViewController`. No non-FullApp compiled file references either type. `SupportBundleExport.swift` has its own `ActivityViewController` but is also NOT compiled. Safe to try removing from Sources → build test. |
| **DoseCoreIntegration.swift** | 0 | 🟡 PROBE | No external references found. Compiled but possibly dead. Remove from Sources → build test. |
| **EnhancedNotificationService.swift** | 0 | 🟡 PROBE | No external references found. Compiled but possibly dead. Remove from Sources → build test. |

### Recommended commit sequence

```
Commit 1: Delete 11 uncompiled files + clean pbxproj file refs
          → xcodebuild verify
Commit 2: Remove UIUtils.swift from Sources phase
          → xcodebuild verify (if fails, revert)
Commit 3: Remove DoseCoreIntegration.swift from Sources phase
          → xcodebuild verify
Commit 4: Remove EnhancedNotificationService.swift from Sources phase
          → xcodebuild verify
```

**Do NOT touch**: SetupWizardService, SetupWizardView, KeychainHelper, DoseModels until their consumers are migrated out of FullApp/.

### legacy/ directory (26 files)

**Zero** pbxproj Sources-phase entries. Entire directory is safe to delete in one commit.
Caveat: `legacy/WHOOP.swift` references `KeychainHelper.shared` (27 refs) but since it's not compiled, this is a comment-only concern.

Tooling caveat: local project-maintenance scripts still reference some `FullApp`/legacy file names. Pruning those files should include a follow-up script cleanup pass (`ios/rebuild_project.py`, `ios/fix_all_missing_files.py`, `ios/clean_project.py`) to avoid stale automation behavior.

---

## 2. print() Migration Patch Plan

### Current state

- **96 `print()` matches** with the planned CI regex scope (`ios/Core` + `ios/DoseTap`, excluding FullApp/legacy/DevelopmentHelper)
- Of those, **86 are executable prints in 19 runtime files** after excluding `Secrets.template.swift` and debug-wrapper helpers in `Security/SecureLogger.swift`
- **CI enforcement**: only `ios/Core/` (pre-commit hook check #2 + `ci-swift.yml:116`)
- **Hard Rule #4**: "No `print()` in production code. Use `os.Logger` with `OSLogPrivacy` annotations."
- **20 files** already use `os.Logger` with subsystem `"com.dosetap.app"`

### Top 5 highest-risk files (ordered by data-leak severity × count)

| # | File | print() count | Risk | Has Logger? |
|---|------|:---:|------|:-----------:|
| 1 | `AlarmService.swift` | 18 | 🔴 Leaks dose timing, notification schedule, snooze count | ❌ |
| 2 | `HealthKitService.swift` | 8 | 🔴 Leaks health authorization status, TTFW data | ❌ |
| 3 | `DosingAmountSchema.swift` | 7 | 🟡 Leaks schema migration state, dose data | ❌ |
| 4 | `DevelopmentHelper.swift` | 7 | 🟡 Debug-only intent but not `#if DEBUG` gated | ❌ |
| 5 | `DoseTapApp.swift` | 6 | 🟡 Leaks session lifecycle, setup state | ❌ |

Remaining 15 files: `WHOOP.swift` (5), `SettingsView.swift` (5), `EncryptedEventStorage.swift` (5), `URLRouter.swift` (4), `UndoSnackbarView.swift` (4), `AnalyticsService.swift` (4), `UndoStateManager.swift` (3), `TimeZoneMonitor.swift` (3), `SecureLogger.swift` (3), `PersistentStore.swift` (3), `FlicButtonService.swift` (3), `UserSettingsManager.swift` (2), `PreSleepLogView.swift` (2), `TimeIntervalMath.swift` (1), `SecureConfig.swift` (1).

### Migration pattern

Every file gets the same treatment:

```swift
// Add at top of file (if not already present):
import os.log

// Add inside class/struct (or file-level for free functions):
private let logger = Logger(subsystem: "com.dosetap.app", category: "AlarmService")

// Replace each print():
// BEFORE: print("⚠️ AlarmService: Failed to configure audio session: \(error)")
// AFTER:  logger.warning("Failed to configure audio session: \(error.localizedDescription, privacy: .public)")
```

**Logger level mapping**:
| print() emoji/prefix | Logger level |
|---|---|
| `✅` / success | `.info` |
| `📅` / scheduled | `.info` |
| `⚠️` / warning | `.warning` |
| `❌` / error/failure | `.error` |
| `🔗` / routing | `.debug` |
| `🔕` / cancelled | `.info` |
| `🔄` / mock/debug | `.debug` (wrap in `#if DEBUG`) |

**Privacy annotations** (per SSOT):
- Dose times, session IDs, health data → `.private`
- Error descriptions, status codes → `.public`
- File paths, URLs → `.private`
- Counts (snooze count, event count) → `.public`

### CI enforcement expansion

**Phase 1** (this PR): Migrate top 5 files and add visibility-first CI without self-blocking.

Pre-commit hook change (`.githooks/pre-commit`, check #2):

```bash
# BEFORE (blocking):
PRINT_VIOLATIONS=$(rg -n '\bprint\s*\(' ios/Core --glob '*.swift' || true)

# AFTER PHASE 1A (keep blocking scope narrow, add audit-only report):
PRINT_VIOLATIONS_CORE=$(rg -n '\bprint\s*\(' ios/Core --glob '*.swift' || true)
PRINT_VIOLATIONS_APP=$(rg -n '\bprint\s*\(' ios/DoseTap --glob '*.swift' \
  --glob '!ios/DoseTap/FullApp/*' \
  --glob '!ios/DoseTap/legacy/*' \
  --glob '!ios/DoseTap/Foundation/DevelopmentHelper.swift' \
  --glob '!ios/DoseTap/Security/SecureLogger.swift' \
  --glob '!ios/DoseTap/Secrets.template.swift' \
  || true)
# block only on Core during migration window
if [ -n "$PRINT_VIOLATIONS_CORE" ]; then exit 1; fi
# print app violations as advisory until phase 2
if [ -n "$PRINT_VIOLATIONS_APP" ]; then printf "%s\n" "$PRINT_VIOLATIONS_APP"; fi
```

CI workflow change (`.github/workflows/ci-swift.yml:116`):
```yaml
# PHASE 1A:
# - keep existing blocking check for ios/Core
# - add a separate non-blocking app print inventory step (same exclusions as above)
```

**Phase 1B** (after top-5 migration): optionally enforce app print-ban only for migrated files by explicit path allowlist.
**Phase 2** (follow-up): migrate remaining files, then make full app scope blocking and remove temporary exclusions as FullApp/legacy are pruned.

### Recommended commit sequence

```
Commit 1: AlarmService.swift — add Logger, replace 18 print() calls
Commit 2: HealthKitService.swift — add Logger, replace 8 print() calls
Commit 3: DosingAmountSchema.swift — add Logger, replace 7 print() calls
Commit 4: DevelopmentHelper.swift — wrap in #if DEBUG, add Logger for non-debug paths
Commit 5: DoseTapApp.swift — add Logger, replace 6 print() calls
Commit 6: Add non-blocking app print inventory to CI/pre-commit (prevents blind regressions)
Commit 7: Optional narrow blocking scope for the 5 migrated files
Commit 8: Full app-scope blocking after remaining migrations land
```

Each commit < 100 lines changed. Each passes `swift build -q` + `xcodebuild`.

---

## 3. EventStorage Split Plan

### Current structure (4,964 lines)

```
EventStorage.swift
├── Lines 1–17       Imports, logger                              (17 lines)
├── Lines 18–69      Class decl, properties, init                 (52 lines)
├── Lines 70–328     Database Setup (open, createTables/schema)   (259 lines)
├── Lines 329–700    Migrations                                   (372 lines)
│   ├── 329–375      Event type normalization                     (47)
│   ├── 376–460      Session ID UUID migration                    (85)
│   ├── 461–495      Deduplication                                (35)
│   └── 496–700      Session ID backfill + diagnostics            (205)
├── Lines 700–937    Session date calculation + utilities          (238 lines)
├── Lines 938–1434   Sleep + Dose CRUD                            (497 lines)
│   ├── 938–1133     Sleep event operations                       (196)
│   ├── 1134–1190    Dose event operations                        (57)
│   ├── 1191–1264    Undo support                                 (74)
│   └── 1265–1434    Time editing (manual entry)                  (170)
├── Lines 1435–2887  Session state + PreSleep + CheckIn ops       (1,453 lines) ← LARGEST
│   ├── 1435–1930    Current session state (start/close/load/update)
│   └── 1931–2887    PreSleep logs, morning check-ins, clear/delete ops
├── Lines 2888–3186  ContentView-required methods                 (299 lines)
├── Lines 3187–3303  Dose event type helpers                      (117 lines)
├── Lines 3304–3437  Utility methods (fetch/export helpers)       (134 lines)
├── Lines 3438–3649  Medication event operations                  (212 lines)
├── Lines 3650–3688  SupportBundleExporter struct                 (39 lines)
├── Lines 3689–4536  Data model types (12 structs)                (848 lines) ← MODELS
│   ├── EventRecord, StoredPreSleepLog, StoredCheckInSubmission
│   ├── PreSleepLog, CloudKitTombstone, StoredSleepEvent
│   ├── StoredDoseLog, SessionSummary, StoredMorningCheckIn
│   └── PreSleepLogAnswers (450 lines! — nested enums for questions)
└── Lines 4537–4964  EventStore protocol conformance extension    (428 lines)
```

### Blocker: singleton constructor prevents integration testing

```swift
// Current (line 57):
private init() {
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    dbPath = documentsPath.appendingPathComponent("dosetap_events.sqlite").path
    // ...
}
```

Must add injectable init **before** writing integration tests:

```swift
// New (Commit 0 of the split):
public init(dbPath: String) {
    self.dbPath = dbPath
    openDatabase()
    createTables()
    storageLog.info("EventStorage initialized at: \(self.dbPath)")
}

private convenience init() {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    self.init(dbPath: docs.appendingPathComponent("dosetap_events.sqlite").path)
}

/// In-memory instance for testing only
#if DEBUG
public static func inMemory() -> EventStorage {
    return EventStorage(dbPath: ":memory:")
}
#endif
```

### Split plan — 6 commits

**Commit 0: Injectable init + split preflight** (~30–60 lines changed)
- Add `public init(dbPath:)`, make existing `init()` call it
- Add `#if DEBUG static func inMemory()` factory
- Preflight for multi-file extensions: relax access where required (`private` → `fileprivate`/`internal`) for members used by extracted methods, or keep thin wrapper methods in `EventStorage.swift` that delegate to extracted helpers
- File: `EventStorage.swift`
- Verify: `swift build -q`, `xcodebuild`

**Commit 1: Extract data models → `Storage/StorageModels.swift`** (~848 lines moved)
- Move: `EventRecord`, `StoredPreSleepLog`, `StoredCheckInSubmission`, `PreSleepLog`, `CloudKitTombstone`, `StoredSleepEvent`, `StoredDoseLog`, `SessionSummary`, `StoredMorningCheckIn`, `PreSleepLogAnswers` (+ all nested enums)
- Move: `SupportBundleExporter` struct (39 lines)
- Move: `CurrentSessionState` struct (currently nested in class — extract to file-level)
- Also move `StoredMedicationEntry` if it exists (check)
- Net: `EventStorage.swift` drops to ~4,077 lines
- Verify: `swift build -q`, `xcodebuild`, `swift test -q`

**Commit 2: Extract schema + migrations → `Storage/EventStorage+Schema.swift`** (~631 lines moved)
- Move: `createTables()` (lines 104–290), `migrateDatabase()` (line 291+), all migration methods through line 700
- These become an `extension EventStorage { }` in the new file
- Requires preflight from Commit 0: these methods currently depend on members declared `private` in `EventStorage.swift`
- Net: `EventStorage.swift` drops to ~3,446 lines
- Verify: build

**Commit 3: Extract EventStore protocol conformance → `Storage/EventStorage+EventStore.swift`** (~428 lines moved)
- Move: lines 4537–4964, the entire `extension EventStorage: EventStore { ... }`
- Clean cut — it's already an extension block
- Net: `EventStorage.swift` drops to ~3,018 lines
- Verify: build + iOS app tests (`xcodebuild test ...`) for SessionRepository/EventStorage paths

**Commit 4: Extract medication + export ops → `Storage/EventStorage+Exports.swift`** (~346 lines moved)
- Move: Medication Event Operations (lines 3438–3649, 212 lines)
- Move: `exportToCSV()`, `exportCombinedData()`, `exportSleepEventsToCSV()`, `exportDoseEventsToCSV()` (~134 lines from utility section)
- Net: `EventStorage.swift` drops to ~2,672 lines
- Verify: build

**Commit 5: Extract session lifecycle → `Storage/EventStorage+Session.swift`** (~800+ lines moved)
- Move: Session state methods (lines 1435–1930): `startSession`, `closeSession`, `closeHistoricalSession`, `upsertSleepSession`, `updateCurrentSession`, `loadCurrentSessionState`, `loadCurrentSession`, `updateTerminalState`
- Move: Session date utilities (lines 742–937): `currentSessionDate`, `getAllSessionDates`, `fetchSessionId`, `filterExistingSessionDates`
- Net: `EventStorage.swift` drops to ~1,872 lines
- Verify: build + full test suite

### Final file map (target state)

```
ios/DoseTap/Storage/
├── StorageModels.swift              ~900 lines  (all data types)
├── EventStorage.swift               ~1,870 lines (core: init, sleep/dose CRUD, undo, pre-sleep, check-in, delete, query)
├── EventStorage+Schema.swift        ~630 lines  (createTables, all migrations)
├── EventStorage+Session.swift       ~800 lines  (session lifecycle + date utils)
├── EventStorage+EventStore.swift    ~430 lines  (protocol conformance)
├── EventStorage+Exports.swift       ~350 lines  (CSV export, medication ops)
├── SessionRepository.swift          ~1,715 lines (unchanged)
└── DosingAmountSchema.swift         (unchanged)
```

Core file lands at ~1,870 lines (under the 2,000-line warning threshold). Further splitting the pre-sleep/check-in CRUD (~957 lines in the 1931–2887 range) into `EventStorage+CheckIns.swift` would bring it under 1,000.

### Integration test plan (post-split)

Once `init(dbPath:)` exists:

```swift
// ios/DoseTapTests/EventStorageIntegrationTests.swift
@MainActor
final class EventStorageIntegrationTests: XCTestCase {
    var storage: EventStorage!

    override func setUp() {
        storage = EventStorage(dbPath: ":memory:")
    }

    func test_fetchRecentSessionsLocal_returns_historical_sessions() { ... }
    func test_fetchDoseLog_fallback_to_dose_events() { ... }
    func test_startSession_closeSession_roundtrip() { ... }
    func test_saveDose1_dose2_creates_paired_records() { ... }
}
```

Note: these are app-target integration tests, not SwiftPM `DoseCoreTests`. `EventStorage` lives under `ios/DoseTap/Storage`, so `swift test` alone will not execute these.

---

## Execution Order

```
Branch: refactor/print-to-logger
  Commits 1–6 from §2

Branch: refactor/fullapp-prune  
  Commits 1–4 from §1

Branch: refactor/split-event-storage
  Commits 0–5 from §3
  + Integration tests
```

Print migration first (mechanical, unblocks CI parity).
FullApp prune second (reduces compile surface before the big split).
EventStorage split last (most complex, benefits from smaller compile surface).
