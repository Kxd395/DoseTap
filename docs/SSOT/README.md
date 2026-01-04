# DoseTap SSOT (Single Source of Truth)

> ✅ **CANONICAL**: This is THE authoritative specification for DoseTap.
> All behavior, thresholds, and contracts are defined here.
> If code differs from this document, the code is wrong.

**Archived documents:** `docs/archive/SSOT_v2.md` (frozen historical reference)

**Constants file:** [`constants.json`](constants.json) - Single source for all numeric constants

**Database schema:** [`../DATABASE_SCHEMA.md`](../DATABASE_SCHEMA.md) - Complete SQLite schema reference

**Follow-along execution checklist:** [`TODO.md`](TODO.md)

**This document supersedes:** `DoseTap_Spec.md`, `ui-ux-specifications.md`, `button-logic-mapping.md`, `api-documentation.md`, `user-guide.md`, `implementation-roadmap.md`

**Last Updated:** 2026-01-03  
**Version:** 2.13.0

---

## Contract Index (machine-checkable map)

This table is the executable map of the SSOT. If a feature is user-visible, it should have an entry here.

| Feature | Spec section | `constants.json` keys | Schema tables | Code entrypoint(s) | Test file(s) |
|---|---|---|---|---|---|
| Dose 2 window + CTAs | “Dose window model” + “CTA Mapping Table” | `doseWindow.*` | `dose_events`, `current_session` | `DoseWindowCalculator`, `SessionRepository` | `Tests/DoseCoreTests/DoseWindowStateTests.swift`, `Tests/DoseCoreTests/DoseWindowEdgeTests.swift` |
| Late Dose 2 override | “Dose 2 Window Override” | `doseWindow.maxMinutes` | `dose_events` | `DoseWindowCalculator` (expired phase) + UI CTA wiring | `Tests/DoseCoreTests/DoseWindowEdgeTests.swift` |
| Midnight rollover interval | “Time Model” + “Midnight rollover interval rule” | n/a | `dose_events` | `SessionSummary.intervalMinutes`, `StoredDoseLog.intervalMinutes` | `Tests/DoseCoreTests/Dose2EdgeCaseTests.swift` |
| Undo snackbar | “Undo Support & Medication Settings” | `undo.windowSeconds` | `dose_events` | `UndoSnackbarView`, `UndoStateManager`, `SessionRepository` | (UI wiring: DoseTapTests) |
| Storage boundaries | “Storage / SSOT Boundary Rules” | n/a | all | `SessionRepository` ⇄ `EventStorage` | CI workflow guards |

---

## Time Model (normative)

The time model is part of the SSOT contract.

- **Absolute timestamps are authoritative**: all stored event times are absolute instants (`Date` / ISO8601 timestamp). Any interval math MUST use these absolute timestamps.
- **`session_date` is a grouping key only**: it is used for “which night” grouping, not for reconstructing absolute times.
- **Never reconstruct absolute timestamps from UI strings**: UI must not rebuild an absolute time from `session_date` + “time-of-day”. Only format already-stored absolute timestamps for display.
- **Midnight rollover interval rule**: if an interval is computed from two timestamps and the end appears earlier than the start (e.g., Dose 2 after midnight), treat end as occurring on the next day (+24h) for interval purposes.

---

## Storage / SSOT Boundary Rules (normative)

These boundaries are enforced by CI and are part of the SSOT contract:

1. Views and view models MAY call `SessionRepository` only.
2. `SessionRepository` is the only module allowed to talk to `EventStorage`.
3. `EventStorage` is the only module allowed to talk to SQLite.
4. `SQLiteStorage.swift` is legacy and banned; any reference is a build failure.
5. Any direct use of `EventStorage.shared` from UI is a build failure.

The exact guard patterns live in `.github/workflows/ci-swift.yml`.

## Recent Updates (v2.13.0) - Night Mode Theme System

### Theme System & Night Mode (Circadian-Friendly UI)

**Problem Solved**: Blue light exposure during nighttime medication dosing can suppress melatonin production and disrupt circadian rhythm, particularly problematic for users taking doses in the middle of the night.

**Architecture Now**:
```
ThemeManager (singleton) → AppTheme enum (Light, Dark, Night)
                        ↓
                   ContentView applies global theme
                        ↓
                   All views inherit theme colors
```

**Key Components**:
- ✅ **AppTheme Enum** (`ios/DoseTap/Theme/AppTheme.swift`): Three modes - Light, Dark, Night Mode
- ✅ **ThemeManager** (`@MainActor`, `ObservableObject`): Singleton managing current theme state
- ✅ **Night Mode Colors**: Red/amber palette eliminating all blue wavelengths (<600nm)
- ✅ **Global Red Filter**: `.colorMultiply()` applied at root when Night Mode active
- ✅ **Persistent Selection**: Theme choice saved to UserDefaults, survives app restart
- ✅ **Settings Integration**: Theme picker in Settings → Appearance section

**Night Mode Color Palette** (eliminating blue light for sleep protection):
- Background: Very deep red-black (`rgb(0.08, 0.0, 0.0)`)
- Cards: Red-tinted (`rgb(0.15, 0.03, 0.0)`)
- Primary text: Warm amber (`rgb(1.0, 0.6, 0.4)`)
- Accent: Deep red (`rgb(0.8, 0.2, 0.1)`)
- Buttons: Dark red (`rgb(0.6, 0.15, 0.0)`)
- Success: Amber (`rgb(0.9, 0.6, 0.0)`)
- Warning: Deep orange (`rgb(1.0, 0.4, 0.0)`)
- Error: Pure red (`rgb(0.8, 0.2, 0.0)`)

**Theme Application**:
```swift
// At ContentView root
.preferredColorScheme(themeManager.currentTheme == .night ? .dark : colorScheme)
.accentColor(themeManager.currentTheme.accentColor)
.applyNightModeFilter(themeManager.currentTheme)  // Red colorMultiply filter

// In child views
@EnvironmentObject var themeManager: ThemeManager
let buttonColor = themeManager.currentTheme.buttonBackground
```

**Medical Rationale**:
- Blue light (400-500nm) suppresses melatonin by 50%+ even at low intensities
- Red/amber light (>600nm) has minimal circadian impact
- Critical for users taking Dose 2 at 2-4 AM (peak melatonin window)
- Enables safe medication checks without disrupting remaining sleep

**User Flow**:
1. User taps Settings → Theme → Night Mode
2. ThemeManager persists choice to UserDefaults (`"selectedTheme": "Night Mode"`)
3. Global red filter applied: all white → red-black, all blue/teal → red/amber
4. User can check doses, log events, view timeline without blue light exposure
5. Theme persists across app restarts and device reboots

**Contract**:
- MUST eliminate ALL blue wavelengths in Night Mode (no exceptions)
- MUST apply to ALL screens (Tonight, Timeline, History, Settings)
- MUST persist user's theme selection
- MUST be toggle-able at any time via Settings
- Light/Dark modes MUST retain original blue/teal accent colors

**Implementation Files**:
- `ios/DoseTap/Theme/AppTheme.swift` - Theme enum, colors, manager
- `ios/DoseTap/Views/ThemeSettingsView.swift` - Theme selection UI
- `ios/DoseTap/ContentView.swift` - Global theme application
- `ios/DoseTap/SettingsView.swift` - Settings integration

**Test Validation**: Visual inspection required - Night Mode must show zero blue UI elements across all 4 tabs.

---

## Recent Updates (v2.12.0) - Storage Enforcement Complete

### Unified Storage (Split Brain Eliminated)

**Problem Solved**: Previously, the app had dual storage paths (SQLiteStorage + EventStorage) creating "split brain" where data could be logged in one location and invisible in another.

**Architecture Now**:
```
UI Views → SessionRepository → EventStorage → SQLite (dosetap_events.sqlite)
                                          ↳ EventStore protocol

SQLiteStorage → BANNED (#if false wrapper)
```

**Key Changes**:
- ✅ **EventStore Protocol** (`ios/Core/EventStore.swift`): Defines unified storage interface
- ✅ **EventStorage Conformance**: EventStorage implements EventStore protocol
- ✅ **SQLiteStorage BANNED**: Wrapped in `#if false` - compiler enforced
- ✅ **SessionRepository Extended**: ALL storage operations route through here
- ✅ **CI Guard Active**: Fails build if views touch EventStorage.shared directly

**Enforced Boundary** (CI Guard in `.github/workflows/ci-swift.yml`):
- `EventStorage.shared` - Views MUST NOT reference directly
- `SQLiteStorage` - Production code MUST NOT reference at all
- All storage access: `SessionRepository.shared.*`

**Terminology note**: `SQLiteStorage.swift` is legacy and banned. When this SSOT refers to “SQLite”, it means the SQLite database as implemented by `EventStorage` and accessed only via `SessionRepository`.

**Migration Complete** (21 → 0 production violations):
| File | Violations Fixed |
|------|------------------|
| ContentView.swift | 15 |
| SettingsView.swift | 3 |
| URLRouter.swift | 2 |
| AnalyticsService.swift | 1 |
| InsightsCalculator.swift | 1 |

**SessionRepository Facade Methods**:
```swift
// Dose operations
saveDose1(timestamp:)
saveDose2(timestamp:isEarly:isExtraDose:)

// Event operations
insertSleepEvent(id:eventType:timestamp:colorHex:notes:)
fetchTonightSleepEvents() -> [StoredSleepEvent]
fetchSleepEvents(for:) -> [StoredSleepEvent]
deleteSleepEvent(id:)
clearTonightsEvents()

// Session operations
currentSessionDateString() -> String
sessionDateString(for:) -> String
fetchRecentSessions(days:) -> [SessionSummary]
fetchDoseLog(forSession:) -> StoredDoseLog?
mostRecentIncompleteSession() -> String?
deleteSession(sessionDate:)

// Pre-sleep & Check-in
savePreSleepLog(answers:completionState:existingLog:)
fetchMostRecentPreSleepLog() -> StoredPreSleepLog?
fetchMostRecentPreSleepLog(sessionId:) -> StoredPreSleepLog?
saveMorningCheckIn(_:sessionDateOverride:)
linkPreSleepLogToSession(sessionId:)

// Export & Debug
exportToCSV() -> String
getSchemaVersion() -> Int
clearAllData()
```

**See**: `docs/STORAGE_ENFORCEMENT_REPORT_2025-12-26.md` for full migration details.

---

## Deferred Items (must be resolved before GA)

- UI component IDs (bulk_delete_button, date_picker, delete_day_button, devices_add_button, devices_list, devices_test_button, heart_rate_chart, insights_chart, session_list, settings_target_picker, timeline_export_button, timeline_list, tonight_snooze_button, wake_up_button, watch_dose_button) are NOT yet bound to shipping UI. These must be wired to real elements or explicitly deferred in product requirements (tracked in docs/PROD_READINESS_TODO.md). Placeholder file removed to avoid masking gaps.
- WHOOP/OAuth integrations remain experimental; treat as disabled-by-default until token handling and UI hardening are complete.
- HealthKit live data is optional: default provider on simulator/tests must be `NoOpHealthKitProvider`; HealthKitService usage must check availability/authorization. Shipping builds should default to off unless entitlements and validation are complete.
- All deferrals are tracked in docs/SSOT/PENDING_ITEMS.md for lint alignment.

## Recent Updates (v2.10.0)

### New in v2.10.0 (WHOOP Integration)

