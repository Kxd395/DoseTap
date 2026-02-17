# 06 — Services

## AlarmService

File: `ios/DoseTap/AlarmService.swift` (607 lines)

Manages all dose-related notifications and the alarm ringing UI.

```text
┌─────────────────────────────────────────────┐
│                AlarmService                  │
│                                             │
│  @Published targetWakeTime: Date?           │
│  @Published alarmScheduled: Bool            │
│  @Published snoozeCount: Int                │
│  @Published isAlarmRinging: Bool            │
│                                             │
│  Notification IDs:                          │
│  ├── dosetap_dose2_alarm                    │
│  ├── dosetap_dose2_pre_alarm                │
│  ├── dosetap_followup_1, _2, _3            │
│  ├── dosetap_second_dose                    │
│  ├── dosetap_window_15min                   │
│  └── dosetap_window_5min                    │
│                                             │
│  Notification Category: dosetap_alarm       │
│  Actions: [Snooze Xm] [I'm Awake]          │
└─────────────────────────────────────────────┘
```

### Key Methods

| Method | Purpose |
| ------ | ------- |
| `scheduleDose2Alarm(at:dose1Time:)` | Main alarm at target time |
| `scheduleDose2Reminders(dose1Time:)` | Window open + 15m/5m warnings |
| `rescheduleAlarm(addingMinutes:)` | Snooze implementation |
| `cancelDose2Alarm()` | Cancel on dose2 taken |
| `cancelAllSessionNotifications()` | Rollover cleanup |
| `triggerAlarmUI()` | Show fullscreen ringing view |
| `stopAlarm()` | User tapped "I'm Awake" |

### Notification Schedule

```text
D1 at 10:30 PM, target = 165m

  10:30 PM ─── D1 taken
      │
  01:00 AM ─── "dosetap_second_dose" (window opens, 150m)
      │
  01:15 AM ─── "dosetap_dose2_alarm" (target, 165m) ← RINGING
      │
  01:25 AM ─── followup_1 (target + 10m)
  01:35 AM ─── followup_2 (target + 20m)
  01:45 AM ─── followup_3 (target + 30m)
      │
  02:15 AM ─── "dosetap_window_15min" (225m, 15m warning)
  02:25 AM ─── "dosetap_window_5min" (235m, 5m warning)
      │
  02:30 AM ─── Window closes (240m)
```

### Critical Alerts

Optional iOS Critical Alerts (requires entitlement):

- Bypass Do Not Disturb
- Custom sound volume
- Enabled via `Settings → Notifications → Critical Alerts`

---

## HealthKitService

File: `ios/DoseTap/HealthKitService.swift` (483 lines)

```text
┌─────────────────────────────────────────────┐
│            HealthKitService                  │
│                                             │
│  Data Types Read:                           │
│  └── HKCategoryType(.sleepAnalysis)         │
│                                             │
│  @Published isAuthorized: Bool              │
│  @Published ttfwBaseline: Double?           │
│  @Published sleepHistory: [SleepNight...]   │
│  @Published lastError: String?              │
└─────────────────────────────────────────────┘
```

### Key Methods

| Method | Purpose |
| ------ | ------- |
| `requestAuthorization()` | Request HealthKit read access |
| `fetchSleepData(for:)` | Get sleep segments for a date |
| `computeSleepNightSummary(for:)` | Total sleep, TTFW, wake count |
| `fetchTTFWBaseline(days:)` | Average TTFW over N days |

### Sleep Stages

```swift
enum SleepStage {
    case inBed
    case asleep       // Generic
    case asleepCore   // Light/Core sleep
    case asleepDeep   // Deep/SWS
    case asleepREM    // REM
    case awake        // Wake after sleep onset
}
```

### SleepNightSummary

```swift
struct SleepNightSummary {
    let date: Date
    let bedTime: Date?
    let sleepOnset: Date?
    let firstWake: Date?
    let finalWake: Date?
    let ttfwMinutes: Double?       // Time to first wake
    let totalSleepMinutes: Double
    let wakeCount: Int             // WASO proxy
    let source: String             // "Apple Watch", etc.
}
```

---

## WHOOPService

File: `ios/DoseTap/WHOOPService.swift` (~564 lines)
Data: `ios/DoseTap/WHOOPDataFetching.swift` (~492 lines)

**Status: Dynamic feature flag — reads `UserDefaults("whoop_enabled")`, auto-set on connect/disconnect**

```text
┌─────────────────────────────────────────────┐
│            WHOOPService                      │
│                                             │
│  static var isEnabled: Bool                 │
│   → UserDefaults("whoop_enabled")           │
│   (auto-set true on connect,               │
│    false on disconnect)                     │
│                                             │
│  OAuth 2.0 + PKCE:                          │
│  ├── client_id (from SecureConfig)          │
│  ├── code_verifier + code_challenge (S256)  │
│  └── redirect_uri                           │
│                                             │
│  API Endpoints (all implemented):           │
│  ├── /developer/v2/activity/sleep           │
│  ├── /developer/v2/activity/sleep/{id}      │
│  ├── /developer/v2/recovery                 │
│  ├── /developer/v2/cycle                    │
│  └── /developer/v2/activity/heart_rate      │
│                                             │
│  Data Models:                               │
│  ├── WHOOPSleep → WHOOPNightSummary         │
│  ├── WHOOPRecovery (recovery + HRV merge)   │
│  ├── WHOOPHeartRate (per-minute HR)         │
│  ├── WHOOPSleepStages → SleepStageBand      │
│  └── WHOOPSleepScore (efficiency, RR, etc)  │
│                                             │
│  Integration Points:                        │
│  ├── Dashboard: DashboardWHOOPCard          │
│  │   (recovery gauge, biometrics, stages)   │
│  ├── Dashboard: Executive Summary KPIs      │
│  │   (recovery %, HRV ms)                   │
│  ├── Dashboard: Recovery Trend chart        │
│  ├── Dashboard: period comparison deltas    │
│  ├── Dashboard: whoopSummary on aggregate   │
│  ├── Night Review: per-session WHOOP card   │
│  ├── Timeline: HR/RR/HRV overlays          │
│  ├── Settings: sleep history with recovery  │
│  └── DoseEffectivenessCalculator: HRV/rec.  │
└─────────────────────────────────────────────┘
```

