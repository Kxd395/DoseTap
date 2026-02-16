# 01 — Tab Architecture

## Navigation Model

5 tabs with swipe navigation (`.tabViewStyle(.page)`), custom tab bar.

```text
┌────────┬──────────┬──────────┬───────────┬──────────┐
│Tonight │ Timeline │ History  │ Dashboard │ Settings │
│moon    │ chart    │ calendar │ xyaxis    │ gear     │
│ .0     │  .1      │  .2      │   .3      │  .4      │
└────────┴──────────┴──────────┴───────────┴──────────┘
         ◄── swipe ──►
```

Deep link tab navigation: `dosetap://tonight`, `dosetap://timeline`, etc.

File: `ios/DoseTap/ContentView.swift` (229 lines)

---

## Tab 0: Tonight (Primary)

File: `ios/DoseTap/Views/TonightView.swift` (478 lines)

```text
┌─────────────────────────────────────────────────┐
│              DoseTap [Theme Toggle]              │
│           Thursday, Feb 15, 2026                 │
│            ⏰ Alarm: 2:45 AM                     │
│                                                  │
│  ┌──────── CompactStatusCard ──────────┐         │
│  │ Phase icon + title + countdown      │         │
│  │ (beforeWindow / active / nearClose  │         │
│  │  closed / completed / finalizing)   │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── PreSleepCard ───────────────┐         │
│  │ "Log Pre-Sleep" or summary of log   │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── CompactDoseButton ──────────┐         │
│  │ [████████ Take Dose 1 ████████████] │         │
│  │                                     │         │
│  │ [Snooze +10m]        [Skip Dose 2]  │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── QuickEventPanel ────────────┐         │
│  │ 🚽 Bathroom  💡 Lights Out  🌊 Water│         │
│  │ 🛏 In Bed    😰 Anxiety    🍽 Snack │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── WakeUpButton ───────────────┐         │
│  │ [☀️ Wake Up & End Session]          │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── CompactSessionSummary ──────┐         │
│  │ Tonight's events timeline           │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── LiveDoseIntervalsCard ──────┐         │
│  │ D1→D2 interval, window status       │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── SleepPlanSummaryCard ───────┐         │
│  │ Wake by: 6:30 AM · In bed: 10:00 PM│         │
│  │ Wind down: 9:30 PM                  │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── SleepPlanOverrideCard ──────┐         │
│  │ [Override wake time for tonight]     │         │
│  └─────────────────────────────────────┘         │
└─────────────────────────────────────────────────┘
```

### Tonight Components

| Component | File | Purpose |
| --------- | ---- | ------- |
| CompactStatusCard | `Views/CompactStatusCard.swift` | Phase display + countdown |
| CompactDoseButton | `Views/CompactDoseButton.swift` | Primary CTA + snooze/skip |
| QuickEventPanel | `Views/QuickEventViews.swift` | Quick-log buttons |
| WakeUpButton | `Views/QuickEventViews.swift` | End session trigger |
| CompactSessionSummary | `Views/SessionSummaryViews.swift` | Event timeline |
| LiveDoseIntervalsCard | `Views/SessionSummaryViews.swift` | D1→D2 timing |
| PreSleepCard | `Views/PreSleepLogView.swift` | Pre-sleep log CTA/summary |
| SleepPlanSummaryCard | `Views/SleepPlanCards.swift` | Sleep schedule |
| AlarmIndicatorView | `AlarmService.swift` | Scheduled alarm time |

### Tonight Actions

| User Action | Handler | Result |
| ----------- | ------- | ------ |
| Tap "Take Dose 1" | `CompactDoseButton` → `DoseActionCoordinator.takeDose1()` | Sets dose1Time, schedules alarm |
| Tap "Take Dose 2" | `CompactDoseButton` → `DoseActionCoordinator.takeDose2()` | Sets dose2Time, may need confirm |
| Tap "Snooze +10m" | `CompactDoseButton` → `SessionRepository.incrementSnoozeCount()` | +10m delay |
| Tap "Skip" | `CompactDoseButton` → `SessionRepository.skipDose2()` | Marks skipped |
| Tap Quick Event | `QuickEventPanel` → `EventLogger.logEvent()` | SQLite insert |
| Tap "Wake Up" | `WakeUpButton` → logs wake_final → shows MorningCheckIn | Ends session |
| Tap "Pre-Sleep" | `PreSleepCard` → sheets `PreSleepLogView` | Logs sleep context |

---

## Tab 1: Timeline (Details)

File: `ios/DoseTap/Views/DetailsView.swift`

