# DoseTap Feature Roadmap

> **Development Phases & Progress**  
> Version: 2.1 | January 2025  
> Last Updated: 2025-01-06
>
> **Note:** Test counts in this document are historical snapshots from when features were implemented. See CI for current test totals.

---

## Table of Contents

1. [Phase 1.5: UI Overhaul](#phase-15-ui-overhaul) ✅ COMPLETE
2. [Phase 1: Sleep Event Logging](#phase-1-sleep-event-logging) ✅ COMPLETE
3. [Phase 2: Health Data Dashboard](#phase-2-health-data-dashboard) 🔄 IN PROGRESS
4. [Phase 3: Advanced Analytics](#phase-3-advanced-analytics) 📋 PLANNED
5. [Technical Architecture](#technical-architecture)

---

## Phase 1.5: UI Overhaul ✅ COMPLETE

### Implementation Status: 100%

| Task | Status | File |
|------|--------|------|
| Swipe navigation (page TabView) | ✅ | `ios/DoseTap/ContentView.swift` |
| Custom bottom tab bar | ✅ | `ios/DoseTap/ContentView.swift` |
| Compact Tonight screen (no scroll) | ✅ | `ios/DoseTap/ContentView.swift` |
| History page with date picker | ✅ | `ios/DoseTap/ContentView.swift` |
| Delete from History (per day) | ✅ | `ios/DoseTap/ContentView.swift` |
| Data Management screen | ✅ | `ios/DoseTap/SettingsView.swift` |
| Multi-select session deletion | ✅ | `ios/DoseTap/SettingsView.swift` |
| SQLite delete methods | ✅ | `ios/DoseTap/Storage/EventStorage.swift` |
| Dose events in timeline | ✅ | `ios/DoseTap/ContentView.swift` |

### 4-Tab Navigation Layout

| Tab | Name | Features |
|-----|------|----------|
| 1 | Tonight | Compact, no scroll, dose buttons, quick events, integrated timer |
| 2 | Details | Full session info, scrollable event timeline |
| 3 | History | Date picker, view past days, delete per day with confirmation |
| 4 | Settings | Configuration, notifications, data management |

### UI Implementation

```
4-Tab Swipe Navigation:
┌─────────────────────────────────────┐
│  [Tonight] [Details] [History] [⚙️] │
│  ─────────────────────────────────  │
│                                     │
│        ◀── Swipe to navigate ──▶    │
│                                     │
└─────────────────────────────────────┘

Tonight Screen (Compact):
┌─────────────────────────────────────┐
│  ┌─────────────────────────────────┐│
│  │ Status Card + Timer (combined)  ││
│  └─────────────────────────────────┘│
│  ┌──────────┐  ┌──────────┐        │
│  │  Dose 1  │  │  Dose 2  │        │
│  └──────────┘  └──────────┘        │
│  ┌─────────────────────────────────┐│
│  │ Compact Session Summary         ││
│  └─────────────────────────────────┘│
│  ┌─────────────────────────────────┐│
│  │ Quick Log Panel (4x3 grid)      ││
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘

History Screen:
┌─────────────────────────────────────┐
│  ◀ Jan 5  [Jan 6]  Jan 7 ▶  📅     │
│  ─────────────────────────────────  │
│  Dose 1: 10:30 PM                   │
│  Dose 2: 1:15 AM                    │
│  Events: 3 logged                   │
│                      [🗑️ Delete]    │
└─────────────────────────────────────┘

Data Management (Settings):
┌─────────────────────────────────────┐
│  Manage History                     │
│  ─────────────────────────────────  │
│  [Clear All] [Clear Old (30d)]      │
│  ─────────────────────────────────  │
│  Sessions:          [Edit]          │
│  ☑ Jan 6, 2025                      │
│  ☐ Jan 5, 2025                      │
│  ☑ Jan 4, 2025                      │
│         [Delete Selected (2)]       │
└─────────────────────────────────────┘
```

### Delete Functionality

| Location | Method | Confirmation |
|----------|--------|--------------|
| History page | Delete per day (trash icon) | Alert dialog |
| Settings > Data Management | Clear All Events | Alert dialog |
| Settings > Data Management | Clear Old (>30 days) | Alert dialog |
| Settings > Data Management | Multi-select delete | Alert dialog |
| Settings > Data Management | Swipe to delete | Destructive button |

### SQLite Methods Added

```swift
// EventStorage.swift
func deleteSession(sessionDate: Date)      // Delete single day
func clearAllSleepEvents()                 // Clear all events
func clearOldData(olderThanDays: Int)      // Clear old data
```

---

## Phase 1: Sleep Event Logging ✅ COMPLETE

### Implementation Status: 100%

| Task | Status | File |
|------|--------|------|
| SleepEvent model (13 types) | ✅ | `ios/Core/SleepEvent.swift` |
| EventRateLimiter extension | ✅ | `ios/Core/EventRateLimiter.swift` |
| SQLite sleep_events table | ✅ | `ios/DoseTapiOSApp/SQLiteStorage.swift` |
| QuickLogPanel UI | ✅ | `ios/DoseTapiOSApp/QuickLogPanel.swift` |
| TimelineView historical | ✅ | `ios/DoseTapiOSApp/TimelineView.swift` |
| DoseCoreIntegration.logSleepEvent() | ✅ | `ios/DoseTapiOSApp/DoseCoreIntegration.swift` |
| UnifiedSleepSession model | ✅ | `ios/Core/UnifiedSleepSession.swift` |
| SleepEventTests (29 tests) | ✅ | `Tests/DoseCoreTests/SleepEventTests.swift` |
| ContentView integration | ✅ | `ios/DoseTap/ContentView.swift` |

### Implemented Event Types (13 total)

| Event | Cooldown | Category | Icon |
|-------|----------|----------|------|
| `bathroom` | 60s | Physical | 🚽 |
| `water` | 300s | Physical | 💧 |
| `snack` | 900s | Physical | 🍴 |
| `lightsOut` | 3600s | Sleep Cycle | 💡 |
| `wakeFinal` | 3600s | Sleep Cycle | ☀️ |
| `wakeTemp` | 300s | Sleep Cycle | 🌙 |
| `anxiety` | 300s | Mental | 🧠 |
| `dream` | 60s | Mental | ☁️ |
| `heartRacing` | 300s | Mental | ❤️ |
| `noise` | 60s | Environment | 🔊 |
| `temperature` | 300s | Environment | 🌡️ |
| `pain` | 300s | Environment | 🩹 |

### UI Implementation

```
Tonight Screen (below dose buttons):
┌─────────────────────────────────────┐
│  Log Sleep Events                   │
│  ─────────────────────────────────  │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐       │
│  │ 🚽 │ │ � │ │ 🍴 │ │ 💡 │       │
│  │Bath│ │Watr│ │Snck│ │Lite│       │
│  └────┘ └────┘ └────┘ └────┘       │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐       │
│  │ ☀️ │ │ 🌙 │ │ 🧠 │ │ ☁️ │       │
│  │Wake│ │Temp│ │Anxi│ │Drem│       │
│  └────┘ └────┘ └────┘ └────┘       │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐       │
│  │ ❤️ │ │ 🔊 │ │ 🌡️ │ │ 🩹 │       │
│  │Hrt │ │Nose│ │Temp│ │Pain│       │
│  └────┘ └────┘ └────┘ └────┘       │
└─────────────────────────────────────┘
```

### Tests: 29 new tests added
- All cooldown scenarios
- All event types
- Category assignments
- Icon mappings
- Encoding/decoding

---

## Phase 2: Health Data Dashboard 🔄 IN PROGRESS

> **Note:** Sleep event model is defined in `ios/Core/SleepEvent.swift` with 13 event types.
> See `docs/SSOT/constants.json` for canonical cooldown values.

---

## 2. Health Data Dashboard

### Proposed Dashboard Layout

```
┌─────────────────────────────────────┐
│  D A S H B O A R D      [7d][30d]   │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────────┐│
│  │  Tonight's Sleep                ││
│  │  ───────────────────────────────││
│  │  In Bed:     10:30 PM           ││
│  │  Lights Out: 10:45 PM           ││
│  │  Dose 1:     10:50 PM           ││
│  │  Bathroom:   12:15 AM, 2:30 AM  ││
│  │  Dose 2:     1:35 AM            ││
│  │  Wake:       6:30 AM            ││
│  │  ───────────────────────────────││
│  │  Total Sleep: 7h 45m            ││
│  │  Awakenings:  2                 ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌─────────────────────────────────┐│
│  │  Heart Rate (Apple Watch)       ││
│  │  ───────────────────────────────││
│  │  Sleeping HR: 52 bpm avg        ││
│  │  [Chart: 10pm ───────── 6am]    ││
│  │   80│     ╱╲                    ││
│  │   60│────╱  ╲───────────        ││
│  │   40│                           ││
│  │  ───────────────────────────────││
│  │  HRV: 45ms avg (▲ from 42ms)    ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌─────────────────────────────────┐│
│  │  WHOOP Recovery                 ││
│  │  ───────────────────────────────││
│  │  Recovery Score: 67% 🟡         ││
│  │  Strain: 8.2                    ││
│  │  Sleep Performance: 85%         ││
│  │  ───────────────────────────────││
│  │  RHR: 54 bpm                    ││
│  │  Resp Rate: 14.2 /min           ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌─────────────────────────────────┐│
│  │  Dose Timing Insights           ││
│  │  ───────────────────────────────││
│  │  Avg Interval: 3h 12m           ││
│  │  On-Time Rate: 92%              ││
│  │  ───────────────────────────────││
│  │  💡 You sleep better when       ││
│  │     Dose 1 is before 11 PM      ││
│  └─────────────────────────────────┘│
│                                     │
├─────────────────────────────────────┤
│  🏠        📊        📈        ⚙️   │
│ Tonight  Timeline  Dashboard Settings│
└─────────────────────────────────────┘
```

### Metrics to Display

| Source | Metric | Display |
|--------|--------|---------|
| DoseTap | Dose 1 time | Time + relative |
| DoseTap | Dose 2 time | Time + interval |
| DoseTap | Events logged | Timeline |
| DoseTap | Adherence % | Progress bar |
| Apple Health | Sleep duration | Hours/minutes |
| Apple Health | Sleep stages | Bar chart |
| Apple Health | Heart rate (sleep) | Min/avg/max |
| Apple Health | HRV | Trend arrow |
| Apple Health | Respiratory rate | Breaths/min |
| WHOOP | Recovery score | Percentage + color |
| WHOOP | Strain | Daily strain |
| WHOOP | Sleep performance | Percentage |
| WHOOP | Sleep cycles | Count |
| WHOOP | Disturbances | Count |

---

## 3. Apple Health Integration

### Current State

- `HealthIntegrationService.swift` exists (341 lines)
- Basic sleep data fetching implemented
- Authorization flow in place
- Only reads `sleepAnalysis` type

### Proposed Enhancements

#### Additional HealthKit Data Types

```swift
// Read types to request
let readTypes: Set<HKObjectType> = [
    // Sleep
    HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
    
    // Heart
    HKObjectType.quantityType(forIdentifier: .heartRate)!,
    HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
    HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
    
    // Respiratory
    HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
    HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
    
    // Activity (for sleep quality correlation)
    HKObjectType.quantityType(forIdentifier: .stepCount)!,
    HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
]
```

#### Sleep Stages (iOS 16+)

```swift
// Parse iOS 16+ sleep stages
extension HKCategoryValueSleepAnalysis {
    var stageName: String {
        switch self {
        case .awake: return "Awake"
        case .asleepCore: return "Core"
        case .asleepDeep: return "Deep"
        case .asleepREM: return "REM"
        case .asleepUnspecified: return "Asleep"
        case .inBed: return "In Bed"
        @unknown default: return "Unknown"
        }
    }
}
```

#### Heart Rate During Sleep

```swift
public struct SleepHeartRateData {
    let date: Date
    let minHR: Double
    let avgHR: Double
    let maxHR: Double
    let restingHR: Double?
    let hrvAvg: Double?
    
    // Computed
    var sleepQualityIndicator: SleepQuality {
        // Lower resting HR + higher HRV = better recovery
        if let hrv = hrvAvg, hrv > 50 && avgHR < 60 {
            return .excellent
        } else if avgHR < 65 {
            return .good
        } else {
            return .fair
        }
    }
}
```

---

## 4. WHOOP Integration

### Current State

- `WHOOP.swift` exists (639 lines)
- OAuth flow implemented
- Token refresh logic in place
- Fetches sleep data, cycles, recovery
- **Not tested** — needs validation

### Proposed Enhancements

#### Data Points to Fetch

```swift
public struct WHOOPNightData {
    // From /v1/cycle
    let cycleId: Int
    let strain: Double
    let kilojoules: Double
    
    // From /v1/recovery
    let recoveryScore: Double      // 0-100
    let restingHeartRate: Double   // bpm
    let hrvRmssd: Double           // ms (different from Apple's SDNN)
    let spo2: Double?              // %
    let skinTemp: Double?          // °C
    
    // From /v1/sleep
    let sleepId: Int
    let qualityDuration: TimeInterval   // Total quality sleep
    let remDuration: TimeInterval
    let deepDuration: TimeInterval
    let lightDuration: TimeInterval
    let awakeDuration: TimeInterval
    let sleepEfficiency: Double    // %
    let respiratoryRate: Double    // breaths/min
    let sleepPerformance: Double   // % of sleep need met
    let sleepConsistency: Double   // % consistency with schedule
    let sleepNeed: TimeInterval    // Baseline sleep need
    let disturbances: Int          // Count
}
```

#### Correlation Insights

```swift
// Analyze how dose timing affects WHOOP metrics
public struct DoseWHOOPCorrelation {
    let dose1TimeBucket: TimeBucket  // e.g., "Before 10pm", "10-11pm", etc.
    let avgRecoveryScore: Double
    let avgSleepPerformance: Double
    let avgDisturbances: Double
    let sampleCount: Int
}

// Generate insights
func generateInsights(correlations: [DoseWHOOPCorrelation]) -> [Insight] {
    // "Your recovery score is 12% higher when you take Dose 1 before 10:30 PM"
    // "Nights with Dose 2 in the 2:45-3:15 window have 23% fewer disturbances"
}
```

---

## 5. Implementation Priority

### Phase 1: Event Logging (2 weeks)

| Task | Effort | Files |
|------|--------|-------|
| Extend `EventRateLimiter` with new events | S | `ios/Core/EventRateLimiter.swift` |
| Create `SleepEvent` model | S | `ios/Core/SleepEvent.swift` (new) |
| Add event buttons to Tonight screen | M | `ios/DoseTapiOSApp/TonightView.swift` |
| Add watchOS quick actions | M | `watchos/DoseTapWatch/` |
| Store events in SQLite | M | `ios/DoseTap/Storage/EventStorage.swift` |
| Display events in Timeline | M | `ios/DoseTapiOSApp/TimelineView.swift` |
| Add tests | M | `Tests/DoseCoreTests/SleepEventTests.swift` |

### Phase 2: Apple Health Enhancement (2 weeks)

| Task | Effort | Files |
|------|--------|-------|
| Add HR/HRV data types to authorization | S | `HealthIntegrationService.swift` |
| Fetch heart rate samples during sleep | M | `HealthIntegrationService.swift` |
| Parse iOS 16+ sleep stages | M | `HealthIntegrationService.swift` |
| Create `SleepMetrics` unified model | M | `ios/Core/SleepMetrics.swift` (new) |
| Display HR chart in Dashboard | L | `DashboardView.swift` |
| Add HRV trend visualization | M | `DashboardView.swift` |

### Phase 3: Dashboard Upgrade (2 weeks)

| Task | Effort | Files |
|------|--------|-------|
| Redesign Dashboard layout | L | `DashboardView.swift` |
| Add "Tonight's Sleep" summary card | M | `DashboardView.swift` |
| Add heart rate chart component | M | `HeartRateChartView.swift` (new) |
| Add sleep stages bar chart | M | `SleepStagesView.swift` (new) |
| Add dose-sleep correlation insights | L | `InsightsEngine.swift` (new) |

### Phase 4: WHOOP Integration (3 weeks)

| Task | Effort | Files |
|------|--------|-------|
| Audit and fix `WHOOP.swift` | L | `ios/DoseTap/WHOOP.swift` |
| Add unit tests for WHOOP | L | `Tests/DoseCoreTests/WHOOPTests.swift` |
| Move to `DoseCore` module | M | `ios/Core/WHOOPClient.swift` (new) |
| Create WHOOP data models | M | `ios/Core/WHOOPModels.swift` (new) |
| Add WHOOP card to Dashboard | M | `DashboardView.swift` |
| Implement recovery score display | S | UI components |
| Add correlation analysis | L | `CorrelationEngine.swift` (new) |
| Rotate and secure API secrets | S | Documentation + Secrets.swift |

---

## 6. Technical Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                         │
├──────────────┬──────────────────┬───────────────────────────┤
│   DoseTap    │   Apple Health   │         WHOOP             │
│   (Local)    │   (HealthKit)    │       (REST API)          │
├──────────────┴──────────────────┴───────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              SleepDataAggregator                    │    │
│  │  - Merges data from all sources                     │    │
│  │  - Aligns timestamps                                │    │
│  │  - Resolves conflicts (prefer WHOOP for HR)         │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              UnifiedNightSession                    │    │
│  │  - doses: [DoseEvent]                               │    │
│  │  - events: [SleepEvent]                             │    │
│  │  - healthMetrics: HealthMetrics?                    │    │
│  │  - whoopMetrics: WHOOPMetrics?                      │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                 │
│              ┌────────────┴────────────┐                    │
│              ▼                         ▼                    │
│  ┌─────────────────────┐   ┌─────────────────────────┐      │
│  │   DashboardView     │   │   InsightsEngine        │      │
│  │   - Display cards   │   │   - Correlations        │      │
│  │   - Charts          │   │   - Recommendations     │      │
│  └─────────────────────┘   └─────────────────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### New Core Models

```swift
// ios/Core/UnifiedSleepSession.swift

public struct UnifiedSleepSession: Codable, Identifiable {
    public let id: UUID
    public let date: Date  // Night of (e.g., Dec 22 for 10pm-6am session)
    
    // DoseTap data
    public let dose1At: Date?
    public let dose2At: Date?
    public let events: [SleepEvent]
    
    // Apple Health data (optional)
    public let appleHealth: AppleHealthMetrics?
    
    // WHOOP data (optional)
    public let whoop: WHOOPMetrics?
    
    // Computed
    public var totalSleepDuration: TimeInterval? {
        // Prefer WHOOP > Apple Health > manual calculation
        whoop?.qualityDuration ?? appleHealth?.totalSleep ?? manualSleepDuration
    }
    
    private var manualSleepDuration: TimeInterval? {
        guard let lightsOut = events.first(where: { $0.type == .lightsOut })?.timestamp,
              let wake = events.first(where: { $0.type == .wakeFinal })?.timestamp else {
            return nil
        }
        return wake.timeIntervalSince(lightsOut)
    }
}

public struct AppleHealthMetrics: Codable {
    public let totalSleep: TimeInterval
    public let sleepStages: SleepStages?
    public let avgHeartRate: Double?
    public let minHeartRate: Double?
    public let restingHeartRate: Double?
    public let hrv: Double?  // SDNN
    public let respiratoryRate: Double?
    public let oxygenSaturation: Double?
}

public struct SleepStages: Codable {
    public let awake: TimeInterval
    public let rem: TimeInterval
    public let core: TimeInterval
    public let deep: TimeInterval
}

public struct WHOOPMetrics: Codable {
    public let recoveryScore: Double
    public let strain: Double
    public let sleepPerformance: Double
    public let sleepConsistency: Double
    public let disturbances: Int
    public let respiratoryRate: Double
    public let hrvRmssd: Double
    public let restingHeartRate: Double
    public let spo2: Double?
    public let skinTemp: Double?
}
```

### Privacy Considerations

1. **HealthKit data never leaves device** — process locally only
2. **WHOOP tokens stored in Keychain** (not UserDefaults)
3. **Export includes only aggregated metrics** — not raw sensor data
4. **Optional analytics** — never include health data

---

## Summary

| Feature | Priority | Effort | Dependencies |
|---------|----------|--------|--------------|
| Sleep Event Logging | P0 | 2 weeks | None |
| Apple Health Enhancement | P1 | 2 weeks | HealthKit entitlement |
| Dashboard Upgrade | P1 | 2 weeks | Event logging |
| WHOOP Integration | P2 | 3 weeks | WHOOP API secrets rotated |

**Total estimated effort: 9 weeks**

---

*Document Version: 1.0*  
*Last Updated: December 23, 2025*
