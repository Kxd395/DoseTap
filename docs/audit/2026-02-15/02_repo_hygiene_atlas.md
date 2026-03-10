# Phase 1 — Repo Hygiene, Build Graph & Architecture Atlas

**Date:** 2026-02-15
**Scope:** File tree analysis, build inclusion map, duplicate detection, architecture atlas

---

## Repository Overview

| Metric | Value |
|--------|-------|
| Git-tracked files | 428 |
| Total LOC (all languages) | ~97,892 |
| Swift files (tracked) | 173 |
| Swift LOC | ~58,591 |
| Markdown files | 161 |
| Markdown LOC | ~44,802 |
| SwiftPM targets | 2 (DoseCore library, DoseCoreTests) |
| Xcode targets | DoseTap iOS app + staging + UITest (via .xcodeproj) |
| CI workflows | 3 (ci.yml, ci-swift.yml, ci-docs.yml) |

### File Distribution by Area

| Area | Tracked Files | LOC | Role |
|------|---------------|-----|------|
| `ios/Core/` | 24 | 5,612 | Platform-free domain logic (SwiftPM) |
| `Tests/DoseCoreTests/` | 30 | 6,551 | SwiftPM unit tests |
| `ios/DoseTap/` | 110 | ~45K | SwiftUI app (Xcode project) |
| `ios/DoseTapTests/` | 11 | ~2K | Xcode test target |
| `docs/` | 121 | ~44K | SSOT, archive, prompts, reviews |
| `tools/` | 18 | ~1K | Build/check scripts |
| `.github/` | 24 | — | CI workflows, agents, prompts |
| `watchos/` | 20 | ~1K | watchOS companion app |
| `macos/DoseTapStudio/` | 18 | ~2K | macOS companion app |
| `specs/` | 10 | — | Feature specifications |
| `.specify/` | 15 | — | Spec Kit framework |
| `dosetap-repo-audit/` | 9 | — | Claude audit skill |

---

## Architecture Atlas

```
DoseTap/
├── Package.swift ─────────────── Root SwiftPM manifest
│   ├── DoseCore (library) ────── ios/Core/ (24 files, 5,612 LOC)
│   └── DoseCoreTests ─────────── Tests/DoseCoreTests/ (30 files, 6,551 LOC)
│
├── ios/DoseTap.xcodeproj ─────── Xcode project (iOS app)
│   ├── DoseTap (app target) ──── ios/DoseTap/ (86 .swift files)
│   │   ├── Storage/ ──────────── EventStorage cluster, SessionRepository
│   │   ├── Views/ ────────────── Dashboard, Timeline, History, etc.
│   │   ├── FullApp/ ──────────── SetupWizard, DoseModels, Keychain
│   │   ├── Security/ ─────────── DatabaseSecurity, InputValidator
│   │   ├── Services/ ─────────── HealthKitProviding
│   │   ├── Theme/ ────────────── AppTheme
│   │   ├── Export/ ───────────── CSVExporter (CoreData variant)
│   │   ├── Persistence/ ──────── FetchHelpers, PersistentStore
│   │   └── Foundation/ ───────── DevelopmentHelper, TimeZoneMonitor
│   ├── DoseTapTests (test target) ── ios/DoseTapTests/ (11 files)
│   └── Staging / UITest targets
│
├── watchos/DoseTapWatch/ ─────── watchOS companion (20 files)
├── macos/DoseTapStudio/ ──────── macOS companion (18 tracked files)
│
├── docs/
│   ├── SSOT/ ─────────────────── Source of truth (6 files)
│   │   ├── README.md ─────────── Master spec (states, thresholds, errors)
│   │   ├── constants.json ────── Machine-readable constants
│   │   ├── navigation.md ─────── Screen navigation spec
│   │   ├── contracts/ ────────── DataDictionary, OpenAPI, encryption
│   │   └── encryption-at-rest.md
│   ├── prompt/ ───────────────── Audit prompt toolkit (8 files)
│   ├── review/ ───────────────── Review docs (7 files)
│   └── archive/ ──────────────── Historical audits (72 files)
│
├── .github/
│   ├── workflows/ ────────────── CI: swift, docs, combined
│   ├── agents/ ───────────────── Spec Kit agent files (10)
│   └── prompts/ ──────────────── Spec Kit prompt files (10)
│
├── tools/ ────────────────────── Scripts (18 files)
├── .specify/ ─────────────────── Spec Kit framework (15 files)
├── specs/ ────────────────────── Feature specs (10 files)
└── dosetap-repo-audit/ ───────── Claude audit skill (9 files)
```

### Core Module Dependency Graph

