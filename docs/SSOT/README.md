# DoseTap SSOT (Single Source of Truth)

Status: Current behavior authority
Last verified: 2026-09-12
SSOT revision: 0.4.19
Shipping app version observed in the Xcode project: 0.4.19 (build 52)

This document is the authoritative specification for current DoseTap behavior. It describes the intended shipping contract and is checked against the implementation. A code/spec mismatch is a defect to reconcile explicitly; changing this file must not be used to hide an unsafe implementation change.

## No alarm reminder choice

Dose 1 reminder choice: the existing interval pills are followed by **No alarm**.
This is an explicit tonight-only opt-out from the active session's Dose 2 wake,
snooze/follow-up and window reminders. Selecting it alone records nothing; dose
confirmation saves medication first, then verifies cancellation. Failed writes
retain the choice and leave preferences/reminders untouched. Cancellation failure
keeps the dose and exposes retry. A separately saved usual choice may be No alarm;
global notifications and medication timing windows do not change. Restart and
History correction must not automatically recreate opted-out reminders. Explicit
alarm changes may re-enable them for the still-active dose.

## Canonical References

- Code entry points: `ios/DoseTap/Storage/SessionRepository.swift`, `ios/Core/DoseTapCore.swift`, `ios/DoseTap/ContentView.swift`
- Views: `ios/DoseTap/Views/TonightView.swift`, `ios/DoseTap/Views/CompactDoseButton.swift`, `ios/DoseTap/Views/DetailsView.swift`
- Storage: `ios/DoseTap/Storage/EventStorage.swift` and the maintained `ios/DoseTap/Storage/EventStorage+*.swift` extensions
- Executable schema: `ios/DoseTap/Storage/EventStorage+Schema.swift`
- Human-readable schema: `docs/DATABASE_SCHEMA.md`
- Dose persistence contract: `docs/SSOT/dose-state-persistence.md`
- Alarm scheduling contract: `docs/SSOT/alarm-scheduling.md`
- Local order reminder contract: `docs/SSOT/supply-reminder.md`
- Data dictionary: `docs/SSOT/contracts/DataDictionary.md`
- Diagnostic logging: `docs/DIAGNOSTIC_LOGGING.md`

Notes:
- `docs/SSOT/constants.json` is a reference snapshot, not a generator. Code must stay in sync manually.
- If you need planned or speculative features, see `docs/FEATURE_TRIAGE.md` (not SSOT).

---

## Domain Entities and Invariants

### Dose 1 reminder review (DOSETAP-71)

- Dose 1 review separates the reported occurrence from its recording time and tonight's Dose 2 reminder interval. The reviewed interval uses the existing 165/180/195/210/225-minute choices; it does not change the medication window. Opening, cancelling, or selecting a preset writes nothing.
- A review challenge is single-use, bound to the current session identity and treatment date, and invalidated on backgrounding. Confirmation rechecks the session and existing dose before writing. Now is captured at confirmation; earlier occurrences must be finite, nonfuture and in the current treatment night. Other historical nights use History.
- The dose commits before alarm scheduling. New review metadata retains recorded-at time, source surface, and selected reminder interval. An optional usual-interval update occurs only after the dose commit; a tonight-only choice leaves the existing preference untouched. Existing records and schemas are unchanged.
- Alarm scheduling uses the reported Dose 1 occurrence plus the selected interval, not capture time. A past reminder target does not reject a reported taken dose; show the saved dose and scheduling error. Retry is alarm-only, bound to the still-active dose/session, and cannot record medication or revive a completed session's reminders.
- Dose-target work advisories use the confirmed interval retained on this session's Dose 1 record, with the existing usual-target fallback for legacy records. Snoozes and later alarm-only changes do not rewrite that confirmed target. A failed write retry preserves the initiating surface. A window-reminder failure keeps retry available even when the main wake alarm is verified.
- In-app review shows the exact target even when unverified, retains a failed write's confirmed occurrence for retry, and distinguishes verified alarm scheduling from saved medication. An invalid earlier date remains editable before confirmation is consumed. An eligible active/unlocked Dose 1 deep link presents the review directly; Flic directs the user to review in the app. Neither writes medication. Native UI and signed-phone delivery are separate validation gates.

### Dose completion and morning timing clarification (DOSETAP-67)

- A committed active-session Dose 2 taken/explicit-skip action cancels only the app-owned Dose 2 wake, follow-up and window reminder identifiers. Morning reconciliation performs the same cleanup before attempting the questionnaire write; a questionnaire failure never undoes that dose or reapplies it on retry. Historical-session completion cannot cancel the current session's reminders.
- Cancellation success requires system-alarm absence and pending/delivered notification readback. An unverified cancellation preserves the medication record and gives separate alarm-status guidance. Alarm open/stop never records a dose. Verification is local API evidence, not signed-phone acceptance.
- The morning exception question is shown only for early/late actual dose intervals, using shared unrounded timing classification; an alarm target is not a dosing-window boundary. In-window records show their interval without reconfirmation. Unanswered taken-reason values remain absent; explicitly selected Unsure remains an answer. Existing records are not rewritten.
- New live submissions omit timing reasons and notes that became inapplicable after a time/status correction; History edits preserve existing annotations. Cancellation warnings name the committed outcome: an explicit skip says skipped (not taken), never implying administration.
- Closing the morning form does not save a partial questionnaire. The control says Close check-in; a durable partial-draft/skip workflow remains separate work. General legacy context defaults, unknown-time dose outcomes, per-session window snapshots and dashboard/schedule cleanup remain open.

### Planned and actual sleeping setup (DOSETAP-70)

- Pre-sleep page 3 includes optional sleeping arrangement, shared-space detail, pets and usual/away sleep location. The setup is a plan, not proof of another person's presence. Missing, Unsure and Prefer not to answer remain distinct. No names, addresses, relationship details or clinical observer questions are collected.
- Morning lookup prefers the exact session identity. If no exact pre-sleep row exists, a date-placeholder plan from before session creation may be read only when the supplied treatment date resolves to that one canonical identity. Multiple sessions on a date, a wrong date, or an explicit blank/skipped row must not borrow a fallback plan. This read-only resolution requires no Dose 1 event and does not relink or rewrite questionnaires.
- A separately saved usual sleeping setup is offered as a visible suggestion, never a confirmed nightly answer. Applying it is explicit and fills only unanswered fields. Saving or forgetting the usual setup does not submit a questionnaire; History edits cannot change that preference. The room-setup toolbar action reveals page 3 and explains whether previous room settings were applied or unavailable.
- Morning shows only the matching session's completed pre-sleep plan. Same as planned requires an explicit action and stores a snapshot; Change records an independent actual arrangement. Unsure, Prefer not to answer and unanswered remain separate. A later pre-sleep correction cannot silently rewrite a saved morning snapshot. No prior morning presence, impact or factors carry forward.
- Optional morning impact is No noticeable effect, Helped, Disrupted, Both, Unsure or Not applicable. Noise, movement, schedules/alarms, care, pets, comfort and Other details apply only to Helped/Disrupted/Both; changing the impact clears hidden factors. Arrangement-specific shared-space detail is removed when no longer applicable.
- Additive version-1 records live in pre-sleep `sleepingSetup` and morning `sleep_environment_json.sleepingContext`, independent of the legacy room-details toggle. Source/normalized questionnaire transactions, History corrections and raw/normalized exports preserve them. Studio's existing raw-questionnaire detail/import path retains them; no new correlation score is introduced. Usual preferences are not a claimed full backup. Existing records stay unanswered; no migration invents prior answers. Medication, alarms, HealthKit and session-completion rules are unchanged.

### Fresh pre-sleep answers (DOSETAP-51)

- A new pre-sleep form may remember room temperature, noise setup and non-medication sleep aids only. The existing preference now says "Remember room setup". Intended sleep timing, daily stress/pain/notes, caffeine, alcohol (including None), food, exercise, naps, screen use and questionnaire dose-plan values are not copied from a previous night.
- "Use room setup" fills only unanswered room-setup fields; it must not erase current answers or replace existing room choices. Opening an existing log or a History correction preserves that log's original answers. No previous stored row is changed by preparing a new form.
- This slice removes cross-night answer copying. Substance-entry default quantities/times, optional amount entry, legacy adapters and unit migration remain follow-up work under DOSETAP-51/52; do not describe all consumption defaults as repaired yet.
- Apple Health data, medication records, alarm behavior and quick logs are unchanged by this repair.
- Saving an unanswered caffeine question preserves a missing answer in both the source questionnaire and normalized responses. Only an explicit None answer produces `pre.substances.caffeine.any = false`. Existing explicit answers remain unchanged; this repair does not relabel older stored None values as unknown.
- The caffeine form offers "No caffeine today" as an explicit answer. "Clear answer" and deselecting the last source return it to Not recorded, not None. The current answer is shown in text as well as through source selection.

### Independent and remembered pain entries (DOSETAP-61)

