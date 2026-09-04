# Dose State Persistence Contract

Status: Current normative persistence contract
Last verified: 2026-09-04

This is the authoritative contract for nightly dose persistence. It exists to prevent split-brain state between `current_session` and `dose_events`.

## Tables

- `dose_events` is the canonical event history for dose actions.
- `current_session` is the active-session snapshot used for fast UI state.
- These tables must agree for the active session after every dose mutation.

## Allowed Write Boundary

Live dose commands must enter through `DoseActionCoordinator`, then mutate through `SessionRepository`.

Allowed production mutation routes:

- `DoseActionCoordinator` -> `SessionRepository.setDose1Time`
- `DoseActionCoordinator` -> `SessionRepository.setDose2Time`
- `DoseActionCoordinator` -> `SessionRepository.skipDose2`
- `DoseActionCoordinator` -> `SessionRepository.incrementSnoozeIfActive`
- App undo bridges -> `SessionRepository.clearDose1`, `clearDose2`, `clearSkip`
- History time edits -> `SessionRepository.updateDose1Time`, `updateDose2Time`
- Morning reconciliation -> `SessionRepository.reconcileDose1`, `reconcileDose2`, `reconcileDose2Skipped`

Storage implementations live in `ios/DoseTap/Storage/`. UI, deep links, Flic, widgets, and other app surfaces must not call `EventStorage.saveDose1`, `saveDose2`, `saveDoseSkipped`, `saveSnooze`, `saveDoseEvent`, `insertDoseEvent`, `upsertDoseEvent`, `clearDose1`, `clearDose2`, `clearSkip`, `updateDose1Time`, or `updateDose2Time` directly.

Deep-link `log` routes must never persist dose vocabulary into `sleep_events`. Dose names such as `dose1`, `dose2`, `extra_dose`, `dose2_skipped`, and `snooze` must be rejected by `log` and handled only by the dose action routes.

## Required Invariants

For the active session:

- A `dose1` event requires `current_session.dose1_time`, and `current_session.dose1_time` requires a `dose1` event.
- A `dose2` event requires `current_session.dose2_time`, and `current_session.dose2_time` requires a `dose2` event.
- `dose1` and `dose2` timestamps must match between the event row and snapshot row.
- `dose2_skipped` must match `current_session.dose2_skipped`.
- `dose2_time` and `dose2_skipped` must not both be set.
- Elapsed time, notification delivery or dismissal, app foregrounding, and session rollover must not create a `dose2`, `dose2_skipped`, taken, missed, or skipped outcome.
- The end of the configured timing window is calculated presentation state only. It must leave the medication outcome unresolved until an explicit user command commits.
- A prospective Dose 2 command after the configured window must fail without writing. A real occurrence that already happened remains recordable through the retrospective command with its actual timestamp.
- An outside-window retrospective occurrence requires an explicit warning confirmation. Its event metadata must distinguish `entry_mode = retrospective`, the later `recorded_at_utc`, and the initiating `surface`; the event timestamp remains the actual occurrence time.
- If a retrospective occurrence replaces a skip created by the removed legacy auto-expiry path, the same transaction clears the legacy `incomplete_slept_through` terminal marker. It does not rewrite unrelated historical outcomes or diagnostics.
- `dose2` must not exist without `dose1`.
- `extra_dose` must not exist before canonical `dose2`.
- `snooze` must not exist without `dose1`.
- `current_session.snooze_count` must not be greater than zero without at least one matching `snooze` event.
- A `snooze` event must not exist while `current_session.snooze_count` is zero.
- Active dose event types are exactly `dose1`, `dose2`, `extra_dose`, `dose2_skipped`, and `snooze`.
- Storage code must write these names through `CanonicalDoseEventType`; legacy aliases may be read for historical reconstruction, but active-session aliases are invariant violations.

## Fail-Closed Mutation Rules

