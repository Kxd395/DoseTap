# DoseTap audit evidence

Status: Point-in-time evidence
Last updated: 2026-09-12

Each dated folder records the checkout, commands, observations, and limits for that audit. Findings do not become current product truth merely because the report is recent. Recheck the code, tests, external systems, and Plane state before acting on them.

- `2026-02-15/`: earlier full audit
- `2026-08-31/`: current broad audit baseline
- `2026-09-01/`: data-integrity, dashboard, timezone, Apple Health, diagnostics, and CRUD delta audit
- `2026-09-04/`: branch consolidation and computer-use smoke/layout repairs
- [September 5 integration readiness](2026-09-05/integration-readiness.md): integration decision and remaining gates at that checkpoint
- [September 9 Plane quick wins](2026-09-09/plane-quick-wins.md): tracker reconciliation evidence and limits on closure
- [September 12 collection/store/export audit](2026-09-12/README.md): owner reading guide, effective stored-field inventory, reproducible export findings and follow-up delivery links

Later code changes belong in linked [delivery records](../review/README.md#delivery-records). Preserve the original audit baseline and failed probes; use a follow-up record to explain what was repaired and validated.

The latest release recommendation in repository evidence is `HOLD`. Plane owns remediation status.
