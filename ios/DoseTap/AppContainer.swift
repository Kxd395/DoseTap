import SwiftUI
import DoseCore
import os.log

private let appContainerLog = Logger(subsystem: "com.dosetap.app", category: "AppContainer")

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
    let core: DoseTapCore
    let eventLogger: EventLogger
    let undoState: UndoStateManager
    let sessionRepository: SessionRepository
    let settings: UserSettingsManager
    let healthKit: HealthKitService
    let alarmService: AlarmService
    let doseCoordinator: DoseActionCoordinator

    private var didConfigureDoseCommands = false

    init(
        dateProvider: DateProviding = SystemDateProvider(),
        core: DoseTapCore? = nil,
        eventLogger: EventLogger? = nil,
        undoState: UndoStateManager? = nil,
        sessionRepository: SessionRepository? = nil,
        settings: UserSettingsManager? = nil,
        healthKit: HealthKitService? = nil,
        alarmService: AlarmService? = nil
    ) {
        let resolvedCore = core ?? DoseTapCore()
        let resolvedEventLogger = eventLogger ?? .shared
        let resolvedUndoState = undoState ?? UndoStateManager()
        let resolvedSessionRepository = sessionRepository ?? .shared
        let resolvedAlarmService = alarmService ?? .shared

        self.dateProvider = dateProvider
        self.core = resolvedCore
        self.eventLogger = resolvedEventLogger
        self.undoState = resolvedUndoState
        self.sessionRepository = resolvedSessionRepository
        self.settings = settings ?? .shared
        self.healthKit = healthKit ?? .shared
        self.alarmService = resolvedAlarmService
        self.doseCoordinator = DoseActionCoordinator(
            core: resolvedCore,
            alarmService: resolvedAlarmService,
            eventLogger: resolvedEventLogger,
            undoState: resolvedUndoState,
            sessionRepo: resolvedSessionRepository
        )

        configureDoseCommandRoutes()
    }

    func configureDoseCommandRoutes(
        urlRouter: URLRouter? = nil,
        flicButtonService: FlicButtonService? = nil
    ) {
        guard !didConfigureDoseCommands else { return }

        let urlRouter = urlRouter ?? URLRouter.shared
        let flicButtonService = flicButtonService ?? FlicButtonService.shared

        core.setSessionRepository(sessionRepository)
        doseCoordinator.eventLogger = eventLogger
        doseCoordinator.undoState = undoState
        doseCoordinator.sessionRepo = sessionRepository
        urlRouter.configure(core: core, eventLogger: eventLogger, coordinator: doseCoordinator)
        flicButtonService.configure(coordinator: doseCoordinator, undoState: undoState)
        alarmService.configureNotificationSnoozeHandler { [weak doseCoordinator] in
            guard let doseCoordinator else { return false }
            if case .success = await doseCoordinator.snooze() {
                return true
            }
            return false
        }
        setupUndoCallbacks()
        didConfigureDoseCommands = true
    }

    private func setupUndoCallbacks() {
        undoState.onCommit = { action in
            appContainerLog.info("Action committed: \(String(describing: action), privacy: .private)")
        }

        undoState.onUndo = { [weak self] action in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch action {
                case .takeDose1(let time):
                    sessionRepository.clearDose1()
                    alarmService.cancelAllAlarms()
                    alarmService.clearDose2AlarmState()
                    appContainerLog.info("Undid Dose 1 taken at \(time, privacy: .private)")

                case .takeDose2(let time):
                    sessionRepository.clearDose2()
                    appContainerLog.info("Undid Dose 2 taken at \(time, privacy: .private)")

                case .skipDose(let seq, _):
                    sessionRepository.clearSkip()
                    appContainerLog.info("Undid skip of dose \(seq)")

                case .snooze(let mins):
                    let restoredAlarm = await alarmService.undoSnooze(minutes: mins, dose1Time: sessionRepository.dose1Time)
                    if restoredAlarm {
                        sessionRepository.decrementSnoozeCount()
                        appContainerLog.info("Undid snooze of \(mins) minutes")
                    } else {
                        appContainerLog.error("Failed to undo snooze of \(mins) minutes")
                    }

                case .deleteEvent(let snapshot):
                    eventLogger.restoreDeletedEvent(snapshot)
                    appContainerLog.info("Undid delete of event \(snapshot.displayName, privacy: .private)")
                }
            }
        }
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
