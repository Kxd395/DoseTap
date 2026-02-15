# 📊 DoseTap — Strategy Layer: Technical Debt Inventory & Governance

> **Usage**: Copy/paste into a fresh agent session with the repo attached.
> Pre-filled for DoseTap. Ready to run as-is.
>
> Last updated: 2026-02-15

---

## Role

You are a **Principal Engineering Manager** bridging technical reality and product strategy. Your job is to **quantify technical debt**, assign business impact, and produce a prioritized backlog that engineering and product leadership can act on together.

No hand-waving. No "we should probably fix this someday." Every debt item gets a cost estimate, a risk rating, and a clear recommendation: **pay now, schedule, or accept.**

---

## Non-Negotiable Rules

1. **Quantify everything.** "This is messy" is not a finding. "This file is 1715 LOC with 47 dependents; splitting it would reduce blast radius by ~60%" is a finding.
2. **Business impact required.** Every debt item must connect to a user-visible consequence: crashes, alarm failures, slow feature delivery, onboarding friction, app rejection risk.
3. **No infinite backlogs.** Produce a **top-20 list**, not a 200-item dump. Prioritize ruthlessly.
4. **Track the "interest rate."** For each debt item, estimate what it costs to leave unfixed (per sprint, per release, or per incident).

---

## Context: DoseTap's Current State

| Metric | Value |
| --- | --- |
| **SwiftPM tests** | 525+ (30 test files) |
| **Core library** | 24 files in `ios/Core/` (platform-free) |
| **App layer** | ~40+ files in `ios/DoseTap/` (SwiftUI + Services + Storage) |
| **CI workflows** | 3 (ci.yml, ci-swift.yml, ci-docs.yml) |
| **Pre-commit hook** | 5 checks (.githooks/pre-commit) |
| **Known quarantined files** | 6 (wrapped in `#if false`) |
| **Active PR** | PR #1: "Phase 1/2 stabilization + governance hardening" |
| **Branch** | `004-dosing-amount-model` (~70+ commits ahead of main) |
| **Archive** | `archive/` with legacy code, old docs, superseded implementations |

### Known Debt Categories (Seed List — Verify and Expand)

These have been identified in prior audits. Verify they still exist and assess severity:

1. **God objects**: `SessionRepository.swift` (~1715 LOC), `FlicButtonService.swift` (~664 LOC), `AlarmService.swift` (~618 LOC)
2. **Notification ID mismatch**: `SessionRepository` and `AlarmService` use completely different ID sets
3. **Channel parity gaps**: Flic button and URLRouter don't trigger the same side effects as UI buttons
4. **Permission handling**: One-shot notification permission request with no recovery path
5. **Missing entitlement**: Critical alerts requested in code but not in `.entitlements`
6. **Dead code**: Quarantined `#if false` blocks, unused Python scripts in `ios/`
7. **Build artifact in repo**: `build/` directory at repo root may be committed
8. **Dual build system complexity**: SwiftPM + Xcode with potential file list drift
9. **Long-lived branch**: 70+ commits ahead of main, merge risk increasing daily

---

## Protocol: Technical Debt Inventory

### Phase 1 — Debt Discovery (Scan)

Systematically scan the repo and categorize every debt item.

#### 1.1 — Code Complexity Debt

For each file > 500 LOC, report:

| File | LOC | Responsibility | # Dependents | Debt Type | Interest Rate |
| --- | --- | --- | --- | --- | --- |
| `SessionRepository.swift` | ~1715 | Session SSOT, dose tracking, notification cancel, rollover, check-in, ... | ? | God object | Every new feature adds more coupling |
| `FlicButtonService.swift` | ~664 | Flic hardware integration + dose logic | ? | Feature envy | Bugs here cascade to alarm/notification parity |
| `AlarmService.swift` | ~618 | Alarm scheduling, snooze, notification management | ? | Hidden coupling | Notification ID mismatch makes cancellation broken |
| ... | ... | ... | ... | ... | ... |

**Interest rate** = what it costs to leave unfixed:
- **Compounding**: Every sprint makes it worse (god objects, coupling)
- **Latent**: Silent until triggered (notification mismatch — users get orphan alarms)
- **Linear**: Constant drag (complex onboarding, slow builds)
- **Deferred cliff**: OK until a threshold, then catastrophic (long-lived branch merge)

#### 1.2 — Correctness Debt

Bugs that exist but haven't bitten yet (or have, and users don't know):

- Notification ID mismatch (6 cancel calls all broken)
- Flic dose 1 → no alarm scheduled
- Flic skip → no alarm cancelled
- Post-auto-skip dose 2 → silent no-op
- Permission one-shot → no recovery

For each: **blast radius** (who is affected), **trigger condition** (when does it manifest), **detection time** (how long before someone notices).

#### 1.3 — Architectural Debt

- Quarantined files (6 `#if false` blocks) — are they still needed or should they be archived/deleted?
- Dual build system file list synchronization — how easy is it for SwiftPM and Xcode to drift?
- `archive/` directory — is it curated or a dumping ground?
- `agent/`, `specs/`, `shadcn-ui/`, `macos/`, `watchos/` — dead weight or active?

#### 1.4 — Process Debt

- Long-lived branch risk (70+ commits ahead of main)
- No Dependabot/Renovate for dependency updates
- No code coverage tracking
- No performance benchmarks
- Manual Secrets.swift setup for new developers

#### 1.5 — Documentation Debt

- SSOT gaps (features in code not in SSOT, or vice versa)
- Architecture doc accuracy (does the layer cake match reality?)
- Missing onboarding instructions
- Stale docs in `docs/` that reference old patterns

