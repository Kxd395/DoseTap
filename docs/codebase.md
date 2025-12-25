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

*   **`DoseTap/`** (The iOS App)
    *   `DoseTapApp.swift`: Entry point.
    *   `Config.plist`: Configuration.
    *   **`Storage/`**: SQLite persistence (`EventStorage.swift`, `SessionRepository.swift`).
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
| `ios/DoseTap/Storage/EventStorage.swift` | SQLite persistence. Single source of truth for all data. |
| `docs/SSOT/README.md` | The Single Source of Truth for feature requirements. |
