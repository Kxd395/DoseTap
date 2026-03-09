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

    func exportData() {
        let csvContent = SessionRepository.shared.exportToCSV()
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "DoseTap_Export_\(DateFormatter.exportDateFormatter.string(from: Date())).csv"
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURL = fileURL
            showingExportSheet = true
            settingsActionsLog.info("Export file created: \(fileURL.lastPathComponent, privacy: .private)")
        } catch {
            settingsActionsLog.error("Failed to create export file: \(error.localizedDescription, privacy: .public)")
            exportErrorMessage = error.localizedDescription
            showingExportError = true
        }
    }

    func clearAllData() {
        #if DEBUG
        settingsActionsLog.debug("Clearing all data")
        #endif

        SessionRepository.shared.clearAllData()

        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }

        settings.resetToDefaults()
        sleepPlanStore.resetToDefaults()
        SessionRepository.shared.reload()

        #if DEBUG
        settingsActionsLog.debug("All data cleared successfully")
        #endif
    }
}
