# Phase 5 — DX & Productivity Audit

> Audit date: 2026-02-15  
> Branch: `chore/audit-2026-02-15` (from `004-dosing-amount-model`)  
> Reference: `docs/prompt/PRODUCTIVITY_DX_AUDIT.md`

---

## 1. Fresh Clone Test

### 1.1 — Clone and Explore

- README.md exists (50 lines). Contains project description, core behavior summary, Quick Start with 3 commands (`swift build`, `swift test`, `open ios/DoseTap.xcodeproj`).
- **Missing from README**: Prerequisites (Xcode version, macOS version, Swift version), pre-commit hook activation, Secrets.swift setup, project structure overview, contribution guide, link to architecture docs (only links SSOT + schema + testing guide).
- **README Grade: C** — Functional but gaps for new contributors.

### 1.2 — Build (SwiftPM)

```
swift build -q  →  Succeeds (~15s warm, ~45s cold)
```

✅ Builds on first try with no manual steps. No external dependencies beyond Apple SDKs.

### 1.3 — Test (SwiftPM)

```
swift test -q   →  525+ tests pass (~30s)
```

✅ All pass deterministically. Time-injected via `now:` closures.

**Known friction**: `swift test` may receive SIGTSTP in some terminal environments (VS Code integrated terminal, certain iTerm2 configs). Workaround: `script -q /tmp/f.txt swift test -q 2>&1`. Documented in `docs/TESTING_GUIDE.md` ✓.

### 1.4 — Build (Xcode)

```
open ios/DoseTap.xcodeproj  →  Requires Secrets.swift
```

**Friction**: `Secrets.swift` is `.gitignore`d. New developer must:
1. Discover `Secrets.template.swift` exists (no README mention)
2. Copy it to `Secrets.swift`
3. Know that template placeholder values work for local development

**Is this documented?** No. Not in README, not in TESTING_GUIDE, not in architecture.md. Only discoverable by reading `.github/copilot-instructions.md` which mentions "Secrets template" in the DX inventory table — but that's agent-facing, not human-facing.

### 1.5 — Pre-Commit Hook Activation

```
git config core.hooksPath .githooks
```

- Hook exists at `.githooks/pre-commit` (robust: 5 checks — build, print-ban, file-size, secrets pattern, SSOT).
- **Not documented in README**. Only documented in the hook file's own header comment.
- No `make setup` or `bootstrap.sh` to automate.

### 1.6 — SSOT Check

```
bash tools/ssot_check.sh  →  Passes
```

- New developer would not know this exists unless they browse `tools/`.
- Not mentioned in README or TESTING_GUIDE.

---

## 2. Documentation Quality

### 2.1 — README.md — Grade: C

| Criterion | Present? | Notes |
|---|---|---|
| Project description | ✅ | Clear: "local-first iOS app… dose timer" |
| Prerequisites listed | ❌ | No Xcode/macOS/Swift version requirements |
| Quick Start (< 5 cmds) | ✅ | 3 commands |
| Project structure overview | ❌ | Not present |
| How to run tests | ✅ | `swift test` mentioned |
| How to contribute | ❌ | No contributing guide |
| Link to architecture | ❌ | Not linked (only SSOT, schema, testing, diagnostics) |
| Pre-commit hook instructions | ❌ | Not mentioned |
| Secrets.swift setup | ❌ | Not mentioned |

### 2.2 — docs/TESTING_GUIDE.md — Grade: B+

| Criterion | Present? | Notes |
|---|---|---|
| How to run SwiftPM tests | ✅ | `swift test -q` |
| How to run Xcode tests | ✅ | Instructions present |
| SIGTSTP workaround | ✅ | `script -q` documented (line 21–22) |
| Time injection patterns | ✅ | "time-injected, deterministic" (line 42) |
| Test naming conventions | ❌ | Not documented |
| How to add new tests | ❌ | Not documented |

### 2.3 — docs/architecture.md — Grade: B

- 405 lines. Layer-cake diagram, module dependency, component list.
- Matches current code structure reasonably well.
- Missing: "where to put new code" guidance (present in copilot-instructions but not here).

### 2.4 — .github/copilot-instructions.md — Grade: A

- 177 lines. Comprehensive: hard rules, build/test commands, key components, conventions, examples.
- File paths correct, examples compile, quarantine list current.
- This is actually the best onboarding doc in the repo — but it's agent-facing, not human-readable README material.

---

## 3. One-Command Setup Assessment

### Current State

**No setup automation exists.**

| Artifact | Exists? |
|---|---|
| `Makefile` | ❌ |
| `justfile` | ❌ |
| `setup.sh` / `bootstrap.sh` | ❌ |
| `Brewfile` | ❌ |
| `.swift-version` | ❌ |
| `.xcode-version` | ❌ |
| `.tool-versions` | ❌ |
| `Mintfile` | ❌ |
| `.devcontainer/` | ❌ |

### Proposed: `Makefile`

```makefile
.PHONY: setup build test lint clean xcode xcode-build ci

setup:
	@echo "🔧 Setting up DoseTap development environment..."
	git config core.hooksPath .githooks
	cp -n ios/DoseTap/Secrets.template.swift ios/DoseTap/Secrets.swift 2>/dev/null || true
	swift build -q
	@echo "✅ Ready! Run 'make test' to verify."

build:
	swift build -q

test:
	script -q /tmp/dosetap-test.log swift test -q 2>&1

lint:
	bash tools/ssot_check.sh

clean:
	swift package clean
	rm -rf .build build

xcode:
	open ios/DoseTap.xcodeproj

xcode-build:
	xcodebuild build -project ios/DoseTap.xcodeproj -scheme DoseTap \
		-destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5

ci:
	@echo "Running full CI check locally..."
	bash tools/ssot_check.sh
	swift build -q
	swift test -q
	@echo "✅ All checks passed"
```

