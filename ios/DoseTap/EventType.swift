import SwiftUI

// MARK: - Unified Event Type
/// Single source of truth for event type normalization, display names, and colors.
/// Replaces the 3 divergent normalization functions that existed before.
/// Uses `unknown(String)` for forward compatibility — new event types don't crash.
enum EventType: Hashable, Sendable {
    // Sleep session events
    case lightsOut
    case inBed
    case wakeFinal
    case wakeTemp
    case napStart
    case napEnd

    // Dose events
    case dose1
    case dose2
    case skipDose
    case snooze
    case extraDose

    // Quick-log / symptom events
    case bathroom
    case water
    case snack
    case pain
    case anxiety
    case noise
    case temperature
    case dream
    case heartRacing
    case congestion
    case grogginess

    // Session-level events
    case morningCheckIn
    case preSleepLog
    case wakeSurvey

    // Catch-all for unrecognized strings (forward-compatible)
    case unknown(String)

    // MARK: - Canonical String (for storage / API)
    var canonicalString: String {
        switch self {
        case .lightsOut:      return "lights_out"
        case .inBed:          return "in_bed"
        case .wakeFinal:      return "wake_final"
        case .wakeTemp:       return "wake_temp"
        case .napStart:       return "nap_start"
        case .napEnd:         return "nap_end"
        case .dose1:          return "dose1"
        case .dose2:          return "dose2"
        case .skipDose:       return "skip"
        case .snooze:         return "snooze"
        case .extraDose:      return "extra_dose"
        case .bathroom:       return "bathroom"
        case .water:          return "water"
        case .snack:          return "snack"
        case .pain:           return "pain"
        case .anxiety:        return "anxiety"
        case .noise:          return "noise"
        case .temperature:    return "temperature"
        case .dream:          return "dream"
        case .heartRacing:    return "heart_racing"
        case .congestion:     return "congestion"
        case .grogginess:     return "grogginess"
        case .morningCheckIn: return "morning_check_in"
        case .preSleepLog:    return "pre_sleep_log"
        case .wakeSurvey:     return "wake_survey"
        case .unknown(let s): return s
        }
    }

