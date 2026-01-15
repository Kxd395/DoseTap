import Foundation
import Combine
import UserNotifications
import SwiftUI
import DoseCore
import AVFoundation

/// Enhanced notification service with medical-grade critical alerts and actionable buttons
@MainActor
public class EnhancedNotificationService: NSObject, ObservableObject {
    
    // Notification identifiers
    private enum NotificationID {
        static let doseReminder = "dose_reminder"
        static let windowOpening = "window_opening"
        static let windowClosing = "window_closing"
        static let windowCritical = "window_critical"
        static let medicationRefill = "medication_refill"
        static let wakeAlarm = "wake_alarm"
        static let hardStop = "hard_stop"
        static let repeatingAlarm = "repeating_alarm"
    }
    
    // Notification actions
    private enum ActionID {
        static let takeNow = "take_now"
        static let snooze = "snooze_10m"
        static let skip = "skip_dose"
        static let dismiss = "dismiss"
        static let stopAlarm = "stop_alarm"
    }
    
    private let notificationCenter = UNUserNotificationCenter.current()
    @Published public var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published public var criticalAlertsEnabled: Bool = false
    @Published public var targetWakeTime: Date?
    @Published public var alarmEnabled: Bool = true
    
    // Audio player for repeating alarm sound
    private var alarmAudioPlayer: AVAudioPlayer?
    private var alarmTimer: Timer?
    
    // Integration with core services
    private var doseCore: DoseCoreIntegration?
    
    public override init() {
        super.init()
        notificationCenter.delegate = self
        checkAuthorizationStatus()
        registerNotificationActions()
        configureAudioSession()
    }
    
    public func setDoseCoreIntegration(_ doseCore: DoseCoreIntegration) {
        self.doseCore = doseCore
    }
    
    // MARK: - Target Wake Time Setup
    
    /// Set target wake time for Dose 2 alarm
    /// Returns true if the wake time is valid (within the dose window)
    public func setTargetWakeTime(_ wakeTime: Date, dose1Time: Date) -> (valid: Bool, message: String) {
        let windowOpen = dose1Time.addingTimeInterval(150 * 60)  // 150 minutes
        let windowClose = dose1Time.addingTimeInterval(240 * 60) // 240 minutes
        
        if wakeTime < windowOpen {
            let minutesEarly = Int((windowOpen.timeIntervalSince(wakeTime)) / 60)
            return (false, "Wake time is \(minutesEarly) minutes before window opens. You may miss your optimal Dose 2 time.")
        }
        
        if wakeTime > windowClose {
            let minutesLate = Int((wakeTime.timeIntervalSince(windowClose)) / 60)
            return (false, "Wake time is \(minutesLate) minutes after window closes! Dose 2 will be outside the safe window.")
        }
        
        // Valid wake time - store it
        targetWakeTime = wakeTime
        UserDefaults.standard.set(wakeTime.timeIntervalSince1970, forKey: "targetWakeTime")
        
        // Calculate recommended Dose 2 time (wake time - 15 min buffer for taking medication)
        let recommendedDose2Time = wakeTime.addingTimeInterval(-15 * 60)
        let intervalFromDose1 = Int(recommendedDose2Time.timeIntervalSince(dose1Time) / 60)
        
        return (true, "Wake alarm set for \(formatTime(wakeTime)). Dose 2 recommended at \(formatTime(recommendedDose2Time)) (\(intervalFromDose1) min after Dose 1).")
    }
    
    /// Clear target wake time
    public func clearTargetWakeTime() {
        targetWakeTime = nil
        UserDefaults.standard.removeObject(forKey: "targetWakeTime")
    }
    
    /// Load persisted target wake time
    public func loadTargetWakeTime() {
        if let timestamp = UserDefaults.standard.object(forKey: "targetWakeTime") as? TimeInterval {
            targetWakeTime = Date(timeIntervalSince1970: timestamp)
        }
    }
    
    // MARK: - Alarm System
    
