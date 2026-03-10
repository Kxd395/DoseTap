# Governance Setup Report — February 9, 2026

**Branch:** `004-dosing-amount-model`  
**Triggered by:** Codebase audit finding 3 P0 bugs caused by incomplete refactoring + 9,131-line uncommitted diff  
**Goal:** Close the governance gaps that allowed split-brain and undetected build failures

---

## Summary

7 changes across 6 files (4 modified, 2 new) to close the gap between CI enforcement (which was strong) and local agent behavior (which had zero guardrails).

| # | Change | File(s) | Lines Changed |
|---|--------|---------|---------------|
| 1 | Added **Hard Rules** section (8 non-negotiable rules) | `.github/copilot-instructions.md` | +18 |
| 2 | Removed build-failure normalization language | `.github/copilot-instructions.md` | +4/−6 |
| 3 | Constitution v1.0.0 → v1.1.0 (added Principles VIII + IX) | `.specify/memory/constitution.md` | +41/−8 |
| 4 | Made SSOT lint **blocking** in CI | `.github/workflows/ci.yml` | −2 |
| 5 | Added `print()` ban CI job | `.github/workflows/ci-swift.yml` | +22 |
| 6 | Created pre-commit hook + activated | `.githooks/pre-commit` (new) | +44 |
| 7 | Created branch protection guide | `docs/BRANCH_PROTECTION.md` (new) | +40 |

**Total:** +169 lines / −16 lines across governance infrastructure (governance-only counts; additional production code changes shipped in the same PR). Build: ✅ `swift build -q`. Tests: ✅ 296/296 pass.

Post-review hardening updates (same date):
- CI suite verification made case-robust (`Test Suite` vs `Test suite`) to avoid false negatives.
- `print-ban` enforcement now blocks **any** `print()` in `ios/Core` (baseline debt fully removed).
- Pre-commit upgraded from advisory to enforce constitution guardrails:
  - blocks >500-line staged commits by default (override supported),
  - runs `xcodebuild` when `ios/DoseTap/` files are staged.
- SSOT lint script (`tools/ssot_check.sh`) aligned to SSOT v3 section names and legacy-archive reality, eliminating false failures.
- Pre-commit architecture hardening: forces native arm64 Swift build on Apple Silicon even when `git` runs under Rosetta, preventing false concurrency/deployment target failures.
- Branch protection was applied directly via GitHub API on February 9, 2026 (not pending manual setup).

---

## Detailed Changes

### 1. Hard Rules Section — `.github/copilot-instructions.md`

Added an `⛔ Hard Rules (NON-NEGOTIABLE)` section at the very top of the file — before all other guidance. This is the first thing any agent reads. Contains 8 rules:

1. **Never leave a broken build** — grep before deleting/renaming
2. **Commit atomically** — each commit compiles and passes tests, max 500 lines
3. **Both targets must build** — SwiftPM AND Xcode (no hiding with `#if false`)
4. **No `print()` in production** — use `os.Logger` with privacy annotations
5. **SSOT first, then code** — update docs before implementation
6. **Read the constitution** — explicit pointer to `.specify/memory/constitution.md`
7. **Test before you ship** — `swift test -q` before marking complete
8. **Refactoring safety protocol** — step-by-step grep/update/build/verify checklist

**Why:** The previous instructions had zero enforcement language. Agents could ignore broken builds, skip tests, and accumulate thousands of lines of uncommitted changes.

### 2. Removed Build-Failure Normalization

**Before:**
> "Xcode app target may fail due to legacy files. If you must run the app, quarantine conflicting legacy files with `#if false`"

**After:**
> "Xcode app target MUST also build. If you touch any file under `ios/DoseTap/`, verify with xcodebuild. If compile errors appear, **diagnose and fix them** — do NOT wrap in `#if false` without explicit user approval."

Also added a list of known quarantined files (already wrapped with prior approval) so agents know which files are intentionally suppressed vs which need fixing.

**Why:** The old language gave agents permission to ignore broken builds. Every P0 in the audit traced back to this.

### 3. Constitution v1.1.0 — Two New Principles

**Principle VIII: Refactoring Safety (NON-NEGOTIABLE)**
- `grep -rn` before any delete/rename/move
- Update all references in the same commit
- Verify both SwiftPM and Xcode build
- Never commit a file referencing an undefined symbol

