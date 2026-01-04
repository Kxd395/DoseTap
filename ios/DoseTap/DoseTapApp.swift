// DoseTapApp_Simple.swift
import SwiftUI
import DoseCore

@main
struct DoseTapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var urlRouter = URLRouter.shared
    
    /// Track when app went to background for duration logging
    @State private var backgroundedAt: Date?
    
    /// Track previous timezone for change detection
    @State private var lastKnownTimezone: TimeZone = TimeZone.current
    
    init() {
        #if DEBUG
        Swift.print("DoseTap app initialized (simplified)")
        #endif
        
        // Request notification permission for wake alarms
        Task { @MainActor in
            let granted = await AlarmService.shared.requestPermission()
            #if DEBUG
            Swift.print("🔔 Notification permission: \(granted ? "granted" : "denied")")
            #endif
        }
        
        // Log app launch
        Task {
            let sessionId = SessionRepository.shared.currentSessionDateString()
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
        
        // Register for timezone change notifications
        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [lastKnownTimezone] _ in
            let currentTz = TimeZone.current
            if currentTz.identifier != lastKnownTimezone.identifier {
                Self.logTimezoneChangeStatic(from: lastKnownTimezone, to: currentTz)
            }
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
            ContentView()
                .environmentObject(urlRouter)
                .onOpenURL { url in
                    // Handle deep links
                    let handled = urlRouter.handle(url)
                    #if DEBUG
                    Swift.print("🔗 URL handled: \(handled)")
                    #endif
                }
                .onChange(of: scenePhase) { newPhase in
                    handleScenePhaseChange(newPhase)
                }
        }
    }
    
    // MARK: - App Lifecycle Logging
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        let sessionId = SessionRepository.shared.currentSessionDateString()
        
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
            
            // Check for expired sessions when app becomes active
            Task { @MainActor in
                if SessionRepository.shared.checkAndHandleExpiredSession() {
                    #if DEBUG
                    Swift.print("😴 App: Auto-marked session as slept-through on foreground")
                    #endif
                }
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
        let sessionId = SessionRepository.shared.currentSessionDateString()
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
        Swift.print("⏰ Timezone changed: \(oldTz.identifier) → \(newTz.identifier)")
        #endif
    }
    
    private func handleSignificantTimeChange() {
        Self.handleSignificantTimeChangeStatic()
    }
    
    private static func handleSignificantTimeChangeStatic() {
        // This fires for midnight rollover, DST changes, and manual clock changes
        let sessionId = SessionRepository.shared.currentSessionDateString()
        Task {
            // We don't have the actual delta, but we log that it happened
            await DiagnosticLogger.shared.logTimeSignificantChange(sessionId: sessionId, timeDeltaSeconds: 0)
        }
        #if DEBUG
        Swift.print("⏰ Significant time change detected")
        #endif
        
        // Trigger session refresh
        SessionRepository.shared.refreshForTimeChange()
    }
}
