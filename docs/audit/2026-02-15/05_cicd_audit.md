# Phase 4 — CI/CD Automator Audit

**Date:** 2026-02-15  
**Branch:** `chore/audit-2026-02-15`  
**Scope:** GitHub Actions workflows, pre-commit hooks, branch protection, release tooling

---

## 1. Pipeline Inventory

### 1.1 GitHub Actions Workflows

| File | Trigger | Jobs | Runner |
|------|---------|------|--------|
| `.github/workflows/ci.yml` | push main/master, all PRs | 5 | `macos-latest` |
| `.github/workflows/ci-swift.yml` | push main, PR to main | 4 | `macos-latest` / `macos-14` |
| `.github/workflows/ci-docs.yml` | push/PR when `docs/**` change | 1 | `ubuntu-latest` |

**Total: 3 workflows, 10 jobs.**

### 1.2 ci.yml — Primary CI (5 jobs)

```
ssot-lint ─┬─ swiftpm-tests ────────────┐
           ├─ release-pin-script-tests ──┼─ release-pinning-check (tags only)
           └─ xcode-tests ──────────────┘
```

| Job | Purpose | Key Details |
|-----|---------|-------------|
| `ssot-lint` | SSOT integrity | Runs `tools/ssot_check.sh`; uploads log artifact |
| `swiftpm-tests` | Core logic testing | **3 timezone runs** (default, UTC, America/New_York); ghost-dir guard; secret guard; mock-transport guard; critical suite verification (5 suites) |
| `release-pin-script-tests` | Pin script regression | 6 scenarios: skip on Debug, pass valid, fail missing/placeholder/malformed/single-pin |
| `xcode-tests` | Simulator tests | Tab split-brain guard; smart simulator selection (6 preferred iPhones); **auto-retry on transient failure** (7 error patterns); 9 required suites + contract test verification |
| `release-pinning-check` | Release gate | Tag-triggered only; uses `secrets.DOSETAP_CERT_PINS`; runs `release_preflight.sh` + `validate_release_pins.sh` + Release build |

**Concurrency:** `ci-${{ github.ref }}` with cancel-in-progress ✅

### 1.3 ci-swift.yml — Secondary CI (4 jobs)

| Job | Purpose | Runner | Key Details |
|-----|---------|--------|-------------|
| `build-and-test` | SwiftPM build + parallel test | `macos-latest` | `env -u SDKROOT` to avoid cross-SDK issues; test summary to `$GITHUB_STEP_SUMMARY` |
| `storage-enforcement` | Architecture guard | `macos-14` | Bans `EventStorage.shared` in views, `SQLiteStorage` in production; stale doc reference scanner (268 tests, v2.10.0, dosetap.db, @available unavailable) |
| `print-ban` | Production print() ban | `macos-14` | Uses `rg` for Core and DoseTap dirs |
| `xcode-build` | iOS compile check | `macos-14` | Selects Xcode 15.4 if available; generates `Secrets.swift` from template; build-only (no tests) |

**Concurrency:** None configured ⚠️

### 1.4 ci-docs.yml — Documentation CI (1 job)

| Job | Purpose | Runner |
|-----|---------|--------|
| `docs-validation` | SSOT + markdown links + OpenAPI | `ubuntu-latest` |

Steps: `tools/ssot_check.sh`, `gaurav-nelson/github-action-markdown-link-check@v1` (scoped to `docs/SSOT`), `@apidevtools/swagger-cli validate` on `docs/SSOT/contracts/api.openapi.yaml`.

**Trigger filter:** Only fires on `docs/**` or `tools/ssot_check.sh` changes.

---

## 2. Pre-commit Hooks

**Config:** `git config core.hooksPath .githooks` (active ✅)

| # | Check | Blocking? | Details |
|---|-------|-----------|---------|
| 1 | SwiftPM build | ✅ Yes | `swift build -q` with `env -u SDKROOT` and arch-arm64 |
| 2 | print() ban | ✅ Yes | Uses `rg` (fallback `grep`) for Core + DoseTap |
| 3 | File size warning | ⚠️ Warning | >2000 lines triggers warning (non-blocking) |
| 4 | Xcode build | ✅ Yes (conditional) | Only if `ios/DoseTap/` files staged |
| 5 | Commit size cap | ✅ Yes | >500 lines blocks; override: `DOSETAP_ALLOW_LARGE_COMMIT=1` |

