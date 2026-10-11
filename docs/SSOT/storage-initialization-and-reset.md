# Local data reset

Status: Current behavior contract
Plane: DOSETAP-39

## Explicit local reset

- Clear All Data deletes the current app-owned clinical SQLite collections in one checked transaction, including daytime observations/events/prompts, naps, physician review, work context and dashboard review/association records. It retains schema and migration metadata. The staging tombstone queue and external stores remain outside this bounded reset; the confirmation discloses retained data.
- A failed preflight, BEGIN, DELETE or COMMIT reports a structured failure. Successful rollback leaves source records, active session, preferences and reminder intent unchanged. No success publication occurs.
- A failed rollback makes the database handle unavailable to later writes. The UI reports unresolved storage and asks the user to restart; it must not claim that every record was preserved or erased.
- Only a committed reset can clear in-memory session state, reset preferences, and request cancellation of app-owned dose and supply notifications and system wake alarms. Cleanup verification is separate from database commit; it cannot undo deletion or be presented as verified cancellation when readback fails.
- Dose/supply readback covers pending and delivered owned requests and the system wake alarm. Cleanup preserves unrelated notification identifiers. A newly started medication session invalidates stale reset-only cleanup.
- Diagnostic files, generated exports, integration credentials and provider-owned Apple Health/WHOOP records are retained and disclosed. Complete store coverage, lossless recovery, staging convergence, signed-device alarm behavior and owner acceptance remain open.
- Routine failure telemetry identifies operation, stage, SQLite code and rollback outcome without clinical records, notes, amounts or credentials.

This slice adapts the reviewed reset repair from `b0960d3` to the current app. Daytime reset cleanup must additionally drain in-flight work, prevent stale routine/request recreation and verify pending plus delivered owned identifiers; that integration remains pending. The separate schema-initialization repair on PR #74 is not part of this integration and remains an explicit follow-up.
