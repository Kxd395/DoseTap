# DoseTap Codebase Map

This document outlines the directory structure of the repository.

## Root Directory
*   `Package.swift`: The Swift Package Manager manifest. Defines the `DoseCore` library and test targets.
*   `archive/`: Contains deprecated documentation and status reports.
*   `docs/`: Active documentation (Specs, SSOT, Descriptions).
*   `tools/`: Helper scripts (if any).

## `ios/` Directory (Source Code)

*   **`Core/`** (Mapped to `DoseCore` target)
    *   Contains the business logic.
    *   `APIClient.swift`: Networking.
    *   `DoseWindowState.swift`: State machine logic.
    *   `OfflineQueue.swift`: Offline sync logic.
    *   `TimeEngine.swift`: Time manipulation protocols.
    *   `EventStore.swift`: Storage protocol interface.

*   **`DoseTap/`** (The iOS App)
    *   `DoseTapApp.swift`: Entry point.
    *   `Config.plist`: Configuration.
    *   **`Storage/`**: SQLite persistence.
        *   `SessionRepository.swift`: **Facade** — ALL view access goes here.
        *   `EventStorage.swift`: SQLite wrapper (internal to SessionRepository).
    *   **`Views/`**: SwiftUI views (`TonightView`, `SettingsView`).
    *   **`Resources/`**: Assets and localized strings.

## `Tests/` Directory
*   **`DoseCoreTests/`**: Unit tests for the Core logic.
    *   `DoseWindowStateTests.swift`: Critical safety window tests.
    *   `APIClientTests.swift`: Network layer tests.

## Key Files to Know
| File | Purpose |
|------|---------|
| `ios/Core/DoseWindowState.swift` | **CRITICAL**. Defines the 150-240m safety window logic. |
| `ios/DoseTap/Storage/SessionRepository.swift` | **Facade**. ALL view storage access goes here. |
| `ios/DoseTap/Storage/EventStorage.swift` | SQLite wrapper (internal — Views must not access directly). |
| `docs/SSOT/README.md` | The Single Source of Truth for feature requirements. |

## Storage Architecture (v2.12.0)

```
Views → SessionRepository → EventStorage → SQLite
          (facade)           (internal)

⛔ SQLiteStorage: BANNED (#if false wrapper)
⛔ EventStorage.shared in Views: BANNED (CI guard)
```

See `docs/STORAGE_ENFORCEMENT_REPORT_2025-12-26.md` for details.
