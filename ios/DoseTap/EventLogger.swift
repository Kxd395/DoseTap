import Foundation

class EventLogger {
    static let shared = EventLogger()
    private init() {}

    private var lastBathroom: Date?

    func handle(event: String) {
        guard let logEvent = LogEvent(rawValue: event) else { return }

        // Debounce bathroom presses (60s)
        if logEvent == .bathroom {
            if let last = lastBathroom, Date().timeIntervalSince(last) < 60 {
                return
            }
            lastBathroom = Date()
        }

        let event = Event(type: logEvent, ts: Date())
        Store.shared.add(event)

        switch logEvent {
        case .dose1:
            Task {
                // Get baseline from WHOOP or Health
                var baseline: Int = 165
                let whoopHistory = await WHOOPManager.shared.fetchSleepHistory()
                if !whoopHistory.isEmpty {
                    let samples = whoopHistory.compactMap { $0.minutesToFirstWake }.filter { $0 >= 150 && $0 <= 240 }
                    if !samples.isEmpty {
                        let sorted = samples.sorted()
                        let mid = sorted.count / 2
                        baseline = sorted.count % 2 == 0 ? (sorted[mid-1] + sorted[mid]) / 2 : sorted[mid]
                    }
                } else if let healthBaseline = await HealthAccess.latestTTFWBaseline() {
                    baseline = healthBaseline
                }
                
                let offset = max(150, min(240, baseline))
                await ReminderScheduler.scheduleSecondDose(after: offset)
            }
        case .dose2:
            ReminderScheduler.cancelSecondDose()
        case .snooze:
            ReminderScheduler.snooze()
        default:
            break
        }
    }
}
