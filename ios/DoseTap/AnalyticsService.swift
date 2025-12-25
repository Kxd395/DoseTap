import Foundation

/// Analytics Service for tracking user events and app metrics
/// Dispatches events to configured providers (local storage, remote API)
///
/// Event naming follows SSOT conventions:
/// - Domain prefix: dose_, event_, session_, ui_, error_
/// - Snake_case format
/// - Includes relevant parameters
///
@MainActor
final class AnalyticsService: ObservableObject {
    
    static let shared = AnalyticsService()
    
    // MARK: - Configuration
    @Published var isEnabled: Bool = false
    @Published var debugLogging: Bool = false
    
    // MARK: - Event Queue
    private var eventQueue: [AnalyticsEvent] = []
    private let maxQueueSize = 100
    private let flushInterval: TimeInterval = 60  // Flush every 60 seconds
    
    // MARK: - Providers
    private var providers: [AnalyticsProvider] = []
    
    // MARK: - Event Names per SSOT
    
    enum EventName: String {
        // Dose Events
        case dose1Taken = "dose_1_taken"
        case dose2Taken = "dose_2_taken"
        case dose2Skipped = "dose_2_skipped"
        case doseUndone = "dose_undone"
        case snoozeActivated = "dose_snooze_activated"
        case windowOpened = "dose_window_opened"
        case windowClosed = "dose_window_closed"
        case windowExceeded = "dose_window_exceeded"
        
        // Sleep Events
        case eventBathroom = "event_bathroom"
        case eventLightsOut = "event_lights_out"
        case eventWakeFinal = "event_wake_final"
        case eventBriefWake = "event_brief_wake"
        case eventDream = "event_dream"
        case eventAnxiety = "event_anxiety"
        case eventNoise = "event_noise"
        case eventTemperature = "event_temperature"
        case eventPain = "event_pain"
        case eventHeartRacing = "event_heart_racing"
        case eventWater = "event_water"
        case eventSnack = "event_snack"
        
        // Session Events
        case sessionStarted = "session_started"
        case sessionCompleted = "session_completed"
        case sessionAbandoned = "session_abandoned"
        case checkInCompleted = "session_checkin_completed"
        case checkInSkipped = "session_checkin_skipped"
        
        // UI Events
        case tabViewed = "ui_tab_viewed"
        case settingsChanged = "ui_settings_changed"
        case exportRequested = "ui_export_requested"
        case exportCompleted = "ui_export_completed"
        case deepLinkOpened = "ui_deep_link_opened"
        case notificationTapped = "ui_notification_tapped"
        case notificationDismissed = "ui_notification_dismissed"
        
        // Integration Events
        case healthKitAuthorized = "integration_healthkit_authorized"
        case healthKitDenied = "integration_healthkit_denied"
        case healthKitSyncCompleted = "integration_healthkit_sync"
        case whoopConnected = "integration_whoop_connected"
        case whoopDisconnected = "integration_whoop_disconnected"
        case flicPaired = "integration_flic_paired"
        case flicUnpaired = "integration_flic_unpaired"
        case flicGestureReceived = "integration_flic_gesture"
        case watchConnected = "integration_watch_connected"
        case watchDisconnected = "integration_watch_disconnected"
        
        // Error Events
        case errorApiFailure = "error_api_failure"
        case errorNetworkTimeout = "error_network_timeout"
        case errorParsingFailure = "error_parsing"
        case errorStorageFailure = "error_storage"
        case errorNotificationFailure = "error_notification"
        
        // Performance Events
        case appLaunched = "perf_app_launched"
        case appBackgrounded = "perf_app_backgrounded"
        case appForegrounded = "perf_app_foregrounded"
        case coldStartDuration = "perf_cold_start_ms"
    }
    
    // MARK: - Event Model
    
    struct AnalyticsEvent: Codable {
        let id: UUID
        let name: String
        let timestamp: Date
        let parameters: [String: AnyCodable]
        let sessionId: String?
        let userId: String?
        let deviceType: String
        let appVersion: String
        
        init(
            name: EventName,
            parameters: [String: Any] = [:],
            sessionId: String? = nil
        ) {
            self.id = UUID()
            self.name = name.rawValue
            self.timestamp = Date()
            self.parameters = parameters.mapValues { AnyCodable($0) }
            self.sessionId = sessionId
            self.userId = nil  // Future: user identification
            self.deviceType = Self.currentDeviceType
            self.appVersion = Self.currentAppVersion
        }
        