#### WHOOP OAuth Service (`WHOOPService.swift`)

- ✅ **ADDED**: `WHOOPService` singleton for WHOOP API integration
- ✅ **ADDED**: OAuth 2.0 authorization flow via `ASWebAuthenticationSession`
- ✅ **ADDED**: Secure token storage in iOS Keychain
- ✅ **ADDED**: Automatic token refresh when expired
- ✅ **ADDED**: `WHOOPProfile` model: userId, firstName, lastName, email
- ✅ **ADDED**: `WHOOPError` enum for typed error handling
- ✅ **ADDED**: Scopes: `read:recovery`, `read:sleep`, `read:cycles`

#### WHOOP Data Fetching (`WHOOPDataFetching.swift`)

- ✅ **ADDED**: `WHOOPSleepRecord` model with stages, efficiency, HRV, RR
- ✅ **ADDED**: `WHOOPNightSummary` computed from raw sleep data
- ✅ **ADDED**: `fetchRecentSleep(nights:)` fetches N nights of sleep data
- ✅ **ADDED**: Sleep stage breakdown: deep, REM, light, awake minutes
- ✅ **ADDED**: Sleep metrics: efficiency, disturbance count, respiratory rate
- ✅ **ADDED**: ISO 8601 date parsing with millisecond support

#### WHOOP Settings UI (`WHOOPSettingsView.swift`)

- ✅ **ADDED**: `WHOOPSettingsView` for connection management
- ✅ **ADDED**: OAuth connect/disconnect flow
- ✅ **ADDED**: Profile display (name, email) when connected
- ✅ **ADDED**: Last sync timestamp display
- ✅ **ADDED**: Recent sleep history (7 nights) with stage breakdown
- ✅ **ADDED**: Sync now action button
- ✅ **ADDED**: `WHOOPStatusRow` compact row for settings list

#### HR/RR/HRV Timeline Overlays (`SleepTimelineOverlays.swift`)

- ✅ **ADDED**: `HeartRateDataPoint`, `RespiratoryRateDataPoint`, `HRVDataPoint` models
- ✅ **ADDED**: `BiometricOverlay` component for line graph overlays
- ✅ **ADDED**: `BiometricDataType` enum: heartRate, respiratoryRate, hrv
- ✅ **ADDED**: `EnhancedSleepTimeline` with toggle-able biometric overlays
- ✅ **ADDED**: `BiometricToggle` component for showing/hiding overlays
- ✅ **ADDED**: `LiveEnhancedTimelineView` with date picker and WHOOP integration
- ✅ **ADDED**: `WHOOPService.extractBiometricData(from:)` for data conversion

#### watchOS Press-and-Hold Interaction (`ContentView.swift`)

- ✅ **ADDED**: `PressAndHoldButton` component with hold duration defined in `constants.json` (single source)
- ✅ **ADDED**: Progress ring animation during hold
- ✅ **ADDED**: Visual feedback: background fill + progress indicator
- ✅ **ADDED**: Haptic feedback via `WKInterfaceDevice.play(.success)`
- ✅ **ADDED**: `CompactPressAndHoldButton` for circular button variant
- ✅ **ADDED**: Accessibility labels with hold duration hint
- ✅ **ADDED**: Cancel on lift before completion
- ✅ **ADDED**: Dose 1 and Dose 2 buttons now use press-and-hold

**Test Coverage**: CI runs `swift test` (DoseCore) and `xcodebuild test` (DoseTapTests). See latest CI for counts.

---

## Recent Updates (v2.9.0)

### New in v2.9.0 (Reduced Motion, Flic Mapping, Analytics)

#### Reduced Motion Support (`ReducedMotionSupport.swift`)

- ✅ **ADDED**: `shouldReduceMotion` computed property in UserSettingsManager
- ✅ **ADDED**: Respects both user preference and system `UIAccessibility.isReduceMotionEnabled`
- ✅ **ADDED**: `accessibleAnimation(_:value:)` view modifier
- ✅ **ADDED**: `accessibleTransition(_:)` view modifier
- ✅ **ADDED**: `withAccessibleAnimation(_:_:)` global function
- ✅ **ADDED**: Animations disabled when reduce motion is enabled

#### Flic Button Service (`FlicButtonService.swift`)

- ✅ **ADDED**: `FlicButtonService` singleton for hardware button integration
- ✅ **ADDED**: `FlicAction` enum: takeDose, snooze, undo, logBathroom, logLightsOut, logWake, skip, none
- ✅ **ADDED**: `FlicGesture` enum: singlePress, doublePress, longHold
- ✅ **ADDED**: Gesture mapping per SSOT: Single=Dose, Double=Snooze, Hold=Undo
- ✅ **ADDED**: `handleGesture(_:)` routes to appropriate action handler
- ✅ **ADDED**: Haptic feedback for success/warning/error outcomes
- ✅ **ADDED**: Configuration persistence (UserDefaults)
- ✅ **ADDED**: `FlicButtonSettingsView` with gesture configuration UI
- ✅ **ADDED**: `FlicPairingView` pairing flow (stub - requires Flic SDK)

#### Analytics Service (`AnalyticsService.swift`)

- ✅ **ADDED**: `AnalyticsService` singleton for event tracking
- ✅ **ADDED**: `EventName` enum with 50+ event types (dose_, event_, session_, ui_, error_, perf_)
- ✅ **ADDED**: `AnalyticsEvent` model with timestamp, parameters, session/device info
- ✅ **ADDED**: `AnalyticsProvider` protocol for pluggable providers
- ✅ **ADDED**: `ConsoleAnalyticsProvider` for debug logging
- ✅ **ADDED**: `LocalFileAnalyticsProvider` for offline storage (analytics_events.json)
- ✅ **ADDED**: Convenience methods: trackDose1Taken, trackDose2Taken, trackSnooze, trackSessionCompleted
- ✅ **ADDED**: Event queue with automatic flush (60s interval, 100 event max)

**Test Coverage**: 246 tests passing

---

## Recent Updates (v2.8.0)

### New in v2.8.0 (Live Timeline, High Contrast, watchOS)

#### Live Sleep Timeline Integration

- ✅ **ADDED**: `fetchSegmentsForTimeline(from:to:)` public method in HealthKitService
- ✅ **ADDED**: `SleepDisplayStage` enum for timeline/HealthKit mapping
- ✅ **ADDED**: `LiveSleepTimelineView` - fetches real HealthKit data
- ✅ **ADDED**: `SleepTimelineContainer` with night picker for browsing history
- ✅ **ADDED**: Timeline tab now shows live HealthKit sleep data

#### High Contrast Color Tokens (`HighContrastColors.swift`)

- ✅ **ADDED**: `DoseColors` enum for centralized color tokens
- ✅ **ADDED**: WCAG AAA compliant colors (≥7:1 contrast ratio)
- ✅ **ADDED**: Automatic high-contrast mode via `UIAccessibility.isDarkerSystemColorsEnabled`
- ✅ **ADDED**: Semantic colors: success, warning, error, info
- ✅ **ADDED**: Phase colors: phasePreWindow, phaseActive, phaseNearEnd, phaseExceeded
- ✅ **ADDED**: Sleep stage colors with high contrast variants
- ✅ **ADDED**: Button colors: buttonDose1, buttonDose2, buttonSkip, buttonSnooze, buttonBathroom
- ✅ **ADDED**: `ContrastValidator` debug utility for ratio validation

#### watchOS App Enhancement (`watchos/DoseTapWatch/`)

- ✅ **ENHANCED**: `WatchDoseViewModel` with full snooze support (max 3, +10 min each)
- ✅ **ENHANCED**: Local persistence for dose state (survives app restart)
- ✅ **ENHANCED**: Session-based storage (resets at 6 PM daily)
- ✅ **ADDED**: `WatchEventType` enum: bathroom, lightsOut, wakeFinal
- ✅ **ADDED**: `StatusCard` with phase icon and snooze indicator
- ✅ **ADDED**: `PrimaryActionButtons` with separate Dose 1/Dose 2 buttons
- ✅ **ADDED**: `QuickEventGrid` for bathroom/lights_out/wake logging
- ✅ **ADDED**: `SyncStatusBar` showing phone connectivity and last sync time
- ✅ **ADDED**: Skip dose confirmation dialog
- ✅ **ENHANCED**: WatchConnectivity with queued message delivery (`transferUserInfo`)
- ✅ **ENHANCED**: App delegate handles state sync from iPhone

**Test Coverage**: 246 tests passing

---

## Recent Updates (v2.7.0)

### New in v2.7.0 (Weekly Planner, Accessibility, Timeline Visualization)

#### Weekly Planner Engine (`WeeklyPlanner.swift`)

- ✅ **ADDED**: `WeeklyPlanner` singleton for 7-day dose timing optimization
- ✅ **ADDED**: Valid intervals: `[165, 180, 195, 210, 225]` minutes
- ✅ **ADDED**: Plan strategies: `consistent`, `weekendAdjusted`, `gradual`, `baseline`
- ✅ **ADDED**: `generatePlan(baseline:strategy:)` creates personalized 7-day plan
- ✅ **ADDED**: `todayTarget()` returns current day's recommended interval
- ✅ **ADDED**: `planNeedsRefresh()` checks if plan is older than 7 days
- ✅ **ADDED**: `WeeklyPlannerView` with strategy picker and day breakdown
- ✅ **ADDED**: `CompactPlanSummary` for Tonight view

#### VoiceOver Accessibility

- ✅ **ADDED**: `accessibilityLabel` and `accessibilityHint` for CompactStatusCard
- ✅ **ADDED**: Timed announcements at 60, 30, 15, 10, 5, 1 minute marks
- ✅ **ADDED**: Accessibility labels for primary dose button (all states)
- ✅ **ADDED**: Accessibility hints with double-tap instructions
- ✅ **ADDED**: 44pt minimum tap targets for QuickLog buttons (was 36pt)

#### Sleep Stage Timeline (`SleepStageTimeline.swift`)

- ✅ **ADDED**: `SleepStageTimeline` visualization with color-coded bands
- ✅ **ADDED**: `SleepStage` enum: `awake`, `light`, `core`, `deep`, `rem`
- ✅ **ADDED**: `SleepStageBand` model for stage intervals
- ✅ **ADDED**: `TimelineEvent` for dose/bathroom markers on timeline
- ✅ **ADDED**: `StageSummaryCard` with duration breakdown by stage
- ✅ **ADDED**: Stage colors: awake=red, light=blue40%, core=blue60%, deep=indigo, rem=purple

**Test Coverage**: 246 tests passing

---

## Recent Updates (v2.6.0)

### New in v2.6.0 (Reminder Scheduling, HealthKit Integration)

#### Dose 2 Reminder Scheduling (`AlarmService.swift`)

- ✅ **ADDED**: `secondDose` notification - fires at window open (150 min)
- ✅ **ADDED**: `windowWarning15` notification - 15 min before window close
- ✅ **ADDED**: `windowWarning5` notification - 5 min before window close (critical)
- ✅ **ADDED**: `scheduleDose2Reminders(dose1Time:)` method
- ✅ **ADDED**: `cancelDose2Reminders()` method
- ✅ **ADDED**: Reminders auto-cancelled when Dose 2 taken or skipped

#### HealthKit Sleep Integration (`HealthKitService.swift`)

