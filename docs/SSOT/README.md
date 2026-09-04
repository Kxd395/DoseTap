# DoseTap SSOT (Single Source of Truth)

Status: Current behavior authority
Last verified: 2026-09-04
SSOT revision: 0.4.15
Shipping app version observed in the Xcode project: 0.4.12 (build 14)

This document is the authoritative specification for current DoseTap behavior. It describes the intended shipping contract and is checked against the implementation. A code/spec mismatch is a defect to reconcile explicitly; changing this file must not be used to hide an unsafe implementation change.

## Canonical References

- Code entry points: `ios/DoseTap/Storage/SessionRepository.swift`, `ios/Core/DoseTapCore.swift`, `ios/DoseTap/ContentView.swift`
- Views: `ios/DoseTap/Views/TonightView.swift`, `ios/DoseTap/Views/CompactDoseButton.swift`, `ios/DoseTap/Views/DetailsView.swift`
- Storage: `ios/DoseTap/Storage/EventStorage.swift` and the maintained `ios/DoseTap/Storage/EventStorage+*.swift` extensions
- Executable schema: `ios/DoseTap/Storage/EventStorage+Schema.swift`
- Human-readable schema: `docs/DATABASE_SCHEMA.md`
- Dose persistence contract: `docs/SSOT/dose-state-persistence.md`
- Alarm scheduling contract: `docs/SSOT/alarm-scheduling.md`
- Data dictionary: `docs/SSOT/contracts/DataDictionary.md`
- Diagnostic logging: `docs/DIAGNOSTIC_LOGGING.md`

Notes:
- `docs/SSOT/constants.json` is a reference snapshot, not a generator. Code must stay in sync manually.
- If you need planned or speculative features, see `docs/FEATURE_TRIAGE.md` (not SSOT).

---

## Domain Entities and Invariants

### SleepSession

Identity and lifecycle are separate from calendar day grouping.

- Identity: `session_id` (UUID string).
- Grouping key: `session_date` (YYYY-MM-DD) computed by `sessionKey(for:timeZone:rolloverHour:)` with default rollover hour 18 (6 PM). See `ios/Core/SessionKey.swift`.
- Persistence: `sleep_sessions` table and `current_session` table (see `ios/DoseTap/Storage/EventStorage.swift`).
- Start: first event that requires a session (dose, snooze, sleep event, pre-sleep log linking) via `SessionRepository.ensureActiveSession(for:reason:)`.
- End: when morning check-in completes or when schedule fallback closes the session.

Closure rules (authoritative):
- Primary: `SessionRepository.completeCheckIn()` closes the active session and clears in-memory state. Invoked by `SessionRepository.saveMorningCheckIn(...)` when the saved check-in matches the active session.
- Fallback A (missed check-in cutoff): `SessionRepository.evaluateSessionBoundaries(reason:)` closes the session if `now >= cutoffTime(start)`.
- Fallback B (prep-time soft rollover): `SessionRepository.evaluateSessionBoundaries(reason:)` closes the session if `now >= prepTime` and session started before prep time.

Schedule settings used by rollover logic (from `UserSettingsManager`):
- `sleepStartMinutes` (default 21:00)
- `wakeTimeMinutes` (default 07:00)
- `prepTimeMinutes` (default 18:00)
- `missedCheckInCutoffHours` (default 4)

Safety constraints (authoritative):
- Dose 2 timing is classified from absolute elapsed seconds: before 150 minutes is early; 150 minutes inclusive through 240 minutes exclusive is in-window; 240 minutes or later is late. Negative or non-finite elapsed values are invalid. Display rounding must never determine eligibility, adherence, export status, or scores.
- Default target interval is 165 minutes (valid planner targets: 165, 180, 195, 210, 225).
- Session day grouping rolls over at 18:00 (6 PM) local time.
- Undo window is 5 seconds by default for dose/event actions.
- Elapsed time, an unanswered alarm, app foregrounding, or session rollover must never persist a taken, skipped, or missed medication outcome.
- `closed` is a calculated timing phase, not a persisted medication outcome. An unresolved record remains unresolved until the user explicitly records an occurrence that already happened or marks Dose 2 missed / not taken.
- Prospective Dose 2 actions are blocked after the configured window. A real occurrence remains recordable retrospectively with its actual timestamp; an occurrence outside the configured window requires an explicit accuracy warning and confirmation.