        private static var currentDeviceType: String {
            #if os(iOS)
            return "ios"
            #elseif os(watchOS)
            return "watchos"
            #else
            return "unknown"
            #endif
        }
        
        private static var currentAppVersion: String {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        }
    }
    
    // MARK: - Type-Erased Codable Wrapper
    
    struct AnyCodable: Codable {
        let value: Any
        
        init(_ value: Any) {
            self.value = value
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            
            if let bool = try? container.decode(Bool.self) {
                value = bool
            } else if let int = try? container.decode(Int.self) {
                value = int
            } else if let double = try? container.decode(Double.self) {
                value = double
            } else if let string = try? container.decode(String.self) {
                value = string
            } else if let array = try? container.decode([AnyCodable].self) {
                value = array.map { $0.value }
            } else if let dict = try? container.decode([String: AnyCodable].self) {
                value = dict.mapValues { $0.value }
            } else {
                value = NSNull()
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            
            switch value {
            case let bool as Bool:
                try container.encode(bool)
            case let int as Int:
                try container.encode(int)
            case let double as Double:
                try container.encode(double)
            case let string as String:
                try container.encode(string)
            case let array as [Any]:
                try container.encode(array.map { AnyCodable($0) })
            case let dict as [String: Any]:
                try container.encode(dict.mapValues { AnyCodable($0) })
            default:
                try container.encodeNil()
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        isEnabled = UserSettingsManager.shared.analyticsEnabled
        setupProviders()
        startFlushTimer()
    }
    
    private func setupProviders() {
        // Local file provider for development
        providers.append(LocalFileAnalyticsProvider())
        
        // Console provider for debug builds
        #if DEBUG
        providers.append(ConsoleAnalyticsProvider())
        #endif
        
        // Remote API provider (future)
        // providers.append(RemoteAnalyticsProvider())
    }
    
    private func startFlushTimer() {
        Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flush()
            }
        }
    }
    
    // MARK: - Public API
    
    /// Track an analytics event
    /// - Parameters:
    ///   - name: The event name from EventName enum
    ///   - parameters: Additional parameters for the event
    func track(_ name: EventName, parameters: [String: Any] = [:]) {
        guard isEnabled else { return }
        
        let sessionId = EventStorage.shared.sessionDateString(for: Date())
        let event = AnalyticsEvent(name: name, parameters: parameters, sessionId: sessionId)
        
        // Add to queue
        eventQueue.append(event)
        
        // Debug logging
        if debugLogging {
            print("📊 Analytics: \(name.rawValue) - \(parameters)")
        }
        
        // Flush if queue is full
        if eventQueue.count >= maxQueueSize {
            flush()
        }
    }
    
    /// Track a dose event with standard parameters
    func trackDose(_ name: EventName, doseType: Int, interval: Int? = nil, isEarly: Bool = false, isLate: Bool = false) {
        var params: [String: Any] = [
            "dose_type": doseType,
            "is_early": isEarly,
            "is_late": isLate
        ]
        if let interval = interval {
            params["interval_minutes"] = interval
        }
        track(name, parameters: params)
    }
    
    /// Track a sleep event with standard parameters
    func trackSleepEvent(_ name: EventName, minutesSinceDose1: Int? = nil) {
        var params: [String: Any] = [:]
        if let minutes = minutesSinceDose1 {
            params["minutes_since_dose1"] = minutes
        }
        track(name, parameters: params)
    }
    
    /// Track an error event
    func trackError(_ name: EventName, error: Error, context: String? = nil) {
        var params: [String: Any] = [
            "error_message": error.localizedDescription,
            "error_type": String(describing: type(of: error))
        ]
        if let context = context {
            params["context"] = context
        }
        track(name, parameters: params)
    }
    
    /// Track a UI event
    func trackUI(_ name: EventName, screen: String? = nil, action: String? = nil) {
        var params: [String: Any] = [:]
        if let screen = screen {
            params["screen"] = screen
        }
        if let action = action {
            params["action"] = action
        }
        track(name, parameters: params)
    }
    
    /// Flush queued events to providers
    func flush() {
        guard !eventQueue.isEmpty else { return }
        
        let events = eventQueue
        eventQueue.removeAll()
        
        for provider in providers {
            provider.send(events: events)
        }
        
        if debugLogging {
            print("📊 Analytics: Flushed \(events.count) events")
        }
    }
    
