# 06 — Backlog and Roadmap

## Phase 0 — Re-Audit Current HEAD

Goal: remove ambiguity before implementation.

Tasks:

- Build a current feature matrix from source.
- Reconcile older audit findings against current HEAD.
- Run `swift build -q` and `swift test -q`.
- Run Xcode build with signing disabled.
- Confirm whether `ios/DoseTapTests/` and `ios/DoseTapUITests/` exist and are wired in the project.
- Run a fresh secret scan.
- Create `CURRENT_STATE_AUDIT.md`.

Acceptance:

- Every historical P0/P1 is marked verified-open, resolved, obsolete, or blocked by runtime/device testing.

## Phase 1 — Domain Contract Freeze

Tasks:

- Update SSOT to current behavior.
- Make `DoseRegistrationPolicy` canonical.
- Create channel-parity tests for Tonight, History, URLRouter, Flic, Siri, Watch, and Widget actions.
- Add explicit source field for every action.

Acceptance:

- No state-changing dose path bypasses policy.
- Early, late, after-skip, and extra dose confirmations are consistent.

## Phase 2 — Storage Boundary

Tasks:

- Define repository protocols.
- Add storage adapter tests.
- Build migration inventory and checksums.
- Prove the SQLite local store plus CloudKit sync adapter after spike.
- Add migration status diagnostics.

Acceptance:

- Current app can run on old storage.
- New storage can be populated in shadow mode.
- Rollback to old storage is tested.

## Phase 3 — Dashboard V2

Tasks:

- Build nightly aggregate model.
- Implement data completeness/provenance.
- Implement dose timing, effectiveness, night score, sleep summary, morning outcomes, and integration quality cards.
- Add sample-size gates.

Acceptance:

- Dashboard never displays simulated health data.
- Sparse data states are explicit.
- Large-history query performance meets target.

## Phase 4 — Integration Hardening

Tasks:

- HealthKit permission matrix and partial-grant handling.
- WHOOP real-credential E2E tests.
- Flic confirmation routing.
- Widget App Group activation and stale-state tests.
- Watch sync/action parity tests.
- Siri/Shortcuts safety review.

Acceptance:

- Each integration can fail independently without breaking dose logging.

## Phase 5 — Release Hardening

Tasks:

- Privacy manifest review.
- Export/redaction tests.
- Support bundle review.
- CI consolidation.
- App Store/TestFlight checklist.
- Performance/load tests.
- Rollback rehearsal.

Acceptance:

- Release candidate passes all validation gates.
- Rollback instructions are executable and tested.

## Parking Lot

- Clinician reports.
- Caregiver sharing.
- Backend account system.
- Cloud web dashboard.
- AI-assisted pattern summaries.
- Multi-medication clinical decision support.
