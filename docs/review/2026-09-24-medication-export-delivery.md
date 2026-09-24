# Medication export delivery — build 66

Date: 2026-09-24. Plane: DOSETAP-73 (In Progress).

## Delivered behavior

Build **0.4.19 (66)** adds **Dose Summary** and **Medication Log** directly after Overview in Settings → Export Excel Workbook. Workbook schema 2 has 17 sheets and retains all 15 existing sheets. Studio JSON/ZIP schema and clinical records are unchanged.

Dose Summary provides one exported treatment-date group with dose outcomes, local occurrence times, interval, available amounts/units, reminder choice, explicit recording times/delay, reasons, and source evidence. Medication Log brings canonical doses and separately logged medications into one sortable table, preserving original source identity and payload variants. Skip, correction and snooze rows are labelled separately from administrations. Local text includes the export timezone offset; typed UTC dates and numeric duration/minute columns support analysis.

The same read-only outcome/time reconciliation now feeds Dose Summary, Nights and Night Review. Duplicate taken events, taken/skip contradictions, source/summary disagreement and unresolved date identities cannot produce a trusted interval. Source occurrence times can be used when summary times are absent. Removal evidence blocks stale summary-only timing. Correction time stays separate from initial recording time: an edit days later is not a days-long logging delay.

Historical medication identity, amount, exact/approximate precision and configured windows are not invented from current settings. Dose-to-sleep and return-to-sleep projections remain follow-on work under the reviewed DOSETAP-57 measurement contract. Missing values are not zeros and reminders do not define the dosing window.

## Export workflow repair

The native export journey initially stalled at “Reading records and available sleep data…” with Health enabled OFF. Inspection found the consent snapshot unconditionally awaited HealthKit authorization refresh whenever HealthKit was available. Export now skips that refresh when the integration is disabled. The unchanged native test then passed, including a second export. Enabled-provider enrichment keeps its existing path; this does not establish live provider completeness or timeout behavior.

## Validation

- Core: **756 XCTest + 43 Swift Testing cases**, no failures. Eight medication projection regressions cover metadata, explicit skips/missingness, raw-only identities, conflicts, correction and removal.
- iOS: **6 Excel/source-snapshot integration tests**, no failures; fixture confirms explicit retrospective recording delay while dose interval uses occurrence time, and verifies source bundle/database records remain unchanged.
- Native simulator: `testExcelWorkbookExportPresentsCompletedShareSheet` passed after the disabled-provider guard, including two completed share sheets. An initial combined invocation incorrectly selected a UI target outside the DoseTap scheme; integration and UI were rerun under their correct schemes.
- Native Microsoft Excel: production-writer synthetic workbook opened without repair, both new sheets visually inspected, numeric interval sorted and explicit-skip outcome filtered (1 of 6 groups). Save/close/reopen succeeded. Independent XML readback preserved all 6 summary row payloads and 18 medication row payloads after Excel save. This is desktop fixture evidence, not owner phone acceptance.
- Signed build 66 was installed as an update on the paired owner phone and independently read back as 0.4.19 (66). The owner returned a new phone-generated workbook; read-only inspection verified 17 sheets, interval arithmetic/Nights parity, and complete canonical-dose source-key coverage in Medication Log. Export-file generation is evidenced; phone viewer name and owner readability/sort acceptance were not supplied.
- Unsigned simulator and signed device builds passed. All four app/staging Debug/Release configurations report 0.4.19 (66). Strict signature verification passed.
- Swift build, SSOT, documentation, architecture, dose-write, legacy safety, companion-target, repository hygiene, Plane workflow and whitespace guards passed.
- The newly supplied owner workbook was inspected read-only: populated intervals reconcile with exported absolute timestamps. It remains the prior 15-sheet format. Private files, counts and source values remain outside Git/Plane.

Temporary local evidence: `/tmp/dosetap-medication66-final-core.log`, `/tmp/dosetap-medication66-integration-final.xcresult`, `/tmp/dosetap-medication66-ui-fixed.xcresult`, `/tmp/dosetap-medication66-ui-proof`, and `/tmp/DoseTap-medication66-review.xlsx`. These may be cleaned; this record is the durable summary.

## Remaining acceptance and next slice

- Owner save/open and medication-view usability in the actual phone viewer; separate accessibility, privacy and release acceptance.
- Prospective amount, medication identity, time precision, recording provenance and historical-window capture across all administration/correction paths require their own reviewed contract. This projection does not backfill absent evidence.
- Reviewed dose/sleep metric parity, live-provider completeness and transaction-wide export consistency remain separate work.
- Continue DOSETAP-73 In Progress. A merged implementation or successful signed installation does not close these gates.

See the [original storage/export review](2026-09-24-medication-export-review.md) and [current workbook contract](../SSOT/contracts/ExcelWorkbook.md).