- Each pain-editor save records one area and side with its own intensity, sensations, pattern and notes. Add another pain creates an independent entry; it must not apply one set of sensations to every area.
- Remember this pain saves a reusable preference, not a nightly symptom observation. Saved pain patterns survive app restart, are independently removable, and open in the editor for review before being added to tonight. Cancelling or merely displaying a saved pattern records nothing. Forgetting a pattern does not delete past questionnaires.
- Using a saved pattern is not editing its matching nightly entry. If its area/side changes during review, the original nightly entry remains; only an explicit nightly Edit action supplies a replacement key.
- The live pre-sleep pain editor offers an explicit Remember for future nights option before Save. Saved-pattern review puts tonight's intensity first, retaining the saved area, side and sensations for adjustment. Each pattern still requires a review/save action for tonight; daily severity is not silently carried forward as an observation. History and morning editors do not change these preferences.
- Live morning Physical Symptoms offers the same saved pain preferences through Use this morning. Each selection opens a review with morning intensity initially Not recorded; choose 0–10 explicitly before adding it to the draft. Saved intensity and notes are not copied into the morning observation. Location, side, sensations and optional pattern are visible for review. Cancel adds nothing; selecting one pattern does not add others. Complete Check-In persists confirmed entries through the existing atomic source/normalized/symptom transaction and retains answers on failure.
- Morning saved-pattern cards omit historical intensity. An already-added area/side directs the user to Edit instead of reapplying that preference. Changing a saved review to an occupied morning area/side also disables Save with explicit Edit guidance, preserving the existing observation. Morning and History never write, forget or update saved patterns; History does not offer current preferences. Existing morning entries still reopen with their recorded intensity and notes. This is explicit reuse of the existing library, not the planned UUID identity, automatic recurring prompts or presence/absence redesign.
- Existing area/side identity and questionnaire exports remain unchanged. At most one entry per area/side is supported; distinct problems in exactly the same area/side need a future identity change. Saved preferences are not currently included in the clinical event export or a promised full backup. Confirmed nightly entries use the existing storage/export path.

### Caffeine amount units (DOSETAP-52)

- New caffeine amounts use a version-1 record with independent optional last/daily beverage volumes in US fluid ounces and caffeine masses in milligrams. One source (user-reported, label-reported, estimated or unknown) applies to the entered amounts; manual entries start as user-reported. No volume-to-caffeine conversion is performed. Missing amounts stay missing; explicit zero and fractional values are retained.
- Older `caffeineLastAmountMg` / `caffeineDailyTotalMg` fields have ambiguous semantics: prior UI entries used ounces and a legacy adapter fabricated 95. Preserve those raw numbers as legacy amounts with unverified units, not as new volume or mass. New normalized responses and reports must not emit the same number under both units. Old records are not bulk rewritten.
- Choosing caffeine alone does not invent amount or time. The Boolean legacy adapter records only the supplied yes/no/unknown caffeine answer. Missing details do not block completion. Entered amounts must be finite and nonnegative, with a daily total no smaller than the last amount when both exist. Unsupported record versions cannot be interpreted or saved as version 1. This is diary context, not a dosing or safety decision.

### Last food in pre-sleep logging (DOSETAP-50)

- Record the last food finish date/time, meal/snack/calorie-containing drink type, optional high-fat/oily Yes/No/Unsure answer, and optional notes (500 characters). Unrecorded is not fasting; Unsure is not No.
- Store an optional `lastFood` object in pre-sleep answers and additive `pre.food.last.*` normalized responses. Preserve legacy late-meal records without inferring fat content or treating them as a verified last-food record. Food observations never carry forward into a new night.
- Save and History correction use existing questionnaire transactions and provenance. Reject non-finite/future finish times relative to questionnaire occurrence, and overlong notes, without partial writes.
- Show the same fields in History review and exports. This is a diary entry, not dose eligibility, dose adjustment, alarm control, or a safe-to-dose indicator.
- Food guidance follows XYWAV prescribing information sections 2.4 and 12.3 (revised July 2025): at least two hours after eating; a high-fat meal affects exposure, but the label does not define an additional fatty-food wait. Source: https://pp.jazzpharma.com/pi/xywav.en.USPI.pdf.

### SleepSession

Identity and lifecycle are separate from calendar day grouping.

- Identity: `session_id` (UUID string). Medication mutations, including undo, annotations and time edits, use that identity. Date-only mutations reject multiple matching identities; legacy NULL/date identities remain supported.
- Grouping key: `session_date` (YYYY-MM-DD) computed by `sessionKey(for:timeZone:rolloverHour:)` with default rollover hour 18 (6 PM). See `ios/Core/SessionKey.swift`.
- While a session remains active, the published Tonight key is that session's saved grouping date across reloads, time changes, and medication writes. The wall-clock grouping date takes over only when no active session remains.
- Persistence: `sleep_sessions` table and `current_session` table (see `ios/DoseTap/Storage/EventStorage.swift`).
- Start: first event that requires a session (dose, snooze, sleep event, pre-sleep log linking) via `SessionRepository.ensureActiveSession(for:reason:)`.
- End: when morning check-in completes or when schedule fallback closes the session.

Closure rules (authoritative):
- Primary: `SessionRepository.completeCheckIn()` closes the active session and clears in-memory state. Invoked by `SessionRepository.saveMorningCheckIn(...)` when the saved check-in matches the active session.
- Fallback A (missed check-in cutoff): `SessionRepository.evaluateSessionBoundaries(reason:)` closes the session if `now >= cutoffTime(start)`.
- Fallback B (prep-time soft rollover): `SessionRepository.evaluateSessionBoundaries(reason:)` closes the session if `now >= prepTime` and session started before prep time.
- Startup may perform either fallback while the repository is initializing. Alarm cleanup receives the closing session's identity explicitly and must not reenter `SessionRepository.shared`.

Schedule settings used by rollover logic (from `UserSettingsManager`):
- `sleepStartMinutes` (default 21:00)
- `wakeTimeMinutes` (default 07:00)
- `prepTimeMinutes` (default 18:00)
- `missedCheckInCutoffHours` (default 4)

