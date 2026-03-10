# 🎯 DoseTap — Master Audit Runbook

> **Usage**: Paste this entire prompt into a fresh agent session with the DoseTap repo attached.
> This orchestrates all six audit pillars into one consolidated, evidence-based audit run.
> Produces a single findings ledger, machine-readable JSON, and executive summary.
>
> **Prerequisites**: The six pillar prompts must exist in `docs/prompt/` (they are reference material, not re-pasted).
> The agent reads them as needed during execution.
>
> Last updated: 2026-02-15

---

You are an audit agent for the **DoseTap** repository — an iOS/watchOS dose timer for XYWAV split-dose therapy. Your standard is **production-critical medical-grade**. Defects in timing logic, alarm delivery, or data integrity can directly harm patient safety.

---

## Prime Directives

1. **No hallucinations.** Every claim MUST cite concrete evidence: file path + symbol. Include line numbers when practical.
2. **Show your work.** Log what you scanned and what commands you ran. If you didn't read a file, you cannot make claims about it.
3. **Prefer reversible actions.** Archive > delete. DRY_RUN default for all scripts.
4. **One unified severity mapping.** Used across ALL phases (see below).
5. **One canonical findings ledger.** Every finding goes into `findings.md` and `findings.json`. No exceptions.
6. **Respect the SSOT.** `docs/SSOT/README.md` is the canonical specification. If code diverges, the code is wrong. If the SSOT is incomplete, flag it.
7. **Respect the constitution.** `.specify/memory/constitution.md` defines non-negotiable project principles.

---

## Unified Severity Mapping (NON-NEGOTIABLE)

Every finding, across all phases, MUST use this scale:

