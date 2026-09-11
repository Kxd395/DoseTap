# Alarm Scheduling Contract

Status: Current normative alarm contract
Last verified: 2026-09-04

This document is normative for DoseTap medication alarms and Dose 2 safety reminders. It defines when the application may claim that a notification is scheduled, how absolute deadlines survive clock and timezone changes, and which notification roles a snooze may replace.

## Safety Model

### Committed Dose 2 completion (DOSETAP-67, build 47)

The coordinator and morning reconciliation share `completeDose2Reminders` after
a dose/explicit-skip transaction commits. A nonmatching historical session cannot
cancel the active session's stable identifiers. Completion invalidates in-flight
scheduling, stops the in-app sound and vibration, and removes the two Dose 2 groups
below from pending and delivered notifications. It does not remove supply, test,
other-app or unrelated notification identifiers.

Success requires system-alarm absence plus pending/delivered readback. A failure or
unavailable readback produces a separate warning without rolling back medication.
Morning reconciliation attempts cleanup before the questionnaire write. Its retry
does not reapply committed medication choices. A saved questionnaire with an alarm
warning remains visibly acknowledged before dismissal; a questionnaire write
failure retains both the draft and any separate alarm warning. No automatic retry
may cancel a future session's alarm. Locked-phone ringing/cancellation, VoiceOver
and owner-observed save/reopen remain independent acceptance gates.

### System wake alarms on iOS 26+

The Dose 2 wake role uses a fixed-date AlarmKit alarm on iOS 26 and later,
with its separate user authorization and pending-alarm readback. AlarmService
retains ownership of the absolute wake target, retry and snooze policy. Existing
UNUserNotificationCenter safety reminders and supply reminders remain separate.
Earlier iOS versions retain the notification wake path described below; its
sound and presentation remain subject to notification, Silent and Focus settings.
The app must not claim continuous locked-phone audio from its AVAudioPlayer.

System Stop silences the alarm without recording Dose 2. Opening DoseTap leads
to the existing explicit medication controls. System snooze is not enabled;
DoseTap's in-app snooze continues to enforce the canonical window and limit.
The stable system-alarm identifier is isolated from supply reminders. Reset,
completion and cancellation invalidate pending system-alarm writes and cancel it.
The UI shows permission or scheduling errors and offers a permission/retry path.
Cancellation errors survive session-state cleanup and remain visible until corrected.
Settings provides a separate, stable-ID one-minute test alarm; it neither replaces
the Dose 2 alarm nor creates a medication event. The unsupported Critical Alerts
toggle is hidden unless the app declares its existing capability flag; no entitlement
or account approval is fabricated. In-app/notification sound and system-alarm sound
are labeled separately.

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
