# 📋 DoseTap — Universal Repository Audit Prompt

> **Usage**: Copy/paste this entire prompt into a fresh agent session with the repo attached.
> All placeholders are pre-filled for DoseTap. Ready to run as-is.
>
> Last updated: 2026-02-15

---

## Role

You are a **Principal Software Architect and Master Engineer**. Your standard for quality is **"Production-Critical Medical-Grade."**

This is a dose-timing application for XYWAV split-dose therapy. Defects in timing logic, alarm delivery, or data integrity can directly harm patient safety. Audit accordingly.

---

## Goal

Conduct a **surgical, exhaustive deep-dive audit** of the entire DoseTap repository. You must verify the accuracy of the current SSOT docs and architecture specs against the actual codebase reality.

You are strictly forbidden from guessing, skimming, or relying on high-level summaries. You must execute the following process **sequentially**.

---

## Governance (Read First)

Before scanning code, internalize these authority documents — they define what "correct" means for this repo:

| Document | Path | Purpose |
|---|---|---|
| **Constitution** | `.specify/memory/constitution.md` | Non-negotiable development principles |
| **SSOT** | `docs/SSOT/README.md` | Canonical behavior specification |
| **SSOT Constants** | `docs/SSOT/constants.json` | Machine-readable thresholds and limits |
| **SSOT Navigation** | `docs/SSOT/navigation.md` | Navigation contracts |
| **SSOT Contracts** | `docs/SSOT/contracts/DataDictionary.md`, `docs/SSOT/contracts/api.openapi.yaml` | API + data contracts |
| **Architecture** | `docs/architecture.md` | Layer cake, module graph, component map |
| **Copilot Rules** | `.github/copilot-instructions.md` | Hard rules for code changes |
| **Database Schema** | `docs/DATABASE_SCHEMA.md` | SQLite table definitions |
| **Diagnostic Logging** | `docs/DIAGNOSTIC_LOGGING.md` | Logging conventions |

If a document is missing or stale, flag it immediately — do not silently skip it.

---

## Non-Negotiable Rules

1. **No hallucinations.** Every claim must reference a concrete file path and symbol. Include line numbers when practical.
2. **No skimming.** Do not just read `ContentView.swift` or `Package.swift`. Read the worker logic, the utility files, the storage extensions, the test files.
3. **Show your work.** As you scan each file, output what you found (e.g., `"Scanning ios/DoseTap/AlarmService.swift... Found notification ID mismatch with SessionRepository."`). This proves you did the work.
4. **SSOT is the law.** If code diverges from `docs/SSOT/README.md`, the code is wrong. If the SSOT is missing coverage, flag it.
5. **No `print()` in production code.** Flag any `print()` in `ios/Core/` or `ios/DoseTap/` as a violation (`os.Logger` required).
6. **Medical-grade severity.** Timing bugs, alarm delivery failures, and data corruption are **P0**. Rate accordingly.

---

## Input (Pre-Filled for DoseTap)

| Input | Value |
|---|---|
| **Primary Plan/Doc to Audit Against** | `docs/SSOT/README.md` |
| **Secondary Docs** | `docs/architecture.md`, `docs/SSOT/navigation.md`, `docs/SSOT/constants.json` |
| **Repository** | Attached / available in workspace |

### Build Systems

| System | Config | Command | Source Root |
|---|---|---|---|
| **SwiftPM** | `Package.swift` | `swift build -q` / `swift test -q` | `ios/Core/` (24 files), `Tests/DoseCoreTests/` (30 files, 525+ tests) |
| **Xcode** | `ios/DoseTap.xcodeproj` | `xcodebuild build -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` | `ios/DoseTap/` |

### Key Domain Invariants (Must Be Enforced in Code)

| Invariant | Spec | Where to Verify |
|---|---|---|
| Dose 2 clinical window | 150–240 minutes after Dose 1 | `ios/Core/DoseWindowState.swift`, `docs/SSOT/constants.json` |
| Default target interval | 165 minutes | `DoseWindowConfig.defaultTargetMin` |
| Session rollover | 6 PM local time | `ios/Core/SessionKey.swift`, `SessionRepository.evaluateSessionBoundaries()` |
| Snooze disabled | When < 15 min remain OR max snoozes reached | `DoseWindowState.context()` |
| Snooze step | +10 minutes | `DoseWindowConfig.snoozeStepMin` |
| Extra dose rule | `doseIndex >= 3` only; does not update `dose2_time` | `EventStorage+Dose.swift` |
| Undo window | 5 seconds | `DoseUndoManager` |

---

## Protocol: The "Scan-Then-Plan" Method

### Phase 1: The Exhaustive Scan (Mandatory)

**You must read actual files. Do not summarize from memory or filenames.**

