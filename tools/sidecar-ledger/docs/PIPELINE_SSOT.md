# SidecarLedger SSOT (invariants + state machine)

## Sources of truth

* **Metadata truth**: `.xmp` sidecar content.
* **Process truth**: `ledger.sqlite` (hashes, locations, verification + commit history).

The ledger **must never** store “meaning metadata” (keywords, descriptions, titles). It only stores evidence and lifecycle.

## Lifecycle states

`media_item.status` is a state machine:

* `INGESTED`: detected but not yet copied/normalized
* `STAGED`: copied into `01_Staging` and hashed
* `WORKING`: placed into `02_Working` and sidecar exists
* `READY_FOR_REVIEW`: rules pass; ready for human review gate
* `COMMITTED`: moved into `03_Archive/YYYY/MM`
* `QUARANTINED`: validation failed or suspicious

Allowed transitions (enforced in code):

* `INGESTED -> STAGED`
* `STAGED -> WORKING` (sidecar created)
* `WORKING -> READY_FOR_REVIEW` (rules pass)
* `READY_FOR_REVIEW -> COMMITTED` (review gate passed)
* `* -> QUARANTINED` (on failure)

## Core invariants

1. `file_sha256` is stable for the binary. If it changes, it is a **new media item**.
2. Sidecar changes do **not** change `file_sha256`; they change `sidecar_sha256` and create a `verification_event`.
3. All file moves are recorded (e.g. `commit_event`).
4. A commit is reversible via the commit chain (future: rollback tool).
