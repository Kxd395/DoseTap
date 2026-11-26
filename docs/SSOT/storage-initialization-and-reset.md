# Storage initialization and reset

Status: Current behavior contract
Plane: DOSETAP-39

## Explicit local reset

- Clear All Data deletes the app-owned clinical SQLite collections in one checked transaction, including daytime observations, events and reminder state, naps, physician review, work context and dashboard review and association records. It retains schema and migration metadata. The staging tombstone queue and external stores remain outside this bounded reset; the confirmation discloses the retained data rather than claiming a full account purge.
- Every database this build opens contains the diary, dashboard and physician collections, because schema initialization creates them. Clear All Data checks the tables inside the write transaction. If another build created additional tables, even under the same schema version, the reset stops before deleting records. Reopen the database with the build that understands those collections. Ownership receipts that earlier main-branch builds wrote for `daytime_checkins` and `daytime_prompt_state` are retained metadata and do not change this rule.
- A failed database preflight, BEGIN, DELETE or COMMIT reports a structured reset failure. A successfully rolled-back reset leaves all source records, the active session, preferences and reminder intent unchanged. No success notification or UI publication occurs.
- A failed rollback makes the database handle unavailable to later writes. The UI reports unresolved storage and asks the user to restart; it must not claim that every record was preserved or erased. Repeated reset attempts on that unavailable handle retain the original failure and restart guidance.
- Only a committed reset can clear in-memory session state, reset preferences, and request cancellation of app-owned dose, supply and daytime notifications and system wake alarms. Cleanup verification is a separate post-commit result; it cannot undo deletion or be presented as verified cancellation when readback fails.
- A committed reset advances a repository generation before publication. Daytime work checks that generation after suspension and before further adds or retries, or before opening an old prompt. Reset cleanup holds new service work, resumes or discards old queued actions, and waits for an in-flight update before cancellation. It cannot report clean while an old OS add is outstanding. Consecutive resets reuse cleanup only within the same generation; a newer reset waits for older cleanup to drain, then performs its own cancellation and readback.
- Readback covers pending and delivered app-owned requests and the system wake alarm. Alarm cleanup never removes another app's notifications. Daytime cleanup verifies both queues, treats unavailable delivered readback as unverified, and preserves unrelated identifiers. A newly started medication session invalidates dose and supply reset-only readback; it does not suppress an independent daytime-cleanup failure.
- An unverified cleanup warning is a persistent app-root panel, remains visible through the return to setup, and persists until its acknowledgment button is pressed, including after restart. The panel scrolls when its content exceeds its bounded height so large-text acknowledgment stays reachable. Reset explicitly marks setup incomplete so default preferences cannot be mistaken for a completed legacy setup on restart. Pre-commit database failures remain on the unchanged Settings screen.
- Diagnostic files, generated exports, integration credentials and provider-owned Apple Health/WHOOP records are not deleted. Complete store coverage, lossless recovery, staging convergence, signed-device alarm delivery and owner acceptance remain open under DOSETAP-39 and their existing related items.
- Routine failure telemetry identifies operation, stage, SQLite code and rollback outcome without clinical records, notes, amounts or credentials.

## Session deletion and retention

Deleting a night removes its explicitly dated dashboard dose reviews and provider
associations in the same transaction as the other records owned by that night.
Age-based retention applies its original cutoff to those two tables as well.
Neither operation infers a relationship between a night and the other six
independent diary collections. A failed deletion rolls back the scoped operation.
The app retains the displayed night and its active dose alarms, and deferred sync
must retry before advancing past a failed local deletion. The whole-database reset
guard still applies.

## Checked schema initialization

- Opening a database does not establish readiness. Initialization checks each schema inspection, statement, backfill, ledger write and version read/write.
- Table creation, legacy column additions, indexes, source backfills, named migrations, ledger entries and `user_version` run in one transaction. Indexes are created after legacy columns exist.
- A failure rolls back the entire initialization and exposes `databaseInitializationFailure`. The connection is closed so legacy write paths cannot use a partially initialized store. A failed rollback remains an unresolved recovery gate.
- Databases from a newer schema version are refused without downgrading or modifying their source records. Repair/recovery uses a reopened connection after the cause is resolved; migration markers are never stamped after a failed operation.
- Existing legacy identity and deduplication rules are preserved. This transaction boundary does not close restore coverage, linked-record migration, signed-device or owner-observed acceptance gates.
