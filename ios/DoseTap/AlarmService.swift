import Foundation
import UserNotifications
import AVFoundation
import AudioToolbox
import DoseCore
import os.log

private let alarmLog = Logger(subsystem: "com.dosetap.app", category: "AlarmService")

/// Alarm service for scheduling and managing wake alarms
/// Handles snooze functionality with proper notification rescheduling
@MainActor
public class AlarmService: NSObject, ObservableObject {
    
    static let shared = AlarmService()
    private static let fallbackAlarmSystemSoundID: SystemSoundID = 1005
    
    // MARK: - Notification IDs
    private enum NotificationID {
        static let wakeAlarm = "dosetap_wake_alarm"
        static let preAlarm = "dosetap_pre_alarm"
        static let followUp = "dosetap_followup"
        static let secondDose = "dosetap_second_dose"         // Window open reminder
        static let windowWarning15 = "dosetap_window_15min"   // 15 min warning
        static let windowWarning5 = "dosetap_window_5min"     // 5 min warning
    }

    private enum NotificationCategory {
        static let alarm = "dosetap_alarm"
    }

    private enum NotificationAction {
        static let snooze = "dosetap_alarm_snooze"
        static let stop = "dosetap_alarm_stop"
    }
    
    // MARK: - Published Properties
    @Published public var targetWakeTime: Date?
    @Published public var alarmScheduled: Bool = false
    @Published public var snoozeCount: Int = 0
    @Published public var reminderScheduled: Bool = false
    @Published public var isAlarmRinging: Bool = false
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private var audioPlayer: AVAudioPlayer?
    private var vibrationTimer: Timer?
    private var usesSystemSoundFallback: Bool = false
    private var alarmAcknowledged: Bool = false
    private let criticalAlertsCapabilityFlag = "CriticalAlertsCapabilityEnabled"
    