**Principle IX: Commit Atomicity (NON-NEGOTIABLE)**
- Every commit compiles and passes tests
- Max 500 lines of uncommitted diff
- WIP saved via branches, not dirty working directories
- Commit or stash before ending any session

Both principles reference the Feb 2026 audit findings as rationale. Sync Impact Report updated in the constitution header.

**Why:** The constitution had 7 excellent principles covering *what* to build, but nothing about *how* to make changes safely. These two fill that gap.

### 4. SSOT Lint Now Blocking — `ci.yml`

Removed `continue-on-error: true` from the `ssot-lint` job. SSOT integrity check now **blocks the pipeline** on failure.

**Before:** SSOT drift was visible but non-blocking → `constants.json` drifted from v1.0.0 while SSOT README hit v3.0.0  
**After:** Pipeline fails if SSOT is inconsistent

**Why:** Advisory checks get ignored. Blocking checks get fixed.

### 5. `print()` Ban CI Job — `ci-swift.yml`

New job `print-ban` that blocks **all** `print()` calls in `ios/Core/`.

**Scope:** `ios/Core/` only (the production DoseCore package). Does NOT scan `ios/DoseTap/` (legacy app — too many existing violations to gate on immediately) or test files.

**Why:** The audit found 67 unguarded `print()` statements leaking session/dose data in release builds. Debt has now been migrated and the policy is strict.

### 6. Pre-Commit Hook — `.githooks/pre-commit`

Local hook with 5 checks:

| Check | Blocking? | What it catches |
|-------|-----------|-----------------|
| `swift build -q` | ✅ Blocks | Compile errors before they're committed |
| any `print()` in `ios/Core/` | ✅ Blocks | Enforces zero-print policy in production core code |
| File >2000 lines | ⚠️ Warning | God-class growth |
| `xcodebuild` when `ios/DoseTap/` is staged | ✅ Blocks | App-target compile breakage before commit |
| Commit >500 lines | ✅ Blocks (override available) | Prevents non-atomic mega commits |

Activated via `git config core.hooksPath .githooks` (already configured for this repo).

**Why:** CI only helps if you push. Pre-commit hooks catch errors locally, which is where every audit P0 originated.

Follow-up implemented:
- hook now forces arm64 Swift execution on Apple Silicon (`arch -arm64`) so local checks are stable even when Git runs under Rosetta.

### 7. Branch Protection Guide — `docs/BRANCH_PROTECTION.md`

Documents recommended GitHub branch protection settings for `main`:
- Require PR before merging
- Require status checks to pass (SwiftPM tests, SSOT lint, Xcode tests)
- Block force pushes and branch deletion
- Direct link to GitHub settings page

**Why:** Branch protection is a GitHub UI setting, not a file. But documenting the expected configuration ensures it's reproducible and auditable.

---

## What This Prevents (mapped to audit findings)

| Audit Finding | Severity | Governance Layer That Now Catches It |
|---------------|----------|--------------------------------------|
| Incomplete refactoring (SleepStageTimeline) | P0 | Hard Rule #1, #8 + Constitution VIII + pre-commit hook |
| Undefined type (TimePickerSheetRow) | P0 | Hard Rule #1, #3 + pre-commit hook (`swift build`) |
| Emptied file still referenced (MorningCheckInViewV2) | P0 | Hard Rule #1, #8 + Constitution VIII |
| Stale constants.json | P2 | Hard Rule #5 + SSOT lint now blocking |
| 67 print() in production | P1 | Hard Rule #4 + CI print-ban + pre-commit hook |
| 9,131-line uncommitted diff | P2 | Hard Rule #2 + Constitution IX + pre-commit warning |
| Agents ignoring broken Xcode builds | Root cause | Hard Rule #3 + removed normalization language |

---

## Remaining Manual Steps

1. **Push latest branch commits** so CI and branch protection evaluate the new strict no-`print()` policy.
2. **Resolve any newly surfaced CI failures** immediately (SSOT lint is blocking by design).

---

## Files Changed

```
Modified:
  .github/copilot-instructions.md       (+18/−6)
  .github/workflows/ci.yml              (−2)
  .github/workflows/ci-swift.yml        (+22)
  .specify/memory/constitution.md       (+41/−8)

New:
  .githooks/pre-commit                  (+44)
  docs/BRANCH_PROTECTION.md             (+40)
```

**Build verification:** `swift build -q` ✅ | `swift test` 296/296 ✅
