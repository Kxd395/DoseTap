# DoseTap SSOT (Single Source of Truth)

Last updated: 2026-02-16
Version: 0.3.3

This document is the authoritative specification for the current DoseTap behavior. It describes what the code does today. If code and this SSOT diverge, the SSOT must be updated to match the code.

## Canonical References

- Code entry points: `ios/DoseTap/Storage/SessionRepository.swift`, `ios/Core/DoseTapCore.swift`, `ios/DoseTap/ContentView.swift`
- Views: `ios/DoseTap/Views/TonightView.swift`, `ios/DoseTap/Views/CompactDoseButton.swift`, `ios/DoseTap/Views/DetailsView.swift`
- Storage: `ios/DoseTap/Storage/EventStorage.swift` + 7 extensions (`+Schema`, `+Session`, `+Exports`, `+EventStore`, `+Dose`, `+CheckIn`, `+Maintenance`)
- Storage schema: `docs/DATABASE_SCHEMA.md`
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
- Dose 2 clinical window is 150-240 minutes after Dose 1.
- Default target interval is 165 minutes (valid planner targets: 165, 180, 195, 210, 225).
- Session day grouping rolls over at 18:00 (6 PM) local time.
- Undo window is 5 seconds by default for dose/event actions.

### DoseEvent

- Storage: `dose_events` table with `session_id` and `session_date`. See `EventStorage+Dose.swift` for `saveDose1/saveDose2/saveDoseSkipped/saveSnooze`.
- Event types (exact strings): `dose1`, `dose2`, `extra_dose`, `dose2_skipped`, `snooze`.
- Dose index rule: `doseIndex = (count of dose events in session) + 1` where count includes `dose1`, `dose2`, `extra_dose` only.
- Dose 2 late flag: `is_late = true` if `doseIndex == 2` and `timestamp > dose1 + maxInterval`.
- Extra dose rule: `doseIndex >= 3` only. Timer expiration never changes dose index.
- Extra dose does not update `current_session.dose2_time`.

Code references:
- `SessionRepository.setDose1Time(_:)`
- `SessionRepository.setDose2Time(_:isEarly:isExtraDose:)`
- `SessionRepository.loadDoseEvents(sessionId:sessionDate:)`
- `EventStorage+Dose.saveDose2(timestamp:isEarly:isExtraDose:isLate:sessionId:sessionDateOverride:)`

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
- `ios/DoseTap/SettingsView.swift` (`HealthKitSettingsView`)

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
- `nearClose` -> `closed`: 240 minutes elapsed since Dose 1.
- `active|nearClose|closed` -> `completed`: Dose 2 taken or Dose 2 skipped.
- `any` -> `finalizing`: wake final logged; check-in pending.
- `finalizing` -> `completed`: morning check-in submitted.

Snooze rules (authoritative):
- Snooze is enabled ONLY in `active` phase AND `snoozeCount < maxSnoozes` (default 3).
- Snooze is disabled in `nearClose` phase (remaining < 15 minutes) regardless of count.
- Snooze is disabled in all other phases (`noDose1`, `beforeWindow`, `closed`, `completed`, `finalizing`).
- All surfaces (UI buttons, Flic, deep links) MUST use `DoseWindowContext.snooze` enum to enforce these rules — not manual boolean checks.

Deep link authorization rules (authoritative):
- State-changing deep links (`dose1`, `dose2`, `snooze`, `skip`) require the app to be in the foreground.
- Late-dose and extra-dose actions via deep link require confirmation UI before persisting.

Transition table (subset):

| Current | Trigger | Guard | Writes | Next |
| --- | --- | --- | --- | --- |
| `noDose1` | Take Dose 1 | none | `saveDose1` + `dose_events` + schedule alarms | `beforeWindow` |
| `beforeWindow` | Take Dose 2 | requires early override | `saveDose2(is_early)` + cancel alarms | `completed` |
| `active` | Take Dose 2 | none | `saveDose2` + cancel alarms | `completed` |
| `nearClose` | Take Dose 2 | none | `saveDose2` + cancel alarms | `completed` |
| `closed` | Take Dose 2 | requires late override | `saveDose2(is_late)` + cancel alarms | `completed` |
| `active\|nearClose\|closed` | Skip Dose 2 | none | `saveDoseSkipped` + cancel alarms | `completed` |
| `any` | Wake Final | none | `insertSleepEvent(wake_final)` | `finalizing` |
| `finalizing` | Submit Check-In | none | `saveMorningCheckIn` + `closeSession` | `completed` |

