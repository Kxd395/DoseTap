# Private cloud dashboard reporting

Status: foundation only, DOSETAP-76. No shipping transport or iPad app yet.

## Transport correction, 2026-09-26

The earlier CloudKit proposal is superseded. Apple App Review Guideline5.1.3(ii)
prohibits personal health information in iCloud. Private-account storage and owner
consent do not establish an exception. No clinical CloudKit upload is authorized
by this contract. Existing source type names remain for compatibility and are
transport-independent. The owner requested investigation of BOTH an existing
private server/database and direct phone-to-iPad transfer. Neither is deployed.

Source: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research).

The owner approved a separate read-only iPad dashboard refreshed through private
cloud storage. ZIP import is optional, not the primary workflow. The iPhone remains
local-first: cloud upload cannot block logging, alter medication state, or operate
alarms. The reader must never call the legacy bidirectional sync service.

## Snapshot acceptance v1

`CloudDashboardSnapshot` is a complete reporting generation for one selected source
installation. A monotonically increasing sequence is scoped to that installation;
wall-clock time is descriptive, not revision ordering. A fresh installation uses a
new source ID and requires explicit source selection. Account scope is supplied by
the authenticated transport, not trusted from downloaded JSON. Changing account or
source clears the in-memory view; a delayed response from the old context fails.

Each generation declares every dataset exactly once, including empty datasets.
Local datasets must be complete before acceptance, except the explicitly
not-collected amendment ledger absent from the current storage schema. Its
`notCollectedBySource=true` declaration has no payload/count/hash; it is not zero. Providers may be unavailable,
with an explicit reason and no payload; unavailable is never a measured zero.
Required datasets: sessions, dose events, quick logs, pre-sleep and morning source
answers, normalized answers, legacy medication entries, preset versions,
administrations, amendments, daytime diary, reviewed sleep windows, inventory,
symptom/body-map source evidence, work/wake schedule, Apple Health evidence, WHOOP evidence. The local producer mapping below preserves source evidence; semantic dashboard
projection and parity remain separate gates.

Payloads are JSON arrays; declared count must match, and SHA-256 must match bytes.
All sections are validated before the last accepted generation changes. A repeated
identical generation is idempotent; a changed same-sequence generation is rejected.
Older sequences, unknown schemas/datasets, duplicate sections, corrupt bytes,
incomplete local datasets and invalid timestamps are rejected. A failed refresh
retains the last accepted snapshot and its original capture time. An empty complete
array replaces the previous array, allowing source deletions to disappear from the
reporting copy without issuing any phone mutation. No partial merge or date cutoff
is implicit. Consumer reports must still validate source identity and metric rules.

The core reducer is in-memory only; durable cache, encrypted/protected files,
account-change invalidation, transport size limits, producer read transaction,
revision/outbox persistence and asynchronous request-generation fencing must be
implemented and tested before connection. SHA-256 detects corruption; it is not
sender authentication or a substitute for private account authorization.

## Historical CloudKit adapter proposal (not delivered; superseded)

Do not implement this proposal for clinical data without resolving the Apple
policy restriction above. Historical technical design:
Use a separate reporting zone/type, immutable asset generations and a head pointer
published only after the entire asset is uploaded. Compare-and-save the pointer;
never let a delayed retry move it backward. Keep the last accepted local cache on
network failure. The iPad API exposes downloads only, no source CRUD or alarm APIs.
Both apps must use the same authenticated account/container/environment. Read-only
is an application capability boundary, not a claim of server-enforced read-only
CloudKit entitlements. Old asset retention and remote purge require explicit rules.

