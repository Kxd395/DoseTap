# Export timing review — build 67

DOSETAP-73 remains In Progress. This bounded follow-up to build 66 addresses independently verified export correctness findings; it does not reconcile or rewrite clinical records.

## Delivered behavior

- Zero and reversed recorded dose spacing retains both occurrences and a raw signed difference, with `nonpositive_dose_interval` review status. Ordinary spacing metrics exclude it; independent sleep measurements remain available.
- Studio JSON, sessions CSV and Excel use the same reporting selection. CSV no longer substitutes current settings for historical target/window, labels confirmed skips explicitly, and includes treatment-date/session identifiers and reminder evidence separately.
- Export 2.9/schema 4 carries `doseTimingReview`; matching Studio retains absent targets and reviewed eligibility through dashboard and timing-comparison consumers. Earlier schema-limited Studio builds reject schema 4. Older archives remain readable.
- Workbook schema 3 adds interval eligibility to Dose Summary and Nights, and counts record-review issues separately from unavailable provider measurements. Existing source details, timestamps and correction evidence remain intact.
- App/staging Debug and Release are 0.4.19 (67). No SQL migration or medication-state write.

## Verification

- Core build and 760 XCTest plus 43 Swift Testing cases passed.
- Studio: 89 tests, four fixture-dependent skips, no failures. Export/import conflict fixture retains all events and excludes the pair from average, anchored, on-time and late spacing paths.
- Six native iOS export/source-snapshot tests passed, including JSON/CSV identity and interval parity, unchanged SQLite records, finalized archive preservation and generated XLSX.
- Native Settings → Excel export share-sheet journey passed (one UI test).
- Unsigned simulator build and signed device build passed. App version checks passed for all four app/staging configurations.
- Studio archive guard: 161 cases plus ZIP input passed. SSOT, documentation, Plane workflow and whitespace checks passed.
- Independent source review found three consumer/counting gaps; regressions and corrections addressed them. Final read-only review found no remaining blocker in ordinary spacing eligibility.

## Remaining gates and next work

Signed build 67 installed after an initial connection reset; independent device inventory confirmed 0.4.19 (67). Phone export acceptance, native viewer review of the new eligibility columns, accessibility, privacy and release acceptance remain separate. Installing a build does not close these gates. Integration and phone outcomes are recorded in the DOSETAP-73 workpad.

Next bounded priorities: fresh-answer provenance for morning ratings and separating questionnaire completion from confirmed lights-out. Medication identity/actual amount confirmation, historical regimen snapshots, compact review exports and schedule-context reconciliation remain follow-on work. Reuse the existing guarded dose/sleep calculator; do not infer actual dose time from recording time or repair private historical records automatically.

Private source exports and the detailed owner-data verification remain outside Git and Plane. This record contains implementation evidence only.