**Auto-install:** None. Requires manual `git config core.hooksPath .githooks`. Documented in hook header but easy to miss for new contributors.

---

## 3. Branch Protection

**Source:** `docs/BRANCH_PROTECTION.md` (documented policy)

| Setting | Value |
|---------|-------|
| Protected branch | `main` |
| Required status checks | 3 (SSOT lint, SwiftPM tests, Xcode tests) |
| Require review | Yes |
| Admin enforcement | Enabled |
| Force push | Blocked |

---

## 4. Release Tooling

| Tool | Purpose |
|------|---------|
| `tools/release_preflight.sh` | Tag-triggered pre-release checks |
| `tools/validate_release_pins.sh` | Certificate pin format/validity enforcement |

Both are invoked by the `release-pinning-check` CI job on tag push.

---

## 5. Strengths

1. **3-timezone SwiftPM testing** — Explicitly catches DST/timezone-dependent failures (proven effective: fixed CI issue in Phase 16-17).
2. **Transient simulator failure retry** — Detects 7 known macOS runner flakiness patterns and auto-retries with simulator reboot. Production-grade resilience.
3. **Critical suite verification** — Both SwiftPM (5 suites) and Xcode (9 suites + 1 contract test) pipelines verify that expected test suites actually executed, catching silent skips.
4. **Architecture enforcement guards** — Storage layer (`EventStorage.shared`, `SQLiteStorage`), secret leak detection, mock transport, ghost test directory, tab split-brain, stale doc references — all enforced in CI.
5. **print() ban** — Enforced in both CI (`ci-swift.yml`) and pre-commit hook, covering Core and DoseTap.
6. **Commit size cap** — Pre-commit blocks >500 lines, aligning with Constitution Principle IX.
7. **Release pinning validation** — 6-scenario regression suite for certificate pin format + tag-gated release build.
8. **Secret template workflow** — `Secrets.template.swift` → `Secrets.swift` on CI. `.gitignore` covers `Secrets.swift`. Clean separation.

---

## 6. Findings

### CICD-001 (P2): Overlapping SwiftPM jobs across workflows

**ci.yml** `swiftpm-tests` and **ci-swift.yml** `build-and-test` both trigger on PRs to main and both run `swift build` + `swift test`. This means every PR executes the full SwiftPM test suite **twice** on different runners.

| Aspect | ci.yml `swiftpm-tests` | ci-swift.yml `build-and-test` |
|--------|----------------------|-------------------------------|
| Build | `swift test --verbose` | `swift build -v` then `swift test --parallel -v` |
| TZ coverage | 3 timezones | 1 (default only) |
| Guards | 4 (ghost dir, secrets, mock, suite verification) | 0 |
| Summary | No | Yes (`$GITHUB_STEP_SUMMARY`) |

**Impact:** ~10 min wasted runner time per PR. The `ci.yml` version is strictly more comprehensive.

**Recommendation:** Remove `build-and-test` from `ci-swift.yml` (or make it conditional on `ci.yml` not running). Consolidate unique features (test summary) into `ci.yml`.

### CICD-002 (P2): Overlapping Xcode build jobs across workflows

**ci.yml** `xcode-tests` runs a full Xcode build + test on simulator. **ci-swift.yml** `xcode-build` runs a build-only (no tests). Both trigger on PRs.

**Impact:** Duplicate Xcode build. The `ci.yml` version does strictly more (build + test vs build-only).

**Recommendation:** Remove `xcode-build` from `ci-swift.yml` or gate it to only run when `ci.yml` is not triggered.

### CICD-003 (P2): Inconsistent runner versions

| Workflow | Jobs | Runner |
|----------|------|--------|
| ci.yml | All 5 | `macos-latest` |
| ci-swift.yml | `build-and-test` | `macos-latest` |
| ci-swift.yml | `storage-enforcement`, `print-ban`, `xcode-build` | `macos-14` |

`macos-latest` currently resolves to `macos-15` (Sequoia). Mixing `macos-14` and `macos-latest` means Xcode/Swift versions differ between workflows. The `xcode-build` job even pins `Xcode_15.4` while `ci.yml` uses whatever `macos-latest` provides.

**Impact:** Subtle version-dependent build differences; `macos-14` will eventually be deprecated.

