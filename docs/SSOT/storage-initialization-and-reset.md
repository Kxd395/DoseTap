# Storage initialization and reset

Status: Current behavior contract
Plane: DOSETAP-39

## Explicit local reset

- Clear All Data deletes the app-owned clinical SQLite collections in one checked transaction. It retains schema and migration metadata. The existing staging tombstone queue and external stores remain outside this bounded reset; the confirmation discloses the retained data rather than claiming a full account purge.
- A failed database preflight, BEGIN, DELETE or COMMIT reports a structured reset failure. A successfully rolled-back reset leaves all source records, the active session, preferences and reminder intent unchanged. No success notification or UI publication occurs.
- A failed rollback makes the database handle unavailable to later writes. The UI reports unresolved storage and asks the user to restart; it must not claim that every record was preserved or erased.
- Only a committed reset can clear in-memory session state, reset preferences, and request cancellation of app-owned notifications and system wake alarms. Alarm cleanup is a separate post-commit result; an unverified cancellation cannot undo deletion or be presented as verified cancellation.
- Alarm cleanup never removes another app's notifications. Readback covers pending and delivered app-owned dose and supply notifications and the system wake alarm. A newly started medication session invalidates reset-only cleanup/retry.
- Diagnostic files, generated exports, integration credentials and provider-owned Apple Health/WHOOP records are not deleted by this bounded repair. Complete store coverage, lossless recovery, staging convergence, signed-device alarm delivery and owner acceptance remain open under DOSETAP-39 and their existing related items.
- Routine failure telemetry identifies operation, stage, SQLite code and rollback outcome without clinical records, notes, amounts or credentials.

## Checked schema initialization

- Opening a database does not establish readiness. Initialization checks each schema inspection, statement, backfill, ledger write and version read/write.
- Table creation, legacy column additions, indexes, source backfills, named migrations, ledger entries and `user_version` run in one transaction. Indexes are created after legacy columns exist.
- A failure rolls back the entire initialization and exposes `databaseInitializationFailure`. The connection is closed so legacy write paths cannot use a partially initialized store. A failed rollback remains an unresolved recovery gate.
- Databases from a newer schema version are refused without downgrading or modifying their source records. Repair/recovery uses a reopened connection after the cause is resolved; migration markers are never stamped after a failed operation.
- Existing legacy identity and deduplication rules are preserved. This transaction boundary does not close restore coverage, linked-record migration, signed-device or owner-observed acceptance gates.
