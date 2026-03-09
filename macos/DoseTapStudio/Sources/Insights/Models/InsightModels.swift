import Foundation

enum InsightDoseEventKind: String, Sendable {
    case dose1
    case dose2
    case dose2Skipped
    case snooze
    case other

    init(eventType: EventType) {
        switch eventType {
        case .dose1_taken:
            self = .dose1
        case .dose2_taken:
            self = .dose2
        case .dose2_skipped:
            self = .dose2Skipped
        case .dose2_snoozed, .snooze:
            self = .snooze
        default:
            self = .other
        }
    }
}

struct InsightEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    let type: EventType
    let kind: InsightDoseEventKind
    let timestamp: Date
    let details: String?
}

struct InsightSession: Identifiable, Hashable, Sendable {
    let id: String
    let sessionDate: String
    let startedAt: Date?
    let endedAt: Date?
    let dose1Time: Date?
    let dose2Time: Date?
    let dose2Skipped: Bool
    let snoozeCount: Int
    let adherenceFlag: String?
    let sleepEfficiency: Double?
    let whoopRecovery: Int?
    let averageHeartRate: Double?
    let notes: String?
    let events: [InsightEvent]

    var intervalMinutes: Int? {
        guard let dose1Time, let dose2Time else { return nil }
        let delta = Int(dose2Time.timeIntervalSince(dose1Time) / 60)
        return delta >= 0 ? delta : nil
    }

    var eventCount: Int {
        events.count
    }

    var bathroomCount: Int {
        events.filter { $0.type == .bathroom }.count
    }

    var lightsOutCount: Int {
        events.filter { $0.type == .lights_out }.count
    }

    var wakeFinalCount: Int {
        events.filter { $0.type == .wake_final }.count
    }

    var isLateDose2: Bool {
        guard let intervalMinutes else { return false }
        return intervalMinutes > 240
    }

    var isOnTimeDose2: Bool {
        guard let intervalMinutes else { return false }
        return (150...240).contains(intervalMinutes)
    }

    var isMissingOutcome: Bool {
        dose1Time != nil && dose2Time == nil && !dose2Skipped
    }

    var completenessScore: Double {
        var score = 0.0
        if dose1Time != nil && (dose2Time != nil || dose2Skipped) { score += 0.4 }
        if sleepEfficiency != nil { score += 0.2 }
        if whoopRecovery != nil || averageHeartRate != nil { score += 0.1 }
        if !events.isEmpty { score += 0.2 }
        if !qualityFlags.isEmpty { score -= 0.1 }
        return max(0.0, min(1.0, score))
    }

    var qualityFlags: [String] {
        var flags: [String] = []
        if isMissingOutcome {
            flags.append("Missing Dose 2 outcome")
        }
        if lightsOutCount > 1 {
            flags.append("Duplicate lights out logs")
        }
        if wakeFinalCount > 1 {
            flags.append("Duplicate wake-final logs")
        }
        if intervalMinutes == nil && dose2Time != nil {
            flags.append("Dose interval unavailable")
        }
        return flags
    }

    var qualitySummary: String {
        qualityFlags.first ?? "Clean"
    }
}

struct InsightFilterState: Equatable, Sendable {
    var searchText = ""
    var lateDoseOnly = false
    var skippedOnly = false
    var qualityIssuesOnly = false
}