```text
┌─────────────────────────────────────────────────┐
│               Tonight's Timeline                 │
│                                                  │
│  ┌──────── TimelineReviewViews ────────┐         │
│  │ Dose 1 ────────────────── 10:30 PM  │         │
│  │   │                                 │         │
│  │   ├─ Lights Out ─────── 10:45 PM    │         │
│  │   ├─ Bathroom ──────── 12:15 AM     │         │
│  │   │                                 │         │
│  │ Dose 2 ────────────────── 1:15 AM   │         │
│  │   │ Interval: 165m ✓               │         │
│  │   │                                 │         │
│  │   ├─ Wake Final ────── 6:30 AM      │         │
│  │   └─ Check-In ──────── 6:32 AM      │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── SleepStageTimeline ─────────┐         │
│  │ HealthKit sleep stages (if auth'd)  │         │
│  │ Awake ─── Light ─── Deep ─── REM    │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── NightReviewView ────────────┐         │
│  │ NightScoreCard (0-100 ring)         │         │
│  │ Component bars: interval/dose/      │         │
│  │   session/sleep                     │         │
│  │ Health Data (if connected)          │         │
│  └─────────────────────────────────────┘         │
└─────────────────────────────────────────────────┘
```

Key files:

- `Views/Timeline/TimelineReviewViews.swift` — event timeline
- `SleepStageTimeline.swift` — HealthKit stages
- `SleepTimelineOverlays.swift` — biometric overlays
- `Views/NightReviewView.swift` — night score + health summary

---

## Tab 2: History

File: `ios/DoseTap/Views/History/HistoryViews.swift` (1214 lines)

```text
┌─────────────────────────────────────────────────┐
│                    History                        │
│                                                  │
│  ┌──────── InsightsSummaryCard ────────┐         │
│  │ Trends: avg interval, on-time %,   │         │
│  │ streak, bathroom avg               │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── DatePicker (.graphical) ────┐         │
│  │ [  February 2026 calendar grid   ] │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── SelectedDayView ────────────┐         │
│  │ Dose 1: 10:30 PM [Edit]            │         │
│  │ Dose 2: 1:15 AM  [Edit]            │         │
│  │ Interval: 165m (on-time ✓)         │         │
│  │ Events: 🚽×2 💡×1                  │         │
│  │ HealthKit: 7h 12m sleep            │         │
│  │ [🗑 Delete Day]                     │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── RecentSessionsList ─────────┐         │
│  │ Last 7 sessions with dose data      │         │
│  └─────────────────────────────────────┘         │
└─────────────────────────────────────────────────┘
```

### History Actions

| Action | Handler |
| ------ | ------- |
| Select date | `DatePicker` → updates `SelectedDayView` |
| Edit Dose 1/2 | `EditDoseTimeView` sheet |
| Delete day | `SessionRepository.deleteSession()` |
| Pull to refresh | `.refreshable` → `loadHistory()` |

---

## Tab 3: Dashboard

Files:

- `Views/Dashboard/DashboardModels.swift` (1429 lines)
- `Views/Dashboard/DashboardViews.swift`

```text
┌─────────────────────────────────────────────────┐
│                   Dashboard                      │
│                                                  │
│  [7D] [14D] [30D] [90D] [1Y] [All]  ← range    │
│                                                  │
│  ┌──────── Interval Chart ─────────────┐         │
│  │ Line/bar chart: D1→D2 minutes       │         │
│  │ 150m ---- target ---- 240m bands    │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── Adherence Stats ────────────┐         │
│  │ On-time: 85% · Skipped: 10%        │         │
│  │ Late: 5% · Avg interval: 168m      │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── Sleep Summary ──────────────┐         │
│  │ Avg sleep: 6h 45m · Avg TTFW: 92m  │         │
│  │ Bathroom avg: 1.5/night            │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── Event Breakdown ────────────┐         │
│  │ Bathroom: 45 · Lights Out: 30      │         │
│  │ Anxiety: 8 · Pain: 5               │         │
│  └─────────────────────────────────────┘         │
│                                                  │
│  ┌──────── Export Card ────────────────┐         │
│  │ [📤 Export CSV] [📤 Export JSON]    │         │
│  └─────────────────────────────────────┘         │
└─────────────────────────────────────────────────┘
```

### Dashboard Models

- `DashboardDateRange` — 7D/14D/30D/90D/1Y/All with cutoff date math
- `DashboardNightAggregate` — per-night summary with doses, events, health, check-ins
- `DashboardViewModel` — aggregation engine with Charts data