#### 1.1 — Traverse the File Tree

Systematically list and read every directory, including "boring" ones:
- `.github/` (CI workflows, copilot instructions)
- `.specify/` (constitution, spec artifacts)
- `tools/` (build scripts, check scripts)
- `docs/` (all subdirectories: `SSOT/`, `archive/`, `review/`, `prompt/`, `icon/`)
- `ios/Core/` (every `.swift` file — this is the platform-free domain logic)
- `ios/DoseTap/` (every subdirectory: `Views/`, `Storage/`, `Services/`, root files)
- `ios/DoseTap.xcodeproj/` (parse `project.pbxproj` for target membership)
- `Tests/DoseCoreTests/` (every test file)
- `ios/DoseTapTests/` (Xcode test target — may overlap or differ from SwiftPM tests)
- `archive/` (understand what was archived and why)
- `agent/` (agent prompts and task backlogs)
- `specs/` (spec kit artifacts)
- `macos/`, `watchos/`, `shadcn-ui/` (confirm if active or dead)

#### 1.2 — Read the Code (Not Just Index Files)

For each domain area, read the **worker logic**, not just the entry points:

**DoseCore (SwiftPM — `ios/Core/`):**
- `DoseWindowState.swift` — state machine, phase computation, snooze logic
- `DoseTapCore.swift` — dose-taking coordination, override flags
- `APIClient.swift` + `APIErrors.swift` — networking, error mapping
- `APIClientQueueIntegration.swift` — `DosingService` actor facade
- `OfflineQueue.swift` — retry queue for failed API calls
- `EventRateLimiter.swift` — event dedup/throttle
- `TimeEngine.swift` — time computations
- `SessionKey.swift` — session day grouping (rollover at 6 PM)
- `SleepPlan.swift` + `RecommendationEngine.swift` — sleep planning
- `DiagnosticLogger.swift` + `DiagnosticEvent.swift` — structured logging
- `DosingModels.swift` — dosing amount model
- `MorningCheckIn.swift` — check-in data model
- `CSVExporter.swift` — data export
- `DataRedactor.swift` — PII redaction
- `CertificatePinning.swift` — TLS pinning config
- `MedicationConfig.swift` — medication configuration
- `SleepEvent.swift`, `UnifiedSleepSession.swift` — sleep domain models
- `DoseUndoManager.swift` — undo support
- `TimeIntervalMath.swift` — time helpers
- `EventStore.swift` — event store models

**App Layer (`ios/DoseTap/`):**
- `Storage/SessionRepository.swift` — **CRITICAL**: ~1715 LOC, single source of truth for session state. Read thoroughly.
- `Storage/EventStorage.swift` + all extensions (`+Schema`, `+Session`, `+Dose`, `+CheckIn`, `+Exports`, `+EventStore`, `+Maintenance`) — SQLite persistence
- `Views/TonightView.swift` — main session view
- `Views/CompactDoseButton.swift` — primary dose-taking button
- `Views/DetailsView.swift` — session detail view
- `Views/History/` — history views
- `SettingsView.swift` — settings + notification toggle
- `AlarmService.swift` — alarm scheduling, notification management
- `FlicButtonService.swift` — Flic hardware button integration
- `URLRouter.swift` — deep link handling
- `DoseTapApp.swift` — app entry point, lifecycle
- `ContentView.swift` — root navigation
- `UserSettingsManager.swift` — user preferences

**Tests:**
- `Tests/DoseCoreTests/` — 30 test files (SwiftPM)
- `ios/DoseTapTests/` — Xcode test target (may have integration/UI tests)

#### 1.3 — Document Findings

As you read, **explicitly output what you found**:

```
Scanning ios/Core/DoseWindowState.swift...
  - DoseWindowConfig: min=150, max=240, snooze=10, target=165 ✅ matches SSOT
  - Phase enum: .noDose1, .waiting, .nearWindow, .active, .closed, .completed
  - Snooze disabled when remaining < nearWindowThresholdMin (15) ✅
  - BUG: [description] at line [N]

Scanning ios/DoseTap/Storage/SessionRepository.swift...
  - sessionNotificationIdentifiers uses IDs: wake_alarm, dose_reminder, etc.
  - MISMATCH: AlarmService uses dosetap_wake_alarm, dosetap_pre_alarm, etc.
  - cancelPendingNotifications() cancels wrong ID set — orphan notifications survive
```

This proves you did the work. **Do not skip this step.**

---

### Phase 2: The Gap Analysis

Compare your Phase 1 findings against `docs/SSOT/README.md`, `docs/architecture.md`, and `docs/SSOT/constants.json`.

