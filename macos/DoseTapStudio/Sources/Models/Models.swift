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
/// Header: as_of_utc,bottles_remaining,doses_remaining,estimated_days_left,next_refill_date,notes
struct InventorySnapshot: Codable, Identifiable {
    let id = UUID()
    let asOfUTC: Date
    let bottlesRemaining: Int
    let dosesRemaining: Int
    let estimatedDaysLeft: Int?
    let nextRefillDate: Date?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
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

    var onTimeFlag: Bool? {
        guard let intervalMinutes else { return nil }
        return (150...240).contains(intervalMinutes)
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

/// Computed analytics for dashboard display
struct DoseTapAnalytics {
    let totalEvents: Int
    let totalSessions: Int
    let adherenceRate30d: Double
    let averageWindow30d: Double
    let missedDoses30d: Int
    let averageRecovery30d: Double?
    let averageHR30d: Double?
    let averageSleepEfficiency30d: Double?
    let averageEventsPerNight30d: Double
    let qualityIssueNights30d: Int
    let highConfidenceNights30d: Int
    let nights: [StudioNightAggregate]

    static let empty = DoseTapAnalytics(
        totalEvents: 0,
        totalSessions: 0,
        adherenceRate30d: 0,
        averageWindow30d: 0,
        missedDoses30d: 0,
        averageRecovery30d: nil,
        averageHR30d: nil,
        averageSleepEfficiency30d: nil,
        averageEventsPerNight30d: 0,
        qualityIssueNights30d: 0,
        highConfidenceNights30d: 0,
        nights: []
    )

    var adherenceStatusText: String {
        switch adherenceRate30d {
        case 95...100: return "Excellent (>=95%)"
        case 85..<95: return "Good (85-94%)"
        case 70..<85: return "Fair (70-84%)"
        default: return "Needs Attention (<70%)"
        }
    }

    var windowStatusText: String {
        switch averageWindow30d {
        case 150...180: return "Optimal Window"
        case 181...210: return "Good Window"
        case 211...240: return "Late Window"
        default: return averageWindow30d < 150 ? "Early Window" : "Missed Window"
        }
    }
}