- ✅ **ADDED**: `HealthKitService` singleton for sleep data access
- ✅ **ADDED**: `requestAuthorization()` for sleep analysis permission
- ✅ **ADDED**: `fetchSleepSegments(from:to:)` - reads sleep stages
- ✅ **ADDED**: `analyzeSleepNight(segments:)` - extracts TTFW, wake count
- ✅ **ADDED**: `computeTTFWBaseline(days:)` - computes average Time to First Wake
- ✅ **ADDED**: `calculateNudgeSuggestion()` - suggests ±15 min adjustment
- ✅ **ADDED**: `sameNightNudge(dose1Time:)` - real-time nudge suggestion

#### HealthKit Settings UI (`HealthKitSettingsView`)

- ✅ **ADDED**: Authorization status display and connect button
- ✅ **ADDED**: "Compute Sleep Baseline" button (14 nights analysis)
- ✅ **ADDED**: TTFW baseline display with suggested nudge
- ✅ **ADDED**: Recent nights sleep history list
- ✅ **ADDED**: Privacy info section explaining data usage

#### Data Types

```swift
struct SleepNightSummary {
    let date: Date
    let bedTime: Date?
    let sleepOnset: Date?
    let firstWake: Date?
    let finalWake: Date?
    let ttfwMinutes: Double?
    let totalSleepMinutes: Double
    let wakeCount: Int
    let source: String
}
```

**Test Coverage**: 246 tests passing

---

## Recent Updates (v2.5.0)

### New in v2.5.0 (URL Scheme, Insights, Tab Rename)

#### URL Scheme / Deep Links (`URLRouter.swift`)

- ✅ **ADDED**: `dosetap://dose1` - Take Dose 1
- ✅ **ADDED**: `dosetap://dose2` - Take Dose 2
- ✅ **ADDED**: `dosetap://snooze` - Snooze alarm +10 min
- ✅ **ADDED**: `dosetap://skip` - Skip Dose 2
- ✅ **ADDED**: `dosetap://log?event=bathroom` - Log quick event
- ✅ **ADDED**: `dosetap://tonight`, `dosetap://history`, `dosetap://settings` - Navigation
- ✅ **ADDED**: `URLFeedbackBanner` - Shows action result feedback

#### Insights Metrics (`InsightsCalculator.swift`)

- ✅ **ADDED**: On-time percentage (doses within 150-240 min window)
- ✅ **ADDED**: Average interval minutes between Dose 1 and 2
- ✅ **ADDED**: Natural wake percentage (sessions with 0 snoozes)
- ✅ **ADDED**: Average WASO (Wake After Sleep Onset) from bathroom events
- ✅ **ADDED**: `InsightsSummaryCard` view showing all metrics
- ✅ **ADDED**: `computeInsights(days:)` method for historical analysis

#### Tab Rename

- ✅ **CHANGED**: "Details" tab renamed to "Timeline"
- ✅ **CHANGED**: Tab icon changed to `chart.bar.xaxis`
- ✅ **ADDED**: InsightsSummaryCard at top of Timeline view

**Test Coverage**: 246 tests passing

---

## Recent Updates (v2.4.9)

### New in v2.4.9 (Timezone Change Detection)

#### Timezone Change Detection System

- ✅ **ADDED**: `currentTimezoneOffsetMinutes()` static method in DoseWindowCalculator
- ✅ **ADDED**: `timezoneChange(from:)` method - returns delta in minutes (nil if no change)
- ✅ **ADDED**: `timezoneChangeDescription(from:)` method - human-readable description
- ✅ **ADDED**: `dose1TimezoneOffsetMinutes` property in SessionRepository
- ✅ **ADDED**: `checkTimezoneChange()` method - returns description if changed
- ✅ **ADDED**: `hasTimezoneChanged` computed property - boolean convenience

#### Behavior

When Dose 1 is taken, the current timezone offset (minutes from UTC) is recorded.
On subsequent checks, UI can detect if timezone has changed and warn user:
- "Timezone shifted 3 hours east"
- "Timezone shifted 1 hour west"
- "Timezone shifted 30 minutes east"

This prevents confusion when users travel or device timezone changes mid-session.

**Test Coverage**: 246 tests passing (+7 new timezone detection tests)

---

## Recent Updates (v2.4.8)

### New in v2.4.8 (Late Dose 1 Detection)

#### Late Night Session Assignment

- ✅ **ADDED**: `lateDose1Info()` method in DoseWindowCalculator
- ✅ **ADDED**: Returns `(isLateNight: Bool, sessionDateLabel: String)` tuple
- ✅ **ADDED**: Detects if current time is midnight-6AM (late night zone)
- ✅ **ADDED**: Returns human-readable session date label (e.g., "Wednesday, Dec 25")

#### Session Date Assignment Rules

Sessions are assigned based on 6 PM boundary:
- **6 PM to 11:59 PM**: Assigned to current calendar date
- **Midnight to 5:59 AM**: Assigned to PREVIOUS calendar date (same sleep night)
- **6 AM to 5:59 PM**: Assigned to current calendar date (new day)

UI can use `lateDose1Info()` to:
- Warn user: "You're logging Dose 1 for last night's session (Dec 25)"
- Show which session date the dose will be recorded under

#### Midnight Rollover Interval Rule

Because `session_date` is a *grouping key* (not necessarily the same as the calendar date of every event), Dose 2 can legitimately occur after midnight while still belonging to the prior session.

**Requirement:** Dose interval calculations must be based on the stored absolute timestamps.

Defensive behavior (to prevent negative intervals in history/review UI):
- If Dose 2 timestamp is earlier than Dose 1 timestamp, treat Dose 2 as occurring the next day for interval math (i.e., add +24h before subtracting).

**Test Coverage**: 239 tests passing (+4 new late dose 1 detection tests)

---

## Recent Updates (v2.4.7)

### New in v2.4.7 (Sleep-Through Handling)

#### Auto-Expire Sessions When User Sleeps Through

- ✅ **ADDED**: `sleepThroughGraceMin` config (default 30 min after 240 min window)
- ✅ **ADDED**: `shouldAutoExpireSession()` method in DoseWindowCalculator
- ✅ **ADDED**: `checkAndHandleExpiredSession()` method in SessionRepository
- ✅ **ADDED**: `markSessionSleptThrough()` internal method for auto-skip
- ✅ **ADDED**: `updateTerminalState()` method in EventStorage
- ✅ **ADDED**: `saveDoseSkipped(reason:)` with optional reason parameter
- ✅ **ADDED**: App lifecycle hook (`scenePhase .active`) to check for expired sessions

#### Behavior

When app returns to foreground, it checks if:
1. Dose 1 was taken
2. Dose 2 was NOT taken or skipped
3. Current time > Dose 1 + 240 min (window) + 30 min (grace)

If all conditions met, session is auto-marked as `incomplete_slept_through`:
- Dose 2 is auto-skipped with reason "slept_through"
- Terminal state is set to "incomplete_slept_through"
- Pending notifications are cancelled
- User can start a new session

**Test Coverage**: 235 tests passing (+6 new sleep-through detection tests)

---

## Recent Updates (v2.4.6)

### New in v2.4.6 (Finalizing State)

#### Finalizing Phase Implementation

- ✅ **ADDED**: `finalizing` phase to `DoseWindowPhase` enum
- ✅ **ADDED**: `wakeFinalTime: Date?` property in SessionRepository
- ✅ **ADDED**: `checkInCompleted: Bool` property in SessionRepository  
- ✅ **ADDED**: `setWakeFinalTime()` and `completeCheckIn()` methods
- ✅ **ADDED**: Updated `context()` to accept `wakeFinalAt` and `checkInCompleted` parameters
- ✅ **ADDED**: `finalizing` case in DoseStatus bridge type

#### State Machine: Finalizing Phase

The `finalizing` phase tracks the session between Wake Up (`wakeFinal` event) and morning check-in completion:
- Enters `finalizing` when `wakeFinalTime` is set but `checkInCompleted` is false
- Transitions to `completed` once check-in is completed
- Prevents premature session end before user confirms morning data

**Test Coverage**: 229 tests passing (+4 new: 3 finalizing state tests, 1 Lumryz test)

---

## Recent Updates (v2.4.5)

### New in v2.4.5 (All Narcolepsy Medications + Multi-Entry)

#### All FDA-Approved Narcolepsy Medications (16 total)

- ✅ **ADDED**: Full medication catalog with 4 categories:
  - **Stimulants (7)**: Adderall IR, Adderall XR, Ritalin IR, Ritalin LA, Concerta, Vyvanse, Dexedrine
  - **Wakefulness Agents (5)**: Modafinil, Provigil, Armodafinil, Nuvigil, Sunosi
  - **Histamine Modulators (1)**: Wakix
  - **Sodium Oxybate (3)**: XYWAV, Xyrem, **Lumryz** (once-nightly extended-release)

- ✅ **ADDED**: `MedicationCategory` enum: `.stimulant`, `.wakefulnessAgent`, `.histamineModulator`, `.sodiumOxybate`
- ✅ **ADDED**: `MedicationFormulation` enum: `.immediateRelease`, `.extendedRelease`, `.liquid`
- ✅ **ADDED**: Dose display formatting (mg for pills, grams for liquids)

#### Multi-Entry Medication Logging

- ✅ **ADDED**: Log multiple medications before saving (batch entry)
- ✅ **ADDED**: "+" button to add medication to pending list
- ✅ **ADDED**: Pending entries preview before Save
- ✅ **ADDED**: Remove individual entries with "×" button
- ✅ **ADDED**: Collapsible category sections in picker
- ✅ **ADDED**: Duplicate guard checks pending list AND database

**Test Coverage**: 225 tests passing (18 MedicationLogger tests)

---

## Recent Updates (v2.4.4)

### New in v2.4.4 (Alarm Indicator & Hard Stop Countdown)
- **AlarmIndicatorView**: Shows scheduled wake/dose 2 time in Tonight header when Dose 1 taken
- **HardStopCountdownView**: Prominent red countdown when <15 minutes remain in window
- **CompactStatusCard Enhanced**: Shows live countdown in nearClose status
- **CSV Export**: Real export implementation with share sheet

### New in v2.4.3 (Undo Support & Medication Settings)

#### Undo Snackbar (High Priority Gap Closed)

- ✅ **IMPLEMENTED**: 5-second undo window for dose actions
- ✅ **ADDED**: Configurable speed setting: Fast (3s), Normal (5s), Slow (7s), Very Slow (10s)
- ✅ **ADDED**: `UndoSnackbarView` with countdown progress bar and color coding
- ✅ **ADDED**: `UndoStateManager` observable wrapper for SwiftUI integration
- ✅ **ADDED**: Undo callback integration with `SessionRepository` for state reversal
- ✅ **ADDED**: Storage layer methods: `clearDose1()`, `clearDose2()`, `clearSkip()`

**User Flow:**
1. User takes Dose 1 or Dose 2
2. Snackbar appears at bottom with countdown
3. User can tap "Undo" to revert within configured window
4. If window expires, action commits permanently

#### Medication Settings (User Request)

- ✅ **ADDED**: `MedicationSettingsView` - configure which medications user takes
- ✅ **ADDED**: Medication toggle for Adderall IR and Adderall XR
- ✅ **ADDED**: Default dose picker (5, 10, 15, 20, 25, 30 mg)
- ✅ **ADDED**: Default formulation picker when both IR/XR selected
- ✅ **ADDED**: Info section explaining duplicate guard and session linking

**Settings Location:** Settings → Medications → My Medications

#### Settings Additions

