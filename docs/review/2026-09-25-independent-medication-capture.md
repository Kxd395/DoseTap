# Independent medication capture — build 68

Date: 2026-09-25
Version: 0.4.19 (68)
Plane: DOSETAP-74, In Progress
Scope: Slice A of the [daytime treatment roadmap](../plans/2026-09-25-daytime-treatment-roadmap.md).

## Result and boundaries

Tonight has a direct **Log Medication** action, including when no night has
started or the previous night is awaiting review. This is reported general
medication capture, separate from Dose 1/2 administration and reminder actions.
The medications enabled in Settings now determine the available picker choices.

Amount and time start unanswered for every selected medication. **Now** captures
the occurrence when Add is pressed; **Earlier** requires review of its date/time.
Save confirms the displayed pending list. A failed write keeps the unsaved
entries and their original times. Successfully saved entries remain in a receipt
until Done. A saved prefix is not submitted again when retrying a partial batch.

The existing whole-milligram catalog is the limit of this slice. It does not
claim prescription verification, custom concentrations/components, versioned
presets, unknown/approximate occurrence capture, audited Undo/Edit, group presets,
or a complete independent daytime diary. Unused default-amount/formulation
controls were removed from Settings; their stored preferences were not erased.

## Persistence and export

Views still write through SessionRepository to EventStorage and SQLite.
General medication records use medication_events; they do not create dose_events.
New records retain a NULL session_id, even across startup. The obsolete startup
date-link backfill was removed; historical non-NULL links are left untouched.
session_date remains a legacy grouping field, not evidence of a sleep relationship.
Deleting/resetting a night preserves independent NULL-linked medication rows and
does not enqueue medication tombstones for them. Synced night deletion uses the
same selection. Explicit Clear All Data still removes independent medication data.

Each pending entry has a stable command ID. A transaction checks that ID, the
current duplicate evidence and the insert. Repeating the same command is
idempotent; different details under an existing ID fail rather than replacing it.
Duplicate review crosses date boundaries and includes actual amount/time. Its
consent token covers complete stored rows, so a new, changed or removed matching
record requires another review. Malformed history fails closed.

occurred-at is taken_at_utc; created_at is explicitly recorded at first successful
capture. Formulation, amount/unit, offset and original identity flow through the
existing source export. No SQL schema migration or new export format is required.
Historical unknowns are not filled from current settings.

## Validation record

- SwiftPM: 760 XCTest and 43 Swift Testing cases passed.
- Native iOS: 142 tests passed across MedicationCapture, SessionRepository,
  DataIntegrity, EventStorageIntegration, ExportRecordFidelity and ExcelExport.
  These cover independent save/reopen,
  active nighttime state preservation, insert/commit failure, stable retry,
  cross-date duplicate evidence, changed consent, invalid inputs, night deletion
  and tombstone isolation, and exports.
- Generic unsigned simulator build passed; all four relevant configurations
  report 0.4.19 (68).
- Two native UI journeys passed, covering explicit amount/time capture and batch
  duplicate/failure/retry. Final result after deletion fix: 2 tests, zero failures
  at 11:48 EDT. One launch-only attempt reported simulator Busy; retry after the
  existing simulator booted completed successfully. No runtime download needed.
  Initial attempts exposed a transient-toast assertion and an inherited
  accessibility identifier; neither is accepted as a passing run. The persistent
  receipt count is the final assertion target.
- Architecture, SSOT, documentation lint, Plane workflow and whitespace checks
  passed before closeout; the workpad records final integration evidence.
- Independent code review checked transaction identity, duplicate evidence,
  daytime/nighttime isolation and the deferred scope boundaries.
  The hosted review subsequently found the legacy date-based night deletion
  cascade. Its fix shares the NULL-link exclusion between deletion and tombstone
  selection, with local/reset/sync and export preservation regressions.

No real patient records or private attachments were copied into the repository.
Native screenshots use synthetic simulator records. Temporary logs/results live
under /tmp/dosetap68-*; this record and the Plane workpad are durable evidence.

## Open acceptance and next work

Build 68 has not been installed or accepted on the owner's phone by this record.
Signed-device save/reopen/export, VoiceOver/largest-text review and privacy/release
acceptance remain open. The existing build 67 acceptance is not transferable.

Next: DOSETAP-74 slice B, immutable prescription presets and administration
snapshots with reviewed correction/reversal. DOSETAP-58 remains Todo for separate
momentary sleepiness, day review, naps/rest and the licensed ESS gate. DOSETAP-59
remains Todo for physician reports with calendar-month and visit-based coverage.
The roadmap includes both supplied physician-review documents, with v2 governing
the expanded nap and reporting requirements.
