import Foundation
import UserNotifications
import AVFoundation

/// Alarm service for scheduling and managing wake alarms
/// Handles snooze functionality with proper notification rescheduling
@MainActor
public class AlarmService: NSObject, ObservableObject {
    
    static let shared = AlarmService()
    
    // MARK: - Notification IDs
    private enum NotificationID {
        static let wakeAlarm = "dosetap_wake_alarm"
        static let preAlarm = "dosetap_pre_alarm"
        static let followUp = "dosetap_followup"
        static let secondDose = "dosetap_second_dose"         // Window open reminder
        static let windowWarning15 = "dosetap_window_15min"   // 15 min warning
        static let windowWarning5 = "dosetap_window_5min"     // 5 min warning
    }
    
    // MARK: - Published Properties
    @Published public var targetWakeTime: Date?
    @Published public var alarmScheduled: Bool = false
    @Published public var snoozeCount: Int = 0
    @Published public var reminderScheduled: Bool = false
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private var audioPlayer: AVAudioPlayer?
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        notificationCenter.delegate = self
        loadTargetWakeTime()
        configureAudioSession()
    }
    
    // MARK: - Audio Session
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ AlarmService: Failed to configure audio session: \(error)")
        }
    }
    
    // MARK: - Permission
    
    public func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
            print("✅ AlarmService: Notification permission \(granted ? "granted" : "denied")")
            return granted
        } catch {
            print("⚠️ AlarmService: Permission request failed: \(error)")
            return false
        }
    }
    
    // MARK: - Schedule Dose 2 Reminders
    
    /// Schedule Dose 2 window reminders after Dose 1 is taken
    /// - Parameter dose1Time: Time Dose 1 was taken
    public func scheduleDose2Reminders(dose1Time: Date) async {
        let settings = UserSettingsManager.shared
        
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
            print("📅 AlarmService: Dose 2 window open reminder scheduled for \(formatTime(windowOpen))")
        }
        
        // Schedule 15 min warning
        if warning15 > Date() && settings.fifteenMinWarning {
            await scheduleNotification(
                id: NotificationID.windowWarning15,
                title: "⚠️ 15 Minutes Remaining",
                body: "Only 15 minutes left in your dose window!",
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
                sound: .defaultCritical
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
        reminderScheduled = false
        print("🔕 AlarmService: Dose 2 reminders cancelled")
    }
    
    // MARK: - Schedule Wake Alarm
    
    /// Schedule wake alarm for Dose 2
    /// - Parameters:
    ///   - time: Target wake time
    ///   - dose1Time: Time of Dose 1 (for window calculations)
    public func scheduleWakeAlarm(at time: Date, dose1Time: Date) async {
        // Cancel any existing alarms first
        cancelAllAlarms()
        
        // Validate wake time is in the future
        guard time > Date() else {
            print("⚠️ AlarmService: Cannot schedule alarm in the past")
            return
        }
        
        // Calculate window info
        let windowClose = dose1Time.addingTimeInterval(240 * 60)
        let minutesRemaining = Int(windowClose.timeIntervalSince(time) / 60)
        
        // Schedule pre-alarm (5 minutes before)
        let preAlarmTime = time.addingTimeInterval(-5 * 60)
        if preAlarmTime > Date() {
            await scheduleNotification(
                id: NotificationID.preAlarm,
                title: "⏰ Wake Alarm in 5 Minutes",
                body: "Your Dose 2 alarm will sound soon",
                at: preAlarmTime,
                sound: .default
            )
        }
        
        // Schedule main wake alarm
        await scheduleNotification(
            id: NotificationID.wakeAlarm,
            title: "🔔 WAKE UP - Time for Dose 2",
            body: "Take your second dose now! \(minutesRemaining) minutes remaining in window.",
            at: time,
            sound: .defaultCritical
        )
        
        // Schedule follow-up alarms (every 2 minutes, 3 times)
        for i in 1...3 {
            let followUpTime = time.addingTimeInterval(TimeInterval(i * 2 * 60))
            if followUpTime < windowClose {
                await scheduleNotification(
                    id: "\(NotificationID.followUp)_\(i)",
                    title: "🔔 REMINDER \(i) - Dose 2 Still Waiting",
                    body: "\(max(0, minutesRemaining - (i * 2))) minutes left in window!",
                    at: followUpTime,
                    sound: .defaultCritical
                )
            }
        }
        
        // Update state
        targetWakeTime = time
        alarmScheduled = true
        saveTargetWakeTime()
        
        print("✅ AlarmService: Wake alarm scheduled for \(formatTime(time))")
    }
    
    // MARK: - Snooze
    
    /// Snooze the alarm by adding 10 minutes to current target time
    /// - Parameter dose1Time: Original Dose 1 time for window recalculation
    /// - Returns: New target time, or nil if snooze not allowed
    public func snoozeAlarm(dose1Time: Date?) async -> Date? {
        guard let currentTarget = targetWakeTime, let d1 = dose1Time else {
            print("⚠️ AlarmService: No alarm to snooze")
            return nil
        }
        
        // Check if snooze is allowed (not within 15 min of window close)
        let windowClose = d1.addingTimeInterval(240 * 60)
        let newTarget = currentTarget.addingTimeInterval(10 * 60)
        let nearCloseThreshold = windowClose.addingTimeInterval(-15 * 60)
        
        if newTarget > nearCloseThreshold {
            print("⚠️ AlarmService: Snooze would exceed near-close threshold")
            return nil
        }
        
        // Cancel existing alarms and reschedule
        cancelAllAlarms()
        snoozeCount += 1
        
        // Schedule new alarm at snoozed time
        await scheduleWakeAlarm(at: newTarget, dose1Time: d1)
        
        print("✅ AlarmService: Alarm snoozed +10min to \(formatTime(newTarget)) (snooze \(snoozeCount)/3)")
        
        return newTarget
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
        
        alarmScheduled = false
        reminderScheduled = false
        print("🔕 AlarmService: All alarms cancelled")
    }
    
    /// Reset for new session
    public func resetForNewSession() {
        cancelAllAlarms()
        cancelDose2Reminders()
        targetWakeTime = nil
        snoozeCount = 0
        reminderScheduled = false
        UserDefaults.standard.removeObject(forKey: "alarmService_targetWakeTime")
    }
    
    // MARK: - Private Helpers
    
    private func scheduleNotification(
        id: String,
        title: String,
        body: String,
        at date: Date,
        sound: UNNotificationSound
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.interruptionLevel = .timeSensitive
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            print("📅 AlarmService: Scheduled '\(id)' for \(formatTime(date))")
        } catch {
            print("⚠️ AlarmService: Failed to schedule notification: \(error)")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: date)
    }
    
    private func saveTargetWakeTime() {
        if let time = targetWakeTime {
            UserDefaults.standard.set(time.timeIntervalSince1970, forKey: "alarmService_targetWakeTime")
        }
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
}

// MARK: - UNUserNotificationCenterDelegate

extension AlarmService: UNUserNotificationCenterDelegate {
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap - just complete for now
        // Actionable buttons can be added later
        completionHandler()
    }
}
