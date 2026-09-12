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
    
    @Published var saveError: String?
    private var retryWrite: (() -> Void)?
    var canRetryFailedEvent: Bool { retryWrite != nil }
    private let sessionRepo: SessionRepository
    private let clock: () -> Date
    private var sessionChangeCancellable: AnyCancellable?
    
    init(sessionRepo: SessionRepository = .shared, clock: @escaping () -> Date = Date.init) {
        self.sessionRepo = sessionRepo
        self.clock = clock
        // Load persisted events from SQLite on startup
        loadEventsFromStorage()
        
        // Refresh events when session changes (rollover/delete)
        sessionChangeCancellable = sessionRepo.sessionDidChange
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
    
    @discardableResult
    func logEvent(name: String, color: Color, cooldownSeconds: TimeInterval, persist: Bool = true,
                  notes: String? = nil, eventTypeOverride: String? = nil) -> Bool {
        if persist && retryWrite != nil { return false }
        let now = clock(), key = Self.canonicalEventType(name)
        if let end = cooldowns[key], now < end { return false }
        let id = UUID(), identity = sessionRepo.currentSessionIdString()
        func failed(_ logger: EventLogger) -> Bool {
            if logger.sessionRepo.currentSessionIdString() != identity {
                logger.retryWrite = nil
                logger.saveError = "Session changed. \(name) at \(now.formatted(date: .abbreviated, time: .shortened)) was not saved. Review it in History."
            } else {
                logger.saveError = "\(name) not saved. Retry keeps the original time."
            }
            return false
        }
        func commit(_ logger: EventLogger) -> Bool {
            if persist {
                guard logger.sessionRepo.currentSessionIdString() == identity else { return failed(logger) }
                guard logger.sessionRepo.insertSleepEvent(id: id.uuidString, eventType: eventTypeOverride ?? key,
                    timestamp: now, colorHex: color.toHex(), notes: notes, expectedSessionId: identity) else { return failed(logger) }
            }
            logger.events.insert(LoggedEvent(id: id, name: name, time: now, color: color), at: 0)
            logger.cooldowns[key] = logger.clock().addingTimeInterval(cooldownSeconds)
            if persist { logger.saveError = nil; logger.retryWrite = nil }
            Haptics.action.play()
            return true
        }
        if commit(self) { return true }
        if sessionRepo.currentSessionIdString() == identity {
            retryWrite = { [weak self] in guard let self else { return }; _ = commit(self) }
        }
        return false
    }

    func retryFailedEvent() { retryWrite?() }
    func discardFailedEvent() { retryWrite = nil; saveError = nil; sessionRepo.sleepEventSaveError = nil }

    func isOnCooldown(_ name: String) -> Bool {
        guard let end = cooldowns[Self.canonicalEventType(name)] else { return false }
        return clock() < end
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

    /// Delete a specific event and return a snapshot that can be used to restore it
    /// via `restoreDeletedEvent(_:)`. Returns nil if no stored event matches.
    /// Intended for the undo-delete flow.
    func deleteEventReturningSnapshot(id: UUID) -> DeletedEventSnapshot? {
        let stored = sessionRepo.fetchTonightSleepEvents().first { $0.id == id.uuidString }
        let logged = events.first { $0.id == id }
        guard stored != nil || logged != nil else { return nil }

        let eventType: String
        let displayName: String
        let timestamp: Date
        let colorHex: String?
        let notes: String?
        if let stored {
            eventType = stored.eventType
            displayName = Self.displayName(forEventType: stored.eventType)
            timestamp = stored.timestamp
            colorHex = stored.colorHex
            notes = stored.notes
        } else if let logged {
            eventType = Self.canonicalEventType(logged.name)
            displayName = logged.name
            timestamp = logged.time
            colorHex = logged.color.toHex()
            notes = nil
        } else {
            return nil
        }

        deleteEvent(id: id)

        return DeletedEventSnapshot(
            id: id.uuidString,
            eventType: eventType,
            displayName: displayName,
            timestamp: timestamp,
            colorHex: colorHex,
            notes: notes
        )
    }

    /// Restore a previously deleted event from a snapshot. No-op if an event
    /// with the same id already exists.
    @discardableResult
    func restoreDeletedEvent(_ snapshot: DeletedEventSnapshot) -> Bool {
        guard let uuid = UUID(uuidString: snapshot.id) else { return false }
        if events.contains(where: { $0.id == uuid }) { return true }

        guard sessionRepo.insertSleepEvent(
            id: snapshot.id,
            eventType: snapshot.eventType,
            timestamp: snapshot.timestamp,
            colorHex: snapshot.colorHex,
            notes: snapshot.notes
        ) else { return false }

        let color = snapshot.colorHex.flatMap { Color(hex: $0) } ?? .gray
        let restored = LoggedEvent(id: uuid, name: snapshot.displayName, time: snapshot.timestamp, color: color)
        events.insert(restored, at: 0)
        events.sort { $0.time > $1.time }
        return true
    }

    /// Manually log an event at a specific date+time (for retroactive entry)
    @discardableResult
    func logManualEvent(eventType: String, color: Color, timestamp: Date) -> Bool {
        let eventId = UUID()
        let displayName = EventType(eventType).displayName
        let event = LoggedEvent(id: eventId, name: displayName, time: timestamp, color: color)

        guard sessionRepo.insertSleepEvent(
            id: eventId.uuidString,
            eventType: eventType,
            timestamp: timestamp,
            colorHex: color.toHex(),
            notes: "manual"
        ) else { return false }
        events.insert(event, at: 0)

        Haptics.action.play()
        return true
    }

    /// Update the time for an existing event
    func updateEventTime(id: UUID, newTime: Date) {
        sessionRepo.updateEventTime(eventId: id.uuidString, newTime: newTime)
        loadEventsFromStorage()
    }

    /// Update notes on an existing event. Pass nil or empty string to clear.
    func updateEventNotes(id: UUID, notes: String?) {
        sessionRepo.updateEventNotes(eventId: id.uuidString, notes: notes)
        loadEventsFromStorage()
    }

    /// Fetch the underlying StoredSleepEvent for a LoggedEvent ID (for edit sheets)
    func storedEvent(for id: UUID) -> StoredSleepEvent? {
        sessionRepo.fetchTonightSleepEvents().first { $0.id == id.uuidString }
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

    /// Last time a given event type was logged tonight. Used for "time since" badges (P3-4).
    func lastEventTime(for name: String) -> Date? {
        let canonical = Self.canonicalEventType(name)
        return events.first { Self.canonicalEventType($0.name) == canonical }?.time
    }

    /// Human-readable relative time: "just now", "3m ago", "1h ago", or nil if >12h / never.
    static func relativeBadge(since date: Date?) -> String? {
        guard let date = date else { return nil }
        let seconds = Date().timeIntervalSince(date)
        guard seconds >= 0, seconds < 12 * 3600 else { return nil }
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
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
        // Route through EventType which normalises all raw variants
        // (e.g. "lightsout", "lights_out", "lightsOut" → .lightsOut)
        let parsed = EventType(eventType)
        if case .unknown = parsed {
            // Fallback for truly unknown strings
            return eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return parsed.displayName
    }
}

struct QuickLogSaveStatus: View {
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var repository: SessionRepository
    var body: some View {
        if let message = eventLogger.saveError ?? repository.sleepEventSaveError {
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.callout).accessibilityIdentifier("quick-log-save-error")
                HStack {
                    if eventLogger.canRetryFailedEvent {
                        Button("Retry entry") { eventLogger.retryFailedEvent() }
                    }
                    Button(eventLogger.canRetryFailedEvent ? "Discard entry" : "Dismiss", role: .cancel) { eventLogger.discardFailedEvent() }
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
        }
    }
}
