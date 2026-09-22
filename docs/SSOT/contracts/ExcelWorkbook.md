# Excel review workbook

Status: Current implementation contract for DOSETAP-13. Build 62 adds the workbook; build 63 reduces packaging memory; build 64 repairs row contrast.

Settings adds **Export Excel Workbook** beside the existing Studio bundle export.
The export is a local, styled XLSX reporting snapshot built from the finalized
Studio JSON and inventory CSV from the same export operation. It never changes
clinical records, preferences, dose outcomes or alarms. The existing Studio ZIP
remains available and retains original source evidence. Neither format is a tested
full-app restore.

The workbook contains Overview, Nights, Night Review, Events, Pre-sleep, Morning,
Pain, Daytime, Sleep Measures, Sleep Intervals, Medications, Inventory, Source
Fields, Review Issues and Field Guide. Record sheets use named Excel tables with
column sorting/filtering, frozen headers, restrained navy/teal styling and typed
numbers/dates/durations. An empty table has one physically blank compatibility row
and an explicit **0 records** note; it contains no invented observation. Notes,
identifiers and unknown values are literal text, never executable formulas.

Build 64 gives every emitted cell an explicit nonzero style with an opaque
background, including notes, links, blank placeholders and both body-row
variants. Dark text uses pale blue-gray or pale aqua; the table's base style
and both row bands also supply explicit backgrounds. The implicit Normal style
stays unfilled and distinct from the body formats, so native Excel does not
coalesce the body format into default style zero. Sorting must not expose
dark text against an unfilled background. The existing direct
row fills travel with their records, so they may no longer alternate after a
sort. This contrast repair does not promise position-based rebanding. Values,
numeric formats, table ranges, links and workbook schema remain unchanged.

Original source records are keyed by table and ID; repeated representations are
not extra observations. Cross-date associations remain explicit and unresolved
date groups do not contribute combined dose/sleep/questionnaire metrics. Unknown
event vocabulary and source fields remain inspectable. Original payload variants,
null, empty text, zero, explicitly unsure, skipped and missing are distinct.
Source values exceeding a cell limit are split with numbered parts, never silently
truncated. Fields outside this archive are identified as unavailable.

Workbook schema 1 includes the SHA-256 of the supplied JSON bytes and UTF-8
inventory CSV, stable named-table grains, and original source keys. Source Fields
keeps every date-group association beside each original source record; it does
not add a separate association table. Snapshot-local field references identify
numbered value/path parts. Parsed JSON views are identified as projections.

Overview uses fixed 7/14/30-day and all-export ranges ending on the latest exported
treatment date. Provider means/medians have usable counts and separate exclusions.
Confirmed following-day answers remain separate from exported schedule estimates.
Table filters change that table; they do not redefine Overview's fixed snapshot.
Night Review is a sortable/filterable per-night review with supporting evidence.
Filter its Treatment date and Date group columns to review one group. Navigation
links go to table headers and remain valid after sorting; they do not silently
select a night or change another table's filters. The chart covers the latest
30 calendar days of the exported range, with absent measurements shown as gaps.

Use a column-header arrow to sort ascending/descending or filter. Use Excel's
multi-column Sort command for date plus event time or other combinations. Table
sorting moves the complete row. Numeric zero, durations and UTC timestamps remain
typed values; original IDs/codes stay text. Excel edits are workbook-only and
cannot change the app's records.

Dose time is not sleep onset. Asleep coverage across Dose 2 is not zero latency.
Unknown intervals are not invented asleep/awake time. Current exported intervals
have start/end/asleep only; detailed stage/device/sample provenance is not invented.
Actual asleep time after Dose 2 differs from elapsed time to final wake. WHOOP
aggregates cannot provide transition evidence. Primary episode totals are not
complete 24-hour sleep. Available numeric zero remains zero and unavailable
measurements never enter means as zero.

Night Review lists exported awake intervals intersecting a known Dose 2 timestamp
and the next exported asleep start. These are direct interval evidence, not the
accepted reviewed dose-to-sleep/return-to-sleep metrics: the archive does not yet
contain that complete reviewed projection, so the workbook does not substitute
a new calculator. Historical window classifications are not recomputed from
today's settings.

Sharing publishes only a completed XLSX. Concurrent export taps are guarded;
progress and retry retain the requested format. Failed work cleans temporary
artifacts and preserves all stored records. Native share/Excel/phone/provider,
accessibility, privacy and release acceptance remain separate gates.

The XLSX is compressed locally with standard ZIP DEFLATE when available. It has
no formulas, macros, remote links or refresh connections. The finalized Studio
JSON/CSV contract remains unchanged (export 2.8/schema 3). Scheduled export still
produces the existing ZIP. Workbook creation reuses the finalized archive; it
does not claim a new transaction across the exporter's existing source reads.

Build 63 packages one generated XML part at a time. The production encoder does
not retain every uncompressed sheet together. Decompressed XML, tables, styles,
record values and workbook schema stay unchanged; ZIP entry order may change.
All parts must succeed before an XLSX is returned for atomic publication. A late
part failure returns no archive. This reduces intermediate allocations, not the
memory required by the source snapshot, projected rows, largest part or final
compressed archive. Large-history phone performance remains a separate gate.