    /// Clear all queued events
    func clearQueue() {
        eventQueue.removeAll()
    }
}

// MARK: - Analytics Providers

protocol AnalyticsProvider {
    func send(events: [AnalyticsService.AnalyticsEvent])
}

/// Console provider for debug logging
class ConsoleAnalyticsProvider: AnalyticsProvider {
    func send(events: [AnalyticsService.AnalyticsEvent]) {
        for event in events {
            print("📊 [\(event.timestamp.formatted(date: .omitted, time: .shortened))] \(event.name)")
        }
    }
}

/// Local file provider for offline storage
class LocalFileAnalyticsProvider: AnalyticsProvider {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documentsPath.appendingPathComponent("analytics_events.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    func send(events: [AnalyticsService.AnalyticsEvent]) {
        // Load existing events
        var allEvents = loadEvents()
        allEvents.append(contentsOf: events)
        
        // Keep only last 1000 events
        if allEvents.count > 1000 {
            allEvents = Array(allEvents.suffix(1000))
        }
        
        // Save back to file
        saveEvents(allEvents)
    }
    
    private func loadEvents() -> [AnalyticsService.AnalyticsEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let events = try? decoder.decode([AnalyticsService.AnalyticsEvent].self, from: data) else {
            return []
        }
        return events
    }
    
    private func saveEvents(_ events: [AnalyticsService.AnalyticsEvent]) {
        do {
            let data = try encoder.encode(events)
            try data.write(to: fileURL)
        } catch {
            print("❌ AnalyticsService: Failed to save events: \(error)")
        }
    }
    
    /// Export all stored events as JSON
    func exportEvents() -> Data? {
        return try? Data(contentsOf: fileURL)
    }
    
    /// Clear stored events
    func clearEvents() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Convenience Extensions

extension AnalyticsService {
    
    /// Track dose 1 taken
    func trackDose1Taken() {
        trackDose(.dose1Taken, doseType: 1)
    }
    
    /// Track dose 2 taken with interval
    func trackDose2Taken(intervalMinutes: Int, isEarly: Bool = false, isLate: Bool = false) {
        trackDose(.dose2Taken, doseType: 2, interval: intervalMinutes, isEarly: isEarly, isLate: isLate)
    }
    
    /// Track dose 2 skipped
    func trackDose2Skipped(reason: String) {
        track(.dose2Skipped, parameters: ["skip_reason": reason])
    }
    
    /// Track snooze
    func trackSnooze(snoozeCount: Int, remainingMinutes: Int) {
        track(.snoozeActivated, parameters: [
            "snooze_count": snoozeCount,
            "remaining_minutes": remainingMinutes
        ])
    }
    
    /// Track session completion
    func trackSessionCompleted(dose1To2Interval: Int?, wasoCount: Int, bathroomCount: Int) {
        var params: [String: Any] = [
            "waso_count": wasoCount,
            "bathroom_count": bathroomCount
        ]
        if let interval = dose1To2Interval {
            params["dose1_to_2_interval"] = interval
        }
        track(.sessionCompleted, parameters: params)
    }
    
    /// Track tab view
    func trackTabView(tabName: String) {
        trackUI(.tabViewed, screen: tabName)
    }
    
    /// Track deep link
    func trackDeepLink(url: String, action: String?) {
        track(.deepLinkOpened, parameters: [
            "url": url,
            "action": action ?? "unknown"
        ])
    }
    
    /// Track Flic gesture
    func trackFlicGesture(gesture: String, action: String, success: Bool) {
        track(.flicGestureReceived, parameters: [
            "gesture": gesture,
            "action": action,
            "success": success
        ])
    }
}

#if DEBUG
// MARK: - Preview/Debug Helpers

extension AnalyticsService {
    /// Generate sample events for testing
    func generateTestEvents() {
        track(.appLaunched, parameters: ["cold_start": true])
        trackDose1Taken()
        trackSleepEvent(.eventBathroom, minutesSinceDose1: 45)
        trackDose2Taken(intervalMinutes: 175, isEarly: false, isLate: false)
        trackSessionCompleted(dose1To2Interval: 175, wasoCount: 2, bathroomCount: 1)
        flush()
    }
}
#endif
