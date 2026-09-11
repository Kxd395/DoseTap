# Shared reviewed-night projection

Date: September 10, 2026
Plane: DOSETAP-56, In Progress
Baseline: `bee1107b`, shipping checkout `/Volumes/Developer/projects/DoseTap-main`

## Scope

The checked provider loader now returns a shared, versioned projection alongside its original provider evidence. The projection contains the reviewed window, generation time, evidence and projection derivation versions, coverage totals, conflicting minutes and chronological state bands. It combines touching bands of the same state without joining gaps or discarding shorter sleep blocks. Sleep-stage changes do not create separate awake bands.

The core builder rejects invalid windows, mismatched query bounds, rejected provider samples and invalid generation times. The app produces this value only after its existing local-record reassessment and exact snapshot comparison. A stale, unreadable, disabled, failed or cancelled check has no projection. Existing no-write transaction assertions remain in place.

Codable round-trip support establishes a shared data contract, not an export feature. The serialized projection omits raw provider sample IDs and source identities, but still contains sensitive session identity, reviewed dates and timezone metadata. Export consumers must apply their existing redaction rules before sharing. Decoding a snapshot does not establish current validity. The original samples and stage/source detail remain in the separate provider evidence.

There are no database migrations, new UI controls, changes to existing chart/export totals, dose/alarm writes or phone installation. Version/build remains 0.4.19 (43); this is internal integration work, not a new install recommendation.

## Validation

- Test-first run failed because the projection type was absent. The initial six tests passed after implementation; two further cases cover fresh deletion and the repeated DST hour.
- `swift build -q` passed. UTC and America/New_York core runs each passed 692 XCTest and 43 Swift Testing cases, with no failures. Logs: `/tmp/dosetap-reviewed-projection-core-utc.log` and `/tmp/dosetap-reviewed-projection-core-ny.log`.
- The unsigned generic iOS Simulator build passed. Log: `/tmp/dosetap-reviewed-projection-build.log`.
- The medication-transaction run passed 51 tests with no failures or skips on iPhone 17 Pro / iOS 26.5 (`/tmp/dosetap-reviewed-projection-app.xcresult`). The initial HealthKit selector used the filename rather than the suite name and matched no tests. The corrected `HealthKitProviderTests` run passed 27 tests with no failures or skips (`/tmp/dosetap-reviewed-projection-healthkit.xcresult`). Both counts were read from the result bundles.
- Plane workflow (15 tests, 80 assertions), SSOT, architecture, dose-state-write, repository hygiene, app-version and whitespace checks passed. No UI layout changed; new visual or signed-device acceptance is not claimed.

## Remaining work

Chart/report adoption, report redaction and parity remain open. DOSETAP-57's dose-to-sleep/return-to-sleep markers, awake episodes and completed counts are not implemented by this slice. Durable provider revision/deletion reconciliation, source/report provenance and app-wide permission/query-readiness wording remain open. A fresh query reflects current returned samples; it is not a persisted import ledger.

Signed-device HealthKit, real-data parity, provider corrections, travel/date-entry, VoiceOver and owner acceptance remain separate. The historical unexpected Dose 2 investigation, medication/alarm restart acceptance, privacy/release and complete backup/restore gates remain open. Previous implementation evidence is retained in the September 9 provider-check and reviewed-window-assessment audits.

The preserved legacy checkout, two unrelated Xcode edits and untracked icon review directory are excluded. Reverting the scoped projection commit removes this in-memory contract without a data migration.
