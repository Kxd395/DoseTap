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

struct InsightBundle: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let exportedAtUTC: Date
    let sessions: [InsightSessionSupplement]
}

struct InsightSessionSupplement: Codable, Hashable, Sendable {
    let sessionDate: String
    let preSleep: InsightPreSleepSummary?
    let morning: InsightMorningSummary?
    let medications: [InsightMedicationSummary]
}

struct InsightPreSleepSummary: Codable, Hashable, Sendable {
    let sessionId: String?
    let completionState: String
    let loggedAtUTC: String
    let stressLevel: Int?
    let stressDrivers: [String]
    let laterReason: String?
    let bodyPain: String?
    let caffeineSources: [String]
    let alcohol: String?
    let exercise: String?
    let napToday: String?
    let lateMeal: String?
    let screensInBed: String?
    let roomTemp: String?
    let noiseLevel: String?
    let sleepAids: [String]
    let notes: String?
}

struct InsightMorningSummary: Codable, Hashable, Sendable {
    let submittedAtUTC: Date
    let sleepQuality: Int
    let feelRested: String
    let grogginess: String
    let sleepInertiaDuration: String
    let dreamRecall: String
    let mentalClarity: Int
    let mood: String
    let anxietyLevel: String
    let stressLevel: Int?
    let stressDrivers: [String]
    let readinessForDay: Int
    let hadSleepParalysis: Bool
    let hadHallucinations: Bool
    let hadAutomaticBehavior: Bool
    let fellOutOfBed: Bool
    let hadConfusionOnWaking: Bool
    let notes: String?
}

struct InsightMedicationSummary: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let medicationId: String
    let doseMg: Int
    let doseUnit: String
    let formulation: String
    let takenAtUTC: Date
    let notes: String?
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
    let preSleep: InsightPreSleepSummary?
    let morning: InsightMorningSummary?
    let medications: [InsightMedicationSummary]

    var intervalMinutes: Int? {
        guard let dose1Time, let dose2Time else { return nil }
        let delta = Int(dose2Time.timeIntervalSince(dose1Time) / 60)
        return delta >= 0 ? delta : nil
    }

    var eventCount: Int {
        events.count
    }

    var medicationCount: Int {
        medications.count
    }

    var preSleepStressLevel: Int? {
        preSleep?.stressLevel
    }

    var morningSleepQuality: Int? {
        morning?.sleepQuality
    }

    var morningReadiness: Int? {
        morning?.readinessForDay
    }

    var hasSupplementalContext: Bool {
        preSleep != nil || morning != nil || !medications.isEmpty
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
        if morning == nil {
            flags.append("Missing morning check-in")
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
