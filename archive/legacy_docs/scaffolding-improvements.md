# Scaffolding Improvements (iOS + watchOS, XYWAV-Only Scope)

All web, Next.js, microservice, and multi-med scaffolding removed. Focused modular Swift architecture supporting: accurate interval timing, reliable event persistence, adaptive evolution, accessibility, and minimal export/sync.

## 🎯 Design Principles

1. Local-first (operate offline flawlessly; sync opportunistically).
2. Deterministic timing (explicit UTC math; clamp invariants enforced).
3. Narrow data model (dose + adjunct events and derived aggregates only).
4. Transparency (planner rationale & debug info accessible in dev builds).
5. Accessibility by default (announcements, haptics, large targets baked in— not bolted on).
6. Testability (pure core modules; side effects isolated behind protocols).

## 📁 Recommended Top-Level Layout

```text
DoseTap/
├── DoseTap/                  # iOS target
│   ├── App/                  # App & Scene delegates / root composition
│   ├── UI/                   # SwiftUI feature folders
│   │   ├── Tonight/
│   │   ├── Timeline/
│   │   ├── Insights/
│   │   ├── Settings/
│   │   └── Components/       # Reusable small views
│   ├── Core/                 # Pure domain modules
│   │   ├── TimeEngine/
│   │   ├── EventStore/
│   │   ├── SnoozeController/
│   │   ├── UndoManager/
│   │   ├── BaselineModel/
│   │   ├── PlannerModule/
│   │   ├── AccessibilityLayer/
│   │   └── ExportFormatter/
│   ├── Services/             # Side-effect boundaries (HealthKit, Network)
│   │   ├── HealthKitClient/
│   │   ├── NetworkClient/
│   │   └── BatteryProfiler/
│   ├── Platform/             # App-wide helpers (Logging, DI, FeatureFlags)
│   ├── Resources/            # Assets, Localizable, Colors
│   └── Tests/
│       ├── Unit/
│       ├── Integration/
│       └── Harness/          # DST & simulation scripts
├── DoseTapWatch/             # watchOS target
│   ├── UI/
│   ├── Bridge/               # Shared model bridging & sync
│   └── Complications/
└── Shared/                   # Cross-target pure code (no UIKit/WatchKit)
    ├── Models/
    ├── Protocols/
    └── Utilities/
```swift

## 🧩 Core Module Contracts

| Module | Responsibilities | Exposed API (Sketch) | Notes |
|--------|------------------|----------------------|-------|
| TimeEngine | Clamp math, interval calc, DST safety | `computeDose2(target: Date, dose1: Date) -> IntervalResult` | Pure; no side effects |
| EventStore | Append+query events, offline queue | `append(_ e: Event)`, `pending()`, `flush()` | Idempotent keys |
| SnoozeController | Enforce Snooze policy | `attemptSnooze(now:) -> SnoozeResult` | Blocks <15m or beyond cap |
| UndoManager | 5s rollback window | `stage(event:)`, `undoLast()` | Cancellation tokens |
| BaselineModel | Median TTFW derivation | `target(for night:)` | Filters outliers |
| PlannerModule | Discrete interval selection | `nextInterval(context:)` | Thompson Sampling Beta params |
| AccessibilityLayer | Announcements & haptics | `scheduleAnnouncements(for:)` | Central timing source |
| ExportFormatter | Deterministic CSV output | `renderCSV(nights:)` | Stable column order |

## 🔌 Protocol-Oriented Boundaries

```swift
protocol Clock { func now() -> Date }
protocol Storage { func write(_ event: StoredEvent) throws; func fetch(range: DateInterval) -> [StoredEvent] }
protocol NetworkSync { func send(batch: [StoredEvent]) async throws }
protocol HealthSource { func recentSleepSamples(days: Int) async throws -> [SleepSample] }
```swift

These abstractions allow deterministic tests (inject FixedClock, InMemoryStorage, FailingNetwork, FixtureHealthSource).

## 🧪 Testing Strategy

| Layer | Approach | Example |
|-------|----------|---------|
| Pure Core | XCTest + property tests | Interval invariants under DST shifts |
| Integration | Harness sequences | Dose1→Snooze→Undo→Dose2 offline burst |
| Watch Bridge | Simulated connectivity toggles | Out-of-order flush ordering maintained |
| Accessibility | Scripted VoiceOver timestamps | ±2s tolerance enforcement |
| Export | Golden file hashing | Stable output across runs |

### DST & Travel Harness

Inputs: (dose1 UTC timestamp, timezone change events[], DST transitions[]). Produces expected dose2 absolute time & interval minutes. Stored fixture JSON drives automated assertions.

## 🧲 Data Model (Slim)

```swift
enum EventType: String { case dose1, dose2, snooze, bathroom, lights_out, wake_final }

struct Event: Identifiable {
  let id: UUID
  let type: EventType
  let at: Date          // UTC
  let localOffset: Int  // seconds from UTC at capture
  let meta: [String:String]? // optional (kept minimal)
  let pending: Bool     // true until outside undo window & flushed
}
```

