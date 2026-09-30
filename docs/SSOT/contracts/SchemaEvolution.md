# Schema evolution

## Dashboard association schema increment

Status: current additive contract, 2026-09-30.

Dashboard association increment: add `dashboard_provider_associations` idempotently with the normal schema bootstrap; no existing records are relinked or backfilled. Store explicit source episode/session relationships only after revision and source checks. Unknown or changed fingerprints are unusable relationships, not authority to rewrite provider or medication data.

## Independent daytime observation ledger (2026-09-30)

Add `daytime_checkins` through idempotent `CREATE TABLE IF NOT EXISTS`. Each row stores a stable observation ID and unique immutable revision ID with validated JSON. Existing records are not migrated or reinterpreted. The ledger is independent of `sleep_sessions`; Clear All Data removes all of its revisions. Unknown content versions and invalid revision chains fail closed on read.

Additive daytime payload fields (`sourceLinks`) decode as absent for existing observations. Link schema version 1 validates explicit source evidence; unknown versions fail closed. No new table, no backfilled source associations and no conversion of legacy night ratings.
Add `daytime_prompt_state(id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL)` idempotently. One validated ledger holds schedule versions and prompt history; an atomic upsert preserves either the old or new whole ledger. Clear All Data includes this table; dose/session deletions do not.
