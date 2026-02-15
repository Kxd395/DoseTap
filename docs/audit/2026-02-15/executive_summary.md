# DoseTap Audit — Executive Summary

> **Date**: 2026-02-15  
> **Branch**: `chore/audit-2026-02-15` (from `004-dosing-amount-model`)  
> **Auditor**: Automated (7-phase skill-driven audit)  
> **Scope**: Full repository — security, hygiene, correctness, CI/CD, DX, tech debt

---

## Overall Health: 🟡 Fair

The core domain logic is solid — 525+ deterministic tests, platform-free architecture, SSOT-driven development. However, **two leaked credentials in git history** and **several notification correctness bugs** prevent a "Good" rating.

---

## Key Metrics

| Metric | Value |
| --- | --- |
| SwiftPM tests | 525+ (all passing, 30 test files) |
| Core library | 24 files in `ios/Core/` (platform-free) |
| App layer | ~80+ files in `ios/DoseTap/` |
| Total findings | **33** (2 P0, 6 P1, 14 P2, 11 P3) |
| Estimated fix cost (Top 20) | ~27 hours (~3.5 dev-days) |
| Branch divergence | 101 commits ahead of main |
| CI workflows | 3 (with redundancy) |
| DX onboarding grade | 2.5 / 5 |

---

## Top 3 Risks

### 1. 🔴 Leaked Credentials (P0)
Two WHOOP OAuth client secrets are in git history (11+ files). One secret is still readable in a tracked archive document on HEAD. Any clone of this repo exposes these credentials. **Action: Rotate immediately and purge history with BFG.**

### 2. 🟠 Notification System Correctness (P1)
`SessionRepository` and `AlarmService` use different notification identifier sets. Cancel calls target wrong IDs, producing orphan alarms. `FlicButtonService` dose-1 path doesn't schedule alarms at all. **Users may receive phantom alerts or miss real ones.**

### 3. 🟠 App Store Submission Blockers (P1)
Missing `PrivacyInfo.xcprivacy` manifest (required since Spring 2024) and an unused CloudKit entitlement will trigger App Store review questions or rejection. **Must fix before any TestFlight or App Store submission.**

---

## Top 10 Actions (Ordered by ROI)

| # | Action | Cost | Fixes Risk |
| --- | --- | --- | --- |
| 1 | Rotate WHOOP secrets at developer.whoop.com | 1h | Credential exposure |
| 2 | BFG purge secrets from git history | 2h | History exposure |
| 3 | Redact secret from `docs/archive/audits_2026-01/RED_TEAM_AUDIT*.md` | 0.5h | HEAD exposure |
| 4 | Add 7 missing .gitignore patterns (*.p12, *.pem, .env, etc.) | 0.5h | Accidental commit risk |
| 5 | Create `PrivacyInfo.xcprivacy` | 1h | App Store rejection |
| 6 | Unify notification IDs (SessionRepository + AlarmService) | 2h | Orphan/phantom alarms |
| 7 | Wire AlarmService into FlicButtonService dose/skip paths | 3h | Silent alarm failure for Flic users |
| 8 | Merge `004-dosing-amount-model` branch to main | 4h | Merge conflict escalation |
| 9 | Create `Makefile` for one-command setup | 2h | Onboarding friction |
| 10 | Document Secrets.swift + pre-commit hook in README | 1h | New developer confusion |

**Total for Top 10: ~17 hours (~2 dev-days)**

---

## Findings by Severity

| Severity | Count | Examples |
| --- | --- | --- |
| **P0 — Critical** | 2 | WHOOP secrets in git history (SEC-001, SEC-002) |
| **P1 — High** | 6 | Secret on HEAD (SEC-003), missing .gitignore patterns (SEC-004), ggshield cache tracked (HYG-001), missing privacy manifest (SEC-006) |
| **P2 — Medium** | 14 | Duplicate files (HYG-002/003), CI overlap (CICD-001/002), channel parity (COR-002), onboarding gaps (DX-001/002/005) |
| **P3 — Low** | 11 | Dead code, SwiftLint config, orphan scripts, cosmetic docs gaps |

---

## Audit Phases Completed

| Phase | Report | Key Finding |
| --- | --- | --- |
| 0 — Secrets Sweep | `01_security_secrets_sweep.md` | 2 P0 leaked credentials |
| 1 — Repo Hygiene | `02_repo_hygiene_atlas.md` | ggshield cache tracked, duplicates |
| 2 — Correctness | `03_universal_audit.md` | EventType split-brain, URLRouter bypass |
| 3 — Security | `04_security_audit.md` | Missing privacy manifest, CloudKit ghost |
| 4 — CI/CD | `05_cicd_audit.md` | Duplicate jobs, runner inconsistency |
| 5 — DX & Productivity | `06_dx_productivity.md` | No setup automation, DX grade 2.5/5 |
| 6 — Strategy & Tech Debt | `07_strategy_tech_debt.md` | 27h to clear Top 20, 1,712 LOC god object |

---

## Limitations

1. **No runtime testing performed.** Audit is static analysis + build verification only. Notification behavior, alarm delivery, and HealthKit integration were assessed via code review, not device testing.
2. **Flic hardware not available.** FlicButtonService correctness assessed via code paths only.
3. **No dependency CVE scan.** `gitleaks` used for secrets; no `osv-scanner` or `snyk` for dependency vulnerabilities.
4. **Coverage data not available.** No code coverage tooling in CI to measure actual test coverage percentages.
5. **watchOS and macOS targets not audited.** Focus was on the primary iOS app and DoseCore library.

---

## Links

- [Phase 0: Secrets Sweep](01_security_secrets_sweep.md)
- [Phase 1: Repo Hygiene & Atlas](02_repo_hygiene_atlas.md)
- [Phase 2: Universal Audit](03_universal_audit.md)
- [Phase 3: Security Audit](04_security_audit.md)
- [Phase 4: CI/CD Audit](05_cicd_audit.md)
- [Phase 5: DX & Productivity](06_dx_productivity.md)
- [Phase 6: Strategy & Tech Debt](07_strategy_tech_debt.md)
- [Findings Ledger (human)](findings.md)
- [Findings Ledger (JSON)](findings.json)