**Recommendation:** Standardize all jobs on `macos-latest` (or pin a specific version consistently).

### CICD-004 (P3): No concurrency group on ci-swift.yml

`ci.yml` has `concurrency: ci-${{ github.ref }}` with cancel-in-progress. `ci-swift.yml` has no concurrency configuration.

**Impact:** Rapid PR updates stack redundant `ci-swift.yml` runs without cancellation.

**Recommendation:** Add matching concurrency group to `ci-swift.yml`.

### CICD-005 (P3): Pre-commit hook not auto-installed

The hook requires `git config core.hooksPath .githooks` which is documented only in the hook file header. New contributors may miss this, working without any local safety net.

**Impact:** Low — CI catches everything the hook catches. But defeats the purpose of shift-left feedback.

**Recommendation:** Add a `make setup` or `tools/setup.sh` script that configures hooks. Document in README.

### CICD-006 (P3): ci-docs.yml path filter may miss code-driven SSOT breaks

`ci-docs.yml` only triggers on `docs/**` changes. If a code change modifies a constant value without updating SSOT docs, `ci-docs.yml` won't fire. However, `ci.yml` runs `ssot-lint` on ALL pushes/PRs, which partially mitigates this.

**Impact:** Minimal — `ci.yml` covers the gap. But `ci-docs.yml`'s markdown link check and OpenAPI validation only run on docs changes.

**Recommendation:** Consider running docs-validation on code changes to `ios/Core/` as well, or consolidate into `ci.yml`.

### CICD-007 (P3): ggshield absent from local and CI toolchain

`.cache_ggshield` is tracked (HYG-001), suggesting ggshield was once used locally for secret scanning. It is now:
- Not installed locally (`command -v ggshield` fails)
- Not referenced in any CI workflow
- Not in pre-commit hook

**Impact:** No automated secret scanning pre-push. CI has a `grep`-based secret guard (hardcoded pattern matching), which is weaker than ggshield/gitleaks regex patterns.

**Recommendation:** Either re-install ggshield (or gitleaks) into CI and pre-commit, or document the intentional removal. Remove `.cache_ggshield` (cross-ref HYG-001).

---

## 7. CI Coverage Matrix

| Check | ci.yml | ci-swift.yml | ci-docs.yml | Pre-commit |
|-------|--------|-------------|-------------|------------|
| SSOT integrity | ✅ | — | ✅ | — |
| SwiftPM build | ✅ | ✅ | — | ✅ |
| SwiftPM tests | ✅ (3 TZ) | ✅ (1 TZ) | — | — |
| Xcode build | ✅ (+tests) | ✅ (build only) | — | ✅ (conditional) |
| print() ban | — | ✅ | — | ✅ |
| Storage enforcement | — | ✅ | — | — |
| Secret leak guard | ✅ (grep) | — | — | — |
| Stale doc refs | — | ✅ | — | — |
| Markdown links | — | — | ✅ | — |
| OpenAPI validation | — | — | ✅ | — |
| Commit size cap | — | — | — | ✅ |
| Release pin validation | ✅ (tags) | — | — | — |
| Suite execution verification | ✅ | — | — | — |
| Transient failure retry | ✅ | — | — | — |

### Gaps identified from matrix:
- **No test execution in pre-commit** — intentional (speed), CI compensates.
- **Storage enforcement only in ci-swift.yml** — if ci-swift.yml is removed per CICD-001/002, consolidate guards into ci.yml.
- **No automated secret scanning tool** (ggshield/gitleaks/trufflehog) in any pipeline — only grep-based pattern matching.

---

## 8. Summary

| Metric | Value |
|--------|-------|
| Workflows | 3 |
| Total CI jobs | 10 |
| Test suite runs per PR | ~5 (3 TZ SwiftPM + 1 duplicate + 1 Xcode) |
| Pre-commit checks | 5 |
| Required branch protection checks | 3 |
| Release gate checks | 3 (preflight + pin validation + Release build) |
| Phase 4 findings | 7 (0 P0, 0 P1, 3 P2, 4 P3) |

**Overall CI/CD health: Strong.** The pipeline is comprehensive, with timezone testing, architecture enforcement guards, transient failure handling, and release gating that exceed typical iOS project standards. The main improvement opportunities are consolidating duplicate jobs across the two Swift-focused workflows and standardizing runner versions.
