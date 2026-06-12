# 03 — Architecture and Storage

## Target Architecture

Recommended layers:

```text
SwiftUI Surfaces
  -> View Models / Coordinators
  -> DoseRegistrationPolicy + SessionUseCases
  -> Repository Protocols
  -> Local Store + Optional Sync Adapter
  -> Platform Integrations
```

Rules:

- Views must not call storage directly.
- Every dose mutation must go through `DoseRegistrationPolicy`.
- Every state-changing action must produce a diagnostic event with correlation/session context.
- Integration data must be optional and provenance-labeled.
- Storage implementation must be swappable behind protocols during migration.

## Domain Services to Keep or Rebuild

| Service | Rebuild Decision |
| --- | --- |
| Dose window calculator | Keep behavior and tests; refactor only if tests prove equivalence. |
| Session key/timezone logic | Keep and expand tests. This is high-risk code. |
| Dose registration policy | Promote to canonical policy for every channel. |
| Session repository | Split by use case and protocol boundary; avoid a single oversized repository. |
| Diagnostic logger | Keep and expand for rebuild migration events. |
| Data redactor | Keep and make mandatory for exports/support bundles/logs. |
| API/offline queue | Keep if backend remains planned; otherwise quarantine. |

## Storage Strategy

### Current Baseline

SQLite is the current local source of truth. It has known tables for sessions, dose events, sleep events, pre-sleep logs, morning check-ins, and medication events.

### Target Requirements

- Local writes must succeed without network.
- All migrations must be idempotent.
- Every migrated row must preserve original IDs, session IDs, session dates, timestamps, and metadata.
- Deletes must use tombstones if any sync exists.
- Writes must be atomic at the session/action level.
- Storage must support data export without requiring sync.
- Schema version must be queryable from diagnostics.

### Migration Plan

1. Add `StorageVersion` and migration status metadata.
2. Build read-only inventory of existing SQLite databases.
3. Implement migration into target store behind a feature flag.
4. Run migration in shadow mode and compare row counts/checksums.
5. Enable dual-read verification for internal builds.
6. Switch writes only after parity passes.
7. Keep rollback path to original SQLite for at least one release train.

### Rollback Plan

- Before migration, create a local encrypted backup of the existing SQLite store.
- Migration writes to a new store path first.
- If migration fails, app continues using original SQLite.
- If post-migration validation fails, app flips back to original store and emits a migration failure diagnostic.
- Never delete the old store until user export and at least one successful new-store backup exist.

## CloudKit Decision Gate

CloudKit must not be production-enabled until these tests pass on real devices:

- iPhone to Watch dose event sync under 30 seconds.
- Airplane mode full session, then sync on reconnect.
- iCloud sign-out: local app still works.
- iCloud account switch: no data mixing.
- Delete propagation via tombstone.
- Migration of one year of data under performance target.
- Conflict tests for same-session edits from two devices.

## Performance Targets

| Operation | Target |
| --- | --- |
| App launch storage initialization | Under 500 ms added overhead. |
| Dose action local write | Under 100 ms p95. |
| Dashboard weekly query | Under 500 ms p95 for one year local data. |
| Migration of one year local data | Under 60 seconds. |
| Export one year local data | Under 10 seconds. |

Algorithm notes:

- Session lookups should be indexed by `session_id`, `session_date`, and UTC timestamps: expected O(log n) indexed lookup or O(k) bounded range scan.
- Dashboard aggregation should precompute per-session aggregates where possible: O(n) initial build, O(1)-O(log n) incremental update per changed session.
- Sync conflict resolution should operate per record/session, not full-database scans.