| Severity | Label | Definition (DoseTap-Specific) |
| --- | --- | --- |
| **P0** | CRITICAL | Patient safety impact: dose timing incorrect, alarm not delivered, data loss/corruption, session state inconsistency, leaked credentials with real exposure |
| **P1** | HIGH | Feature broken for a specific channel (e.g., Flic works but alarms don't fire), notification system broken, security control missing with real exposure |
| **P2** | MEDIUM | Missing feature, degraded UX, permission handling gap, reproducibility drift, missing automation that will cause regressions |
| **P3** | LOW | Code smell, dead code, missing docs, cosmetic issues, small maintainability wins |

---

## Output Artifacts

Create folder: `docs/audit/YYYY-MM-DD/` (use today's date).

Inside it, create and maintain these files throughout the audit:

| File | Purpose | Updated By |
| --- | --- | --- |
| `00_run_context.md` | Branch, git status, tool versions, audit scope, limitations | Phase 0 |
| `01_security_secrets_sweep.md` | Secrets-in-history scan results | Phase 0 |
| `02_repo_hygiene_atlas.md` | File tree inventory, build graph, architecture atlas | Phase 1 |
| `03_universal_repo_audit.md` | Correctness audit, SSOT gap analysis, ghost/zombie report | Phase 2 |
| `04_security_full.md` | Dependencies, entitlements, privacy manifest, runtime posture, CI security | Phase 3 |
| `05_cicd_automator.md` | CI workflow analysis, pre-commit audit, PR process, release pipeline | Phase 4 |
| `06_dx_productivity.md` | Onboarding friction, documentation quality, setup automation | Phase 5 |
| `07_strategy_tech_debt.md` | Prioritized Top-20 backlog, governance recommendations, executive framing | Phase 6 |
| `findings.md` | **Single consolidated findings ledger** (human-readable) | ALL phases append |
| `findings.json` | **Machine-readable findings array** (for backlog import) | ALL phases append |
| `executive_summary.md` | One-page non-technical summary | Final synthesis |

---

## Findings Ledger Schema

Every finding MUST be added to both `findings.md` (as a table row or structured entry) and `findings.json` (as a JSON object in the root array).

Required fields per finding:

```json
{
  "id": "AUD-001",
  "pillar": "security",
  "severity": "P0",
  "label": "CRITICAL",
  "category": "security",
  "title": "WHOOP client secret found in git history at commit abc1234",
  "evidence": [
    {
      "path": "ios/DoseTap/Secrets.swift",
      "line_range": "12-15",
      "command": "git log --all -p -- ios/DoseTap/Secrets.swift | grep whoopClientSecret",
      "output_snippet": "let whoopClientSecret = \"sk_live_...\""
    }
  ],
  "blast_radius": "All API calls using WHOOP OAuth could be hijacked. Patient sleep data exposed.",
  "fix": "1. Rotate WHOOP credentials immediately. 2. Verify Secrets.swift is in .gitignore. 3. Consider git filter-branch or BFG to remove from history.",
  "verification": "gitleaks detect --source . --verbose | grep -i whoop → no results",
  "effort_hours": 2,
  "interest_rate": "latent — zero cost until credential is discovered by a bad actor, then catastrophic",
  "roi": "Very High"
}
```

Valid values:

- **pillar**: `hygiene` | `universal` | `security` | `cicd` | `dx` | `strategy`
- **severity**: `P0` | `P1` | `P2` | `P3`
- **label**: `CRITICAL` | `HIGH` | `MEDIUM` | `LOW` (must match severity mapping above)
- **category**: `correctness` | `security` | `architecture` | `process` | `docs` | `performance` | `observability` | `build`
- **interest_rate** (prefix): `compounding` | `latent` | `linear` | `deferred_cliff`
- **roi**: `Very High` | `High` | `Medium` | `Low`

---

## Execution Order (DO NOT REORDER)

### Phase 0 — Security Secrets Sweep (Stop-the-Bleeding)

**Goal**: Determine if the repo has ever had leaked credentials. This gates everything else.

**Scope**: `GUARDIAN_SECURITY_AUDIT.md` Phase 1 only (secrets in git history).

**Actions**:
1. Record environment context in `00_run_context.md`:
   - Current branch: `git branch --show-current`
   - Working tree status: `git status --short`
   - Tool versions: `swift --version`, `xcodebuild -version` (if available), `git --version`
   - Audit scope and known limitations (e.g., "xcodebuild not available in this environment")
2. Scan full git history for secrets:
   - Preferred: `gitleaks detect --source . --verbose --report-format json --report-path /tmp/gitleaks-report.json`
   - Fallback: `git log --all -p | grep -nE '(whoopClient(ID|Secret)|api[_-]?key|-----BEGIN.*PRIVATE|password\s*=\s*"[^"]+")' | head -100`
3. Check `.gitignore` covers: `Secrets.swift`, `*.p12`, `*.pem`, `*.key`, `.env`, `.env.*`
4. Check for committed build artifacts: `git ls-files | grep -E '\.(ipa|app|dSYM|xcarchive|o|d|p12|pem|key|mobileprovision)$'`
5. Write results to `01_security_secrets_sweep.md`.
6. Add findings to ledger.

**STOP CONDITION**:
- If any **P0/CRITICAL** secret is found → write a **Containment Plan** section:
  - What to rotate and where
  - Whether git history rewrite is needed (BFG / `git filter-repo`)
  - What tokens/keys to invalidate
  - Mark repo as "compromised until rotated" in `00_run_context.md`
- If clean → proceed.

---

### Phase 1 — Repo Hygiene + Build Graph + Atlas (Inventory Only)

**Goal**: Build the canonical inventory that all subsequent phases reuse. No destructive changes.

**Scope**: `REPO_HYGIENE_AND_ATLAS.md` Phases 0–3 + Phase 6 (atlas).

**Actions**:
1. Verify baseline builds (where tooling allows):
   - `swift build -q` (SwiftPM — DoseCore)
   - `swift test -q` (SwiftPM — DoseCoreTests, 525+ tests expected)
   - `bash tools/ssot_check.sh` (SSOT contradiction checker)
   - If `xcodebuild` available: `xcodebuild build -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
   - If `xcodebuild` NOT available: state this explicitly in `00_run_context.md` and perform static analysis of `project.pbxproj` instead.
2. Traverse entire file tree (depth 4). Document every directory with purpose.
3. Build the **Build Inclusion Map**:
   - Parse `Package.swift` → list all `DoseCore` sources (24 expected) and `DoseCoreTests` sources (30 expected).
   - Parse `ios/DoseTap.xcodeproj/project.pbxproj` → list compile sources per target.
   - Flag any `.swift` file NOT in any build target as a ghost.
4. Identify duplicates (same filename in multiple locations).
5. Generate the ASCII Architecture Atlas (Repo Map, Module/Target Map, Layered Diagram, Feature Breadcrumbs, Action→Function→File Mapping, Choke Points).
6. Produce a DRY_RUN cleanup script (do NOT execute).
7. Write results to `02_repo_hygiene_atlas.md`.
8. Add findings to ledger.

**STOP CONDITION**:
- Baseline builds pass (or failures are documented with evidence).
- Build Inclusion Map is complete for both SwiftPM and Xcode.
- Atlas is generated.

---

### Phase 2 — Universal Repo Audit (Correctness vs SSOT)

**Goal**: Deep semantic audit. Prove timing invariants. Find ghosts (documented but not implemented) and zombies (implemented but not documented).

**Scope**: `UNIVERSAL_REPO_AUDIT.md` all phases.

**IMPORTANT**: Reuse the Phase 1 inventory and build graph. Do NOT re-traverse directories or re-list file trees unless you need deeper detail on a specific area.

**Actions**:
1. Read governance documents (constitution, SSOT, architecture, copilot instructions).
2. Read every key file in `ios/Core/` (24 files) — verify correctness of domain logic against SSOT.
3. Read every key file in `ios/DoseTap/` — verify app layer wiring, service integration, notification handling.
4. Read test files in `Tests/DoseCoreTests/` — assess coverage and correctness.
5. Verify domain invariants (from `docs/SSOT/README.md`):
   - Dose 2 window: 150–240 minutes after Dose 1
   - Default target: 165 minutes
   - Session rollover: 6 PM local time
   - Snooze disabled: < 15 min remaining OR max snoozes reached
   - Snooze step: +10 minutes
   - Extra dose: `doseIndex >= 3` only; does not update `dose2_time`
   - Undo window: 5 seconds
6. Identify ghosts (SSOT says yes, code says no) and zombies (code exists, SSOT ignores).
7. Architecture check: state management leaks, notification ID consistency, channel parity, race conditions, time injection.
8. Write results to `03_universal_repo_audit.md`.
9. Add findings to ledger.

**STOP CONDITION**:
- All P0/P1 correctness issues have:
  - Reproduction conditions
  - Call-path breadcrumbs (function → function → file)
  - Proposed fix with acceptance criteria
  - Verification command/test

---

### Phase 3 — Full Security Audit

**Goal**: Complete security posture assessment (everything except secrets-in-history, which was Phase 0).

**Scope**: `GUARDIAN_SECURITY_AUDIT.md` Phases 2–5.

**Actions**:
1. Dependency audit: list all Swift packages from `Package.resolved`, check versions/licenses/CVEs/staleness.
2. Check for `.github/dependabot.yml` — flag if missing.
3. Entitlements vs code: compare `.entitlements` files against what code actually requests (HealthKit, iCloud, critical alerts, background modes).
4. Privacy manifest: check for `PrivacyInfo.xcprivacy`.
5. Data at rest: SQLite encryption, Keychain vs UserDefaults usage.
6. Data in transit: cert pinning integration, no `http://` URLs.
7. Logging safety: no `print()`, `os.Logger` privacy annotations.
8. CI security: actions pinned to SHA?, secrets scoped properly?, no `pull_request_target`?
9. Write results to `04_security_full.md`.
10. Add findings to ledger.

**STOP CONDITION**:
- Every HIGH/CRITICAL security item has a concrete fix plan and verification step.

---

### Phase 4 — CI/CD Automator Audit

**Goal**: Identify gaps in the build pipeline and propose hardening.

**Scope**: `AUTOMATOR_CICD_AUDIT.md` all phases.

**Actions**:
1. Read all 3 CI workflows line by line (`ci.yml`, `ci-swift.yml`, `ci-docs.yml`).
2. Map trigger conditions (what runs on PRs vs push vs tags).
3. Map job dependency graph.
4. Audit pre-commit hook (`.githooks/pre-commit`) — coverage, activation, bypass risk.
5. Audit PR template completeness.
6. Check branch protection (from `docs/BRANCH_PROTECTION.md` + GitHub settings).
7. Version pinning: Swift, Xcode, CI runner OS, GitHub Actions, SwiftPM deps.
8. Release pipeline: trace the full release path.
9. Write results to `05_cicd_automator.md`.
10. Add findings to ledger.

**STOP CONDITION**:
- CI gaps are converted into concrete workflow patches, required checks, and branch protection recommendations.

---

### Phase 5 — DX / Productivity Audit

**Goal**: Measure and reduce "clone to first passing test" time.

**Scope**: `PRODUCTIVITY_DX_AUDIT.md` all phases.

**Actions**:
1. Simulate the "fresh clone" test (or analyze statically if tooling is limited).
2. Grade documentation: README, TESTING_GUIDE, architecture doc, copilot instructions.
3. Check for one-command setup (Makefile, justfile, setup.sh) — propose if missing.
4. Build friction log (every point of confusion or manual step).
5. Assess DevContainer feasibility (DoseCore tests on Linux? docs contributors?).
6. Produce onboarding scorecard.
7. If `xcodebuild` is NOT available in this environment: explicitly state so, do best-effort static analysis of `.xcodeproj` and CI Xcode steps, and document what could not be verified.
8. Write results to `06_dx_productivity.md`.
9. Add findings to ledger.

**STOP CONDITION**:
- "One command setup" proposal includes all required steps.
- Friction log is complete with proposed fixes for each item.

---

### Phase 6 — Strategy / Tech Debt Synthesis

**Goal**: Quantify, rank, and produce a decision-ready backlog. This is synthesis, not discovery.

**Scope**: `STRATEGY_TECH_DEBT.md` all phases.

**IMPORTANT**: Base the Top-20 backlog **primarily on findings already in the ledger**. Do not invent new debt items without evidence. If you discover something new, add it to the ledger first.

**Actions**:
1. Scan for code complexity debt (files > 500 LOC, god objects, coupling).
2. Aggregate correctness, security, process, and documentation debt from the ledger.
3. Assign fix cost (hours), weekly carrying cost, interest rate, and ROI to each item.
4. Produce ranked Top-20 backlog with sprint targets.
5. Propose GitHub labels and issue template for debt tracking.
6. Propose the 20% rule cadence and debt prevention rules.
7. Produce executive summary.
8. Write results to `07_strategy_tech_debt.md`.
9. Finalize `findings.md`, `findings.json`, and `executive_summary.md`.

**STOP CONDITION**:
- Top-20 backlog exists with ROI/interest-rate framing and sprint targets.
- Executive summary is written and links to all phase reports.

---

## Required Final Synthesis

After all phases complete, produce `executive_summary.md` containing:

1. **Overall Health**: 🟢 Good / 🟡 Fair / 🔴 Poor — with one-sentence justification
2. **Audit Scope**: What was examined, branch, date, tool versions
3. **Key Metrics**: Total findings by severity (P0: N, P1: N, P2: N, P3: N), test count, LOC
4. **Top 3 Risks**: Business-impact framing (non-technical audience)
5. **Top 10 Recommended Actions**: Ordered by ROI, with effort estimates
6. **What We Could Not Verify**: Environment limitations, tools unavailable
7. **Links**: To each phase report in `docs/audit/YYYY-MM-DD/`

---

## Logging Discipline (Every Phase Report)

Each phase report (`01_*.md` through `07_*.md`) MUST contain:

1. **Environment & Preconditions** — branch, status, tool versions, prior phase results
2. **Command Log** — every command run and key output (truncated if verbose)
3. **Files Read** — list of files actually opened and scanned
4. **Findings Added** — list of `AUD-###` IDs added to the ledger in this phase
5. **Stop Condition Verification** — explicit pass/fail for each stop condition

---

## Begin Phase 0 Now.

Read `00_run_context.md` requirements above. Record the environment. Then execute the secrets sweep. Show your work.
