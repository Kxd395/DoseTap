# DoseTap Architecture

## High-Level Overview
DoseTap uses a **Clean Architecture** approach, leveraging Swift Package Manager (SwiftPM) to modularize core logic away from the UI. The app is **Local-First**, meaning all logic and state validity is determined on-device, with the backend serving as a synchronization point for analytics/backup.

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
    *   `PersistentStore.swift`: Core Data stack wrapper. Handles persistence of `DoseEvent` entities.
    *   `TonightView.swift`: The main dashboard view.
    *   `Config.plist`: Application configuration (Secrets, API URLs).

### 3. `DoseTapWatch` (The Companion)
*   **Responsibility**: specific watchOS views. Simplifies the UI to "Take", "Snooze", "Skip".

## Key Architectural Patterns

### Local-First Persistence
*   **Core Data**: Uses `NSPersistentContainer` with a fallback to `NSInMemoryStoreType` for crash resilience.
*   **Entities**:
    *   `DoseEvent`: The atomic unit of history (type: dose1/dose2, timestamp).
    *   `DoseSession`: Aggregates events into a "Night".

### Offline Sync
*   **Actor-based Queue**: `OfflineQueue` is an actor ensuring thread-safe operations.
*   **Strategy**: "Fire and Forget" from the UI perspective. The UI updates optimistically, while the queue handles the network synchronization in the background.

### Dependency Injection
*   Used heavily in `DoseCore` to allow unit testing of time-dependent logic.
*   `TimeProvider` protocol allows tests to inject "fake time" to simulate window expiration or DST jumps.

## Data Flow
1.  **User Action** (Tap "Take") -> **ViewModel**
2.  **ViewModel** -> **DoseCore** (Validate Window)
3.  **DoseCore** -> **Persistence** (Core Data Save)
4.  **DoseCore** -> **APIClient** (Network Request)
    *   *Success*: Done.
    *   *Failure*: **OfflineQueue** (Store Task) -> Retry Loop.