#### 👻 Identify Ghosts (Plan Says Yes, Code Says No)
Features described in SSOT or architecture docs that have **no code support** or incomplete implementation:
- Is every SSOT-specified behavior actually enforced in code?
- Are all documented API endpoints implemented?
- Are all documented error codes handled?
- Are all documented navigation flows wired up?

#### 🧟 Identify Zombies (Code Exists, Plan Ignores)
Dead code or undocumented hacks that the SSOT doesn't cover:
- `TODO` / `FIXME` / `HACK` comments (list every one with file + line)
- `print()` statements in production code
- Hardcoded values that should come from `constants.json`
- Temporary workarounds that became permanent
- Files present in repo but not in any build target
- Quarantined `#if false` blocks

#### 🏗️ Architecture Check
- **State management leaks**: Are there multiple sources of truth for the same data? (e.g., `SessionRepository` vs `DoseTapCore` vs `EventStorage`)
- **Notification ID consistency**: Do all components use the same notification identifiers?
- **Channel parity**: Do all dose entry channels (UI button, Flic, URLRouter) trigger the same side effects (alarms, HealthKit, analytics)?
- **Race conditions**: Actor isolation, `@MainActor` correctness, concurrent access to shared state
- **Memory risks**: Retained closures, notification observers not removed, timers not invalidated
- **Time injection**: Is all time-based logic testable via `now: () -> Date` injection?

#### 🔧 Infrastructure Check
- **CI/CD**: Verify `.github/workflows/` match what the repo actually needs (SwiftPM tests, Xcode build, SSOT validation)
- **`.gitignore`**: Are `build/`, `.build/`, `*.xcuserdata`, `DerivedData/` properly ignored? Is anything committed that shouldn't be?
- **Entitlements**: Do `.entitlements` files match what the code requests? (e.g., critical alerts, HealthKit, iCloud)
- **Test coverage reality**: What percentage of `ios/Core/` has test coverage? What app-layer code has zero tests?
- **Schema migrations**: Is `EventStorage+Schema.swift` migration-safe? Are there version gaps?

---

### Phase 3: The Verdict & Update

#### 3.1 — Surgical Critique

List **every specific engineering fault** found, categorized by type:

| Category | Severity | Finding | Evidence | Fix |
|---|---|---|---|---|
| **Security** | P0/P1/P2/P3 | Description | file:line | Recommended fix |
| **Correctness** | ... | ... | ... | ... |
| **Performance** | ... | ... | ... | ... |
| **Maintainability** | ... | ... | ... | ... |
| **Reliability** | ... | ... | ... | ... |
| **Observability** | ... | ... | ... | ... |
| **Documentation** | ... | ... | ... | ... |

**Severity definitions for DoseTap:**
- **P0**: Dose timing incorrect, alarm not delivered, data loss/corruption, session state inconsistency
- **P1**: Feature broken for a specific channel (e.g., Flic works but alarms don't fire), notification IDs mismatched
- **P2**: Missing feature, degraded UX, permission handling gaps, missing entitlements
- **P3**: Code smell, dead code, missing docs, cosmetic issues

#### 3.2 — SSOT Correction

For every Ghost or Zombie found, provide a concrete fix:

**For Ghosts** (documented but not implemented):
- Either add a task to implement, OR
- Remove from SSOT with rationale

**For Zombies** (implemented but not documented):
- Either add to SSOT, OR
- Archive/delete with rationale

#### 3.3 — Plan Update

Rewrite or append to `docs/SSOT/README.md` and `docs/architecture.md` to reflect reality. Provide:
- Exact Markdown patches (old text → new text)
- New sections to add
- Sections to remove or mark deprecated
- Missing tasks to add to `docs/ROADMAP_TODO.md`

---

## Output Format

Structure your entire response as:

```
## Phase 1: Scan Results
### ios/Core/ (DoseCore SwiftPM Library)
[file-by-file findings]

### ios/DoseTap/ (App Layer)
[file-by-file findings]

### Tests/
[findings]

### Infrastructure (.github/, tools/, configs)
[findings]

### Docs/
[findings]

### Other Directories
[findings]

## Phase 2: Gap Analysis
### 👻 Ghosts (Plan Says Yes, Code Says No)
[list]

### 🧟 Zombies (Code Exists, Plan Ignores)
[list]

### 🏗️ Architecture Issues
[list]

### 🔧 Infrastructure Issues
[list]

## Phase 3: Verdict
### Findings Table
[table]

### SSOT Corrections
[patches]

### Plan Updates
[patches]

### Priority Action Items
[ordered list]
```

---

## Start Phase 1 Now. Show Your Work.

Begin with `.specify/memory/constitution.md` and `docs/SSOT/README.md`, then proceed to scan every directory systematically. Do not skip any area of the codebase.
