# 00 — System Overview

## Core Invariant

> **Dose 2 must be taken 150–240 minutes after Dose 1.**
> Default target: 165m · Snooze adds 10m · Snooze disabled when <15m remain

## System Layer Cake

```
┌──────────────────────────────────────────────────────┐
│                    SwiftUI Views                      │
│  TonightView · DetailsView · HistoryView ·           │
│  DashboardViews · SettingsView · NightReviewView     │
├──────────────────────────────────────────────────────┤
│              View Models / Coordinators               │
│  DoseTapCore · DoseActionCoordinator ·               │
│  UndoStateManager · EventLogger                      │
├──────────────────────────────────────────────────────┤
│                 Service Layer                         │
│  AlarmService · HealthKitService · WHOOPService ·    │
│  FlicButtonService · URLRouter · AnalyticsService    │
├──────────────────────────────────────────────────────┤
│               Repository Layer                        │
│  SessionRepository (SSOT for session state)          │
│  SleepPlanStore · InsightsCalculator                 │
├──────────────────────────────────────────────────────┤
│                Storage Layer                          │
│  EventStorage (SQLite, WAL mode)                     │
│  EventStorage+Schema · +Dose · +Session ·            │
│  +CheckIn · +EventStore · +Exports · +Maintenance    │
├──────────────────────────────────────────────────────┤
│            DoseCore (platform-free SwiftPM)           │
│  DoseWindowState · DosingModels · APIClient ·        │
│  APIErrors · OfflineQueue · EventRateLimiter ·       │
│  NightScoreCalculator · CertificatePinning ·         │
│  DataRedactor · DiagnosticLogger                     │
└──────────────────────────────────────────────────────┘
```

## Module Dependency Graph

```
DoseCore  (SwiftPM target, 25 files)
   │
   │  import DoseCore
   ▼
DoseTap App  (~130 files, Xcode project)
   ├── Views/           (UI layer)
   ├── Storage/         (SQLite persistence)
   ├── Services/        (integrations)
   ├── Security/        (validation, DB security)
   ├── Theme/           (appearance)
   └── Foundation/      (helpers)
   │
   │  import DoseCore
   ▼
DoseCoreTests  (31 test files, 559 tests)
```

## Tech Stack

| Layer | Technology |
| ----- | ---------- |
| UI | SwiftUI + UIKit (screenshots, haptics) |
| State | @Published + Combine + @StateObject |
| Persistence | SQLite3 (direct C API, WAL mode) |
| Networking | URLSession + APIClient (async/await) |
| Security | CryptoKit (cert pinning), SQLCipher-compatible |
| Health | HealthKit (sleep analysis) |
| Logging | os.Logger with OSLogPrivacy |
| Testing | XCTest (unit + UI) |
| Min Target | iOS 16.0 |
| Build | SwiftPM (core) + Xcode 15 (app) |

## Key Counts

| Metric | Count |
| ------ | ----- |
| Swift files | ~155 |
| Lines of code | ~52,000 |
| DoseCore files | 25 |
| App files | ~130 |
| SwiftPM tests | 559 |
| Xcode unit tests | 134 |
| XCUITest tests | 12 |
| **Total tests** | **705** |
| SQLite tables | 12 |
| API endpoints | 5 |
| Deep link routes | 10 |
| Notification types | 8 |

## App Entry Point

```
DoseTapApp (@main)
  ├── SetupWizardView  (first-launch onboarding)
  └── ContentView      (main TabView with 5 tabs)
       ├── AppContainer (composition root / DI)
       ├── URLRouter    (deep link handling)
       └── ThemeManager (appearance)
```

File: `ios/DoseTap/DoseTapApp.swift` (252 lines)
- `@main struct DoseTapApp: App`
- Handles: scene phase, timezone changes, setup migration, diagnostic logging init
- Delegates deep links to `URLRouter.handle(_:)`

File: `ios/DoseTap/AppContainer.swift` (78 lines)
- `AppContainer: ObservableObject` — composition root
- Injects: `DateProviding`, `SessionRepository`, `UserSettingsManager`, `HealthKitService`, `AlarmService`
- Tests inject `FixedDateProvider` for determinism