- ✅ **ADDED**: "Undo" section with speed picker in Settings
- ✅ **ADDED**: "Medications" navigation link to MedicationSettingsView
- ✅ **ADDED**: `undoWindowSeconds` user preference (default: 5.0)
- ✅ **ADDED**: `userMedications` array for tracking selected medications

---

## Recent Updates (v2.4.2)

### New in v2.4.2 (MedicationLogger & Schema Enhancements)

#### MedicationLogger Feature (First-Class Adderall Tracking)

- ✅ **ADDED**: `medication_events` SQLite table for session-linked medication logging
- ✅ **ADDED**: `MedicationType` model with Adderall IR/XR support (extendable)
- ✅ **ADDED**: `MedicationPickerView` - Quick one-handed medication entry form
- ✅ **ADDED**: Duplicate guard (5-minute window, user confirmation for overrides)
- ✅ **ADDED**: UI integration in PreSleepLogView Card 2 (Substances section)

**Schema columns:** `id`, `session_id`, `session_date`, `medication_id`, `dose_value`, `dose_unit`, `formulation`, `taken_at_utc`, `local_offset_minutes`, `notes`, `confirmed_duplicate`, `created_at`

**Design goals:**
- First-class medication tracking (not hacked into text fields)
- Session-linked for correlation with sleep quality
- Timezone-aware with `local_offset_minutes`
- Flexible dose units (mg default) and formulation tracking (ir/xr)

#### Dose 2 Window Override

- ✅ **CHANGED**: Window Expired phase now allows late dose with confirmation
- ✅ **ADDED**: `takeWithOverride` CTA case in `DoseActionPrimaryCTA`
- ✅ **ADDED**: Confirmation dialog before taking late Dose 2
- ✅ **ADDED**: "Take Dose 2 (Late)" button in red when window expired (240+ minutes)

**Behavior:** After 240 minutes, the window is expired but user can still take Dose 2 by confirming "I understand the window has expired". Logged as "Dose 2 (Late)" event.

#### Schema Enhancements

- ✅ **ADDED**: `local_offset_minutes` - Timezone offset at log time (e.g., -300 for EST)
- ✅ **ADDED**: `dose_unit` - Flexible dose units ("mg" default, extensible)
- ✅ **ADDED**: `formulation` - IR/XR tracking ("ir", "xr")
- ✅ **CHANGED**: `dose_mg` → `dose_value REAL` for decimal dose support
- ✅ **FIXED**: Session cascade delete now includes `medication_events`
- ✅ **FIXED**: CSV export includes all new columns

#### Test Coverage
- Added `MedicationLoggerTests.swift` with 16 tests:
  - MedicationType configuration validation
  - Session date boundary computation (6 PM rule)
  - Duplicate guard absolute time delta (forward/backward)
  - Guard window boundary tests

---

## Recent Updates (v2.4.1)

### New in v2.4.1 (Sleep Environment & Documentation)

#### Sleep Environment Feature (V1 Question Set)

- ✅ **ADDED**: `sleepEnvironmentSection` in Morning Check-In with 18 sleep aid options
- ✅ **ADDED**: "Same as usual" shortcut (10-second completion)
- ✅ **ADDED**: Conditional follow-ups: screen time, sound type, darkness/noise ratings
- ✅ **ADDED**: `has_sleep_environment`, `sleep_environment_json` columns in SQLite

**Design goals:**
- 10 seconds if "Same as usual"
- 25 seconds for full entry
- High-signal correlation data without ML

#### Documentation Updates

- ✅ **ADDED**: `docs/DATABASE_SCHEMA.md` - Comprehensive database schema reference
- ✅ **UPDATED**: Sleep Environment section with V1 question set specification
- ✅ **FIXED**: SessionRepository.swift added to Xcode project (was missing from build)

---

## Recent Updates (v2.4.0)

### v2.4.0 (Dose 2 Safety & History Fixes)

#### Architecture Fix: SessionRepository (Single Source of Truth)

- ✅ **FIXED**: **Two sources of truth bug** - History delete now properly clears Tonight state
- ✅ **ADDED**: `SessionRepository.swift` - Single source of truth for session state
- ✅ **FIXED**: **Delete not updating Tonight** - SessionRepository broadcasts changes via Combine
- ✅ **ADDED**: `SessionRepositoryTests.swift` - Deterministic tests for delete/state sync

The previous architecture had `DoseTapCore` (in-memory) and `EventStorage` (SQLite) as separate sources of truth. Deleting from History modified SQLite but Tonight continued reading stale in-memory state.

**New architecture:**

- `SessionRepository` owns published session state (`dose1Time`, `dose2Time`, etc.)
- All delete/mutation operations go through `SessionRepository`
- `SessionRepository.sessionDidChange` broadcasts to all observers
- `ContentView` syncs `DoseTapCore` from `SessionRepository` on changes
- Delete from History → SessionRepository.deleteSession() → clears state → broadcasts → Tonight updates

#### Bug Fixes (v2.4.0)
- ✅ **FIXED**: **History delete not refreshing** - SelectedDayView now receives `refreshTrigger` that forces reload after deletion
- ✅ **FIXED**: **Early Dose 2 not updating UI** - `takeDose(earlyOverride:)` now accepts override flag; early doses update `dose2Time` immediately and show "(Early)" badge in orange
- ✅ **FIXED**: **Multiple Dose 2 overwrites** - Second Dose 2 attempt is blocked with major stop warning; if user confirms, recorded as `extra_dose` event type without overwriting original `dose2_time`

#### New Safety Features
- ⚠️ **Extra Dose Warning**: Attempting to log Dose 2 when already taken shows blocking alert: "STOP - Dose 2 Already Taken" with explicit health hazard framing
- ⚠️ **Extra Dose Recording**: If user confirms extra dose, it's stored with `is_extra_dose: true` metadata and event type `extra_dose` (NOT overwriting original)
- 🔶 **Early Dose Badge**: Doses taken before window opens show orange color and "(Early)" label in event list

#### Data Model Changes
- `saveDose2(timestamp:isEarly:isExtraDose:)` - New parameters for metadata tracking
- `extra_dose` event type added to dose_events table
- Metadata fields: `is_early`, `is_extra_dose` stored as JSON in dose_events.metadata

#### Test Coverage
- Added `Dose2EdgeCaseTests.swift` with 15 deterministic tests:
  - Early dose 2 scenarios (before window, 120 minutes, exact 150 boundary)
  - Extra dose blocking (completed phase, disabled primary action)
  - Interval calculations (normal, near-close, exact boundaries)
  - Window boundary tests (149/150/239/240/241 minute edges)
  - Skip behavior tests

### Previous Updates (v2.3.0)

### New in v2.3.0 (Spec Consistency Audit)

#### P0 Fixes (Breaking Contradictions Resolved)
- ✅ **FIXED**: Target interval enum enforced - Only [165, 180, 195, 210, 225] valid (was incorrectly showing 150-240 range in Setup Wizard)
- ✅ **FIXED**: Snooze duration is fixed at 10 minutes (removed incorrect 5/10/15 options from Setup Wizard)
- ✅ **FIXED**: Undo window is fixed at 5 seconds (removed incorrect 3-10 configurable range from Setup Wizard)
- ✅ **FIXED**: Persistence story - SQLite is the implementation (removed Core Data references)
- ✅ **FIXED**: Event system clarified - All 13 sleep event types defined, stored locally in SQLite
- ✅ **ADDED**: `constants.json` - Single source of truth for all numeric constants

#### P1 Fixes (Platform/Security)
- ✅ **FIXED**: Support bundle privacy claim - Changed "zero PII" to "PII minimized with automatic redaction + required user review"
- ✅ **FIXED**: Inventory notification - Changed "cannot be dismissed" to "repeats daily until resolved" (iOS platform constraint)

#### State Naming (Literal, Explicit)
- States renamed to be brutally literal: `NoSession`, `SessionActiveBeforeWindow`, `WindowOpen`, `WindowNearClose`, `WindowExpired`, `Dose2Taken`, `Dose2Skipped`

### v2.2.0 (Critical Fixes & Alarm System)

#### Bug Fixes
- ✅ **FIXED**: Event display bug - Sleep events now correctly associate with sessions using 12-hour timestamp proximity matching instead of date-string matching
- ✅ **FIXED**: Orphaned events - Timeline creates synthetic sessions for sleep events without matching dose events, ensuring no logged events are lost
- ✅ **FIXED**: Tonight's Events section added to TonightView showing expandable list of all logged sleep events with count, icons, and timestamps

#### Wake Alarm System (NEW)
- ✅ **IMPLEMENTED**: Target wake time setup with validation against dose window (150-240min)
- ✅ **IMPLEMENTED**: Wake alarm scheduling with pre-alarm (5min), main alarm, and follow-up alarms (every 2min x3)
- ✅ **IMPLEMENTED**: Hard stop warnings at 15min, 5min, 2min, 30sec before window close
- ✅ **IMPLEMENTED**: Window expired notification when 240min passes
- ✅ **IMPLEMENTED**: Stop alarm action to dismiss alarms without taking dose

#### Enhanced Notification Service
- `setTargetWakeTime()` - Validate and store target wake time
- `scheduleWakeAlarm()` - Schedule escalating wake alarms
- `scheduleHardStopWarnings()` - Schedule hard stop countdown alerts
- `stopAllAlarms()` - Stop all active alarms

### Known Gaps (v2.4.0) - Identified for Future Work

| Gap | Description | Priority |
|-----|-------------|----------|
| ~~**Undo Support**~~ | ✅ FIXED in v2.4.3 - Undo snackbar with configurable speed (3-10s), full state reversal | ~~High~~ |
| ~~**Session Terminal State**~~ | ✅ FIXED in v2.4.0 - SQLite now has `terminal_state` column via migration | ~~Medium~~ |
| ~~**History Delete State Sync**~~ | ✅ FIXED in v2.4.0 - SessionRepository pattern ensures Tonight clears on delete | ~~High~~ |
| ~~**Finalizing State**~~ | ✅ FIXED in v2.4.6 - Track session between wakeFinal and check-in via `.finalizing` phase | ~~Medium~~ |
| ~~**Sleep-Through Handling**~~ | ✅ FIXED in v2.4.7 - Auto-mark incomplete on app foreground if window+30min grace passed | ~~Medium~~ |
| ~~**Late Dose 1 Logic**~~ | ✅ FIXED in v2.4.8 - `lateDose1Info()` detects midnight-6AM zone, returns session date label | ~~Low~~ |
| ~~**Timezone Changes**~~ | ✅ FIXED in v2.4.9 - `checkTimezoneChange()` detects and describes timezone shifts | ~~Low~~ |
| ~~**Early Dose Override**~~ | ✅ FIXED in v2.4.0 - Confirmation dialog for Dose 2 before window opens | ~~Low~~ |
| ~~**Alarm UI Indicator**~~ | ✅ FIXED in v2.4.4 - AlarmIndicatorView shows scheduled wake time in Tonight header | ~~Medium~~ |
| ~~**Hard Stop Countdown**~~ | ✅ FIXED in v2.4.4 - HardStopCountdownView + CompactStatusCard shows countdown when <15 min remain | ~~Medium~~ |

