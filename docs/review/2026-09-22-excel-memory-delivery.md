# Excel export packaging memory

Date: September 22, 2026
Plane: DOSETAP-13, In Progress
App: 0.4.19 (63)
Baseline: GitHub main `9f9ff0c`, build 62
Scope: Workbook packaging only; source projection, contents and schema unchanged.

## Change

The production encoder now generates and compresses one XML part before asking
for the next. Previously it held every uncompressed workbook part in a dictionary
before compression. The inspection/test adapter still collects parts when asked;
both paths use the same XML generation code. Declaration and worksheet-ending
concatenations no longer create extra full-size strings.

The archive is returned only after all parts and the central directory succeed.
The app still writes the completed result atomically. A later part failure returns
no partial archive and does not change clinical records. The ZIP member order
changes deterministically; all decompressed contents remain identical. There is
no workbook schema, table, value, formatting, calculation or UI change.

## Measured evidence

Both revisions were compiled with the same local `swiftc -O` toolchain and run on
the same Mac. Peak resident memory is whole CLI process memory, including source
projection where applicable. These single-run comparisons are not phone memory
measurements or a guaranteed runtime improvement.

| Input | Build 62 peak RSS | Build 63 peak RSS | Reduction | Elapsed, before / after | Identical parts |
| --- | ---: | ---: | ---: | ---: | ---: |
| Synthetic six-sheet, 240,000-row fixture | 499,499,008 bytes | 394,936,320 bytes | 20.9% | 26.10 / 25.81 seconds | 24/24 |
| Previously supplied finalized archive, kept private | 860,553,216 bytes | 695,058,432 bytes | 19.2% | 15.19 / 14.72 seconds | 54/54 |

Independent Python ZIP readback verified CRCs, member sets and byte-for-byte
decompressed contents. The private archive produced the same 10,453,995-byte
workbook size. Original source files stayed outside the repository and tracker.
XML identity includes all tables, styles, chart, values, relationships and panes;
native Excel visual review was not repeated for unchanged views/dependencies.

## Validation

- Core build and all 746 XCTest plus 43 Swift Testing cases passed.
- The 21 writer cases include a 12-sheet archive, central-directory offsets,
  CRCs, local/central sizes, deterministic repeats, literal values, empty tables,
  chart relationships, duplicate names, ZIP count/name limits and late failures.
  New producer tests failed to compile against the original API before the change.
- Six native iOS integration tests passed: ExcelExportTests and
  ExportSourceSnapshotTests, on the existing iOS 26.5 export simulator.
- The native repeated-export UI journey passed on retry. Its first attempt failed
  to launch the simulator test runner before executing any test; after simulator
  boot completed, the unchanged test passed once with zero failures. It verified
  the completed share item, dismissal and another export, not a physical Files save.
- Unsigned simulator and signed device builds, strict code-signature verification
  and all four version configurations passed. USB installation succeeded;
  independent device app metadata confirmed 0.4.19 (63). No uninstall was used.
- Independent source review found no blockers. Plane workflow (15 tests,
  80 assertions), SSOT, docs, architecture and whitespace checks passed. All 13
  protected baseline file hashes remained unchanged.
- PR checks and final integration are recorded in Plane after they complete;
  local results are not substituted for hosted CI results.

## Reproduce without personal data

From the selected checkout, compile the same benchmark driver against its Core
sources. For the old revision, use this driver with the build-62 Core files.

```bash
swiftc -O ios/Core/ExcelWorkbook*.swift ios/Core/StudioWorkbook*.swift \
  tools/bench_excel_workbook.swift -o /tmp/dosetap-workbook-benchmark
/usr/bin/time -l /tmp/dosetap-workbook-benchmark /tmp/dosetap-candidate.xlsx
python3 tools/check_excel_workbook_parity.py \
  /tmp/dosetap-baseline.xlsx /tmp/dosetap-candidate.xlsx
```

An optional second benchmark argument accepts a local finalized Studio directory.
Keep personal inputs and generated workbooks outside Git and shared CI artifacts.
Package parity is a preservation check, not validation of the source records or
clinical interpretation.

## Acceptance boundaries

The owner confirmed build 62 export, Save to Files and opening on September 18;
that acceptance remains recorded and does not need repeating for build 62.
Build 63 installation is verified; owner workflow and measured performance
remain separate evidence. Workbook rows,
the largest generated XML part and compressed archive still occupy memory; this
is not a fully streaming source/row/file exporter. Larger-history phone memory,
real failure/retry, phone sorting/save-reopen, additional viewers, accessibility,
provider, privacy, full-backup and release gates remain open in DOSETAP-13.