### DoseEvent

- Storage: `dose_events` table with `session_id` and `session_date`. See `EventStorage+Dose.swift` for `saveDose1/saveDose2/saveDoseSkipped/saveSnooze`.
- Event types (exact strings): `dose1`, `dose2`, `extra_dose`, `dose2_skipped`, `snooze`.
- Dose index rule: `doseIndex = (count of dose events in session) + 1` where count includes `dose1`, `dose2`, `extra_dose` only.
- Dose 2 late flag: `is_late = true` if `doseIndex == 2` and `timestamp >= dose1 + maxInterval`.
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

- Storage: `morning_checkins` table.
- Save path: `MorningCheckInView` -> `MorningCheckInViewModel.toStoredCheckIn()` -> `SessionRepository.saveMorningCheckIn(...)`.
- When saved for the active session, check-in closes the session: `SessionRepository.completeCheckIn()` -> `closeActiveSession(...)`.
- If morning answers derive symptom events, the morning source row, normalized check-in submission row, and derived symptom replacement commit in one SQLite transaction. Failure in any one of those writes rolls back the source row save.

### NapEvent

Naps are implemented as paired sleep events, not a separate table.

- Start: sleep event named "Nap Start".
- End: sleep event named "Nap End".
- Pairing is done in History (`SelectedDayView.napIntervals`) by pairing the next "Nap End" after a "Nap Start".
- If a start has no end, History shows "Nap in progress". There is no guard preventing multiple overlapping naps.

### HealthKit

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
beforeWindow --(150m)--> active --(<15m left)--> nearClose --(240m, no write)--> closed
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

Tab selection is synced between compact (TabView `$urlRouter.selectedTab`) and regular (sidebar selection `$urlRouter.selectedTab`) layouts. Deep links work identically in both modes.

Code references:
- `ios/DoseTap/ContentView.swift` (adaptive root)
- `ios/DoseTap/Views/AdaptiveLayouts.swift` (environment key, sidebar, helpers)
- `ios/DoseTap/URLRouter.swift` (`AppTab` enum, `selectedTab`)

---

## Time Boundary Model

- All timestamps are absolute `Date` instants stored as ISO8601 strings.
- `session_date` is a grouping key derived from `sessionKey(for:timeZone:rolloverHour:)` with default rollover 18 (6 PM). It is not the session boundary.
- Cross-midnight rule: events after midnight remain in the open session until it is closed by morning check-in or fallback cutoff.
- Interval math uses absolute timestamps with a single midnight rollover allowance. See `TimeIntervalMath.minutesBetween(start:end:)` in `ios/Core/TimeIntervalMath.swift`.
- Timezone changes: `SessionRepository` listens for time change notifications and reloads state via `updateSessionKeyIfNeeded(reason:)`.

---

## Storage and Persistence Truth

Persistence is local SQLite via `EventStorage`.

The executable schema is `EventStorage.createTables()` in `ios/DoseTap/Storage/EventStorage+Schema.swift`. At the last verification it creates 16 application tables plus the internal `schema_migrations` ledger and writes SQLite `user_version` 4. `docs/DATABASE_SCHEMA.md` and `docs/SSOT/contracts/DataDictionary.md` contain the field-by-field inventory and must move with that source. Do not copy a partial table list into evergreen documentation.

Symptom source identity:
- `pre_sleep_logs` and `morning_checkins` remain the source rows for questionnaire context.
- Structured pain entries in those source rows derive rebuildable `symptom_events` using `source + source_record_id + source_entry_key`.
- Editing, clearing, syncing, or deleting a source row must replace or clear that row's derived symptom events and rebuild `symptom_summaries`.
- Pre-sleep and morning source-row writes, normalized `checkin_submissions` writes, and derived symptom replacement or clearing must commit in the same local SQLite transaction. Partial source-only or symptom-only commits are invalid.

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
| Take Dose 1 | Dose 1 event and active-session projection agree | Schedule the absolute wake alarm and window reminders; surface any scheduling failure after preserving the committed Dose 1 | Policy must allow the first dose |
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
- **Dashboard:** WHOOP Card shown only when `!model.whoopNights.isEmpty`. Recovery KPIs in Executive Summary conditional on `averageWhoopRecovery != nil`.
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
