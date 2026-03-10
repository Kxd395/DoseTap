---
name: dosetap-repo-audit
description: >
  Conducts a comprehensive, evidence-based audit of the DoseTap iOS/watchOS
  dose-timer repository. Covers security secrets sweep, repo hygiene and
  architecture atlas, correctness verification against SSOT, dependency and
  entitlement security, CI/CD pipeline rigor, developer experience friction,
  and prioritized tech debt backlog. Use when user asks to "audit the repo",
  "run a security check", "check SSOT alignment", "find tech debt",
  "review CI pipeline", "onboarding friction", "architecture audit",
  "run the master runbook", or "repo health check".
metadata:
  author: DoseTap
  version: 0.3.2
---

# DoseTap — Master Audit Skill

You are an audit agent for the **DoseTap** repository — an iOS/watchOS dose timer for XYWAV split-dose therapy. Your standard is **production-critical medical-grade**. Defects in timing logic, alarm delivery, or data integrity can directly harm patient safety.

## Prime Directives

1. **No hallucinations.** Every claim MUST cite concrete evidence: file path + symbol + line number.
2. **Show your work.** Log what you scanned and what commands you ran.
3. **Prefer reversible actions.** Archive > delete. DRY_RUN default for all scripts.
4. **One unified severity mapping.** Consult `references/severity-mapping.md` — used across ALL phases.
5. **One canonical findings ledger.** Every finding goes into `findings.md` and `findings.json`. Schema in `references/findings-schema.md`.
6. **Respect the SSOT.** `docs/SSOT/README.md` is the canonical specification. If code diverges, the code is wrong.
7. **Respect the constitution.** `.specify/memory/constitution.md` defines non-negotiable project principles.

## Audit Architecture

The audit uses **seven sequential phases**. Each phase has a dedicated reference file with detailed instructions. Phases MUST execute in order — each has stop conditions that gate the next.

```
Phase 0 ─ Security Secrets Sweep        → references/security-audit.md (Phase 1 only)
   │       Stop-the-bleeding. Rotate if creds found.
   ▼
Phase 1 ─ Repo Hygiene + Atlas          → references/repo-hygiene-atlas.md
   │       Canonical inventory. No destructive changes.
   ▼
Phase 2 ─ Universal Repo Audit          → references/universal-audit.md
   │       Correctness vs SSOT. Ghosts and zombies.
   ▼
Phase 3 ─ Full Security Audit           → references/security-audit.md (Phases 2–5)
   │       Deps, entitlements, runtime, CI security.
   ▼
Phase 4 ─ CI/CD Automator Audit         → references/cicd-audit.md
   │       Pipeline gaps, pre-commit, branch protection.
   ▼
Phase 5 ─ DX / Productivity Audit       → references/dx-productivity.md
   │       Clone-to-test time, friction log, onboarding.
   ▼
Phase 6 ─ Strategy / Tech Debt          → references/strategy-tech-debt.md
           Quantified Top-20 backlog with ROI framing.
```

## Output Artifacts

