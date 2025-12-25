// DoseTapApp_Simple.swift
import SwiftUI

@main
struct DoseTapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        print("DoseTap app initialized (simplified)")
        
        // Request notification permission for wake alarms
        Task { @MainActor in
            let granted = await AlarmService.shared.requestPermission()
            print("🔔 Notification permission: \(granted ? "granted" : "denied")")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // Check for expired sessions when app becomes active
                        // This handles the case where user slept through the dose window
                        Task { @MainActor in
                            if SessionRepository.shared.checkAndHandleExpiredSession() {
                                print("😴 App: Auto-marked session as slept-through on foreground")
                            }
                        }
                    }
                }
        }
    }
}
