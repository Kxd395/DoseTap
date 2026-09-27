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

## Follow-up: both server and direct-device routes

Owner approved investigation of both paths. The prior recommendation to publish
clinical snapshots to CloudKit is superseded by Apple's current5.1.3(ii) iCloud
restriction, which applies more broadly than raw HealthKit. No private-account or
owner-consent exception is assumed. See the updated reporting contract.

For nearby updates, Multipeer Connectivity supports discovery and sessions; use
required encryption, explicit authenticated pairing and no health data in discovery
metadata. The initial scope is foreground nearby refresh, not an always-running
background service. Local network consent must be handled. No direct adapter or
connection permissions have yet been installed on either device.

For remote updates, inspect the existing restricted server gateway and dedicated
service/authentication/retention readiness before deploying a reporting API.
Do not expose a database port or repurpose an unrelated business database.
The existing historical Supabase/PostgreSQL inventory is not proof that a DoseTap
backend exists or that the host is ready to store clinical reporting data.

### Existing-server investigation result

The restricted `serverctl.py status --timeout 20 --json` attempt failed with exit255,
`Permission denied (publickey)`, and no gateway response. No current remote database
or service state was obtained. The reviewed client only exposes status, disk_status
and backup_status; even successful status lacks database/application inventory.
The Mac-local registry has no DoseTap entry, which does not prove remote absence.
The July24 server inventory is historical. No configuration, service, database or
clinical record was changed. The private computer work log records the attempt.

Next server prerequisite: repair the restricted authentication path through the
approved administration workflow, then provide a fixed read-only metadata action
for service health and DoseTap schema/role presence. No generic SSH or database port
exposure is an acceptable substitute. The direct nearby route can progress without
this server prerequisite; it still needs implementation and real paired-device tests.

### Checked local producer

The new repository entry point reads source rows in one SQLite transaction and
retains exact tagged values, orphan/no-night records, all dates and unknown columns.
Canonical preset/admin validation runs in that transaction. The amendment ledger is
explicitly not-collected, not falsely counted as zero. Provider evidence is explicitly
unavailable, and no networking is called. Current source table mapping is specified
in the contract. Reporting row counts are not clinical observation counts.