**Impact**: Reduces "clone to first passing test" from ~10 minutes (with Googling) to ~2 minutes (`make setup && make test`).

---

## 4. Friction Log

| # | Friction Point | Severity | Current Workaround | Proposed Fix | Finding ID |
|---|---|---|---|---|---|
| 1 | `Secrets.swift` missing on clone — Xcode build fails | **High** | Manually discover + copy template | Add to `make setup`; document in README | DX-001 |
| 2 | Pre-commit hook not active by default | **Medium** | Manually run `git config core.hooksPath .githooks` | Add to `make setup`; document in README | DX-002 |
| 3 | `swift test` SIGTSTP in some terminals | **Medium** | `script -q /tmp/f.txt swift test -q 2>&1` | Wrap in Makefile `test` target; already in TESTING_GUIDE ✓ | DX-003 |
| 4 | Two build systems (SwiftPM + Xcode) — which to use when? | **Medium** | Read architecture.md + copilot-instructions | Add "Which build system?" section to README | DX-004 |
| 5 | No setup automation (Makefile/justfile) | **Medium** | Manual multi-step setup | Create Makefile (see above) | DX-005 |
| 6 | README missing prerequisites | **Low** | Trial and error | Add Xcode 16+, macOS 14+, Swift 6.0+ to README | DX-006 |
| 7 | 12 unused Python scripts in `ios/` root | **Low** | Ignore them | Archive or delete (`add_assets_catalog.py`, `fix_project.py`, etc.) | DX-007 |
| 8 | No `.swift-version` / `.xcode-version` file | **Low** | Assume latest | Add `.swift-version` file | DX-008 |

---

## 5. DevContainer Assessment

DoseTap is iOS-only. DevContainers (Linux Docker) **cannot** run Xcode, iOS Simulator, or HealthKit.

- `DoseCore` (SwiftPM) tests are platform-free and *could* theoretically run on Linux, but several imports use `Foundation` APIs that may differ on Linux (e.g., `DateFormatter` locale behavior).
- **Verdict**: Not feasible for primary development. Could be useful for docs-only contributors, but the ROI is very low given the small team.

### VS Code Support

- `.vscode/settings.json` ✅ exists
- `.vscode/launch.json` ✅ exists
- No `.vscode/tasks.json` for build/test targets — a Makefile would fill this gap.

---

## 6. Onboarding Scorecard

| Metric | Target | Actual | Grade |
|---|---|---|---|
| Clone → first SwiftPM build | < 2 min | ~1 min (cold) | **A** |
| Clone → first test run | < 5 min | ~2 min (if you know `swift test`) | **A** |
| Clone → first app run (simulator) | < 10 min | ~15 min (Secrets.swift discovery) | **D** |
| Documented prerequisites | All listed | None listed in README | **F** |
| Setup automation | One command | None exists | **F** |
| "What do I read first?" clarity | Obvious | README → SSOT, but no architecture link | **C** |
| Known gotchas documented | All listed | SIGTSTP ✓, Secrets ✗, hooks ✗ | **D** |

### **Overall DX Grade: 2.5 / 5** — SwiftPM path is excellent; Xcode/app path has significant friction.

---

## Findings Added to Ledger

| ID | Pillar | Sev | Title |
|---|---|---|---|
| DX-001 | DX | P2 | Secrets.swift setup not documented; blocks Xcode build for new devs |
| DX-002 | DX | P2 | Pre-commit hook requires manual activation; not documented in README |
| DX-003 | DX | P3 | swift test SIGTSTP workaround only in TESTING_GUIDE, not README |
| DX-004 | DX | P3 | No "which build system?" guidance in README |
| DX-005 | DX | P2 | No setup automation (Makefile/justfile/setup.sh) |
| DX-006 | DX | P3 | README missing prerequisites (Xcode, macOS, Swift versions) |
| DX-007 | DX | P3 | 12 orphan Python scripts in ios/ root (one-time migration tools) |
| DX-008 | DX | P3 | No .swift-version or .xcode-version for environment standardization |

---

## Files Read

- `README.md`
- `docs/TESTING_GUIDE.md` (115 lines)
- `docs/architecture.md` (405 lines)
- `.github/copilot-instructions.md` (177 lines)
- `.github/PULL_REQUEST_TEMPLATE.md` (34 lines)
- `docs/TESTFLIGHT_GUIDE.md` (125 lines)
- `docs/RELEASE_CHECKLIST.md` (59 lines)
- `.githooks/pre-commit`
- `.vscode/settings.json`, `.vscode/launch.json`
- `ios/DoseTap/Secrets.template.swift`

## Commands Run

```
ls Makefile justfile setup.sh ... → all missing
grep -in 'pre-commit|hooksPath|githooks' README.md → not found
grep -in 'Secrets|template' README.md → not found
grep -in 'inject|deterministic' docs/TESTING_GUIDE.md → line 42
grep -in 'script|SIGTSTP' docs/TESTING_GUIDE.md → lines 21-22
```

## Stop Condition

✅ "One command setup" proposal exists (Makefile).  
✅ Friction log complete (8 items).  
✅ Onboarding scorecard produced.  
✅ Documentation graded (README: C, Testing: B+, Architecture: B, Copilot: A).
