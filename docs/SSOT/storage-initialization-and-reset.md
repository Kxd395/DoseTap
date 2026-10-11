# Local data reset

Status: Current behavior contract
Plane: DOSETAP-39

## Explicit local reset

- Clear All Data deletes the current app-owned clinical SQLite collections in one checked transaction, including daytime observations/events/prompts, naps, physician review, work context and dashboard review/association records. It retains schema and migration metadata. The staging tombstone queue and external stores remain outside this bounded reset; the confirmation discloses retained data.
- A failed preflight, BEGIN, DELETE or COMMIT reports a structured failure. Successful rollback leaves source records, active session, preferences and reminder intent unchanged. No success publication occurs.
- A failed rollback makes the database handle unavailable to later writes. The UI reports unresolved storage and asks the user to restart, including on repeated reset attempts before reopening; it must not claim that every record was preserved or erased.
- Only a committed reset can clear in-memory session state, reset preferences, and request cancellation of app-owned dose, supply and daytime notifications and system wake alarms. Cleanup verification is separate from database commit; it cannot undo deletion or be presented as verified cancellation when readback fails.
- A committed reset advances a repository generation before publication. Daytime work checks that generation after suspension and before further adds/retries or opening an old prompt. Reset cleanup holds new service work, resumes/discards old queued actions, and waits for an in-flight update before cancellation. It cannot report clean while an old OS add is outstanding.
- Consecutive resets reuse cleanup only within the same generation. A newer reset waits for older cleanup to drain, then performs its own cancellation/readback; obsolete tasks cannot clear the newer task or publish its status.
- Readback covers pending and delivered owned requests and the system wake alarm. Daytime cleanup verifies both queues, treats unavailable delivered readback as unverified, and preserves unrelated identifiers. Its source/generation checks reject stale cleanup after another reset or a newly saved routine; a newly started medication session invalidates dose/supply reset-only readback presentation.
- Post-commit cleanup warnings are persisted and presented at app scope until acknowledgment, including when preferences removal returns the app to setup. A new medication session does not suppress an independent daytime-cleanup failure. Pre-commit database failures remain on the unchanged Settings screen.
- Diagnostic files, generated exports, integration credentials and provider-owned Apple Health/WHOOP records are retained and disclosed. Complete store coverage, lossless recovery, staging convergence, signed-device alarm behavior and owner acceptance remain open.
- Routine failure telemetry identifies operation, stage, SQLite code and rollback outcome without clinical records, notes, amounts or credentials.

This slice adapts the reviewed reset repair from `b0960d3` to the current app, including its newer daytime integration. The separate schema-initialization repair on PR #74 is not part of this integration and remains an explicit follow-up.