```
DoseCore (platform-free, no UIKit/SwiftUI)
├── DoseWindowState ←── DoseWindowConfig, DoseWindowContext, Phase
├── APIClient ←── URLSession transport abstraction
├── APIErrors ←── APIErrorMapper, DoseAPIError enum
├── OfflineQueue ←── Actor, Codable queue persistence
├── APIClientQueueIntegration ←── DosingService (facade: API + queue + limiter)
├── EventRateLimiter ←── Actor, cooldown enforcement
├── TimeEngine ←── Sleep/wake cycle calculations
├── SessionKey ←── Date-based session partitioning
├── SleepPlan ←── Sleep schedule model
├── MorningCheckIn ←── Check-in model + validation
├── DosingModels ←── Dosing amount, medication types
├── MedicationConfig ←── Medication configuration
├── RecommendationEngine ←── Dose timing recommendations
├── CSVExporter ←── Platform-free export (DoseExportRecord)
├── DiagnosticLogger ←── os.Logger wrapper
├── DiagnosticEvent ←── Structured diagnostic events
├── DataRedactor ←── PII/PHI redaction
├── CertificatePinning ←── TLS pin validation
├── DoseUndoManager ←── Undo stack for dose actions
├── EventStore ←── In-memory event store
├── SleepEvent ←── Sleep event model
├── UnifiedSleepSession ←── Cross-platform session model
├── TimeIntervalMath ←── Time arithmetic utilities
└── DoseTapCore ←── Module facade / re-exports
```

---

## Findings

### HYG-001 (P1): `.cache_ggshield` tracked in git

- **File:** `.cache_ggshield` (root)
- **Issue:** Contains ggshield scan cache with a secret hash. Should be in `.gitignore`, not tracked.
- **Evidence:** `git ls-files .cache_ggshield` returns the file; contents show `last_found_secrets` JSON.
- **Fix:** Add `.cache_ggshield` to `.gitignore` and `git rm --cached .cache_ggshield`.

### HYG-002 (P2): Duplicate `CSVExporter.swift` (different implementations)

- **Locations:**
  - `ios/Core/CSVExporter.swift` (176 LOC) — Platform-free, `DoseExportRecord` value type
  - `ios/DoseTap/Export/CSVExporter.swift` (48 LOC) — CoreData-dependent, `NSManagedObjectContext`
- **Issue:** Same filename, different implementations. Confusing for contributors.
- **Fix:** Rename app version to `EventCSVExporter.swift` or consolidate.

### HYG-003 (P2): Duplicate `TimeIntervalMath.swift` (diverged copies)

- **Locations:**
  - `ios/Core/TimeIntervalMath.swift` (54 LOC) — Canonical, platform-free
  - `ios/DoseTap/TimeIntervalMath.swift` (46 LOC) — App copy, different content
- **Issue:** Two diverged copies of time math utilities. Bug risk from drift.
- **Fix:** Delete app copy; import from DoseCore instead.

### HYG-004 (P2): Orphan `ios/DoseTap/Package.swift`

- **File:** `ios/DoseTap/Package.swift`
- **Issue:** Defines a second SwiftPM package inside the Xcode app directory with `path: "."` targeting all of `ios/DoseTap/`. Conflicts with root `Package.swift`. Likely vestigial from an earlier SPM experiment.
- **Fix:** Remove or gitignore. The root Package.swift is authoritative.

### HYG-005 (P2): docs/archive bloat (72 tracked files)

- **Directory:** `docs/archive/` — 72 tracked files, mostly from 2025-12 audit sessions
- **Issue:** Historical ballast. These are audit logs, not living documentation.
- **Fix:** Consider moving to a separate `archive` branch or trimming to essentials.

### HYG-006 (P3): Untracked `archive/` directory (75 files on disk, 0 tracked)

- **Directory:** `archive/` (root level)
- **Issue:** Local-only files, no git backup. May contain important historical context.
- **Assessment:** Low risk — appears intentional. Note for awareness.

### HYG-007 (P3): `shadcn-ui/` directory (0 tracked files, abandoned)

- **Directory:** `shadcn-ui/` — config files on disk, nothing tracked
- **Issue:** Abandoned web UI experiment. Clutter.
- **Fix:** Remove directory or `.gitignore` it explicitly.

### HYG-008 (P3): SwiftLint includes non-existent `ios/AppMinimal`

- **File:** `.swiftlint.yml` line `included: - ios/AppMinimal`
- **Issue:** This directory doesn't exist. SwiftLint silently ignores it, but it's misleading.
- **Fix:** Remove the entry from `.swiftlint.yml`.

---

## Build Graph Verification

| Target | Build Tool | Status |
|--------|-----------|--------|
| DoseCore (SwiftPM) | `swift build -q` | ✅ Green |
| DoseCoreTests (SwiftPM) | `swift test -q` | ✅ 525 pass |
| DoseTap (Xcode app) | xcodeproj | ✅ Last verified |
| watchOS | xcodeproj | ⚠️ Not independently verified |
| macOS DoseTapStudio | SwiftPM | ⚠️ Not independently verified |

---

## Stop Condition Assessment

No P0 findings in this phase. All findings are P1-P3 hygiene issues.

**Proceeding to Phase 2.**
