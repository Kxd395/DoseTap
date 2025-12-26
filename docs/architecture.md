# DoseTap Architecture

> **Last Updated:** 2024-12-24
> **Persistence Layer:** SQLite (via `EventStorage.swift`)
> **SSOT Reference:** [DATABASE_SCHEMA.md](DATABASE_SCHEMA.md)

## High-Level Overview

DoseTap uses a **Clean Architecture** approach, leveraging Swift Package Manager (SwiftPM) to modularize core logic away from the UI. The app is **Local-First**, meaning all logic and state validity is determined on-device, with optional backend synchronization for analytics/backup.

## Module Structure (SwiftPM)

The project is divided into distinct targets within `Package.swift`:

### 1. `DoseCore` (The Brain)
*   **Responsibility**: Pure domain logic, state management, and networking. Independent of UIKit/SwiftUI.
*   **Key Components**:
    *   `DoseWindowState`: Value type representing the state of the dose window (e.g., `beforeWindow`, `active`, `closed`).
    *   `TimeEngine`: Protocol-based time source to allow deterministic testing (especially for DST transitions).
    *   `APIClient`: Networking layer. Responsible for communicating with the `doses/*` endpoints.
    *   `OfflineQueue`: Robust queueing system to handle offline actions. Stores failed requests and retries them with exponential backoff.
    *   `EventRateLimiter`: Prevents double-taps and spam actions.

### 2. `DoseTap` (The App)
*   **Responsibility**: The iOS Application target. Contains SwiftUI Views and ViewModels.
*   **Key Components**:
    *   `DoseTapApp.swift`: App entry point.
    *   `EventStorage.swift`: SQLite database wrapper. Single source of truth for all persistence.
    *   `SessionRepository.swift`: Observable state manager that bridges storage and UI.
    *   `TonightView.swift`: The main dashboard view.
    *   `Config.plist`: Application configuration (Secrets, API URLs).

### 3. `DoseTapWatch` (The Companion)
*   **Responsibility**: WatchOS-specific views. Simplifies the UI to "Take", "Snooze", "Skip".

## Persistence Layer: SQLite

> **CANONICAL**: SQLite is the ONLY persistence layer. There is NO Core Data.
> 
> **ENFORCED** (v2.12.0): Views MUST access storage via SessionRepository only.
> Direct EventStorage.shared access from Views is banned (CI guard enforced).
> SQLiteStorage is banned (`#if false` wrapper).

### Storage Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    UI Layer (SwiftUI)                       │
│   TonightView, HistoryView, MorningCheckInView, etc.        │
│                                                             │
│   ⛔ Views MUST NOT access EventStorage.shared directly     │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ @StateObject / SessionRepository.shared
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              SessionRepository (Facade)                      │
│   @Published dose1Time, dose2Time, snoozeCount, etc.        │
│   Broadcasts changes via Combine (sessionDidChange)          │
│                                                             │
│   ALL storage methods exposed here:                         │
│   - saveDose1/2(), insertSleepEvent(), fetchTonightEvents() │
│   - savePreSleepLog(), saveMorningCheckIn(), exportToCSV()  │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ internal only
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              EventStorage (SQLite Wrapper)                   │
│   @MainActor singleton, direct SQLite3 calls                 │
│   Database file: dosetap_events.sqlite                       │
│   Implements: EventStore protocol                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    SQLite Database                           │
│   Tables: current_session, dose_events, sleep_events,        │
│           morning_checkins, pre_sleep_logs, medication_events│
└─────────────────────────────────────────────────────────────┘

⛔ BANNED: SQLiteStorage (#if false wrapper)
```

### Key Files

| File | Purpose |
|------|---------|
| `ios/DoseTap/Storage/EventStorage.swift` | SQLite wrapper, all CRUD operations |
| `ios/DoseTap/Storage/SessionRepository.swift` | **Facade** — ALL view access goes here |
| `ios/Core/EventStore.swift` | Protocol defining storage interface |
| `docs/DATABASE_SCHEMA.md` | Canonical schema documentation |
| `docs/SSOT/contracts/SchemaEvolution.md` | Migration history |

### CI Enforcement

The storage boundary is enforced by CI (`.github/workflows/ci-swift.yml`):
- ❌ `EventStorage.shared` in Views → Build fails
- ❌ `SQLiteStorage` anywhere in production → Build fails

### Why SQLite (Not Core Data)

1. **Deterministic Testing**: Raw SQL is easier to test and mock
2. **Export-Friendly**: Direct CSV export without transformation
3. **Lightweight**: No Core Data stack overhead
4. **Debuggable**: Can inspect `.sqlite` file directly

## Offline Sync

*   **Actor-based Queue**: `OfflineQueue` is an actor ensuring thread-safe operations.
*   **Strategy**: "Fire and Forget" from the UI perspective. The UI updates optimistically, while the queue handles network synchronization in the background.

## Dependency Injection

*   Used heavily in `DoseCore` to allow unit testing of time-dependent logic.
*   `TimeProvider` protocol allows tests to inject "fake time" to simulate window expiration or DST jumps.

## Data Flow

```
1. User Action (Tap "Take") → ViewModel
2. ViewModel → SessionRepository.takeDose1()
3. SessionRepository → EventStorage.saveDose1()
4. EventStorage → SQLite INSERT
5. SessionRepository → sessionDidChange.send()
6. UI updates via @Published properties
7. (Background) APIClient → Network Request
   • Success: Done
   • Failure: OfflineQueue → Retry Loop
```

## iOS Target Structure

The repository contains multiple iOS-related folders. Here's what each is for:

| Folder | Status | Purpose |
|--------|--------|---------|
| `ios/Core/` | ✅ **Active** | SwiftPM `DoseCore` library - pure logic, fully tested |
| `ios/DoseTap/` | ✅ **Active** | Main iOS app target - production app |
| `ios/DoseTapiOSApp/` | 🔄 **Merging** | Alternative implementation - being consolidated into DoseTap |
| `ios/AppMinimal/` | 📦 **Archive** | Debug/test scaffold - can be deleted |
| `ios/DoseTapWorking/` | 📦 **Archive** | Prototype scratch space - can be deleted |
| `ios/DoseTapNative/` | 📦 **Archive** | Legacy native experiment - can be deleted |
| `ios/TempProject/` | 📦 **Archive** | Temporary files - can be deleted |

**To build the production app:** Open `ios/DoseTap.xcodeproj` in Xcode.

**To run SwiftPM tests:** `swift test` from the repository root (tests `DoseCore`). See CI for current test count.

**To run Xcode tests:** `xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 15'`

### Legacy Code Warning

Files in `ios/DoseTap/legacy/` are preserved for reference but are **not compiled**. The following files in `ios/DoseTap/` may conflict with `DoseCore` and are wrapped in `#if false`:
- `TimeEngine.swift` (use `ios/Core/` version)
- `EventStore.swift` (use `ios/Core/` version)  
- `UndoManager.swift` (use `ios/Core/DoseUndoManager.swift`)
- `DoseTapCore.swift` (deprecated)
- `EventStoreCoreData.swift` (deprecated - SQLite is canonical)

## References

- [DATABASE_SCHEMA.md](DATABASE_SCHEMA.md) - Complete SQLite schema
- [SSOT/contracts/SchemaEvolution.md](SSOT/contracts/SchemaEvolution.md) - Migration history
- [SSOT/constants.json](SSOT/constants.json) - Canonical enum definitions

