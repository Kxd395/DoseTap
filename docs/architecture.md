# DoseTap Architecture

Last updated: 2026-02-13

## Overview

DoseTap is a local-first iOS dose timer for XYWAV split-dose therapy. Domain logic lives in a platform-free SwiftPM library (`DoseCore`), while the SwiftUI app consumes it through a thin reactive layer.

---

## System Layer Cake

```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Views                        │
│  Tonight │ Details │ History │ Dashboard │ Settings      │
├─────────────────────────────────────────────────────────┤
│              Presentation / Coordination                │
│  DoseTapCore  │  EventLogger  │  UndoStateManager       │
├─────────────────────────────────────────────────────────┤
│                   Domain Services                       │
│  SessionRepository  │  UserSettingsManager               │
│  HealthKitService   │  AlarmService                      │
├─────────────────────────────────────────────────────────┤
│                  Storage (Single Writer)                 │
│  EventStorage  (+Schema +Session +Dose +CheckIn          │
│   +Exports +EventStore +Maintenance)                     │
├─────────────────────────────────────────────────────────┤
│               DoseCore (SwiftPM Library)                 │
│  DoseWindowState │ TimeEngine │ DosingModels │ SessionKey │
│  APIClient │ OfflineQueue │ EventRateLimiter             │
│  DiagnosticLogger │ SleepPlanCalculator                  │
├─────────────────────────────────────────────────────────┤
│                    Platform / OS                         │
│  SQLite  │  HealthKit  │  UserNotifications  │  Keychain │
└─────────────────────────────────────────────────────────┘
```

---

## Module Dependency Graph

```
                  ┌──────────────┐
                  │  DoseTap App │
                  └──────┬───────┘
                         │ depends on
            ┌────────────┼────────────┐
            │            │            │
            ▼            ▼            ▼
     ┌───────────┐ ┌──────────┐ ┌──────────────┐
     │  SwiftUI  │ │ DoseCore │ │  HealthKit   │
     │  (Apple)  │ │ (SwiftPM)│ │  (Apple)     │
     └───────────┘ └──────────┘ └──────────────┘
                         │
                         │ imports only
                         ▼
                   ┌───────────┐
                   │ Foundation │
                   └───────────┘
```

DoseCore has **zero** platform imports — no UIKit, SwiftUI, or HealthKit.

---

## Tab Architecture (App Shell)

```
┌───────────────────────────────────────────────────┐
│                  ContentView                       │
│  ┌─────────────────────────────────────────────┐  │
│  │        TabView (paged, swipeable)            │  │
│  │                                              │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐       │  │
│  │  │ Tonight │ │ Details │ │ History │       │  │
│  │  │   Tab   │ │   Tab   │ │   Tab   │       │  │
│  │  └─────────┘ └─────────┘ └─────────┘       │  │
│  │  ┌──────────┐ ┌──────────┐                  │  │
│  │  │Dashboard │ │ Settings │                  │  │
│  │  │   Tab    │ │   Tab    │                  │  │
│  │  └──────────┘ └──────────┘                  │  │
│  └─────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────┐  │
│  │            CustomTabBar (fixed)              │  │
│  │  Tonight │ Details │ History │ Dash │ Settings │
│  └─────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────┐  │
│  │         UndoOverlayView (snackbar)           │  │
│  └─────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────┘
```

---

## Tonight Tab — View Decomposition

```
LegacyTonightView
├── CompactStatusCard          ← timer, window phase, countdown
├── CompactDoseButton          ← Dose 1 / Dose 2 actions
├── SleepPlanCards             ← plan config, target interval
├── QuickEventViews            ← quick log button grid
│   └── EventLogger            ← dispatches to SessionRepository
├── SessionSummaryViews        ← post-session summary
└── TonightView                ← main tonight state coordinator
```

---

## Data Flow (Dose 1 → Storage → UI)