### Previous (v2.1.0)
- ✅ **COMPLETED**: Swipe Navigation (horizontal page-style TabView with custom bottom tab bar)
- ✅ **COMPLETED**: Compact Tonight Screen (no vertical scroll, integrated timer)
- ✅ **COMPLETED**: History Page (date picker to view past days' doses and events)
- ✅ **COMPLETED**: Data Management (delete history from Settings and History pages)
- ✅ **COMPLETED**: Multi-select session deletion with confirmation dialogs
- ✅ **COMPLETED**: Dose events logged (Dose 1/2 appear in event timeline)
- ✅ **COMPLETED**: SQLite persistence for events with session linking

### Previous (v2.0.0)
- ✅ **COMPLETED**: Sleep Event Logging System (13 event types with rate limiting)
- ✅ **COMPLETED**: QuickLogPanel UI component with cooldown indicators
- ✅ **COMPLETED**: Timeline View with historical session display
- ✅ **COMPLETED**: UnifiedSleepSession data model (DoseTap + HealthKit + WHOOP)
- ✅ **COMPLETED**: SQLite storage for sleep_events table
- ✅ **COMPLETED**: DoseCore unit tests passing (run `swift test -q` for current count)
- ✅ **COMPLETED**: WHOOP OAuth integration tested (using non-production test account; no personal identifiers in SSOT)
- 🔄 Phase 2: Health Dashboard with data aggregation (next priority)
- 🔄 WHOOP data visualization and correlation insights

## Implementation Status

### ✅ Phase 1.5 Complete (UI Overhaul - v2.1.0)
- Swipe navigation with page-style TabView (`ios/DoseTap/ContentView.swift`)
- Custom bottom tab bar with 4 tabs (Tonight, Details, History, Settings)
- Compact Tonight screen (no scroll, integrated timer)
- History page with date picker navigation
- Data management with multi-select deletion (`ios/DoseTap/SettingsView.swift`)
- SQLite delete methods (`ios/DoseTap/Storage/EventStorage.swift`)
- Dose events logged in timeline (Dose 1/2 appear as events)

### ✅ Phase 1 Complete (Sleep Event Logging)
- SleepEvent model with 13 event types (`ios/Core/SleepEvent.swift`)
- EventRateLimiter with per-event cooldowns (`ios/Core/EventRateLimiter.swift`)
- SQLite sleep_events table (`ios/DoseTapiOSApp/SQLiteStorage.swift`)
- QuickLogPanel UI with 4x4 grid (`ios/DoseTapiOSApp/QuickLogPanel.swift`)
- TimelineView historical display (`ios/DoseTapiOSApp/TimelineView.swift`)
- DoseCoreIntegration.logSleepEvent() (`ios/DoseTapiOSApp/DoseCoreIntegration.swift`)
- UnifiedSleepSession data model (`ios/Core/UnifiedSleepSession.swift`)
- DoseCoreTests via SwiftPM (CI is source of truth for count)

### 🔄 Phase 2: Health Dashboard (In Progress)
- SleepDataAggregator for merging data sources
- Enhanced DashboardView with health cards
- HeartRateChartView, SleepStagesChart components
- WHOOP Recovery visualization

### 🆕 Phase 2.5: Morning Check-In (NEW)
- MorningCheckIn data model (`ios/Core/MorningCheckIn.swift`)
- SQLite morning_checkins table (`ios/DoseTap/Storage/EventStorage.swift`)
- MorningCheckInView with Quick Mode + Deep Dive (`ios/DoseTap/Views/MorningCheckInView.swift`)
- Session correlation queries for specialist reports
- Narcolepsy symptom tracking (sleep paralysis, hallucinations, automatic behavior)
- Physical symptoms with body part picker and pain severity
- Respiratory/illness tracking
- Wellness score calculation for trend analysis

### 📋 Phase 3: Advanced Analytics (Planned)
- Dose-sleep correlation insights
- Personalized recommendations
- Export enhancements

## Core Invariants

### Medication Scope
- **Primary Focus**: XYWAV dose timing (150-240 minute window)
- **Secondary Logging**: All FDA-approved narcolepsy medications (15 total) for daytime tracking
- **Dose Window**: Dose 2 must be taken 150–240 minutes after Dose 1
- **Default Target**: 165 minutes (2h 45m)
- **Safety**: Never combine doses, never exceed window, always enforce stay-in-bed protocol
- **Out of Scope**: Refills, pharmacy integration, provider portals

### Supported Medications (v2.4.5)

| Category | Medications |
|----------|-------------|
| **Stimulants** | Adderall IR, Adderall XR, Ritalin IR, Ritalin LA, Concerta, Vyvanse, Dexedrine |
| **Wakefulness Agents** | Modafinil, Provigil, Armodafinil, Nuvigil, Sunosi |
| **Histamine Modulators** | Wakix |
| **Sodium Oxybate** | XYWAV, Xyrem, Lumryz (once-nightly) |

### Dose Timing Parameters (AUTHORITATIVE)

| Parameter | Value | Notes |
|-----------|-------|-------|
| Window Opens | **150 minutes** | After Dose 1 |
| Window Closes | **240 minutes** | After Dose 1 (hard limit) |
| Default Target | **165 minutes** | User configurable |
| Valid Targets | **165, 180, 195, 210, 225** | Only these 5 options |
| Snooze Duration | **10 minutes** | Fixed |
| Max Snoozes | **3 per night** | Counter resets with new session |
| Snooze Disabled | **<15 min remaining** | Safety rule |
| Undo Window | **5 seconds** | For all dose actions |
| On-Time Threshold | **±10 minutes** | For adherence metrics |

### Window Behavior
- **Snooze Availability**: Disabled when <15 minutes remain in window
- **Window Close**: All dose actions disabled when window expires
- **Undo Window**: 5-second undo available for all dose actions
- **Offline Support**: Actions queue locally, sync when connected

### Notification Schedule

| Alert | Time After Dose 1 | Action |
|-------|-------------------|--------|
| Window Opens | 150 min | Take Now / Snooze / Skip |
| Target Time | 165 min (default) | Escalating urgency |
| 30 min warning | 210 min | Yellow indicator |
| 15 min warning | 225 min | Red warning, snooze disabled |
| 5 min warning | 235 min | Critical alert |
| 1 min warning | 239 min | Final warning |
| Window Expired | 240 min | Override required (red button, confirmation dialog) |

**Window Expired Override**: When 240 minutes have passed, user CAN still take Dose 2 but must explicitly confirm via a warning dialog. Button shows "Take Dose 2 (Late)" in red. This ensures the user makes a conscious decision while not completely blocking the dose.

**Normative rule**: At window expiry ($\ge 240$ minutes), the standard “Take Dose 2” action is blocked. The only allowed path to record a Dose 2 is the explicit late-override CTA + confirmation.

## Wake Alarm System (NEW in v2.2.0)

### Overview
User can set a target wake time at session start. The app validates the time against the dose window and schedules escalating wake alarms to ensure Dose 2 is taken on time.

### Target Wake Time Setup
- **When**: After Dose 1 is logged, user can optionally set target wake time
- **Validation**: Wake time must be within dose window (150-240 min after Dose 1)
- **Warning**: If wake time is before window opens or after window closes, user is warned
- **Storage**: Persisted in UserDefaults, cleared on session completion

### Wake Alarm Schedule

| Alarm | Timing | Type | Actions |
|-------|--------|------|---------|
| Pre-alarm | Target - 5 min | Standard | Dismiss |
| Main alarm | Target time | Critical | Take Now / Stop / Snooze |
| Follow-up 1 | Target + 2 min | Critical | Take Now / Stop / Snooze |
| Follow-up 2 | Target + 4 min | Critical | Take Now / Stop / Snooze |
| Follow-up 3 | Target + 6 min | Critical | Take Now / Stop / Snooze |

### Hard Stop Warning Schedule

| Warning | Time Before Window Close | Type | Actions |
|---------|-------------------------|------|---------|
| 15 min | 225 min after Dose 1 | Standard | Take Now / Snooze / Skip |
| 5 min | 235 min after Dose 1 | Critical | Take Now / Skip |
| 2 min | 238 min after Dose 1 | Critical | Take Now / Skip |
| 30 sec | 239.5 min after Dose 1 | Critical | Take Now / Skip |
| Expired | 240 min after Dose 1 | Critical | Dismiss (session incomplete) |

### Alarm Actions
- **Take Now**: Takes Dose 2, stops all alarms, cancels remaining notifications
- **Stop Alarm**: Stops current alarm sound without taking dose
- **Snooze**: Stops alarm, adds 10 min to target, reschedules notifications

### API Methods (`EnhancedNotificationService`)
```swift
func setTargetWakeTime(_ wakeTime: Date, dose1Time: Date) -> (valid: Bool, message: String)
func scheduleWakeAlarm(at time: Date, dose1Time: Date)
func scheduleHardStopWarnings(dose1Time: Date)
func stopAllAlarms()
func clearTargetWakeTime()
```

## Sleep Event System (NEW in v2.0)

### Event Types (13 total)

> Canonical source: [constants.json](constants.json)

| Event | Raw Value | Cooldown | Category | Icon |
|-------|-----------|----------|----------|------|
| Bathroom | `bathroom` | 60s | Physical | 🚽 |
| Water | `water` | 60s | Physical | 💧 |
| Snack | `snack` | 60s | Physical | 🍴 |
| In Bed | `inBed` | 0 | Sleep Cycle | 🛏️ |
| Lights Out | `lightsOut` | 0 | Sleep Cycle | 💡 |
| Final Wake | `wakeFinal` | 0 | Sleep Cycle | ☀️ |
| Temp Wake | `wakeTemp` | 0 | Sleep Cycle | 🌙 |
| Anxiety | `anxiety` | 0 | Mental | 🧠 |
| Dream | `dream` | 0 | Mental | ☁️ |
| Heart Racing | `heartRacing` | 0 | Mental | ❤️ |
| Noise | `noise` | 0 | Environment | 🔊 |
| Temperature | `temperature` | 0 | Environment | 🌡️ |
| Pain | `pain` | 0 | Environment | 🩹 |

> **Note**: Only physical events (bathroom, water, snack) have 60s cooldowns to prevent accidental double-taps. All other events have no cooldown—log as often as experienced.

### Event Categories

| Category | Color | Events |
|----------|-------|--------|
| Physical | Blue | bathroom, water, snack |
| Sleep Cycle | Indigo | inBed, lightsOut, wakeFinal, wakeTemp |
| Mental | Purple | anxiety, dream, heartRacing |
| Environment | Green | noise, temperature, pain |

### QuickLog Panel (Customizable)

**Grid Layout**: 4x4 (up to 16 slots)

| Feature | Value |
|---------|-------|
| Max slots | 16 |
| Layout | 4 columns × 4 rows |
| Customizable | Yes - user picks which events appear |
| Custom events | User can create up to 8 custom event types |

**Customization** (Settings → QuickLog):
- Drag to reorder slots
- Tap + to add event type (built-in or custom)
- Swipe to remove from panel
- Create custom events with name, icon, color

### Rate Limiting (Revised)

**Only physical events have cooldowns** (to prevent accidental double-taps):

| Event | Cooldown | Rationale |
|-------|----------|-----------|
| bathroom | 60s | Prevent double-tap |
| water | 60s | Prevent double-tap |
| snack | 60s | Prevent double-tap |
| All others | **None** | Log as often as experienced |

> **Rationale**: Mental/environment events (anxiety, pain, noise, etc.) should be loggable without restriction. If you're anxious multiple times, log it multiple times.

- UI shows circular progress indicator during cooldown
- Haptic feedback on successful log
- Events stored in SQLite with session linking

### History View (Sort & Filter)

| Sort Option | Description |
|-------------|-------------|
| Newest First | Default - most recent at top |
| Oldest First | Chronological order |
| A-Z | Alphabetical by event type |
| Z-A | Reverse alphabetical |

**Filters**:
- By event type (multi-select)
- By date range
- By category (physical, mental, etc.)

**Grouping**: Day (default), Week, Month, or None

## Morning Check-In System (NEW in v2.5)

### Overview
Comprehensive morning questionnaire for specialist reports. Uses progressive disclosure:
- **Quick Mode**: 5 core questions (~30 seconds)
- **Deep Dive**: Conditional expansion for symptoms

### Quick Mode Fields (Always Visible)

| Field | Type | Range | Default |
|-------|------|-------|---------|
| Sleep Quality | Stars | 1-5 | 3 |
| Feel Rested | Enum | notAtAll → veryWell | moderate |
| Grogginess | Enum | none → cantFunction | mild |
| Mental Clarity | Slider | 1-10 | 5 |
| Mood | Enum | veryLow → great | neutral |

### Deep Dive: Physical Symptoms (Conditional)

| Field | Type | Values |
|-------|------|--------|
| Pain Locations | Multi-select | head, neck, shoulders, upperBack, lowerBack, hips, legs, knees, feet, hands, arms, chest, abdomen |
| Pain Severity | Slider | 0-10 |
| Pain Type | Enum | aching, sharp, stiff, throbbing, burning, tingling, cramping |
| Headache Details | Nested | severity, location, isMigraine |
| Muscle Stiffness | Enum | none → severe |
| Muscle Soreness | Enum | none → severe |

### Deep Dive: Respiratory Symptoms (Conditional)

| Field | Type | Values |
|-------|------|--------|
| Congestion | Enum | none, stuffyNose, runnyNose, both |
| Throat | Enum | normal, dry, sore, scratchy |
| Cough | Enum | none, dry, productive |
| Sinus Pressure | Enum | none → severe |
| Feeling Feverish | Bool | false/true |
| Sickness Level | Enum | no, comingDown, activelySick, recovering |

### Narcolepsy-Specific Flags (Toggle List)

| Flag | Description |
|------|-------------|
| Sleep Paralysis | Inability to move upon waking |
| Hallucinations | Hypnagogic/hypnopompic hallucinations |
| Automatic Behavior | Performed actions without awareness |
| Fell Out of Bed | Related to cataplexy or vivid dreams |
| Confusion on Waking | Disorientation upon awakening |

### Sleep Environment (NEW in v2.5.1 / Updated v2.4.1)

> **V1 Question Set**: High-signal correlation data with minimal friction.
> **Time Target**: 10 seconds if "Same as usual", 25 seconds for full entry.

#### Card: "Sleep Setup & Aids"

**A) Sleep Aids Used (Multi-select Chips)**