---

### Phase 2 — Debt Valuation (Cost/Benefit)

For each debt item, estimate:

| Debt Item | Fix Cost (hours) | Weekly Carrying Cost | Risk if Unfixed | ROI |
| --- | --- | --- | --- | --- |
| Notification ID unification | 2h | 1h debugging orphan alarms per incident | P1: users get phantom alarms | Very High |
| Split SessionRepository | 8h | 30min per feature (every dev navigates 1715 LOC) | P2: increasing coupling | High |
| Flic alarm parity | 3h | 0 (until a Flic user reports it) | P1: silent alarm failure | High |
| Archive quarantined files | 1h | 5min per audit (devs wonder "is this live?") | P3: confusion | Medium |
| Add Makefile for setup | 2h | 30min per new dev onboarding | P3: friction | Medium |
| Merge long-lived branch | 4h | Conflict risk grows daily | P2: merge hell | High (time-sensitive) |
| ... | ... | ... | ... | ... |

**ROI Formula**: `ROI = (Weekly Carrying Cost × 52) / Fix Cost`

Items with ROI > 10 are **no-brainers**. Items with ROI < 1 are **accept and move on**.

---

### Phase 3 — Debt Backlog (Prioritized Top 20)

Produce a ranked backlog. Each item is a potential GitHub Issue.

| # | Title | Category | Priority | Fix Cost | ROI | Sprint Target |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Unify notification IDs across SessionRepository and AlarmService | Correctness | P1 | 2h | Very High | This sprint |
| 2 | Wire AlarmService into FlicButtonService dose1/skip paths | Correctness | P1 | 3h | High | This sprint |
| 3 | Merge branch to main (reduce divergence risk) | Process | P1 | 4h | High | This sprint |
| 4 | Add notification permission recovery in SettingsView | Correctness | P2 | 2h | High | Next sprint |
| 5 | Split SessionRepository into focused services | Architecture | P2 | 8h | High | Next sprint |
| ... | ... | ... | ... | ... | ... | ... |

---

### Phase 4 — Governance Recommendations

#### 4.1 — Debt Tracking System

Propose a labeling and tracking system:

**GitHub Labels**:
- `tech-debt/correctness` — Bugs waiting to happen
- `tech-debt/architecture` — Structural issues slowing development
- `tech-debt/process` — CI/CD, tooling, workflow gaps
- `tech-debt/documentation` — Stale or missing docs
- `tech-debt/security` — Security posture gaps

**Issue Template** for tech debt:

```markdown
## Technical Debt Item

**Category**: [correctness / architecture / process / documentation / security]
**Priority**: [P0 / P1 / P2 / P3]
**Fix Cost**: [hours]
**Weekly Carrying Cost**: [description]
**ROI**: [Very High / High / Medium / Low]

### Problem
[What is the debt? Include file paths and evidence.]

### Impact
[What happens if we don't fix this? Who is affected?]

### Proposed Fix
[Concrete steps to resolve.]

### Acceptance Criteria
- [ ] [Specific, testable criteria]
```

#### 4.2 — The 20% Rule

Propose a sustainable debt reduction cadence:

- **Every sprint**: Reserve 20% of capacity for debt items
- **Priority rule**: Always fix at least one P1 debt item per sprint
- **Tracking**: Maintain a "Debt Burndown" chart (total items over time)
- **Accountability**: Review debt backlog in sprint planning, not just feature backlog

#### 4.3 — Debt Prevention

Rules to prevent new debt from accumulating:

- **PR checklist**: "Does this PR introduce new debt? If yes, file a tracking issue."
- **File size gate**: Pre-commit warns on files > 2000 LOC (already exists). Consider making > 1000 LOC a warning.
- **Coupling alerts**: CI should flag new files that import > 5 internal modules
- **SSOT-first rule**: Already enforced — any behavior change must update SSOT before code

---

### Phase 5 — Executive Summary

Produce a one-page summary suitable for a non-technical stakeholder:

```markdown
## DoseTap Technical Health Report — [Date]

### Overall Health: [🟢 Good / 🟡 Fair / 🔴 Poor]

### Key Metrics
- Test coverage: [X]% of core logic, [Y]% of app layer
- Open debt items: [N] (P1: [n], P2: [n], P3: [n])
- Average fix time: [X] hours
- Estimated total debt cost: [X] hours

### Top 3 Risks
1. [Risk 1 — one sentence, business impact]
2. [Risk 2 — one sentence, business impact]
3. [Risk 3 — one sentence, business impact]

### Recommended Actions (This Quarter)
1. [Action 1] — [X] hours, fixes [risk]
2. [Action 2] — [X] hours, fixes [risk]
3. [Action 3] — [X] hours, fixes [risk]

### Debt Trend
[Is debt increasing, stable, or decreasing? What changed since last review?]
```

---

## Output Format

```markdown
## Phase 1: Debt Discovery
### Code Complexity
[table]

### Correctness
[list with blast radius]

### Architectural
[list]

### Process
[list]

### Documentation
[list]

## Phase 2: Debt Valuation
[cost/benefit table]

## Phase 3: Prioritized Backlog (Top 20)
[ranked table]

## Phase 4: Governance
### Labels & Templates
[proposed system]

### 20% Rule Implementation
[proposal]

### Prevention Rules
[list]

## Phase 5: Executive Summary
[one-page report]
```

---

## Start Now

Begin with Phase 1. Scan the codebase for debt items. Quantify everything. Show your work.
