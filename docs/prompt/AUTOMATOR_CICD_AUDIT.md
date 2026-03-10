# ⚙️ DoseTap — Automator Layer: CI/CD Rigor & Guardrails Audit

> **Usage**: Copy/paste into a fresh agent session with the repo attached.
> Pre-filled for DoseTap. Ready to run as-is.
>
> Last updated: 2026-02-15

---

## Role

You are a **Principal DevOps/Platform Engineer** specializing in iOS CI/CD pipelines. Your goal is to make the DoseTap build pipeline **unbreakable** — every regression caught before merge, every guardrail automated, every manual step eliminated.

---

## Non-Negotiable Rules

1. **No hallucinations.** Every claim references a real file or workflow step.
2. **Show your work.** Log each workflow/script/hook as you review it.
3. **Prove coverage.** For every guardrail, show what it catches and what it misses.
4. **Automate or die.** If a human must remember to do something, it will be forgotten. Propose automation.

---

## Existing CI/CD Posture (Verify These Still Hold)

DoseTap already has significant CI infrastructure — verify and grade each:

### Workflows (`.github/workflows/`)

| Workflow | File | Jobs | What It Does |
| --- | --- | --- | --- |
| **CI (main)** | `ci.yml` | `ssot-lint`, `swiftpm-tests`, `release-pin-script-tests`, `xcode-tests`, `release-pinning-check` | SSOT validation, SwiftPM tests (3 timezones), secrets guard, mock guard, Xcode simulator tests, release pin validation |
| **Swift CI** | `ci-swift.yml` | `build-and-test`, `storage-enforcement` | SwiftPM build+test, storage layer access enforcement |
| **Docs CI** | `ci-docs.yml` | `docs-validation` | SSOT integrity, markdown link check, OpenAPI spec validation |

### Pre-Commit Hook (`.githooks/pre-commit`)

| Check | Blocking? | What It Does |
| --- | --- | --- |
| SwiftPM build | ✅ Yes | `swift build -q` must succeed |
| `print()` in Core | ✅ Yes | Zero tolerance in `ios/Core/` |
| `print()` in App | ✅ Yes | Zero tolerance in `ios/DoseTap/` |
| File size warning | ⚠️ No | Warns on files > 2000 LOC |
| Xcode build | ✅ Yes | Runs if `ios/DoseTap/` files staged |
| Commit size cap | ✅ Yes | Blocks > 500 lines (overridable) |

### PR Template (`.github/PULL_REQUEST_TEMPLATE.md`)

Has checklists for: type of change, testing, SSOT compliance, release.

---

## Protocol: CI/CD Completeness Audit

### Phase 1 — Workflow Coverage Matrix

For each CI workflow, verify it actually runs when expected:

#### 1.1 — Trigger Analysis

| Workflow | Trigger | Runs on PRs? | Runs on Push to Main? | Path Filters? |
| --- | --- | --- | --- | --- |
| `ci.yml` | `pull_request` + `push: [main, master]` | ? | ? | None (runs on all) |
| `ci-swift.yml` | `push: [main]` + `pull_request: [main]` | ? | ? | None |
| `ci-docs.yml` | `push: [main, develop]` + `pull_request: [main]` | ? | ? | `docs/**`, `tools/ssot_check.sh` |

**Flag**: Do any workflows only run on `main` but not on PR branches? That means regressions aren't caught until after merge.

#### 1.2 — Job Dependency Graph

Map the `needs:` chain in `ci.yml`:

```
ssot-lint
  ├── swiftpm-tests (needs: ssot-lint)
  ├── release-pin-script-tests (needs: ssot-lint)
  └── xcode-tests (needs: ssot-lint)
        └── release-pinning-check (needs: [swiftpm-tests, xcode-tests, release-pin-script-tests])
```

**Verify**: Is this DAG correct? Are there missing dependencies? Could jobs run in parallel that shouldn't?

#### 1.3 — What's NOT Tested in CI

Check for gaps — things that should be tested but aren't:

- [ ] **Secrets scan** (gitleaks/trufflehog) — is there a CI job for this?
- [ ] **Dependency audit** — are Swift packages scanned for CVEs?
- [ ] **License compliance** — are dependency licenses checked?
- [ ] **Code coverage** — is coverage measured and reported?
- [ ] **Performance regression** — are there benchmark tests in CI?
- [ ] **Xcode warnings** — does CI fail on new warnings, or just errors?
- [ ] **SwiftLint / SwiftFormat** — is code style enforced in CI?
- [ ] **Branch protection** — is `main` branch protected? (check `docs/BRANCH_PROTECTION.md`)

---

### Phase 2 — Pre-Commit Hook Audit

Read `.githooks/pre-commit` thoroughly.

#### 2.1 — Activation Check

Is the hook activated? Look for evidence:
- `git config core.hooksPath .githooks` — is this documented?
- Is there a setup script that runs this?
- **Risk**: New developers who clone won't have hooks active unless told.

#### 2.2 — Coverage Gaps

What the pre-commit hook does NOT check:

