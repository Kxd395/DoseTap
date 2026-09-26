# Private cloud dashboard reporting

Status: foundation only, DOSETAP-76. No shipping cloud transport or iPad app yet.

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
Local datasets must be complete before acceptance. Providers may be unavailable,
with an explicit reason and no payload; unavailable is never a measured zero.
Required datasets: sessions, dose events, quick logs, pre-sleep and morning source
answers, normalized answers, legacy medication entries, preset versions,
administrations, amendments, daytime diary, reviewed sleep windows, inventory,
Apple Health evidence, WHOOP evidence. v1 declarations do not certify that these
producers exist: production projection and semantic parity remain open gates.

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

## Cloud adapter plan (not delivered)

Use the existing private container only after verifying its schema and environment.
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
