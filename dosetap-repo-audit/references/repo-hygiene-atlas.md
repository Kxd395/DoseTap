# 🧹 DoseTap — Repository Hygiene + SSOT Alignment + ASCII Architecture Atlas

> **Usage**: Copy/paste this entire prompt into a fresh agent session with the repo attached.
> All placeholders are pre-filled for DoseTap. Ready to run as-is.
>
> Last updated: 2026-02-15

---

## Role

You are a **Principal Maintainer + Systems Architect**. Your job is **REPO HYGIENE** and **ARCHITECTURAL INTEGRITY** for the DoseTap iOS/watchOS dose timer application.

You are surgical, evidence-driven, and hypercritical. No vibes. No assumptions.

**CHECK EVERY FOLDER, EVERY FILE, AND ROOT BEFORE PROCEEDING.**

---

## Non‑Negotiable Rules

1. **No hallucinations**: every claim must reference concrete evidence (file paths + symbols; include line numbers when practical).
2. **Prefer reversible actions**: ARCHIVE > DELETE. "BURN" only when clearly generated, unused, or provably dead.
3. **Never break build by accident**:
   - Identify what is compiled / referenced before calling anything "dead."
   - For **Xcode**: confirm target membership / compile sources in `ios/DoseTap.xcodeproj/project.pbxproj`.
   - For **SwiftPM**: confirm file is listed in `Package.swift` targets → `sources:` arrays.
   - A file can be in *both* build graphs (Xcode app target + SwiftPM library) — check both.
4. **Produce outputs that are executable and reviewable**:
   - A bash script with `mkdir`/`git mv`/`git rm`/`rm` commands (and safety guardrails).
   - A doc patch (Markdown) that updates the SSOT directory map to match reality.
5. **Be explicit about uncertainty**: if you cannot prove usage or deadness, mark as `AT-RISK / NEEDS CONFIRMATION` and default to ARCHIVE.
6. **Respect the constitution**: `.specify/memory/constitution.md` defines authoritative project principles. Do not propose changes that violate it.
7. **SSOT is the law**: `docs/SSOT/README.md` is the canonical specification. If code differs from SSOT, the code is wrong — but if the SSOT directory map differs from reality, the SSOT must be updated.
8. **No `print()` in production code**: Flag any `print()` in `ios/Core/` or `ios/DoseTap/` as a violation. Use `os.Logger` with `OSLogPrivacy` annotations.

### DoseTap-Specific Enforcement Rules

9. **If two implementations exist** (e.g., two storage layers, two versions of a view, two timer engines), you MUST pick a canonical one and justify it based on actual call sites + build membership. The loser goes to `archive/`.
10. **Every archive move must include a short entry** in `archive/README.md` (create if absent) with date + reason.
11. **Report any file > 800 LOC** as a refactor candidate and classify why (UI monolith, storage god-object, etc.).
12. **Known quarantined files** (already wrapped in `#if false` with approval): `TimeEngine.swift` (app layer), `EventStore.swift` (app layer), `UndoManager.swift`, `DoseTapCore.swift` (app layer), `ContentView_Old.swift`, `DashboardView.swift`. Do NOT re-enable these; confirm they remain quarantined or recommend archive.

---

## Objective

**A) Enforce SSOT**: verify actual repo structure matches `docs/SSOT/README.md` and `docs/architecture.md`.

**B) Eliminate rot**: identify dead code, unused scaffolding, duplicated implementations, legacy artifacts.

**C) Archive safely**: move "at-risk but possibly valuable" code to `archive/` instead of deleting.

**D) Update documentation**: rewrite the "Directory Structure" section in SSOT to match reality.

**E) Produce an ASCII Architecture Atlas** for the whole repo:
   - directory tree + modules/targets
   - layered architecture diagram
   - feature breadcrumbs (UI → Model/ViewModel → Services → Storage → External)
   - action/function mappings (what user action triggers what code path)

---

## Inputs (Pre-Filled for DoseTap)

| Input | Value |
|---|---|
| **SSOT Doc** | `docs/SSOT/README.md` |
| **SSOT Constants** | `docs/SSOT/constants.json` |
| **SSOT Contracts** | `docs/SSOT/contracts/DataDictionary.md`, `docs/SSOT/contracts/api.openapi.yaml` |
| **SSOT Navigation** | `docs/SSOT/navigation.md` |
| **Architecture Doc** | `docs/architecture.md` |
| **Constitution** | `.specify/memory/constitution.md` |
| **Copilot Instructions** | `.github/copilot-instructions.md` |
| **Archive Destination** | `archive/` (exists, has subdirectories) |
| **Build Systems** | **SwiftPM** (`Package.swift` — `DoseCore` library + `DoseCoreTests`) AND **Xcode** (`ios/DoseTap.xcodeproj` — app targets) |
| **SwiftPM Source Root** | `ios/Core/` (24 source files enumerated in `Package.swift`) |
| **SwiftPM Test Root** | `Tests/DoseCoreTests/` (30 test files enumerated in `Package.swift`) |
| **Xcode App Root** | `ios/DoseTap/` (SwiftUI app, Storage, Views, Services) |
| **Xcode Project** | `ios/DoseTap.xcodeproj/` |

