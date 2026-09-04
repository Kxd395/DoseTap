# Alarm Scheduling Contract

Status: Current normative alarm contract
Last verified: 2026-09-04

This document is normative for DoseTap medication alarms and Dose 2 safety reminders. It defines when the application may claim that a notification is scheduled, how absolute deadlines survive clock and timezone changes, and which notification roles a snooze may replace.

## Safety Model

A call to `UNUserNotificationCenter.add` is an attempted write, not proof of a durable schedule. DoseTap may show a wake alarm or reminder group as scheduled only when all required requests for that group are present in the pending-request store and match the requested absolute instants.

There are two independently managed notification groups:

| Group | Canonical identifiers |
| --- | --- |
| Wake | `dosetap_dose2_alarm`, `dosetap_dose2_pre_alarm`, `dosetap_followup_1`, `dosetap_followup_2`, `dosetap_followup_3` |
| Safety reminders | `dosetap_second_dose`, `dosetap_window_15min`, `dosetap_window_5min` |

The desired set is time-dependent. Requests whose fire dates are already past are not required. Follow-ups that would occur after the 240-minute Dose 2 window are also omitted.

## Absolute Deadline

The selected Dose 2 wake target is an absolute Foundation `Date`. Travel, a manual timezone change, or a daylight-saving transition must not change that instant.

For each notification request:

1. Derive local date components for the absolute instant in the currently reconciled named timezone.
2. Freeze the timezone offset that applies at that exact instant and attach that fixed-offset timezone to the calendar trigger. This prevents the repeated fall-back hour from resolving to the wrong occurrence.
3. Store the absolute epoch, the named reconciliation timezone, and the notification group in `userInfo`.

The fixed-offset trigger is the delivery representation. The named timezone in persisted metadata and `userInfo` is provenance and is what the UI reports.

## Reconstruction Metadata

`AlarmService` persists one versioned reconstruction record containing:

- Dose 1 absolute time;
- absolute wake deadline;
- creation time;
- origin named-timezone identifier;
- last-reconciled named-timezone identifier;
- snooze count;
- wake and reminder verification flags; and
- expected request identifiers for each group.

On process restart, persisted verification flags describe the last commit but do not prove current pending state. Both published scheduled flags start false until reconciliation inspects the notification center.

## Transaction and Verification

Scheduling a group follows this sequence:

1. Capture one injected `now` value and one timezone value for the operation.
2. Reject a past wake deadline.
3. Fail closed when notification authorization is denied or undetermined.
4. Capture the previously pending requests for the affected group.
5. Add every desired request while checking the scheduling generation after each suspension point.
6. Remove stale identifiers belonging to that group only.
7. Read pending requests and verify the exact identifier set, absolute trigger dates, fixed offsets, and named-timezone provenance.
8. Commit published flags and reconstruction metadata only after verification succeeds.

An add error or verification mismatch removes the partial candidate and attempts to restore the prior group. A cancellation invalidates the scheduling generation; cancellation wins even if an add was in flight. The other notification group is never part of this rollback.

Typed scheduling results are:

- `scheduled`: the desired pending set was verified;
- `notNeeded`: no enabled future request is required, or notifications are intentionally disabled; and
- `failed`: authorization, invalid deadline, add, verification, cancellation, or reconstruction failure requires attention.

`DoseActionCoordinator.takeDose1` commits the medication event independently, then surfaces a warning when either notification group fails. The alarm indicator presents `lastSchedulingError` and a Retry Alarm action. Retry reconstructs and verifies both groups from persisted intent.

## Reconciliation

Reconciliation runs after app activation, timezone changes, significant-time changes, initial post-setup bootstrap, and explicit retry. It compares desired requests with actual pending requests and repairs missing, stale, mismatched, or unverified groups.

Timezone reconciliation preserves every absolute epoch while rebuilding trigger representations and named-zone provenance. Reconciliation with no persisted alarm intent is a successful no-op.

## Snooze Role Isolation

Snooze eligibility comes from `DoseRegistrationPolicy.evaluateSnooze` using one injected decision time. It is allowed only in the active phase and below the configured limit.

A successful snooze:

1. replaces the wake group transactionally at the new absolute deadline;
2. increments and persists snooze count only after the replacement verifies;
3. leaves every still-future safety reminder untouched; and
4. removes only safety reminders that are now expired or disabled.

A blocked or failed snooze does not modify either pending group. Dose 2 completion, skip, session reset, and explicit full cancellation remain the operations that cancel both role groups.

## Medication Outcome Isolation

Alarm state is reminder state, never medication state. Scheduling, delivery, dismissal, expiry, failure, app foregrounding, reconciliation, or the passage of the 240-minute window must not persist a taken, skipped, missed, or terminal medication outcome. When the window has ended with no Dose 2 outcome, the app may emphasize an unresolved-record prompt; only an explicit user command may record an actual occurrence or mark Dose 2 missed / not taken.

## Validation Boundary

Automated and simulator validation can prove policy decisions, request construction, failure rollback, reconciliation, and pending-request state. It cannot prove signed-device notification delivery, Focus/Silent-mode behavior, or an external hardware-button delivery sequence. Those acceptance checks remain open until owner-observed on a signed physical device.
