import Foundation
import UserNotifications

enum ReminderIDs {
    static let secondDose = "secondDose"
}

struct ReminderScheduler {
    static func scheduleSecondDose(after minutes: Int) async {
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
    }

    static func cancelSecondDose() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [ReminderIDs.secondDose])
    }

    static func snooze() {
        // Snooze by 10 minutes
        Task {
            await scheduleSecondDose(after: 10)
        }
    }
}
