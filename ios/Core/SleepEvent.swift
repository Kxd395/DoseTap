import Foundation

/// Sleep-related event types that can be logged during a dose session
/// Per SSOT: Events help correlate sleep behaviors with dose timing
public enum SleepEventType: String, Codable, Sendable, CaseIterable {
    case bathroom       // Bathroom visit during sleep
    case inBed          // Got into bed (may not be sleeping yet)
    case lightsOut      // User turned off lights / going to sleep
    case wakeFinal      // Final wake (morning)
    case wakeTemp       // Temporary wake (not final)
    case snack          // Late snack before bed
    case water          // Drank water
    case anxiety        // Anxiety/restlessness
    case dream          // Notable dream (for patterns)
    case noise          // External noise disturbance
    case temperature    // Temperature discomfort
    case pain           // Pain/discomfort
    case heartRacing    // Heart racing sensation
    
    /// SF Symbol name for UI display
    public var iconName: String {
        switch self {
        case .bathroom:     return "toilet.fill"
        case .inBed:        return "bed.double.fill"
        case .lightsOut:    return "light.max"
        case .wakeFinal:    return "sun.max.fill"
        case .wakeTemp:     return "moon.zzz.fill"
        case .snack:        return "fork.knife"
        case .water:        return "drop.fill"
        case .anxiety:      return "brain.head.profile"
        case .dream:        return "cloud.moon.fill"
        case .noise:        return "speaker.wave.3.fill"
        case .temperature:  return "thermometer.medium"
        case .pain:         return "bandage.fill"
        case .heartRacing:  return "heart.fill"
        }
    }
    
    /// Default cooldown in seconds to prevent rapid duplicate logging
    /// Per SSOT constants.json: Only physical events have cooldowns to prevent accidental double-taps
    /// Mental/environment events have NO cooldown - log as many times as needed
    public var defaultCooldownSeconds: TimeInterval {
        switch self {
        // Physical events - 60s cooldown to prevent accidental double-tap
        case .bathroom:     return 60
        case .water:        return 60
        case .snack:        return 60
        // Sleep cycle markers - no cooldown (session markers)
        case .inBed:        return 0
        case .lightsOut:    return 0
        case .wakeFinal:    return 0
        case .wakeTemp:     return 0
        // Mental events - no cooldown (log as often as experienced)
        case .anxiety:      return 0
        case .dream:        return 0
        case .heartRacing:  return 0
        // Environment events - no cooldown (log as often as experienced)
        case .noise:        return 0
        case .temperature:  return 0
        case .pain:         return 0
        }
    }
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .bathroom:     return "Bathroom"
        case .inBed:        return "In Bed"
        case .lightsOut:    return "Lights Out"
        case .wakeFinal:    return "Wake Up"
        case .wakeTemp:     return "Brief Wake"
        case .snack:        return "Snack"
        case .water:        return "Water"
        case .anxiety:      return "Anxiety"
        case .dream:        return "Dream"
        case .noise:        return "Noise"
        case .temperature:  return "Temp"
        case .pain:         return "Pain"
        case .heartRacing:  return "Heart Racing"
        }
    }
    
    /// Category for grouping in UI
    public var category: SleepEventCategory {
        switch self {
        case .bathroom, .water, .snack:
            return .physical
        case .inBed, .lightsOut, .wakeFinal, .wakeTemp:
            return .sleepCycle
        case .anxiety, .dream, .heartRacing:
            return .mental
        case .noise, .temperature, .pain:
            return .environment
        }
    }
    
    /// All cooldowns as a dictionary for EventRateLimiter
    public static var allCooldowns: [String: TimeInterval] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0.defaultCooldownSeconds) })
    }
}

/// Categories for organizing event types in UI
public enum SleepEventCategory: String, Codable, Sendable, CaseIterable {
    case physical       // Body-related: bathroom, water, snack
    case sleepCycle     // Sleep state: lights out, wake
    case mental         // Mental state: anxiety, dreams
    case environment    // External: noise, temperature
    
    public var displayName: String {
        switch self {
        case .physical:     return "Physical"
        case .sleepCycle:   return "Sleep"
        case .mental:       return "Mental"
        case .environment:  return "Environment"
        }
    }
    
    public var iconName: String {
        switch self {
        case .physical:     return "figure.stand"
        case .sleepCycle:   return "bed.double.fill"
        case .mental:       return "brain"
        case .environment:  return "house.fill"
        }
    }
    
    /// Events belonging to this category
    public var events: [SleepEventType] {
        SleepEventType.allCases.filter { $0.category == self }
    }
}

/// A logged sleep event with timestamp and optional metadata
public struct SleepEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let type: SleepEventType
    public let timestamp: Date
    public let sessionId: UUID?      // Links to dose session if active
    public let notes: String?        // Optional user notes
    public let source: EventSource   // How event was logged
    
    public init(
        id: UUID = UUID(),
        type: SleepEventType,
        timestamp: Date = Date(),
        sessionId: UUID? = nil,
        notes: String? = nil,
        source: EventSource = .manual
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.notes = notes
        self.source = source
    }
    
    /// Source of how the event was logged
    public enum EventSource: String, Codable, Sendable {
        case manual     // User tapped button
        case watch      // watchOS companion
        case flic       // Flic button
        case siri       // Siri shortcut
        case automatic  // Auto-detected (e.g., motion sensor)
    }
}

/// Result of attempting to log an event
public enum SleepEventResult: Sendable {
    case logged(SleepEvent)
    case rateLimited(remainingSeconds: Int)
    case error(String)
    
    public var isSuccess: Bool {
        if case .logged = self { return true }
        return false
    }
}

/// Summary statistics for a sleep session's events
public struct SleepEventSummary: Sendable {
    public let totalEvents: Int
    public let bathroomCount: Int
    public let wakeCount: Int        // wakeTemp events
    public let firstEvent: Date?
    public let lastEvent: Date?
    public let eventsByType: [SleepEventType: Int]
    
    public init(events: [SleepEvent]) {
        self.totalEvents = events.count
        self.bathroomCount = events.filter { $0.type == .bathroom }.count
        self.wakeCount = events.filter { $0.type == .wakeTemp }.count
        self.firstEvent = events.map(\.timestamp).min()
        self.lastEvent = events.map(\.timestamp).max()
        
        var counts: [SleepEventType: Int] = [:]
        for event in events {
            counts[event.type, default: 0] += 1
        }
        self.eventsByType = counts
    }
}

// MARK: - Extensions for API Integration

extension SleepEvent {
    /// Convert to API request body
    public var apiBody: [String: Any] {
        var body: [String: Any] = [
            "id": id.uuidString,
            "type": type.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "source": source.rawValue
        ]
        if let sessionId = sessionId {
            body["session_id"] = sessionId.uuidString
        }
        if let notes = notes {
            body["notes"] = notes
        }
        return body
    }
}
