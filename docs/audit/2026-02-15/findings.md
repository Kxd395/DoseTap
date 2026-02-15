# Findings Ledger — Audit 2026-02-15

> Machine-readable companion: [`findings.json`](findings.json)

| ID | Pillar | Sev | Title | Status |
|----|--------|-----|-------|--------|
| SEC-001 | Security | P0 | WHOOP Client Secret #1 in git history (11 files, 2 on HEAD) | 🔴 Open |
| SEC-002 | Security | P0 | WHOOP Client Secret #2 in git history (1 file, deleted from HEAD) | 🔴 Open |
| SEC-003 | Security | P1 | Archive audit doc still contains plaintext secret on HEAD | 🔴 Open |
| SEC-004 | Security | P1 | .gitignore missing 7 sensitive file patterns | 🔴 Open |
| HYG-001 | Hygiene | P1 | `.cache_ggshield` tracked in git (contains secret hash) | 🔴 Open |
| HYG-002 | Hygiene | P2 | Duplicate `CSVExporter.swift` (different impls, confusing) | 🟡 Open |
| HYG-003 | Hygiene | P2 | Duplicate `TimeIntervalMath.swift` (diverged copies) | 🟡 Open |
| HYG-004 | Hygiene | P2 | Orphan `ios/DoseTap/Package.swift` (vestigial) | 🟡 Open |
| HYG-005 | Hygiene | P2 | `docs/archive/` bloat (72 tracked historical files) | 🟡 Open |
| HYG-006 | Hygiene | P3 | Untracked `archive/` dir (75 files, local only) | ⚪ Info |
| HYG-007 | Hygiene | P3 | `shadcn-ui/` abandoned (0 tracked files) | ⚪ Info |
| HYG-008 | Hygiene | P3 | SwiftLint includes non-existent `ios/AppMinimal` | ⚪ Info |
| COR-001 | Correctness | P2 | SleepEventType/EventType split-brain (Core missing nap events) | 🟡 Open |
| COR-002 | Correctness | P2 | URLRouter bypasses DoseTapCore for extra doses (channel parity) | 🟡 Open |
| COR-003 | Correctness | P3 | EventType congestion/grogginess cases misleading naming | ⚪ Info |
| SEC-005 | Security | P2 | CloudKit entitlement present but no implementation | 🟡 Open |
| SEC-006 | Security | P1 | Missing privacy manifest (PrivacyInfo.xcprivacy) | 🔴 Open |
| CICD-001 | CI/CD | P2 | Overlapping SwiftPM jobs across ci.yml and ci-swift.yml | 🟡 Open |
| CICD-002 | CI/CD | P2 | Overlapping Xcode build jobs across ci.yml and ci-swift.yml | 🟡 Open |
| CICD-003 | CI/CD | P2 | Inconsistent runner versions (macos-latest vs macos-14) | 🟡 Open |
| CICD-004 | CI/CD | P3 | No concurrency group on ci-swift.yml | ⚪ Open |
| CICD-005 | CI/CD | P3 | Pre-commit hook not auto-installed for new contributors | ⚪ Open |
| CICD-006 | CI/CD | P3 | ci-docs.yml path filter may miss code-driven SSOT breaks | ⚪ Info |
| CICD-007 | CI/CD | P3 | ggshield absent from local and CI toolchain | ⚪ Open |
| DX-001 | DX | P2 | Secrets.swift setup not documented; blocks Xcode build for new devs | 🟡 Open |
| DX-002 | DX | P2 | Pre-commit hook requires manual activation; not documented in README | 🟡 Open |
| DX-003 | DX | P3 | swift test SIGTSTP workaround only in TESTING_GUIDE, not README | ⚪ Open |
| DX-004 | DX | P3 | No "which build system?" guidance in README | ⚪ Open |
| DX-005 | DX | P2 | No setup automation (Makefile/justfile/setup.sh) | 🟡 Open |
| DX-006 | DX | P3 | README missing prerequisites (Xcode, macOS, Swift versions) | ⚪ Open |
| DX-007 | DX | P3 | 12 orphan Python scripts in ios/ root (one-time migration tools) | ⚪ Open |
| DX-008 | DX | P3 | No .swift-version or .xcode-version for environment standardization | ⚪ Open |
| DEBT-001 | Strategy | P0 | Total identified debt: 33 items (2 P0, 6 P1, 14 P2, 11 P3). ~27h to clear Top 20 | 🔴 Open |

**Totals**: 33 findings — 2 P0, 6 P1, 14 P2, 11 P3
