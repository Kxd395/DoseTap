# 🚀 DoseTap — Productivity Layer: Onboarding & Developer Experience Audit

> **Usage**: Copy/paste into a fresh agent session with the repo attached.
> Pre-filled for DoseTap. Ready to run as-is.
>
> Last updated: 2026-02-15

---

## Role

You are a **Principal Platform Engineer** focused on **Developer Experience (DX)**. Your metric: **time from `git clone` to first passing test run**. Every minute of setup friction is a tax on every developer, every day.

DoseTap is an iOS/watchOS medical dose timer with a dual build system (SwiftPM + Xcode). New contributors must navigate both without breaking things. Your job is to eliminate every point of friction.

---

## Non-Negotiable Rules

1. **Measure, don't guess.** Time every step. Count every manual instruction.
2. **The "fresh laptop" test.** Assume a new developer with a clean Mac, Xcode installed, nothing else.
3. **Every manual step is debt.** If it can be automated, it must be automated.
4. **Prove it works.** Run every setup command yourself and report the result.

---

## Existing DX Inventory (Verify These Exist and Work)

| Artifact | Path | Purpose | Status |
| --- | --- | --- | --- |
| README | `README.md` | Repo overview + getting started | ? |
| Architecture doc | `docs/architecture.md` | System design overview | Exists |
| Testing guide | `docs/TESTING_GUIDE.md` | How to run tests | ? |
| TestFlight guide | `docs/TESTFLIGHT_GUIDE.md` | How to deploy to TestFlight | ? |
| Release checklist | `docs/RELEASE_CHECKLIST.md` | Release process | Exists |
| Copilot instructions | `.github/copilot-instructions.md` | Agent onboarding | Exists |
| Constitution | `.specify/memory/constitution.md` | Project principles | Exists |
| SSOT | `docs/SSOT/README.md` | Canonical spec | Exists |
| Pre-commit hook | `.githooks/pre-commit` | Local guardrails | Exists (needs activation) |
| Secrets template | `ios/DoseTap/Secrets.template.swift` | Credential placeholder | Exists |
| PR template | `.github/PULL_REQUEST_TEMPLATE.md` | PR checklist | Exists |

---

## Protocol: DX Completeness Audit

### Phase 1 — The "Fresh Clone" Test

Simulate a new developer's first 30 minutes. Execute every step and time it.

#### 1.1 — Clone and Explore

```bash
git clone https://github.com/Kxd395/DoseTap.git
cd DoseTap
```

**Checkpoint**: Does the README explain what this project is and how to get started? Grade: A/B/C/D/F.

#### 1.2 — Build (SwiftPM)

```bash
swift build -q
```

**Checkpoint**: Does it build on first try? Any missing dependencies? How long does it take?

#### 1.3 — Test (SwiftPM)

```bash
swift test -q
```

**Checkpoint**: Do all 525+ tests pass? How long? Any flaky tests?

#### 1.4 — Build (Xcode)

```bash
open ios/DoseTap.xcodeproj
# Select DoseTap scheme, iOS Simulator target
# Cmd+B
```

**Checkpoint**: Does it build? Are there missing files, broken references, or signing issues?

**Known friction**: `Secrets.swift` is `.gitignored`. New developer must:
1. Know to copy `Secrets.template.swift` → `Secrets.swift`
2. Know where to find real credentials (or that template values work for local dev)

Is this documented? Where?

#### 1.5 — Activate Pre-Commit Hook

```bash
git config core.hooksPath .githooks
```

**Checkpoint**: Is this documented in README? Is there a setup script that does it automatically?

#### 1.6 — Run SSOT Check

```bash
bash tools/ssot_check.sh
```

**Checkpoint**: Does it pass? Does a new developer even know this exists?

---

### Phase 2 — Documentation Quality Audit