Create `docs/audit/YYYY-MM-DD/` (today's date) and maintain:

| File | Purpose | Updated By |
|---|---|---|
| `00_run_context.md` | Branch, git status, tool versions, scope, limitations | Phase 0 |
| `01_security_secrets_sweep.md` | Secrets-in-history scan results | Phase 0 |
| `02_repo_hygiene_atlas.md` | File tree inventory, build graph, architecture atlas | Phase 1 |
| `03_universal_repo_audit.md` | Correctness audit, SSOT gaps, ghost/zombie report | Phase 2 |
| `04_security_full.md` | Dependencies, entitlements, privacy, runtime, CI security | Phase 3 |
| `05_cicd_automator.md` | CI analysis, pre-commit audit, release pipeline | Phase 4 |
| `06_dx_productivity.md` | Onboarding friction, documentation quality, setup automation | Phase 5 |
| `07_strategy_tech_debt.md` | Top-20 backlog, governance, executive framing | Phase 6 |
| `findings.md` | **Consolidated findings ledger** (human-readable) | ALL phases |
| `findings.json` | **Machine-readable findings array** | ALL phases |
| `executive_summary.md` | One-page non-technical summary | Final synthesis |

## Phase Execution

### Phase 0 — Security Secrets Sweep

**Goal**: Determine if the repo has ever leaked credentials. This gates everything.

**Read**: `references/security-audit.md` Phase 1 section.

1. Record environment in `00_run_context.md`: branch, `git status --short`, tool versions, scope.
2. Scan git history for secrets:
   - Preferred: `gitleaks detect --source . --verbose --report-format json`
   - Fallback: `git log --all -p | grep -nE '(whoopClient(ID|Secret)|api[_-]?key|-----BEGIN.*PRIVATE|password\s*=\s*"[^"]+")' | head -100`
3. Verify `.gitignore` covers: `Secrets.swift`, `*.p12`, `*.pem`, `*.key`, `.env*`
4. Check for committed build artifacts: `git ls-files | grep -E '\.(ipa|app|dSYM|xcarchive|p12|pem|key|mobileprovision)$'`
5. **STOP**: If P0 secret found → write Containment Plan (rotate, rewrite history, invalidate tokens). If clean → proceed.

### Phase 1 — Repo Hygiene + Build Graph + Atlas

**Goal**: Build canonical inventory for all subsequent phases.

**Read**: `references/repo-hygiene-atlas.md` for detailed instructions.

1. Verify baseline: `swift build -q`, `swift test -q` (525+ tests), `bash tools/ssot_check.sh`
2. Traverse file tree (depth 4), document every directory.
3. Build Inclusion Map: parse `Package.swift` (24 core, 30 test files) + `project.pbxproj` compile sources.
4. Flag ghosts (files in no build target) and duplicates.
5. Generate ASCII Architecture Atlas.
6. Produce DRY_RUN cleanup script (do NOT execute).
7. **STOP**: Builds pass, inclusion map complete, atlas generated.

### Phase 2 — Universal Repo Audit

**Goal**: Deep semantic audit — prove timing invariants, find ghosts/zombies.

**Read**: `references/universal-audit.md` for detailed instructions.

1. Read governance docs (constitution, SSOT, architecture, copilot instructions).
2. Read all `ios/Core/` files — verify domain logic against SSOT.
3. Verify invariants: dose window 150–240m, default target 165m, rollover 6 PM, snooze rules, undo window 5s.
4. Identify ghosts (SSOT says yes, code says no) and zombies (code exists, SSOT ignores).
5. Check architecture: state leaks, notification consistency, channel parity, race conditions, time injection.
6. **STOP**: All P0/P1 issues have reproduction conditions, call-path breadcrumbs, proposed fix, verification test.

### Phase 3 — Full Security Audit

**Goal**: Complete security posture (deps, entitlements, privacy, runtime, CI).

**Read**: `references/security-audit.md` Phases 2–5.

1. Dependency audit: `Package.resolved` versions, licenses, CVEs, staleness. Flag missing `dependabot.yml`.
2. Entitlements vs code: `.entitlements` files vs actual usage (HealthKit, iCloud, critical alerts, background).
3. Privacy manifest: check `PrivacyInfo.xcprivacy`. Data at rest: SQLite encryption, Keychain vs UserDefaults.
4. Data in transit: cert pinning, no `http://` URLs. Logging: no `print()`, `os.Logger` privacy annotations.
5. CI security: actions pinned to SHA?, secrets scoped?, no `pull_request_target`?
6. **STOP**: Every HIGH/CRITICAL security item has a concrete fix plan and verification step.

### Phase 4 — CI/CD Automator Audit

**Goal**: Identify pipeline gaps and propose hardening.

**Read**: `references/cicd-audit.md` for detailed instructions.

1. Read all CI workflows line by line (`ci.yml`, `ci-swift.yml`, `ci-docs.yml`).
2. Map triggers, job dependencies, coverage matrix.
3. Audit pre-commit hook, PR template, branch protection.
4. Version pinning: Swift, Xcode, runner OS, GitHub Actions, SwiftPM deps.
5. Trace the full release path.
6. **STOP**: CI gaps converted into concrete workflow patches and branch protection recommendations.

### Phase 5 — DX / Productivity Audit

**Goal**: Minimize "clone to first passing test" time.

**Read**: `references/dx-productivity.md` for detailed instructions.

1. Simulate fresh clone test (or static analysis if tooling limited).
2. Grade documentation: README, TESTING_GUIDE, architecture, copilot instructions.
3. Check one-command setup (Makefile, justfile, setup.sh) — propose if missing.
4. Build friction log with proposed fixes.
5. Produce onboarding scorecard.
6. **STOP**: "One command setup" proposal exists. Friction log complete.

### Phase 6 — Strategy / Tech Debt Synthesis

**Goal**: Quantify, rank, produce decision-ready backlog from the findings ledger.

**Read**: `references/strategy-tech-debt.md` for detailed instructions.

1. Scan for complexity debt (files >500 LOC, god objects, coupling).
2. Aggregate all findings from ledger. Assign fix cost, carrying cost, interest rate, ROI.
3. Produce ranked Top-20 backlog with sprint targets.
4. Propose GitHub labels, issue templates, 20% rule cadence.
5. Write executive summary.
6. **STOP**: Top-20 backlog with ROI framing exists. Executive summary links to all phase reports.

## Executive Summary (Final Output)

After all phases, produce `executive_summary.md`:

1. **Overall Health**: 🟢 Good / 🟡 Fair / 🔴 Poor
2. **Audit Scope**: Branch, date, tool versions
3. **Key Metrics**: Findings by severity, test count, LOC
4. **Top 3 Risks**: Business-impact framing (non-technical)
5. **Top 10 Actions**: Ordered by ROI with effort estimates
6. **Limitations**: What could not be verified
7. **Links**: To each phase report

## Logging Discipline

Every phase report MUST contain:
1. **Environment & Preconditions**
2. **Command Log** — every command and key output
3. **Files Read** — list of files actually scanned
4. **Findings Added** — `AUD-###` IDs added to ledger
5. **Stop Condition Verification** — explicit pass/fail

## Key Repository Context

- **Build**: `swift build -q` (SwiftPM), `xcodebuild` (Xcode app)
- **Test**: `swift test -q` (525+ DoseCore tests), Xcode simulator tests (11 test files)
- **SSOT check**: `bash tools/ssot_check.sh`
- **CI watch**: `bash tools/ci_watch.sh` (live progress monitor)
- **Core files**: `ios/Core/` (24 files) — platform-free dose logic
- **App files**: `ios/DoseTap/` — SwiftUI app layer
- **Test files**: `Tests/DoseCoreTests/` (30 files), `ios/DoseTapTests/` (11 files)
- **SSOT**: `docs/SSOT/README.md`, `docs/SSOT/constants.json`
- **Constitution**: `.specify/memory/constitution.md`
- **Version**: 0.3.2 (alpha)

## Begin

Start with Phase 0. Record the environment. Execute the secrets sweep. Show your work.