Label: "What did you use last night?"

| Aid | Category | Icon | Note |
|-----|----------|------|------|
| Dark room/blackout | Environment | moon.fill | |
| Eye mask | Environment | eye.slash.fill | |
| Earplugs | Environment | ear.badge.checkmark | |
| White noise/sound | Environment | waveform | Triggers sound type follow-up |
| Fan | Environment | fan.fill | |
| Weighted blanket | Environment | bed.double.fill | |
| Heating pad | Environment | flame.fill | |
| Humidifier | Environment | humidity.fill | |
| Meditation/breathing | Relaxation | brain.head.profile | |
| Music | Relaxation | music.note | |
| Podcast/audiobook | Relaxation | headphones | |
| CPAP | Medical | wind | |
| Mouth tape | Medical | mouth | |
| Nasal strip | Medical | nose | |
| **TV on** | **Screen** | tv.fill | ⚠️ Behavior, not aid - triggers screen time follow-up |
| **Phone in bed** | **Screen** | iphone | ⚠️ Behavior, not aid - triggers screen time follow-up |
| Other | Meta | ellipsis.circle | Shows optional 50-char text field |
| None | Meta | xmark.circle | Clears all others |

**Design notes:**
- Chips are tap-to-toggle
- "None" chip clears all others
- Screen behaviors (TV, Phone) are visually tagged in orange

**B) Lights and Noise Quick Ratings (2 single taps)**

Only shown if user doesn't select "Same as usual":

| Field | Values | Icon |
|-------|--------|------|
| Room Darkness | Bright, Dim, Dark | sun.max.fill → moon.fill |
| Noise Level | Quiet, Some noise, Loud | speaker.fill → speaker.wave.3.fill |

**C) Screen Time Follow-up (if TV/Phone selected)**

Label: "How long was screen on?"

| Bucket | Data Key |
|--------|----------|
| 0-15 min | `0_15` |
| 15-45 min | `15_45` |
| 45+ min | `45_plus` |

**D) Sound Type Follow-up (if White Noise selected)**

| Type | Data Key |
|------|----------|
| White noise | `white_noise` |
| Rain | `rain` |
| Fan | `fan` |
| Other | `other` |

#### Data Model Keys (Export-Ready)

All fields stored in `sleep_environment_json` column:

```json
{
  "sleep_aids_used": ["Dark room/blackout", "Eye mask", "White noise/sound"],
  "room_darkness": "dark",        // bright | dim | dark
  "noise_level": "quiet",          // quiet | some_noise | loud
  "screen_in_bed_minutes_bucket": "0_15",  // 0_15 | 15_45 | 45_plus | unknown
  "sound_type": "white_noise",     // white_noise | rain | fan | other | unknown
  "other_aid_text": "",            // Optional, max 50 chars
  "same_as_usual": false           // true if shortcut used
}
```

#### Export CSV Column Definitions

| Column | Type | Description |
|--------|------|-------------|
| `sleep_aids_used` | String (JSON array) | Array of aid names selected |
| `room_darkness` | Enum | bright, dim, dark |
| `noise_level` | Enum | quiet, some_noise, loud |
| `screen_minutes_bucket` | Enum | 0_15, 15_45, 45_plus, unknown |
| `sound_type` | Enum | white_noise, rain, fan, other, unknown |
| `other_aid_text` | String (50 max) | Free text, optional |
| `same_as_usual` | Bool | Whether shortcut was used |

#### "Same as Usual" Shortcut

- Stores last session's selections in UserDefaults
- Single tap auto-fills: sleep_aids_used, room_darkness, noise_level
- Hides all follow-up questions when selected
- Sets `same_as_usual: true` in JSON

#### Dashboard Correlation Insights (No ML Required)

Without ML, simple descriptive correlations:

| Correlation | Description |
|-------------|-------------|
| Sleep quality vs TV on | % change in sleep quality on TV nights |
| Wake events vs noise | Wake count by noise level |
| Sleep inertia vs phone | Morning grogginess by screen bucket |
| Dose 2 adherence vs screen | Skip/early rate by screen time |

**SQLite Columns (via migration):**
```sql
ALTER TABLE morning_checkins ADD COLUMN has_sleep_environment INTEGER DEFAULT 0;
ALTER TABLE morning_checkins ADD COLUMN sleep_environment_json TEXT;
```

### Wellness Score Calculation

```
Score = (sleepQuality/5 × 30) +
        (feelRested/5 × 25) +
        (mentalClarity/10 × 20) +
        (mood/5 × 15) +
        (readiness/5 × 10) -
        (hasPhysical ? 10 : 0) -
        (hasRespiratory ? 5 : 0) -
        (hasNarcolepsy ? 5 : 0)

Range: 0-100
```

### SQLite Schema

