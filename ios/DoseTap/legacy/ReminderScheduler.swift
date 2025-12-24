import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

enum ReminderIDs {
    static let secondDose = "secondDose"
}

struct ReminderScheduler {
    static func scheduleSecondDose(after minutes: Int) async {
#if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Second dose window"
            content.body  = "If you're awake, it's time to take Dose 2."
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
            let req = UNNotificationRequest(identifier: ReminderIDs.secondDose, content: content, trigger: trigger)
            try await center.add(req)
        } catch {
            print("Notification scheduling failed: \(error)")
        }
#else
        // Unsupported platform (tests / macOS) -> no-op
#endif
    }

    static func cancelSecondDose() {
#if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [ReminderIDs.secondDose])
#endif
    }

    static func snooze() {
#if canImport(UserNotifications)
        Task { await scheduleSecondDose(after: 10) }
#endif
    }
}