```
┌──────────────────┐
│ CompactDoseButton │  User taps "Take Dose 1"
└────────┬─────────┘
         │ calls
         ▼
┌──────────────────┐
│   DoseTapCore    │  .takeDose(earlyOverride:lateOverride:)
└────────┬─────────┘
         │ delegates to
         ▼
┌──────────────────┐
│SessionRepository │  .setDose1Time(_:)
│                  │   → validates state
│                  │   → writes to storage
└────────┬─────────┘
         │ calls         ┌───────────────────┐
         ├──────────────▶│  EventStorage     │
         │               │  +Dose.saveDose1()│
         │               └────────┬──────────┘
         │                        │ INSERT INTO dose_events
         │                        ▼
         │               ┌───────────────────┐
         │               │   SQLite DB       │
         │               └───────────────────┘
         │
         │ also calls
         ├──────────────▶ DiagnosticLogger.logDoseTaken(...)
         │
         │ publishes
         ▼
┌──────────────────┐
│sessionDidChange  │  Combine PassthroughSubject
│  .send()         │
└────────┬─────────┘
         │ observed by
         ▼
┌──────────────────┐
│  SwiftUI Views   │  @ObservedObject → UI redraws
└──────────────────┘
```

---

## Dose Window State Machine

```
                    ┌──────────┐
                    │ noDose1  │  (waiting for first dose)
                    └────┬─────┘
                         │ takeDose1
                         ▼
                    ┌───────────────┐
                    │  beforeWindow │  (0–150 min after D1)
                    └────┬──────────┘
                         │ 150 min elapsed
                         ▼
                    ┌───────────────┐
                    │    active     │  (150–225 min, D2 window open)
                    └────┬──────────┘
                         │ ≤ 15 min remain
                         ▼
                    ┌───────────────┐
                    │   nearClose   │  (225–240 min, closing soon)
                    └────┬──────────┘
                         │ 240 min elapsed
                         ▼
                    ┌───────────────┐
                    │    closed     │  (window expired)
                    └───────────────┘

  From active / nearClose / closed:
     takeDose2 ──────▶ ┌───────────┐
     skipDose2 ──────▶ │ completed │
                        └───────────┘

  From any state:
     wakeFinal ──────▶ ┌────────────┐  checkIn  ┌───────────┐
                        │ finalizing │ ────────▶ │ completed │
                        └────────────┘           └───────────┘
```

**Clinical invariant:** Dose 2 must be 150–240 min after Dose 1.
Default target: 165 min. Snooze: +10 min. Snooze disabled when < 15 min remain.

---

## Session Lifecycle

```
┌────────────────────────────────────┐
│          active                     │  (session open, end_utc = nil)
│  first event creates session        │
└──────┬────────────────┬────────────┘
       │                │
       │ wake_final     │ prep-time / cutoff
       ▼                ▼
┌──────────────┐  ┌───────────┐
│  finalizing  │  │  closed   │  (fallback auto-close)
│  (awaiting   │  └───────────┘
│   check-in)  │
└──────┬───────┘
       │ morning check-in
       ▼
┌───────────┐
│  closed   │  (session archived)
└───────────┘
```

Session identity: UUID. Grouping key: `session_date` (rollover hour 18:00).

---

## Storage Boundary (Single-Writer Architecture)

```
┌─────────────────────────────────────────┐
│              SwiftUI Views              │
│  (read via @Published, write via calls) │
└────────────────┬────────────────────────┘
                 │ ONLY path
                 ▼
┌─────────────────────────────────────────┐
│          SessionRepository              │
│  (observable façade, Combine publisher) │
└────────────────┬────────────────────────┘
                 │ ONLY path
                 ▼
┌─────────────────────────────────────────┐
│           EventStorage                  │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ │
│  │ +Schema  │ │ +Session │ │ +Dose   │ │
│  │ +Exports │ │ +CheckIn │ │ +Maint  │ │
│  │ +EventSt │ │          │ │         │ │
│  └──────────┘ └──────────┘ └─────────┘ │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│        SQLite (local file)              │
│  dosetap_events.sqlite                  │
│                                         │
│  Tables:                                │
│  ├── sleep_sessions                     │
│  ├── current_session                    │
│  ├── dose_events                        │
│  ├── sleep_events                       │
│  ├── morning_checkins                   │
│  ├── pre_sleep_logs                     │
│  └── medication_events                  │
└─────────────────────────────────────────┘
```

**Rule:** Views never touch `EventStorage` directly. All writes route through `SessionRepository`.

---

## Module Layout

| Module | Location | Files | Description |
| --- | --- | --- | --- |
| **DoseCore** | `ios/Core/` | 24 | Platform-free domain logic |
| **DoseCoreTests** | `Tests/DoseCoreTests/` | 29 | 497 unit tests |
| **DoseTap** (app) | `ios/DoseTap/` | 92 | SwiftUI app target |
| **DoseTapTests** | `ios/DoseTapTests/` | 11 | Xcode unit tests |
| **DoseTapUITests** | `ios/DoseTapUITests/` | 2 | 12 XCUITest smoke tests |