    private var canUseCriticalAlerts: Bool {
        let capabilityEnabled = (Bundle.main.object(forInfoDictionaryKey: criticalAlertsCapabilityFlag) as? Bool) == true
        return UserSettingsManager.shared.criticalAlertsEnabled && capabilityEnabled
    }
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        notificationCenter.delegate = self
        registerNotificationCategories()
        loadTargetWakeTime()
        configureAudioSession()
    }

    private func registerNotificationCategories() {
        let snoozeMinutes = configuredSnoozeDurationMinutes
        let snooze = UNNotificationAction(
            identifier: NotificationAction.snooze,
            title: "Snooze \(snoozeMinutes) min",
            options: []
        )
        let stop = UNNotificationAction(
            identifier: NotificationAction.stop,
            title: "I'm Awake",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: NotificationCategory.alarm,
            actions: [snooze, stop],
            intentIdentifiers: [],
            options: []
        )
        notificationCenter.setNotificationCategories([category])
    }

    public var maxSnoozesAllowed: Int {
        configuredMaxSnoozes
    }

    public var snoozeDurationMinutes: Int {
        configuredSnoozeDurationMinutes
    }
    
    // MARK: - Audio Session
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            alarmLog.error("Failed to configure audio session: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Permission
    
    public func requestPermission() async -> Bool {
        do {
            let options: UNAuthorizationOptions = canUseCriticalAlerts
                ? [.alert, .sound, .badge, .criticalAlert]
                : [.alert, .sound, .badge]
            let granted = try await notificationCenter.requestAuthorization(options: options)
            alarmLog.info("Notification permission \(granted ? "granted" : "denied", privacy: .public)")
            return granted
        } catch {
            alarmLog.error("Permission request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    // MARK: - Schedule Dose 2 Reminders
    
    /// Schedule Dose 2 window reminders after Dose 1 is taken
    /// - Parameter dose1Time: Time Dose 1 was taken
    public func scheduleDose2Reminders(dose1Time: Date) async {
        let settings = UserSettingsManager.shared
        guard settings.notificationsEnabled else {
            reminderScheduled = false
            return
        }
        
        // Window boundaries
        let windowOpen = dose1Time.addingTimeInterval(150 * 60)   // 150 min
        let windowClose = dose1Time.addingTimeInterval(240 * 60)  // 240 min
        let warning15 = windowClose.addingTimeInterval(-15 * 60)  // 15 min before close
        let warning5 = windowClose.addingTimeInterval(-5 * 60)    // 5 min before close
        
        // Schedule window open reminder (identifier: secondDose)
        if windowOpen > Date() && settings.windowOpenAlert {
            await scheduleNotification(
                id: NotificationID.secondDose,
                title: "💊 Dose Window Now Open",
                body: "Your Dose 2 window has opened (150 min). Take Dose 2 when ready.",
                at: windowOpen,
                sound: .default
            )
            alarmLog.info("Dose 2 window reminder scheduled for \(self.formatTime(windowOpen), privacy: .private)")
        }
        
        // Schedule 15 min warning
        if warning15 > Date() && settings.fifteenMinWarning {
            await scheduleNotification(
                id: NotificationID.windowWarning15,
                title: "⚠️ 15 Minutes Remaining",
                body: "Only \(TimeIntervalMath.formatMinutes(15)) left in your dose window!",
                at: warning15,
                sound: .default
            )
        }
        
        // Schedule 5 min warning
        if warning5 > Date() && settings.fiveMinWarning {
            await scheduleNotification(
                id: NotificationID.windowWarning5,
                title: "🚨 5 Minutes Remaining!",
                body: "Final warning - take Dose 2 NOW or skip!",
                at: warning5,
                sound: notificationSound(isCritical: true),
                isCritical: canUseCriticalAlerts
            )
        }
        
        reminderScheduled = true
    }
    
    /// Cancel Dose 2 reminders (called when Dose 2 taken or skipped)
    public func cancelDose2Reminders() {
        let ids = [
            NotificationID.secondDose,
            NotificationID.windowWarning15,
            NotificationID.windowWarning5
        ]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ids)
        reminderScheduled = false
        alarmLog.info("Dose 2 reminders cancelled")
        
        // Diagnostic logging: alarms cancelled
        let sessionId = SessionRepository.shared.currentSessionIdString()
        for id in ids {
            Task {
                await DiagnosticLogger.shared.logAlarm(.alarmCancelled, sessionId: sessionId, alarmId: id, reason: "dose2_completed_or_skipped")
            }
        }
    }
    
    // MARK: - Schedule Wake Alarm
    
    /// Schedule wake alarm for Dose 2
    /// - Parameters:
    ///   - time: Target wake time
    ///   - dose1Time: Time of Dose 1 (for window calculations)
    public func scheduleWakeAlarm(at time: Date, dose1Time: Date) async {
        // Keep action titles in sync with current user snooze settings.
        registerNotificationCategories()
        // Cancel any existing alarms first
        cancelAllAlarms()
        guard UserSettingsManager.shared.notificationsEnabled else {
            clearWakeAlarmState()
            return
        }
        
        // Validate wake time is in the future
        guard time > Date() else {
            alarmLog.warning("Cannot schedule alarm in the past")
            clearWakeAlarmState()
            return
        }
        
        // Calculate window info
        let windowClose = dose1Time.addingTimeInterval(240 * 60)
        let minutesRemaining = Int(windowClose.timeIntervalSince(time) / 60)
        
        alarmAcknowledged = false

        // Schedule pre-alarm (5 minutes before)
        let preAlarmTime = time.addingTimeInterval(-5 * 60)
        if preAlarmTime > Date() {
            await scheduleNotification(
                id: NotificationID.preAlarm,
                title: "⏰ Wake Alarm in 5 Minutes",
                body: "Your Dose 2 alarm will sound soon",
                at: preAlarmTime,
                sound: .default,
                category: NotificationCategory.alarm
            )
        }
        
        // Schedule main wake alarm
        await scheduleNotification(
            id: NotificationID.wakeAlarm,
            title: "🔔 WAKE UP - Time for Dose 2",
            body: "Take your second dose now! \(TimeIntervalMath.formatMinutes(minutesRemaining)) remaining in window.",
            at: time,
            sound: alarmNotificationSound(),
            isCritical: canUseCriticalAlerts,
            category: NotificationCategory.alarm
        )
        
        // Schedule follow-up alarms (every 2 minutes, 3 times)
        for i in 1...3 {
            let followUpTime = time.addingTimeInterval(TimeInterval(i * 2 * 60))
            if followUpTime < windowClose {
                await scheduleNotification(
                    id: "\(NotificationID.followUp)_\(i)",
                    title: "🔔 REMINDER \(i) - Dose 2 Still Waiting",
                    body: "\(TimeIntervalMath.formatMinutes(max(0, minutesRemaining - (i * 2)))) left in window!",
                    at: followUpTime,
                    sound: alarmNotificationSound(),
                    isCritical: canUseCriticalAlerts,
                    category: NotificationCategory.alarm
                )
            }
        }
        
        // Update state
        targetWakeTime = time
        alarmScheduled = true
        saveTargetWakeTime()
        
        alarmLog.info("Wake alarm scheduled for \(self.formatTime(time), privacy: .private)")
    }
    
    // MARK: - Snooze
    
    /// Snooze the alarm by adding 10 minutes to current target time
    /// - Parameter dose1Time: Original Dose 1 time for window recalculation
    /// - Returns: New target time, or nil if snooze not allowed
    public func snoozeAlarm(dose1Time: Date?) async -> Date? {
        let maxSnoozes = configuredMaxSnoozes
        guard maxSnoozes > 0 else {
            alarmLog.warning("Snooze disabled; max snoozes is 0")
            return nil
        }
        guard snoozeCount < maxSnoozes else {
            alarmLog.warning("Max snoozes reached: \(maxSnoozes, privacy: .public)")
            return nil
        }
        guard let currentTarget = targetWakeTime, let d1 = dose1Time else {
            alarmLog.warning("No alarm to snooze")
            return nil
        }
        guard UserSettingsManager.shared.notificationsEnabled else {
            alarmLog.warning("Snooze unavailable while notifications are disabled")
            return nil
        }
        
        // Check if snooze is allowed (not within 15 min of window close)
        let snoozeMinutes = configuredSnoozeDurationMinutes
        let windowClose = d1.addingTimeInterval(240 * 60)
        let newTarget = currentTarget.addingTimeInterval(TimeInterval(snoozeMinutes * 60))
        let nearCloseThreshold = windowClose.addingTimeInterval(-15 * 60)
        
        if newTarget > nearCloseThreshold {
            alarmLog.warning("Snooze would exceed near-close threshold")
            return nil
        }
        
        // Schedule new alarm at snoozed time
        await scheduleWakeAlarm(at: newTarget, dose1Time: d1)
        guard targetWakeTime == newTarget && alarmScheduled else {
            alarmLog.error("Snooze reschedule failed")
            return nil
        }
        snoozeCount += 1
        
        alarmLog.info("Alarm snoozed +\(snoozeMinutes, privacy: .public)m to \(self.formatTime(newTarget), privacy: .private) (snooze \(self.snoozeCount, privacy: .public)/\(maxSnoozes, privacy: .public))")
        
        return newTarget
    }

    // MARK: - Ringing Control

    public func checkForDueAlarm(now: Date = Date()) {
        guard let target = targetWakeTime else { return }
        if SessionRepository.shared.dose2Time != nil || SessionRepository.shared.dose2Skipped {
            clearWakeAlarmState()
            cancelAllAlarms()
            return
        }
        guard alarmScheduled else { return }
        guard !alarmAcknowledged else {
            // Defensive cleanup in case a stale target survives an acknowledged alarm.
            clearWakeAlarmState()
            return
        }
        if target <= now {
            startRinging()
        }
    }

    public func startRinging() {
        guard !isAlarmRinging else { return }
        isAlarmRinging = true
        playAlarmSound()
        startVibrationLoop()
    }

    public func stopRinging(acknowledge: Bool = true) {
        isAlarmRinging = false
        alarmAcknowledged = acknowledge
        stopAlarmSound()
        stopVibrationLoop()
        usesSystemSoundFallback = false
        if acknowledge {
            targetWakeTime = nil
            clearSavedTargetWakeTime()
        }
    }

    public func acknowledgeAlarm() {
        clearWakeAlarmState()
        cancelAllAlarms()
    }
    
    // MARK: - Cancel
    
    /// Cancel all scheduled alarms
    public func cancelAllAlarms() {
        let ids = [
            NotificationID.wakeAlarm,
            NotificationID.preAlarm,
            "\(NotificationID.followUp)_1",
            "\(NotificationID.followUp)_2",
            "\(NotificationID.followUp)_3",
            NotificationID.secondDose,
            NotificationID.windowWarning15,
            NotificationID.windowWarning5
        ]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ids)
        
        alarmScheduled = false
        reminderScheduled = false
        alarmLog.info("All alarms cancelled")
    }

    /// Clear in-memory and persisted wake-alarm target state.
    public func clearWakeAlarmState() {
        stopRinging(acknowledge: true)
        targetWakeTime = nil
        clearSavedTargetWakeTime()
        snoozeCount = 0
        alarmScheduled = false
    }
    
    /// Reset for new session
    public func resetForNewSession() {
        cancelAllAlarms()
        cancelDose2Reminders()
        clearWakeAlarmState()
        reminderScheduled = false
    }
    
    // MARK: - Private Helpers
    
    private func scheduleNotification(
        id: String,
        title: String,
        body: String,
        at date: Date,
        sound: UNNotificationSound?,
        isCritical: Bool = false,
        category: String? = nil
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.interruptionLevel = isCritical ? .critical : .timeSensitive
        if let category {
            content.categoryIdentifier = category
        }
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            alarmLog.info("Scheduled \(id, privacy: .public) for \(self.formatTime(date), privacy: .private)")
            
            // Diagnostic logging: alarm scheduled
            let sessionId = SessionRepository.shared.currentSessionIdString()
            await DiagnosticLogger.shared.logAlarm(.alarmScheduled, sessionId: sessionId, alarmId: id)
        } catch {
            alarmLog.error("Failed to schedule notification: \(error.localizedDescription, privacy: .public)")
            
            // Diagnostic logging: notification error
            let sessionId = SessionRepository.shared.currentSessionIdString()
            await DiagnosticLogger.shared.logError(.errorNotification, sessionId: sessionId, reason: "Failed to schedule: \(error.localizedDescription)")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: date)
    }

    private func notificationSound(isCritical: Bool) -> UNNotificationSound? {
        guard UserSettingsManager.shared.soundEnabled else { return nil }
        if isCritical && canUseCriticalAlerts {
            return .defaultCritical
        }
        return .default
    }

    private func alarmNotificationSound() -> UNNotificationSound? {
        return notificationSound(isCritical: true)
    }
    
    private func saveTargetWakeTime() {
        if let time = targetWakeTime {
            UserDefaults.standard.set(time.timeIntervalSince1970, forKey: "alarmService_targetWakeTime")
        }
    }

    private func clearSavedTargetWakeTime() {
        UserDefaults.standard.removeObject(forKey: "alarmService_targetWakeTime")
    }
    
    private func loadTargetWakeTime() {
        if let timestamp = UserDefaults.standard.object(forKey: "alarmService_targetWakeTime") as? TimeInterval {
            let savedTime = Date(timeIntervalSince1970: timestamp)
            // Only restore if in the future
            if savedTime > Date() {
                targetWakeTime = savedTime
                alarmScheduled = true
            }
        }
    }

    private func playAlarmSound() {
        guard UserSettingsManager.shared.soundEnabled else { return }
        usesSystemSoundFallback = true
        AudioServicesPlaySystemSound(Self.fallbackAlarmSystemSoundID)
    }

    private func stopAlarmSound() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func startVibrationLoop() {
        let settings = UserSettingsManager.shared
        vibrationTimer?.invalidate()
        let shouldVibrate = settings.hapticsEnabled
        let shouldPlayFallbackTone = settings.soundEnabled && usesSystemSoundFallback
        guard shouldVibrate || shouldPlayFallbackTone else { return }
        let fallbackSoundID = Self.fallbackAlarmSystemSoundID
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            if shouldVibrate {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
            if shouldPlayFallbackTone {
                AudioServicesPlaySystemSound(fallbackSoundID)
            }
        }
        if let timer = vibrationTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopVibrationLoop() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }

    private var configuredSnoozeDurationMinutes: Int {
        max(1, min(30, UserSettingsManager.shared.snoozeDurationMinutes))
    }

    private var configuredMaxSnoozes: Int {
        max(0, min(10, UserSettingsManager.shared.maxSnoozes))
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AlarmService: UNUserNotificationCenterDelegate {
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Diagnostic logging: notification delivered (shown while app in foreground)
        let notificationId = notification.request.identifier
        Task { @MainActor in
            let sessionId = SessionRepository.shared.currentSessionIdString()
            await DiagnosticLogger.shared.logNotificationDelivered(
                sessionId: sessionId,
                notificationId: notificationId,
                category: notification.request.content.categoryIdentifier
            )

            if notificationId == NotificationID.wakeAlarm || notificationId.hasPrefix(NotificationID.followUp) {
                self.startRinging()
            }
        }
        
        // Show notification even when app is in foreground.
        // Respect live sound toggle changes.
        var options: UNNotificationPresentationOptions = [.banner, .badge]
        if UserSettingsManager.shared.soundEnabled {
            options.insert(.sound)
        }
        completionHandler(options)
    }
    
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Diagnostic logging: notification tapped
        let notificationId = response.notification.request.identifier
        let actionId = response.actionIdentifier
        
        Task { @MainActor in
            let sessionId = SessionRepository.shared.currentSessionIdString()
            
            if actionId == UNNotificationDismissActionIdentifier {
                await DiagnosticLogger.shared.logNotificationDismissed(
                    sessionId: sessionId,
                    notificationId: notificationId,
                    category: response.notification.request.content.categoryIdentifier
                )
            } else {
                await DiagnosticLogger.shared.logNotificationTapped(
                    sessionId: sessionId,
                    notificationId: notificationId,
                    category: response.notification.request.content.categoryIdentifier
                )
            }

            if actionId == NotificationAction.snooze {
                let snoozed = await self.snoozeAlarm(dose1Time: SessionRepository.shared.dose1Time)
                if snoozed != nil {
                    SessionRepository.shared.incrementSnooze()
                    self.stopRinging(acknowledge: false)
                }
            } else if actionId == NotificationAction.stop {
                self.acknowledgeAlarm()
            } else if actionId == UNNotificationDefaultActionIdentifier {
                if notificationId == NotificationID.wakeAlarm || notificationId.hasPrefix(NotificationID.followUp) {
                    self.startRinging()
                }
            }
        }
        
        completionHandler()
    }
}
