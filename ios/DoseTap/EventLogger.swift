import SwiftUI
import Combine
import DoseCore
import UIKit
import os.log

let appLogger = Logger(subsystem: "com.dosetap.app", category: "UI")

// MARK: - Shared Event Logger (Observable with SQLite persistence)
@MainActor
class EventLogger: ObservableObject {
    static let shared = EventLogger()
    
    @Published var events: [LoggedEvent] = []
    @Published var cooldowns: [String: Date] = [:]
    
    private let sessionRepo = SessionRepository.shared
    private var sessionChangeCancellable: AnyCancellable?
    
    private init() {
        // Load persisted events from SQLite on startup
        loadEventsFromStorage()
        
        // Refresh events when session changes (rollover/delete)
        sessionChangeCancellable = SessionRepository.shared.sessionDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.loadEventsFromStorage()
            }
    }
    
    /// Load events from SQLite for tonight's session
    private func loadEventsFromStorage() {
        let storedEvents = sessionRepo.fetchTonightSleepEvents()
        events = storedEvents.map { stored in
            LoggedEvent(
                id: UUID(uuidString: stored.id) ?? UUID(),
                name: Self.displayName(forEventType: stored.eventType),
                time: stored.timestamp,
                color: stored.colorHex.flatMap { Color(hex: $0) } ?? .gray
            )
        }
        appLogger.debug("Loaded \(self.events.count) events from SQLite")
    }
    
    func logEvent(
        name: String,
        color: Color,
        cooldownSeconds: TimeInterval,
        persist: Bool = true,
        notes: String? = nil,
        eventTypeOverride: String? = nil
    ) {
        let now = Date()
        let cooldownKey = Self.canonicalEventType(name)
        let persistedEventType = eventTypeOverride ?? cooldownKey
        
        // Check cooldown
        if let end = cooldowns[cooldownKey], now < end {
            return // Still in cooldown
        }
        
        // Create and add event
        let eventId = UUID()
        let event = LoggedEvent(id: eventId, name: name, time: now, color: color)
        events.insert(event, at: 0)
        
        // Set cooldown
        cooldowns[cooldownKey] = now.addingTimeInterval(cooldownSeconds)
        
        if persist {
            // Persist to SQLite via SessionRepository
            sessionRepo.insertSleepEvent(
                id: eventId.uuidString,
                eventType: persistedEventType,
                timestamp: now,
                colorHex: color.toHex(),
                notes: notes
            )
        }
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    func isOnCooldown(_ name: String) -> Bool {
        guard let end = cooldowns[Self.canonicalEventType(name)] else { return false }
        return Date() < end
    }
    
    func cooldownEnd(for name: String) -> Date? {
        cooldowns[Self.canonicalEventType(name)]
    }
    
    /// Clear cooldown for a specific event (for undo)
    func clearCooldown(for name: String) {
        let cooldownKey = Self.canonicalEventType(name)
        cooldowns.removeValue(forKey: cooldownKey)
        // Also remove the event from the in-memory list
        events.removeAll { Self.canonicalEventType($0.name) == cooldownKey }
    }
    
    /// Delete a specific event by ID
    func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
        sessionRepo.deleteSleepEvent(id: id.uuidString)
    }
    
    /// Refresh events from storage
    func refresh() {
        loadEventsFromStorage()
    }
    
    /// Clear tonight's events
    func clearTonight() {
        events.removeAll()
        cooldowns.removeAll()
        sessionRepo.clearTonightsEvents()
    }

    private static func canonicalEventType(_ raw: String) -> String {
        EventType(raw).canonicalString
    }

    private static func displayName(forEventType raw: String) -> String {
        EventType(raw).displayName
    }
}

// MARK: - Logged Event Model
struct LoggedEvent: Identifiable {
    let id: UUID
    let name: String
    let time: Date
    let color: Color
    
    init(id: UUID = UUID(), name: String, time: Date, color: Color) {
        self.id = id
        self.name = name
        self.time = time
        self.color = color
    }

    static func fromDoseEvent(_ event: DoseCore.StoredDoseEvent) -> LoggedEvent? {
        let (displayName, color) = DoseEventDisplay.displayNameAndColor(for: event)
        return LoggedEvent(
            id: UUID(uuidString: event.id) ?? UUID(),
            name: displayName,
            time: event.timestamp,
            color: color
        )
    }
}

// MARK: - Dose Event Display Helpers
enum DoseEventDisplay {
    static func displayNameAndColor(for event: DoseCore.StoredDoseEvent) -> (String, Color) {
        switch event.eventType {
        case "dose1":
            return ("Dose 1", .blue)
        case "dose2":
            return ("Dose 2", .green)
        case "extra_dose":
            return ("Extra Dose", .orange)
        case "snooze":
            return ("Snooze", .yellow)
        case "skip":
            return ("Dose Skipped", .orange)
        default:
            return (event.eventType.replacingOccurrences(of: "_", with: " ").capitalized, .gray)
        }
    }
}

enum EventDisplayName {
    static func displayName(for eventType: String) -> String {
        switch eventType {
        case "bathroom": return "Bathroom"
        case "water": return "Water"
        case "lightsOut", "lights_out": return "Lights Out"
        case "inBed", "in_bed": return "In Bed"
        case "wakeFinal", "wake_final": return "Wake Up"
        case "wakeTemp", "wake_temp": return "Brief Wake"
        case "anxiety": return "Anxiety"
        case "pain": return "Pain"
        case "noise": return "Noise"
        case "snack": return "Snack"
        case "dream": return "Dream"
        case "temperature": return "Temperature"
        case "heartRacing", "heart_racing": return "Heart Racing"
        default:
            return eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
