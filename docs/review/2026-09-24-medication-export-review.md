# Medication storage and export review

Date: 2026-09-24
Tracker: DOSETAP-73 (In Progress)
Source baseline: main `94a7989a349156eeb0714148674a7cc56d87fa79`, app 0.4.19 (65)
Scope: read-only source and supplied build-64 workbook review; proposed design.
No app behavior, clinical record, workbook or database was changed by this review.

## Finding

The workbook preserves useful dose evidence but makes the reader assemble it
across several sheets. A sheet named Medications excludes canonical Dose 1 and
Dose 2 events. Those are in Events and Nights. Dose metadata is embedded in
Details and Source Fields rather than presented as medication columns.

Independent arithmetic against every populated interval in the supplied workbook
matched the difference between its two absolute dose timestamps. This verifies
that artifact's subtraction, not the truth of reported administration times or
all phone storage invariants. Private counts and source-file identity remain in
the local review evidence, outside Git and Plane.

## Source-to-export ownership

| Layer | Current responsibility | Review implication |
| --- | --- | --- |
| `DoseActionCoordinator` and `SessionRepository` | Explicit live administration and retrospective review | Preserve occurrence versus recording and confirmation boundaries |
| `EventStorage+Dose.swift` | Canonical `dose_events`, related state updates and transaction/rollback handling | Canonical dose ledger remains authoritative; do not copy doses into general medication storage to populate a sheet |
| `EventStorage+EventStore.swift` | Reads canonical dose rows from the same `dose_events` table | This inspected path does not demonstrate a second independently writable dose database |
| `medication_events` | Separately logged medicines, amount/unit/formulation and occurrence | Distinct record type, not a substitute canonical Dose 1/Dose 2 ledger |
| `EventStorage+Exports.swift` | Checked original event reads with IDs, stored timestamps and metadata | Keep original evidence and explicit source identity |
| `SettingsStudioExport.swift` | Finalized JSON/CSV export, date identity exclusions, selected dose timestamps and enrichment | Existing export is multiple source reads, not proof of one database-wide snapshot transaction |
| `SettingsExcelExport.swift` | Builds XLSX from the finalized JSON and inventory CSV | No second database read or clinical write is needed to improve presentation |
| `StudioWorkbookDetails/Summaries/NightReview.swift` | Workbook projections | This is the first bounded implementation surface |

Do not call the two clinical tables “split brain” merely because the user-facing
sheet organization separates them. A complete live-phone invariant audit was not
performed here. In particular, the dose summary read has a `current_session` fast
path and historical ledger fallback; future regression tests must compare the
selected summary with the effective canonical rows rather than assume parity.

## Confirmed gaps

1. **Medication navigation:** Medications means separately logged medicines. It
   can be empty while the workbook contains many canonical dose events. Its
   dynamic columns can also disappear when it has no records.
2. **Clinical facts are not first:** Events begins with seven identity/provenance
   columns. Dose amounts, reasons, entry mode, explicit recording timestamps and
   reminder choices are embedded in JSON details. Provenance is necessary but
   should follow the everyday review columns.
3. **Times are technically precise but cumbersome:** typed UTC timestamps appear
   before local ISO text. Local time uses the export timezone, not a guaranteed
   historical location. Use readable local date/time with a visible timezone
   basis, while retaining absolute UTC and original strings for ingestion.
4. **Historical window unavailable:** Nights deliberately says that the historical
   configured window was not exported. Do not replace this with classifications
   calculated from today's settings. Existing `is_early`/`is_late` metadata can be
   exposed as recorded flags, with unknown kept distinct from false.
5. **Recording-time coverage is incomplete:** explicit `recorded_at_utc` exists
   only on some paths/records. SQL `created_at` is stored row creation, not a
   universally trustworthy capture timestamp. Corrections can preserve a row's
   creation time while changing its occurrence. A logging delay requires explicit
   compatible recording evidence; do not manufacture it from row creation.
6. **Amount and regimen coverage is incomplete:** `amount_mg` is optional metadata
   on canonical doses; current live Dose 1/2 writers do not consistently supply
   amount, medication identity, formulation, precision or a historical window
   snapshot. General medication rows have their own amount/unit fields. Never
   fill historical gaps from today's medication settings or assume standard doses.
7. **Dose/sleep export parity:** Night Review explicitly leaves reviewed Dose 1
   onset and Dose 2 return-to-sleep metrics unavailable. It shows raw awake-interval
   overlap evidence instead. Exporting the existing reviewed app result needs a
   versioned result/evidence contract; another spreadsheet calculator is not a fix.