    /// Schedule wake alarm for Dose 2
    public func scheduleWakeAlarm(at time: Date, dose1Time: Date) {
        guard alarmEnabled else { return }
        
        // Cancel existing wake alarms
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.wakeAlarm,
            "\(NotificationID.wakeAlarm)_pre",
            "\(NotificationID.wakeAlarm)_follow1",
            "\(NotificationID.wakeAlarm)_follow2",
            "\(NotificationID.wakeAlarm)_follow3"
        ])
        
        let remainingWindow = Int((dose1Time.addingTimeInterval(240 * 60).timeIntervalSince(time)) / 60)
        
        // Pre-alarm warning (5 minutes before)
        scheduleAlarmNotification(
            id: "\(NotificationID.wakeAlarm)_pre",
            title: "⏰ DoseTap - Wake Alarm in 5 min",
            body: "Your Dose 2 wake alarm will sound in 5 minutes",
            date: time.addingTimeInterval(-5 * 60),
            isAlarm: false
        )
        
        // Main wake alarm
        scheduleAlarmNotification(
            id: NotificationID.wakeAlarm,
            title: "🔔 DoseTap - WAKE UP FOR DOSE 2",
            body: "Time for your second dose! \(remainingWindow) minutes left in window.",
            date: time,
            isAlarm: true
        )
        
        // Follow-up alarms every 2 minutes (3 times) if not acknowledged
        for i in 1...3 {
            scheduleAlarmNotification(
                id: "\(NotificationID.wakeAlarm)_follow\(i)",
                title: "🔔🔔 DoseTap - DOSE 2 REMINDER \(i)",
                body: "Still waiting for Dose 2! \(max(0, remainingWindow - (i * 2))) minutes left in window.",
                date: time.addingTimeInterval(TimeInterval(i * 2 * 60)),
                isAlarm: true
            )
        }
        
        targetWakeTime = time
        print("Scheduled wake alarm for \(formatTime(time))")
    }
    
    /// Schedule hard stop warnings (escalating alerts as window closes)
    public func scheduleHardStopWarnings(dose1Time: Date) {
        let windowClose = dose1Time.addingTimeInterval(240 * 60)
        
        // 15 minute warning (snooze still enabled)
        let fifteenMinWarning = windowClose.addingTimeInterval(-15 * 60)
        scheduleNotification(
            id: NotificationID.windowClosing,
            title: "⚠️ DoseTap - 15 MIN WARNING",
            body: "Dose 2 window closes in 15 minutes! Snooze will be disabled soon.",
            date: fifteenMinWarning,
            critical: false,
            actions: [ActionID.takeNow, ActionID.snooze, ActionID.skip]
        )
        
        // 5 minute warning (critical, no snooze)
        let fiveMinWarning = windowClose.addingTimeInterval(-5 * 60)
        scheduleAlarmNotification(
            id: "\(NotificationID.hardStop)_5min",
            title: "🚨 DoseTap - HARD STOP IN 5 MIN",
            body: "TAKE DOSE 2 NOW! Window closes in 5 minutes.",
            date: fiveMinWarning,
            isAlarm: true
        )
        
        // 2 minute warning (repeating critical)
        let twoMinWarning = windowClose.addingTimeInterval(-2 * 60)
        scheduleAlarmNotification(
            id: "\(NotificationID.hardStop)_2min",
            title: "🚨🚨 DoseTap - HARD STOP IN 2 MIN",
            body: "URGENT: Take Dose 2 immediately or window will expire!",
            date: twoMinWarning,
            isAlarm: true
        )
        
        // 30 second final warning
        let thirtySecWarning = windowClose.addingTimeInterval(-30)
        scheduleAlarmNotification(
            id: "\(NotificationID.hardStop)_30sec",
            title: "⛔️ DoseTap - FINAL WARNING",
            body: "30 SECONDS LEFT! Take Dose 2 NOW or window expires!",
            date: thirtySecWarning,
            isAlarm: true
        )
        
        // Window expired notification
        scheduleNotification(
            id: "\(NotificationID.hardStop)_expired",
            title: "⛔️ DoseTap - WINDOW EXPIRED",
            body: "Dose 2 window has closed. Session will be marked incomplete.",
            date: windowClose,
            critical: true,
            actions: [ActionID.dismiss]
        )
    }
    
    private func scheduleAlarmNotification(
        id: String,
        title: String,
        body: String,
        date: Date,
        isAlarm: Bool
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = isAlarm ? "dose_alarm" : "dose_reminder"
        
        if isAlarm && criticalAlertsEnabled {
            content.interruptionLevel = .critical
            content.sound = .defaultCritical
        } else if isAlarm {
            content.interruptionLevel = .timeSensitive
            content.sound = UNNotificationSound.defaultCritical
        } else {
            content.interruptionLevel = .active
            content.sound = .default
        }
        
        content.badge = 1
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule alarm notification \(id): \(error)")
            } else {
                print("Scheduled alarm: \(title) at \(date)")
            }
        }
    }
    
    /// Stop all active alarms
    public func stopAllAlarms() {
        // Stop audio player
        alarmAudioPlayer?.stop()
        alarmTimer?.invalidate()
        alarmTimer = nil
        
        // Remove alarm notifications
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.wakeAlarm,
            "\(NotificationID.wakeAlarm)_pre",
            "\(NotificationID.wakeAlarm)_follow1",
            "\(NotificationID.wakeAlarm)_follow2",
            "\(NotificationID.wakeAlarm)_follow3",
            "\(NotificationID.hardStop)_5min",
            "\(NotificationID.hardStop)_2min",
            "\(NotificationID.hardStop)_30sec",
            "\(NotificationID.hardStop)_expired"
        ])
        
        print("All alarms stopped")
    }
    
    // MARK: - Audio Configuration
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    // MARK: - Permissions
    
    /// Request notification permissions including critical alerts
    public func requestPermissions() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge, .criticalAlert, .providesAppNotificationSettings]
            )
            
            await MainActor.run {
                authorizationStatus = granted ? .authorized : .denied
                criticalAlertsEnabled = granted
            }
            
            return granted
        } catch {
            print("Failed to request notification permissions: \(error)")
            return false
        }
    }
    
    /// Schedule dose window notifications based on current context
    public func scheduleDoseNotifications(for context: DoseWindowContext, dose1Time: Date?) {
        // Clear existing notifications
        notificationCenter.removeAllPendingNotificationRequests()
        
        guard let dose1Time = dose1Time else {
            print("No Dose 1 time available for scheduling")
            return
        }
        
        let windowStart = dose1Time.addingTimeInterval(150 * 60) // 150 minutes
        let windowEnd = dose1Time.addingTimeInterval(240 * 60)   // 240 minutes
        let nearCloseTime = dose1Time.addingTimeInterval(225 * 60) // 225 minutes (15m before close)
        let criticalTime = dose1Time.addingTimeInterval(237 * 60)  // 237 minutes (3m before close)
        
        // Schedule window opening notification
        scheduleNotification(
            id: NotificationID.windowOpening,
            title: "DoseTap",
            body: "Dose 2 window is now open",
            date: windowStart,
            critical: false,
            actions: [ActionID.takeNow, ActionID.snooze, ActionID.dismiss]
        )
        
        // Schedule regular reminders during active window
        let reminderInterval: TimeInterval = 30 * 60 // Every 30 minutes
        var reminderTime = windowStart.addingTimeInterval(reminderInterval)
        
        while reminderTime < nearCloseTime {
            let remainingMinutes = Int((windowEnd.timeIntervalSince(reminderTime)) / 60)
            
            scheduleNotification(
                id: "\(NotificationID.doseReminder)_\(remainingMinutes)",
                title: "DoseTap",
                body: "Take Dose 2 — \(remainingMinutes)m left",
                date: reminderTime,
                critical: false,
                actions: context.snoozeEnabled ? 
                    [ActionID.takeNow, ActionID.snooze, ActionID.skip] :
                    [ActionID.takeNow, ActionID.skip]
            )
            
            reminderTime = reminderTime.addingTimeInterval(reminderInterval)
        }
        
        // Schedule near-close warning (snooze disabled)
        let nearCloseMinutes = Int((windowEnd.timeIntervalSince(nearCloseTime)) / 60)
        scheduleNotification(
            id: NotificationID.windowClosing,
            title: "DoseTap",
            body: "Take Dose 2 — \(nearCloseMinutes)m left",
            subtitle: "Snooze unavailable (<15m)",
            date: nearCloseTime,
            critical: false,
            actions: [ActionID.takeNow, ActionID.skip]
        )
        
        // Schedule critical alert (persistent until action)
        scheduleNotification(
            id: NotificationID.windowCritical,
            title: "⚠️ DoseTap - CRITICAL",
            body: "Dose window closing in 3m",
            subtitle: "This alert stays until you take action.",
            date: criticalTime,
            critical: true,
            actions: [ActionID.takeNow, ActionID.skip]
        )
        
        Task {
            let count = await getPendingNotificationCount()
            print("Scheduled \(count) dose notifications")
        }
    }
    
    /// Schedule medication refill reminder
    public func scheduleRefillReminder(daysRemaining: Int, medicationName: String) {
        let reminderDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        
        let title: String
        let body: String
        let critical: Bool
        
        switch daysRemaining {
        case 0:
            title = "⚠️ DoseTap - MEDICATION EMPTY"
            body = "\(medicationName) supply depleted"
            critical = true
        case 1...7:
            title = "🔴 DoseTap - CRITICAL REFILL"
            body = "\(medicationName) refill needed: \(daysRemaining) days left"
            critical = true
        case 8...15:
            title = "🟡 DoseTap - Refill Soon"
            body = "\(medicationName) refill in \(daysRemaining) days"
            critical = false
        default:
            return // No reminder needed for >15 days
        }
        
        scheduleNotification(
            id: NotificationID.medicationRefill,
            title: title,
            body: body,
            date: reminderDate,
            critical: critical,
            actions: [ActionID.dismiss]
        )
    }
    
    /// Cancel all pending notifications
    public func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        print("Cancelled all pending notifications")
    }
    
    /// Get count of pending notifications for debugging
    public func getPendingNotificationCount() async -> Int {
        let requests = await notificationCenter.pendingNotificationRequests()
        return requests.count
    }
    
    // MARK: - Private Methods
    
    private func checkAuthorizationStatus() {
        Task { @MainActor in
            let settings = await notificationCenter.notificationSettings()
            self.authorizationStatus = settings.authorizationStatus
            self.criticalAlertsEnabled = settings.criticalAlertSetting == .enabled
        }
    }
    
    private func registerNotificationActions() {
        let takeAction = UNNotificationAction(
            identifier: ActionID.takeNow,
            title: "Take Now",
            options: [.foreground]
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: ActionID.snooze,
            title: "Snooze +10m",
            options: []
        )
        
        let skipAction = UNNotificationAction(
            identifier: ActionID.skip,
            title: "Skip",
            options: [.destructive]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: ActionID.dismiss,
            title: "Dismiss",
            options: []
        )
        
        let stopAlarmAction = UNNotificationAction(
            identifier: ActionID.stopAlarm,
            title: "Stop Alarm",
            options: [.foreground]
        )
        
        // Dose reminder category (with snooze)
        let doseReminderCategory = UNNotificationCategory(
            identifier: "dose_reminder",
            actions: [takeAction, snoozeAction, skipAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Near-close category (no snooze)
        let nearCloseCategory = UNNotificationCategory(
            identifier: "dose_near_close",
            actions: [takeAction, skipAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Critical category (persistent)
        let criticalCategory = UNNotificationCategory(
            identifier: "dose_critical",
            actions: [takeAction, skipAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Alarm category (take now or stop)
        let alarmCategory = UNNotificationCategory(
            identifier: "dose_alarm",
            actions: [takeAction, stopAlarmAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Refill category
        let refillCategory = UNNotificationCategory(
            identifier: "medication_refill",
            actions: [dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        notificationCenter.setNotificationCategories([
            doseReminderCategory,
            nearCloseCategory,
            criticalCategory,
            alarmCategory,
            refillCategory
        ])
    }
    
    // MARK: - Helper Methods
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func scheduleNotification(
        id: String,
        title: String,
        body: String,
        subtitle: String? = nil,
        date: Date,
        critical: Bool = false,
        actions: [String] = []
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        
        // Set category based on actions
        if actions.contains(ActionID.snooze) {
            content.categoryIdentifier = "dose_reminder"
        } else if critical && title.contains("CRITICAL") {
            content.categoryIdentifier = "dose_critical"
        } else if actions.contains(ActionID.takeNow) {
            content.categoryIdentifier = "dose_near_close"
        } else {
            content.categoryIdentifier = "medication_refill"
        }
        
        // Configure for critical alerts
        if critical && criticalAlertsEnabled {
            content.interruptionLevel = .critical
            content.sound = .defaultCritical
        } else {
            content.interruptionLevel = .active
            content.sound = .default
        }
        
        content.badge = 1
        
        // Schedule for specific time
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule notification \(id): \(error)")
            } else {
                print("Scheduled notification: \(title) at \(date)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension EnhancedNotificationService: @preconcurrency UNUserNotificationCenterDelegate {
    
    /// Handle notification actions
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        
        Task { @MainActor in
            switch actionIdentifier {
            case ActionID.takeNow:
                await handleTakeAction()
                
            case ActionID.snooze:
                await handleSnoozeAction()
                
            case ActionID.skip:
                await handleSkipAction()
                
            case ActionID.stopAlarm:
                handleStopAlarmAction()
                
            case ActionID.dismiss, UNNotificationDefaultActionIdentifier:
                // Just dismiss - no additional action needed
                break
                
            default:
                print("Unknown notification action: \(actionIdentifier)")
            }
            
            completionHandler()
        }
    }
    
    /// Show notifications even when app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is active
        let options: UNNotificationPresentationOptions = [.banner, .sound, .badge]
        completionHandler(options)
    }
    
    // MARK: - Action Handlers
    
    private func handleTakeAction() async {
        guard let doseCore = doseCore else {
            print("DoseCore integration not available")
            return
        }
        
        // Stop any active alarms
        stopAllAlarms()
        
        // Determine which dose to take based on current context
        let context = doseCore.currentContext
        
        if context.primaryCTA.lowercased().contains("dose 1") {
            await doseCore.takeDose1()
        } else {
            await doseCore.takeDose2()
        }
        
        // Cancel remaining notifications since dose was taken
        cancelAllNotifications()
        
        print("Handled take action via notification")
    }
    
    private func handleSnoozeAction() async {
        guard let doseCore = doseCore else {
            print("DoseCore integration not available")
            return
        }
        
        // Stop current alarm but don't cancel all notifications
        stopAllAlarms()
        
        await doseCore.snooze()
        
        // Reschedule notifications with new snooze time
        // This would need access to current dose1 time and context
        print("Handled snooze action via notification")
    }
    
    private func handleSkipAction() async {
        guard let doseCore = doseCore else {
            print("DoseCore integration not available")
            return
        }
        
        // Stop alarms
        stopAllAlarms()
        
        await doseCore.skipDose2()
        
        // Cancel remaining notifications since dose was skipped
        cancelAllNotifications()
        
        print("Handled skip action via notification")
    }
    
    private func handleStopAlarmAction() {
        // Stop alarms without taking any dose action
        stopAllAlarms()
        print("Handled stop alarm action via notification")
    }
}
