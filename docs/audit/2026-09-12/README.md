# Collection, storage and export review guide

Status: Navigation for point-in-time evidence and subsequent deliveries
Last updated: 2026-09-12

This packet answers what DoseTap collects, where it stores each record, and which fields Settings export preserves. The audit and stored-field inventory are pinned to **0.4.19 (50)**. Later repairs do not erase those findings; read their delivery evidence alongside the original baseline.

## Suggested reading order

1. [Owner collection inventory and dashboard plan](../../review/2026-09-11-dashboard-and-collected-data-review.md): Apple Health, conditional WHOOP, questionnaires, dose/bathroom/other logs, preferences and proposed work/off averages, explained by purpose.
2. [Collection/store/export findings](collection-store-export-audit.md): confirmed discrepancies, source/export coverage and the DC-01–DC-12 follow-up list.
3. [Stored field inventory](stored-field-inventory.md): exact SQLite columns, questionnaire properties and versioned payload names. A field in a model does not prove a visible input or an actively confirmed answer.
4. [Build 51 durable-log delivery](../../review/2026-09-12-durable-log-delivery.md): follow-up to DC-01's create/write feedback path. Other CRUD operations, process-termination recovery and the export findings remain separate.
5. [Build 52 export fidelity](../../review/2026-09-12-export-fidelity-delivery.md): DC-02/03 inventory/medication preservation, read-failure handling, Studio compatibility and exact Plane gate reconciliation.
6. [Build 53 event provenance](../../review/2026-09-12-event-export-provenance-delivery.md): DC-04 dose/sleep row identity, stored timestamps and metadata preservation; typed CSV unknown-event inclusion and full-backup acceptance remain separate.
7. [Local archive validator and Plane review](../../review/2026-09-12-plane-closeout-review.md): DC-12 consent omission repair, corrected DC-05 source interpretation and remaining acceptance. Tools/docs only; app stays build 53.

8. [Build 54 candidate: Health export missingness](../../review/2026-09-12-health-export-missingness-delivery.md): partial DC-05 repair for absent primary-sleep summaries and matching Studio missingness; provider-query error details, upstream evidence coverage and acceptance remain separate.

## Evidence and authority

- [Effective schema](evidence/effective-schema.json) records initialized table metadata; it contains no clinical rows.
- [Synthetic export probes](evidence/ExportAuditProbe.swift.txt) reproduce the original gaps. Passing these audit probes means the gap was reproduced, not that the export is correct.
- [DataDictionary](../../SSOT/contracts/DataDictionary.md) owns current field meanings; [SSOT](../../SSOT/README.md) owns current behavior. The Settings reporting archive is not a promised complete backup.
- [Planning index](../../PLANNING.md) links work owners. Plane owns live priority, state and acceptance: DOSETAP-39 for whole-project lifecycle evidence, DOSETAP-13 for export coverage, and DOSETAP-3 for medication write failures.

No owner database, live Health/WHOOP records or phone export was inspected for the original audit. Record personal examples in the local workpad; do not add clinical rows or credentials to this public evidence packet.
