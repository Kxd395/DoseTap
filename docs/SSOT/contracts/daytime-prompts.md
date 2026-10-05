# Optional daytime routine prompt (DOSETAP-58)

## Visible queue status

The reminder screen presents saved status before editable configuration. A queue
snapshot is published only after OS request identity/time readback and the final
ledger write succeed. It records verification time and sorted attempt times;
the next reminder is the earliest future attempt in that snapshot, not the first
ledger row or the saved routine's nominal clock time. Past attempts are never
presented as upcoming. Refresh, pause, denied permission, active sleep, capacity
limits and failures clear the previous snapshot. Queue verification is not proof
of notification delivery. The last-check time includes unsuccessful attempts.
Permission denial provides a direct iOS Settings action; it does not enable
notifications or alter the saved schedule. Status and Save remain accessible
without scrolling through all weekday controls.

The settings draft initializes once, after a valid ledger load and completion of
any in-progress reconciliation. Loading or unreadable state disables edits and
Save. A successful retry enables the retained draft; refresh never overwrites
unsaved edits. Saved status remains separate from those edits.

One optional user-selected routine reminder is off by default. Its anchor and selected days are explicitly configured. Store immutable schedule versions and prompt IDs, intended time, opened time, actual assessment time, response identity, and explicit pending/deferred/suppressed/skipped/expired/responded state. A schedule change cancels outstanding prompts; it never rewrites old intended times. Retry uses the same prompt/request identity. Nonresponse is unknown, never a symptom or sleep score.

Use a routine passive notification with generic DoseTap wording, no sound, no health value, and no bypass of Focus. Skip and Later are explicit actions. Suppress while a known main sleep or nap is active, within user-configured quiet hours, or without permission. Up to seven daily occurrences are queued using stable schedule/date identities; foreground reconciliation replenishes the horizon. Settings shows the last scheduled time and explains the renewal boundary. Known active sleep cancels queued requests, keeps past unanswered delivery unknown, and retains future pending slots for wake reconciliation. This bounded schedule does not promise indefinite background scheduling. Delivery time is not claimed. A delayed response assesses the current moment, never the intended prompt time.

History and preferences persist in SQLite through SessionRepository. Clear All Data removes both and cancels the owned request on reconciliation. Dose alarm categories, requests, permissions and routing remain independent. Physical-device background delivery, Focus, actions, nap cancellation and notification privacy require owner-observed acceptance.

Eligibility recovery may resume only future instances in the current schedule that were suppressed for notification permission or configured quiet hours. Preserve their intended time and identity; recheck permission and quiet hours before queueing. Explicit skips, responses, older schedule versions and past unknown-delivery instances never reactivate automatically.

## Selected days and evidence-based anchors

A versioned rule chooses Gregorian weekdays in its explicitly saved timezone and one primary anchor: local clock time, elapsed minutes after a patient-reported designated main wake, reviewed saved shift midpoint, or reviewed saved shift break. Shift-based rules have a separately configured off-day clock or main-wake anchor. Unknown work status cannot silently choose either branch. A 13-hour explicitly saved shift midpoint is 6 hours 30 minutes after its start; weekday names never supply a start. Missing, conflicting or differently zoned source evidence remains explicitly unscheduled.

Main-wake anchors use an explicit reported final-wake observation and source/revision; session closure, check-in completion and nap end cannot substitute. Preserve original intended notification time, source IDs/revisions, anchor kind, work/off-day basis and actual assessment time separately. Revisions may change future scheduling only after recording the prior source; saved assessment answers and timestamps remain immutable. Future wakes are not predicted. The horizon is seven civil days, not seven selected weekdays spanning multiple weeks.

## Persisted timestamp representation

