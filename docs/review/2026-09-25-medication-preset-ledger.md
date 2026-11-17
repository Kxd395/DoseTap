# Independent medication preset ledger and export

Date: 2026-09-25
Plane: DOSETAP-74, slice B2
Candidate: 0.4.19 (69)
Integration baseline: main 61a2801, PR58; all three post-merge workflows verified passed.

## Delivered boundary

B2 persists the B1 immutable oral-solid prescription-label revisions and explicitly
confirmed administration snapshots through SessionRepository → EventStorage → SQLite.
The ledger does not require a nighttime session. Unknown occurrence has no invented
date or timezone. It does not mirror the legacy whole-mg medication table, create
Dose 1/2 events, alter reminders, or rewrite older records.

A single write transaction checks stable IDs, predecessor ownership, competing
revision branches and embedded revision equality. Identical retries are no-ops;
changed content under an existing ID fails. Insert/commit failures roll back.
Strict export reads validate both collections in one read transaction and compare
indexed fields with canonical payloads. This is not a transaction guarantee for
all other existing export collections.

Studio schema 5/export 3.0 includes the complete independent ledger even with zero
nights. Original JSON strings preserve Decimal amounts through preparation,
source inspection and Studio import/re-export. Workbook schema 4 adds Medication
Presets and Confirmed Medications (19 sheets). Legacy bundles keep 17 sheets.
Amounts are exact text with lexical sorting; timestamps in Excel's supported
range are typed dates. Known dates outside that range are explicitly marked,
while unknown occurrence remains blank. Source Fields retains the full evidence.
Neither new table contributes to nighttime dose-spacing or sleep summaries.
Existing Studio clinical reports remain session-based and do not yet analyze
these independent administrations.

Clear All removes administrations before revisions. Night reset/deletion and
legacy age-based pruning preserve the ledger. The retention policy and audited
correction/reversal controls must be exposed before preset capture UI ships.
No CloudKit staging sync or preset save/log UI is introduced in B2.

## Validation evidence

- Core: 780 XCTest plus 43 Swift Testing cases passed; includes exact Decimal,
  unknown-time, malformed-schema, zero-night and Excel date-range regressions.
- Native iOS: 150 tests passed across medication capture, ledger storage, session
  repository, data integrity, storage integration, source fidelity and Excel export.
  Both manual/local writers export independent records with zero nights. Tests
  retain a 29-place decimal, survive database reopen, reject same-ID changed
  actuals, roll back injected failures, and preserve truly old ledger records
  through night-history cleanup.
- Studio: 91 tests, 3 skipped, 0 failures with the synthetic native schema-5
  raw-only archive supplied. Typed import/re-export retains snapshots; conflicted
  dates stay out of combined analytics.
- Archive audit: 201 cases plus ZIP passed. This is structural/identity evidence;
  Swift's checked Decimal arithmetic is not duplicated by the Python audit.
- Native desktop Excel: a synthetic app-export workbook opened with 19 sheets.
  Both new sheets were visually inspected. Sorting Recorded (UTC) oldest first
  moved complete administration rows, retaining exact amount text, unknown versus
  approximate timing and IDs. The sorted disposable copy saved and reopened with its row order and exact
  values preserved.
  This does not establish phone viewer or large-history performance acceptance.
- Independent read-only reviews found no remaining storage/export blocker. Review
  gaps in administration conflict and historical-retention fixtures were fixed.

Local evidence logs: /tmp/dosetap-b2-final-core.log,
/tmp/dosetap-b2-native-final.log, /tmp/dosetap-b2-studio-fixture.log,
/tmp/dosetap-ledger-audit.log. Native workbook originated in the retained
ExcelExportTests attachment. Temporary artifacts may expire; this record is durable.
Final guard, PR/main integration and exact Plane readback are recorded in the
DOSETAP-74 workpad rather than inferred from this candidate record.

## Remaining acceptance and next slice

B3 should add reviewed preset Settings/quick-log controls, last-log receipts,
explicit amount/time confirmation, duplicate review, visible retention policy and
audited correction/reversal. Oral solids and taken outcomes are the current
contract; liquids, other units, broader outcomes and opt-in groups remain later.
Signed-phone install/export, owner-observed capture/reopen, accessibility, privacy
and release acceptance remain open. No phone installation was performed for B2.
DOSETAP-58 sleepiness/day review/nap work and ESS licensing remain separate.
