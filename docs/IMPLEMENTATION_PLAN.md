# DoseTap Implementation Plan

> **Roadmap Features → Code**  
> Last Updated: January 7, 2025  
> Status: Phase 1 Complete, Phase 2 Planned (Not Started)

---

## 📊 Current State (123 Tests Passing)

### ✅ Phase 1 Complete - Sleep Event Logging

| Component | Location | Status | Tests |
|-----------|----------|--------|-------|
| Dose Window Logic | `ios/Core/DoseWindowState.swift` | ✅ Complete | 13 |
| API Client | `ios/Core/APIClient.swift` | ✅ Complete | 11 |
| Error Mapping | `ios/Core/APIErrors.swift` | ✅ Complete | 12 |
| Offline Queue | `ios/Core/OfflineQueue.swift` | ✅ Complete | 4 |
| Rate Limiter | `ios/Core/EventRateLimiter.swift` | ✅ Extended | all events |
| CRUD Actions | `ios/DoseTapiOSApp/` | ✅ Complete | 25 |
| **SleepEvent Model** | `ios/Core/SleepEvent.swift` | ✅ NEW | 29 |
| **SQLite sleep_events** | `ios/DoseTapiOSApp/SQLiteStorage.swift` | ✅ Updated | - |
| **QuickLogPanel UI** | `ios/DoseTapiOSApp/QuickLogPanel.swift` | ✅ NEW | - |
| **TimelineView** | `ios/DoseTapiOSApp/TimelineView.swift` | ✅ NEW | - |
| **UnifiedSleepSession** | `ios/Core/UnifiedSleepSession.swift` | ✅ NEW | - |
| **ContentView 12 buttons** | `ios/DoseTap/ContentView.swift` | ✅ Updated | - |
| WHOOP OAuth | `~/.dosetap_whoop_tokens.json` | ✅ Tested | - |

### 🎯 Phase 2 Next - Health Dashboard

| Task | Status | Priority |
|------|--------|----------|
| SleepDataAggregator | 📋 Planned | P0 |
| HeartRateChartView | 📋 Planned | P1 |
| WHOOPRecoveryCard | 📋 Planned | P1 |
| SleepStagesChart | � Planned | P2 |
| Correlation Insights | 📋 Planned | P2 |

---

## ✅ Phase 1 Implementation (COMPLETE)

### Files Created/Updated

```
ios/Core/
├── SleepEvent.swift           ✅ NEW (216 lines)
│   - 12 event types with cooldowns
│   - SleepEventCategory enum
│   - SleepEvent struct
├── UnifiedSleepSession.swift  ✅ NEW
│   - Merges DoseTap + HealthKit + WHOOP
│   - AppleHealthMetrics struct
│   - WHOOPMetrics struct
└── EventRateLimiter.swift     ✅ UPDATED
    - canLog(SleepEventType) method
    - remainingCooldown(for:) method
    - reset(for:) method

ios/DoseTapiOSApp/
├── SQLiteStorage.swift        ✅ UPDATED
│   - sleep_events table
│   - insertSleepEvent()
│   - fetchSleepEvents(for:)
│   - exportSleepEventsCSV()
├── QuickLogPanel.swift        ✅ NEW (350+ lines)
│   - 4x3 grid of event buttons
│   - Cooldown progress indicators
│   - Haptic feedback
├── TimelineView.swift         ✅ NEW (320+ lines)
│   - Historical session cards
│   - Expandable event details
│   - Date grouping
├── DoseCoreIntegration.swift  ✅ UPDATED
│   - logSleepEvent() method
│   - getTonightSleepEvents()
│   - getSleepEventSummary()
└── TonightView.swift          ✅ UPDATED
    - QuickLogSection added
    - QuickLogPanel integrated

ios/DoseTap/
└── ContentView.swift          ✅ UPDATED (443 lines)
    - 12 sleep event buttons
    - Cooldown UI with progress
    - Category-based colors

Tests/DoseCoreTests/
└── SleepEventTests.swift      ✅ NEW (29 tests)
    - All event type tests
    - Cooldown logic tests
    - Category tests
    - Encoding/decoding tests
```