### WHOOP Data Flow

```text
WHOOP API
  │
  ├── fetchRecentSleep(nights:) ─► [WHOOPSleep]
  │     └── .toNightSummary() ─► WHOOPNightSummary
  │           (totalSleep, deep, REM, light, awake,
  │            efficiency, respiratoryRate)
  │
  ├── fetchRecoveryData(from:to:) ─► [WHOOPRecovery]
  │     └── merged into WHOOPNightSummary by sleepId
  │           (+recoveryScore, +hrvMs, +restingHR)
  │
  ├── fetchHeartRateData(from:to:) ─► [WHOOPHeartRate]
  │     └── Timeline: per-minute HR overlay
  │
  └── fetchCycleData(from:to:) ─► [WHOOPCycle]

DashboardModels.loadNights()
  │  gate: isEnabled && whoopEnabled && isConnected
  │  fetches sleep + recovery, keys by session date
  ▼
DashboardNightAggregate.whoopSummary
  │  accessed via: .whoopRecoveryScore, .whoopHRV,
  │  .whoopSleepEfficiency, .whoopRespiratoryRate, etc.
  ▼
DashboardViewModel computed averages
  │  averageWhoopRecovery, averageWhoopHRV,
  │  averageWhoopRestingHR, averageWhoopDeepMinutes, ...
  ▼
Views: DashboardWHOOPCard, ExecutiveSummary KPIs,
       RecoveryTrend chart, period comparison deltas

LiveEnhancedTimelineView (SleepTimelineOverlays.swift)
  │  fetches HR data → heartRateData overlay
  │  uses sleep.score.respiratoryRate → RR baseline overlay
  │  uses WHOOPNightSummary.hrvMs → HRV baseline overlay
  ▼
EnhancedSleepTimeline: toggleable HR/RR/HRV overlays
```

---

## FlicButtonService

File: `ios/DoseTap/FlicButtonService.swift` (724 lines)

Hardware button integration for bedside use.

### Gesture Mapping

| Gesture | Default Action | Customizable |
| ------- | -------------- | ------------ |
| Single press | Take dose (D1 or D2) | Yes |
| Double press | Snooze (+10m) | Yes |
| Long hold (1s+) | Undo last action | Yes |

### Available Actions

```swift
enum FlicAction: String {
    case takeDose       // "take_dose"
    case snooze         // "snooze"
    case undo           // "undo"
    case logBathroom    // "log_bathroom"
    case logLightsOut   // "log_lights_out"
    case logWake        // "log_wake"
    case skip           // "skip"
    case none           // "none"
}
```

### State

```swift
@Published isPaired: Bool
@Published isConnected: Bool
@Published batteryLevel: Int?
@Published lastEventTime: Date?
@Published lastAction: FlicAction?
```

---

## URLRouter (Deep Links)

File: `ios/DoseTap/URLRouter.swift` (395 lines)

### Supported URLs

| URL | Action |
| --- | ------ |
| `dosetap://dose1` | Take Dose 1 |
| `dosetap://dose2` | Take Dose 2 |
| `dosetap://snooze` | Snooze alarm |
| `dosetap://skip` | Skip Dose 2 |
| `dosetap://log?event=bathroom` | Log event |
| `dosetap://log?event=X&notes=Y` | Log event with notes |
| `dosetap://tonight` | Navigate to Tonight tab |
| `dosetap://timeline` | Navigate to Timeline tab |
| `dosetap://history` | Navigate to History tab |
| `dosetap://dashboard` | Navigate to Dashboard tab |
| `dosetap://settings` | Navigate to Settings tab |

### URL Validation

All deep link inputs validated through `InputValidator`:

- Event names checked against whitelist
- Notes sanitized (max 500 chars)
- URL host validated against known routes

---

## EventLogger

File: `ios/DoseTap/EventLogger.swift` (196 lines)

In-memory event cache + SQLite persistence for tonight's events.

```swift
@Published var events: [LoggedEvent]
@Published var cooldowns: [String: Date]

func logEvent(name:color:cooldownSeconds:persist:notes:)
func isOnCooldown(_:) -> Bool
func clearCooldown(for:)
```

Cooldown prevents duplicate taps (e.g., bathroom cooldown = 60s).

---

## AnalyticsService

File: `ios/DoseTap/AnalyticsService.swift`

Local analytics computation (no remote tracking):

- Adherence percentages
- Interval trends
- Event frequency
- Sleep correlation
- Export to CSV/JSON

---

## InsightsCalculator

File: `ios/DoseTap/InsightsCalculator.swift`

Computes dashboard trend metrics from session history.

---

## SleepPlanStore

File: `ios/DoseTap/SleepPlanDetailView.swift` (approximate)

Manages sleep schedule recommendations and per-night overrides.
