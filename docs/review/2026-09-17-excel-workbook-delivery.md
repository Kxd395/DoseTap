# Styled, sortable Excel workbook delivery

Date: September 17, 2026
Plane: DOSETAP-13, In Progress
App: 0.4.19 (62)
Status: Validated implementation installed on the owner's phone; integration is tracked by the feature PR and Plane workpad. This is not release acceptance.

## What changed

Settings → Data Management adds **Export Excel Workbook**. It creates one dated XLSX from the same finalized JSON and inventory CSV used by the Studio export. **Export Studio Bundle** and scheduled ZIP exports remain available. The workbook has no database writes, medication actions, new provider queries of its own, macros, executable formulas, external links or automatic refresh.

The first three sheets are Overview, Nights and Night Review. Details follow in Events, Pre-sleep, Morning, Pain, Daytime, Sleep Measures, Sleep Intervals, Medications and Inventory. Source Fields, Review Issues and Field Guide complete the 15-sheet workbook.

Every sheet contains a named Excel table with column-header sorting/filtering, frozen headers and identity columns, readable navy/teal formatting, alternating rows and typed numeric values. Durations display as hours/minutes and retain their numeric value. UTC dates have sufficient width for the full timestamp. IDs and user notes remain literal text, including strings beginning with `=`. Empty sources have one blank table compatibility row, explicitly labeled as zero records.

## How to use it

1. In the app, choose **Export Excel Workbook**, wait for the share sheet, then choose **Save to Files**. Open the saved XLSX in Excel.
2. Start on Overview for fixed 7-, 14-, 30-day and full-export summaries, usable counts and separate provider/confirmed-work/schedule-estimate populations.
3. On Nights or a detail sheet, use any column-header arrow to sort or filter. Sorting moves each complete record together. Excel's multi-column Sort can combine treatment date and event time.
4. Filter **Night Review** by Treatment date and Date group to inspect one night's facts and evidence. Navigation links go to table headers; they do not select a date or alter other filters.
5. Use Field Guide's Owner review and Owner notes columns for collection feedback. These are workbook-only comments. Clinical corrections still belong in the app, followed by a fresh export.

Overview is a fixed snapshot. Filtering a detail table does not recalculate the Overview. Do not append complete exports together as new observations; use stable source keys and explicit reconciliation for multi-export analysis. Prefer the versioned Studio archive for exact source bytes and software ingestion.

## Fidelity and measurement boundaries

Original event/questionnaire records are deduplicated by table, source ID and payload variant. Every date-group association and conflicting variant remains inspectable. Unresolved identity, contradictory or reused session identities and cross-date original-record associations exclude unsupported combined metrics. Missing, null, empty, explicitly unsure, skipped, zero and unavailable remain distinct.

Source Fields retains unknown keys, original JSON text, parsed views, SQLite type tags, source associations and numbered parts for long values/paths. Workbook schema 1, input SHA-256 hashes and table grains are included. The Studio archive remains export 2.8/schema 3; no SQL migration or source format change is introduced.

Night Review shows direct exported awake intervals intersecting Dose 2 and the next exported asleep start. It does not invent an accepted dose-to-sleep/return-to-sleep metric when the complete reviewed projection is absent. Detailed interval stage/device/sample provenance, saved preferences outside the archive and historical confirmation/window snapshots remain unavailable. Provider episodes are not complete 24-hour sleep, and an overlapping event does not establish why someone woke.

The projection is read-only and local. Generation runs off the main UI thread, with progress, a duplicate-export guard, requested-format retry, atomic file publication and temporary-source cleanup. Standard ZIP DEFLATE reduces the workbook size. Reusing one finalized archive does not close the existing cross-source concurrent-write consistency gate.

## Validation evidence

- Core: `swift build -q` and `swift test -q` passed **741 XCTest and 43 Swift Testing cases**. The new writer/projection suites cover typed sorting inputs, empty tables, date/time boundaries, unknown fields, long values, source conflicts, zero/missingness, literal formula-like text, XML escaping, ZIP CRC/decompression and chart gaps.
- App integration: **6 tests passed** across ExcelExportTests and ExportSourceSnapshotTests. The production exporter generated a workbook from synthetic records; encoded stored records and source JSON stayed unchanged, and invalid input could not publish a workbook.
- Existing export regression: **42 tests passed** across WHOOP status, Apple Health missingness, record fidelity, integrity and import round-trip suites. An initial selector used a filename instead of class names; the actual five classes were subsequently run and passed.
- Unsigned iOS Simulator build passed. Native Settings UI exposed both export choices and a completed Office Spreadsheet share item. The journey dismissed the share sheet and successfully exported again. An initial test queried a button; the runtime exposes Save to Files as a cell. The corrected test passed. This does not demonstrate a completed Files save on the physical phone.
- Signed iPhone build and strict code-signature verification passed. USB installation succeeded, and an independent device app-list readback reported `com.dosetap.ios`, version **0.4.19**, bundle version **62**. Installation is separate from the owner export/open acceptance below.
- Native Excel for Mac opened the full synthetic 15-sheet workbook without repair, saved it, and reopened it. An independent readback retained all 15 named filter tables, frozen panes, the chart, dates and zero values. A smaller native fixture verified ascending numeric order **0, 2, 10**, whole-row identity preservation, filtering to one record and literal formula-like notes. Native review caught and corrected header-only empty-table repair and narrow date columns.
- A local owner-supplied finalized archive was projected outside the repository. Independent read-only reconciliation checked every original event ID, every date group, questionnaire identities/variants, review exclusions and all Overview summary rows. The source files were not modified. No personal records or workbook are included in this repository or tracker.
- An independent agent reviewed app integration, source identity eligibility and source-text escaping. Identified chart-gap and event-overlap issues were fixed and covered by regressions. Final source review of the cross-date guard and XML fast path reported no blocking findings; that review is not physical acceptance.
- Version/configuration, Plane workflow, SSOT, documentation, architecture, questionnaire-export fields, the Studio-export audit and whitespace guards passed. Existing protected files in the baseline checkout were preserved.

Detailed temporary evidence is in the isolated build/test result bundles (`/tmp/dosetap-excel-*.xcresult`) and local validation receipts. Durable semantics are in the [Excel contract](../SSOT/contracts/ExcelWorkbook.md), [approved design](../plans/2026-09-17-excel-workbook-export.md) and Plane workpad. Temporary paths may expire.

## Remaining acceptance

- Owner-observed export → Save to Files → open/reopen and sorting on the installed build, including the full current history and acceptable phone memory/time.
- Export retry after a real source/provider failure and Files destination behavior on the signed phone.
- VoiceOver, large text, iPad and secondary workbook viewers. Native Excel for Mac validation does not prove Numbers, mobile Excel or every Excel version.
- Provider grant/deny/no-data/parity, scheduled export, source completeness, source consistency under concurrent writes and all pre-existing DOSETAP-13 gates.
- Privacy/release acceptance for the sensitive workbook and original archive. Neither export is a tested full-app restore.

A combined workbook-plus-source package, dynamic cross-sheet selectors and new clinical collection are separate future work. DOSETAP-13 stays In Progress until its full acceptance is complete.
