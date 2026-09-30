import Foundation
import os.log
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

private let settingsActionsLog = Logger(subsystem: "com.dosetap.app", category: "SettingsView")

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
        SavedPainPatternStore.shared.reloadFromPreferences()
        sleepPlanStore.resetToDefaults()
        SessionRepository.shared.reload()
        Task { @MainActor in
            guard SessionRepository.shared.activeSessionId == nil else { return }
            let verified = await AlarmService.shared.verifyDataResetAlarmCancellation()
            guard !verified, SessionRepository.shared.activeSessionId == nil else { return }
            resetErrorMessage = "Local records and settings were cleared, but alarm cleanup could not be verified. Check iOS alarms and notifications before relying on them."
            showingResetError = true
        }

        #if DEBUG
        settingsActionsLog.debug("All data cleared successfully")
        #endif
    }
}