ASCII diagram:

```
noDose1
  | takeDose1
  v
beforeWindow --(150m)--> active --(<15m left)--> nearClose --(240m)--> closed
   | takeDose2 (early override)        | takeDose2                | takeDose2 (late override)
   v                                   v                          v
completed <----------------------------+--------------------------+
   ^
   | skipDose2
   |
finalizing --(check-in complete)--> completed
```

Code references:
- `DoseWindowCalculator.context(...)`
- `DoseTapCore.takeDose(earlyOverride:lateOverride:)`
- `SessionRepository.setDose1Time(_:)`
- `SessionRepository.setDose2Time(_:isEarly:isExtraDose:)`
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
  -> DoseTapCore.takeDose()
    -> SessionRepository.setDose1Time(_:) (ios/DoseTap/Storage/SessionRepository.swift)
      -> EventStorage.saveDose1(...) (ios/DoseTap/Storage/EventStorage+Dose.swift)
      -> DiagnosticLogger.logDoseTaken(...) (ios/Core/DiagnosticLogger.swift)
      -> SessionRepository.sessionDidChange.send()
         -> UI redraw via Combine subscription
```

Dose 2 example:

```
CompactDoseButton.takeDose2WithOverride() (ios/DoseTap/Views/CompactDoseButton.swift)
  -> DoseTapCore.takeDose(lateOverride: true)
    -> SessionRepository.setDose2Time(_:isEarly:isExtraDose:)
      -> EventStorage.saveDose2(..., isLate: true) (ios/DoseTap/Storage/EventStorage+Dose.swift)
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

Tables (authoritative in `EventStorage.createTables()`):
- `sleep_sessions` (session_id, session_date, start_utc, end_utc, terminal_state)
- `current_session` (session_id, session_date, dose1_time, dose2_time, snooze_count, dose2_skipped, session_start_utc, session_end_utc)
- `dose_events` (id, event_type, timestamp, session_date, session_id, metadata)
- `sleep_events` (id, event_type, timestamp, session_date, session_id, color_hex, notes)
- `morning_checkins` (session_id, timestamp, session_date, ...)
- `pre_sleep_logs` (session_id, created_at_utc, answers_json, ...)
- `medication_events` (session_id, medication_id, taken_at_utc, ...)

Data retention:
- App restart: data persists.
- App uninstall: iOS deletes the sandbox; all local data is lost.
- Manual export: Settings -> "Export Data (CSV)" writes a file to Files.
- Cloud sync: not implemented.

---

## Known Limitations (Truth, Not Plans)

- Duplicate dose taps are not explicitly de-duplicated in storage. Rapid taps can create multiple dose events.
- Nap overlap is not prevented. Pairing uses first start with next end only.
- Sleep event `event_type` strings are not normalized across UI and deep links.

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
| `dosetap_wake_alarm` | `AlarmService.scheduleWakeAlarm(at:dose1Time:)` | Primary wake alarm at target time |
| `dosetap_pre_alarm` | `AlarmService.scheduleWakeAlarm(at:dose1Time:)` | 15-minute pre-alarm warning |
| `dosetap_followup_1` | `AlarmService.scheduleWakeAlarm(at:dose1Time:)` | Follow-up alarm +2 min |
| `dosetap_followup_2` | `AlarmService.scheduleWakeAlarm(at:dose1Time:)` | Follow-up alarm +4 min |
| `dosetap_followup_3` | `AlarmService.scheduleWakeAlarm(at:dose1Time:)` | Follow-up alarm +6 min |
| `dosetap_second_dose` | `AlarmService.scheduleDose2Reminders(dose1Time:)` | Dose 2 window opening reminder |
| `dosetap_window_15min` | `AlarmService.scheduleDose2Reminders(dose1Time:)` | 15-minute window closing warning |
| `dosetap_window_5min` | `AlarmService.scheduleDose2Reminders(dose1Time:)` | 5-minute final warning (critical) |

