# DoseTap TODO + Feature Roadmap

Last updated: 2026-02-14
Owner: Product/Engineering

## Purpose
Track active gaps after the Phase 1/2 stabilization pass and keep a short, current list of what is done vs still open.

---

## Recently Completed

- [x] Move DB reads/writes onto `SessionStorageActor` paths for core session flows.
- [x] Consolidate Tonight/Timeline/History flow boundaries and remove split-brain behavior in primary paths.
- [x] Add release-time pin validation checks in CI for non-debug/release safety gates.
- [x] Add planner turnover setting (`After check-in, show upcoming night`) and wire planner key through Tonight-facing surfaces.
- [x] Add weekly workday/off-day setup template for split schedules (including 3-day work week setups).
- [x] Add theme-stable schedule picker UX (sheet-based wheel pickers) across Settings, Setup Wizard, and Weekly Schedule.
- [x] Split `ContentView.swift` god file (2,850 → 228 lines) into 8 domain files: TonightView, CompactDoseButton, CompactStatusCard, SleepPlanCards, SessionSummaryViews, QuickEventViews, DetailsView, EventLogger.
- [x] Split `EventStorage.swift` god file (1,948 → 277 lines) into 3 extension files: +Dose, +CheckIn, +Maintenance.
- [x] Add `DoseTapUITests` XCUITest target with 12 smoke tests (launch, navigation, dose flow).
- [x] Grow DoseCoreTests from 296 → 497 tests across 29 test files (7 new test files for untested modules).
- [x] CI governance: 3 workflows (ci.yml, ci-swift.yml, ci-docs.yml) + branch protection on main.
- [x] Comprehensive documentation refresh (architecture, testing guide, SSOT, all dated references).
- [x] Repo cleanup: removed 104 dead files (−18,165 lines) — archive/, agent/, shadcn-ui/, one-off scripts.
- [x] Architecture doc rewrite with ASCII diagrams (layer cake, data flow, state machines, test pyramid).
- [x] Wrap `MockAPITransport` in `#if DEBUG` — no mock code ships in release builds.
- [x] Harden `SecureConfig`: release builds return empty string when Keychain/env not configured (no Secrets.swift fallback).
- [x] Add CI guard for mock transport leaking into production code.
- [x] Grow DoseCoreTests to 499 tests (transport safety canaries).
- [x] Split `SettingsView.swift` god file (1,644 → 628 lines) into 6 focused modules: HealthKitSettingsView, AboutView, EventCooldownSettingsView, DataManagementView, QuickLogCustomizationView, SettingsHelpers.
- [x] Fix PR #1 review comments (URLRouter snooze feedback, governance doc accuracy; 7/9 already resolved by prior cleanup).
- [x] Fix 3 CI failures: Storage Enforcement Guard (EventStorage.shared in SupportBundleExporter), tab split-brain script path (test file moved), non-existent grep target.
- [x] Extract real SPKI pins from live `api.dosetap.com` — leaf + intermediate CA. Create operational rotation runbook (`docs/CERTIFICATE_PINNING.md`).
- [x] Remove 13 empty dead files (10 `.swift` emptied during prior refactoring, 3 `.md` docs). No pbxproj impact — none were referenced.
- [x] Fix `Build & Test` CI job: align with proven `ci.yml` pattern (strip SDKROOT/deployment target env vars, use `macos-latest` runner, parallel tests, tee log output).
- [x] Fix Xcode simulator tests CI: generate `Secrets.swift` stub from template on CI (file is `.gitignore`d but required by `.xcodeproj`). All 10/10 CI checks now green ✅.
- [x] Audit and confirm one canonical settings flow (no duplicate settings surfaces).
- [x] Normalize user-facing "HealthKit" → "Apple Health" in 6 UI files (693339e).
- [x] Add export failure alerts with retry to `SettingsView` and `SupportBundleExportManager` (298967d).
- [x] Remove dead `WHOOPManager` (`WHOOP.swift`, −704 lines) — zero callers, not in compile sources (93c443a).
- [x] Document encrypted-at-rest decision: iOS Data Protection sufficient for v1 (`docs/SSOT/encryption-at-rest.md`).
- [x] Add 26 session rollover regression tests: DST, timezone travel, leap year, nextRollover(), preSleepSessionKey (a330c66).
- [x] Deduplicate `.gitignore` (ggshield entries, bc8fa6c).

---

## P0 — Ship Blockers (All Resolved ✅)

### Security & Privacy
- [x] ~~Purge committed secrets from git history~~ — **Audit complete (2026-02-14): `Secrets.swift` was never committed to git.** `git log --all --diff-filter=ADRM` and `git log -p -S` confirm zero credential values in history. File is properly `.gitignore`d. `SecureConfig.swift` references the property name only (in `#if DEBUG` blocks); release builds return empty string. No rotation needed.
- [x] Enforce env/Keychain-only secret loading with CI guards.

### Core Runtime
- [x] Replace `MockAPITransport` in main app path for non-debug builds.
- [x] Finish production certificate pin set (real SPKI pins + operational rotation procedure). See `docs/CERTIFICATE_PINNING.md`.

---

## P1 — High Priority

### UX / Product
- [x] Retire duplicate/legacy settings surfaces and keep one canonical settings flow. — **Audited 2026-02-14: confirmed clean.** One canonical `SettingsView` with `NavigationLink`s to focused sub-views. No duplicates.
- [x] Finish timeline terminology normalization and polish remaining low-signal cards. — **Fixed 2026-02-14 (693339e):** normalized "HealthKit" → "Apple Health" in 6 user-facing files.
- [x] Complete export failure UX for all code paths (alert + retry + reason). — **Fixed 2026-02-14 (298967d):** error alerts with retry added to `SettingsView.exportData()` and `SupportBundleExportManager`.

### Integrations
- [x] Consolidate duplicate HealthKit/WHOOP service paths to one source of truth. — **Fixed 2026-02-14 (93c443a):** deleted dead `WHOOPManager` (`WHOOP.swift`, −704 lines). `WHOOPService.swift` is the sole WHOOP path.
- [ ] Complete WHOOP OAuth + production API path with resilient retry/error handling. *(Code hardened 2026-02-14: added retry with exponential backoff, os.Logger, 429/5xx resilience. Blocked on WHOOP developer credentials. See `docs/WHOOP_INTEGRATION.md` for enablement steps.)*

---

## P2 — Medium Priority

### Data & Trust
- [x] Decide and document encrypted-at-rest storage requirement (SQLCipher or explicit non-goal). — **Documented 2026-02-14 (a330c66):** `docs/SSOT/encryption-at-rest.md` — iOS Data Protection sufficient for v1; SQLCipher optional for v2.
- [x] Add regression coverage for remaining edge cases around session rollover + timezone + planner toggle interaction. — **Added 2026-02-14 (a330c66):** 26 tests in `SessionRolloverRegressionTests` covering DST, timezone travel, custom rollover hours, leap year, nextRollover(), preSleepSessionKey, dose window midnight spanning.

### Operations
- [x] Add release checklist enforcement for secret scanning + pin freshness checks. — **Added 2026-02-14:** `tools/release_preflight.sh` (8 automated checks), CI runs on tag pushes, `RELEASE_CHECKLIST.md` updated with quick-start command.

---

## Notes

- Dose window safety contract remains unchanged: Dose 2 window is still 150-240 minutes after Dose 1.
- Planner/UI day turnover is now configurable; storage integrity remains tied to canonical session boundaries.
