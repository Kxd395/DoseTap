import Foundation
import os.log
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

private let settingsActionsLog = Logger(subsystem: "com.dosetap.app", category: "SettingsView")

enum DataResetPresentation {
    static let warningKey = "data_reset_cleanup_warning"
    static let cleanupWarning = "Local records and settings were cleared, but alarm cleanup could not be verified. Check iOS alarms and notifications before relying on them."

    @MainActor
    static func finishCleanup(repository: SessionRepository, generation: UInt,
                              verifyAlarms: () async -> Bool, defaults: UserDefaults) async {
        guard repository.dataResetGeneration == generation,
              repository.activeSessionId == nil else { return }
        let verified = await verifyAlarms()
        guard !verified, repository.dataResetGeneration == generation,
              repository.activeSessionId == nil else { return }
        defaults.set(cleanupWarning, forKey: warningKey)
    }
}

extension SettingsView {
    @MainActor
    func validateNotificationAuthorization() async {
        let status = await notificationAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            let granted = await AlarmService.shared.requestPermission()
            if !granted {
                settings.notificationsEnabled = false
                notificationPermissionMessage = "DoseTap cannot play notification alarms until you grant notification permission."
                showingNotificationPermissionAlert = true
            }
        case .denied:
            settings.notificationsEnabled = false
            notificationPermissionMessage = "Notifications are denied for DoseTap in iOS Settings. Enable them to receive wake alarms when the app is backgrounded or the phone is locked."
            showingNotificationPermissionAlert = true
        @unknown default:
            settings.notificationsEnabled = false
            notificationPermissionMessage = "DoseTap could not verify notification permission. Please enable notifications in iOS Settings."
            showingNotificationPermissionAlert = true
        }
    }

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func openSystemNotificationSettings() {
        #if canImport(UIKit)
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
        #endif
    }

    func clearAllData() {
        #if DEBUG
        settingsActionsLog.debug("Clearing all data")
        #endif

        guard SessionRepository.shared.clearAllData() else {
            resetErrorMessage = SessionRepository.shared.lastDataResetFailure?.localizedDescription
                ?? "The reset could not be completed. Your session and settings were not reset."
            showingResetError = true
            return
        }
        AlarmService.shared.prepareAlarmsForDataReset()

        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }

        settings.resetToDefaults()
        // Default settings are not evidence of a completed legacy setup.
        UserDefaults.standard.set(false, forKey: SetupWizardService.setupCompletedKey)
        SavedPainPatternStore.shared.reloadFromPreferences()
        sleepPlanStore.resetToDefaults()
        SessionRepository.shared.reload()
        let generation = SessionRepository.shared.dataResetGeneration
        Task { @MainActor in
            await DataResetPresentation.finishCleanup(repository: .shared, generation: generation,
                verifyAlarms: { await AlarmService.shared.verifyDataResetAlarmCancellation() },
                defaults: .standard)
        }

        #if DEBUG
        settingsActionsLog.debug("All data cleared successfully")
        #endif
    }
}