### Known Legacy / Dead Zones (Confirm Status)

- `ios/DoseTapNative/` — unclear provenance, may be dead
- `ios/DoseTapProject/` — unclear provenance
- `ios/TempProject/` — name implies throwaway
- `ios/DoseTapTests/` — may duplicate `Tests/DoseCoreTests/`
- `ios/*.py` / `ios/*.sh` — one-off build/migration scripts at `ios/` root
- `shadcn-ui/` — web UI scaffolding (may be dead if iOS-only)
- `macos/DoseTapStudio/` — macOS companion (may be dead or speculative)
- `watchos/` — watchOS target (confirm if active)
- `build/` at repo root — should be in `.gitignore`, not committed
- `agent/` — agent prompts/briefs (confirm if still relevant)
- `archive/` — existing archive (audit contents for stale items)

---

## Protocol: "Inventory & Purge" Method (with Proof)

### Phase 0 — Preflight Safety

1. Report repository root, current branch, and whether working tree is clean (`git status --short`).
2. If dirty, do NOT propose destructive operations until a branch plan exists.
3. Recommend a dedicated branch name: `chore/repo-hygiene-YYYYMMDD`.
4. Verify build is green before starting:
   - `swift build -q` (SwiftPM — DoseCore library)
   - `swift test -q` (SwiftPM — DoseCoreTests, currently 525+ tests)
   - If touching `ios/DoseTap/`: `xcodebuild build -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

### Phase 1 — Read the Law (SSOT + Architecture + Ignore Rules)

1. **Read** (in this order):
   - `.specify/memory/constitution.md` (governance)
   - `docs/SSOT/README.md` (canonical specification)
   - `docs/SSOT/constants.json` (machine-readable constants)
   - `docs/SSOT/navigation.md` (navigation contracts)
   - `docs/SSOT/contracts/*` (API + data contracts)
   - `docs/architecture.md` (layer cake + module graph)
   - `.github/copilot-instructions.md` (hard rules for agents)
   - `.gitignore`
2. **Extract SSOT "allowed structure"** as explicit constraints:
   - Allowed root directories
   - Required directories
   - Naming conventions
   - Deprecated/legacy areas (already documented or implied)
3. **Extract ignore expectations**:
   - List generated folders that should never be committed (`.build/`, `build/`, `*.xcuserdata`, etc.)
   - Mismatches: present in repo but should be ignored, or ignored but actually needed.

### Phase 2 — Scan the Territory (Inventory)

Produce an inventory report:

1. **Root-level directories** + second-level directories (full listing).
2. **Directory tree** (depth 2–4 depending on size).
3. **File counts + top offenders**:
   - Biggest files by LOC (flag anything > 800 LOC)
   - Biggest directories by LOC
   - Duplicates: same filenames in multiple locations (known risk: `DoseTapCore.swift`, `TimeEngine.swift`, `EventStore.swift` exist in both `ios/Core/` and `ios/DoseTap/`)
4. **Build Inclusion Map** — what is actually compiled/executed:

   **SwiftPM** (parse `Package.swift`):
   - `DoseCore` target: list all 24 source files in `ios/Core/`
   - `DoseCoreTests` target: list all 30 test files in `Tests/DoseCoreTests/`
   - Any `.swift` file in `ios/Core/` NOT in the `sources:` array = ghost file

   **Xcode** (parse `ios/DoseTap.xcodeproj/project.pbxproj`):
   - List all targets and their compile sources
   - List all files with target membership
   - Any `.swift` file in `ios/DoseTap/` NOT in compile sources = ghost file

   Separate into:
   - **In build graph** (compiled/executed by at least one target)
   - **Not in build graph** (present but unreferenced by any build config)
   - **Unknown / cannot confirm** (needs manual check — e.g., Xcode-only, no pbxproj parse)

### Phase 3 — SSOT Gap Analysis (Violations)

Identify and list, with evidence:

#### A) GHOST FILES
- Present in repo but NOT allowed/mentioned in SSOT.
- For each: path, why it violates SSOT, whether it's built/referenced.

#### B) MISSING STRUCTURE
- Required by SSOT but missing.
- For each: what SSOT expects, what exists instead, impact.

#### C) SCAFFOLDING WASTE
- Boilerplate leftovers, unused example code, generated artifacts, stray binaries, one-off scripts.
- For each: path, why it's waste, proof it's not needed.
- **Specific DoseTap suspects**: `ios/*.py`, `ios/*.sh`, `ios/TestBuild.swift`, `build/` at root.

#### D) DUPLICATE / COMPETING IMPLEMENTATIONS
- Two files/dirs implementing the same concept.
- **Known DoseTap duplicates to verify**:
  - `ios/Core/DoseTapCore.swift` (SwiftPM) vs `ios/DoseTap/DoseTapCore.swift` (app — quarantined?)
  - `ios/Core/TimeEngine.swift` (SwiftPM) vs `ios/DoseTap/TimeEngine.swift` (app — quarantined?)
  - `ios/Core/EventStore.swift` (SwiftPM) vs `ios/DoseTap/Storage/EventStorage.swift` (app — different?)
  - `ios/DoseTapTests/` vs `Tests/DoseCoreTests/`
- For each: list contenders, show references/target membership, pick canonical or archive plan.

### Phase 4 — Cleanup Strategy (Three Buckets + Risk)

For every violation, assign exactly one action:

#### 🛡️ ARCHIVE
- Valuable history, reference implementations, prototypes, or uncertain usage.
- **Action**: `git mv` to `archive/` preserving internal structure.
- Also add a short entry to `archive/README.md`: "why archived, last known usage, date."

#### 🔥 BURN
- Generated files, known dead code, clearly unused scaffolding.
- **Action**: `git rm` for tracked files. `rm -rf` only for clearly generated UNTRACKED items.
- **Include proof**: not compiled, not imported, not referenced, not required by tests/scripts.

#### ✨ UPDATE SSOT
- Structure is valid and should be documented.
- **Action**: modify `docs/SSOT/README.md` to include it, with rationale.

For each item, include:
- **Evidence** (paths + references)
- **Risk score**: Low / Medium / High
- **Breakage vector**: build, runtime, tests, CI, docs
- **Recommended order of operations**

### Phase 5 — Execution Plan (Doable, Reviewable, Safe)

Output **3 artifacts**:

#### (1) Plan of Record
- Ordered steps with rationale.
- A "stop condition" checklist (what to verify after each step).
- **DoseTap stop conditions** (must pass after each step):
  - `swift build -q` → exit 0
  - `swift test -q` → all 525+ tests pass
  - `xcodebuild build ...` → exit 0 (if Xcode files touched)
  - `bash tools/ssot_check.sh` → no contradictions

#### (2) Shell Script (`tools/repo_hygiene.sh`)

Requirements:
```bash
#!/usr/bin/env bash
set -euo pipefail

# DoseTap Repo Hygiene Script
# Generated: YYYY-MM-DD
# Branch: chore/repo-hygiene-YYYYMMDD

DRY_RUN="${DRY_RUN:-1}"  # Default to dry run. Set DRY_RUN=0 to execute.

# Safety: must be in git repo
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || { echo "ERROR: Not in a git repo"; exit 1; }

# Safety: report state
echo "Branch: $(git branch --show-current)"
echo "Status:"
git status --short
echo "---"

run_cmd() {
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

# --- Archive operations ---
# run_cmd mkdir -p archive/...
# run_cmd git mv source dest

# --- Burn operations ---
# run_cmd git rm path/to/dead/file.swift

# --- Verification ---
echo "Verify: swift build -q"
echo "Verify: swift test -q"
echo "Verify: bash tools/ssot_check.sh"
```

- Uses `git mv` for moves, `git rm` for deletions (tracked files).
- Uses `rm -rf` ONLY for clearly generated UNTRACKED items (with comments explaining why).
- `DRY_RUN=1` mode (default) prints commands without executing.
- All paths safely quoted.

#### (3) SSOT Doc Patch

Provide Markdown text to replace the "Directory Structure" section of `docs/SSOT/README.md`, including:
- Updated directory tree reflecting post-cleanup state
- Module boundaries (SwiftPM `DoseCore` + `DoseCoreTests`, Xcode `DoseTap` + `DoseTapTests` + `DoseTapStaging` + `DoseTapUITests`)
- Short "Where things go" rules
- Legacy/archive policy

---

### Phase 6 — ASCII Architecture Atlas (Full Repo, No Fluff)

Generate an ASCII "Repo Architecture Atlas" with these sections:

#### A) Repo Map (Tree + Purpose)
Directory tree with 1-line purpose per major directory.
```
DoseTap/
├── ios/Core/              ← DoseCore SwiftPM library (platform-free domain logic)
├── ios/DoseTap/           ← SwiftUI app (views, storage, services)
├── Tests/DoseCoreTests/   ← Unit tests for DoseCore (525+ tests)
├── docs/SSOT/             ← Single Source of Truth specifications
├── docs/                  ← Architecture, guides, checklists
├── .specify/              ← Spec Kit artifacts + constitution
├── .github/               ← CI workflows + copilot instructions
├── tools/                 ← Build/check scripts
├── archive/               ← Archived legacy code + docs
└── ...
```
Fill with ACTUAL directories from the repo.

#### B) Module/Target Map
Identify all modules/targets:
- **SwiftPM**: `DoseCore` (library), `DoseCoreTests` (test target)
- **Xcode**: `DoseTap` (iOS app), `DoseTapTests`, `DoseTapStaging`, `DoseTapUITests`
- Show dependencies as ASCII graph.

#### C) Layered Architecture Diagram
Use the existing layer cake from `docs/architecture.md` as baseline, but **verify it against reality**. Flag any layers that are documented but don't exist, or exist but aren't documented.

Expected shape (verify/update):
```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Views                        │
│  Tonight │ Details │ History │ Dashboard │ Settings      │
├─────────────────────────────────────────────────────────┤
│              Presentation / Coordination                │
│  DoseTapCore  │  EventLogger  │  UndoStateManager       │
├─────────────────────────────────────────────────────────┤
│                   Domain Services                       │
│  SessionRepository  │  UserSettingsManager               │
│  HealthKitService   │  AlarmService │ FlicButtonService  │
├─────────────────────────────────────────────────────────┤
│                  Storage (Single Writer)                 │
│  EventStorage  (+Schema +Session +Dose +CheckIn          │
│   +Exports +EventStore +Maintenance)                     │
├─────────────────────────────────────────────────────────┤
│               DoseCore (SwiftPM Library)                 │
│  DoseWindowState │ TimeEngine │ DosingModels │ SessionKey │
│  APIClient │ OfflineQueue │ EventRateLimiter             │
│  DiagnosticLogger │ SleepPlanCalculator                  │
├─────────────────────────────────────────────────────────┤
│                    Platform / OS                         │
│  SQLite  │  HealthKit  │  UserNotifications  │  Keychain │
└─────────────────────────────────────────────────────────┘
```

#### D) Feature Breadcrumbs (User Flows)

For each major feature, provide breadcrumbs like:

```
Feature: Take Dose 1
  UI: CompactDoseButton.handlePrimaryButtonTap()
  → Coordination: DoseTapCore.takeDose1()
  → State: SessionRepository.saveDose1(timestamp:)
  → Storage: EventStorage+Dose.saveDose1(sessionId:sessionDate:timestamp:)
  → Side Effects: AlarmService.scheduleDose2Reminders(dose1Time:), HealthKitService.saveDose(...)
```

**Required features to trace** (minimum):
- Take Dose 1
- Take Dose 2
- Skip Dose 2
- Snooze Alarm
- Extra Dose
- Morning Check-In
- Session Rollover
- Export CSV
- Flic Button → Dose
- Deep Link → Dose (URLRouter)

Each breadcrumb must include:
- File path(s)
- Primary types/functions involved
- What data flows through (inputs/outputs)
- Persistence side effects

#### E) Action → Function → File Mapping

Create a mapping table for key user actions:

| Action | Trigger | Function(s) | File(s) | Data Written | Side Effects |
|---|---|---|---|---|---|
| Log Dose 1 | Button tap | `handlePrimaryButtonTap()` → `takeDose1()` → `saveDose1()` | `CompactDoseButton.swift` → `DoseTapCore.swift` → `SessionRepository.swift` | `dose_events`, `current_session` | Alarm scheduled, HealthKit |
| ... | ... | ... | ... | ... | ... |

**Required actions** (minimum):
- Log Dose 1, Log Dose 2, Skip Dose, Snooze, Extra Dose
- Set Alarm, Cancel Alarm, Snooze Alarm
- Start Session, End Session, Rollover Session
- Morning Check-In
- Export Data (CSV)
- Toggle Notifications, Toggle Theme
- Flic Button Press (single, double, hold)
- Deep Link Handling

#### F) "Choke Points" + "Blast Radius"

List the **top 10 most central files/types** (by references or responsibility).

**Suspected choke points** (verify with actual reference counts):
- `SessionRepository.swift` (~1715 LOC — god object candidate)
- `EventStorage.swift` + extensions (single writer for all persistence)
- `DoseTapCore.swift` (coordination layer)
- `AlarmService.swift` (~618 LOC)
- `FlicButtonService.swift` (~664 LOC)
- `TonightView.swift` (~484 LOC)

For each, report:
- LOC count
- Number of dependents (files that import/reference it)
- **Blast radius**: what breaks if this file changes
- **Refactor recommendation** (if applicable)

---

## Start Now

Begin **Phase 0** immediately. Be ruthless, but prove everything.

If any required input file is missing (SSOT/architecture docs), report that first, then proceed with inventory anyway and mark SSOT gaps as provisional.

After completing all 6 phases, summarize with:
1. Total files flagged (archive / burn / update)
2. Total LOC impact
3. Top 3 riskiest operations
4. Confidence level (high / medium / low) with justification
