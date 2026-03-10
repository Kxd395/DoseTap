# DoseTap Architecture

> **Last updated:** 2026-02-16  
> **Version:** 0.3.3 alpha  
> **Branch:** `chore/audit-2026-02-15`  
> **Codebase:** ~52,000 LOC across ~155 Swift files  
> **Tests:** 587 XCTest + 43 Swift Testing (SwiftPM) = 630 total

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Module Dependency Graph](#2-module-dependency-graph)
3. [Tab Architecture](#3-tab-architecture)
4. [Tonight Tab](#4-tonight-tab)
5. [Timeline Tab (Details)](#5-timeline-tab-details)
6. [History Tab](#6-history-tab)
7. [Dashboard Tab](#7-dashboard-tab)
8. [Settings Tab](#8-settings-tab)
9. [Dose Window State Machine](#9-dose-window-state-machine)
10. [Session Lifecycle](#10-session-lifecycle)
11. [Data Flow — User Actions](#11-data-flow--user-actions)
12. [Deep Link Routing](#12-deep-link-routing)
12b. [Dose Registration Surface Matrix](#12b-dose-registration-surface-matrix)
13. [Notification & Alarm System](#13-notification--alarm-system)
14. [Storage & Persistence](#14-storage--persistence)
15. [Service Layer](#15-service-layer)
16. [Security & Privacy](#16-security--privacy)
17. [HealthKit Integration](#17-healthkit-integration)
18. [WHOOP Integration](#18-whoop-integration)
19. [Theme & Accessibility](#19-theme--accessibility)
20. [Module Layout](#20-module-layout)
21. [Test Pyramid](#21-test-pyramid)
22. [CI & Branch Protection](#22-ci--branch-protection)
23. [Known Issues & Technical Debt](#23-known-issues--technical-debt)
24. [Repository Structure](#24-repository-structure)

---

## 1. System Overview

DoseTap is an iOS dose-timer app for XYWAV (sodium oxybate). The core invariant:

> **Dose 2 must be taken 150–240 minutes after Dose 1.**  
> Default target: 165m. Snooze adds 10m. Snooze disabled when <15 min remain.

### System Layer Cake

```text
+-----------------------------------------------------+
|                   SwiftUI Views                      |
|   Tonight - Timeline - History - Dashboard - Settings|
+-----------------------------------------------------+
|              App Services (Singletons)               |
| SessionRepository - AlarmService - FlicButtonService |
| EventLogger - HealthKitService - WHOOPService        |
| UserSettingsManager - URLRouter - ThemeManager        |
+-----------------------------------------------------+
|               DoseCore (SwiftPM)                     |
| DoseWindowState - DoseTapCore - DosingModels         |
| TimeEngine - SessionKey - SleepPlan - APIClient      |
| OfflineQueue - EventRateLimiter - DiagnosticLogger   |
+-----------------------------------------------------+
|              Storage Layer (SQLite)                   |
| EventStorage (+7 extensions) - SessionRepository     |
| EncryptedEventStorage - DosingAmountSchema           |
+-----------------------------------------------------+
|            Platform (iOS 17+ / watchOS)              |
| UserNotifications - HealthKit - CloudKit - AVAudio   |
+-----------------------------------------------------+
```

### Composition Root

`DoseTapApp.swift` -> `ContentView` -> injects all `@StateObject` singletons:

```text
ContentView
 +-- @StateObject DoseTapCore        (dose state machine)
 +-- @StateObject UserSettingsManager (user preferences)
 +-- @StateObject EventLogger        (event cooldowns + logging)
 +-- @StateObject SessionRepository  (SSOT for session state)
 +-- @StateObject UndoStateManager   (5-second undo queue)
 +-- @StateObject ThemeManager       (theme + night mode)
 +-- @StateObject AlarmService       (notifications + alarms)
 +-- @ObservedObject URLRouter       (deep link handler + tab selection)
```

`AppContainer` provides a `DateProviding` protocol for injectable time (migration in progress).

---

## 2. Module Dependency Graph

```text
DoseCore (SwiftPM, platform-free)
    |
    +-- DoseWindowState       -> pure calculation, no I/O
    +-- DoseTapCore           -> ObservableObject, dose state machine
    +-- DosingModels          -> value types (DoseAmount, DoseUnit, etc.)
    +-- TimeEngine            -> time calculations, DST-safe
    +-- SessionKey            -> YYYY-MM-DD session identity
    +-- SleepPlan             -> sleep schedule + SleepPlanCalculator
    +-- MedicationConfig      -> medication definitions
    +-- MorningCheckIn        -> check-in model
    +-- SleepEvent            -> sleep event model
    +-- UnifiedSleepSession   -> session aggregation
    +-- RecommendationEngine  -> sleep recommendations
    +-- TimeIntervalMath      -> safe minute arithmetic
    |
    +-- APIClient             -> HTTP transport protocol
    +-- APIErrors             -> APIErrorMapper + DoseAPIError
    +-- APIClientQueueIntegration -> DosingService actor
    +-- OfflineQueue          -> actor, enqueue + flush
    +-- EventRateLimiter      -> actor, cooldown enforcement
    +-- CertificatePinning    -> TLS pin validation
    |
    +-- DiagnosticLogger      -> structured logging
    +-- DiagnosticEvent       -> log event model
    +-- DataRedactor          -> PII scrubbing
    +-- CSVExporter           -> export formatting
    +-- DoseUndoManager       -> undo action model
    +-- EventStore            -> (quarantined legacy)

DoseTap App (Xcode project)
    |
    +-- imports DoseCore
    +-- Views/       (23 files)
    +-- Storage/     (13 files)
    +-- Services/    (1 file)
    +-- Security/    (3 files)
    +-- Foundation/  (2 files)
    +-- FullApp/     (4 files)
    +-- Persistence/ (2 files)
    +-- Export/      (1 file)
    +-- Theme/       (1 file)
    +-- App root     (36 files)
```

---

## 3. Tab Architecture

Five tabs in a swipeable `TabView(.page)` with a custom tab bar:

| Tab | Enum | Icon | View | Purpose |
| --- | --- | --- | --- | --- |
| **Tonight** | `.tonight` | `moon.fill` | `LegacyTonightView` | Active session: dose buttons, sleep plan, quick events |
| **Timeline** | `.timeline` | `chart.bar.xaxis` | `DetailsView` | Live timeline + past night review |
| **History** | `.history` | `calendar` | `HistoryView` | Calendar picker, session list, full detail drill-down |
| **Dashboard** | `.dashboard` | `chart.xyaxis.line` | `DashboardTabView` | Analytics, trends, integrations, CloudKit sync |
| **Settings** | `.settings` | `gear` | `SettingsView` | All configuration: timing, notifications, appearance, data |

Navigation is managed by `URLRouter.selectedTab: AppTab` (`@Published`).

---

## 4. Tonight Tab

**File:** `ios/DoseTap/Views/TonightView.swift` (415 LOC)

```text
LegacyTonightView
 +-- Date label (TonightDateLabel)
 +-- QuickThemeSwitchButton
 +-- Sleep Plan Cards (from SleepPlanCards.swift)
 |    +-- Tonight schedule, wind-down, target times
 |    +-- "If in bed now" shows hours+minutes (e.g. "8h 20m")
 +-- CompactStatusCard
 |    +-- Session phase, countdown, dose window status
 |    +-- .beforeWindow: animated progress ring (Circle().trim)
 +-- CompactDoseButton (primary CTA)
 |    +-- Take Dose 1    (pre-dose state)
 |    +-- Take Dose 2    (window open)
 |    +-- Take Dose 2 (Late) (window closed — override confirmation)
 |    +-- Snooze (+10m)  (window open, <maxSnoozes, >=15m remain)
 |    +-- Skip Dose 2    (window open)
 |    +-- Morning Check-In (finalizing state)
 |    +-- DoseActionCoordinator: haptic feedback + confirmation sound
 +-- QuickEventViews (grid of event buttons)
 |    +-- bathroom, water, snack, lights_out, in_bed, etc.
 |    +-- "time since" badges (EventLogger.relativeBadge)
 +-- Pre-Sleep Log button -> PreSleepLogView (sheet)
 +-- Session summary (SessionSummaryViews)
 +-- Undo Snackbar overlay (UndoSnackbarView)
 +-- Early/late dose override confirmation dialogs
```

### Tonight User Actions

| Action | Trigger | Handler | Storage Effect |
| --- | --- | --- | --- |
| Take Dose 1 | Dose button | `DoseTapCore.takeDose()` -> `SessionRepo.saveDose1()` | `current_session.dose1_time` set |
| Take Dose 2 | Dose button | `DoseTapCore.takeDose()` -> `SessionRepo.saveDose2()` | `current_session.dose2_time` set |
| Skip Dose 2 | Skip button | `DoseTapCore.skipDose()` -> `SessionRepo.markSkipped()` | `current_session.dose2_skipped = 1` |
| Snooze | Snooze button | `AlarmService.snoozeAlarm()` -> `SessionRepo.incrementSnooze()` | `current_session.snooze_count++` |
| Log Event | QuickLog grid | `EventLogger.logEvent()` -> `EventStorage.insertSleepEvent()` | Row in `sleep_events` |
| Wake Up | Wake button | `SessionRepo.setWakeFinalTime()` | Session -> `finalizing` phase |
| Pre-Sleep Log | Sheet | `PreSleepLogView` -> `EventStorage.savePreSleepLog()` | Row in `pre_sleep_logs` |
| Undo | Snackbar | `UndoStateManager.onUndo` -> clears last action | Reverses last write |
| Log Medication | Medication picker | `DoseAmountPicker` -> `EventStorage.insertMedicationEvent()` | Row in `medication_events` |

---

## 5. Timeline Tab (Details)

**File:** `ios/DoseTap/Views/DetailsView.swift` (56 LOC wrapper) + `ios/DoseTap/Views/Timeline/TimelineReviewViews.swift` (1346 LOC)

```text
DetailsView
 +-- Live Mode (current session):
 |    +-- LiveNextActionCard       -- next recommended action
 |    +-- TonightTimelineProgressCard -- visual timeline with markers
 |    +-- LiveEventsPreviewCard    -- recent events feed
 |
 +-- Review Mode (past sessions):
      +-- ReviewHeaderCard          -- date, session stats
      +-- ReviewStickyHeaderBar     -- pinned navigation
      +-- CoachSummaryCard          -- AI-generated narrative
      +-- MergedNightTimelineCard   -- merged dose + events timeline
      +-- ReviewKeyMetricsCard      -- interval, snoozes, event count
      +-- ReviewEventsAndNotesCard  -- all logged events with notes
      +-- ReviewEventsSnapshotCard  -- shareable snapshot
```

Also hosts `AlarmRingingView` (full-screen alarm when alarm fires).

### Timeline User Actions

| Action | Effect |
| --- | --- |
| Tap event in timeline | Expand detail / show notes |
| Share snapshot | Render `TimelineReviewShareSnapshotView` -> UIActivityViewController |
| Resolve duplicate | `DuplicateResolutionSheet` -> merge or delete duplicate events |
| Swipe between live/review | Toggle between current session and selected past session |

---

## 6. History Tab

**File:** `ios/DoseTap/Views/History/HistoryViews.swift` (1177 LOC)

```text
HistoryView
 +-- Calendar grid (month view)
 |    +-- Dots indicate sessions with data
 +-- SelectedDayView
 |    +-- Dose timing summary
 |    +-- Nap intervals display
 |    +-- Quick session metrics
 +-- RecentSessionsList
 |    +-- SessionRow (dose1, dose2, interval, skip, event count)
 +-- FullSessionDetails (drill-down)
      +-- StatusCard           -- session state badge
      +-- TimeUntilWindowCard  -- countdown or elapsed
      +-- DoseButtonsSection   -- take/skip/snooze (can act on past)
      +-- EarlyDoseOverrideSheet -- confirm early dose
      +-- FullEventLogGrid     -- all events with timestamps
      +-- EventHistorySection  -- per-type event history
      +-- WarningRow           -- any safety warnings
```

### History User Actions

| Action | Effect |
| --- | --- |
| Tap calendar date | Load `SelectedDayView` with that session |
| Tap session row | Drill down to `FullSessionDetails` |
| Take Dose (from history) | Retroactive dose logging with confirmation |
| Delete event | Remove from `sleep_events` table |
| Early dose override | `EarlyDoseOverrideSheet` with risk acknowledgment |

---

## 7. Dashboard Tab

**Files:** `ios/DoseTap/Views/Dashboard/DashboardModels.swift` (~1580 LOC) + `DashboardViews.swift` (~1270 LOC)

```text
DashboardTabView
 +-- Date range picker (7d / 14d / 30d / 90d / all)
 +-- DashboardExecutiveSummaryCard
 |    +-- KPIs: On-Time %, Completion %, Streak, Confidence
 |    +-- WHOOP KPIs (conditional): Recovery %, HRV ms
 +-- DashboardPeriodComparisonCard
 |    +-- This period vs. previous period deltas
 |    +-- Includes WHOOP Recovery + HRV deltas when available
 +-- DashboardDosingSnapshotCard
 |    +-- Dose 1/2 timing averages, skip rate
 +-- DashboardSleepSnapshotCard
 |    +-- Avg sleep quality, grogginess, restedness
 |    +-- WHOOP Metrics section: recovery, HRV, efficiency, respiratory rate
 +-- DashboardWHOOPCard (conditional: only when WHOOP nights exist)
 |    +-- Recovery gauge (circular ring, color-coded green/orange/red)
 |    +-- Biometrics grid: HRV, Resting HR, Sleep Efficiency, Respiratory Rate
 |    +-- Sleep stage breakdown bar (deep/REM proportional) + disturbance count
 +-- DashboardLifestyleFactorsCard
 |    +-- Substance usage, activity, nap correlations
 +-- DashboardMoodSymptomsCard
 |    +-- Mood trends, anxiety, symptom frequency
 +-- DashboardDataQualityCard
 |    +-- Missing data indicators, completion rates
 +-- DashboardIntegrationsCard
 |    +-- HealthKit, WHOOP connection status
 +-- DashboardTrendChartsCard
 |    +-- Modes: Interval, Sleep, Compliance, Recovery (WHOOP)
 |    +-- Recovery trend: dual-axis (recovery line + dose interval scatter)
 +-- DashboardRecentNightsCard
 |    +-- Last 5 sessions with per-night recovery badge
 +-- DashboardCapturedMetricsCard
      +-- Total data points captured across all categories
```

### Dashboard Data Model

`DashboardAnalyticsModel` (ObservableObject) aggregates data from:
- `SessionRepository` -> dose logs, session summaries
- `EventStorage` -> sleep events, check-ins, pre-sleep logs
- `HealthKitService` -> sleep stages, heart rate
- `WHOOPService` -> recovery, strain, HRV

`DeferredCloudKitSyncService` handles the deferred CloudKit bi-directional sync path used only by the cloud-enabled staging target.

### Dashboard User Actions

| Action | Effect |
| --- | --- |
| Change date range | Re-aggregate all metrics for selected period |
| Tap integration | Navigate to integration settings |
| Tap recent night | Navigate to night review in Timeline tab |
| Export from dashboard | Generate CSV/share of visible data |

---

## 8. Settings Tab

**File:** `ios/DoseTap/SettingsView.swift` (698 LOC)

### Settings Sections & Sub-Views

```text
SettingsView (NavigationView > List)
 +-- Section: Dose & Timing
 |    +-- Target Interval picker (150-240 min)
 |    +-- NavigationLink -> WeeklyPlannerView
 |    +-- Undo Window picker (3s/5s/7s/10s)
 |    +-- Info card (dose window rules)
 |
 +-- Section: Night Schedule
 |    +-- Sleep Start time picker
 |    +-- Wake Time picker
 |    +-- DisclosureGroup: Evening Prep & Auto-Close
 |         +-- Prep Time picker
 |         +-- Missed check-in cutoff stepper
 |         +-- Auto-close time display
 |
 +-- Section: Notifications & Alerts
 |    +-- Toggle: Enable Notifications
 |    +-- Toggle: Critical Alerts (red tint)
 |    +-- Toggle: Window Open (150 min)
 |    +-- Toggle: 15 Min Warning
 |    +-- Toggle: 5 Min Warning
 |    +-- Toggle: Sound
 |    +-- Toggle: Haptics
 |
 +-- Section: Sleep Planning
 |    +-- NavigationLink -> SleepPlanDetailView
 |    +-- Target Sleep (minutes stepper)
 |    +-- Sleep Latency (minutes stepper)
 |    +-- Wind Down (minutes stepper)
 |
 +-- Section: Appearance
 |    +-- NavigationLink -> ThemeSettingsView
 |    +-- Theme picker (system/light/dark)
 |    +-- Toggle: High Contrast
 |    +-- Toggle: Reduce Motion
 |
 +-- Section: Medications
 |    +-- NavigationLink -> MedicationSettingsView
 |
 +-- Section: Event Logging
 |    +-- NavigationLink -> QuickLogCustomizationView
 |    +-- NavigationLink -> EventCooldownSettingsView
 |
 +-- Section: Integrations
 |    +-- NavigationLink -> HealthKitSettingsView
 |    +-- WHOOPStatusRow (inline status)
 |
 +-- Section: Data Management
 |    +-- Button: Export Data (CSV)
 |    +-- NavigationLink -> DiagnosticExportView
 |    +-- NavigationLink -> DataManagementView
 |    +-- Button: Clear All Data (destructive)
 |
 +-- Section: Privacy & Diagnostics
 |    +-- Toggle: Anonymous Analytics
 |    +-- Toggle: Crash Reports
 |    +-- NavigationLink -> DiagnosticLoggingSettingsView
 |
 +-- Section: About
      +-- Version display
      +-- Build number display
      +-- NavigationLink -> AboutView
```

### Settings Sub-Views (separate files)

| View | File | Purpose |
| --- | --- | --- |
| `WeeklyPlannerView` | `WeeklyPlanner.swift` | Per-day target intervals |
| `SleepPlanDetailView` | `SleepPlanDetailView.swift` | Full weekly sleep schedule |
| `ThemeSettingsView` | `Views/ThemeSettingsView.swift` | Night mode, custom themes |
| `MedicationSettingsView` | `Views/MedicationSettingsView.swift` | Add/remove medications |
| `MedicationPickerView` | `Views/MedicationPickerView.swift` | Pick from medication catalog |
| `QuickLogCustomizationView` | `QuickLogCustomizationView.swift` | Customize quick-log grid |
| `EventCooldownSettingsView` | `EventCooldownSettingsView.swift` | Per-event cooldown durations |
| `HealthKitSettingsView` | `HealthKitSettingsView.swift` | HealthKit permissions and config |
| `WHOOPSettingsView` | `WHOOPSettingsView.swift` | WHOOP OAuth + data fetch config |
| `DiagnosticExportView` | `Views/DiagnosticExportView.swift` | Export session diagnostics bundle |
| `DataManagementView` | `DataManagementView.swift` | History management, purge old data |
| `DiagnosticLoggingSettingsView` | `DiagnosticLoggingSettingsView.swift` | Diagnostic log level and retention |
| `AboutView` | `AboutView.swift` | App info, privacy policy, credits |

---

## 9. Dose Window State Machine

**File:** `ios/Core/DoseWindowState.swift`

### Phases

```text
                    dose1_time == nil
                         |
                  +------v------+
                  |   noDose1   |
                  +------+------+
                    dose1 taken
                         |
               elapsed < 150m?
              +----------+----------+
              | yes                  | no
       +------v------+      +------v------+
       | beforeWindow |      |    active   |
       +------+------+      +------+------+
              | 150m reached       |
              +----------+         | elapsed > 225m (max-15)
                         |  +------v------+
                         +-->  nearClose  |
                            +------+------+
                                   | elapsed > 240m
                            +------v------+
                            |    closed   |
                            +------+------+
                                   | dose2 taken/skipped
                            +------v------+
                            |  completed  |
                            +------+------+
                                   | wake_final event
                            +------v------+
                            | finalizing  |
                            +-------------+
```

### Actions per Phase

| Phase | Primary CTA | Snooze | Skip |
| --- | --- | --- | --- |
| `noDose1` | Take Dose 1 | `disabled` | `disabled` |
| `beforeWindow` | Waiting... (countdown) | `disabled` | `disabled` |
| `active` | Take Dose 2 (`takeNow`) | `snoozeEnabled` | `skipEnabled` |
| `nearClose` | Take Dose 2 (`takeBeforeWindowEnds`) | `snoozeDisabled(<15m)` | `skipEnabled` |
| `closed` | Take Dose 2 (`takeWithOverride`) | `disabled` | `skipEnabled` |
| `completed` | (Done) | `disabled` | `disabled` |
| `finalizing` | Morning Check-In | `disabled` | `disabled` |

### Key Constants

| Constant | Value | Source |
| --- | --- | --- |
| Window open | 150 min | `DoseWindowConfig.min` |
| Window close | 240 min | `DoseWindowConfig.max` |
| Near-close threshold | 15 min before max | `DoseWindowConfig.nearWindowThresholdMin` |
| Default target | 165 min | `DoseWindowConfig.defaultTargetMin` |
| Snooze step | 10 min | `DoseWindowConfig.snoozeStepMin` |
| Max snoozes | User-configurable (default 3) | `UserSettingsManager.maxSnoozes` |

---

## 10. Session Lifecycle

```text
Session boundary: NOT midnight. It is the biological sleep cycle.

 6:00 PM  --- Prep Time (configurable)
 |              +-- PreSleepLogView available
 |
 8:00 PM  --- Sleep Start (configurable)
 |              +-- Take Dose 1 -> session starts
 |              +-- dose1_time recorded in current_session
 |
10:30 PM  --- Window opens (dose1 + 150m)
 |              +-- Dose 2 available
 |              +-- Notifications fire
 |
12:45 AM  --- Window closes (dose1 + 240m)
 |              +-- Late override still possible
 |
 6:00 AM  --- Wake Time (configurable)
 |              +-- Wake alarm fires
 |              +-- wake_final event -> phase = finalizing
 |
 7:00 AM  --- Morning Check-In
 |              +-- MorningCheckInView questionnaire
 |              +-- Session archived to sleep_sessions
 |
 +cutoff  --- Missed check-in cutoff (wake + N hours)
                +-- Auto-close session if no check-in
```

**Session ID:** UUID assigned at session start.
**Session Date:** `YYYY-MM-DD` of the night (based on `SessionKey` logic).
**Rollover:** `SessionRepository` detects new sessions at the configured boundary.

---

## 11. Data Flow -- User Actions

### Dose 1 Flow

```text
User taps "Take Dose 1"
  |
  +-- CompactDoseButton (View)
  |     +-- calls DoseTapCore.takeDose()
  |
  +-- DoseTapCore (ViewModel)
  |     +-- sets dose1Time, starts timer
  |     +-- calls SessionRepository.saveDose1(timestamp:)
  |
  +-- SessionRepository (Storage Facade)
  |     +-- writes to current_session table
  |     +-- creates dose_events entry
  |     +-- publishes @Published state
  |
  +-- UndoStateManager
  |     +-- enqueues .takeDose1(time) with 5s window
  |     +-- if undo: SessionRepository.clearDose1()
  |
  +-- AlarmService
  |     +-- scheduleWakeAlarm(at: dose1 + target)
  |     +-- scheduleDose2Reminders(dose1Time:)
  |
  +-- EventLogger
        +-- logs "Dose 1" event with 8h cooldown
```

### Quick Event Flow

```text
User taps "Bathroom" in QuickLog grid
  |
  +-- QuickEventViews (View)
  |     +-- calls EventLogger.logEvent(name:)
  |
  +-- EventLogger
  |     +-- checks cooldown via cooldownEnd(for:)
  |     +-- if allowed: EventStorage.insertSleepEvent()
  |     +-- tracks last-logged time for cooldown
  |
  +-- EventStorage.insertSleepEvent()
        +-- writes to sleep_events(session_date, event_type, timestamp)
```

### Morning Check-In Flow

```text
User opens MorningCheckInView
  |
  +-- Multi-section questionnaire:
  |     +-- Core: sleep quality, restedness, grogginess, sleep inertia, dream recall
  |     +-- Physical: body map, pain entries, stiffness, soreness, headache
  |     +-- Respiratory: congestion, throat, cough, sinus, sickness level
  |     +-- Mental: mental clarity, mood, anxiety, readiness
  |     +-- Narcolepsy: sleep paralysis, hallucinations, automatic behavior, fell out of bed
  |     +-- Sleep therapy: device usage, compliance, comfort
  |     +-- Notes: free text
  |
  +-- EventStorage.insertMorningCheckIn()
  |     +-- writes to morning_checkins table (40+ columns)
  |
  +-- EventStorage.insertCheckInSubmission()
  |     +-- writes to checkin_submissions (normalized, versioned)
  |
  +-- SessionRepository
        +-- archives session to sleep_sessions
        +-- resets current_session for next night
```

---

## 12. Deep Link Routing

**File:** `ios/DoseTap/URLRouter.swift` (389 LOC)

Scheme: `dosetap://`

### Action Deep Links

| URL | Action | Validation |
| --- | --- | --- |
| `dosetap://dose1` | Take Dose 1 | Must not have dose1 already |
| `dosetap://dose2` | Take Dose 2 | Must have dose1, window open |
| `dosetap://snooze` | Snooze alarm | Window active, <maxSnoozes, >=15m remain |
| `dosetap://skip` | Skip Dose 2 | Must have dose1, dose2 not taken |
| `dosetap://log?event=bathroom` | Log event | Valid event type, not on cooldown |
| `dosetap://log?event=bathroom&notes=urgent` | Log event with notes | Same + sanitized notes |

### Navigation Deep Links

| URL | Tab |
| --- | --- |
| `dosetap://tonight` | Tonight |
| `dosetap://timeline` or `dosetap://details` | Timeline |
| `dosetap://history` | History |
| `dosetap://dashboard` | Dashboard |
| `dosetap://settings` | Settings |

### Special

| URL | Handler |
| --- | --- |
| `dosetap://oauth` | Forwarded to WHOOP OAuth callback (not handled by URLRouter) |

All deep links are validated by `InputValidator.validateDeepLink()` and sanitized via `InputValidator.sanitizeForLogging()` before processing.

---

## 12b. Dose Registration Surface Matrix

Dose actions can be triggered from 4 independent surfaces. **These implementations diverge in important ways:**

### Feature Parity Matrix

| Capability | Tonight (CompactDoseButton) | History (DoseButtonsSection) | Flic (FlicButtonService) | Deep Link (URLRouter) |
|---|---|---|---|---|
| Take Dose 1 | ✅ | ✅ | ✅ | ✅ |
| Take Dose 2 | ✅ | ✅ | ✅ | ✅ |
| Late override confirm | ✅ Alert | ✅ Alert | ❌ Haptic only | ❌ Blocks |
| Extra-dose (3rd) warning | ✅ Alert | ❌ Missing | ❌ Logs silently | ❌ Not supported |
| Snooze | ✅ | ✅ | ✅ | ✅ |
| Snooze <15m check | ❌ Count only | ❌ Count only | ✅ Via context | N/A |
| Skip | ✅ | ✅ | ✅ | ✅ |
| Event logging (EventLogger) | ✅ | ❌ | ❌ | ❌ |
| Undo registration | ✅ | ❌ | ❌ | ❌ |
| Alarm scheduling | ✅ | ❌ | ✅ | ❌ |
| Theme-aware colors | ✅ | ❌ | N/A | N/A |

### Button State per Phase

| Phase | Primary Button | Color | Snooze | Skip | Notes |
|---|---|---|---|---|---|
| `noDose1` | "Take Dose 1" | Blue | Disabled | Disabled | |
| `beforeWindow` | "Waiting..." | Gray | Disabled | Disabled | Tap shows early-override alert |
| `active` | "Take Dose 2" | Green | Enabled (if count<3) | Enabled | |
| `nearClose` | "Take Dose 2" | Orange | **Should check <15m** | Enabled | SSOT: disable at <15m |
| `closed` | "Take Dose 2 (Late)" | Red | Disabled | Enabled | Requires confirmation |
| `completed` | "Complete ✓" | Purple | Disabled | Disabled | Tap checks for extra-dose |
| `finalizing` | "Check-In" | Yellow | Disabled | Disabled | |

> **⚠️ Known issue:** Snooze enable logic in UI buttons checks only `snoozeCount < 3`, not `remaining < 15m`. See `docs/IMPROVEMENT_ROADMAP.md` P0-2.


---

## 13. Notification & Alarm System

**File:** `ios/DoseTap/AlarmService.swift` (607 LOC)

### Notification Identifiers

| ID | Trigger | Content |
| --- | --- | --- |
| `dosetap_wake_alarm` | dose1 + target minutes | Full alarm with sound + follow-ups |
| `dosetap_pre_alarm` | 5 min before wake alarm | "Wake alarm in 5 minutes" |
| `dosetap_followup_1..3` | +3m, +6m, +9m after wake | Escalating reminders if not dismissed |
| `dosetap_second_dose` | dose1 + 150m (window open) | "Dose 2 window is now open" |
| `dosetap_window_15min` | dose1 + 225m | "15 minutes remaining in window" |
| `dosetap_window_5min` | dose1 + 235m | "5 minutes remaining in window" |

### Category

- `dosetap_alarm` -- action buttons on notification

### Snooze Behavior

1. User taps snooze -> `AlarmService.snoozeAlarm(dose1Time:)`
2. Cancels current alarm + pending follow-ups
3. Reschedules at `now + snoozeDuration` (default 10m)
4. Increments `snooze_count` in `current_session`
5. Blocked if `snoozeCount >= maxSnoozes` or `remaining < 15m`

### Alarm Ringing

`AlarmService.isAlarmRinging` (`@Published`) triggers `AlarmRingingView` as a `.fullScreenCover`:
- System sound playback (`SystemSoundID 1005` fallback)
- Haptic feedback
- Dismiss / Snooze / Take Dose 2 buttons

---

## 14. Storage & Persistence

### Database: SQLite (via EventStorage)

**File:** `ios/DoseTap/Storage/EventStorage.swift` + 7 extension files (total ~3,500 LOC)

### Tables

| Table | Purpose | Key Columns |
| --- | --- | --- |
| `sleep_events` | All logged sleep events | `id`, `event_type`, `timestamp`, `session_date`, `session_id`, `notes` |
| `dose_events` | Dose-specific events | `id`, `event_type`, `timestamp`, `session_date`, `session_id`, `metadata` |
| `current_session` | Active session state (singleton row) | `dose1_time`, `dose2_time`, `snooze_count`, `dose2_skipped`, `session_date`, `session_id` |
| `sleep_sessions` | Archived session metadata | `session_id`, `session_date`, `start_utc`, `end_utc`, `terminal_state` |
| `pre_sleep_logs` | Pre-night questionnaires | `id`, `session_id`, `answers_json`, `completion_state` |
| `morning_checkins` | Morning check-in data (40+ cols) | `id`, `session_id`, `sleep_quality`, `feel_rested`, `grogginess`, ... |
| `checkin_submissions` | Normalized check-in responses | `id`, `checkin_type`, `questionnaire_version`, `responses_json` |
| `cloudkit_tombstones` | Pending CloudKit deletes | `key`, `record_type`, `record_name` |
| `medication_events` | Medication dose entries | `id`, `medication_id`, `dose_mg`, `formulation`, `taken_at_utc` |

### Indexes (17 total)

Performance indexes on: `session_date`, `timestamp`, `session_id`, `event_type`, `medication_id`, `taken_at_utc`, `checkin_type`, `created_at`.

### Extension Files

| File | Purpose |
| --- | --- |
| `EventStorage+Schema.swift` (680 LOC) | Table creation, migrations, deduplication |
| `EventStorage+Session.swift` (702 LOC) | Session CRUD, rollover, archival |
| `EventStorage+Dose.swift` | Dose event read/write |
| `EventStorage+CheckIn.swift` (824 LOC) | Morning check-in + submission CRUD |
| `EventStorage+Exports.swift` | CSV/JSON export queries |
| `EventStorage+EventStore.swift` | Sleep event CRUD |
| `EventStorage+Maintenance.swift` | Cleanup, purge, integrity checks |

### Storage Models

**File:** `ios/DoseTap/Storage/StorageModels.swift` (867 LOC)

| Model | Purpose |
| --- | --- |
| `EventRecord` | Legacy event compatibility |
| `StoredPreSleepLog` | Pre-sleep log read model |
| `StoredCheckInSubmission` | Normalized check-in read model |
| `PreSleepLog` | Pre-sleep log write model |
| `CloudKitTombstone` | Outbound delete marker |
| `StoredSleepEvent` | Sleep event read model |
| `StoredDoseLog` | Dose log with interval calculation |
| `SessionSummary` | Aggregated session for History view |
| `StoredMorningCheckIn` | Morning check-in read model |
| `PreSleepLogAnswers` | Pre-sleep questionnaire answers (nested enums) |

### Additional Storage

| File | Purpose |
| --- | --- |
| `SessionRepository.swift` (1712 LOC) | **SSOT facade** -- wraps EventStorage, publishes @Published state, handles rollover |
| `DosingAmountSchema.swift` (762 LOC) | Dosing amount tables + medication event schema |
| `EncryptedEventStorage.swift` | SQLite encryption wrapper |
| `JSONMigrator.swift` | Legacy JSON -> SQLite migration |

### Persistence Layer

| File | Purpose |
| --- | --- |
| `PersistentStore.swift` | Legacy persistence compatibility shim |
| `FetchHelpers.swift` | Legacy persistence helper utilities |

---

## 15. Service Layer

### App-Level Singletons (injected via ContentView)

| Service | Responsibility |
| --- | --- |
| `SessionRepository` | **Central state store** -- session lifecycle, dose state, event persistence |
| `AlarmService` | Local notification scheduling, alarm ringing state |
| `EventStorage` | SQLite database layer (raw reads/writes) |
| `WhoopManager` | WHOOP API OAuth + data fetch |
| `HealthKitManager` | HealthKit read/write + sleep stage analysis |
| `FlicManager` | Flic 2 button BLE connection + action mapping |
| `ThemeManager` | Day/night theme switching, high-contrast mode |
| `ExportService` | CSV/JSON export with sharing |
| `DiagnosticLogger` | Structured logging for diagnostic traces |
| `DashboardAnalyticsModel` | Aggregated analytics computation |
| `DeferredCloudKitSyncService` | Deferred iCloud record sync + conflict resolution for the staging target |
| `OnboardingManager` | First-run flow state |
| `NotificationDelegate` | UNUserNotificationCenterDelegate routing |
| `URLRouter` | Deep link + Shortcuts action routing |

### DoseCore Services (SwiftPM, platform-free)

| Service | File | Purpose |
| --- | --- | --- |
| `DoseWindowCalculator` | `DoseWindowState.swift` | Phase computation, CTA generation |
| `APIClient` | `APIClient.swift` | HTTP transport with auth |
| `DosingService` | `APIClientQueueIntegration.swift` | Facade: API + queue + rate limiter |
| `OfflineQueue` | `OfflineQueue.swift` | Actor-based retry queue |
| `EventRateLimiter` | `EventRateLimiter.swift` | Cooldown-based event dedup |
| `APIErrorMapper` | `APIErrors.swift` | Status code -> typed error mapping |

### Support Services

| File | Purpose |
| --- | --- |
| `InputValidator.swift` | Deep link parameter sanitization |
| `SleepStageTimeline.swift` | HealthKit sleep stage segmentation |
| `SleepStageChartView.swift` | Stage timeline visualization |
| `NightScoreCalculator.swift` | Multi-factor night quality score |
| `SessionDateCalculator.swift` | 6pm-cutoff session date logic |
| `CoachInsightGenerator.swift` | AI-style narrative generation from session data |

---

## 16. Security & Privacy

### Security Files

| File | Purpose |
| --- | --- |
| `Security/KeychainHelper.swift` | Keychain read/write wrapper |
| `Security/AppProtection.swift` | Biometric/passcode lock on app launch |
| `Security/JailbreakDetection.swift` | Runtime environment checks |
| `EncryptedEventStorage.swift` | SQLCipher database encryption |
| `InputValidator.swift` | Deep link injection prevention |

### Privacy Measures

- **No `print()` in production** -- all logging via `os.Logger` with `OSLogPrivacy`
- **Keychain-stored secrets** -- WHOOP tokens, API keys never in UserDefaults
- **Biometric lock** -- optional Face ID/Touch ID on app resume
- **Data encryption** -- SQLCipher for at-rest database
- **Export redaction** -- personal identifiers stripped in exports
- **CloudKit privacy** -- private database zone only
- **HealthKit** -- read-only unless user grants write
- **Diagnostic mode** -- requires explicit toggle, auto-disables after 24h

---

## 17. HealthKit Integration

**File:** `ios/DoseTap/HealthKitManager.swift`

### Data Types Read

| Type | Usage |
| --- | --- |
| `.sleepAnalysis` | Sleep stage data (awake, REM, core, deep) |
| `.heartRate` | Resting HR during sleep |
| `.heartRateVariabilitySDNN` | HRV for recovery metrics |

### Key Protocol

`HealthKitProviding` -- protocol for testability (mock injection in tests).

### Sleep Stage Timeline

`SleepStageTimeline` segments HealthKit `HKCategorySample` data into typed stages with duration computation. Used by:
- `SleepStageChartView` (visual bar chart in Night Review)
- `NightScoreCalculator` (quality scoring)
- `CoachInsightGenerator` (narrative text)

---

## 18. WHOOP Integration

**Files:** `ios/DoseTap/WHOOPService.swift` (~470 LOC), `WHOOPDataFetching.swift` (~480 LOC), `WHOOPSettingsView.swift` (~280 LOC), `SleepTimelineOverlays.swift` (609 LOC)

### Feature Flag

`WHOOPService.isEnabled` is dynamic — reads `UserDefaults("whoop_enabled")`. Auto-set to `true` when user connects WHOOP via OAuth, `false` on disconnect. No hardcoded kill switch.

### OAuth Flow

1. User initiates from `WHOOPSettingsView` → Settings > Integrations
2. `WHOOPService.authorize()` → `ASWebAuthenticationSession` opens WHOOP OAuth consent
3. Callback via `dosetap://whoop-callback` → token exchange
4. Access + refresh tokens stored in Keychain
5. Auto-refresh on 401 via `refreshTokenIfNeeded()`

### API Endpoints (WHOOPDataFetching — 7 functions built)

| Function | Endpoint | Data |
|---|---|---|
| `fetchSleepData(from:to:)` | `/v1/activity/sleep` | Sleep records with scores |
| `fetchRecoveryData(from:to:)` | `/v1/recovery` | Recovery score, HRV, RHR |
| `fetchCycleData(from:to:)` | `/v1/cycle` | Strain, calories |
| `fetchRecentSleep(nights:)` | `/v1/activity/sleep` | Last N nights |
| `fetchSleepForNight(_:)` | `/v1/activity/sleep` | Single night lookup |
| `fetchSleepStages(sleepId:)` | `/v1/activity/sleep/:id` | Per-stage breakdown |
| `fetchHeartRateData(from:to:)` | `/v1/cycle/:id/heart_rate` | HR time series |

### Current Data Flow Status ✅

| Surface | Status | Detail |
|---|---|---|
| **Dashboard** | � Full | Executive Summary Recovery/HRV KPIs, dedicated WHOOP Card (gauge + biometrics + sleep stages), Period Comparison deltas, Recovery Trend chart, Sleep Snapshot WHOOP section, Recent Nights recovery badges |
| **Timeline** | � Real data | `extractBiometricData()` calls real WHOOP APIs (heart rate, respiratory rate, HRV). Empty arrays when WHOOP disabled or API fails. |
| **Night Review** | � Real data | `HealthDataCard` loads WHOOP sleep + recovery data per-session with loading state. Shows recovery, HRV, efficiency, respiratory rate. |
| **DashboardNightAggregate** | � Full | `whoopSummary: WHOOPNightSummary?` with computed properties for recovery, HRV, sleep efficiency, respiratory rate, deep/REM/light/awake minutes, disturbances, resting HR |

> **Feature flag:** `WHOOPService.isEnabled` reads `UserDefaults("whoop_enabled")` — dynamically set on connect/disconnect. No hardcoded kill switch.

---

## 19. Theme & Accessibility

**File:** `ios/DoseTap/Theme/ThemeManager.swift`

### Themes

| Mode | Trigger | Palette |
| --- | --- | --- |
| Day | Default / manual toggle | Standard iOS light colors |
| Night | Auto after `lights_out` event / manual | Dark reds/ambers, low blue light |

### Accessibility

| Feature | File | Implementation |
| --- | --- | --- |
| High Contrast | `HighContrastColors.swift` | Alternative color set with WCAG AA+ ratios |
| Reduced Motion | `ReducedMotionSupport.swift` | Respects `UIAccessibility.isReduceMotionEnabled` |
| Dynamic Type | All views | `.font(.body)` / `.font(.headline)` throughout |
| VoiceOver | All views | `.accessibilityLabel()` on all interactive elements |

---

## 20. Module Layout

### DoseCore (SwiftPM target: `ios/Core/`)

25 files, platform-free (no UIKit/SwiftUI).

| Category | Files |
| --- | --- |
| **Dose Logic** | `DoseWindowState.swift`, `DoseConstants.swift` |
| **Networking** | `APIClient.swift`, `APIErrors.swift`, `APIClientQueueIntegration.swift` |
| **Resilience** | `OfflineQueue.swift`, `EventRateLimiter.swift` |
| **Medication** | `Medication.swift`, `MedicationDose.swift`, `MedicationStore.swift`, `DosingAmountTypes.swift`, `DosingAmountCalculator.swift`, `DosingAmountDiagnostics.swift`, `DosingAmountMigration.swift` |
| **Protocols** | `DateProviding.swift` |
| **App Container** | `AppContainer.swift` |
| **Utilities** | Supporting types and extensions |

### App Target (`ios/DoseTap/`) -- 85+ files across 9 directories

| Directory | Count | Contents |
| --- | --- | --- |
| Root | 36 | Views, services, managers, app entry |
| `Storage/` | 13 | EventStorage + extensions, models, schema |
| `Views/` | 23 | All tab views, sub-views, sheets |
| `Export/` | 1 | Export service |
| `Foundation/` | 2 | Foundation extensions |
| `FullApp/` | 4 | Full-app entry points |
| `Persistence/` | 2 | Legacy persistence compatibility files |
| `Security/` | 3 | Keychain, biometric, jailbreak |
| `Services/` | 1 | Service layer files |
| `Theme/` | 1 | ThemeManager |

---

## 21. Test Pyramid

```
             ╱╲
            ╱  ╲          12 XCUITests (UI flows)
           ╱────╲
          ╱      ╲        587 XCTest unit tests (SwiftPM)
         ╱────────╲
        ╱          ╲      43 Swift Testing tests (SwiftPM)
       ╱────────────╲
      Total: 630 SwiftPM tests + Xcode tests
```

### SwiftPM Tests (`Tests/DoseCoreTests/`)

| File | Test Count | Coverage |
| --- | --- | --- |
| `DoseWindowStateTests.swift` | ~60 | Phase computation, CTA logic |
| `DoseWindowEdgeTests.swift` | ~40 | Boundary conditions, DST |
| `APIClientTests.swift` | ~30 | Request building, error mapping |
| `APIErrorsTests.swift` | ~25 | Status code -> error type |
| `OfflineQueueTests.swift` | ~20 | Enqueue, flush, retry |
| `EventRateLimiterTests.swift` | ~15 | Cooldown enforcement |
| `DosingServiceTests.swift` | ~20 | Facade action dispatch |
| `MedicationTests.swift` | ~30 | Medication CRUD |
| `DosingAmountTests.swift` | ~40 | Dosing calculations |
| + 20 more files | ~245 | Various edge cases |

### Xcode Tests (`ios/DoseTapTests/`)

| File | Coverage |
| --- | --- |
| `EventStorageTests.swift` | SQLite CRUD, migrations |
| `SessionRepositoryTests.swift` | Session lifecycle, rollover |
| `AlarmServiceTests.swift` | Notification scheduling |
| `HealthKitManagerTests.swift` | Sleep stage parsing |
| `ThemeManagerTests.swift` | Theme switching |
| `ExportServiceTests.swift` | CSV/JSON generation |
| + 5 more | Integration scenarios |

### XCUITests (`ios/DoseTapTests/XCUITests/`)

| File | Flows |
| --- | --- |
| `OnboardingUITests.swift` | First-run flow |
| `DosingFlowUITests.swift` | Dose 1 -> Dose 2 full cycle |

---

## 22. CI & Branch Protection

### Branch Strategy

```
main ──────────────────────────── production-ready
  └── chore/audit-2026-02-15 ─── active development (PR #1, 101 commits ahead)
       └── chore/audit-2026-02-15  audit findings
```

### CI Pipeline (GitHub Actions)

| Job | Trigger | Steps |
| --- | --- | --- |
| `swift-test` | Push to any branch | `swift build -q` → `swift test -q` |
| `xcode-build` | Push to `main`, `004-*` | `xcodebuild build` (simulator) |
| `lint` | PR | SwiftLint rules check |

### Branch Protection (main)

- Require PR review (1 approval)
- Require `swift-test` passing
- No force-push
- Linear history preferred

---

## 23. Known Issues & Technical Debt

> Full roadmap: `docs/IMPROVEMENT_ROADMAP.md` (6 P0 resolved + 7 P1 resolved + 8 P2 + 10 P3)

### P0 (Critical) — ALL RESOLVED ✅

| # | Issue | Resolution |
| --- | --- | --- |
| 1 | ~~WHOOP client secret needs rotation~~ | PKCE migration (P0-6), client_secret removed |
| 2 | ~~WHOOP data decorative only~~ | Real data wired to all surfaces (P0-1, P1-1/2/3) |
| 3 | ~~Snooze <15m check missing~~ | All UI surfaces use `DoseWindowContext.snooze` enum (P0-2) |
| 4 | ~~Flic bypasses late-dose confirmation~~ | Blocks with local notification (P0-3) |
| 5 | ~~Dose logic duplicated across 4 surfaces~~ | `DoseActionCoordinator` centralises (P0-4) |

### P1 (High) — ALL RESOLVED (P1-5 deferred) ✅

| # | Issue | Resolution |
| --- | --- | --- |
| 6 | ~~Night Review health data hardcoded~~ | Real WHOOP + HealthKit data per-session (P1-1) |
| 7 | ~~Timeline biometrics simulated~~ | Async real WHOOP API calls (P1-2) |
| 8 | ~~DashboardNightAggregate no WHOOP fields~~ | Full `whoopSummary` + 10+ computed properties (P1-3) |
| 9 | SessionRepository (1712 LOC) needs decomposition | Open — maintainability |
| 10 | ~~NightScoreCalculator not surfaced~~ | Night Review NightScoreCard (P1-6) |

### Remaining Open Items

| Priority | Issue | Roadmap |
| --- | --- | --- |
| P2-1 | No Widget support | Phase 6 |
| P2-2 | No Siri Shortcuts / AppIntents | Phase 6 |
| P2-3 | No watchOS companion | Phase 6 |
| P2-6 | No History search | Phase 6 |
| P3-6 | Session comparison view | Backlog |
| P3-7 | Data export scheduling | Backlog |
| P3-8 | Medication interaction warnings | Backlog |

### Technical Debt

- Legacy persistence shim files (`PersistentStore`, `FetchHelpers`) still remain
- `JSONMigrator` one-time migration code still ships
- Duplicate model types between `StorageModels` and `DoseCore`
- ~44,400 LOC total -- opportunity to extract shared frameworks
- Manual session date rollover logic duplicated in 3 places
- CloudKit sync is non-functional skeleton (~600 LOC)
- 6 quarantined legacy files still in project

---

## 24. Repository Structure

```
DoseTap/
├── Package.swift                    # SwiftPM manifest (DoseCore + tests)
├── ios/
│   ├── Core/                        # DoseCore SwiftPM target (24 files)
│   │   ├── DoseWindowState.swift    # Phase calculator + CTA engine
│   │   ├── APIClient.swift          # HTTP client with transport protocol
│   │   ├── APIErrors.swift          # Error mapper (422/409/429/401)
│   │   ├── APIClientQueueIntegration.swift  # DosingService facade
│   │   ├── OfflineQueue.swift       # Actor-based retry queue
│   │   ├── EventRateLimiter.swift   # Cooldown dedup
│   │   ├── AppContainer.swift       # DI composition root
│   │   ├── Medication.swift         # Medication model
│   │   ├── MedicationDose.swift     # Dose amount model
│   │   ├── MedicationStore.swift    # Medication CRUD
│   │   ├── DosingAmount*.swift      # Calculator, types, diagnostics, migration
│   │   └── ...
│   ├── DoseTap/                     # iOS app target (85+ files)
│   │   ├── DoseTapApp.swift         # @main entry
│   │   ├── ContentView.swift        # 5-tab root + DI wiring
│   │   ├── URLRouter.swift          # Deep link routing (389 LOC)
│   │   ├── SessionRepository.swift  # Central state store (1712 LOC)
│   │   ├── AlarmService.swift       # Notification engine (607 LOC)
│   │   ├── Storage/                 # SQLite layer (13 files)
│   │   ├── Views/                   # SwiftUI views (23 files)
│   │   ├── Security/                # Keychain, biometric, jailbreak (3 files)
│   │   ├── Theme/                   # ThemeManager (1 file)
│   │   └── ...
│   ├── DoseTap.xcodeproj/          # Xcode project
│   └── DoseTapTests/               # Xcode unit + UI tests (13 files)
├── Tests/
│   └── DoseCoreTests/              # SwiftPM unit tests (31 files, 559 tests)
├── docs/
│   ├── architecture.md             # This document
│   ├── SSOT/
│   │   ├── README.md               # Authoritative behavior spec
│   │   ├── navigation.md           # Navigation contracts
│   │   └── contracts/              # API + data contracts
│   ├── DATABASE_SCHEMA.md          # Schema reference
│   └── TESTING_GUIDE.md            # Test patterns & conventions
├── tools/                          # Build & maintenance scripts
├── watchos/                        # watchOS companion (planned)
└── specs/                          # Spec Kit feature specs
```

---

## Appendix A: Event Type Catalog

The `EventType` enum (`ios/DoseTap/Storage/`) defines all trackable events:

### Sleep Events

| Canonical String | Display Name | Notes |
| --- | --- | --- |
| `lights_out` | Lights Out | Triggers Night Mode, starts session |
| `sleep` | Fell Asleep | Estimated sleep onset |
| `wake` | Woke Up | Intermediate wake |
| `wake_final` | Final Wake | Ends sleep period |
| `nap` | Nap | Daytime sleep (separate from night) |

### Dose Events

| Canonical String | Display Name | Notes |
| --- | --- | --- |
| `dose_1` | Dose 1 Taken | Starts dose window countdown |
| `dose_2` | Dose 2 Taken | Must be 150-240m after dose 1 |
| `dose_skipped` | Dose Skipped | Explicit skip with reason |
| `dose_snoozed` | Dose Snoozed | +10m, max snoozes enforced |

### Symptom & Activity Events

| Canonical String | Display Name | Notes |
| --- | --- | --- |
| `bathroom` | Bathroom | Rate-limited (60s cooldown) |
| `food` | Food/Drink | Pre-sleep intake |
| `exercise` | Exercise | Activity logging |
| `stress` | Stress | Subjective marker |
| `pain` | Pain | With severity (1-10) |
| `anxiety` | Anxiety | Subjective marker |
| `screen_time` | Screen Time | Blue light exposure |
| `caffeine` | Caffeine | Intake timing |
| `alcohol` | Alcohol | Intake timing |
| `meditation` | Meditation | Relaxation activity |
| `reading` | Reading | Wind-down activity |
| `stretching` | Stretching | Physical activity |

### Check-In Events

| Canonical String | Display Name | Notes |
| --- | --- | --- |
| `morning_checkin` | Morning Check-In | Post-wake questionnaire |
| `pre_sleep_log` | Pre-Sleep Log | Pre-night questionnaire |
| `unknown(String)` | Dynamic | Extensible for future types |

---

## Appendix B: Flic Button Integration

**File:** `ios/DoseTap/FlicManager.swift`

| Click Type | Action | Context |
| --- | --- | --- |
| Single click | Log quick event (bathroom) | Configurable in Settings |
| Double click | Take Dose 2 | Only active during dose window |
| Hold (2s) | Start/stop session | Toggle lights_out / wake_final |

Requires Flic 2 SDK. BLE connection managed by `FlicManager`. Button actions routed through `URLRouter` as `dosetap://action/log?event=<type>`.

---

## Appendix C: Undo System

**File:** `ios/DoseTap/SessionRepository.swift`

### Undoable Actions

| Action | Revert Method | Window |
| --- | --- | --- |
| Log Event | `undoLastEvent()` | 30 seconds |
| Take Dose 1 | `undoDose1()` | 60 seconds |
| Take Dose 2 | `undoDose2()` | 60 seconds |
| Skip Dose | `undoSkip()` | 60 seconds |

Undo state tracked via `@Published var undoAction: UndoableAction?` with auto-expiry timer. UI shows floating undo banner when available.

---

## Cross-References

- **Behavior spec:** `docs/SSOT/README.md`
- **Database schema:** `docs/DATABASE_SCHEMA.md`
- **Test patterns:** `docs/TESTING_GUIDE.md`
- **Navigation contracts:** `docs/SSOT/navigation.md`
- **API contracts:** `docs/SSOT/contracts/`
- **Audit findings:** `docs/audit/2026-02-15/`
- **Changelog:** `CHANGELOG.md`

---

## Cross-References

- **Behavior spec:** `docs/SSOT/README.md`
- **Database schema:** `docs/DATABASE_SCHEMA.md`
- **Test patterns:** `docs/TESTING_GUIDE.md`
- **Improvement roadmap:** `docs/IMPROVEMENT_ROADMAP.md`
- **WHOOP integration:** `docs/WHOOP_INTEGRATION.md`
- **Dose registration review:** `docs/review/dose_registration_architecture_2026-02-15.md`
- **Changelog:** `CHANGELOG.md`

---

*Generated: 2026-02-16 | Version: 0.3.3 alpha | Branch: chore/audit-2026-02-15*
