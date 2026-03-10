import SwiftUI
import os.log

// MARK: - Date Provider
/// Protocol for injectable time source. Use `SystemDateProvider` in production,
/// inject a fixed/mock provider in tests.
protocol DateProviding: Sendable {
    func now() -> Date
}

/// Production date provider — returns the real system clock.
struct SystemDateProvider: DateProviding {
    func now() -> Date { Date() }
}

/// Fixed date provider for deterministic tests.
struct FixedDateProvider: DateProviding {
    let date: Date
    func now() -> Date { date }
}

// MARK: - App Container
/// Composition root for the app. Owns or references all key services.
///
/// **Migration plan** (incremental — do NOT rewrite everything at once):
/// 1. ✅ Created `AppContainer` with `DateProvider`.
/// 2. Pass `AppContainer` into `ContentView` via `.environmentObject()`.
/// 3. Replace `Date()` calls with `container.dateProvider.now()` one file at a time.
/// 4. Replace `.shared` singleton access with injected references one service at a time.
///
/// Each step compiles independently. Tests can inject `FixedDateProvider`.
@MainActor
final class AppContainer: ObservableObject {
    let dateProvider: DateProviding

    // Service references — currently forwarding to singletons.
    // Future: accept these via init parameters for testability.
    let sessionRepository: SessionRepository
    let settings: UserSettingsManager
    let healthKit: HealthKitService
    let alarmService: AlarmService

    init(
        dateProvider: DateProviding = SystemDateProvider(),
        sessionRepository: SessionRepository? = nil,
        settings: UserSettingsManager? = nil,
        healthKit: HealthKitService? = nil,
        alarmService: AlarmService? = nil
    ) {
        self.dateProvider = dateProvider
        self.sessionRepository = sessionRepository ?? .shared
        self.settings = settings ?? .shared
        self.healthKit = healthKit ?? .shared
        self.alarmService = alarmService ?? .shared
    }
}

// MARK: - Environment Key
private struct AppContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer? = nil
}

extension EnvironmentValues {
    var appContainer: AppContainer? {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}