### Test Summary: 123 Total

| Suite | Tests |
|-------|-------|
| SleepEventTests | 29 |
| CRUDActionTests | 25 |
| APIErrorsTests | 13 |
| APIClientTests | 11 |
| DoseWindowStateTests | 7 |
| DoseWindowEdgeTests | 6 |
| OfflineQueueTests | 4 |
| EventRateLimiterTests | 16 |
| DoseUndoManagerTests | 12 |

---

## � Phase 2 Implementation (PLANNED - Not Started)                       │
│  Step 1.5: Integrate into Tonight Screen                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ios/DoseTapiOSApp/TonightView.swift (UPDATE)        │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • Add QuickLogPanel below dose buttons              │    │
│  │ • Wire to DoseCoreIntegration.logSleepEvent()       │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│  Step 1.6: Tests                                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Tests/DoseCoreTests/SleepEventTests.swift (NEW)     │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • Test cooldown logic                               │    │
│  │ • Test event storage                                │    │
│  │ • Test all event types                              │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Phase 2: Health Dashboard (Week 2-3)

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: HEALTH DASHBOARD                                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Step 2.1: Unified Sleep Session Model                      │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ios/Core/UnifiedSleepSession.swift (NEW)            │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • Merges: DoseTap events + Apple Health + WHOOP     │    │
│  │ • struct AppleHealthMetrics                         │    │
│  │ • struct WHOOPMetrics                               │    │
│  │ • Computed: totalSleepDuration, sleepQuality        │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│  Step 2.2: Sleep Data Aggregator                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ios/DoseTapiOSApp/SleepDataAggregator.swift (NEW)   │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • Fetches from SQLite, HealthKit, WHOOP             │    │
│  │ • Aligns by session date                            │    │
│  │ • Returns UnifiedSleepSession                       │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│  Step 2.3: Dashboard View                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ios/DoseTapiOSApp/DashboardView.swift (NEW)         │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • TonightsSleepCard                                 │    │
│  │ • HeartRateCard (with chart)                        │    │
│  │ • WHOOPRecoveryCard                                 │    │
│  │ • DoseInsightsCard                                  │    │
│  │ • Tab bar: Tonight | Timeline | Dashboard | Settings│    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│  Step 2.4: Chart Components                                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ios/DoseTapiOSApp/Charts/                           │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • HeartRateChartView.swift - Line chart overnight   │    │
│  │ • SleepStagesChart.swift - Stacked bar chart        │    │
│  │ • RecoveryGauge.swift - WHOOP recovery ring         │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Phase 3: Timeline View (Week 3)

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 3: TIMELINE VIEW                                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Step 3.1: Timeline View                                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ios/DoseTapiOSApp/TimelineView.swift (NEW)          │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • List of sessions by date                          │    │
│  │ • Each session shows: Dose 1, events, Dose 2        │    │
│  │ • Expandable detail view                            │    │
│  │ • Filter: All / Doses / Events                      │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│  Step 3.2: Session Detail View                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ios/DoseTapiOSApp/SessionDetailView.swift (NEW)     │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • Visual timeline of night                          │    │
│  │ • Health metrics sidebar                            │    │
│  │ • Export single session                             │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Phase 4: WHOOP Integration (Week 4)

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 4: WHOOP INTEGRATION                                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Step 4.1: WHOOP Client (Core)                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ios/Core/WHOOPClient.swift (NEW)                    │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • Move OAuth logic from WHOOP.swift                 │    │
│  │ • Use v2 API endpoints (verified working)           │    │
│  │ • fetchSleep() -> WHOOPSleepData                    │    │
│  │ • fetchRecovery() -> WHOOPRecoveryData              │    │
│  │ • fetchCycles() -> WHOOPCycleData                   │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│  Step 4.2: WHOOP Models                                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ios/Core/WHOOPModels.swift (NEW)                    │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • struct WHOOPSleepData: Codable                    │    │
│  │ • struct WHOOPRecoveryData: Codable                 │    │
│  │ • struct WHOOPCycleData: Codable                    │    │
│  │ • Matches v2 API response shapes                    │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│  Step 4.3: Token Management                                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ios/DoseTapiOSApp/WHOOPTokenManager.swift (NEW)     │    │
│  │ ─────────────────────────────────────────────────── │    │
│  │ • Store tokens in Keychain (secure)                 │    │
│  │ • Auto-refresh before expiry                        │    │
│  │ • Handle re-auth flow                               │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 File Structure After Implementation