No user PII fields; device identifier handled separately.

## ♻️ Undo Lifecycle

1. User action → stage Event (pending=true) + schedule flush after 5s.
2. If Undo invoked: remove from pending store; no network dispatch.
3. If flush triggers first: mark pending=false, enqueue network batch.
4. Network ack returns idempotent receipt hash → store for de-dupe.

## 🌐 Offline Queue

| State | Description |
|-------|-------------|
| staging | Within undo window |
| queued | Awaiting connectivity / backoff |
| flushing | In-flight dispatch |
| persisted | Acked (may still be local for 365d retention) |

Backoff: 1s → 2s → 5s → 10s (cap). Random jitter ±15%.

## 🧮 Planner Structure (Preview)

Intervals: {165,180,195,210,225}. Each holds Beta(α,β). Reward proxy: natural wake flag + (no skip) w/in clamp.

```swift
struct BanditInterval { let minutes: Int; var alpha: Double; var beta: Double }
func sample(_ b: BanditInterval) -> Double { Double.random(in: 0...1).pow(1.0 / (b.alpha)) /* simplified placeholder */ }
```

Rationale: “Selected 195m (recent natural wake cluster near 194m).”

## 🔔 Accessibility Scheduling

| Cue | Timing | Medium |
|-----|--------|--------|
| Pre-target | 5m before target | VoiceOver announcement + subtle haptic |
| Target | At target | VoiceOver + medium haptic |
| Window close | Clamp max reached | VoiceOver + strong haptic |

Central scheduler queries TimeEngine; watch and phone share same schedule to avoid drift.

## 🧷 Dependency Injection Pattern

Simple Environment struct passed through root view hierarchy (avoid global singletons):

```swift
struct AppEnvironment {
  let clock: Clock
  let storage: Storage
  let network: NetworkSync
  let health: HealthSource
  let logger: Logger
  let featureFlags: FeatureFlags
}
```

Preview providers inject MockEnvironment for SwiftUI previews.

## 📦 Build Config & Feature Flags

| Flag | Purpose | Default |
|------|---------|---------|
| ENABLE_PLANNER | Enable discrete interval sampling | off (user opt-in) |
| ENABLE_DEBUG_METRICS | Show internal metrics overlay | debug only |
| ENABLE_HIGH_CONTRAST_DEFAULT | Start in high contrast mode | off |

Implemented via Swift compiler condition + small FeatureFlags store persisted in UserDefaults.

## 🧹 Log & Storage Hygiene

| Data | Retention | Pruning |
|------|-----------|---------|
| Raw Events | 365 nights | Nightly sweep >365d |
| Planner State | Rolling | Re-init if corruption detected |
| Baseline Aggregates | Derived | Recomputed nightly |
| Metrics Snapshot | 30 nights | Sliding window |

## � Metrics Overlay (Debug)

Displays: queueDepth, lastFlushLatency, avgEventWriteMs, batteryDelta (if available), currentIntervalTarget, undoWindowRemaining.

## ♿ Accessibility Checklist Embed

| Item | Requirement |
|------|-------------|
| Contrast | ≥ 4.5:1 for body text |
| Hit Target | ≥ 48x48pt primary actions |
| VO Timing | Cues within ±2s of schedule |
| Focus Order | Logical linear progression |
| Dynamic Type | Respects user settings (no truncation) |

## 🛠 Tooling Scripts (Proposed)

| Script | Function |
|--------|----------|
| simulate_night.swift | Generate synthetic night (dose1, snoozes, dose2) |
| dst_harness.swift | Apply DST/timezone transitions to fixtures |
| export_diff.swift | Compare CSV outputs (hash + diff) |
| planner_sweep.swift | Run bandit simulation over synthetic reward curves |

## 🚫 Explicit Non-Goals

No: React/Next.js stack, Kubernetes manifests, microservices decomposition, payment gateways, caregiver sharing portal, push socket infrastructure.

## 📌 Implementation Sequence (Modules)

1. TimeEngine + EventStore (foundation)
2. SnoozeController + UndoManager integration
3. Offline queue + idempotent sync
4. BaselineModel w/ outlier filtering
5. AccessibilityLayer (announcements + high contrast) baseline
6. ExportFormatter deterministic tests
7. PlannerModule (opt-in) + rationale surface
8. Metrics overlay + battery profiler

## ✅ Definition of Done (Scaffolding Changes)

1. Module pure APIs documented & unit tested.
2. No global singletons except immutable config.
3. All side effects behind protocols with mock coverage.
4. Lint & markdown clean; no dangling web references.
5. Accessibility criteria validated for new UI wrappers.
6. Harness scripts updated if data model changes.

---
Last Updated: 2025-09-03
Owner: DoseTap Technical Team
    "dev": "next dev",
