# Phase 6 — Strategy & Technical Debt Synthesis

> Audit date: 2026-02-15  
> Branch: `chore/audit-2026-02-15` (from `004-dosing-amount-model`)  
> Reference: `docs/prompt/STRATEGY_TECH_DEBT.md`

---

## 1. Debt Discovery

### 1.1 — Code Complexity Debt

Files > 500 LOC (sorted by size):

| File | LOC | Responsibility | Debt Type | Interest Rate |
| --- | --- | --- | --- | --- |
| `SessionRepository.swift` | 1,712 | Session SSOT, dose tracking, notification cancel, rollover, check-in, export, undo, analytics | God object | **Compounding** — every feature adds coupling |
| `PreSleepLogView.swift` | 1,440 | Pre-sleep logging UI — multi-step form | Large view | Linear — isolated, but hard to modify |
| `DashboardModels.swift` | 1,423 | Dashboard state models, computed properties | Data layer bloat | Linear — read-heavy, rarely changed |
| `TimelineReviewViews.swift` | 1,346 | Timeline visualization components | Large view | Linear — isolated |
| `HistoryViews.swift` | 1,177 | History list + detail views | Large view | Linear — isolated |
| `SleepStageTimeline.swift` | 996 | Sleep stage visualization | Large view | Linear — isolated |
| `DashboardViews.swift` | 974 | Dashboard UI components | Large view | Linear — sibling to DashboardModels |
| `MorningCheckInView.swift` | 869 | Multi-step morning check-in flow | Large view | Linear |
| `StorageModels.swift` | 866 | Core Data model definitions | Data layer | Linear — stable |
| `EventStorage+CheckIn.swift` | 824 | Check-in storage operations | Storage extension | Linear |
| `DosingAmountSchema.swift` | 762 | Dosing amount data schema | Data layer | Linear — new, may grow |
| `NightReviewView.swift` | 720 | Night review visualization | Large view | Linear |
| `FlicButtonService.swift` | 712 | Flic hardware + dose logic | Feature envy | **Compounding** — duplicates dose paths |
| `SupportBundleExport.swift` | 702 | Debug support bundle generation | Utility | Low — rarely changed |
| `EventStorage+Session.swift` | 702 | Session storage operations | Storage extension | Linear |
| `AlarmService.swift` | 606 | Alarm scheduling, snooze, notifications | Hidden coupling | **Latent** — notification ID mismatch |
| `SettingsView.swift` | 697 | Settings UI | Large view | Linear |
| `DoseAmountPicker.swift` | 675 | Dose amount selection UI | Large view | Linear |

**Key concern**: `SessionRepository.swift` at 1,712 LOC is the #1 god object. It owns session lifecycle, dose recording, notification management, rollover, undo, and export coordination. Every new feature must navigate this file.

### 1.2 — Correctness Debt

| Issue | Blast Radius | Trigger Condition | Detection Time | Ref |
| --- | --- | --- | --- | --- |
| Notification ID mismatch (SessionRepository vs AlarmService) | All users with alarms | Any alarm cancel/reschedule path | Minutes–hours (orphan alerts) | Prior audit |
| FlicButtonService dose-1 path skips alarm scheduling | Flic hardware users | Press Flic for dose 1 | Until dose 2 window — no alarm fires | Prior audit |
| FlicButtonService skip path skips alarm cancellation | Flic hardware users | Skip dose via Flic | Orphan alarm fires unexpectedly | Prior audit |
| URLRouter bypasses DoseTapCore for extra doses | Deep-link/Siri users | Extra dose via URL scheme | Silent — dose logged but side effects missing | COR-002 |
| SleepEventType missing nap events vs app EventType | Core API consumers | If Core ever needs nap routing | Silent — nap events lost in Core layer | COR-001 |
| CloudKit entitlement but no implementation | All users | App Store review | App may be questioned or rejected | SEC-005 |
| Missing PrivacyInfo.xcprivacy | All users | Spring 2024+ App Store submission | Rejection or privacy warning | SEC-006 |

### 1.3 — Architectural Debt

| Issue | Description | Impact |
| --- | --- | --- |
| 6 quarantined `#if false` files | `TimeEngine.swift`, `EventStore.swift`, `UndoManager.swift`, `DoseTapCore.swift`, `ContentView_Old.swift`, `DashboardView.swift` — dead code with user approval to quarantine | Low — but confuses new devs |
| Dual build system drift risk | SwiftPM `Package.swift` (24 core files) + Xcode `project.pbxproj` (full app). File lists can drift silently | Medium — caught by CI, but not fast |
| Orphan `ios/DoseTap/Package.swift` | Vestigial embedded package definition conflicts with root | Low (HYG-004) |
| `docs/archive/` bloat | 72 tracked files, mostly 2025-12 session logs | Low — repo size drag |
| Abandoned directories | `shadcn-ui/` (0 tracked), `agent/` (0 tracked) on disk | Low — confusion for new devs |
| `macos/` and `watchos/` | 18 and 20 tracked files respectively — incomplete companion apps | Medium — maintained or abandoned? |

