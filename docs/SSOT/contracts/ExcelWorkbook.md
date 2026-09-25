# Excel review workbook

Status: Current implementation contract for DOSETAP-13. Build 62 adds the workbook; build 63 reduces packaging memory; build 64 repairs row contrast.

Settings adds **Export Excel Workbook** beside the existing Studio bundle export.
The export is a local, styled XLSX reporting snapshot built from the finalized
Studio JSON and inventory CSV from the same export operation. It never changes
clinical records, preferences, dose outcomes or alarms. The existing Studio ZIP
remains available and retains original source evidence. Neither format is a tested
full-app restore.

When Apple Health is disabled in DoseTap, export does not await a HealthKit
authorization refresh. Local record export remains independent of that disabled
provider; enabling Apple Health retains the existing permission/enrichment path.

Build 66 adds Dose Summary and Medication Log immediately after Overview. These
are read-only views of existing finalized source records. Dose Summary uses one
exported date group, excludes ambiguous identities, and reconciles selected dose
timestamps against canonical taken/skipped rows before calculating intervals.
A known source time remains usable without a summary timestamp; contradictory
source/summary times or taken/skip evidence make timing unavailable. All workbook
dose summaries share this result. Medication Log retains one source record and
payload variant per row, separates administrations from skip/correction/other
events, and exposes explicit amount, recording metadata, reason and reminder
choice without filling historical gaps. Recording delay uses explicit metadata
only, never SQL row creation. Correction-bearing records expose correction time
separately and do not claim initial recording delay. Removal evidence prevents
stale summary-only timestamps from resurrecting a removed administration. Local display uses the export timezone and includes
the UTC offset; UTC instants remain typed. Missing historical windows and reviewed
sleep latency stay unavailable. No medication/schema writes or archive changes.

The workbook contains Overview, Dose Summary, Medication Log, Nights, Night Review, Events, Pre-sleep, Morning,
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

Workbook schema 2 adds the two medication views and shared dose reconciliation;
existing source table names and payloads are preserved. Schema 1 introduced the SHA-256 of the supplied JSON bytes and UTF-8
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
Build 66 retained export 2.8/schema 3. Build 67 advances the contract as described below. Scheduled export still
produces the existing ZIP. Workbook creation reuses the finalized archive; it
does not claim a new transaction across the exporter's existing source reads.

Build 63 packages one generated XML part at a time. The production encoder does
not retain every uncompressed sheet together. Decompressed XML, tables, styles,
record values and workbook schema stay unchanged; ZIP entry order may change.
All parts must succeed before an XLSX is returned for atomic publication. A late
part failure returns no archive. This reduces intermediate allocations, not the
memory required by the source snapshot, projected rows, largest part or final
compressed archive. Large-history phone performance remains a separate gate.

## Build 67 timing review and Studio CSV

Workbook schema 3 adds Dose interval eligibility to Dose Summary and Nights,
and an interval-specific Review Issues reason. Nonpositive selected differences
are preserved in source timestamps and JSON rawIntervalSeconds, but ordinary
Dose interval cells remain blank pending review. Positive subsecond spacing
remains eligible before display rounding. Identity conflicts, missing timestamps
and explicit skips retain separate reasons; sleep eligibility is independent.

Studio export 2.9/schema 4 retains dateGroups and original records. Each group
adds doseTimingReview version 1: status (available, missing, needs_review), reason,
optional rawIntervalSeconds, and intervalSeconds only when eligible. Source
selection is shared with workbook reconciliation; original values are not repaired.

sessions.csv retains its first nine column positions. started_utc and ended_utc
are legacy names for selected Dose 1/2 occurrences. window_target_min is blank
because no historical plan target is established. window_actual_min retains
legacy whole-minute presentation only for eligible pairs. adherence_flag now
uses taken, explicitly_skipped, missing or needs_review, never a current-window
classification. Appended fields: session_date, session_id, actual_interval_seconds,
interval_status, interval_review_reason, historical_window_status,
dose2_reminder_enabled, reminder_interval_minutes. Historical window is unavailable;
reminder fields require explicit Dose 1 metadata. Rows require resolved identity
and a usable Dose 1 occurrence; other source records remain in JSON/events.csv.
Updated Studio preserves blank targets as nil and uses the exported treatment
date for joins. Schema 1–3 remain readable; older Studio rejects schema 4. This
is a reporting compatibility change, not a database migration or a full-export
transaction guarantee. Scheduled and manual archives share the same writer.

Strict schema-4 archive validation requires versioned timing reviews and the new
CSV columns, checks per-date eligibility/value parity and rejects current-target
substitution or missing eligible pairs. CSV omission of a date without a selected
Dose 1 is valid; raw-only evidence remains in JSON.