    // MARK: - Display Name
    var displayName: String {
        switch self {
        case .lightsOut:      return "Lights Out"
        case .inBed:          return "In Bed"
        case .wakeFinal:      return "Wake Up"
        case .wakeTemp:       return "Brief Wake"
        case .napStart:       return "Nap Start"
        case .napEnd:         return "Nap End"
        case .dose1:          return "Dose 1"
        case .dose2:          return "Dose 2"
        case .skipDose:       return "Skip Dose"
        case .snooze:         return "Snooze"
        case .extraDose:      return "Extra Dose"
        case .bathroom:       return "Bathroom"
        case .water:          return "Water"
        case .snack:          return "Snack"
        case .pain:           return "Pain"
        case .anxiety:        return "Anxiety"
        case .noise:          return "Noise"
        case .temperature:    return "Temperature"
        case .dream:          return "Dream"
        case .heartRacing:    return "Heart Racing"
        case .congestion:     return "Congestion"
        case .grogginess:     return "Grogginess"
        case .morningCheckIn: return "Morning Check-In"
        case .preSleepLog:    return "Pre-Sleep Log"
        case .wakeSurvey:     return "Wake Survey"
        case .unknown(let s):
            return s.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Display Color
    var displayColor: Color {
        switch self {
        case .lightsOut:      return .indigo
        case .inBed:          return .indigo
        case .wakeFinal:      return .yellow
        case .wakeTemp:       return .indigo
        case .napStart:       return .green
        case .napEnd:         return .orange
        case .dose1:          return .green
        case .dose2:          return .blue
        case .skipDose:       return .orange
        case .snooze:         return .yellow
        case .extraDose:      return .red
        case .bathroom:       return .blue
        case .water:          return .cyan
        case .snack:          return .orange
        case .pain:           return .red
        case .anxiety:        return .purple
        case .noise:          return .yellow
        case .temperature:    return .orange
        case .dream:          return .indigo
        case .heartRacing:    return .red
        case .congestion:     return .teal
        case .grogginess:     return .gray
        case .morningCheckIn: return .green
        case .preSleepLog:    return .purple
        case .wakeSurvey:     return .yellow
        case .unknown:        return .gray
        }
    }

    // MARK: - SF Symbol
    var sfSymbol: String {
        switch self {
        case .lightsOut:      return "moon.fill"
        case .inBed:          return "bed.double.fill"
        case .wakeFinal:      return "sun.max.fill"
        case .wakeTemp:       return "eye.fill"
        case .napStart:       return "zzz"
        case .napEnd:         return "alarm.fill"
        case .dose1:          return "1.circle.fill"
        case .dose2:          return "2.circle.fill"
        case .skipDose:       return "forward.fill"
        case .snooze:         return "clock.badge.fill"
        case .extraDose:      return "exclamationmark.triangle.fill"
        case .bathroom:       return "drop.fill"
        case .water:          return "cup.and.saucer.fill"
        case .snack:          return "fork.knife"
        case .pain:           return "bolt.fill"
        case .anxiety:        return "heart.fill"
        case .noise:          return "speaker.wave.3.fill"
        case .temperature:    return "thermometer.medium"
        case .dream:          return "cloud.fill"
        case .heartRacing:    return "heart.circle.fill"
        case .congestion:     return "nose.fill"
        case .grogginess:     return "cloud.fog.fill"
        case .morningCheckIn: return "sunrise.fill"
        case .preSleepLog:    return "moon.zzz.fill"
        case .wakeSurvey:     return "list.clipboard.fill"
        case .unknown:        return "questionmark.circle"
        }
    }

    // MARK: - Initialization from raw string
    /// The single normalization entry point. Handles all known variants,
    /// emoji shortcuts, and falls back to `unknown(String)` for anything else.
    init(_ raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        // Lights out variants
        case "lightsout", "lights_out", "🌙":
            self = .lightsOut

        // In bed
        case "inbed", "in_bed":
            self = .inBed

        // Wake final variants
        case "wakefinal", "wake_final", "wake", "wakeup", "wake_up", "☀️":
            self = .wakeFinal

        // Brief / temp wake
        case "waketemp", "wake_temp", "brief_wake":
            self = .wakeTemp

        // Nap
        case "napstart", "nap_start":
            self = .napStart
        case "napend", "nap_end":
            self = .napEnd

        // Dose events
        case "dose1", "dose_1":
            self = .dose1
        case "dose2", "dose_2":
            self = .dose2
        case "skip", "skip_dose", "skipped":
            self = .skipDose
        case "snooze":
            self = .snooze
        case "extra_dose", "extra_dose_taken":
            self = .extraDose

        // Quick-log events
        case "bathroom", "🚽":
            self = .bathroom
        case "water", "💧":
            self = .water
        case "snack", "🍿":
            self = .snack
        case "pain", "💊":
            self = .pain
        case "anxiety", "restless", "😰":
            self = .anxiety
        case "noise", "🔊":
            self = .noise
        case "temp", "temperature", "🌡️":
            self = .temperature
        case "dream", "💭":
            self = .dream
        case "heartracing", "heart_racing":
            self = .heartRacing
        case "congestion":
            self = .congestion
        case "grogginess":
            self = .grogginess

        // Session events
        case "morning_check_in", "morningcheckin":
            self = .morningCheckIn
        case "pre_sleep_log", "presleeplog":
            self = .preSleepLog
        case "wake_survey":
            self = .wakeSurvey

        default:
            self = .unknown(normalized)
        }
    }
}

// MARK: - Convenience
extension EventType: CustomStringConvertible {
    var description: String { canonicalString }
}

/// Drop-in replacement for the old `normalizeStoredEventType(_:)` free function.
/// Use `EventType(raw).canonicalString` directly when possible.
func normalizeStoredEventType(_ raw: String) -> String {
    EventType(raw).canonicalString
}
