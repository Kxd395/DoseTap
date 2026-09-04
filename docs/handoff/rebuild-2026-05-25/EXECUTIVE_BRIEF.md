# Executive Brief

## Product Thesis

DoseTap is a local-first iOS medication and sleep companion for two-dose nighttime medication timing. The rebuild should keep the 2-4 AM medication workflow simple, reliable, and safe while improving dashboards, integrations, storage durability, cross-device workflows, and support diagnostics.

The product should not become a generic sleep tracker. Its core value is confidence around dose timing, session history, and clear feedback about how timing, sleep behavior, and biometric data relate.

## Current Reality

The repository already contains meaningful production-grade work:

- Platform-free core logic in `ios/Core/`.
- SwiftUI iOS app code in `ios/DoseTap/`.
- SQLite local storage in `ios/DoseTap/Storage/`.
- HealthKit, WHOOP, Flic, URL routing, widgets, AppIntents, diagnostic logging, CSV export, setup wizard, settings, history, and dashboard code.
- SSOT behavior documentation in `docs/SSOT/README.md`.
- Database documentation in `docs/DATABASE_SCHEMA.md`.
- Test documentation in `docs/TESTING_GUIDE.md`.
- Historical audits and roadmap files with both resolved and unresolved risk.

The rebuild should be an incremental consolidation, not a blind rewrite. A greenfield rewrite would risk losing hard-won behavior around dose windows, session rollover, timezone handling, late Dose 2 classification, extra-dose indexing, undo, and confirmation flows.

## Rebuild Objectives

1. Make dose logging and dose-state transitions reliable across app, widget, watch, Siri, deep link, and hardware button surfaces.
2. Route every state-changing dose action through one policy and one mutation use case.
3. Upgrade storage and sync without breaking local-first operation.
4. Build dashboards that explain dose timing, sleep quality, check-in outcomes, and biometric trends without fabricating or overclaiming data.
5. Separate shipping-local behavior from staging-only CloudKit and experimental integration paths.
6. Reduce maintenance drag from duplicated models, legacy files, stale docs, oversized files, and mixed build entry points.
7. Preserve privacy-safe diagnostics, redacted support bundles, and user-owned exports.

## Primary Users

- A patient taking a two-dose nighttime medication who needs low-friction, high-confidence logging.
- A patient reviewing patterns across nights.
- A caregiver or clinician receiving user-exported data.
- A developer or support operator diagnosing a session without seeing sensitive health details by default.

## Non-Negotiable Rebuild Constraints

- Dose 2 window remains 150-240 minutes after Dose 1.
- Late Dose 2 remains Dose 2 with late metadata; it must not become an extra dose.
- Extra dose starts only at dose index 3+ and requires explicit confirmation.
- Sessions close through morning check-in or documented fallback rules, not midnight.
- Dose logging works without network, iCloud, WHOOP, HealthKit, Flic, widget, or watch availability.
- Integration data is optional, provenance-labeled, and never simulated as real.
- Migrations are idempotent and rollback-tested.

## Definition of Done

- The SSOT matches code.
- Every dose mutation path uses canonical policy and use cases.
- URLRouter, Flic, Tonight, History, Siri, Watch, and Widget paths have channel-parity tests.
- Storage migration has backup, shadow validation, checksums, and rollback.
- Dashboards show data completeness, sample-size limits, and source provenance.
- HealthKit and WHOOP have mocked, offline, rate-limited, credential-failure, and revoked-permission tests.
- Release gates include SwiftPM tests, Xcode build/tests, UI smoke tests, security scans, privacy manifest checks, and support bundle redaction tests.