```sql
CREATE TABLE morning_checkins (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    session_date TEXT NOT NULL,
    sleep_quality INTEGER NOT NULL DEFAULT 3,
    feel_rested TEXT NOT NULL DEFAULT 'moderate',
    grogginess TEXT NOT NULL DEFAULT 'mild',
    sleep_inertia_duration TEXT NOT NULL DEFAULT 'fiveToFifteen',
    dream_recall TEXT NOT NULL DEFAULT 'none',
    has_physical_symptoms INTEGER NOT NULL DEFAULT 0,
    physical_symptoms_json TEXT,
    has_respiratory_symptoms INTEGER NOT NULL DEFAULT 0,
    respiratory_symptoms_json TEXT,
    mental_clarity INTEGER NOT NULL DEFAULT 5,
    mood TEXT NOT NULL DEFAULT 'neutral',
    anxiety_level TEXT NOT NULL DEFAULT 'none',
    readiness_for_day INTEGER NOT NULL DEFAULT 3,
    had_sleep_paralysis INTEGER NOT NULL DEFAULT 0,
    had_hallucinations INTEGER NOT NULL DEFAULT 0,
    had_automatic_behavior INTEGER NOT NULL DEFAULT 0,
    fell_out_of_bed INTEGER NOT NULL DEFAULT 0,
    had_confusion_on_waking INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

## Application Architecture

### Navigation Structure (v2.1.0)

**4-Tab Layout with Swipe Navigation:**
| Tab | Name | Purpose | Scroll |
|-----|------|---------|--------|
| 1 | Tonight | Compact dose tracking, quick events | No scroll |
| 2 | Details | Full session info, event timeline | Scrollable |
| 3 | History | View past days via date picker | Scrollable |
| 4 | Settings | Configuration, data management | Scrollable |

**Navigation Type:** Horizontal swipe (`.tabViewStyle(.page)`) + custom bottom tab bar

### Screens & States

> **Note:** All constants defined in [`constants.json`](constants.json). State names are literal and explicit.

#### Tonight Screen (Primary) - COMPACT LAYOUT
- **States** (literal naming per SSOT):
  - `NoSession` - Ready for Dose 1
  - `SessionActiveBeforeWindow` - Dose 1 taken, window not yet open (<150m)
  - `WindowOpen` - Window open, Dose 2 available (150-225m)
  - `WindowNearClose` - Window closing soon, snooze disabled (225-240m)
  - `WindowExpired` - 240m passed without Dose 2
  - `Dose2Taken` - Session complete, Dose 2 taken
  - `Dose2Skipped` - Session complete, Dose 2 skipped
- **Near-Window Rules**:
  - Disable snooze <15m remaining
  - Show countdown timer
  - Block all actions at window expiry
- **Layout**: Compact, single-screen *by design*, but must not be visually cut off by the custom bottom tab bar.
  - If content doesn't fit (smaller devices / dynamic type), the view MUST scroll and include a bottom inset/padding so primary CTAs (e.g. `wake_up_button`) remain reachable.
- **Components**:
  - `compact_status_card` (integrated status + timer display)
  - `compact_dose1_button`
  - `compact_dose2_button`
  - `quick_log_panel` (4 quick event buttons: Bathroom, Water, Brief Wake, Anxiety)
  - `wake_up_button` (prominent "Wake Up & End Session" button)
  - `compact_session_summary`


#### Wake Up & End Session Flow (NEW in v2.5)

- **Trigger**: User taps "Wake Up & End Session" button on Tonight screen
- **Action Sequence**:
  1. Log `wakeFinal` event to SQLite
  2. Present Morning Check-In sheet
  3. User completes questionnaire (Quick Mode or Deep Dive)
  4. Session marked as complete
- **Cooldown**: 3600s (1 hour) - prevents accidental retap
- **UI**: Prominent yellow button with sun icon, different from other event buttons


#### Details Screen (Full Event Grid)

- **Purpose**: Full session details and all 13 event buttons
- **States**: `loading`, `ready`, `empty`
- **Scroll**: Vertical scroll enabled
- **Components**:
  - `session_details_card` (Dose 1/2 times, window times, interval, snoozes)
  - `full_event_grid` (13 sleep event buttons including Wake Up)
  - Note: Wake Up here just logs event, doesn't trigger Morning Check-In


#### History Screen (NEW in v2.1.0)

- **Purpose**: View past days' doses and events with date navigation
- **States**: `loading`, `ready`, `empty`, `error`
- **Components**:
  - `date_picker` (calendar strip)
  - `selected_day_view` (doses + events for selected date)
  - `delete_day_button` (trash icon with confirmation)
- **Actions**:
  - Navigate to any past date
  - View dose times and events for selected day
  - Delete individual day's data with confirmation

#### Timeline Screen (Legacy)

---

## Settings & Navigation Behavior (UX Guarantees)

### Settings is a Tab (Not a Sheet)

- The Settings screen is displayed as Tab 4 in the 4-tab swipe navigation.
- Because Settings is not presented modally, there is **no "Done" button** for dismissal.
- Exiting Settings is done by navigating to another tab (swipe or tap in the bottom tab bar).

### Content must not be obscured by the bottom tab bar

- Any screen that places interactive controls near the bottom edge MUST include adequate bottom padding/inset to avoid overlap with the custom tab bar.
- If the screen is "compact" but could exceed viewport height, scrolling is allowed and preferred over truncation.

---

## HealthKit Integration Contract (Authorization vs Enable)

DoseTap tracks **two distinct states** for Apple Health integration:

1. **OS Authorization (HealthKit)**

- Source of truth: `HKHealthStore.authorizationStatus(for: .sleepAnalysis)`
- Derived flag: `HealthKitService.isAuthorized`
- Requirement: `HealthKitService` MUST restore/check authorization status on initialization (app launch) so UI reflects the true OS permission state.

1. **User Preference (App-level Toggle)**

- Source of truth: `UserSettingsManager.healthKitEnabled` (`@AppStorage("healthkit_enabled")`)
- Meaning: user has opted-in to using sleep data within DoseTap
- Default: `false` until user explicitly enables

### Effective Enable Rule

- HealthKit-derived sleep features are enabled only when:
  - `HealthKitService.isAuthorized == true` AND
  - `UserSettingsManager.healthKitEnabled == true`

- **Purpose**: Historical dose events and sleep patterns
- **States**: `loading`, `ready`, `empty`, `error`
- **Components**:
  - `timeline_list` (expandable session cards)
  - `timeline_filter`
  - `timeline_export_button`
  - `session_event_details` (NEW)

#### Dashboard Screen (NEW)

- **Purpose**: Health metrics and insights
- **Components**:
  - `tonights_sleep_card`
  - `heart_rate_chart`
  - `whoop_recovery_card`
  - `dose_insights_card`

#### Insights Screen

- **Analytics**: On-time %, Dose1→Dose2 intervals, natural-wake %, WASO
- **States**: `loading`, `ready`, `insufficient_data`
- **Components**:
  - `insights_chart`
  - `insights_summary`
  - `insights_export`

#### Devices Screen

- **Features**: Flic button pairing, device registration
- **States**: `scanning`, `paired`, `disconnected`
- **Components**:
  - `devices_list`
  - `devices_add_button`
  - `devices_test_button`

#### Settings Screen

- **Configuration**: Target interval, notifications, accessibility, data management
- **Components**:
  - `settings_target_picker`
  - `settings_notifications`
  - `settings_accessibility`
  - `data_management_section` (NEW)

#### Data Management Screen (NEW in v2.1.0)

- **Purpose**: Delete history and manage stored data
- **Access**: Settings → Manage History
- **Components**:
  - `quick_actions_section` (Clear All, Clear Old)
  - `session_list` (multi-select with EditMode)
  - `bulk_delete_button` (Delete Selected)
  - `swipe_to_delete` (individual session delete)
- **Actions**:
  - Clear all sleep events
  - Clear data older than X days
  - Multi-select sessions for bulk delete
  - Swipe-to-delete individual sessions
- **Confirmation**: All destructive actions require confirmation dialog

#### watchOS Companion

- **Features**: Dose taking, timer display, haptic feedback
- **States**: `syncing`, `ready`, `offline`
- **Components**:
  - `watch_dose_button`
  - `watch_timer`
  - `watch_complications`

## New Features (v1.1.0)

### First-Run Setup Wizard

- **Purpose**: Guided 5-step onboarding to establish user preferences and core invariant
- **Steps**: Sleep schedule → Medication profile → Dose window rules → Notifications → Privacy
- **Completion**: Required before accessing main application
- **Re-run**: Available from Settings → "Reconfigure Setup"
- **Contract**: See `docs/SSOT/contracts/SetupWizard.md`

### Inventory Management
- **Purpose**: Track medication supply, calculate remaining doses, trigger refill reminders
- **Components**: Current inventory display, refill logging, reminder thresholds
- **Events**: `refill_logged`, `refill_reminder`, `inventory_adjustment`
- **Export**: New `inventory.csv` export format
- **Contract**: See `docs/SSOT/contracts/Inventory.md`

### Support Bundle System
- **Purpose**: Privacy-safe diagnostic data export for troubleshooting
- **Privacy**: Zero PII by default, anonymized timestamps, generalized medication names
- **Contents**: events.csv, inventory.csv, app_metadata.json, debug_log.txt
- **Export**: ZIP archive via iOS share sheet
- **Contract**: See `docs/SSOT/contracts/SupportBundle.md`

### Enhanced Notifications
- **Actionable Alerts**: Take/Snooze/Skip actions directly from notification banner
- **Critical Alerts**: Persistent alerts for medical necessity (requires entitlement)
- **Smart Snooze**: Automatically disabled when <15 minutes remain in window
- **Focus Override**: Optional critical alert bypass for Focus/DND modes

### Time Zone Resilience
- **Auto-Detection**: Prompt user when timezone change detected
- **Travel Mode**: Recalculate and reschedule notifications for new timezone
- **DST Handling**: Maintain dose window integrity across time transitions
- **Edge Cases**: Handle overnight flights, short sleep windows, schedule conflicts

## Button Logic & Components

| Component ID | Preconditions | Action | API Call | Next State | Error Handling | Undo | Deep Link |
|--------------|---------------|--------|----------|------------|----------------|------|-----------|
| `tonight_dose1_button` | No dose1 today, not loading | Take Dose 1 | `POST /doses/take` | `dose1_taken` | Toast with retry | 5s undo | `dosetap://dose1` |
| `tonight_dose2_button` | Dose1 taken, in window (150-240m) | Take Dose 2 | `POST /doses/take` | `dose2_taken` | Toast with retry | 5s undo | `dosetap://dose2` |
| `tonight_snooze_button` | In window, >15m remaining, <3 snoozes | Snooze 10m | `POST /doses/snooze` | Stay current | Show limit reached | None | `dosetap://snooze` |
| `timeline_export_button` | Has data | Export CSV | `GET /analytics/export` | Show success | Retry dialog | None | N/A |
| `devices_test_button` | Device paired | Test connection | Local only | Flash/haptic | Show disconnected | None | N/A |
| `flic_single_press` | Paired, app active | Take next dose | Route to dose1/2 | Per dose button | Per dose button | 5s undo | N/A |
| `flic_double_press` | In window | Snooze | `POST /doses/snooze` | Stay current | Haptic error | None | N/A |
| `flic_hold` | Any time | Cancel/undo last | Undo if available | Previous state | Haptic confirm | None | N/A |

## API Contract

> 🔄 **STATUS: PLANNED** — The API contract below is designed but not yet implemented.  
> The app currently operates in local-first mode with SQLite storage.  
> API calls use `MockAPITransport` for development. Production server is future work.

### Base Configuration
- **Base URL**: `https://api.dosetap.com/v1` (production, planned)
- **Auth**: Bearer token in header
- **Content-Type**: `application/json`
- **Timeout**: 30 seconds
- **Retry**: 3 attempts with exponential backoff

### Endpoints

#### POST /doses/take
Records a dose taken event.

**Request:**
```json
{
  "type": "dose1|dose2",
  "timestamp": "2024-01-15T22:30:00Z"
}
```

**Response (200 OK):**
```json
{
  "id": "evt_123456",
  "type": "dose1",
  "timestamp": "2024-01-15T22:30:00Z",
  "next_window_opens": "2024-01-16T01:00:00Z",
  "next_window_closes": "2024-01-16T02:30:00Z"
}
```

#### POST /doses/skip
Records skipping dose 2.

**Request:**
```json
{
  "sequence": 2,
  "reason": "optional reason string"
}
```

**Response (200 OK):**
```json
{
  "id": "evt_123457",
  "type": "skip",
  "sequence": 2,
  "timestamp": "2024-01-16T01:30:00Z"
}
```

#### POST /doses/snooze
Delays dose reminder by 10 minutes.

**Request:**
```json
{
  "minutes": 10
}
```

**Response (200 OK):**
```json
{
  "snooze_until": "2024-01-16T01:40:00Z",
  "snoozes_used": 1,
  "snoozes_remaining": 2
}
```

#### POST /events/log
Logs sleep/wake events for optional cloud sync. **Note**: Sleep events are primarily stored locally in SQLite. This endpoint is for future sync functionality.

**Request:**
```json
{
  "type": "bathroom|water|snack|lightsOut|wakeFinal|wakeTemp|anxiety|dream|heartRacing|noise|temperature|pain",
  "timestamp": "2024-01-15T22:30:00Z",
  "session_id": "optional-session-uuid"
}
```

**Response (200 OK):**
```json
{
  "id": "evt_123458",
  "type": "bathroom",
  "timestamp": "2024-01-15T22:30:00Z"
}
```

**Current Implementation**: All 13 sleep event types are stored locally in SQLite (`sleep_events` table). The API endpoint is reserved for future iCloud/backend sync—not currently wired. For SSOT completeness, the contract is defined; implementation is deferred.

#### GET /analytics/export
Exports dose and analytics data as CSV.

**Query Parameters:**
- `start_date`: ISO8601 date (optional, default 30 days ago)
- `end_date`: ISO8601 date (optional, default today)

**Response (200 OK):**
```csv
Date,Dose1Time,Dose2Time,Interval,OnTime,NaturalWake
2024-01-15,22:30:00,01:15:00,165,true,false
2024-01-14,22:45:00,01:30:00,165,true,true
```

### Error Codes & UX

| Code | Name | User Message | Recovery |
|------|------|--------------|----------|
| `422_WINDOW_EXCEEDED` | Window expired | "Dose 2 window has expired. Please skip this dose." | Show skip option |
| `422_SNOOZE_LIMIT` | Max snoozes | "Maximum snoozes reached (3). Take dose now or skip." | Disable snooze |
| `422_DOSE1_REQUIRED` | Dose 1 missing | "Please take Dose 1 first." | Highlight dose 1 |
| `409_ALREADY_TAKEN` | Duplicate dose | "This dose was already taken at [time]." | Show timeline |
| `429_RATE_LIMIT` | Too many requests | "Too many requests. Please wait 1 minute." | Retry after delay |
| `401_DEVICE_NOT_REGISTERED` | Unregistered device | "Device not authorized. Please re-register." | Show settings |
| `OFFLINE` | No connection | "Action saved offline. Will sync when connected." | Queue & show badge |

## Data Models

### xywav_profile
User's XYWAV configuration and preferences.

