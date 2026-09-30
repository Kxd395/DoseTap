# Dashboard association schema increment

Status: current additive contract, 2026-09-30.

Dashboard association increment: add `dashboard_provider_associations` idempotently with the normal schema bootstrap; no existing records are relinked or backfilled. Store explicit source episode/session relationships only after revision and source checks. Unknown or changed fingerprints are unusable relationships, not authority to rewrite provider or medication data.