Apple supports multiple apps using one container:
[CloudKit design](https://developer.apple.com/icloud/cloudkit/designing/).
No private cloud records were downloaded or uploaded in this foundation slice.

## Acceptance gates

- Full repository projection with checked reads, transaction consistency, stable
  IDs and app/Excel/ZIP parity; include independent medications with no night.
- Private cloud schema inspection, development/production separation, provisioning,
  synthetic upload/read round-trip, interrupted upload and offline recovery.
- Persistent revision/outbox, source replacement, account sign-out/switch,
  deletion/purge, retention and iPad cache protection.
- Provider consent and permitted cloud handling; no automatic raw Health upload.
- Separate iPad target/UI, real phone/iPad parity, accessibility, privacy/disclosure
  (DOSETAP-14), performance and owner acceptance.

## Approved connection investigations

- Private server: investigate the existing service inventory through the restricted
  workstation gateway. Require dedicated authenticated reporting endpoints,
  per-owner isolation, encrypted transport/storage, deletion/retention, backups and
  restore evidence before deployment. Database presence is not a ready DoseTap API.
- Direct nearby transfer: evaluate Multipeer Connectivity with required encryption
  and explicit paired-peer authentication (a device display name is not identity).
  No PHI in discovery metadata. Transfer a bounded complete generation, authenticate
  the sender, validate before atomic cache replacement, and support revocation.
  Foreground nearby refresh is the initial scope; do not promise constant background
  delivery or access across networks. Local-network consent denial must be recoverable.

Both transports must share the same producer/validator and source revision sequence.
Neither grants the iPad any phone clinical-write or alarm API. Provider cloud policy,
server deployment, actual device pairing, accessibility and owner acceptance remain
open gates. The separate dashboard must show disconnected/stale status honestly.

Apple references: [Multipeer sessions](https://developer.apple.com/documentation/multipeerconnectivity/mcsession)
and [local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## Local producer mapping

`SessionRepository.dashboardSnapshot` delegates to a checked SQLite read transaction.
No existing write transaction is accepted. Every source read must succeed; rollback
on any read/encoding error does not roll back someone else's transaction. No cutoff,
identity repair, inferred event or provider fetch occurs. Unknown columns and tagged
SQL NULL/text/integer/real/blob values are retained. Source-table row counts are not
clinical observation counts. Canonical medication payload checks remain active.

| Section | Source tables/evidence |
| --- | --- |
| sessions | sleep_sessions, current_session |
| doseEvents / quickLogs | dose_events / sleep_events |
| preSleep / morning | pre_sleep_logs / morning_checkins |
| normalizedAnswers | checkin_submissions |
| medicationEntries | medication_events, including NULL session IDs |
| presetVersions / administrations | medication_preset_revisions / confirmed_medication_administrations |
| amendments | Explicit not-collected; no durable ledger yet |
| daytimeDiary | morning_checkins plus night_outcome submission source rows |
| reviewedSleepWindows | night_outcome source rows, including revisions |
| inventory | inventory_snapshots, supply_state |
| symptoms | symptom_events, symptom_locations, body_map_points, symptom_command_log, symptom_summaries |
| workSchedule | work_wake_schedule |
| appleHealth / whoop | Explicit unavailable; no provider upload or query |

Repeated source rows across sections retain source identity and must not be counted
as multiple observations. Derived symptom caches/audit entries are not new symptoms.
The snapshot excludes schema_migrations and legacy cloudkit_tombstones intentionally;
full replacement represents reporting deletions without remote phone deletes.
UserDefaults, Keychain, files/preferences and provider stores are separate owners,
so this is not a full-device backup. Durable publisher revisions, payload size limits,
identity conflict classification and consumer analytics remain unimplemented.

## Initial separate dashboard display and nearby transport

The first display projects dose-day review states and medication occurrences from
source evidence. Dose spacing requires a single positive ordered pair; skipped,
missing and duplicate/conflicting sources remain distinct. Medication dates come
from occurrence plus retained offset, not treatment-date grouping. Unknown time or
unavailable offset cannot be reconstructed from capture time. No efficacy or safety
score is produced. Provider sleep evidence remains explicitly unavailable in this
initial transport; the app must not imply that sleep metrics were transferred.

Nearby pairing requires an out-of-band random secret, fresh challenge nonces and
mutual authentication before report requests or payload delivery. MC encryption is
required; application authenticated encryption also protects payloads against a
relay terminating two MC sessions. Discovery names are not identity. The publisher
accepts an invitation explicitly. Secrets expire when the pairing session ends;
no clinical payload enters advertising metadata, logs or clipboard automatically.
The iPad is a separate app target and has no source write or alarm capability.

Nearby prototype v1 uses a fresh 256-bit out-of-band key, role-separated HMAC
proofs over both random nonces, directional HKDF keys and ChaChaPoly envelopes.
Counters reject replay; the publisher accepts only a requested snapshot. Snapshot
payload limit is32MiB; incomplete/failed transfers retain the last verified report.
No background availability or forward secrecy is claimed. Both apps must stay open.
The phone reserves a durable monotonic revision before capturing; failed delivery
may leave a revision gap. Corrupt identity state fails closed. The iPad persists
only after full validation and projection, with complete file protection and
backup exclusion. A new phone source requires explicitly forgetting the old copy.

The separate iPad target is `com.dosetap.dashboard`, version0.1.0(1), generated
from `ipad/project.yml`. It contains no EventStorage, medication writer or alarm
service. Initial views are recorded dose spacing, medication calendar occurrences,
night review states and connection status. All-time medications are explicitly
separate from treatment-date-filtered interval trends. A provider sleep dashboard,
automatic background updates and private-server transport remain later gates.
