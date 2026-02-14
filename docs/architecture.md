# DoseTap Architecture

Last updated: 2026-02-13

## Overview

DoseTap is a local-first iOS app built with SwiftUI and a SQLite persistence layer. Domain logic lives in `DoseCore` (SwiftPM), while UI and storage orchestration live in the Xcode app target.

## Module Layout

| Module | Location | Description |
|--------|----------|-------------|
| **DoseCore** (SwiftPM) | `ios/Core/` (24 files) | Platform-free domain logic: window math, time engine, dosing models, API client, offline queue, rate limiter, diagnostic logger |
| **DoseCoreTests** (SwiftPM) | `Tests/DoseCoreTests/` (29 files, 497 tests) | Unit tests for all core modules |
| **DoseTap** (Xcode app) | `ios/DoseTap/` (92 files) | SwiftUI views, SessionRepository, EventStorage, HealthKit, settings |
| **DoseTapTests** (Xcode) | `ios/DoseTapTests/` (11 files) | Xcode unit tests for app-layer logic |
| **DoseTapUITests** (Xcode) | `ios/DoseTapUITests/` (2 files, 12 tests) | XCUITest smoke tests for launch, navigation, dose flow |
| **DoseTapStaging** (Xcode) | `ios/DoseTap/` (shared sources) | Staging build variant |

## Key Subdirectory Structure

### Storage Layer (`ios/DoseTap/Storage/` — 13 files)

`EventStorage` was split from a single 1,948-line file into a focused core + 7 extension files:

| File | Responsibility |
|------|---------------|
| `EventStorage.swift` (277 lines) | Core class, properties, init, sleep events |
| `EventStorage+Schema.swift` | Table creation, migrations |
| `EventStorage+Session.swift` | Session lifecycle (open, close, query) |
| `EventStorage+Exports.swift` | CSV/data export methods |
| `EventStorage+EventStore.swift` | EventStore protocol conformance |
| `EventStorage+Dose.swift` | Dose CRUD: saveDose1, saveDose2, undo, time edit |
| `EventStorage+CheckIn.swift` | Morning check-in CRUD |
| `EventStorage+Maintenance.swift` | Deletes, CloudKit prep, utilities |

Plus: `DosingAmountSchema.swift`, `EncryptedEventStorage.swift`, `JSONMigrator.swift`, `SessionRepository.swift`, `StorageModels.swift`

### Views Layer (`ios/DoseTap/Views/` — 25 files)

`ContentView.swift` was split from a 2,850-line god file into a thin shell + 8 extracted domain files:

| File | Responsibility |
|------|---------------|
| `ContentView.swift` (228 lines) | Tab container shell + CustomTabBar |
| `TonightView.swift` | Main tonight tab with session state |
| `CompactDoseButton.swift` | Dose 1/2 take actions, overrides |
| `CompactStatusCard.swift` | Timer, window phase status display |
| `SleepPlanCards.swift` | Sleep plan configuration cards |
| `SessionSummaryViews.swift` | Post-session summary display |
| `QuickEventViews.swift` | Quick log button grid |
| `DetailsView.swift` | Detail/breakdown views |
| `EventLogger.swift` | Event logging coordinator |

Plus subdirectories: `Dashboard/` (2 files), `Timeline/` (1 file), `History/` (1 file)

## Storage Boundary (Single Writer)

UI must only talk to `SessionRepository`. `SessionRepository` is the only path to `EventStorage`.

```
SwiftUI Views
  -> SessionRepository (observable facade)
    -> EventStorage (SQLite wrapper, split across 8 files)
      -> SQLite database
```

Primary files:
- `ios/DoseTap/Storage/SessionRepository.swift`
- `ios/DoseTap/Storage/EventStorage.swift` + extensions
- `docs/DATABASE_SCHEMA.md`

## Session Model

- Session identity: UUID string (`session_id`).
- Grouping key: `session_date` (YYYY-MM-DD, rollover hour 18).
- Session closure: morning check-in, missed check-in cutoff, or prep-time soft rollover.

Key flow:
- `SessionRepository.ensureActiveSession(for:reason:)` creates or reuses the active session.
- `SessionRepository.completeCheckIn()` closes the session and clears in-memory state.
- `SessionRepository.evaluateSessionBoundaries(reason:)` handles fallback rollover.

## HealthKit Integration

HealthKit is read-only and gated by two states:
- Preference: `UserSettingsManager.healthKitEnabled`.
- Authorization: `HealthKitService.isAuthorized`.

The app must reconcile these on launch and on settings view appearance.

## Diagnostics

Diagnostic logs are written to `Documents/diagnostics/sessions/<session-id>/`.
See `docs/DIAGNOSTIC_LOGGING.md` and `docs/HOW_TO_READ_A_SESSION_TRACE.md`.

## CI / Branch Protection

Three CI workflows guard main:
- `ci.yml`: SSOT lint → SwiftPM tests (3 timezones) → Xcode sim tests → release pinning
- `ci-swift.yml`: Storage enforcement guards
- `ci-docs.yml`: Documentation validation

Branch protection requires PR + all 3 status checks to merge.

