# DoseTap TODO + Feature Roadmap

Last updated: 2026-02-09
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

---

## P0 — Ship Blockers (Still Open)

### Security & Privacy
- [ ] Purge committed secrets from git history and rotate exposed credentials.
- [ ] Enforce env/Keychain-only secret loading with CI guards.

### Core Runtime
- [ ] Replace `MockAPITransport` in main app path for non-debug builds.
- [ ] Finish production certificate pin set (real SPKI pins + operational rotation procedure).

---

## P1 — High Priority

### UX / Product
- [ ] Retire duplicate/legacy settings surfaces and keep one canonical settings flow.
- [ ] Finish timeline terminology normalization and polish remaining low-signal cards.
- [ ] Complete export failure UX for all code paths (alert + retry + reason).

### Integrations
- [ ] Consolidate duplicate HealthKit/WHOOP service paths to one source of truth.
- [ ] Complete WHOOP OAuth + production API path with resilient retry/error handling.

---

## P2 — Medium Priority

### Data & Trust
- [ ] Decide and document encrypted-at-rest storage requirement (SQLCipher or explicit non-goal).
- [ ] Add regression coverage for remaining edge cases around session rollover + timezone + planner toggle interaction.

### Operations
- [ ] Add release checklist enforcement for secret scanning + pin freshness checks.

---

## Notes

- Dose window safety contract remains unchanged: Dose 2 window is still 150-240 minutes after Dose 1.
- Planner/UI day turnover is now configurable; storage integrity remains tied to canonical session boundaries.
