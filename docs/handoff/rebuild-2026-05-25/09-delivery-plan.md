# 09 — Delivery Plan

## Delivery Strategy

Use an incremental rebuild. Replace boundaries one at a time while preserving the current app as a working fallback.

Do not rewrite UI, storage, integrations, and dashboards in one branch. That combines the highest-risk areas and makes rollback meaningless.

## Milestones

### M0 — Current-State Audit

Duration: 2-4 days.

Outputs:

- `CURRENT_STATE_AUDIT.md`.
- Updated findings ledger.
- Fresh test results.
- Secret scan result.
- Build-system inventory.

Rollback:

- Docs-only milestone; revert audit docs if inaccurate.

### M1 — Policy and Use-Case Layer

Duration: 1-2 weeks.

Outputs:

- Canonical dose registration policy.
- Mutation use cases.
- Channel-parity test suite.
- SSOT update.

Rollback:

- Feature flag routes channels back to existing paths while retaining tests as pending gates.

### M2 — Storage Adapter and Migration Spike

Duration: 2 weeks.

Outputs:

- Storage protocol boundary.
- SQLite adapter parity tests.
- Target-store spike.
- Migration dry-run and checksum tool.
- Architecture decision: SQLite local store plus a CloudKit sync adapter.

Rollback:

- No production writes to new store.
- Delete spike store and continue with SQLite.

### M3 — Dashboard V2

Duration: 2-3 weeks.

Outputs:

- Nightly aggregate model.
- Dashboard cards.
- Data provenance and completeness.
- Performance tests.

Rollback:

- Hide Dashboard V2 behind feature flag and keep existing history/insights.

### M4 — Integration Hardening

Duration: 2-4 weeks depending on hardware/accounts.

Outputs:

- HealthKit permission matrix.
- WHOOP real API validation.
- Widget/watch App Group state.
- Flic confirmation flow.
- Siri/Shortcuts safety review.

Rollback:

- Disable individual integrations by remote/local feature flag.
- Keep manual dose logging fully functional.

### M5 — Release Candidate

Duration: 1-2 weeks.

Outputs:

- Release checklist.
- Privacy review.
- TestFlight build.
- Rollback rehearsal.
- Known-issues document.

Rollback:

- Pull TestFlight build.
- Disable integration flags.
- Preserve local data and exports.
- Ship hotfix with old storage adapter if migration issue appears.

## Team Handoff Notes

Needed roles:

- iOS lead for SwiftUI, storage, and Apple platform integration.
- QA owner with real-device access.
- Security/privacy reviewer.
- Product owner for dashboard wording and feature prioritization.
- Optional clinical reviewer for insight language and export usefulness.

Needed accounts/hardware:

- Apple Developer Team.
- iCloud test accounts.
- Apple Watch.
- WHOOP developer app credentials and test account/device.
- Flic hardware if Flic support remains in scope.
- Multiple iPhone simulators and at least one physical iPhone.

## Final Release Gate

Release only when:

- Local dose logging works without every integration.
- Migration rollback has been rehearsed.
- No known P0/P1 findings remain open.
- Dashboard does not overclaim or show simulated data as real.
- Exports and diagnostics are redaction-tested.
- App Store privacy and permission strings are accurate.