Safety constraints (authoritative):
- Dose 2 timing is classified from absolute elapsed seconds: 150 minutes inclusive through 240 minutes inclusive is in-window; before 150 minutes is early and more than 240 minutes is late. Negative or non-finite elapsed values are invalid. Display rounding must never determine eligibility, adherence, export status, or scores.
- Endpoint reconciliation (DOSETAP-15, 2026-09-07): the owner-requested inclusive upper endpoint replaces the prior exclusive contract. It implements the twice-nightly 2.5-to-4-hour interval in the [XYWAV prescribing information, sections 2.2 and 2.3](https://pp.jazzpharma.com/pi/xywav.en.USPI.pdf). Exactly 14,400 elapsed seconds is in-window; any larger interval is late. This does not change prescribed amounts, permit automatic medication recording, or equate in-window timing with medication effectiveness.
- Default target interval is 165 minutes (valid planner targets: 165, 180, 195, 210, 225).
- Session day grouping rolls over at 18:00 (6 PM) local time.
- Undo window is 5 seconds by default for dose/event actions.
- Elapsed time, an unanswered alarm, app foregrounding, or session rollover must never persist a taken, skipped, or missed medication outcome.
- An ordinary Dose 2 request opens an explicit record confirmation; the initial tap, deep link, or Flic action cannot commit it. Confirmation is single-use, bound to the active session and its Dose 1 timestamp, and invalidated when the app becomes inactive. Confirming rechecks the current timing and work-warning policy and captures the commit-time clock; a stale prompt must never supply an earlier alarm or request timestamp.
- The confirmation control says that it records a dose already taken. Cancel, dismissal, alarm open/stop, and backgrounding leave the medication record unchanged. The early warning plus hold-to-confirm remains its existing explicit confirmation path; retrospective and extra-dose confirmations also remain distinct. A work-warning acknowledgement alone does not replace ordinary Dose 2 record confirmation.
- `closed` is a calculated timing phase, not a persisted medication outcome. An unresolved record remains unresolved until the user explicitly records an occurrence that already happened or marks Dose 2 missed / not taken.
- Prospective Dose 2 actions are blocked after the configured window. A real occurrence remains recordable retrospectively with its actual timestamp; an occurrence outside the configured window requires an explicit accuracy warning and confirmation.

### DoseEvent

- Storage: `dose_events` table with `session_id` and `session_date`. See `EventStorage+Dose.swift` for `saveDose1/saveDose2/saveDoseSkipped/saveSnooze`.
- Event types (exact strings): `dose1`, `dose2`, `extra_dose`, `dose2_skipped`, `snooze`.
- Dose index rule: `doseIndex = (count of dose events in session) + 1` where count includes `dose1`, `dose2`, `extra_dose` only.
- Dose 2 late flag: `is_late = true` if `doseIndex == 2` and `timestamp > dose1 + maxInterval`.
- Retrospective Dose 2 records persist `entry_mode = retrospective`, `recorded_at_utc`, and the initiating `surface` in metadata while keeping the event timestamp equal to the actual occurrence time.
- Extra dose rule: `doseIndex >= 3` only. Timer expiration never changes dose index.
- An ordinary Dose 2 command must never be promoted to `extra_dose` because another surface committed first. Repository and storage preconditions require an explicit extra-dose confirmation.
- Extra dose does not update `current_session.dose2_time`.
- Active-session dose writes must keep `dose_events` and `current_session` consistent in one SQLite transaction. Only a typed committed result may update in-memory state or trigger success feedback; open/full-disk/corruption/statement/commit failures fail closed with retry guidance. The write boundary, failure taxonomy, and restart invariants are specified in `docs/SSOT/dose-state-persistence.md`.

Code references:
- `SessionRepository.setDose1Time(_:)`
- `SessionRepository.setDose2Time(_:isEarly:isExtraDose:entryMode:recordedAt:surface:reason:reasonNotes:)`
- `SessionRepository.loadDoseEvents(sessionId:sessionDate:)`
- `EventStorage+Dose.saveDose2(timestamp:isEarly:isExtraDose:isLate:entryMode:recordedAt:surface:reason:reasonNotes:sessionId:sessionDateOverride:)`

### SleepEvent

Sleep events are stored as free-form strings in `sleep_events.event_type`. The Quick Log buttons are the only authoritative source of event names for the app UI.

- Storage: `sleep_events` table with `session_id` and `session_date`.
- Inserted via `SessionRepository.insertSleepEvent(...)` (used by `EventLogger.logEvent(...)` in `ios/DoseTap/EventLogger.swift`).
- There is no enforced canonical enum for UI event strings in the app target; `InputValidator` provides a whitelist for deep links only.

Current Quick Log event names (from `UserSettingsManager.allAvailableEvents`):
- Bathroom
- Water
- Snack
- Nap Start
- Nap End
- Lights Out
- Brief Wake
- In Bed
- Anxiety
- Dream
- Heart Racing
- Noise
- Temperature
- Pain

### Morning Check-In

- DOSETAP-51 remembered morning setup: both the saved-settings path and prior-check-in fallback may restore only the therapy device, room temperature, noise setup and sleep aid. They do not restore daily outcomes, symptoms, therapy use/compliance, stress, notes, work context or clinical answers. Room/equipment choices remain inactive until their current-morning section is selected. Remembering setup remains optional; switching it off does not clear this morning's answers.
- Newly saved morning preferences contain only those four setup fields. Legacy preference payloads are read through the same whitelist without rewriting historical check-ins. Explicit existing-night/History editing still loads that night's answers. The existing fixed rating and Boolean defaults remain a known limitation; removing cross-night copying does not make every untouched control an unanswered observation. Optional-answer/schema work, substance defaults and caffeine unit handling remain separate follow-ups.

- DOSETAP-67/61 symptom-selection repair: Physical Symptoms includes localized pain, headache, stiffness, soreness, reflux, restlessness and bathroom urgency. Opening that section does not require a localized pain entry to complete the questionnaire. The separate pain editor still validates an entry before adding it. Failed questionnaire writes retain the same error/retry behavior.
- In new or explicitly edited morning answers, deselecting Headache removes its severity, location and migraine-like fields from the saved physical payload and normalized responses. Hidden headache values cannot affect the current derived pain burden; disabling the whole physical section excludes its current payload and burden. Other selected symptoms and localized pain entries remain intact. Opening an editor does not rewrite old rows. Existing History correction provenance is unchanged.
- With no localized entries, new/edited payloads omit localized pain type and intensity rather than saving the editor's defaults. Legacy `pain.any` remains the physical-section flag, not a measured pain count; existing scales/default-origin limitations are unchanged. These repairs add no clinical scale, medication action or schema migration.

- DOSETAP-67 questionnaire-intent repair: missing Dose 1 starts unselected and Dose 2 starts Leave as-is, including an existing skip. Opening or ordinarily saving a morning form does not add, replace or annotate medication records. Unanswered medication status remains unrecorded, not skipped. Explicitly selected retrospective reconciliation is still supported; separating it into its own reviewed action remains planned. Questionnaire reason answers stay questionnaire data unless included in an explicitly selected new dose/skip action. Existing medication reasons and occurrence times are not overwritten by default questionnaire values.

- Storage: `morning_checkins` table.
- Save path: `MorningCheckInView` -> `MorningCheckInViewModel.toStoredCheckIn()` -> `SessionRepository.saveMorningCheckIn(...)`.
- When saved for the active session, check-in closes the session: `SessionRepository.completeCheckIn()` -> `closeActiveSession(...)`.
- If morning answers derive symptom events, the morning source row, normalized check-in submission row, and derived symptom replacement commit in one SQLite transaction. Failure in any one of those writes rolls back the source row save.
- Only a confirmed questionnaire commit may dismiss the morning form, save reusable settings, or complete its session. Failure keeps the draft visible with retry guidance; previously committed explicit medication reconciliation is not undone or described as rolled back. The save stays bound to the form's night/identity, never a newly active session.
- A readable saved check-in suppresses the matching incomplete-night reminder, including legacy date-keyed check-ins when that date identifies only one session. Ambiguous dates do not let one check-in hide another identity. Record-change notifications refresh the reminder without requiring a relaunch. No old rows are rewritten by reminder selection.

### NapEvent

Naps are implemented as paired sleep events, not a separate table.

- Start: sleep event named "Nap Start".
- End: sleep event named "Nap End".
- Pairing is done in History (`SelectedDayView.napIntervals`) by pairing the next "Nap End" after a "Nap Start".
- If a start has no end, History shows "Nap in progress". There is no guard preventing multiple overlapping naps.

### HealthKit

- Shared reviewed-night projection, DOSETAP-56: successful current-input provider checks also produce a versioned, read-only `ReviewedNightSleepProjection`. It carries reviewed bounds, generation time, coverage, conflict duration and chronological sleep/awake/unmeasured/conflict bands without raw sample or source identifiers. Adjacent bands of the same state are joined; provider sample boundaries and stage changes do not create awakenings. The original provider snapshot and stage detail remain intact. Invalid bounds, malformed observations or a generation time before window review cannot produce a projection. Empty and all-awake results remain distinct. This is an in-memory consumer contract, not a saved report, completed marker calculation or replacement for existing chart/export totals. Consumers must honor the loader's invalidation rules; serialization does not certify that a snapshot is still current. Export redaction and chart/report adoption remain open.

- Reviewed-night provider check, DOSETAP-56: an optional action in Wake & Next Day queries Apple Health only for an unchanged, saved window whose current local assessment is checked, with the HealthKit preference enabled. Read the selected identity, full dose rows, saved outcome, other reviewed windows and nap markers together before the query and again after it. Changed, unreadable or newly invalid inputs discard the provider result; cancellation discards it too. A disabled preference does not request access or query data.
- The result retains the queried window, current local assessment, check time and conflict-aware provider snapshot. Empty observations remain unavailable; observed all-awake coverage can show zero sleep. Show sleep, awake, unmeasured and conflicting minutes separately, using the existing consensus calculation. A returned snapshot for different bounds is rejected. This is a point-in-time check, not continuous provider monitoring, durable import, permission proof or a new source for existing chart/export totals. Editing bounds, local record notifications, preference changes and leaving the active view clear the displayed check. DOSETAP-57 markers and shared report integration remain open.

- Reviewed-window assessment, DOSETAP-56: recheck saved bounds against current medication rows, other saved reviewed windows and recorded nap markers. A missing window stays missing. Invalid/contradictory doses, a taken dose outside `[start,end)`, overlapping reviewed identities, ambiguous/incomplete overlapping naps or unreadable evidence require review. The storage adapter uses the existing dose-alias canonicalizer without rewriting rows. Skipped outcomes must have finite, nonfuture timestamps at or after Dose 1, but are not taken doses subject to the window bounds. Missing Dose 2 does not mean skipped and does not itself invalidate an observation window. Missing nap endpoints are never filled from the clock, session closure or another session's events.
- The assessment is read-only and recalculated on request; it never edits the saved window or medication records. All ledger event timestamps must be finite and nonfuture; snoozes require one Dose 1 and cannot precede it. Snoozes and correction audit events are not administrations and do not need to lie inside the observation window. A `checked` result means these local boundary checks passed at that assessment time, not that provider coverage is complete or that a dosing action is appropriate. Unknown nap endpoints conservatively require review when their possible interval could overlap the window. It is not a durable validity certificate; future async provider consumers must recheck current input snapshots before publishing results.
- Assessment reads use a SQLite read snapshot and fail closed on statement, decoding or partial-read errors. Bundle exports read and decode shared window/nap evidence once for their selected nights in one assessment snapshot; no cache survives the batch. Per-night snapshot failures affect that night's assessment, not other readable nights. Unreadable shared evidence still prevents checking saved windows; a separately verified absent window stays missing. Nap timestamp parsing accepts supported ISO formats without substituting the clock. Wake & Next Day shows the saved assessment and reasons, refreshes after record changes, and offers a manual recheck. Changed drafts do not inherit a saved-window check. Collected-night JSON/CSV and Studio carry the assessment version/status/reasons and assessment UTC time; the time uses existing safe-report redaction. No raw record identifiers enter these new report fields. Other diary saves remain allowed; an assessment warning does not alter medication, alarms or existing sleep totals.

- Bounded evidence reconciliation, DOSETAP-56: the opt-in query retains original sample bounds/category, sample UUID, source bundle/name/revision, optional device description, provider timezone metadata and query receipt time before clipping. These records stay in the returned snapshot, not a new persisted ledger or public export. Missing metadata is not inferred. Query receipt time is not consumption, sleep onset or permission proof.
- `SleepEvidenceResolution` uses a conservative consensus policy for bounded queries only. Compatible unspecified-asleep and one detailed sleep stage may agree; differing detailed stages, sleep versus awake, and a known classification overlapping an unknown category remain conflicts. In-bed evidence is context, not a competing sleep/awake classification. Conflicted slices contribute to unmeasured time, never sleep or awake. Raw observations remain available for review; no source is ranked by name or claimed more accurate. Duplicate/reordered evidence cannot change measured durations or conflict intervals. Existing primary-episode charts and the legacy post-dose estimator retain their existing policies until consumer integration.
- The conflict-aware result carries resolved slices with supporting sample IDs, conflict duration, coverage and a derivation version. The coverage-only adapter uses those resolved slices. No query result is persisted or used to update dose/alarm/session state. Fresh bounded queries reflect currently returned provider samples; durable deletion/revision reconciliation, saved-window versus dose/nap/session validation and cross-screen/report integration remain open.

- Reviewed night window, DOSETAP-56: the existing night-outcome diary may hold an optional `reviewedSleepWindow`, independently of final awakening. Its version-1 record stores stable session identity, absolute start/end, explicit user-review source and review time, entry timezone and that zone's UTC offsets at both bounds. Entry timezone records how the dates were reviewed, not proof of the person's location during sleep. Finite, ordered, past bounds and matching session identity are required. Existing records without this field remain unanswered.
- Window saves use the existing night-outcome transaction and stale-snapshot checks. Correcting or clearing an existing window requires a reason and retains it in prior answers. Other diary edits and explicit Dose 2 wake recording preserve the window. No dose, alarm, active-session, provider record or final-awakening answer is created or changed by window entry. Source/nap/session conflicts still need resolution before these bounds drive treatment-night totals; saving a window alone does not certify those inputs.
- A Dose 2 wake-answer write validates the resulting diary against its supplied entry time before commit. A backdated occurrence cannot substitute for a later entry time if that would invalidate already reviewed observations. Failure rolls back the pending dose and wake write together, leaving the prior diary readable; no timestamp is silently moved forward.
- Wake & Next Day exposes optional window entry with both date/time bounds, entry-zone label and explicit review confirmation. Suggestions from actual Dose 1 and an answered final wake are drafts only; no current-clock/session-lifetime fallback is saved as a night window. Cancel saves nothing. Unchanged saved bounds keep their original review metadata; changed bounds need fresh confirmation. Clearing retains correction history. The versioned collected-night JSON, CSV and Studio reports carry the reviewed window separately from all sleep estimates, with timestamp/entry-zone redaction in safe Studio reports. Existing charts and sleep totals are unchanged pending source/conflict integration.
- Bounded interval coverage, DOSETAP-56: `SleepIntervalCoverage` measures caller-supplied absolute start/end instants, clipping and unioning all eligible recorded intervals without a largest-cluster filter. It reports sleep, awake, classified coverage and unmeasured time separately. Empty coverage is unavailable with missing sleep/awake totals; fully observed awake time is valid zero sleep. Invalid/non-finite windows are rejected. This utility does not choose or persist a treatment-night window.
- `HealthKitService.fetchSleepCoverage(from:to:)` is an opt-in bounded query using overlapping samples, including samples that begin before the requested start. It delegates to `fetchSleepEvidence(from:to:)` and the consensus policy above, excluding unresolved conflicts, in-bed and unknown categories from classified coverage. Wake & Next Day's saved-window check uses the rich evidence query and rejects malformed observations or mismatched returned bounds. Existing primary-episode queries, charts and export totals are unchanged; durable source reconciliation and shared consumer/report integration remain open under DOSETAP-56.
- The existing post-Dose-2 estimator delegates interval arithmetic to this shared utility while preserving its awake-over-asleep overlap rule, optional result and existing coverage-gap display tolerance. New coverage status itself discloses any positive unmeasured interval. Source conflict resolution must happen before calling this measured-interval utility; it is not an accuracy policy.
- Boundary correction, DOSETAP-56: the existing primary-episode summary uses the last observed asleep end for its final-wake estimate, not the end of trailing awake/in-bed observations. It retains a separate observation end and records whether contiguous awake evidence supports that boundary or it is only a last-observed-sleep-end estimate. This remains a primary-episode summary, not a reviewed treatment-night total.
- Unknown HealthKit sleep categories remain unclassified and retain their raw category value in adapter segments. Valid unspecified-asleep remains sleep. Unknown observations cannot supply asleep/awake duration; in-bed-only and unknown observations do not become awake chart bands. Raw-category preservation is not yet a complete sample/source revision ledger.
- Equal-priority normalized slices choose the lexically first source display name and then lowest raw category value. This stable tie-break makes reordered identical evidence reproducible; it is not a source-accuracy ranking or full conflict/provenance resolution.
- Derivation metadata identifies this boundary correction separately from older unversioned reports. Full reviewed-night aggregation, durable source reconciliation and wider marker adoption remain planned in `docs/plans/2026-09-09-sleep-timing-calculation-addendum.md` under DOSETAP-56/57. No medication, alarm or session mutations are introduced.

- HealthKit status lookup must not block repository or UI initialization. Synchronous provider status calls run away from the main actor; until they return, the app preserves its unresolved status and medication screens remain usable.

- Preference: `UserSettingsManager.healthKitEnabled` (user intent).
- Authorization: `HealthKitService.authorizationStatus` and `HealthKitService.isAuthorized` (system grant).
- The app must treat these as separate states. Preference may be ON when authorization is missing, and UI must prompt without clearing preference unless explicitly disabled.

Code references:
- `ios/DoseTap/HealthKitService.swift`
- `ios/DoseTap/HealthKitSettingsView.swift`

---

## State Machines and Transitions

### Dose Flow State Machine

States (from `DoseWindowPhase` in `ios/Core/DoseWindowState.swift`):
- `noDose1`
- `beforeWindow`
- `active`
- `nearClose`
- `closed`
- `finalizing` (wake final logged, awaiting check-in)
- `completed`

Key transitions:
- `noDose1` -> `beforeWindow`: Dose 1 taken.
- `beforeWindow` -> `active`: 150 minutes elapsed since Dose 1.
- `active` -> `nearClose`: remaining <= 15 minutes.
- `nearClose` -> `closed`: 240 minutes elapsed since Dose 1. This transition performs no medication write.
- `active|nearClose` -> `completed`: Dose 2 prospectively recorded or Dose 2 explicitly skipped.
- `closed` -> `completed`: the user explicitly records an occurrence that already happened or marks Dose 2 missed / not taken.
- `any` -> `finalizing`: wake final logged; check-in pending.
- `finalizing` -> `completed`: morning check-in submitted.

Snooze rules (authoritative):
- Snooze is enabled ONLY in `active` phase AND `snoozeCount < maxSnoozes` (default 3).
- Snooze is disabled in `nearClose` phase (remaining < 15 minutes) regardless of count.
- Snooze is disabled in all other phases (`noDose1`, `beforeWindow`, `closed`, `completed`, `finalizing`).
- All surfaces (UI buttons, Flic, deep links) MUST use `DoseWindowContext.snooze` enum to enforce these rules — not manual boolean checks.
- Persistence MUST also fail closed if there is no open active session with Dose 1, if Dose 2 is already taken, if Dose 2 is skipped, or if session rollover closes the session during snooze preflight.

Skip rules (authoritative):
- Skip is enabled only in `active`, `nearClose`, and `closed` phases.
- Skip is blocked in `beforeWindow` with the canonical reason `Dose 2 window has not opened`; no route may mutate state before the window opens.
- `DoseRegistrationPolicy.evaluateSkip` owns eligibility for every surface. `DoseWindowContext.skip` derives its presentation state from that same policy.
- A committed skip event records the initiating `RegistrationSurface` in its metadata when the action came through the coordinator.

Deep link authorization rules (authoritative):
- State-changing deep links (`dose1`, `dose2`, `snooze`, `skip`, `log`) require the app to be in the foreground and protected data to be available.
- A Dose 2 deep link after the window closes is blocked as a prospective action and directs the user to the in-app historical record flow. Extra-dose actions require confirmation UI before persisting.
- `log` deep links are for sleep and quick-log events only. Dose names such as `dose1`, `dose2`, `extra_dose`, `dose2_skipped`, and `snooze` must be rejected by `log` and routed through the dose action links.

Transition table (subset):

| Current | Trigger | Guard | Writes | Next |
| --- | --- | --- | --- | --- |
| `noDose1` | Take Dose 1 | none | `saveDose1` + `dose_events` + schedule alarms | `beforeWindow` |
| `beforeWindow` | Take Dose 2 | requires early override | `saveDose2(is_early)` + cancel alarms | `completed` |
| `active` | Take Dose 2 | none | `saveDose2` + cancel alarms | `completed` |
| `nearClose` | Take Dose 2 | none | `saveDose2` + cancel alarms | `completed` |
| `closed` | Record Dose 2 already taken | actual time selected; outside-window warning confirmed | `saveDose2(actual_time, entry_mode=retrospective)` + cancel alarms | `completed` |
| `active\|nearClose\|closed` | Skip Dose 2 | none | `saveDoseSkipped` + cancel alarms | `completed` |
| `active` | Snooze | open active Dose 1 session, no Dose 2, no skip, count < max | `saveSnooze` + reschedule alarm, rollback if alarm fails | `active` |
| `any` | Wake Final | none | `insertSleepEvent(wake_final)` | `finalizing` |
| `finalizing` | Submit Check-In | none | `saveMorningCheckIn` + `closeSession` | `completed` |

ASCII diagram:

```
noDose1
  | takeDose1
  v
beforeWindow --(150m)--> active --(<=15m left)--> nearClose --(>240m, no write)--> closed
   | takeDose2 (early override)        | takeDose2                       | record actual occurrence
   v                                   v                                 | or explicitly mark missed
completed <----------------------------+---------------------------------+
   ^
   | skipDose2
   |
finalizing --(check-in complete)--> completed
```

Code references:
- `DoseWindowCalculator.context(...)`
- `DoseRegistrationPolicy.evaluate(...)`
- `DoseActionCoordinator.takeDose1(...)`
- `DoseActionCoordinator.takeDose2(override:...)`
- `DoseActionCoordinator.recordDose2Occurrence(at:warningConfirmed:...)`
- `DoseActionCoordinator.snooze(...)`
- `DoseActionCoordinator.skipDose(...)`
- `SessionRepository.setDose1Time(_:)`
- `SessionRepository.setDose2Time(_:isEarly:isExtraDose:)`
- `SessionRepository.incrementSnoozeIfActive()`
- `SessionRepository.skipDose2()`

### Session Rollover State Machine

States:
- `active` (session open, end_utc == nil)
- `finalizing` (wake final logged, check-in not completed)
- `closed` (end_utc set)

Transitions:
- `active` -> `finalizing`: wake final logged.
- `finalizing` -> `closed`: morning check-in saved.
- `active|finalizing` -> `closed`: missed check-in cutoff reached.
- `active|finalizing` -> `closed`: prep-time soft rollover reached.

ASCII diagram:

```
active --(wake final)--> finalizing --(check-in submit)--> closed
  |                                   |
  | (prep time)                       | (missed check-in cutoff)
  +-------------------------------> closed
```

Code references:
- `SessionRepository.setWakeFinalTime(_:)`
- `SessionRepository.completeCheckIn()`
- `SessionRepository.evaluateSessionBoundaries(reason:)`
- `SessionRepository.closeActiveSession(at:terminalState:reason:)`

---

## Event Flow (UI -> Domain -> Storage -> Diagnostics -> UI)

Dose 1 example:

```
CompactDoseButton.takeDose() (ios/DoseTap/Views/CompactDoseButton.swift)
  -> DoseActionCoordinator.takeDose1()
    -> DoseRegistrationPolicy.evaluate(...)
    -> SessionRepository.setDose1Time(_:) (ios/DoseTap/Storage/SessionRepository.swift)
      -> EventStorage.saveDose1(...) (ios/DoseTap/Storage/EventStorage+Dose.swift)
      -> DiagnosticLogger.logDoseTaken(...) (ios/Core/DiagnosticLogger.swift)
      -> SessionRepository.sessionDidChange.send()
         -> UI redraw via Combine subscription
```

Dose 2 retrospective example:

```
ExpiredDose2ResolutionSheet (ios/DoseTap/Views/SessionSupportViews.swift)
  -> DoseActionCoordinator.recordDose2Occurrence(at:warningConfirmed:...)
    -> DoseRegistrationPolicy.evaluateRetrospectiveDose2(...)
    -> SessionRepository.setDose2Time(actualTime, entryMode: .retrospective, recordedAt: ...)
      -> EventStorage.saveDose2(..., entry_mode: retrospective) (ios/DoseTap/Storage/EventStorage+Dose.swift)
      -> DiagnosticLogger.logDoseTaken(..., doseIndex: 2, isLate: true)
      -> sessionDidChange -> UI updates
```

Sleep event example:

```
Quick Log button (ios/DoseTap/Views/QuickEventViews.swift)
  -> EventLogger.logEvent(...) (ios/DoseTap/EventLogger.swift)
    -> SessionRepository.insertSleepEvent(...)
      -> EventStorage.insertSleepEvent(...)
      -> DiagnosticLogger.logSleepEventLogged(...)
      -> sessionDidChange -> UI updates
```

---

## Navigation and Layout (Adaptive)

The app uses an adaptive navigation pattern based on horizontal size class:

- **Compact** (iPhone portrait, iPhone landscape): Swipeable `TabView(.page)` with a custom `CustomTabBar` at the bottom. 5 tabs: Tonight, Timeline, History, Dashboard, Settings.
- **Regular** (iPad, large iPhone landscape): `NavigationSplitView` with a sidebar listing all 5 sections. The selected section's content appears in the detail column. Each tab's view uses `NavigationStack` for internal push navigation.

Environment key `isInSplitView` (from `AdaptiveLayouts.swift`) signals child views whether they are embedded in a `NavigationSplitView` detail column. When `true`, child views skip their own `NavigationView`/`NavigationStack` wrapper since the split view provides the navigation context. When `false` (default, compact), they wrap themselves.

Wide-layout adaptations:
- **Dashboard**: 2-column `LazyVGrid` when `isWideLayout` (already present).
- **Tonight**: Side-by-side layout — dose controls on the left, quick event log on the right — when `horizontalSizeClass == .regular`.
- **History**: Side-by-side calendar picker (left) and selected day detail (right) on iPad.
- **Timeline/Settings**: Benefit from wider content area; no structural change needed.

Compact History insights use one row of four metrics at standard text sizes, with wrapping labels. Larger accessibility text and detailed definitions use fewer columns. Tonight uses one outer horizontal inset and no duplicate tab-bar spacer. The ready-for-tonight layout, including a previous-night reminder and the weekly summary, should fit a standard portrait phone without incidental scrolling. Scrolling remains available for smaller screens, larger text, additional logs, and safety warnings; controls and warnings must never be clipped to force a fit.

Tab selection is synced between compact (TabView `$urlRouter.selectedTab`) and regular (sidebar selection `$urlRouter.selectedTab`) layouts. Deep links work identically in both modes.

All five tabs use native navigation headers, with inline titles on compact screens. The shared toolbar places the theme quick switch at the leading edge and current-page capture at the trailing edge. Capture is available in Timeline Live and Review, including empty states. History's record editor and Dashboard's refresh/sync controls remain contextual actions beside capture. Timeline's separate review-summary capture stays in the Review content. Tonight keeps its session date and dose/alarm information below the header. Titles remain below the system status area, and scrolling stays available for larger text.

Code references:
- `ios/DoseTap/ContentView.swift` (adaptive root)
- `ios/DoseTap/Views/AdaptiveLayouts.swift` (environment key, sidebar, helpers)
- `ios/DoseTap/URLRouter.swift` (`AppTab` enum, `selectedTab`)

---

## Appearance

### Automatic Night Mode (DOSETAP-48)

- Automatic Night Mode is enabled by default and can be disabled in Settings → Theme. It changes DoseTap's appearance only, not device brightness, Focus, alarms, or medication state.
- A committed Dose 1 in the open active session enables the existing red/amber theme until that treatment night's Sleep Plan `Wake by` instant (including its nightly override). Dose 2, skips, and brief wakes do not end it. Explicit final wake, session closure, or removing/undoing Dose 1 ends it early.
- The saved manual appearance is preserved during automation and restored at wake-up. Selecting a theme manually overrides automation for that session, including across app restart; the next session can automate again. Turning automation off restores the saved appearance; turning it back on explicitly resumes eligibility.
- Launch, foreground, committed session changes, and the visible clock reconcile appearance from current session state. Historical-only records and failed/unconfirmed medication actions cannot start it. While visible, the wake boundary is checked once per second; after suspension it is checked on foreground, without requiring background execution.
- Quick Log events and all dosing confirmation/hold behavior remain unchanged.

## Time Boundary Model

- All timestamps are absolute `Date` instants stored as ISO8601 strings.
- `session_date` is a grouping key derived from `sessionKey(for:timeZone:rolloverHour:)` with default rollover 18 (6 PM). It is not the session boundary.
- Cross-midnight rule: events after midnight remain in the open session until it is closed by morning check-in or fallback cutoff.
- Interval math uses absolute timestamps with a single midnight rollover allowance. See `TimeIntervalMath.minutesBetween(start:end:)` in `ios/Core/TimeIntervalMath.swift`.
- Timezone changes: `SessionRepository` listens for time change notifications and reloads state via `updateSessionKeyIfNeeded(reason:)`.

---

## Durable quick logs and general medication entry (DOSETAP-3/39)

Quick-log success, list insertion, cooldown and haptics follow a committed SQLite write. A new active session and its first quick log commit together; failed writes leave both absent. Final wake and its finalizing state also commit together. Failed manual entries retain their fields, while a failed quick tap retains its occurrence for an explicit same-session retry. If that session changes, retry is cleared, the unsaved occurrence stays visible for History review, and new quick logs remain usable. Alternate final-wake logs share the finalizing transaction. Siri, deep links and Flic report failure instead of success. Medication names remain outside the quick-log route.

General medication entries report storage failure separately from duplicate review. The picker retains unsaved entries and explicit duplicate consent, removes only committed entries from a partially saved batch, and dismisses only when every entry commits. Retrying a failed batch must not replay its saved prefix. These entries do not change Dose 1/2 state or alarms. Deletion/edit failure handling, export preservation and staging sync acceptance remain separate work.

## Storage and Persistence Truth

Studio export 2.4 (DOSETAP-13) preserves stored general-medication units,
formulation, session identity, offset, duplicate confirmation and original
occurrence/creation timestamp text. Current medication configuration must not
reconstruct historical facts. Inventory export reads every stored snapshot with
its ID and medication name; its notes remain unchanged and source is a separate
column. These two export reads reject unreadable rows/SQLite failures instead of
publishing a partial result. They do not certify other export reads or a complete
database backup. Older Studio bundles retain missing provenance as missing.

Persistence is local SQLite via `EventStorage`.

The executable schema is `EventStorage.createTables()` in `ios/DoseTap/Storage/EventStorage+Schema.swift`, including the SQLite `user_version` and internal `schema_migrations` ledger. `docs/DATABASE_SCHEMA.md` and `docs/SSOT/contracts/DataDictionary.md` contain the field-by-field inventory and must move with that source. Do not duplicate mutable schema versions, table totals, or partial table lists in this overview.

Symptom source identity:
- `pre_sleep_logs` and `morning_checkins` remain the source rows for questionnaire context.
- Structured pain entries in those source rows derive rebuildable `symptom_events` using `source + source_record_id + source_entry_key`.
- Editing, clearing, syncing, or deleting a source row must replace or clear that row's derived symptom events and rebuild `symptom_summaries`.
- Pre-sleep and morning source-row writes, normalized `checkin_submissions` writes, and derived symptom replacement or clearing must commit in the same local SQLite transaction. Partial source-only or symptom-only commits are invalid.
- Once a morning form's medication reconciliation commits, later questionnaire retries must not repeat it or overwrite newer medication corrections. The retained form replaces medication controls with a saved-status explanation; further medication changes use History. Questionnaire answers remain editable for retry.

CloudKit delete tombstones:
- CloudKit-tracked deletes must enqueue the matching `cloudkit_tombstones` row in the same local SQLite transaction as the local row delete.
- If tombstone queueing fails, the local delete must fail closed and leave the local source row in place.
- Remote sync imports call delete paths with tombstone queueing disabled to avoid echoing inbound remote deletes back into the outbound queue.

Data retention:
- App restart: data persists.
- App uninstall: iOS deletes the sandbox; all local data is lost.
- Manual export: Settings -> "Export Data (CSV)" writes a file to Files.
- Shipping `DoseTap` target: CloudKit is disabled by build configuration and uses local entitlements.
- `DoseTapStaging` target: a quarantined CloudKit implementation exists for validation. Hosted round-trip, conflict, privacy, and delete-convergence evidence remain open; it is not a shipping backup guarantee.

---

## Manual history and reviewed corrections (DOSETAP-47)

- History exposes Add / Correct Records for the selected treatment night, even when no record exists. Manual entry records an occurrence already past; it is never permission to take medication now. Apple Health and WHOOP observations remain read-only.
- History also exposes the full pre-sleep and morning questionnaires for the explicitly selected treatment night, including nights without dose records. Each add/correction requires a reviewed past occurrence time, reason, and confirmation; the actual submission time is retained separately. Existing answers and their prior revisions are preserved in questionnaire provenance. Conflicting identities or concurrent changes fail closed. Questionnaire-only saves do not reconcile medication, write remembered defaults or wake overrides, schedule alarms, or complete the active session. Cancel leaves both questionnaires and medication unchanged.
- Dose 1, Dose 2, explicit missed/not-taken outcomes, and extra doses may be added or corrected with an actual timestamp, a reason, and explicit confirmation. Early/late occurrences remain recordable with an accuracy warning, not an arbitrary retrospective interval cap. Future or reversed timestamps and contradictory/duplicate primary outcomes are rejected. Dose 1 is never inferred from Dose 2.
- An erroneous medication row may be removed from the effective record only after review. Its original contents remain in a non-dose `history_correction` audit event. Removing a row does not mean skipped; dependent doses must be corrected first. Replacements preserve original metadata and correction chains.
- The standard CSV includes the medication event ledger and metadata, including extra doses and non-dose correction evidence, instead of only primary-dose projections. This still is not a whole-project backup.
- A save is tied to the reviewed session identity and original rows. Stale or ambiguous reviews fail without writing; no date-only fallback may select another session. Empty-night entries create an isolated historical identity, never a new active session.
- Manual quick-log events are available for the selected past night, not just the preceding 24 hours. Failed writes keep the editor open. Medication and sleep history changes publish only after transaction commit.
- Historical edits do not reopen sessions or affect unrelated alarms. An edit to the active medication record invalidates pending consent and reconciles its alarms from the updated state; a saved record and a failed alarm side effect must be reported separately.

## Dose 2 wake and next-day diary (DOSETAP-49)

- Explicit Dose 2 wake method is Natural, Alarm, Other or Unknown; backup-alarm setup is an independent optional answer. Natural waking before a backup alarm remains Natural. Alarm delivery, snoozes, timestamps and missing answers never imply a wake method or a medication event.
- Dose 2 confirmation offers mutually exclusive Natural / Alarm checkboxes, initially unanswered. Selecting, cancelling or backgrounding does not persist a choice or record medication. The confirmed dose and its selected wake answer commit in one transaction, including early-hold and retrospective occurrence entry. The morning check-in and History review the same `night_outcome.v1` answer, not a duplicate morning-only answer; final morning awakening remains a separate question.
- A session-bound night-outcome submission records wake details, optional final awakening, following-day Workday/Day off/Unknown, and an optional personal 0–10 sleepiness rating with assessment time. It does not replace the legacy 1–5 morning-questionnaire field or represent a validated clinical score. Epworth is not a per-night outcome.
- Outcome saves cannot write medication, finish a session, or schedule alarms. Stale dose/session or outcome snapshots fail without writing. Revisions retain prior answers and require a reason when an already answered value is changed; filling an unanswered field is a new observation. History exposes the same diary for an existing selected night.
- Estimated sleep after Dose 2 sums the union of recorded asleep intervals clipped between the actual second dose and final awakening, subtracting recorded awake intervals. It does not count elapsed time, in-bed time or provider totals as sleep segments. Missing segment data is unavailable, never zero. Coverage gaps remain unmeasured and are disclosed; WHOOP totals alone cannot supply this estimate.
- The natural-versus-alarm comparison shows medians, usable sample counts and expandable middle-50% ranges, with Other/Unknown visible separately and an explicit following-day filter. Missing outcomes remain distinct from confirmed skipped/missed doses. Descriptive differences are not medication-effectiveness or causation claims.
- Comparison groups use the explicit session-bound wake diary only. Legacy morning-questionnaire wake fields may be carry-forward defaults and cannot distinguish an explicitly reconfirmed answer; they remain preserved but are not silently treated as verified wake-method observations. Older nights can be confirmed through History.
- Studio uses the version-1 collected-night Dose 2 wake answer for wake labels, tags, cohorts, trend counts and report calculations. Unknown, unsupported versions and nights without a recorded Dose 2 cannot become Natural or Alarm from legacy fields or alarm diagnostics. Other remains distinct. Legacy context stays available in raw exports for review.
- A recorded following-day Workday, Day off or Unknown answer overrides Studio's legacy work/off context for grouping and filters. Older bundles without this answer retain their separate legacy context; it is not filled into the diary. Natural-wake scoring requires a recorded Natural or Alarm answer. Unanswered/Other wake methods do not enter that score or its denominator.
- Studio's older composite timing score remains an exploratory legacy measure, not a validated outcome or dosing/driving recommendation. Its existing 1–5 questionnaire inputs are not replaced or combined with the personal 0–10 sleepiness rating or post-Dose-2 sleep estimate. Timing reports disclose that distinction and carry the collected diary fields alongside the legacy score, with the same redaction rules as the night CSV.
- History's Natural Wake percentage also uses explicit Dose 2 wake answers, dividing Natural by answered Natural/Alarm/Other nights. Unknown and unreadable answers do not enter that denominator. No answered nights is unavailable, not zero; a zero-snooze night is never assumed to be a natural wake.

## Known Limitations (Truth, Not Plans)

- Recent owner-reported Dose 2 actions did not reach the retained durable-write path. Prospective commit-gated writes and diagnostics are implemented, but reviewed recovery and signed-device registration/restart evidence remain open under DOSETAP-34 and DOSETAP-38.
- Apple Health authorization, no-data, real-data, and same-night cross-screen parity still require signed-device verification under DOSETAP-10.
- The app displays the current named timezone, but historical rows do not yet persist complete named-zone provenance. Physical timezone-change and DST evidence remain open under DOSETAP-37.
- Whole-project Clear All Data and content-equal backup/restore are incomplete. Export must not be described as a full backup until DOSETAP-39 closes.
- Live WHOOP OAuth, token refresh, approved-account data, and production token-exchange handling remain unverified.
- Nap overlap is not prevented. Pairing uses the first start with the next end.
- Sleep event `event_type` strings are not normalized across every UI and deep-link path.

---

## HealthKit Interaction Diagram

```
User Settings Toggle
  -> UserSettingsManager.healthKitEnabled (preference)
     -> HealthKitService.checkAuthorizationStatus()
        -> isAuthorized

If preference ON and not authorized:
  -> HealthKitService.requestAuthorization()
  -> Update isAuthorized
  -> If authorized, keep preference ON and allow queries
```

Code references:
- `HealthKitService.requestAuthorization()`
- `HealthKitService.checkAuthorizationStatus()`
- `HealthKitSettingsView` (Settings)
- `LiveSleepTimelineView` (Timeline)

---

## Alarm and Notification System

### Notification Identifiers (Canonical)

All session-scoped notification identifiers use the `dosetap_` prefix. These are defined in `AlarmService.NotificationID` and mirrored in `SessionRepository.sessionNotificationIdentifiers`.

| Identifier | Scheduled By | Purpose |
| --- | --- | --- |
| `dosetap_dose2_alarm` | `AlarmService.scheduleDose2Alarm(at:dose1Time:)` | Primary wake alarm at the absolute target deadline |
| `dosetap_dose2_pre_alarm` | `AlarmService.scheduleDose2Alarm(at:dose1Time:)` | 5-minute pre-alarm warning |
| `dosetap_followup_1` | `AlarmService.scheduleDose2Alarm(at:dose1Time:)` | Follow-up alarm +2 min |
| `dosetap_followup_2` | `AlarmService.scheduleDose2Alarm(at:dose1Time:)` | Follow-up alarm +4 min |
| `dosetap_followup_3` | `AlarmService.scheduleDose2Alarm(at:dose1Time:)` | Follow-up alarm +6 min |
| `dosetap_second_dose` | `AlarmService.scheduleDose2Reminders(dose1Time:)` | Dose 2 window opening reminder |
| `dosetap_window_15min` | `AlarmService.scheduleDose2Reminders(dose1Time:)` | 15-minute window closing warning |
| `dosetap_window_5min` | `AlarmService.scheduleDose2Reminders(dose1Time:)` | 5-minute final warning (critical) |

Cancellation:
- `SessionRepository.cancelPendingNotifications()` cancels all identifiers in `sessionNotificationIdentifiers`.
- `AlarmService.cancelAllAlarms()` cancels the same set via `UNUserNotificationCenter`.
- `AlarmService.cancelWakeAlarms()` cancels only the wake-alarm role group.
- `AlarmService.cancelDose2Reminders()` cancels window reminder identifiers specifically.

### Verified Scheduling and Absolute-Deadline Semantics

- Medication alarm intent is an absolute `Date`, not a wall-clock time that moves when the device timezone changes.
- The persisted reconstruction record includes Dose 1, the absolute wake deadline, the origin and last-reconciled named timezones, snooze count, verification flags, and expected request IDs.
- Calendar triggers use the target timezone's fixed UTC offset at each requested instant. This disambiguates the repeated daylight-saving fall-back hour; the named timezone remains recorded separately as provenance.
- `scheduleDose2Alarm` and `scheduleDose2Reminders` return a typed result. A group is marked scheduled only after every required request is added and the exact pending set, trigger instant, fixed offset, and named-zone provenance are verified.
- A partial add or verification mismatch rolls back the entire affected role group. Denied or undetermined authorization fails closed and is visible through `lastSchedulingError`.
- Persisted verification flags are not treated as runtime proof after launch. App activation, significant-time changes, timezone changes, and manual retry reconcile persisted intent against actual pending requests.
- The alarm indicator displays the absolute deadline, the last reconciled named timezone, degraded scheduling status, and a manual retry action.
- Snooze replaces only wake-alarm roles. Still-future window-open/15-minute/5-minute safety reminders remain pending; reminders that have become stale are removed deterministically.

The complete normative contract and failure table are in `docs/SSOT/alarm-scheduling.md`.

Code references:
- `ios/DoseTap/AlarmService.swift` (scheduling, cancellation, notification categories)
- `ios/DoseTap/Storage/SessionRepository.swift` (`sessionNotificationIdentifiers`, `cancelPendingNotifications()`)

### Critical Alerts Entitlement

The app supports the `com.apple.developer.usernotifications.critical-alerts` entitlement for time-sensitive dose reminders that must bypass Do Not Disturb and Silent Mode.

- Capability gating: `AlarmService.canUseCriticalAlerts` checks both `UserSettingsManager.criticalAlertsEnabled` AND the `CriticalAlertsCapabilityEnabled` Info.plist flag. If either is false, notifications fall back to `.timeSensitive` interruption level.
- Entitlements files (`DoseTap.Cloud.entitlements`, `DoseTap.Local.entitlements`): add the `com.apple.developer.usernotifications.critical-alerts` key only after Apple approves the entitlement request.
- 5-minute final warning (`dosetap_window_5min`) and wake alarms use `.critical` interruption level when `canUseCriticalAlerts` is true.
- All other notifications use `.timeSensitive` interruption level.

### Notification Permission Recovery

If the user enables notifications in Settings but iOS authorization is `.denied`:
1. `SettingsView` detects the mismatch via `validateNotificationAuthorization()`.
2. Resets `settings.notificationsEnabled = false`.
3. Shows an alert explaining the issue with a button to open iOS Settings (`UIApplication.openSettingsURLString`).

If authorization is `.notDetermined`:
1. Requests permission via `AlarmService.requestPermission()`.
2. If denied, resets preference and shows alert.

Code references:
- `ios/DoseTap/SettingsActions.swift` (`validateNotificationAuthorization()`, `openSystemNotificationSettings()`)

---

## Channel Parity (Dose Entry Surfaces)

All dose entry channels MUST use the same policy, transactional persistence, notification, diagnostics, and feedback boundary for the same action. This is a patient-safety invariant.

Entry surfaces:
1. **Tonight UI**: `CompactDoseButton` and `SessionSupportViews`
2. **Deep link**: `URLRouter`, for example `dosetap://dose1` and `dosetap://dose2`
3. **Hardware button**: `FlicButtonService`

`DoseActionCoordinator` is the single action entry point. It applies `DoseRegistrationPolicy`, commits through `SessionRepository`, records outcome-accurate diagnostics, and then performs the applicable notification work. A committed medication event with a failed notification side effect returns `attentionRequired`; a persistence failure returns retry guidance and must not publish success.

Required outcomes:

| Action | Required committed state | Notification outcome | Confirmation boundary |
| --- | --- | --- | --- |
| Take Dose 1 | Dose 1 event and active-session projection agree | Schedule the absolute wake alarm and window reminders; surface any scheduling failure after preserving the committed Dose 1 | Policy must allow the first dose; explicit reviewed occurrence and reminder confirmation required |
| Take Dose 2 | Dose 2 event and active-session projection agree | Cancel the applicable wake and window notifications after commit | Early, late, after-skip, and extra-dose paths require the matching explicit confirmation |
| Skip Dose 2 | Durable skip outcome for the active session | Cancel the applicable wake and window notifications after commit | Block before the window opens |
| Extra dose | New event with index 3 or greater; do not replace Dose 2 | Do not alter Dose 2 projection | Require explicit extra-dose confirmation |
| Snooze | Durable snooze count and intent remain consistent | Replace only the wake-alarm role group and retain future safety reminders | Allow only in the policy-approved active phase |

Code references:
- `ios/DoseTap/Views/CompactDoseButton.swift`
- `ios/DoseTap/Views/SessionSupportViews.swift`
- `ios/DoseTap/URLRouter.swift`
- `ios/DoseTap/FlicButtonService.swift`
- `ios/DoseTap/DoseActionCoordinator.swift`

---

## WHOOP Integration

### Feature Flag

`WHOOPService.isEnabled` is a dynamic computed property reading `UserDefaults("whoop_enabled")`.

State transitions:
- **On connect:** `authorize()` sets `UserDefaults("whoop_enabled") = true` after successful OAuth token exchange.
- **On disconnect:** `disconnect()` sets `UserDefaults("whoop_enabled") = false` and clears Keychain tokens.
- **Migration (init):** If tokens exist in Keychain but `whoop_enabled` is `false`, auto-sets to `true`.
- There is no hardcoded kill switch.

### OAuth and Token Refresh

- OAuth runs through `ASWebAuthenticationSession` with PKCE.
- Generated OAuth `state` values are 8-character URL-safe strings to match WHOOP's documented constraint.
- Required scopes are `offline`, `read:recovery`, `read:sleep`, `read:cycles`, and `read:profile`.
- Access-token refresh requests are serialized through one in-flight refresh task. This avoids racing WHOOP's rotating refresh tokens when multiple views fetch data after token expiry.
- Refresh requests include `scope=offline`.
- On API `401`, the app attempts one serialized refresh before disconnecting.
- Current iOS code still needs `SecureConfig.shared.whoopClientSecret` for WHOOP token exchange. Production builds must provide it through a secure server-side token broker or another secure injection path. Do not ship a plaintext client secret in source or logs.

### Data Surface Gating

All WHOOP data display is gated behind `WHOOPService.isEnabled` and/or data presence checks:
- **Dashboard:** WHOOP measurements appear only with recorded WHOOP nights; otherwise its card explains the missing data and connection/range checks. Recovery and HRV appear in the WHOOP card with observed sample counts and as compact Overview summaries, all using the same provider aggregates.
- **Timeline:** `extractBiometricData()` returns empty arrays when `!WHOOPService.isEnabled`.
- **Night Review:** `HealthDataCard` WHOOP section guarded behind `WHOOPService.isEnabled`.
- **Sleep Snapshot:** WHOOP Metrics section guarded behind `averageWhoopRecovery != nil || averageWhoopHRV != nil`.

Code references:
- `ios/DoseTap/WHOOPService.swift` (`isEnabled`, `authorize()`, `disconnect()`)
- `ios/DoseTap/WHOOPSettingsView.swift` (connect/disconnect UI and configuration gate)
- `ios/DoseTap/UserSettingsManager.swift` (`whoopEnabled`)
- `ios/DoseTap/Views/Dashboard/DashboardViews.swift` (all WHOOP-gated sections)
- `ios/DoseTap/SleepTimelineOverlays.swift` (`extractBiometricData()`)

### Sleep Plan Display

`SleepPlanSummaryCard` displays "If in bed now" as hours+minutes (e.g. "8h 20m"), not raw minutes.

Calculation: `expectedSleepMinutes = wakeBy - now - sleepLatencyMinutes` (always ≥ 0).

Code references:
- `ios/Core/SleepPlan.swift` (`expectedSleepIfInBedNow`)
- `ios/DoseTap/Views/SleepPlanCards.swift` (`formatSleepDuration`)

## Work and wake advisories

Work status is separate from medication timing and resolution. Legacy Typical Week `enabled` values never imply working. Users explicitly choose a recurring work pattern and one advisory target: a fixed local cutoff, required wake minus a user-set buffer, or the existing Dose 2 target. No mode changes the medication window. Unknown work status produces no assumed work warning.

Resolve the wake date in the saved work schedule timezone from the canonical treatment-night date plus one calendar day, not from the current clock's date. Dated overrides take precedence over the recurring pattern. A one-day nonworking override suppresses only the work warning and commits no medication event. Dated wake edits leave the recurring pattern unchanged. DST gaps use the next valid local time and repeated times use the first occurrence.

Inside the medication window, passing the selected target on a working wake date presents Continue to Record Dose 2, I'm Not Working [exact date], Change Wake Time, and Cancel. Continue revalidates timing and the schedule revision; its acknowledgement is committed in dose metadata. Schedule changes never create a dose. A failed schedule write leaves the previous schedule and warning effective. After the medication window, only the retrospective resolution policy applies.

Work schedule configuration and dated overrides are stored together in SQLite `work_wake_schedule`. Weekly confirmation is an independent reminder and is deferred; its absence never blocks medication recording. Historical acknowledgements retain the schedule revision, timezone, wake instant, target instant and selected mode.

### Timeline Review metrics (DOSETAP-64)

- Review and its capture use the same read-only presentation of actual dose timestamps. MedicationTiming classifies the unrounded elapsed seconds; a displayed duration cannot determine the status. Early, In-window, Late and Invalid pair remain distinct. Capture materializes a standalone bitmap and rejects empty pixel output before opening the preview.
- An explicit skip shows Skipped. Dose 1 without Dose 2 shows Pending through the inclusive upper boundary, then Not recorded. No doses and an orphan Dose 2 are separate states. Contradictory taken/skipped records require review rather than a timing classification.
- Bathroom logs and disruption logs are counts of saved events, not durations or proof of every awakening. Zero logs means none logged, not zero awake minutes. Review does not estimate WASO from bathroom counts; Apple Health sleep information remains available in the existing timeline and provider cards.
- The summary describes recorded timing and missing information. It does not suggest moving doses or putting lights-out inside the Dose 2 window. Lights-out to final wake is labeled as logged elapsed time, not measured sleep; reversed or missing markers are unavailable.

### History bathroom-log summary (DOSETAP-65)

- History and the shared review-summary trend card show Bathroom Logs as a total count, not average awake minutes. Match the canonical bathroom event type; other quick logs do not contribute. Existing Apple Health awake intervals and their exports remain unchanged.
- Show the number of recorded nights with bathroom logs out of all nights included in the card. Nights without bathroom entries remain part of that denominator. Zero entries means none logged, not no awakenings or zero awake duration. An empty history shows No history rather than a measured zero.
- The card covers up to 14 most recent recorded night keys, not necessarily 14 consecutive calendar nights. Its header says Recorded nights and shows the actual count. Display the bathroom count explanation in compact History as well as detailed review/capture, with full accessible labels.
- Corrections and deletions refresh the same read-only summary. No migration, source-event rewriting, medication action or alarm change is part of this correction.

### Dashboard analytics contract (DOSETAP-45)

- Food/outcome reporting parity: one versioned `collectedNight` projection exposes last-food finish/type/high-fat/notes, exact non-negative food-to-dose intervals, explicit Dose 2 wake/backup-alarm/following-day/final-wake answers, personal 0–10 sleepiness and assessment/record timestamps, and measured post-Dose-2 sleep with source/coverage. Raw questionnaire answers and revision history remain in the bundle; legacy 1–5 ratings and late-meal answers stay separate.
- Food analytics use completed pre-sleep logs only. High-fat Yes/No/Unsure groups and unrecorded nights remain distinct, use medians with per-outcome usable counts, and follow the selected range/provider. No dose changes, inferred fasting, causal claims or food-effectiveness score. Food notes remain a detail field rather than an aggregate.
- Manual and scheduled local exports share the Studio bundle writer and include all local questionnaire submissions, events, medication and inventory rows, plus a flat collected-night CSV. Scheduled exports do not fetch network/provider enrichment; source unavailability stays explicit. Publish a unique completed archive only after all files succeed; cancellation/failure must not advance the successful-export date. Scheduled timing and signed-device background behavior remain OS-controlled acceptance gates.
- Studio imports the versioned projection and shows/report-exports its fields without converting old ratings or inferring legacy wake answers. Missing projections in older bundles are unavailable, not zero. CSV quoting must preserve commas, quotes, CR/LF; spreadsheet-safe text escaping must round-trip through Studio. Export remains an analysis archive, not a content-equal whole-project restore guarantee.
- Studio export actions and metadata adapt to the available window width. Save status remains below the actions. Source iPhone build identifies the imported archive, not the running Studio app or the current phone installation. Redaction applies to generated reports; an imported bundle copy preserves the original data.

- Date ranges include exactly the selected number of civil night keys through the current evening-anchored night; malformed and future keys are excluded. All Time includes all discovered local history. Provider fetch horizons remain explicit (Apple Health up to 120 nights, WHOOP 30 days).
- Recorded dose events own retrospective timing; never infer Dose 1 from Dose 2 or an extra dose. Pending Dose 2 (before the existing upper timing boundary) is separate from missing outcomes. Recorded outcomes include explicit skips; on-time percentages use valid timestamp pairs only, with exact elapsed seconds and the shared MedicationTiming classification.
- Missing observations remain missing, never zero or an implicit negative answer. Bathroom analytics count logs; duration is not measured. Pre-sleep completion requires a completed log. Stress-driver frequency counts each driver at most once per night.
- Studio's 30-day dose-timing cards use valid recorded timestamp pairs only, disclose their usable pair count, and show No data when no pairs exist. Classify each pair from unrounded elapsed seconds, never a legacy adherence flag. The average interval is descriptive; it is not labeled Optimal, Good, or an effectiveness result.
- Sleep comparisons use one explicitly selected provider without fallback. Show sample counts, source coverage and fetch errors. Descriptive timing groups and associations do not measure medication effectiveness or establish causation; changes in an average are not automatically improvements.
- Dashboard defaults to All, showing Overview, Trends and Data in one scroll; these groups remain optional filters. The captured metric reference is available in All and Data. Missing WHOOP, prior-period or timing-group inputs show explanatory cards. Empty, loading and partial-provider states remain visible. Existing Typical Week, nightly overrides, medication supply and alarm behavior are unchanged.

Tonight’s weekly summary covers the seven finished civil nights before the current night. “Dose 2 recorded” is the fraction of Dose-1 nights with a recorded second dose; explicit skips and unrecorded outcomes are shown separately. Gaps are not a day streak, and orphan second doses cannot inflate the rate.

Dashboard WHOOP sleep totals/stage proportions require all three sleep-stage fields; omitted stage, awake or disturbance fields are unavailable rather than zero. A recovery-enrichment failure preserves scored sleep data and surfaces a warning. This changes missingness presentation, not provider records.


### Dashboard build-14 metric parity (DOSETAP-45)
- Restore the useful build-14 summaries in every applicable section, using the same dashboard model: selected-range night count, finished-night in-window streak, category coverage, summary WHOOP recovery/HRV, nightly status, per-night coverage and descriptive interval change.
- The finished-night streak ends on the civil night before the current 18:00 night key, stops at a missing/non-in-window night, and is limited to the selected range. An active night never breaks or inflates it.
- Coverage is a count out of four existing record categories, never statistical confidence. Missing fields stay visible as unavailable; unknown observations never become zero.
- Colors identify timing (blue), sleep/check-ins (purple) and coverage (teal). Orange identifies record-review actions; provider recovery ranges and chart series retain explicit text legends. Directional comparison colors never imply that shorter intervals or higher values are better.

### Read-only dose/sleep durations (DOSETAP-57)

The optional Wake & Next Day Apple Health coverage check derives four durations from the same freshly checked local snapshot and reviewed provider projection: Dose 1 to initial sleep, awakening to Dose 2, Dose 2 to return to sleep, and the whole Dose 2 awakening. The contract is [reviewed dose/sleep metrics](contracts/reviewed-dose-sleep-metrics.md). These estimates do not record medication, infer skipped doses, replace dashboard totals, persist provider history, or supply awakening counts. Signed-device/provider, VoiceOver and release acceptance remain separate.

Timeline Review exposes a read-only dose/sleep check for its selected treatment night. It uses the existing saved reviewed window and repository loader, shows the associated Dose 2 awakening and source samples, and clears results after local changes, a night switch, backgrounding or Health preference changes. It does not replace the legacy stage chart or infer wake causes. See the reviewed-dose-sleep contract.
