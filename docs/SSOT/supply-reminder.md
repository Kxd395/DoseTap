# Local order reminder

Implementation contract for DOSETAP-30, extended by owner-authorized DOSETAP-77.

Settings > Medications provides one private, local order reminder. The user enters
either a last-received date plus 21 calendar days, a reminder date, or a cycle-end date minus selected lead days,
and a local time. These are entered planning dates, not forecasts. Legacy inventory
snapshots remain separate from the tracked receipts below. No pharmacy, shipping, ordering or receipt service
is connected, and no dose history is used to infer consumption.

The source record lives in SQLite through SessionRepository. It preserves civil
date/time, source mode, lead days, enabled/handled state, revision history and a
named current-device-wall-clock timezone policy. Export/restore uses a versioned
local supply JSON file; importing replaces the complete supply document after confirmation.
Deleting the reminder removes its reminder history without touching bottle or dose data.

The notification uses only `dosetap_supply_order_reminder`. Notification content
is generic: “DoseTap reminder due.” Saving commits source data before attempting
scheduling. Scheduled means pending-request readback matched the current revision
and calendar trigger. Permission denial, failed/missing requests and past or
nonexistent local times have visible recovery states. Ambiguous fall-back times
use the first occurrence; nonexistent spring-forward times require user correction.
The first content on the first Pre-Sleep Check card, above the plan summary and
remembered-settings control, asks “Started a new bottle?” with the same optional
bottle-record sheet available in supply settings. Tonight links into this check immediately above the dose action. Confirmation saves
the bottle immediately and returns to the check; cancelling the sheet writes nothing.
The active nonvoided opening is displayed with its date and time. This record is independent
of completing, skipping or cancelling the check and is never carried forward by
"Use room setup" or remembered pre-sleep settings. Under DOSETAP-51, only room
temperature, noise setup and non-medication sleep aids may carry forward. Daily
answers, notes and occurrence times start unanswered for a new night; existing
logs and History edits retain their answers. Recording a bottle is not required
to continue.
Legacy unlinked bottle-start records preserve opened-at and recorded-at times and
retain their existing deletion option. Tracked records use the retained undo history
described below. Neither kind moves the calendar reminder or alters dose records.
Launch, foreground, significant clock changes and timezone changes reconcile the
same identifier. No supply operation touches medication alarm identifiers.
Tapping the supply notification opens its management screen; it does not acknowledge
the reminder or record a medication event.

Handled acknowledges the local reminder only. Disable/handled/delete cancels the
supply request. Changes preserve previous source revisions and their times. The
UI serializes commands; reset invalidates any scheduling work in flight.

Automatic quantity-based estimates are deferred until a confirmed compatible
quantity, plan and treatment schedule exist. Physical delivery, permission
recovery, accessibility and owner acceptance remain distinct from automated tests.

## Bottle tracking extension (DOSETAP-77)

See [local bottle tracking](bottle-tracking.md) for the complete contract.
Reported receipts default to three unopened bottles, editable from 1–100. Receipt
entry opens nothing. An explicit tracked opening reduces unopened stock and replaces
the displayed active opening without claiming the previous bottle was empty.
Undo retains source history and restores stock; legacy openings are never assigned
by inference. Recorded dosing nights and unopened stock are separate measures.
Only third-night emphasis requires a successful usage read; the last-tracked-bottle
notice depends on validated supply alone. Both are in-app notices, not automatic
third-night notifications or pharmacy actions. Quantity estimates remain unavailable.
Version-1 documents remain readable; tracking writes version 2 so older apps reject
rather than erase new records. Settings supply JSON and Studio ZIP/Excel retain
receipts, openings and void history. Export's `supplyStateJSON` uses
`supplyStateEncoding: json-date-seconds-since-2001-v1` to preserve exact source dates.
