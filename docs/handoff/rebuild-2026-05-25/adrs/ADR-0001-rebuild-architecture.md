# ADR-0001 — Incremental Local-First Rebuild

Date: 2026-05-25
Status: Proposed

## Context

DoseTap has a clinically sensitive core workflow: two-dose nighttime timing, session rollover, morning check-in closure, offline use, and multi-channel dose entry. The existing repo contains substantial domain logic, tests, storage schema, diagnostics, and historical audit knowledge.

A full greenfield rewrite would risk losing edge-case behavior around dose windows, late Dose 2 classification, extra dose indexing, DST/timezone grouping, and cross-channel confirmation.

## Decision

Rebuild incrementally around a stable domain and storage boundary:

1. Freeze the SSOT and dose registration policy first.
2. Route every state-changing channel through canonical use cases.
3. Introduce storage protocols before replacing storage.
4. Run storage migration in shadow mode before any production write cutover.
5. Keep local-first dose logging as the invariant.
6. Feature-flag integration and dashboard changes.

## Alternatives Considered

### Full Greenfield Rewrite

Rejected for first release. It maximizes design freedom but creates unacceptable data-loss, behavioral regression, and validation risk.

### Keep Existing App and Only Add Features

Rejected as the complete strategy. The current app has enough duplicated surfaces, legacy/deferred code, and documentation drift that simple feature accretion will compound maintenance risk.

### Backend-First Rebuild

Rejected for first release. DoseTap handles sensitive medication and sleep data. A backend introduces account, IAM, HIPAA-adjacent, breach, cost, and availability concerns. Local-first plus optional user-owned sync is the safer baseline.

## Consequences

Positive:

- Preserves proven behavior.
- Allows rollback per boundary.
- Keeps user data local during migration.
- Lets integrations fail independently.
- Improves testability and channel parity.

Negative:

- Takes more discipline than a rewrite.
- Requires maintaining old and new storage paths during migration.
- Some UI cleanup must wait until domain/storage seams are stable.

## Rollback

Each milestone must be independently reversible:

- Policy layer can route channels back to legacy paths.
- Storage migration writes to a new store first and keeps old SQLite intact.
- Dashboard V2 remains feature-flagged.
- Integrations are individually disable-able.
- Release candidate can ship with old local storage if sync/migration fails.