- Every live dose, skip, snooze, undo, time-edit, and morning-reconciliation mutation returns `MedicationMutationResult`. Callers may acknowledge an action only for `.committed`; `.failed` carries a stable operation, failure code, transaction stage, optional SQLite code, retry classification, and safe user message.
- The event-ledger change and matching `current_session` snapshot change must run inside one `BEGIN IMMEDIATE` transaction. Delete/replace operations, including a repeated Dose 1, must roll back to the last acknowledged sequence if insert, update, or commit fails.
- `SessionRepository` must not publish in-memory medication state, emit success diagnostics, cancel alarms, register undo, refresh widgets, play a success haptic/sound, or call a remote dosing service until the local transaction commits.
- A storage failure must remain visible through `SessionRepository.lastMedicationMutationError`. User-facing surfaces must show retry guidance and must not dismiss a morning reconciliation form as complete after a failed dose write.
- `SessionRepository.setDose2Time` must return without writing if there is no open active session with canonical Dose 1.
- `DoseActionCoordinator.takeDose2` must not use an override to turn `closed` or an existing skipped outcome into a prospective medication action. A skipped outcome may be corrected only by a confirmed retrospective occurrence.
- A repeated ordinary Dose 2 submission must fail at the repository and transactional storage boundaries once canonical Dose 2 exists. Only a command explicitly confirmed as an extra dose may create `extra_dose`; rapid taps and interleaved surfaces must not promote an ordinary Dose 2 command into an extra dose.
- `SessionRepository.incrementSnoozeMutationIfActive` must fail without writing if there is no open active session with Dose 1, if Dose 2 is already taken, if Dose 2 is skipped, or if schedule rollover closed the session during preflight. The Boolean compatibility wrapper is not an acknowledgement boundary.
- `DoseActionCoordinator.snooze` must commit repository snooze state before rescheduling alarm state. If alarm rescheduling fails, it must roll back the latest snooze event and snapshot count.
- `SessionRepository.clearDose1` must clear the full dependent dose sequence for that session: Dose 1, Dose 2, extra dose, Dose 2 skipped, and snooze state.
- Morning reconciliation replaces the selected canonical outcome and active matching snapshot atomically. Historical reconciliation may update that session's ledger but must never replace a different active snapshot.

## Failure Classification

The persistence boundary distinguishes database unavailable/open failure, full disk, corruption, constraints, busy/locked storage, I/O failure, statement failure, transaction failure, stale-state precondition, and unknown failure. Transaction stages are `open`, `preflight`, `begin`, `delete`, `insert`, `update`, `commit`, and `rollback`.

Corruption, constraint, and domain-precondition failures are not blind-retry conditions. Temporary availability, full-disk, busy, I/O, statement, transaction, and unknown failures provide retry guidance, while still requiring the user to confirm that the medication state visibly appears before relying on it.

## Time Source Contract

- `SessionRepository.currentContext` must derive dose-window phase from the repository `clock` dependency, not a process-global `Date()` source.
- Session boundary evaluation, active-session writes, and UI phase calculation must share the same time source.
- Tests that inject a repository clock must build dose timestamps from that same clock.

## Recovery

On reload, recoverable active dose-state violations must not crash app launch. The repository must close the active snapshot with terminal state `invalid_dose_state`, preserve evidence rows for audit, log the invariant violation, and return the UI to no active session.

A failed replacement must survive restart as the last previously acknowledged event/snapshot pair. A process restart is not allowed to expose a deleted Dose 1, a newly inserted event without its snapshot, or a snapshot update whose event insert did not commit.

## Enforcement

- Runtime checker: `EventStorage.validateActiveDoseStateInvariant()`.
- Repository hook: `SessionRepository.validateDoseStateInvariant(reason:)` logs and debug-asserts after active dose mutations.
- Fault suite: `MedicationMutationTransactionTests` injects open, preflight, begin/corruption, insert/full-disk, update/I/O, commit, and rollback failures; it also verifies replacement rollback, restart recovery, reconciliation isolation, retry UI results, and absence of success side effects.
- CI guard: `tools/check_dose_state_writes.sh` blocks new direct write paths outside the allowed boundary.

Any future sync implementation, CloudKit adapter, import path, or widget action must use this same boundary or add a reviewed reconciliation layer with tests.

## Reviewed corrections and session identity

Medication identity is the session UUID. A date is a grouping key; a UUID-scoped read or write must not include another UUID merely because its date matches. Legacy rows without a UUID (NULL or the original date string used as the old identity) may match their original session date. Another UUID must never match by date.

Replacing a dose outcome must preserve every replaced row (ID, type, occurrence timestamp, session identity, raw metadata, and creation time) in the replacement event's `correction.previous_events` metadata, with `corrected_at_utc` and source. History capture and replacement commit or roll back together. Existing nested correction history is retained verbatim. Diagnostic logs are supplemental evidence, not the correction ledger.

History can resolve a selected session with Dose 1 and no Dose 2 without reopening it or touching another active session or its alarms. The command rechecks Dose 1 and missing Dose 2 under the write transaction, rejects future/reversed occurrences, and requires explicit confirmation. A second submission fails rather than replacing the first committed occurrence. Missing Dose 1 requires its own reviewed correction and must not be guessed from the session date.
