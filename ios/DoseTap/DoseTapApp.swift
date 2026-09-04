// DoseTapApp_Simple.swift
import SwiftUI
import DoseCore
import os.log

private let appLifecycleLog = Logger(subsystem: "com.dosetap.app", category: "DoseTapApp")

private enum ReleaseArtifactSmokeMarker {
    static let launchArgument = "--release-artifact-smoke"
    static let fileName = "release-artifact-first-ui-v1.txt"

    static func recordIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument),
              let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
              ).first else {
            return
        }

        do {
            try Data("first-ui-v1\n".utf8).write(
                to: documentsURL.appendingPathComponent(fileName),
                options: .atomic
            )
        } catch {
            appLifecycleLog.error(
                "Release artifact smoke marker failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

@main
struct DoseTapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var urlRouter = URLRouter.shared
    @StateObject private var settings = UserSettingsManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var container = AppContainer()
    @AppStorage(SetupWizardService.setupCompletedKey) private var isSetupComplete: Bool = false
    
    /// Track when app went to background for duration logging
    @State private var backgroundedAt: Date?
    
    /// Track previous timezone for change detection
    @State private var lastKnownTimezone: TimeZone = TimeZone.current
    @State private var didRunPostSetupBootstrap = false
    
    init() {
        #if DEBUG
        appLifecycleLog.debug("App initialized (simplified)")
        #endif
        Self.migrateSetupStateIfNeeded()
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--uitesting-expired-session") {
            UserDefaults.standard.set(true, forKey: SetupWizardService.setupCompletedKey)
            SessionRepository.prepareExpiredSessionUITestFixture()
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-work-warning") {
            UserDefaults.standard.set(true, forKey: SetupWizardService.setupCompletedKey)
            UserSettingsManager.shared.targetIntervalMinutes = 165
            UserSettingsManager.shared.soundEnabled = false
            let repository = SessionRepository.shared
            repository.prepareWorkWarningUITestSession()
        }
        #endif


        // P3-7: Register background export task
        AutoExportService.shared.registerBackgroundTask()
        
        // Log app launch
        Task { @MainActor in
            let sessionId = SessionRepository.shared.currentSessionIdString()
            await DiagnosticLogger.shared.logAppLaunched(sessionId: sessionId)
        }
        
        // Sync diagnostic logging settings
        Task { @MainActor in
            let settings = UserSettingsManager.shared
            await DiagnosticLogger.shared.updateSettings(
                isEnabled: settings.diagnosticLoggingEnabled,
                tier2Enabled: settings.diagnosticTier2Enabled,
                tier3Enabled: settings.diagnosticTier3Enabled
            )
        }
        
        // Register for significant time change notifications
        NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.handleSignificantTimeChangeStatic()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if isSetupComplete {
                    ContentView()
                        .environmentObject(urlRouter)
                        .environmentObject(container)
                        .environmentObject(container.settings)
                        .environmentObject(container.sessionRepository)
                        .environmentObject(container.alarmService)
                        .environment(\.appContainer, container)
                        .onOpenURL { url in
                            // Handle deep links
                            let handled = urlRouter.handle(url)
                            #if DEBUG
                            appLifecycleLog.debug("URL handled: \(handled, privacy: .public)")
                            #endif
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                            let currentTz = TimeZone.current
                            if currentTz.identifier != lastKnownTimezone.identifier {
                                logTimezoneChange(from: lastKnownTimezone, to: currentTz)
                                lastKnownTimezone = currentTz
                                Task {
                                    await container.alarmService.reconcilePendingRequests(
                                        reason: .timeZoneChange,
                                        dose1Time: container.sessionRepository.dose1Time,
                                        forceReschedule: true
                                    )
                                }
                            }
                        }
                        .onChange(of: scenePhase) { newPhase in
                            handleScenePhaseChange(newPhase)
                        }
                        .task {
                            await runPostSetupBootstrapTasksIfNeeded()
                        }
                } else {
                    SetupWizardView(isSetupComplete: $isSetupComplete)
                        .preferredColorScheme(
                            themeManager.currentTheme == .night
                                ? .dark
                                : (themeManager.currentTheme.colorScheme ?? settings.colorScheme)
                        )
                        .accentColor(themeManager.currentTheme.accentColor)
                        .applyNightModeFilter(themeManager.currentTheme)
                }
            }
            .onAppear {
                ReleaseArtifactSmokeMarker.recordIfRequested()
            }
            .onChange(of: isSetupComplete) { completed in
                if completed {
                    Task {
                        await runPostSetupBootstrapTasksIfNeeded()
                    }
                }
            }
        }
    }
    
    // MARK: - App Lifecycle Logging
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        let sessionId = SessionRepository.shared.currentSessionIdString()
        
        switch newPhase {
        case .active:
            // Calculate background duration
            let backgroundDuration: Int?
            if let bg = backgroundedAt {
                backgroundDuration = Int(Date().timeIntervalSince(bg))
            } else {
                backgroundDuration = nil
            }
            backgroundedAt = nil
            
            // Log foregrounded
            Task {
                await DiagnosticLogger.shared.logAppForegrounded(
                    sessionId: sessionId,
                    backgroundDurationSeconds: backgroundDuration
                )
            }
            
            // If the wake alarm time passed while backgrounded, ring now
            AlarmService.shared.checkForDueAlarm()

            Task {
                await container.alarmService.reconcilePendingRequests(
                    reason: .appActive,
                    dose1Time: container.sessionRepository.dose1Time
                )
            }
            
            // Check for timezone changes while backgrounded
            let currentTz = TimeZone.current
            if currentTz.identifier != lastKnownTimezone.identifier {
                logTimezoneChange(from: lastKnownTimezone, to: currentTz)
                lastKnownTimezone = currentTz
            }
            
        case .background:
            backgroundedAt = Date()
            Task {
                await DiagnosticLogger.shared.logAppBackgrounded(sessionId: sessionId)
            }
            AlarmService.shared.stopRinging(acknowledge: false)

        case .inactive:
            // Transitional state, don't log
            break
            
        @unknown default:
            break
        }
    }
    
    private func handleTimezoneChange() {
        let currentTz = TimeZone.current
        if currentTz.identifier != lastKnownTimezone.identifier {
            logTimezoneChange(from: lastKnownTimezone, to: currentTz)
            lastKnownTimezone = currentTz
        }
    }

    private func logTimezoneChange(from oldTz: TimeZone, to newTz: TimeZone) {
        Self.logTimezoneChangeStatic(from: oldTz, to: newTz)
    }
    
    private static func logTimezoneChangeStatic(from oldTz: TimeZone, to newTz: TimeZone) {
        let sessionId = SessionRepository.shared.currentSessionIdString()
        Task {
            await DiagnosticLogger.shared.logTimezoneChanged(
                sessionId: sessionId,
                previousTimezone: oldTz.identifier,
                newTimezone: newTz.identifier,
                previousOffset: oldTz.secondsFromGMT() / 60,
                newOffset: newTz.secondsFromGMT() / 60
            )
        }
        #if DEBUG
        appLifecycleLog.debug("Timezone changed: \(oldTz.identifier, privacy: .private) -> \(newTz.identifier, privacy: .private)")
        #endif
    }
    
    private func handleSignificantTimeChange() {
        Self.handleSignificantTimeChangeStatic()
    }
    
    private static func handleSignificantTimeChangeStatic() {
        // This fires for midnight rollover, DST changes, and manual clock changes
        let sessionId = SessionRepository.shared.currentSessionIdString()
        Task {
            // We don't have the actual delta, but we log that it happened
            await DiagnosticLogger.shared.logTimeSignificantChange(sessionId: sessionId, timeDeltaSeconds: 0)
        }
        #if DEBUG
        appLifecycleLog.debug("Significant time change detected")
        #endif
        
        // Trigger session refresh
        SessionRepository.shared.refreshForTimeChange()
        Task { @MainActor in
            await AlarmService.shared.reconcilePendingRequests(
                reason: .significantTimeChange,
                dose1Time: SessionRepository.shared.dose1Time,
                forceReschedule: true
            )
        }
    }

    // MARK: - Setup / Install Quality

    private static func migrateSetupStateIfNeeded() {
        let defaults = UserDefaults.standard
        let setupKey = SetupWizardService.setupCompletedKey
        guard defaults.object(forKey: setupKey) == nil else { return }

        let hasLegacySetupData =
            defaults.data(forKey: "DoseTapUserConfig") != nil ||
            defaults.object(forKey: "target_interval_minutes") != nil ||
            defaults.object(forKey: "notifications_enabled") != nil ||
            defaults.object(forKey: "user_medications_json") != nil

        if hasLegacySetupData {
            defaults.set(true, forKey: setupKey)
        }
    }

    private func runPostSetupBootstrapTasksIfNeeded() async {
        guard isSetupComplete, !didRunPostSetupBootstrap else { return }
        didRunPostSetupBootstrap = true
        await requestNotificationPermissionIfNeeded()
        await container.alarmService.reconcilePendingRequests(
            reason: .appActive,
            dose1Time: container.sessionRepository.dose1Time
        )
    }

    private func requestNotificationPermissionIfNeeded() async {
        let defaults = UserDefaults.standard
        let requestedKey = "notification_permission_requested_once"
        guard !defaults.bool(forKey: requestedKey) else { return }
        guard UserSettingsManager.shared.notificationsEnabled else { return }

        let granted = await AlarmService.shared.requestPermission()
        defaults.set(true, forKey: requestedKey)

        if !granted {
            UserSettingsManager.shared.notificationsEnabled = false
        }

        #if DEBUG
        appLifecycleLog.debug("Post-setup notification permission: \(granted ? "granted" : "denied", privacy: .public)")
        #endif
    }
}
