# Dose State Persistence Contract

Last updated: 2026-07-09

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
- `dose2` must not exist without `dose1`.
- `extra_dose` must not exist before canonical `dose2`.
- `snooze` must not exist without `dose1`.
- `current_session.snooze_count` must not be greater than zero without at least one matching `snooze` event.
- A `snooze` event must not exist while `current_session.snooze_count` is zero.
- Active dose event types are exactly `dose1`, `dose2`, `extra_dose`, `dose2_skipped`, and `snooze`.
- Storage code must write these names through `CanonicalDoseEventType`; legacy aliases may be read for historical reconstruction, but active-session aliases are invariant violations.

## Fail-Closed Mutation Rules

- `SessionRepository.setDose2Time` must return without writing if there is no open active session with canonical Dose 1.
- `SessionRepository.setDose2Time` must acknowledge storage success before mutating published state or reporting success to the user.
- Confirmed Dose 2 recovery after a skip must atomically insert Dose 2, clear the matching skip event and snapshot flag, and preserve the invariant that `dose2_time` and `dose2_skipped` cannot coexist.
- Auto-expiry after the Dose 2 alarm grace period may mark Dose 2 skipped, but must not close the session or write a terminal session state.
- `SessionRepository.incrementSnoozeIfActive` must return `false` without writing if there is no open active session with Dose 1, if Dose 2 is already taken, if Dose 2 is skipped, or if schedule rollover closed the session during preflight.
- `DoseActionCoordinator.snooze` must commit repository snooze state before rescheduling alarm state. If alarm rescheduling fails, it must roll back the latest snooze event and snapshot count.
- `SessionRepository.clearDose1` must clear the full dependent dose sequence for that session: Dose 1, Dose 2, extra dose, Dose 2 skipped, and snooze state.

## Time Source Contract

- `SessionRepository.currentContext` must derive dose-window phase from the repository `clock` dependency, not a process-global `Date()` source.
- Session boundary evaluation, active-session writes, and UI phase calculation must share the same time source.
- Tests that inject a repository clock must build dose timestamps from that same clock.

## Recovery

On reload, recoverable active dose-state violations must not crash app launch. The repository must close the active snapshot with terminal state `invalid_dose_state`, preserve evidence rows for audit, log the invariant violation, and return the UI to no active session.

## Enforcement

- Runtime checker: `EventStorage.validateActiveDoseStateInvariant()`.
- Repository hook: `SessionRepository.validateDoseStateInvariant(reason:)` logs and debug-asserts after active dose mutations.
- CI guard: `tools/check_dose_state_writes.sh` blocks new direct write paths outside the allowed boundary.

Any future sync implementation, CloudKit adapter, import path, or widget action must use this same boundary or add a reviewed reconciliation layer with tests.