### 1.4 — Process Debt

| Issue | Impact |
| --- | --- |
| Long-lived branch: 101 commits ahead of main | **Deferred cliff** — merge risk grows daily. Conflict probability increases with each main-branch commit |
| No Dependabot/Renovate | SwiftPM deps not auto-updated. No CVE alerts for transitive deps |
| No code coverage tracking | Cannot measure test effectiveness. Regressions in coverage go undetected |
| No performance benchmarks | No way to detect timing regressions in dose window math |
| Duplicate CI jobs | SwiftPM tests run twice per PR (ci.yml + ci-swift.yml). Xcode build runs twice. Wasted ~8 min/PR |
| Manual Secrets.swift setup | Blocks Xcode build for new devs. No automation |
| Pre-commit hook manual activation | Safety net not active by default |

### 1.5 — Security Debt

| Issue | Impact |
| --- | --- |
| 2× WHOOP client secrets in git history | **P0** — must rotate and purge (SEC-001, SEC-002) |
| Plaintext secret in archive doc on HEAD | **P1** — redact immediately (SEC-003) |
| 7 missing .gitignore patterns | **P1** — *.p12, *.pem, *.key, .env, etc. (SEC-004) |
| .cache_ggshield tracked with secret hash | **P1** — remove from tracking (HYG-001) |
| No secret scanning in CI | **P3** — gitleaks/ggshield absent from pipeline (CICD-007) |

### 1.6 — Documentation Debt

| Issue | Impact |
| --- | --- |
| README missing prerequisites, Secrets setup, hook activation | New dev friction — 15+ min to first app build |
| No contributing guide | Unclear how to contribute |
| Architecture.md lacks "where to put new code" | Copilot-instructions has it, but humans don't read that file |
| No API documentation for DoseCore public surface | Consumers must read source |

---

## 2. Debt Valuation

| # | Debt Item | Fix Cost | Weekly Carry Cost | Risk if Unfixed | ROI |
| --- | --- | --- | --- | --- | --- |
| 1 | Rotate WHOOP secrets + BFG purge | 3h | Credential exposure risk | P0: active leak | **Critical** |
| 2 | Add PrivacyInfo.xcprivacy | 1h | 0 until submission | P1: App Store rejection | Very High |
| 3 | Redact secret from archive doc | 0.5h | Exposure per clone | P1: secret on HEAD | Very High |
| 4 | Add 7 .gitignore patterns | 0.5h | Risk per commit | P1: accidental commit | Very High |
| 5 | Remove .cache_ggshield from tracking | 0.5h | Secret hash exposed | P1: ggshield cache leak | Very High |
| 6 | Merge branch to main | 4h | Conflict risk grows daily | P1: merge hell at 101 commits | Very High |
| 7 | Deduplicate CI jobs | 2h | ~8 min wasted per PR | P2: CI cost + feedback delay | High |
| 8 | Create Makefile for setup automation | 2h | 30 min per new dev | P2: onboarding friction | High |
| 9 | Fix notification ID mismatch | 2h | 1h per orphan alarm incident | P1: phantom alerts for users | Very High |
| 10 | Wire AlarmService into FlicButtonService | 3h | 0 until Flic user reports | P1: silent alarm failure | High |
| 11 | Route URLRouter extra dose through DoseTapCore | 1h | 0 until URL-scheme use | P2: channel parity gap | High |
| 12 | Remove CloudKit entitlement | 0.5h | 0 until App Review | P2: review questions | High |
| 13 | Document Secrets.swift setup in README | 0.5h | 15 min per new dev | P2: onboarding block | High |
| 14 | Document pre-commit hook in README | 0.5h | Risk of unguarded commits | P2: safety gap | High |
| 15 | Consolidate CI workflows | 3h | Maintenance across 3 files | P2: CI complexity | Medium |
| 16 | Add Dependabot for SwiftPM | 1h | 0 until CVE hits | P2: unpatched deps | Medium |
| 17 | Archive quarantined #if false files | 1h | 5 min per audit | P3: confusion | Medium |
| 18 | Clean orphan Python scripts from ios/ | 0.5h | Confusion for new devs | P3: clutter | Low |
| 19 | Add .swift-version file | 0.25h | 0 until version mismatch | P3: env drift | Low |
| 20 | Add code coverage tracking to CI | 2h | 0 until regression | P3: invisible coverage drops | Medium |

---

## 3. Prioritized Top-20 Backlog