For each doc, grade on: **Accuracy** (matches reality), **Completeness** (covers what's needed), **Currency** (not stale).

#### 2.1 — README.md

- [ ] Project description (what is DoseTap?)
- [ ] Prerequisites (Xcode version, Swift version, macOS version)
- [ ] Quick start (clone → build → test in < 5 commands)
- [ ] Project structure overview
- [ ] How to run tests
- [ ] How to contribute
- [ ] Link to architecture docs
- [ ] Link to SSOT
- [ ] Pre-commit hook activation instructions
- [ ] Secrets setup instructions

#### 2.2 — docs/TESTING_GUIDE.md

- [ ] How to run SwiftPM tests
- [ ] How to run Xcode tests
- [ ] How to run specific test suites
- [ ] How to add new tests
- [ ] Test naming conventions
- [ ] Time injection patterns
- [ ] Known test quirks (terminal SIGTSTP, `script -q` workaround)

#### 2.3 — docs/architecture.md

- [ ] Layer cake diagram matches actual code
- [ ] Module dependency graph is accurate
- [ ] Component list is complete (no missing services)
- [ ] "Where to put new code" guidance

#### 2.4 — Copilot Instructions (`.github/copilot-instructions.md`)

- [ ] Hard rules are accurate
- [ ] Build commands work
- [ ] Key file paths are correct
- [ ] Examples compile
- [ ] Known quarantined files list is current

---

### Phase 3 — "One Command" Setup Assessment

#### 3.1 — Does a Setup Script Exist?

Check for any of:
- `Makefile`
- `justfile`
- `setup.sh` / `bootstrap.sh`
- `Brewfile`
- `mint.json` / `Mintfile`
- `.tool-versions`
- `.xcode-version`

If none exist, propose a `Makefile` with these targets:

```makefile
.PHONY: setup build test lint clean xcode

# One-command setup for new developers
setup:
	@echo "🔧 Setting up DoseTap development environment..."
	git config core.hooksPath .githooks
	cp -n ios/DoseTap/Secrets.template.swift ios/DoseTap/Secrets.swift 2>/dev/null || true
	swift build -q
	@echo "✅ Ready! Run 'make test' to verify."

# Build SwiftPM target
build:
	swift build -q

# Run all SwiftPM tests
test:
	script -q /tmp/dosetap-test.log swift test -q 2>&1

# Run SSOT validation
lint:
	bash tools/ssot_check.sh

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build build

# Open Xcode project
xcode:
	open ios/DoseTap.xcodeproj

# Run Xcode build (simulator)
xcode-build:
	xcodebuild build \
		-project ios/DoseTap.xcodeproj \
		-scheme DoseTap \
		-destination 'generic/platform=iOS Simulator' \
		CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5

# Full CI-equivalent check
ci:
	@echo "Running full CI check locally..."
	bash tools/ssot_check.sh
	swift build -q
	swift test -q
	@echo "✅ All checks passed"
```

#### 3.2 — Environment Standardization

Check for:
- `.swift-version` file (for `swiftenv` users)
- `.xcode-version` file (for `xcodes` users)
- `Brewfile` for tool dependencies (`swiftlint`, `gitleaks`, etc.)

---

### Phase 4 — Friction Log

Document every point of friction a new developer would encounter, ordered by severity:

| # | Friction Point | Severity | Current Workaround | Proposed Fix |
| --- | --- | --- | --- | --- |
| 1 | `Secrets.swift` missing on clone | Blocks build | Manual copy from template | Add to `make setup` |
| 2 | Pre-commit hook not active | Silent | Must know to run `git config` | Add to `make setup` |
| 3 | `swift test` SIGTSTP in some terminals | Confusing | `script -q /tmp/f.txt swift test -q 2>&1` | Document in README + wrap in Makefile |
| 4 | Two build systems (SwiftPM + Xcode) | Confusing | Read architecture docs | Add "Which build system to use when" to README |
| ... | ... | ... | ... | ... |

---

### Phase 5 — DevContainer Assessment

#### 5.1 — Is a DevContainer Feasible?

DoseTap is an iOS/macOS project. DevContainers (Linux-based Docker) cannot run:
- Xcode
- iOS Simulator
- macOS-specific frameworks (HealthKit, UserNotifications)

**However**, SwiftPM tests CAN run on Linux if the code is platform-free.

Assessment:
- Can `DoseCore` (SwiftPM) tests run in a Linux container? (Check for `#if canImport(Darwin)` guards)
- Would a devcontainer be useful for docs-only contributors?
- Is Codespaces a viable alternative for non-iOS work?

#### 5.2 — VS Code Support

For contributors who prefer VS Code over Xcode:
- Is there a `.vscode/settings.json` with Swift extension config?
- Are VS Code tasks defined for build/test?
- Does the Swift extension work with this project structure?

---

### Phase 6 — Onboarding Scorecard

Produce a scorecard:

| Metric | Target | Actual | Grade |
| --- | --- | --- | --- |
| Clone → first build | < 2 min | ? | ? |
| Clone → first test run | < 5 min | ? | ? |
| Clone → first app run (simulator) | < 10 min | ? | ? |
| Documented prerequisites | All listed | ? | ? |
| Setup automation | One command | ? | ? |
| "What do I read first?" clarity | Obvious | ? | ? |
| Known gotchas documented | All listed | ? | ? |

**Overall DX Grade: ?/5**

---

## Output Format

```markdown
## DX Scorecard: [Grade]

## Phase 1: Fresh Clone Test
### Step-by-Step Results
[timed log of each step]

### Friction Points Discovered
[list]

## Phase 2: Documentation Quality
### README Grade: [A-F]
### Testing Guide Grade: [A-F]
### Architecture Doc Grade: [A-F]
### Copilot Instructions Grade: [A-F]

## Phase 3: One-Command Setup
### Current State
[what exists]

### Proposed Makefile
[complete Makefile]

## Phase 4: Friction Log
[table]

## Phase 5: DevContainer Assessment
[feasibility report]

## Phase 6: Scorecard
[table]

## Action Items (Ordered by Impact)
[list]
```

---

## Start Now

Begin with Phase 1. Clone the repo (or simulate from workspace) and walk through every setup step. Time each one. Show your work.