The new `daytime_prompt_state` JSON payload encodes every timestamp as UTC ISO8601 with exactly millisecond precision (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`). Normalize supplied event times to the nearest millisecond once at the ledger mutation boundary; calendar minute boundaries remain exact. Awaited repository readbacks compare canonical encoded payloads, avoiding submillisecond in-memory differences. Consumers use the shared strict `DaytimePromptLedger.decodePayload` codec. This payload has not shipped and has no legacy numeric-date migration.

Calendar notification attempts have whole-second precision: a 30-minute user deferral rounds its requested fire time up to the next whole second. Actual assessment and opening times retain millisecond precision; the original intended prompt time is unchanged.

## Anchor horizon and source revisions

Anchor rules evaluate a rolling interval after reconciliation through the same saved-zone civil clock time seven calendar days later, with at most seven requests. A selected weekday whose clock time has already passed can therefore queue its next occurrence within that interval; DST does not turn the boundary into a fixed 168-hour duration. Selected weekdays never extend that horizon into later weeks. Weekday selection applies to the originating anchor day in the saved timezone, not the eventual notification day: a Tuesday evening shift with a Wednesday midpoint is selected by Tuesday. A wake offset crossing midnight follows the reported wake day. The planner also examines the previous anchor day for these future overnight times. Each planned slot retains its originating civil day, anchor kind, source ID/revision/timestamps, optional work-source revision and original intended time. Whole-second notification attempts round upward without changing that intended time. A changed future anchor suppresses the prior slot and creates a stable new occurrence; retries reuse the current occurrence. Past potentially delivered slots, explicit skips and responses never generate a second same-day prompt. An existing main-wake occurrence remains tied to its original night source identity; disappearance or replacement leaves it unscheduled until the routine is reviewed. Missing or conflicting anchor evidence never supplies a guessed timestamp.

The app resolves work evidence from the validated work document in the routine’s saved timezone. Initial wake-anchor selection requires exactly one explicit reported main-wake source for the selected civil day. Existing prompts resolve their original stable night-source identity after corrections; cleared, absent or conflicting evidence remains unscheduled. Session closure, nap end and provider data are not fallback anchors. Current source context and the canonical prompt ledger are re-read after asynchronous notification work; a changed source cancels owned requests and reports a failed update rather than claiming the old context was scheduled successfully.

Non-repeating OS trigger components use UTC so the second occurrence of a repeated fall-back clock hour retains its exact intended instant. Saved-zone weekday selection, originating anchor day, quiet-hour evaluation and original source metadata remain in the routine’s explicitly saved timezone.

## Randomized main-wake routine (DOSETAP-58)

An optional randomized wake routine preserves existing single-reminder schedules.
Workdays use elapsed-hour windows 2–4, 6–9 and 11–13 after explicitly reported
main wake; off days use 3–5 and 8–10. Work status must be explicitly resolved for
the wake date. Unknown status, missing/future/ambiguous wake or mismatched zones
remain unscheduled. These are personal diary defaults, not clinical thresholds.
A separately saved work/off-day bedtime (initial draft 22:00, editable before
Save) stops prompts two hours before the next bedtime after wake. Quiet hours
and known sleep remain independent suppressors. No future wakes are predicted.

A stable schedule/date/window seed selects whole-minute steps from the first
valid whole-second instant in the window. Normalize the lower bound before
calculating the available choices so rounding cannot discard an upper-edge draw.
Previously saved choices remain unchanged. New choices have at
least two hours between attempts. Each occurrence retains its window bounds and
wake/work evidence. Refresh and restart cannot redraw it. Source corrections
suppress remaining old occurrences for that wake date instead of silently
resampling; a reviewed new schedule is required. Past, answered or skipped
windows are not repeated by saving a new routine. At most three windows per
workday or two per off day are created; missed windows never cause catch-up.
The existing seven-request queue ceiling and seven-civil-day horizon remain.

Completing a nonretrospective original check-in within a window satisfies that
window without changing its reported origin or answers. Explicit prompt responses
still refer to their original prompt. Later windows remain independent. Later
moves the same occurrence by 30 minutes only within its window and bedtime cutoff,
and only when two-hour spacing from other attempts remains; otherwise it fails
without a new request. There are no automatic follow-up nudges. Missing responses
remain unknown. Enabling and Save remain explicit user actions.