- [ ] `swift test` — only builds, doesn't run tests
- [ ] SSOT consistency (`tools/ssot_check.sh`) — only CI checks this
- [ ] SwiftLint — no linting
- [ ] Merge conflict markers (`<<<<<<<`)
- [ ] TODO/FIXME inventory — no tracking
- [ ] Secrets detection — no local scan

For each gap: is it acceptable (too slow for pre-commit) or should it be added?

#### 2.3 — Bypass Analysis

How easily can the hook be bypassed?
- `git commit --no-verify` — standard bypass
- `DOSETAP_ALLOW_LARGE_COMMIT=1` — documented override for size cap
- Is there telemetry or CI double-check for bypassed hooks?

---

### Phase 3 — PR Process Audit

#### 3.1 — PR Template Completeness

Read `.github/PULL_REQUEST_TEMPLATE.md`. Does it cover:

- [ ] What changed (summary)
- [ ] Type of change
- [ ] Test evidence (`swift test -q` passed)
- [ ] SSOT updated if behavior changed
- [ ] Navigation/contracts updated if applicable
- [ ] `tools/ssot_check.sh` run
- [ ] Breaking change assessment
- [ ] Reviewer checklist (security, performance, accessibility)
- [ ] Issue link

What's missing?

#### 3.2 — Branch Protection

Read `docs/BRANCH_PROTECTION.md` and verify against GitHub settings:

- [ ] `main` requires PR reviews before merge?
- [ ] `main` requires CI checks to pass?
- [ ] Which checks are required vs. optional?
- [ ] Force push disabled on `main`?
- [ ] Conversation resolution required?

#### 3.3 — Merge Strategy

- Is squash merge enforced? (Keeps history clean)
- Are commit messages standardized? (Conventional commits?)
- Is the PR title format enforced?

---

### Phase 4 — Build Reproducibility

#### 4.1 — Version Pinning

| Artifact | Pinned? | Location |
| --- | --- | --- |
| Swift version | ? | Xcode version in CI (`macos-latest` is floating!) |
| Xcode version | ? | `xcodebuild -version` in CI |
| SwiftPM dependencies | ? | `Package.resolved` committed? |
| CI runner OS | ? | `macos-latest` vs `macos-14` (inconsistent in ci.yml vs ci-swift.yml?) |
| GitHub Actions | ? | `actions/checkout@v4` — pinned to SHA or floating tag? |
| npm packages | ? | `shadcn-ui/package-lock.json` committed? |

**Flag**: `macos-latest` is a floating target. Builds that pass today may fail tomorrow when GitHub updates the runner image.

#### 4.2 — Environment Parity

- Does local dev environment match CI? (Xcode version, Swift version, simulator)
- Are there known "works locally, fails in CI" issues?
- Is there a `.xcode-version` or `.swift-version` file?

---

### Phase 5 — Release Pipeline

#### 5.1 — Release Process

Trace the full release path:

1. `docs/RELEASE_CHECKLIST.md` — read and verify completeness
2. `tools/release_preflight.sh` — what does it check?
3. `tools/validate_release_pins.sh` — cert pin validation
4. CI `release-pinning-check` job — runs on tags
5. Xcode archive → TestFlight → App Store

#### 5.2 — Release Guardrails

- [ ] Version bump is automated or enforced?
- [ ] CHANGELOG.md is required before release?
- [ ] Release tags are protected?
- [ ] Cert pins are validated for release config?
- [ ] App Store submission checklist exists?

---

### Phase 6 — Recommendations

For every gap found, produce a concrete recommendation:

| Gap | Risk | Recommendation | Effort | Priority |
| --- | --- | --- | --- | --- |
| No secrets scan in CI | HIGH | Add `gitleaks` job to `ci.yml` | 30 min | P1 |
| `macos-latest` floating | MEDIUM | Pin to `macos-14` everywhere | 10 min | P2 |
| No code coverage | MEDIUM | Add `xcresultparser` for coverage reporting | 2 hrs | P2 |
| ... | ... | ... | ... | ... |

Group into: **Quick Wins** (< 1 hr), **Sprint Items** (1 day), **Strategic** (> 1 day).

---

## Output Format

```markdown
## CI/CD Posture Grade: [A/B/C/D/F]

## Phase 1: Workflow Coverage
### Trigger Matrix
[table]

### Job Dependency Graph
[ASCII graph]

### Coverage Gaps
[list]

## Phase 2: Pre-Commit Hook
### Activation Status
[findings]

### Coverage Gaps
[list]

### Bypass Risk
[findings]

## Phase 3: PR Process
### Template Grade
[findings]

### Branch Protection
[findings]

## Phase 4: Build Reproducibility
### Version Pinning
[table]

### Environment Parity
[findings]

## Phase 5: Release Pipeline
### Release Path
[flow diagram]

### Release Guardrails
[checklist]

## Phase 6: Recommendations
### Quick Wins
[table]

### Sprint Items
[table]

### Strategic
[table]
```

---

## Start Now

Begin with Phase 1. Read every workflow file line by line. Show your work.