| Rank | Title | Category | Priority | Cost | ROI | Sprint Target |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Rotate WHOOP secrets + BFG history purge | Security | P0 | 3h | Critical | **Immediate** |
| 2 | Redact secret from archive doc on HEAD | Security | P1 | 0.5h | Very High | **Immediate** |
| 3 | Add 7 missing .gitignore patterns | Security | P1 | 0.5h | Very High | **Immediate** |
| 4 | Remove .cache_ggshield from git tracking | Security | P1 | 0.5h | Very High | **Immediate** |
| 5 | Create PrivacyInfo.xcprivacy manifest | Security | P1 | 1h | Very High | **This sprint** |
| 6 | Fix notification ID mismatch | Correctness | P1 | 2h | Very High | **This sprint** |
| 7 | Wire AlarmService into FlicButtonService | Correctness | P1 | 3h | High | **This sprint** |
| 8 | Merge 004 branch to main | Process | P1 | 4h | Very High | **This sprint** |
| 9 | Create Makefile for one-command setup | DX | P2 | 2h | High | **This sprint** |
| 10 | Document Secrets.swift + pre-commit in README | DX | P2 | 1h | High | **This sprint** |
| 11 | Deduplicate CI jobs (remove ci-swift.yml overlap) | CI/CD | P2 | 2h | High | Next sprint |
| 12 | Route URLRouter extra dose through DoseTapCore | Correctness | P2 | 1h | High | Next sprint |
| 13 | Remove CloudKit entitlement | Security | P2 | 0.5h | High | Next sprint |
| 14 | Add Dependabot for SwiftPM deps | Process | P2 | 1h | Medium | Next sprint |
| 15 | Standardize CI runner versions | CI/CD | P2 | 1h | Medium | Next sprint |
| 16 | Add code coverage tracking | Process | P3 | 2h | Medium | Sprint +2 |
| 17 | Archive quarantined #if false files | Architecture | P3 | 1h | Medium | Sprint +2 |
| 18 | Clean orphan Python scripts from ios/ | Hygiene | P3 | 0.5h | Low | Sprint +2 |
| 19 | Add .swift-version file | DX | P3 | 0.25h | Low | Sprint +2 |
| 20 | Add concurrency group to ci-swift.yml | CI/CD | P3 | 0.5h | Low | Sprint +2 |

**Total estimated fix cost for Top 20: ~27 hours** (roughly 3.5 dev-days).

---

## 4. Governance Recommendations

### 4.1 — GitHub Labels

```
tech-debt/security      — Credential leaks, missing manifests, entitlement gaps
tech-debt/correctness   — Bugs waiting to happen (notification IDs, channel parity)
tech-debt/architecture  — God objects, coupling, dead code
tech-debt/process       — CI/CD, tooling, workflow gaps
tech-debt/dx            — Onboarding friction, missing docs, setup automation
```

### 4.2 — Issue Template

```markdown
## Technical Debt Item

**Category**: [security / correctness / architecture / process / dx]
**Priority**: [P0 / P1 / P2 / P3]
**Fix Cost**: [hours]
**Carrying Cost**: [what it costs to leave unfixed]
**ROI**: [Critical / Very High / High / Medium / Low]

### Problem
[What is the debt? File paths and evidence.]

### Impact
[What happens if unfixed? Who is affected?]

### Proposed Fix
[Concrete steps.]

### Acceptance Criteria
- [ ] [Specific, testable criteria]
```

### 4.3 — The 20% Rule

- **Every sprint**: Reserve 20% of capacity for debt items from the ranked backlog
- **Priority rule**: Always address at least one P0/P1 item per sprint until none remain
- **Tracking**: Tag issues with `tech-debt/*` labels. Review debt count in sprint planning
- **Burndown**: Track total open debt items over time. Target: monotonically decreasing

### 4.4 — Debt Prevention Rules

1. **PR checklist** (already exists): Add "Does this PR introduce new tech debt? If yes, file a tracking issue."
2. **File size gate**: Pre-commit already warns >2000 LOC. Consider adding >1000 LOC soft warning.
3. **SSOT-first rule**: Already enforced. Any behavior change must update SSOT before code.
4. **CI consolidation**: Before adding new CI workflows, check for overlap with existing ones.
5. **Dependency review**: Enable Dependabot; review dependency updates monthly.

---

## Findings Added to Ledger

| ID | Pillar | Sev | Title |
| --- | --- | --- | --- |
| DEBT-001 | Strategy | P0 | Total identified debt: 32 items (2 P0, 6 P1, 14 P2, 10 P3). Estimated 27h to clear Top 20 |

---

## Files Read

All previous phase reports (`01`–`06`), `findings.json`, `findings.md`, `docs/prompt/STRATEGY_TECH_DEBT.md`

## Commands Run

```
find ios/ -name '*.swift' -exec wc -l {} + | sort -rn | head -20
grep -rl '#if false' ios/
git log --oneline main..HEAD | wc -l  →  101
git ls-files build/ | wc -l  →  0
for d in agent specs macos watchos shadcn-ui; git ls-files $d/ | wc -l
wc -l ios/DoseTap/AlarmService.swift  →  606
wc -l ios/DoseTap/FlicButtonService.swift  →  712
```

## Stop Condition

✅ Top-20 backlog with ROI framing exists.  
✅ Governance recommendations (labels, template, 20% rule, prevention) documented.  
✅ All findings aggregated from prior phases.  
✅ Cost estimates assigned to every item.