```
ios/
├── Core/                          # SwiftPM DoseCore module
│   ├── DoseWindowState.swift      ✅ Exists
│   ├── APIClient.swift            ✅ Exists
│   ├── APIErrors.swift            ✅ Exists
│   ├── OfflineQueue.swift         ✅ Exists
│   ├── EventRateLimiter.swift     🔄 Update (add cooldowns)
│   ├── SleepEvent.swift           🆕 NEW
│   ├── UnifiedSleepSession.swift  🆕 NEW
│   ├── WHOOPClient.swift          🆕 NEW
│   └── WHOOPModels.swift          🆕 NEW
│
├── DoseTapiOSApp/                  # iOS App
│   ├── SQLiteStorage.swift        ✅ Exists
│   ├── DoseCoreIntegration.swift  🔄 Update (add event logging)
│   ├── HealthKitManager.swift     ✅ Exists
│   ├── SleepDataAggregator.swift  🆕 NEW
│   ├── WHOOPTokenManager.swift    🆕 NEW
│   │
│   ├── Views/
│   │   ├── TonightView.swift      🔄 Update (add QuickLogPanel)
│   │   ├── QuickLogPanel.swift    🆕 NEW
│   │   ├── DashboardView.swift    🆕 NEW
│   │   ├── TimelineView.swift     🆕 NEW
│   │   ├── SessionDetailView.swift 🆕 NEW
│   │   └── MainTabView.swift      🆕 NEW (navigation)
│   │
│   └── Charts/
│       ├── HeartRateChartView.swift   🆕 NEW
│       ├── SleepStagesChart.swift     🆕 NEW
│       └── RecoveryGauge.swift        🆕 NEW
│
Tests/
└── DoseCoreTests/
    ├── SleepEventTests.swift      🆕 NEW
    ├── WHOOPClientTests.swift     🆕 NEW
    └── UnifiedSessionTests.swift  🆕 NEW
```

---

## 🔗 Dependency Graph

```
                    ┌─────────────────┐
                    │   SleepEvent    │
                    │   (Core Model)  │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
     ┌────────────┐  ┌──────────────┐  ┌──────────────┐
     │EventRate   │  │ SQLite       │  │QuickLogPanel │
     │Limiter     │  │ Storage      │  │ (UI)         │
     └────────────┘  └──────────────┘  └──────────────┘
              │              │              │
              └──────────────┼──────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │DoseCoreIntegr.  │
                    │ logSleepEvent() │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
     ┌────────────┐  ┌──────────────┐  ┌──────────────┐
     │HealthKit   │  │  WHOOP       │  │UnifiedSleep  │
     │Manager     │  │  Client      │  │Session       │
     └────────────┘  └──────────────┘  └──────────────┘
              │              │              │
              └──────────────┼──────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │SleepDataAggr.   │
                    │ (merges all)    │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
     ┌────────────┐  ┌──────────────┐  ┌──────────────┐
     │TonightView │  │DashboardView │  │TimelineView  │
     └────────────┘  └──────────────┘  └──────────────┘
```

---

## 🚀 Let's Start Building!

**Recommended order:**
1. ✅ SleepEvent model (Core) - foundation for everything
2. ✅ EventRateLimiter update - cooldowns for new events
3. ✅ SQLite storage update - persist events
4. ✅ QuickLogPanel UI - user interaction
5. ✅ Tests - validate it works
6. Then: Dashboard, Timeline, WHOOP integration

Ready to start with **Step 1.1: SleepEvent Model**?
