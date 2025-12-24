# DoseTap SSOT v2.0 — Single Source of Truth

> ⚠️ **DEPRECATED**: This document has been superseded by [`README.md`](./README.md) in this directory.
> Please refer to `docs/SSOT/README.md` as the canonical SSOT document.
> This file is retained for historical reference only.

---

> **Authoritative specification for DoseTap behavior, logic, and contracts**

**Last Updated:** 2025-12-23  
**Version:** 2.1.0  
**Status:** DEPRECATED - See README.md
**Supersedes:** All previous SSOT versions, `DoseTap_Spec.md`, `ui-ux-specifications.md`, `button-logic-mapping.md`

---

## Table of Contents

1. [Core Invariants](#1-core-invariants)
2. [Application Architecture](#2-application-architecture)
3. [State Machine](#3-state-machine)
4. [Button Logic Mapping](#4-button-logic-mapping)
5. [API Contract](#5-api-contract)
6. [Error Handling](#6-error-handling)
7. [Core Components](#7-core-components)
8. [Navigation Structure](#8-navigation-structure)
9. [Event Types](#9-event-types)
10. [Sleep Event Types](#10-sleep-event-types)
11. [Data Integration](#11-data-integration)
12. [Test Coverage](#12-test-coverage)

---

## 1. Core Invariants

### Medication Scope

| Constraint | Value | Rationale |
|------------|-------|-----------|
| Medication | XYWAV only | No multi-medication support |
| Doses per night | Exactly 2 | Dose 1 at bedtime, Dose 2 later |
| Minimum interval | **150 minutes** (2h 30m) | Safety: too early is unsafe |
| Maximum interval | **240 minutes** (4h 00m) | Efficacy: too late is ineffective |
| Default target | **165 minutes** (2h 45m) | Recommended timing |
| Snooze step | 10 minutes | Each snooze adds 10m |
| Max snoozes | 3 | After 3, snooze disabled |
| Near-close threshold | 15 minutes | Snooze disabled when <15m remain |
| Undo window | 5 seconds | Time to undo accidental tap |

### Safety Rules (Non-Negotiable)

```
1. Dose 2 MUST be ≥150 minutes after Dose 1
2. Dose 2 MUST be ≤240 minutes after Dose 1
3. Snooze DISABLED when remaining < 15 minutes
4. Snooze DISABLED after 3 snoozes used
5. All actions queue offline and sync when connected
6. All timestamps stored in UTC ISO8601
```

---

## 2. Application Architecture

### Module Structure

```
DoseTap/
├── ios/Core/                    # Platform-free logic (DoseCore module)
│   ├── DoseWindowState.swift    # Window calculator & state machine
│   ├── APIClient.swift          # HTTP client with typed responses
│   ├── APIErrors.swift          # Error types and mapping
│   ├── APIClientQueueIntegration.swift  # DosingService façade
│   ├── OfflineQueue.swift       # Offline-first queue
│   ├── EventRateLimiter.swift   # Debounce for rapid events
│   ├── SleepEvent.swift         # Sleep event types & models (NEW)
│   ├── UnifiedSleepSession.swift # Multi-source data model (NEW)
│   ├── RecommendationEngine.swift # Target time calculation
│   └── TimeEngine.swift         # Time utilities
│
├── ios/DoseTapiOSApp/           # SwiftUI iOS app
│   ├── DoseCoreIntegration.swift # Connects UI to DoseCore
│   ├── TonightView.swift        # Main dose tracking screen
│   ├── TimelineView.swift       # Session history view (NEW)
│   ├── DashboardView.swift      # Analytics & history
│   ├── QuickLogPanel.swift      # Event logging buttons (NEW)
│   ├── SettingsView.swift       # Configuration
│   ├── SQLiteStorage.swift      # Local persistence
│   ├── HealthKitManager.swift   # Apple Health integration (NEW)
│   └── MainTabView.swift        # Tab navigation
│
├── watchos/DoseTapWatch/        # watchOS companion
│
└── Tests/DoseCoreTests/         # Unit tests (95 passing)
    ├── DoseWindowStateTests.swift
    ├── DoseWindowEdgeTests.swift
    ├── APIClientTests.swift
    ├── APIErrorsTests.swift
    ├── OfflineQueueTests.swift
    ├── EventRateLimiterTests.swift
    ├── CRUDActionTests.swift
    └── SleepEventTests.swift    # 29 tests (NEW)
```

### Dependency Graph

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI App                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ TonightView │  │ DashboardView│  │    SettingsView    │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         │                │                     │             │
│         └────────────────┼─────────────────────┘             │
│                          ▼                                   │
│              ┌─────────────────────┐                         │
│              │ DoseCoreIntegration │                         │
│              │    (@MainActor)     │                         │
│              └──────────┬──────────┘                         │
├─────────────────────────┼───────────────────────────────────┤
│                         ▼                                   │
│                  ┌─────────────┐                             │
│                  │ DoseCore    │  (Platform-free module)     │
│  ┌───────────────┴─────────────┴───────────────┐            │
│  │                                             │            │
│  │  ┌──────────────┐    ┌─────────────────┐    │            │
│  │  │DosingService │◄───│DoseWindowCalc.  │    │            │
│  │  │   (Actor)    │    │ (Pure function) │    │            │
│  │  └──────┬───────┘    └─────────────────┘    │            │
│  │         │                                   │            │
│  │    ┌────┴────┬──────────────┐               │            │
│  │    ▼         ▼              ▼               │            │
│  │┌────────┐┌────────────┐┌──────────────┐     │            │
│  ││APIClient││OfflineQueue││EventRateLimiter│  │            │
│  │└────────┘└────────────┘└──────────────┘     │            │
│  │                                             │            │
│  └─────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. State Machine

### Window Phases

```swift
public enum DoseWindowPhase: Equatable {
    case noDose1      // No Dose 1 recorded tonight
    case beforeWindow // Dose 1 taken, waiting for 150m
    case active       // Window open (150-240m), >15m remain
    case nearClose    // Window open, <15m remain
    case closed       // Window expired (>240m)
    case completed    // Dose 2 taken or skipped
}
```

### State Transitions

```
                    ┌─────────────┐
                    │   noDose1   │  ← App launch / new night
                    └──────┬──────┘
                           │ takeDose1()
                           ▼
                    ┌─────────────┐
         ┌─────────│ beforeWindow │
         │         └──────┬──────┘
         │                │ elapsed ≥ 150m
         │                ▼
         │         ┌─────────────┐
         │    ┌────│   active    │◄───┐
         │    │    └──────┬──────┘    │ snooze()
         │    │           │           │ (if allowed)
         │    │           │ remaining < 15m
         │    │           ▼
         │    │    ┌─────────────┐
         │    └───►│  nearClose  │
         │         └──────┬──────┘
         │                │ elapsed ≥ 240m
         │                ▼
         │         ┌─────────────┐
skip()   │    ┌────│   closed    │
(any phase)│  │    └─────────────┘
         │    │
         │    │ skip() from any
         ▼    ▼
    ┌─────────────┐
    │  completed  │  ← takeDose2() OR skip()
    └─────────────┘
```

### Phase → UI State Mapping

| Phase | Primary CTA | Snooze | Skip | Color |
|-------|-------------|--------|------|-------|
| `noDose1` | "Take Dose 1" | Disabled | Disabled | Blue |
| `beforeWindow` | "Waiting: Xh Xm" | Disabled | Enabled | Orange |
| `active` | "Take Dose 2" | Enabled* | Enabled | Green |
| `nearClose` | "Take Now! Xm left" | Disabled | Enabled | Red/Orange |
| `closed` | "Window Closed" | Disabled | Enabled | Gray |
| `completed` | "Complete ✓" | Disabled | Disabled | Blue |

*Snooze enabled only if `snoozeCount < maxSnoozes` (default 3)

---

## 4. Button Logic Mapping

### Tonight Screen — Primary Actions

| Component ID | Phase Required | Preconditions | Action | API Call | Result |
|--------------|----------------|---------------|--------|----------|--------|
| `dose1_button` | `noDose1` | Not loading | `takeDose1()` | `POST /doses/take {type:"dose1"}` | → `beforeWindow` |
| `dose2_button` | `active` OR `nearClose` | In window | `takeDose2()` | `POST /doses/take {type:"dose2"}` | → `completed` |

### Tonight Screen — Secondary Actions

| Component ID | Phase Required | Preconditions | Action | API Call | Result |
|--------------|----------------|---------------|--------|----------|--------|
| `snooze_button` | `active` | remaining > 15m AND snoozeCount < 3 | `snooze()` | `POST /doses/snooze {minutes:10}` | +10m target, stay `active` |
| `skip_button` | `beforeWindow`, `active`, `nearClose`, `closed` | Dose 1 taken | `skipDose2()` | `POST /doses/skip {sequence:2}` | → `completed` |

### Tonight Screen — Event Logging

| Component ID | Preconditions | Action | API Call | Cooldown |
|--------------|---------------|--------|----------|----------|
| `bathroom_button` | Always | `logEvent(.bathroom)` | `POST /events/log {event:"bathroom"}` | 60s |
| `lights_out_button` | Always | `logEvent(.lightsOut)` | `POST /events/log {event:"lights_out"}` | 300s |
| `wake_final_button` | Always | `logEvent(.wakeFinal)` | `POST /events/log {event:"wake_final"}` | 600s |

### Undo Logic

```
On any dose action (takeDose1, takeDose2, skip):
  1. Show undo banner for 5 seconds
  2. If "UNDO" tapped within 5s:
     - Revert state to previous
     - Cancel pending API call (if still in queue)
     - Show "Action undone" toast
  3. After 5s: Action becomes permanent
```

### Deep Links

| URL Scheme | Action |
|------------|--------|
| `dosetap://dose1` | Navigate to Tonight, trigger Dose 1 |
| `dosetap://dose2` | Navigate to Tonight, trigger Dose 2 |
| `dosetap://snooze` | Trigger snooze if allowed |
| `dosetap://skip` | Trigger skip dialog |

---

## 5. API Contract

### Base Configuration

```
Base URL: https://api.dosetap.com/v1
Auth: Bearer <token> in Authorization header
Content-Type: application/json
Timestamps: ISO8601 UTC (e.g., "2025-12-23T10:30:00Z")
```

### Endpoints

#### POST /doses/take

```json
// Request
{
  "type": "dose1" | "dose2",
  "at": "2025-12-23T22:30:00Z"
}

// Response 200
{
  "event_id": "uuid",
  "type": "dose1",
  "at": "2025-12-23T22:30:00Z",
  "dose2_window": {
    "min": "2025-12-24T01:00:00Z",  // +150m
    "max": "2025-12-24T02:30:00Z"   // +240m
  }
}
```

#### POST /doses/snooze

```json
// Request
{
  "minutes": 10,
  "at": "2025-12-24T01:20:00Z"
}

// Response 200
{
  "event_id": "uuid",
  "minutes": 10,
  "new_target_at": "2025-12-24T01:30:00Z"
}

// Response 422 (snooze limit)
{
  "error_code": "SNOOZE_LIMIT",
  "message": "Maximum snoozes reached"
}
```

#### POST /doses/skip

```json
// Request
{
  "sequence": 2,
  "reason": "user_skip" | "felt_alert" | "side_effects" | null,
  "at": "2025-12-24T02:30:00Z"
}

// Response 200
{
  "event_id": "uuid",
  "reason": "user_skip"
}
```

#### POST /events/log

```json
// Request
{
  "event": "bathroom" | "lights_out" | "wake_final",
  "at": "2025-12-24T01:00:00Z"
}

// Response 200
{
  "event_id": "uuid",
  "event": "bathroom",
  "at": "2025-12-24T01:00:00Z"
}
```

#### GET /analytics/export

```
// Response 200: CSV data
// Content-Type: text/csv
```

---

## 6. Error Handling

### Error Codes → User Messages

| HTTP | error_code | APIError | User Message | UI Action |
|------|------------|----------|--------------|-----------|
| 422 | `WINDOW_EXCEEDED` | `.windowExceeded` | "Window exceeded. Take now or Skip." | Disable Dose 2, show Skip |
| 422 | `SNOOZE_LIMIT` | `.snoozeLimit` | "Snooze limit reached for tonight" | Disable Snooze button |
| 422 | `DOSE1_REQUIRED` | `.dose1Required` | "Log Dose 1 first" | Highlight Dose 1 button |
| 409 | - | `.alreadyTaken` | "Dose 2 already resolved" | Show completed state |
| 429 | - | `.rateLimit` | "Too many taps. Try again in a moment." | Disable all buttons 5s |
| 401 | - | `.deviceNotRegistered` | "Device not registered." | Prompt re-auth |
| - | - | `.offline` | "No internet connection." | Show offline badge |

### Error Recovery Flow

```
On API Error:
  1. Map response to APIError (via APIError.from())
  2. If retriable (5xx, timeout):
     - Enqueue action to OfflineQueue
     - Show "Saved offline" indicator
  3. If not retriable (4xx):
     - Show error toast with message
     - Log to analytics
  4. Always: Update UI to reflect error state
```

---

## 7. Core Components

### DoseWindowCalculator

**Location:** `ios/Core/DoseWindowState.swift`

```swift
public struct DoseWindowCalculator {
    public let config: DoseWindowConfig
    public let now: () -> Date  // Injectable for testing
    
    public func context(
        dose1At: Date?,
        dose2TakenAt: Date?,
        dose2Skipped: Bool,
        snoozeCount: Int
    ) -> DoseWindowContext
}
```

**Config Defaults:**
- `minIntervalMin`: 150
- `maxIntervalMin`: 240
- `nearWindowThresholdMin`: 15
- `defaultTargetMin`: 165
- `snoozeStepMin`: 10
- `maxSnoozes`: 3

### DosingService

**Location:** `ios/Core/APIClientQueueIntegration.swift`

```swift
public actor DosingService {
    public enum Action: Codable, Sendable, Equatable {
        case takeDose(type: String, at: Date)
        case skipDose(sequence: Int, reason: String?)
        case snooze(minutes: Int)
        case logEvent(name: String, at: Date)
    }
    
    // Attempts immediately; queues on failure
    public func perform(_ action: Action) async
    
    // Retries all queued actions
    public func flushPending() async
}
```

### EventRateLimiter

**Location:** `ios/Core/EventRateLimiter.swift`

```swift
public actor EventRateLimiter {
    // Check and register event (returns false if in cooldown)
    public func shouldAllow(event: String, at date: Date?) -> Bool
    
    // Check without registering (for UI state)
    public func canLog(event: String, at date: Date?) -> Bool
    
    // Get remaining cooldown seconds (0 if ready)
    public func remainingCooldown(for event: String, at date: Date?) -> TimeInterval
    
    // Reset cooldown for specific event or all
    public func reset(event: String)
    public func resetAll()
    
    // Default limiter with all sleep event cooldowns
    public static var `default`: EventRateLimiter {
        EventRateLimiter(cooldowns: SleepEventType.allCooldowns)
    }
}
```

**Default Cooldowns (from SleepEventType.allCooldowns):**
- bathroom: 60s, water: 300s, snack: 900s
- lightsOut: 3600s, wakeFinal: 3600s, wakeTemp: 300s
- anxiety: 300s, dream: 60s, heartRacing: 300s
- noise: 60s, temperature: 300s, pain: 300s

### OfflineQueue

**Location:** `ios/Core/OfflineQueue.swift`

```swift
public protocol OfflineQueue: AnyObject, Sendable {
    func enqueue(_ task: AnyOfflineQueueTask) async
    func flush() async
    func pending() async -> [AnyOfflineQueueTask]
}

public actor InMemoryOfflineQueue: OfflineQueue {
    // Config: maxRetries=3, backoffBaseSeconds=2
}
```

### RecommendationEngine

**Location:** `ios/Core/RecommendationEngine.swift`

```swift
public struct RecommendationEngine {
    /// Returns recommended minutes after Dose 1 for Dose 2
    /// Constrained to 150-240, baseline clamp 165-210
    public static func recommendOffsetMinutes(
        history: [NightSummary],
        liveSignals: (isLightOrAwakeNow: Bool, minutesSinceDose1: Int)?
    ) -> Int
}
```

---

## 8. Navigation Structure

### iOS Tab Bar

```
┌─────────────────────────────────────┐
│                                     │
│          [Current Screen]           │
│                                     │
├─────────────────────────────────────┤
│   🌙       �        📊        ⚙️   │
│ Tonight  Timeline  Dashboard  Settings│
└─────────────────────────────────────┘
```

| Tab | View | Purpose |
|-----|------|---------|
| Tonight | `TonightView` | Primary dose tracking |
| Timeline | `TimelineView` | Session history & events (NEW) |
| Dashboard | `DashboardView` | Charts, metrics, export |
| Settings | `SettingsView` | Configuration, permissions |

### Screen Flow

```
App Launch
    │
    ▼
┌─────────────────┐
│ Setup Complete? │
└────────┬────────┘
         │
    ┌────┴────┐
    │ No      │ Yes
    ▼         ▼
┌─────────┐  ┌─────────────┐
│ Setup   │  │ MainTabView │
│ Wizard  │  └──────┬──────┘
└────┬────┘         │
     │              ├── Tonight (default)
     │              ├── Dashboard
     └─────────────►└── Settings
                          │
                          └── Reconfigure Setup
```

---

## 9. Event Types

### DoseEventType Enum

**Location:** `ios/DoseTapiOSApp/DoseCoreIntegration.swift`

```swift
public enum DoseEventType: String, CaseIterable {
    case dose1 = "dose1"
    case dose2 = "dose2"
    case snooze = "snooze"
    case skip = "skip"
    case bathroom = "bathroom"
    case lightsOut = "lights_out"
    case wakeFinal = "wake_final"
}
```

### Event Icons & Colors

| Event | Icon | SF Symbol | Color |
|-------|------|-----------|-------|
| `dose1` | 💊 | `pills.fill` | Blue |
| `dose2` | 💊 | `pills.fill` | Blue |
| `snooze` | ⏰ | `clock.fill` | Orange |
| `skip` | ❌ | `xmark.circle.fill` | Red |
| `bathroom` | 🚶 | `figure.walk` | Purple |
| `lightsOut` | 💡 | `lightbulb.slash.fill` | Indigo |
| `wakeFinal` | ☀️ | `sun.max.fill` | Yellow |

---

## 10. Sleep Event Types

**Location:** `ios/Core/SleepEvent.swift`

### SleepEventType Enum

```swift
public enum SleepEventType: String, Codable, Sendable, CaseIterable {
    case bathroom       // Bathroom visit during sleep
    case inBed          // Got into bed (may not be sleeping yet)
    case lightsOut      // User turned off lights / going to sleep
    case wakeFinal      // Final wake (morning)
    case wakeTemp       // Temporary wake (not final)
    case snack          // Late snack before bed
    case water          // Drank water
    case anxiety        // Anxiety/restlessness
    case dream          // Notable dream (for patterns)
    case noise          // External noise disturbance
    case temperature    // Temperature discomfort
    case pain           // Pain/discomfort
    case heartRacing    // Heart racing sensation
}
```

### Event Categories

| Category | Events | Purpose |
|----------|--------|---------|
| **Physical** | bathroom, water, snack | Body-related events |
| **Sleep Cycle** | inBed, lightsOut, wakeFinal, wakeTemp | Sleep state transitions |
| **Mental** | anxiety, dream, heartRacing | Mental/emotional events |
| **Environment** | noise, temperature, pain | External disturbances |

### Event Cooldowns

| Event | Cooldown | Rationale |
|-------|----------|-----------|
| `bathroom` | 60s | Multiple trips common |
| `inBed` | 3600s | Once per night |
| `lightsOut` | 3600s | Once per night |
| `wakeFinal` | 3600s | Once per night |
| `wakeTemp` | 300s | Multiple brief wakes |
| `snack` | 900s | 15 min reasonable spacing |
| `water` | 300s | Multiple drinks |
| `anxiety` | 300s | Track multiple episodes |
| `dream` | 60s | Log when remembered |
| `noise` | 60s | Multiple disturbances |
| `temperature` | 300s | Track changes |
| `pain` | 300s | Track episodes |
| `heartRacing` | 300s | Track episodes |

### QuickLog Panel Events

The QuickLogPanel shows 8 most common events in a 4x2 grid:

```
┌──────────┬──────────┬──────────┬──────────┐
│ Bathroom │  Water   │ Lights   │  Wake Up │
│    🚽    │    💧    │  Out 💡  │    ☀️    │
├──────────┼──────────┼──────────┼──────────┤
│  Brief   │ Anxiety  │   Pain   │  Noise   │
│  Wake 🌙 │   🧠     │    🩹    │    🔊    │
└──────────┴──────────┴──────────┴──────────┘
```

---

## 11. Data Integration

### UnifiedSleepSession

**Location:** `ios/Core/UnifiedSleepSession.swift`

Combines data from three sources into a unified model:

```swift
public struct UnifiedSleepSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    
    // DoseTap core data
    public let doseData: DoseSessionData
    
    // Apple Health data (optional)
    public let healthData: HealthSleepData?
    
    // WHOOP data (optional)
    public let whoopData: WhoopSleepData?
    
    // Computed unified metrics
    public var sleepQualityScore: Int?
    public var totalSleepDuration: TimeInterval?
    public var awakenings: Int
}
```

### Data Sources

| Source | Data Types | Integration Status |
|--------|------------|-------------------|
| **DoseTap** | Dose times, sleep events, compliance | ✅ Complete |
| **Apple Health** | HR, HRV, sleep stages, respiratory | ✅ HealthKitManager ready |
| **WHOOP** | Recovery, strain, sleep performance | ✅ API connected |

### HealthSleepData Fields

```swift
public struct HealthSleepData: Codable, Sendable {
    public let totalSleepDuration: TimeInterval?
    public let sleepStages: SleepStages?       // awake, rem, core, deep
    public let averageHeartRate: Double?        // bpm
    public let minimumHeartRate: Double?        // bpm
    public let averageHRV: Double?              // ms
    public let respiratoryRate: Double?         // breaths/min
    public let oxygenSaturation: Double?        // %
    public let awakenings: Int
    public let sleepLatency: TimeInterval?      // time to fall asleep
}
```

### WhoopSleepData Fields

```swift
public struct WhoopSleepData: Codable, Sendable {
    public let recoveryScore: Int?              // 0-100
    public let strain: Double?                  // 0-21
    public let sleepPerformance: Int?           // 0-100
    public let sleepEfficiency: Double?         // %
    public let totalSleepSeconds: Int?
    public let sleepNeed: Int?                  // seconds
    public let sleepDebt: Int?                  // seconds (negative = surplus)
    public let restingHeartRate: Double?        // bpm
    public let hrv: Double?                     // ms
    public let skinTempDeviation: Double?       // °C from baseline
    public let spo2: Double?                    // %
    public let respiratoryRate: Double?         // breaths/min
}
```

---

## 12. Test Coverage

### Current State: 95 Tests Passing

| Test Suite | Tests | Coverage |
|------------|-------|----------|
| `SleepEventTests` | 29 | Event types, cooldowns, categories, codable (NEW) |
| `CRUDActionTests` | 25 | CREATE/READ/UPDATE/DELETE, API actions (NEW) |
| `APIErrorsTests` | 12 | Error code mapping, HTTP status handling |
| `APIClientTests` | 11 | Request formation, error mapping |
| `DoseWindowStateTests` | 7 | Phase transitions, context calculation |
| `DoseWindowEdgeTests` | 6 | DST, edge cases, boundary conditions |
| `OfflineQueueTests` | 4 | Retry, backoff, max attempts |
| `EventRateLimiterTests` | 1 | Cooldown logic, debouncing |

### Key Tested Behaviors

```
✓ Window opens at exactly 150 minutes
✓ Window closes at exactly 240 minutes
✓ Snooze disabled when <15 minutes remain
✓ Snooze disabled after 3 snoozes
✓ Error 422 WINDOW_EXCEEDED → .windowExceeded
✓ Error 422 SNOOZE_LIMIT → .snoozeLimit
✓ Error 422 DOSE1_REQUIRED → .dose1Required
✓ Error 409 → .alreadyTaken
✓ Error 429 → .rateLimit
✓ Offline queue retries up to 3 times
✓ Rate limiter blocks bathroom within 60s
✓ All 12 sleep event types have icons/names/cooldowns
✓ Sleep event categories contain correct events
✓ Sleep events encode/decode correctly (Codable)
✓ Event summary calculates bathroom/wake counts
```

---

## Appendix A: Quick Reference

### Timing Cheat Sheet

| Event | Minutes | Time |
|-------|---------|------|
| Window opens | 150 | 2h 30m |
| Default target | 165 | 2h 45m |
| Window closes | 240 | 4h 00m |
| Near-close threshold | 15 | 0h 15m |
| Snooze step | 10 | 0h 10m |

### File Quick Reference

| Need | File |
|------|------|
| Window logic | `ios/Core/DoseWindowState.swift` |
| Sleep events | `ios/Core/SleepEvent.swift` |
| Unified sessions | `ios/Core/UnifiedSleepSession.swift` |
| API calls | `ios/Core/APIClient.swift` |
| Error mapping | `ios/Core/APIErrors.swift` |
| Offline queue | `ios/Core/OfflineQueue.swift` |
| Rate limiting | `ios/Core/EventRateLimiter.swift` |
| UI → Core bridge | `ios/DoseTapiOSApp/DoseCoreIntegration.swift` |
| Tonight screen | `ios/DoseTapiOSApp/TonightView.swift` |
| Timeline screen | `ios/DoseTapiOSApp/TimelineView.swift` |
| QuickLog panel | `ios/DoseTapiOSApp/QuickLogPanel.swift` |
| SQLite storage | `ios/DoseTapiOSApp/SQLiteStorage.swift` |
| HealthKit | `ios/DoseTapiOSApp/HealthKitManager.swift` |
| Tests | `Tests/DoseCoreTests/*.swift` |

---

*This document is the authoritative source for DoseTap behavior.*  
*All implementation must match this specification.*  
*Update SSOT first, then code.*