---

## Tab 4: Settings

File: `ios/DoseTap/SettingsView.swift` (696 lines)

```text
┌─────────────────────────────────────────────────┐
│                   Settings                       │
│                                                  │
│  ═══ Dose & Timing ═══                           │
│  Target interval: [165 min]                      │
│  Weekly Planner >                                │
│  Undo speed: [10 sec]                            │
│  ℹ XYWAV Window info card                       │
│                                                  │
│  ═══ Night Schedule ═══                           │
│  Sleep Start: [10:00 PM]                         │
│  Wake Time:   [6:30 AM]                          │
│  ▶ Evening Prep & Auto-Close                     │
│                                                  │
│  ═══ Notifications ═══                            │
│  Notifications: [ON]                             │
│  Alarm Sound >                                   │
│  Critical Alerts: [OFF]                          │
│                                                  │
│  ═══ Flic Button ═══                              │
│  Pair Flic >                                     │
│  Single/Double/Hold gesture config               │
│                                                  │
│  ═══ Integrations ═══                             │
│  Apple Health >                                  │
│  WHOOP > (isEnabled: false)                      │
│                                                  │
│  ═══ Appearance ═══                               │
│  Theme >                                         │
│  Reduced Motion: [OFF]                           │
│                                                  │
│  ═══ Quick Log Buttons ═══                        │
│  Customize quick event panel >                   │
│  Event Cooldowns >                               │
│                                                  │
│  ═══ Medication ═══                               │
│  Medication Settings >                           │
│  Dosing Amount >                                 │
│                                                  │
│  ═══ Data ═══                                     │
│  Export Data > (CSV/JSON)                        │
│  Diagnostic Logging >                            │
│  Support Bundle >                                │
│  Data Management >                               │
│                                                  │
│  ═══ About ═══                                    │
│  Version · Privacy Policy · Reset App            │
└─────────────────────────────────────────────────┘
```

### Settings Sub-Views

| View | File | Purpose |
| ---- | ---- | ------- |
| WeeklyPlannerView | `WeeklyPlanner.swift` | Per-day target intervals |
| MedicationSettingsView | `Views/MedicationSettingsView.swift` | Med name/type |
| DoseAmountPicker | `Views/DoseAmountPicker.swift` | Split dose amounts |
| ThemeSettingsView | `Views/ThemeSettingsView.swift` | Light/dark/night mode |
| HealthKitSettingsView | `HealthKitSettingsView.swift` | HealthKit auth |
| WHOOPSettingsView | `WHOOPSettingsView.swift` | WHOOP OAuth |
| QuickLogCustomizationView | `QuickLogCustomizationView.swift` | Event button config |
| EventCooldownSettingsView | `EventCooldownSettingsView.swift` | Cooldown durations |
| DiagnosticLoggingSettingsView | `DiagnosticLoggingSettingsView.swift` | Tier 1/2/3 toggles |
| DataManagementView | `DataManagementView.swift` | Delete/export |
| AboutView | `AboutView.swift` | Version, legal |

---

## Breadcrumb Navigation

```text
Tonight ──────────────────────────────────────────
  ├── PreSleepLogView (sheet)
  ├── MorningCheckInView (sheet)
  ├── EarlyDoseOverrideSheet (sheet, from alert)
  ├── ExtraDoseWarning (alert)
  └── AlarmRingingView (fullScreenCover)

Timeline ─────────────────────────────────────────
  └── NightReviewView (inline)
       └── NightScoreCard (inline)

History ──────────────────────────────────────────
  └── SelectedDayView (inline)
       ├── EditDoseTimeView (sheet)
       └── Delete confirmation (alert)

Dashboard ────────────────────────────────────────
  └── Export sheet (share)

Settings ─────────────────────────────────────────
  ├── WeeklyPlannerView (NavigationLink)
  ├── MedicationSettingsView (NavigationLink)
  ├── DoseAmountPicker (NavigationLink)
  ├── ThemeSettingsView (NavigationLink)
  ├── HealthKitSettingsView (NavigationLink)
  ├── WHOOPSettingsView (NavigationLink)
  ├── QuickLogCustomizationView (NavigationLink)
  ├── EventCooldownSettingsView (NavigationLink)
  ├── DiagnosticLoggingSettingsView (NavigationLink)
  ├── DataManagementView (NavigationLink)
  ├── DiagnosticExportView (NavigationLink)
  ├── SupportBundleExport (NavigationLink)
  ├── AboutView (NavigationLink)
  └── Reset App (alert)
```
