import DoseCore
import Foundation

/// Event types matching SSOT CSV v1 specification
enum EventType: String, Codable, CaseIterable {
    case dose1_taken = "dose1_taken"
    case dose2_taken = "dose2_taken"
    case dose2_skipped = "dose2_skipped"
    case dose2_snoozed = "dose2_snoozed"
    case bathroom = "bathroom"
    case undo = "undo"
    case snooze = "snooze"
    case lights_out = "lights_out"
    case wake_final = "wake_final"
    case app_opened = "app_opened"
    case notification_received = "notification_received"

    init?(csvValue: String) {
        switch Self.normalized(csvValue) {
        case "dose1", "dose_1", "dose1_taken", "dose_1_taken":
            self = .dose1_taken
        case "dose2", "dose_2", "dose2_taken", "dose_2_taken":
            self = .dose2_taken
        case "dose2_skipped", "dose_2_skipped":
            self = .dose2_skipped
        case "dose2_snoozed", "dose_2_snoozed":
            self = .dose2_snoozed
        case "bathroom":
            self = .bathroom
        case "undo":
            self = .undo
        case "snooze":
            self = .snooze
        case "lightsout", "lights_out", "lights out":
            self = .lights_out
        case "wakefinal", "wake_final", "wake final":
            self = .wake_final
        case "appopened", "app_opened", "app opened":
            self = .app_opened
        case "notificationreceived", "notification_received", "notification received":
            self = .notification_received
        default:
            return nil
        }
    }

    private static func normalized(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }
}

/// Dose event model matching SSOT CSV v1 schema
/// Header: event_type,occurred_at_utc,details,device_time
struct DoseEvent: Codable, Identifiable {
    let id = UUID()
    let eventType: EventType
    let occurredAtUTC: Date
    let details: String?
    let deviceTime: String?
    
    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case occurredAtUTC = "occurred_at_utc"
        case details = "details"
        case deviceTime = "device_time"
    }
}

/// Dose session model matching sessions.csv schema  
/// Header: started_utc,ended_utc,window_target_min,window_actual_min,adherence_flag,whoop_recovery,avg_hr,sleep_efficiency,notes
struct DoseSession: Codable, Identifiable {
    let id = UUID()
    let startedUTC: Date
    let endedUTC: Date?
    let windowTargetMin: Int
    let windowActualMin: Int?
    let adherenceFlag: String?
    let whoopRecovery: Int?
    let avgHR: Double?
    let sleepEfficiency: Double?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case startedUTC = "started_utc"
        case endedUTC = "ended_utc"
        case windowTargetMin = "window_target_min"
        case windowActualMin = "window_actual_min"
        case adherenceFlag = "adherence_flag"
        case whoopRecovery = "whoop_recovery"
        case avgHR = "avg_hr"
        case sleepEfficiency = "sleep_efficiency"
        case notes = "notes"
    }
}

/// Inventory snapshot model matching inventory.csv schema
/// The legacy six CSV columns are followed by optional stored identity/provenance.
struct InventorySnapshot: Codable, Identifiable {
    let id = UUID()
    var sourceRecordId: String? = nil
    var medicationName: String? = nil
    var createdAtStoredUTC: String? = nil
    var source: String? = nil
    let asOfUTC: Date
    let bottlesRemaining: Int
    let dosesRemaining: Int
    let estimatedDaysLeft: Int?
    let nextRefillDate: Date?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case sourceRecordId = "id"
        case medicationName = "medication_name"
        case createdAtStoredUTC = "created_at_stored_utc"
        case source
        case asOfUTC = "as_of_utc"
        case bottlesRemaining = "bottles_remaining"
        case dosesRemaining = "doses_remaining"
        case estimatedDaysLeft = "estimated_days_left"
        case nextRefillDate = "next_refill_date"
        case notes = "notes"
    }
}

struct StudioNightAggregate: Identifiable {
    let id: String            // yyyy-MM-dd
    let dose1: Date?
    let dose2: Date?
    let dose2Skipped: Bool
    let intervalMinutes: Int?
    let eventCount: Int
    let bathroomEvents: Int
    let lightsOutEvents: Int
    let wakeFinalEvents: Int
    let sleepEfficiency: Double?
    let whoopRecovery: Int?
    let avgHR: Double?
    let totalSleepMinutes: Double?
    let wakeDisruptionCount: Int?
    let hrvMs: Double?

    var onTimeFlag: Bool? {
        guard let dose1, let dose2 else { return nil }
        return MedicationTiming.classify(dose1: dose1, dose2: dose2) == .inWindow
    }

    var completenessScore: Double {
        var score = 0.0
        if dose1 != nil && (dose2 != nil || dose2Skipped) { score += 0.4 }
        if sleepEfficiency != nil { score += 0.3 }
        if eventCount > 0 { score += 0.3 }
        return score
    }

    var qualityFlags: [String] {
        var flags: [String] = []
        if dose1 != nil && dose2 == nil && !dose2Skipped {
            flags.append("Dose 2 outcome missing")
        }
        if lightsOutEvents > 1 {
            flags.append("Duplicate lights-out logs")
        }
        return flags
    }
}

/// Descriptive timing from recorded pairs. Missing observations never enter the denominator.
struct StudioDoseTimingSummary {
    let pairCount: Int
    let inWindowPercent: Double?
    let averageMinutes: Double?

    init(intervalSeconds: [Double?]) {
        let valid = intervalSeconds.compactMap { $0 }.filter { MedicationTiming.classify(elapsedSeconds: $0) != .invalid }
        pairCount = valid.count
        inWindowPercent = valid.isEmpty ? nil : Double(valid.filter { MedicationTiming.classify(elapsedSeconds: $0) == .inWindow }.count) / Double(valid.count) * 100
        averageMinutes = valid.isEmpty ? nil : valid.reduce(0) { $0 + $1 / Double(valid.count) / 60 }
    }
}

/// Computed analytics for dashboard display
struct DoseTapAnalytics {
    let totalEvents: Int
    let totalSessions: Int
    let adherenceRate30d: Double?
    let averageWindow30d: Double?
    let timingPairCount30d: Int
    let missedDoses30d: Int
    let averageRecovery30d: Double?
    let averageHR30d: Double?
    let averageSleepEfficiency30d: Double?
    let averageTotalSleepMinutes30d: Double?
    let averageHRV30d: Double?
    let healthKitNightCount30d: Int
    let whoopNightCount30d: Int
    let averageEventsPerNight30d: Double
    let qualityIssueNights30d: Int
    let highConfidenceNights30d: Int
    let nights: [StudioNightAggregate]

    static let empty = DoseTapAnalytics(
        totalEvents: 0,
        totalSessions: 0,
        adherenceRate30d: nil,
        averageWindow30d: nil,
        timingPairCount30d: 0,
        missedDoses30d: 0,
        averageRecovery30d: nil,
        averageHR30d: nil,
        averageSleepEfficiency30d: nil,
        averageTotalSleepMinutes30d: nil,
        averageHRV30d: nil,
        healthKitNightCount30d: 0,
        whoopNightCount30d: 0,
        averageEventsPerNight30d: 0,
        qualityIssueNights30d: 0,
        highConfidenceNights30d: 0,
        nights: []
    )

    var adherenceStatusText: String {
        timingPairCount30d == 0 ? "No recorded pairs in the last 30 days" : "150–240 min inclusive · n = \(timingPairCount30d) pairs"
    }

    var windowStatusText: String {
        timingPairCount30d == 0 ? "No recorded pairs in the last 30 days" : "Recorded intervals · n = \(timingPairCount30d) pairs"
    }
}