Cancellation:
- `SessionRepository.cancelPendingNotifications()` cancels all identifiers in `sessionNotificationIdentifiers`.
- `AlarmService.cancelAllAlarms()` cancels the same set via `UNUserNotificationCenter`.
- `AlarmService.cancelDose2Reminders()` cancels window reminder identifiers specifically.

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
- `ios/DoseTap/SettingsView.swift` (`validateNotificationAuthorization()`, `openSystemNotificationSettings()`)

---

## Channel Parity (Dose Entry Surfaces)

All dose entry channels MUST trigger identical side effects for the same action. This is a patient-safety invariant.

Entry surfaces:
1. **Tonight UI** — `CompactDoseButton` in `TonightView`
2. **History UI** — `DoseButtonsSection` in `HistoryViews`
3. **Deep link** — `URLRouter` (e.g., `dosetap://dose1`, `dosetap://dose2`)
4. **Hardware button** — `FlicButtonService`

Required side effects per action:

| Action | Domain Write | Alarm Schedule | Alarm Cancel | Diagnostic Log |
| --- | --- | --- | --- | --- |
| Take Dose 1 | `SessionRepository.saveDose1(timestamp:)` | `AlarmService.scheduleWakeAlarm(...)` + `scheduleDose2Reminders(...)` | — | Yes |
| Take Dose 2 | `SessionRepository.saveDose2(timestamp:...)` | — | `AlarmService.cancelAllAlarms()` + `clearWakeAlarmState()` | Yes |
| Take Dose 2 (late) | `SessionRepository.saveDose2(timestamp:...)` | — | `AlarmService.cancelAllAlarms()` + `clearWakeAlarmState()` | Yes |
| Skip Dose 2 | `SessionRepository.skipDose2()` | — | `AlarmService.cancelAllAlarms()` + `clearWakeAlarmState()` | Yes |
| Extra Dose | `SessionRepository.saveDose2(timestamp:..., isExtraDose: true)` | — | — | Yes |
| Snooze | `AlarmService.snoozeAlarm(dose1Time:)` | Reschedule alarm | — | Yes |

Code references:
- `ios/DoseTap/Views/CompactDoseButton.swift`
- `ios/DoseTap/Views/History/HistoryViews.swift` (`DoseButtonsSection`)
- `ios/DoseTap/URLRouter.swift`
- `ios/DoseTap/FlicButtonService.swift`

---

## WHOOP Integration

### Feature Flag

`WHOOPService.isEnabled` is a dynamic computed property reading `UserDefaults("whoop_enabled")`.

State transitions:
- **On connect:** `authorize()` sets `UserSettingsManager.shared.whoopEnabled = true` after successful OAuth token exchange.
- **On disconnect:** `disconnect()` sets `UserSettingsManager.shared.whoopEnabled = false` and clears Keychain tokens.
- **Migration (init):** If tokens exist in Keychain but `whoopEnabled` is `false`, auto-sets to `true`.
- There is no hardcoded kill switch.

### Data Surface Gating

All WHOOP data display is gated behind `WHOOPService.isEnabled` and/or data presence checks:
- **Dashboard:** WHOOP Card shown only when `!model.whoopNights.isEmpty`. Recovery KPIs in Executive Summary conditional on `averageWhoopRecovery != nil`.
- **Timeline:** `extractBiometricData()` returns empty arrays when `!WHOOPService.isEnabled`.
- **Night Review:** `HealthDataCard` WHOOP section guarded behind `WHOOPService.isEnabled`.
- **Sleep Snapshot:** WHOOP Metrics section guarded behind `averageWhoopRecovery != nil || averageWhoopHRV != nil`.

Code references:
- `ios/DoseTap/WHOOPService.swift` (`isEnabled`, `authorize()`, `disconnect()`)
- `ios/DoseTap/UserSettingsManager.swift` (`whoopEnabled`)
- `ios/DoseTap/Views/Dashboard/DashboardViews.swift` (all WHOOP-gated sections)
- `ios/DoseTap/Views/SleepTimelineOverlays.swift` (`extractBiometricData()`)

### Sleep Plan Display

`SleepPlanSummaryCard` displays "If in bed now" as hours+minutes (e.g. "8h 20m"), not raw minutes.

Calculation: `expectedSleepMinutes = wakeBy - now - sleepLatencyMinutes` (always ≥ 0).

Code references:
- `ios/Core/SleepPlan.swift` (`expectedSleepIfInBedNow`)
- `ios/DoseTap/Views/SleepPlanCards.swift` (`formatSleepDuration`)
