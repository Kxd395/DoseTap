import Foundation

enum WakeFeelingNow: String {
    case rough
    case okay
    case good
    case great

    init(rawSurveyValue: String) {
        switch rawSurveyValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "rough": self = .rough
        case "great": self = .great
        case "good": self = .good
        default: self = .okay
        }
    }
}

enum WakeAwakeningsCount: String {
    case none
    case oneTwo
    case threeFour
    case fivePlus

    init(rawSurveyValue: String) {
        switch rawSurveyValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1-2", "one-two": self = .oneTwo
        case "3-4", "three-four": self = .threeFour
        case "5+", "5plus", "five-plus": self = .fivePlus
        default: self = .none
        }
    }
}

enum WakeLongAwakePeriod: String {
    case none
    case lessThan15
    case fifteenTo30
    case thirtyTo60
    case oneHourPlus

    init(rawSurveyValue: String) {
        switch rawSurveyValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "<15m", "<15", "less_than_15": self = .lessThan15
        case "15-30m", "15-30": self = .fifteenTo30
        case "30-60m", "30-60": self = .thirtyTo60
        case "1h+", "1h", "1hour+", "60+": self = .oneHourPlus
        default: self = .none
        }
    }
}

@MainActor
final class MorningCheckInViewModelV2 {
    var feelingNow: WakeFeelingNow = .okay
    var sleepQuality: Int = 3
    var sleepinessNow: Int = 3
    var wakePainLevel: Int = 0
    var painWokeUser: Bool = false
    var awakeningsCount: WakeAwakeningsCount = .none
    var longAwakePeriod: WakeLongAwakePeriod = .none
    var notes: String = ""

    @discardableResult
    func applyLastWakeSurvey(from events: [StoredSleepEvent], excludingSessionDate: String) -> Bool {
        guard
            let latest = events.filter({ $0.eventType == "wake_survey" && $0.sessionDate != excludingSessionDate }).sorted(by: { $0.timestamp > $1.timestamp }).first,
            let payloadText = latest.notes,
            let payloadData = payloadText.data(using: .utf8),
            let payload = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any]
        else {
            return false
        }

        if let value = payload["feeling"] as? String { feelingNow = WakeFeelingNow(rawSurveyValue: value) }
        if let value = payload["sleep_quality"] as? Int { sleepQuality = value }
        if let value = payload["sleepiness_now"] as? Int { sleepinessNow = value }
        if let value = payload["pain_level"] as? Int { wakePainLevel = value }
        if let value = payload["pain_woke_user"] as? Bool { painWokeUser = value }
        if let value = payload["awakenings"] as? String { awakeningsCount = WakeAwakeningsCount(rawSurveyValue: value) }
        if let value = payload["long_awake"] as? String { longAwakePeriod = WakeLongAwakePeriod(rawSurveyValue: value) }
        if let value = payload["notes"] as? String { notes = value }
        return true
    }
}
