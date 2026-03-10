# DoseTap Audit & Governance Prompt Toolkit

> **Location**: `docs/prompt/`
> **Last updated**: 2026-02-15
> **Audience**: AI agents, human auditors, new maintainers

---

## What This Is

A set of seven purpose-built prompts that, when run in sequence, produce a complete evidence-based audit of the DoseTap repository — from secret leaks to code correctness to developer onboarding friction.

Each prompt can be run **standalone** (paste into a fresh agent session with the repo attached) or **orchestrated** via the Master Runbook for a consolidated audit with a single findings ledger.

---

## The Toolkit

| # | File | Pillar | Purpose | Standalone? |
|---|---|---|---|---|
| 0 | [`MASTER_RUNBOOK.md`](MASTER_RUNBOOK.md) | 🎯 Orchestrator | Runs all six prompts in sequence with shared findings ledger, unified severity, and stop conditions | **Start here** for full audit |
| 1 | [`REPO_HYGIENE_AND_ATLAS.md`](REPO_HYGIENE_AND_ATLAS.md) | 🧹 Geography | File tree hygiene, SSOT alignment, build graph inventory, ASCII architecture atlas, DRY_RUN cleanup script | ✅ Yes |
| 2 | [`UNIVERSAL_REPO_AUDIT.md`](UNIVERSAL_REPO_AUDIT.md) | 📋 Engine | Exhaustive scan-then-plan code audit, ghost/zombie detection, SSOT gap analysis, correctness verification | ✅ Yes |
| 3 | [`GUARDIAN_SECURITY_AUDIT.md`](GUARDIAN_SECURITY_AUDIT.md) | 🛡️ Guardian | Secrets in git history, dependency CVEs/licenses, entitlements vs code, cert pinning, privacy manifest, CI security | ✅ Yes |
| 4 | [`AUTOMATOR_CICD_AUDIT.md`](AUTOMATOR_CICD_AUDIT.md) | ⚙️ Automator | CI workflow coverage matrix, pre-commit hook audit, PR process, build reproducibility, release pipeline | ✅ Yes |
| 5 | [`PRODUCTIVITY_DX_AUDIT.md`](PRODUCTIVITY_DX_AUDIT.md) | 🚀 Productivity | "Fresh clone" test, one-command setup (Makefile), documentation quality, friction log, onboarding scorecard | ✅ Yes |
| 6 | [`STRATEGY_TECH_DEBT.md`](STRATEGY_TECH_DEBT.md) | 📊 Strategy | Debt inventory with quantified interest rates, ROI-based top-20 backlog, GitHub label/template system, executive summary | ✅ Yes |

---

## Run Order (Why This Sequence)

The prompts are ordered to minimize wasted work and catch catastrophic problems first:

```
Phase 0 ─ Guardian Phase 1 (secrets in git history)
   │       Stop-the-bleeding. If creds found, rotate before continuing.
   ▼
Phase 1 ─ Repo Hygiene + Atlas (inventory + build graph)
   │       Canonical data-gathering. No destructive changes.
   ▼
Phase 2 ─ Universal Repo Audit (correctness vs SSOT)
   │       Deep semantic scan. Reuses Phase 1 inventory.
   ▼
Phase 3 ─ Guardian Phases 2–5 (deps, entitlements, runtime, CI security)
   │       Security posture, grounded in what actually executes.
   ▼
Phase 4 ─ Automator CI/CD Audit
   │       Harden pipeline based on known gaps.
   ▼
Phase 5 ─ Productivity / DX Audit
   │       Optimize onboarding with real build/test/guardrail knowledge.
   ▼
Phase 6 ─ Strategy / Tech Debt Synthesis
           Quantify + rank. Produces decision-ready Top-20 backlog.
```

Each phase has explicit **stop conditions** (documented in the Master Runbook). No phase proceeds until the prior phase's stop conditions are met.

---

## Unified Severity Mapping

All prompts use one severity scale (enforced by the Master Runbook):

| Severity | Label | DoseTap Definition | Examples |
|---|---|---|---|
| **P0** | CRITICAL | Patient safety, dose timing incorrect, alarm not delivered, data loss/corruption, leaked credentials | Dose window math wrong, orphan alarms after session delete, API key in git history |
| **P1** | HIGH | Feature broken for a channel, notification system broken, security control missing with real exposure | Flic button → no alarms scheduled, notification ID mismatch, `macos-latest` floating runner |
| **P2** | MEDIUM | Missing feature, degraded UX, permission gaps, reproducibility drift, missing automation | No permission recovery, no Dependabot, no code coverage tracking |
| **P3** | LOW | Code smell, dead code, missing docs, cosmetic, small maintainability wins | Dead `alarm_tone.caf` check, stale archive contents, TODO comments |

---

## Output Structure (Full Audit)

When run via the Master Runbook, the audit produces:

```
docs/audit/YYYY-MM-DD/
├── 00_run_context.md              ← Branch, status, tool versions, scope
├── 01_security_secrets_sweep.md   ← Phase 0: secrets in history
├── 02_repo_hygiene_atlas.md       ← Phase 1: inventory + atlas
├── 03_universal_repo_audit.md     ← Phase 2: correctness + SSOT
├── 04_security_full.md            ← Phase 3: deps, entitlements, runtime
├── 05_cicd_automator.md           ← Phase 4: CI/CD gaps
├── 06_dx_productivity.md          ← Phase 5: onboarding + DX
├── 07_strategy_tech_debt.md       ← Phase 6: debt backlog + governance
├── findings.md                    ← Consolidated findings ledger (human)
├── findings.json                  ← Machine-readable findings array
└── executive_summary.md           ← One-page non-technical summary
```

The **findings ledger** is the single source of truth. Every phase appends to it. The executive summary and strategy backlog are derived from it.

---

## Two-Pass Workflow (Recommended)

**Pass A — Audit (read-only branch):**
Run the Master Runbook on a `chore/audit-YYYY-MM-DD` branch. Produce inventory, findings, DRY_RUN scripts, and SSOT patches — but do NOT execute destructive changes. This preserves the original state for reproducibility.

**Pass B — Cleanup (implementation branch):**
Create `chore/repo-hygiene-YYYY-MM-DD` from the audit branch. Apply `git mv`/`git rm` from the DRY_RUN script, rewrite SSOT directory sections, and re-run all stop conditions (`swift build -q`, `swift test -q`, `tools/ssot_check.sh`). Open a PR.

---

## Standalone Usage

Any prompt can be used independently. To run one:

1. Open a fresh agent session (Copilot Chat, Claude, etc.)
2. Attach or provide access to the DoseTap repo
3. Paste the entire contents of the prompt file
4. Let the agent execute

Each prompt is pre-filled with DoseTap-specific paths, file counts, build commands, known hotspots, and severity definitions. No placeholders to replace.

---

## Maintenance

When the repo structure changes significantly:
- Update the prompts to reflect new file paths, test counts, and known hotspots
- Update the Master Runbook stop conditions if CI workflows change
- Bump the "Last updated" date in each modified prompt

The prompts reference these authority documents (keep in sync):
- `.specify/memory/constitution.md`
- `docs/SSOT/README.md`
- `docs/architecture.md`
- `.github/copilot-instructions.md`
