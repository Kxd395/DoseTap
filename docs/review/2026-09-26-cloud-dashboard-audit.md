# Separate iPad dashboard: cloud audit and first foundation

Plane: DOSETAP-76. Date: 2026-09-26. Base: main 90db5d9 (PR65).

## Verified current state

The installed build76 artifact is local-only: no CloudKit entitlements, and no
Info.plist opt-in flag (the service fails closed when it is absent). The project
explicitly sets shipping sync NO and staging YES. The local readiness script
passes configuration/entitlement checks; this is not hosted schema or data evidence.
The iPad currently has the full DoseTap app, not a separate dashboard application.

`DeferredCloudKitSyncService` uses the default container's private database and
DoseTapZone. It uploads local records and deletion tombstones, then imports remote
changes and deletions into the phone repository. Its default lookback is 120 days.
It must not be reused as the dashboard's read-only reader.

| Dataset | Legacy upload path | Reporting work remaining |
| --- | --- | --- |
| Sessions, dose events, quick logs | Explicit record builders | Verify all fields, identity conflicts, deletion and date coverage |
| Pre-sleep and morning | Explicit record builders | Verify lossless current answers and source/normalized provenance |
| Legacy general medication entries | DoseTapMedicationEvent builder | Preserve occurrence vs creation; include no-night records |
| Saved prescription presets and administration ledger | No builders in this service | Full immutable versions, actual snapshots and amendments |
| Independent daytime diary | No builder | Timed observations and missingness |
| Reviewed sleep boundaries | No builder | Source evidence and derivation versions |
| Inventory and related records | No builder | Define reporting scope and complete producer |
| Apple Health / WHOOP evidence | No builders | Consent, allowed cloud treatment, source/coverage and intervals |

These are code-path observations, not proof of records in the hosted private
container. No cloud account contents, schema deployment, upload or download was
performed. Existing historical cloud copies may exist; completeness is unknown.

## Bounded implementation

The core now provides a Codable reporting snapshot, SHA-256 payload checks, explicit
complete/unavailable sections and a pure in-memory acceptance reducer. All local
sections must be present and readable; provider absence is explicit. Invalid or
partial refreshes retain the old snapshot. Account/source switches clear it. Old
revisions and changed same-revision retries fail. A complete empty generation can
remove a row from reporting without deleting anything on the phone.

This is transport-independent foundation, not a working cloud feed or installed
new app. It introduces no iPhone runtime calls, schema migration, entitlements,
cloud permission, alarm change or app-version bump. Tests use synthetic data only.

## Next implementation sequence

1. Checked repository reporting projection covering all source ledgers, with
   transaction consistency, independent medication calendar dates and parity tests.
2. Durable source revision/outbox and CloudKit adapter in a separate reporting zone,
   immutable assets, verified head publication, bounded retention and explicit purge.
3. Separate iPad target with download-only APIs, protected cache, account/source
   selection, offline freshness display and interactive analytics.
4. Synthetic real-device round-trip, failure/account/deletion tests, then scoped
   owner-data parity and privacy acceptance before enabling phone publishing.

The ZIP remains optional. The approved primary direction is automatic private
cloud reporting. Same-container multi-app access is supported by Apple's
[CloudKit design guidance](https://developer.apple.com/icloud/cloudkit/designing/).
DOSETAP-14 retains cloud privacy/disclosure work; this slice does not close it.