### Storage Layer (`ios/DoseTap/Storage/` — 13 files)

| File | Responsibility |
| --- | --- |
| `EventStorage.swift` (277 lines) | Core class, init, sleep events |
| `+Schema` | Table creation, migrations |
| `+Session` | Session lifecycle |
| `+Exports` | CSV export |
| `+EventStore` | Protocol conformance |
| `+Dose` | Dose CRUD, undo, time edit |
| `+CheckIn` | Morning check-in CRUD |
| `+Maintenance` | Deletes, CloudKit, utilities |
| `SessionRepository` | Observable façade |
| `StorageModels` | Shared model types |

Plus: `DosingAmountSchema`, `EncryptedEventStorage`, `JSONMigrator`

### Views Layer (`ios/DoseTap/Views/` — 25 files)

| File | Responsibility |
| --- | --- |
| `ContentView.swift` (228 lines) | Tab shell + CustomTabBar |
| `TonightView` | Tonight tab coordinator |
| `CompactDoseButton` | Dose take actions |
| `CompactStatusCard` | Timer / phase display |
| `SleepPlanCards` | Plan configuration |
| `SessionSummaryViews` | Post-session summary |
| `QuickEventViews` | Quick log grid |
| `DetailsView` | Detail breakdown |
| `EventLogger` | Event dispatch |

Plus: `Dashboard/` (2), `Timeline/` (1), `History/` (1)

---

## Test Pyramid

```
                    ╱╲
                   ╱  ╲
                  ╱ UI ╲         12 XCUITest smoke tests
                 ╱ Tests╲        (launch, nav, dose flow)
                ╱────────╲
               ╱  Xcode   ╲     ~134 integration tests
              ╱  Unit Tests ╲    (app-layer, storage)
             ╱───────────────╲
            ╱   SwiftPM Unit  ╲  497 domain-logic tests
           ╱    Tests (DoseCore)╲ (deterministic, time-injected)
          ╱──────────────────────╲
         ╱    Manual Regression   ╲  8-point checklist
        ╱     Checklist            ╲ (see TESTING_GUIDE.md)
       ╱────────────────────────────╲
```

**Total automated: 643+ tests. All passing. 0 failures.**

---

## CI / Branch Protection

```
Pull Request ──▶ ci.yml ──────▶ SSOT lint
                      ├────────▶ SwiftPM tests (3 TZs)
                      ├────────▶ Xcode sim build + tests
                      └────────▶ Release pin validation
               ──▶ ci-swift.yml ▶ Storage enforcement guards
               ──▶ ci-docs.yml ─▶ Documentation validation
                                         │
                                         ▼
                                   All 3 pass ──▶ Merge allowed
```

---

## HealthKit Integration

Read-only, gated by two independent states:
- **Preference:** `UserSettingsManager.healthKitEnabled` (user toggle)
- **Authorization:** `HealthKitService.isAuthorized` (OS grant)

The app reconciles these on launch and on settings view appearance.

---

## Diagnostics

```
Documents/diagnostics/sessions/<session-id>/
├── dose_events.jsonl
├── sleep_events.jsonl
├── state_transitions.jsonl
└── errors.jsonl
```

Uses `os.Logger` with `OSLogPrivacy` annotations. No `print()` in production code.

---

## Repository Structure (Post-Cleanup)

```
DoseTap/
├── Package.swift              SwiftPM manifest
├── ios/
│   ├── Core/                  DoseCore library (24 files)
│   ├── DoseTap/               Xcode app target (92 files)
│   │   ├── Storage/             EventStorage + extensions (13)
│   │   ├── Views/               SwiftUI views (25)
│   │   └── ...                  Services, models, settings
│   ├── DoseTap.xcodeproj/     Xcode project
│   ├── DoseTapTests/          Xcode unit tests (11)
│   └── DoseTapUITests/        XCUITest smoke tests (2)
├── Tests/
│   └── DoseCoreTests/         SwiftPM unit tests (29, 497 tests)
├── docs/
│   ├── SSOT/                  Single Source of Truth specs
│   ├── architecture.md        This file
│   ├── TESTING_GUIDE.md       Test inventory + commands
│   └── ...                    Diagnostics, schemas, guides
├── tools/                     CI scripts, linters
├── specs/                     Spec Kit feature specs
├── macos/                     DoseTapStudio (separate app)
├── watchos/                   Watch companion (assets)
└── .github/                   CI workflows, Copilot instructions
```

