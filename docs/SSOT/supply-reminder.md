# Local order reminder

Implementation contract for DOSETAP-30, on `feat/local-order-reminder`.

Settings > Medications provides one private, local order reminder. The user enters
either a last-received date plus 21 calendar days, a reminder date, or a cycle-end date minus selected lead days,
and a local time. These are entered planning dates, not forecasts. Bottle counts
remain independent snapshots. No pharmacy, shipping, ordering or receipt service
is connected, and no dose history is used to infer consumption.

The source record lives in SQLite through SessionRepository. It preserves civil
date/time, source mode, lead days, enabled/handled state, revision history and a
named current-device-wall-clock timezone policy. Export/restore uses a versioned
local supply JSON file; importing replaces reminder and bottle records after confirmation.
Deleting it removes its history, after confirmation, without touching dose data.

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
The last saved opening is displayed with its date and time. This record is independent
of completing, skipping or cancelling the check and is never carried forward by
“Use last” or remembered pre-sleep answers. Other pre-sleep answers, including
free-text notes, carry forward when remembering is enabled or “Use last” is selected;
time-of-day answers move to the new reference day. Users can edit or clear these
answers. Recording a bottle is not required to continue.
Optional bottle-start records preserve opened-at and recorded-at times,
can be deleted if entered accidentally, and never move the reminder or alter dose records.
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