```typescript
interface XywavProfile {
  user_id: string;
  target_interval_minutes: number; // 165 default, must be one of {165, 180, 195, 210, 225}
  // NOTE: target_interval_minutes is the user's preferred reminder time (discrete set).
  // The window (clamp_min to clamp_max) is the allowed range during which Dose 2 may be taken.
  // These are different concepts: target = when we remind, window = when it's valid.
  clamp_min: 150; // constant - window minimum (not a valid target)
  clamp_max: 240; // constant - window maximum (not a valid target)
  nudge_step_minutes: 15; // constant
  notifications_enabled: boolean;
  haptics_enabled: boolean;
  created_at: string; // ISO8601
  updated_at: string; // ISO8601
}
```

### dose_event
Individual dose or skip event.

```typescript
interface DoseEvent {
  id: string;
  type: 'dose1' | 'dose2' | 'skip';
  timestamp: string; // ISO8601 actual time
  planned_timestamp?: string; // ISO8601 planned time
  meta: {
    snooze_count: number; // 0-3
    undo_used: boolean;
    offline_recorded: boolean;
    device_type: 'ios' | 'watchos' | 'flic';
  };
}
```

### sleep_event
Sleep-related events for analytics.

```typescript
interface SleepEvent {
  id: string;
  type: 'bathroom' | 'lights_out' | 'wake_final';
  timestamp: string; // ISO8601
  meta?: {
    duration_minutes?: number; // for bathroom
    quality_score?: number; // 1-5 subjective
  };
}
```

## Persistence & Data Management

### Source of Truth
- **Primary Store**: SQLite via `EventStorage` (implementation), accessed only through `SessionRepository` (public boundary)
- **Export Formats**: JSON and CSV files for interoperability
- **Sync**: iCloud/CloudKit sync is optional and disabled by default per privacy posture

### SQLite Tables

**Schema authority**: Table/column definitions are normative in `docs/DATABASE_SCHEMA.md`. This section is a high-level summary only.

#### dose_events
- **id**: TEXT PRIMARY KEY - Unique event identifier
- **event_type**: TEXT NOT NULL - 'dose1', 'dose2', 'skip', 'snooze'
- **timestamp**: TEXT NOT NULL - ISO8601 UTC timestamp
- **session_date**: TEXT NOT NULL - Date string (YYYY-MM-DD) for session grouping
- **metadata**: TEXT - Optional JSON metadata
- **synced**: INTEGER DEFAULT 0 - Sync status flag
- **created_at**: TEXT - Creation timestamp

#### sleep_events
- **id**: TEXT PRIMARY KEY - Unique event identifier
- **event_type**: TEXT NOT NULL - One of 13 event types (see constants.json)
- **timestamp**: TEXT NOT NULL - ISO8601 UTC timestamp
- **session_id**: TEXT - Optional session linkage
- **notes**: TEXT - Optional user notes
- **source**: TEXT DEFAULT 'manual' - Event source
- **synced**: INTEGER DEFAULT 0 - Sync status flag
- **created_at**: TEXT - Creation timestamp

#### current_session
- **id**: INTEGER PRIMARY KEY CHECK (id = 1) - Singleton row
- **dose1_time**: TEXT - Dose 1 timestamp
- **dose2_time**: TEXT - Dose 2 timestamp (NULL if not taken)
- **snooze_count**: INTEGER DEFAULT 0 - Snoozes used this session
- **dose2_skipped**: INTEGER DEFAULT 0 - Skip flag
- **session_date**: TEXT NOT NULL - Session date
- **updated_at**: TEXT - Last update timestamp

#### morning_checkins
- **id**: TEXT PRIMARY KEY - Check-in identifier
- **session_id**: TEXT NOT NULL - Linked session
- **timestamp**: TEXT NOT NULL - Check-in time
- **session_date**: TEXT NOT NULL - Session date
- **sleep_quality**: INTEGER NOT NULL - 1-5 rating
- **feel_rested**: TEXT NOT NULL - yes/no/somewhat
- **grogginess**: TEXT NOT NULL - none/mild/moderate/severe
- **sleep_inertia_duration**: TEXT NOT NULL - Duration category
- *(plus additional fields for symptoms, mental state, etc.)*

#### user_config
- **key**: TEXT PRIMARY KEY - Setting key
- **value**: TEXT NOT NULL - Setting value
- **updated_at**: TEXT - Last update timestamp

### Export System
- **Default Location**: iCloud Drive/DoseTap/Exports (user-configurable)
- **Format Compliance**: SSOT CSV v1 (header always included, deterministic order)
- **Files Generated**:
  - `events.csv` - Complete dose and sleep event history
  - `sessions.csv` - Aggregated session data with analytics
  - `inventory.csv` - Medication tracking snapshots
- **macOS Integration**: Exports automatically consumable by DoseTap Studio
- **Privacy**: All personal identifiers stripped from export files

### Time Zone & DST Resilience
- **Detection**: NSSystemTimeZoneDidChange and NSCalendarDayChanged monitoring
- **Response**: Automatic window recalculation and user notification
- **Travel Mode**: Interstitial UI for user confirmation of time zone changes
- **System Events**: Logged for audit trail and troubleshooting
- **Safety**: 150-240 minute window invariant preserved across all time changes

### Data Lifecycle
- **JSON Migration**: One-time import from existing dose_events.json and dose_sessions.json files
- **Migration Flag**: UserDefaults.didMigrateToSQLite prevents re-migration
- **Atomic Operations**: Batch deletes and saves for data integrity
- **Clear All Data**: Two-step confirmation with atomic wipe functionality

## Planner (Client-Only)

### Safe Interval Set
Discrete options to prevent unsafe configurations:
- **Valid intervals**: `{165, 180, 195, 210, 225}` minutes
- **Default**: 165 minutes
- **Selection method**: Manual only (no auto-adjust in v1)

### Weekly Planning Algorithm
```typescript
function suggestNextWeekTarget(history: DoseEvent[]): number {
  const baseline = 165;
  const lastWeek = history.filter(e => e.timestamp > weekAgo);
  
  if (lastWeek.length < 5) return baseline; // Insufficient data
  
  const avgActualInterval = calculateAvgInterval(lastWeek);
  const consistency = calculateConsistency(lastWeek);
  
  if (consistency < 0.7) return baseline; // Too variable
  
  if (avgActualInterval < 160 && currentTarget > 165) {
    return currentTarget - 15; // Nudge down
  }
  if (avgActualInterval > currentTarget + 10 && currentTarget < 225) {
    return currentTarget + 15; // Nudge up
  }
  
  return currentTarget; // No change
}
```

### Safety Constraints
- **Never suggest** <150m or >240m
- **Require 7-day stability** before any change
- **Revert trigger**: 3 consecutive missed windows → return to 165m
- **Manual override**: Requires explicit confirmation with safety warning

## Accessibility

### Visual Requirements
- **Contrast Ratios**:
  - Action buttons: ≥7:1 (WCAG AAA)
  - Body text: ≥4.5:1 (WCAG AA)
  - Timer display: ≥7:1 when <30m remaining
- **Typography**:
  - Dynamic Type support up to XXL
  - Minimum sizes: 17pt body, 22pt buttons
  - SF Pro Display for timers
- **Touch Targets**: 
  - Minimum 48x48pt
  - 8pt spacing between targets
  - Press-and-hold duration MUST come from `constants.json` (single source)

### Audio & Haptics
- **VoiceOver Announcements**:
  - Timer updates at: window open, -30m, -15m, -5m, -1m, close
  - State changes: "Dose 1 taken at 10:30 PM"
  - Warnings: "Dose window closing in 5 minutes"
- **Sound Effects**:
  - Success: Rising chime (dose taken)
  - Warning: Descending tone (window closing)
  - Error: Sharp buzz (action failed)
- **Haptic Patterns**:
  - Success: Medium impact
  - Warning: Light continuous
  - Error: Heavy double-tap
  - Timer tick: Light tap every minute <5m

### Cognitive Accessibility
- **Clear Language**: No medical jargon in UI
- **Confirmation Dialogs**: For destructive actions
- **Undo Support**: 5-second undo for all dose actions
- **Visual Indicators**: Icons + color + text (never color alone)

## Glossary

- **Clamp**: Hard min/max limits for Dose 2 window (150-240 minutes)
- **Natural-wake**: Waking without alarm before dose window opens
- **Nudge**: 15-minute adjustment to target interval
- **On-time dose**: Dose taken within ±10 minutes of target
- **Queued Action**: Offline action pending sync
- **Snooze**: 10-minute delay of dose reminder (max 3 per night)
- **Stay-in-bed protocol**: Remain in bed between doses for safety
- **Target interval**: Planned minutes between Dose 1 and Dose 2
- **TTFW**: Time To Fall Asleep When first in bed
- **WASO**: Wake After Sleep Onset (sleep interruptions)
- **Window**: Valid time range for taking Dose 2 (150-240m after Dose 1)

## Definition of Done (Per Screen)

### ✅ Tonight Screen
- [ ] All button states work offline with queue indicator
- [x] 5-second undo snackbar
- [ ] Window countdown displays mm:ss format
- [ ] Near-window rules enforced (<15m snooze disabled)
- [ ] Error states have clear recovery actions
- [ ] VoiceOver announces all state changes
- [ ] Haptics work for all actions
- [ ] Deep links route correctly
- [ ] Flic button integrated

### ✅ Timeline Screen
- [ ] Export generates valid CSV
- [ ] Filters work (week/month/all)
- [ ] Performance acceptable with 1000+ events
- [ ] Offline events marked clearly
- [ ] Pagination implemented
- [ ] Pull-to-refresh works

### ✅ Insights Screen
- [ ] Charts render on all device sizes
- [ ] Analytics calculations verified against test data
- [ ] Export includes all data points
- [ ] Loading states for slow calculations
- [ ] Empty state for insufficient data
- [ ] Accessibility labels for all chart elements

### ✅ Devices Screen
- [ ] Flic pairing flow completes <30s
- [ ] Device removal confirmation works
- [ ] Test button provides haptic feedback
- [ ] Connection status updates real-time
- [ ] Multiple device support
- [ ] Clear pairing instructions

### ✅ Settings Screen
- [ ] Target interval saves and validates
- [ ] Notification permissions handled correctly
- [ ] Accessibility settings apply immediately
- [ ] Changes sync to watch
- [ ] Export/import settings works
- [ ] Version info displayed

### 🔄 watchOS Companion (PARTIAL - Not Production Ready)

> ⚠️ **Status:** Basic timer and state machine implemented, but NOT integrated with iOS companion.
> WatchConnectivity messaging exists but requires iOS-side listener implementation.

**Implemented:**
- [x] Timer display showing remaining time until window opens/closes
- [x] Phase colors matching iOS (blue/orange/green/yellow/red/gray)
- [x] Dose 1/2 buttons with state-appropriate enabling
- [x] Bathroom and Snooze quick actions

**NOT Implemented:**
- [ ] Complications update within 1 minute
- [ ] Haptic feedback matches iOS
- [ ] Battery usage <5% per night
- [ ] Sync works bidirectionally (WatchConnectivity listener missing on iOS)
- [ ] Offline mode clearly indicated
- [ ] Timer shows on watch face (complication)

## Version History

- **1.0.0** (2024-01-15): Initial SSOT consolidation from 6 documents
- See [CHANGELOG.md](../../CHANGELOG.md) for detailed changes