8. **Summary consistency needs explicit regression coverage:** workbook outcome
   classification and interval selection are separate helpers. Test contradictions
   between selected summary timestamps, canonical skip/taken rows, duplicate rows,
   corrections and unknown times before introducing a new medication summary.

## Proposed reader-facing layout

Keep the existing source sheets and names during the first additive rollout so
current consumers continue to work. Add two focused sheets immediately after
Overview, with fixed headers even when empty:

| Sheet | Row grain | First visible columns |
| --- | --- | --- |
| Dose Summary | One resolved treatment session; unresolved groups remain visibly excluded | Treatment date, Dose 1 outcome/time, Dose 2 outcome/time, interval, timing status, review reason |
| Medication Log | One canonical administration/outcome or separately logged medication record | Treatment date, medicine as recorded, dose label, outcome, amount, unit, occurred local date/time, recorded local date/time |

Dose Summary detail columns: Dose 1/2 amount and unit when recorded, timing basis,
recorded window minimum/maximum/version when available, reminder enabled/target,
recording source, explicit logging delay, extra-dose count and relevant review
flags. Keep reminder interval separate from medication eligibility. “No alarm,”
unknown alarm setting and no alarm evidence are different states.

Medication Log detail columns: occurrence precision, entry mode, recording-time
basis, source/surface, correction or superseded state, reason, notes, session ID,
source table/record ID, UTC instants and original source references. Distinguish
canonical doses, other medicines and audit-only correction rows. Audit rows must
not be counted as additional administrations. Unknown drug identity remains
“Not recorded”; “Dose 1” is a role, not a medication name.

Sort the summary newest treatment date first. Within a selected session, order
events by occurrence with a stable source-ID tie break; unknown times remain
explicit. Use real numeric duration cells displayed as hours/minutes, numeric
amounts plus units, fixed table headers, frozen date/medication columns and full-row
sort/filter. Support date, medicine, dose, outcome, entry mode and needs-review
filters. Put technical IDs to the right. Preserve the build-64 opaque styles and
native Excel sort/save/reopen contrast fix. Do not use green to imply a dose was
medically safe. Workbook filters still affect their own table only.

## Implementation sequence and acceptance

1. **Presentation and reconciliation:** build the two additive projections from
   existing finalized sources. Extract only explicitly recorded metadata. Give
   absent values specific reasons. Add summary-to-ledger consistency checks and
   retain unresolved raw evidence. No SQLite migration or medication write.
2. **Prospective data contract:** define medication/regimen identity, amount/unit,
   actual time/precision, explicit recording time/source, session window snapshot
   and reminder selection. Apply consistently to live, retrospective and corrected
   paths. Define how edits retain original recording history. Do not backfill.
3. **Reviewed dose/sleep results:** export the existing versioned result, status,
   missingness/conflicts, coverage and evidence references under DOSETAP-57 and
   provider/privacy review. Reconcile iPhone, Studio and Excel meanings.

Required cases: midnight and DST crossings; fractional minute intervals; explicit
skip versus absent outcome; taken time unknown; Dose 2 without Dose 1; duplicate or
conflicting rows; correction/removal and extra doses; retrospective recording;
no-alarm choice; absent amount/window; identical source represented twice; empty
tables; source preservation; native Excel sort/filter/save/reopen. Show neither an
interval for a confirmed skip nor a zero for missing timing. Keep approximate
times spanning a window boundary timing-uncertain.

This owner-reported export concern takes priority over adding another dashboard
summary. It is a narrower next slice than redesigning medication storage at once.

## Review validation and gates

- Supplied workbook was inspected without editing; source hash unchanged.
- Every populated interval reconciled to the workbook's absolute dose timestamps.
- Existing `StudioWorkbookProjectionTests`: 15 passed. These confirm current
  behavior; they are not tests of the proposed new sheets or prospective fields.
- Required Plane workflow, documentation and whitespace checks are recorded in
  the workpad with the final review commit.
- DOSETAP-73 remains In Progress: new sheets, prospective data contract, native
  viewer/phone usability and owner acceptance are not delivered by this review.
- No new build number. App remains 0.4.19 (65). Phone source completeness,
  transaction-wide export consistency, privacy and release acceptance remain
  separate from workbook arithmetic and source inspection.
