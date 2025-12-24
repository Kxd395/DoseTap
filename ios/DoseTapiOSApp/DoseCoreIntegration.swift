import Foundation
import SwiftUI
import DoseCore

// MARK: - Configuration
/// API configuration - loads from Info.plist or uses defaults
public struct APIConfiguration {
    public static var baseURL: URL {
        // Try to load from Info.plist first
        if let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: urlString) {
            return url
        }
        // Fall back to default (can be overridden in scheme environment variables)
        if let envURL = ProcessInfo.processInfo.environment["DOSETAP_API_URL"],
           let url = URL(string: envURL) {
            return url
        }
        // Default for development - this should be configured per environment
        #if DEBUG
        return URL(string: "https://api-dev.dosetap.com")!
        #else
        return URL(string: "https://api.dosetap.com")!
        #endif
    }
}

/// Integration layer that connects the SwiftUI app to the tested DoseCore module
@MainActor
public class DoseCoreIntegration: ObservableObject {
    // Core services from the tested DoseCore module
    private let dosingService: DosingService
    private let windowCalculator: DoseWindowCalculator
    
    // SQLite storage for persistence (accessed lazily)
    private var _storage: SQLiteStorage?
    private var storage: SQLiteStorage {
        if _storage == nil {
            _storage = SQLiteStorage.shared
        }
        return _storage!
    }
    
    // Published state for SwiftUI
    @Published public var currentContext: DoseWindowContext
    @Published public var recentEvents: [DoseEvent] = []
    @Published public var isLoading: Bool = false
    @Published public var lastError: String?
    
    // Enhanced notification service
    public let notificationService = EnhancedNotificationService()
    
    // Dose tracking state (persisted to SQLite)
    private var dose1Time: Date?
    private var dose2Time: Date?
    private var snoozeCount: Int = 0
    private var dose2Skipped: Bool = false
    
    // Timer reference for cleanup
    private var updateTimer: Timer?
    
    // Notification observer for data cleared
    private var dataClearedObserver: NSObjectProtocol?
    
    public init() {
        // Initialize core services with configurable base URL
        let transport = URLSessionTransport()
        let apiClient = APIClient(baseURL: APIConfiguration.baseURL, transport: transport)
        let offlineQueue = InMemoryOfflineQueue(isOnline: { true }) // TODO: Use real network monitor
        let rateLimiter = EventRateLimiter.default // Use all 12 event cooldowns
        
        self.dosingService = DosingService(
            client: apiClient,
            queue: offlineQueue,
            limiter: rateLimiter
        )
        
        self.windowCalculator = DoseWindowCalculator()
        
        // Load persisted state from SQLite
        loadPersistedState()
        
        // Initialize context with loaded state
        self.currentContext = windowCalculator.context(
            dose1At: dose1Time, 
            dose2TakenAt: dose2Time, 
            dose2Skipped: dose2Skipped, 
            snoozeCount: snoozeCount
        )
        
        // Load recent events from SQLite
        loadRecentEvents()
        
        // Set up notification service integration
        notificationService.setDoseCoreIntegration(self)
        
        // Start periodic updates
        startPeriodicUpdates()
        
        // Listen for data cleared notification to reset in-memory state
        dataClearedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DataCleared"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetSession()
            print("✅ DoseCoreIntegration: Session reset after data cleared")
        }
    }
    
    // MARK: - Persistence
    
    /// Load persisted dose state from SQLite
    private func loadPersistedState() {
        // Load tonight's session if it exists
        let sessions = storage.fetchSessions(limit: 1)
        if let session = sessions.first, Calendar.current.isDateInToday(session.startTime) {
            dose1Time = session.dose1Time
            dose2Time = session.dose2Time
            snoozeCount = session.snoozeCount
            dose2Skipped = session.dose2Skipped
        } else {
            // No active session for today - check if we need to create one
            // (Will be created when user takes Dose 1)
            dose1Time = nil
            dose2Time = nil
            snoozeCount = 0
            dose2Skipped = false
        }
    }
    
    /// Load recent events from SQLite
    private func loadRecentEvents() {
        let events = storage.fetchEvents(limit: 50)
        recentEvents = events.compactMap { event -> DoseEvent? in
            guard let eventType = DoseEventType(rawValue: event.type) else { return nil }
            return DoseEvent(type: eventType, timestamp: event.timestamp)
        }
    }
    
    /// Persist current session state to SQLite
    private func persistSessionState() {
        guard let d1 = dose1Time else { return }
        
        let session = DoseSession(
            startTime: d1,
            dose1Time: d1,
            dose2Time: dose2Time,
            snoozeCount: snoozeCount,
            dose2Skipped: dose2Skipped
        )
        storage.insertSession(session)
    }
    
    /// Take Dose 1 - records timestamp and updates window state
    public func takeDose1() async {
        isLoading = true
        defer { isLoading = false }
        
        let now = Date()
        dose1Time = now
        
        // Persist to SQLite
        storage.insertEvent(EventRecord(type: "dose1", timestamp: now, metadata: nil))
        persistSessionState()
        
        // Record event via core services
        do {
            await dosingService.perform(.takeDose(type: "dose1", at: now))
            await dosingService.perform(.logEvent(name: "dose1", at: now))
            addEvent(type: .dose1, timestamp: now)
            updateContext()
            
            // Schedule dose 2 notifications
            notificationService.scheduleDoseNotifications(for: currentContext, dose1Time: dose1Time)
        } catch {
            lastError = "Failed to record Dose 1: \(error.localizedDescription)"
        }
    }
    
    /// Take Dose 2 - records timestamp and updates window state
    public func takeDose2() async {
        isLoading = true
        defer { isLoading = false }
        
        let now = Date()
        dose2Time = now
        
        // Persist to SQLite
        storage.insertEvent(EventRecord(type: "dose2", timestamp: now, metadata: nil))
        persistSessionState()
        
        // Record event via core services
        do {
            await dosingService.perform(.takeDose(type: "dose2", at: now))
            await dosingService.perform(.logEvent(name: "dose2", at: now))
            addEvent(type: .dose2, timestamp: now)
            updateContext()
            
            // Cancel remaining notifications since dose 2 was taken
            notificationService.cancelAllNotifications()
        } catch {
            lastError = "Failed to record Dose 2: \(error.localizedDescription)"
        }
    }
    
    /// Snooze - adds 10 minutes to target if allowed
    public func snooze() async {
        guard currentContext.snoozeEnabled else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        let now = Date()
        snoozeCount += 1
        
        // Persist to SQLite
        storage.insertEvent(EventRecord(type: "snooze", timestamp: now, metadata: "{\"count\":\(snoozeCount)}"))
        persistSessionState()
        
        // Record snooze via core services
        do {
            await dosingService.perform(.snooze(minutes: 10))
            await dosingService.perform(.logEvent(name: "snooze", at: now))
            addEvent(type: .snooze, timestamp: now)
            updateContext()
            
            // Reschedule notifications with updated snooze time
            notificationService.scheduleDoseNotifications(for: currentContext, dose1Time: dose1Time)
        } catch {
            lastError = "Failed to record snooze: \(error.localizedDescription)"
        }
    }
    
    /// Skip Dose 2 - marks dose 2 as intentionally skipped
    public func skipDose2() async {
        isLoading = true
        defer { isLoading = false }
        
        let now = Date()
        dose2Skipped = true
        
        // Persist to SQLite
        storage.insertEvent(EventRecord(type: "skip", timestamp: now, metadata: "{\"reason\":\"user_skip\"}"))
        persistSessionState()
        
        // Record skip via core services
        do {
            await dosingService.perform(.skipDose(sequence: 2, reason: "user_skip"))
            await dosingService.perform(.logEvent(name: "skip", at: now))
            addEvent(type: .skip, timestamp: now)
            updateContext()
            
            // Cancel remaining notifications since dose 2 was skipped
            notificationService.cancelAllNotifications()
        } catch {
            lastError = "Failed to record skip: \(error.localizedDescription)"
        }
    }
    
    /// Log adjunct event (bathroom, lights out, etc.)
    public func logEvent(type: DoseEventType) async {
        isLoading = true
        defer { isLoading = false }
        
        let now = Date()
        let eventName = type.rawValue
        
        // Persist to SQLite
        storage.insertEvent(EventRecord(type: eventName, timestamp: now, metadata: nil))
        
        do {
            await dosingService.perform(.logEvent(name: eventName, at: now))
            addEvent(type: type, timestamp: now)
        } catch {
            lastError = "Failed to log \(eventName): \(error.localizedDescription)"
        }
    }
    
    /// Log a sleep event with rate limiting and SQLite persistence
    /// Returns the result of the logging attempt
    @discardableResult
    public func logSleepEvent(_ eventType: QuickLogEventType, notes: String? = nil, source: String = "manual") async -> SleepEventLogResult {
        let now = Date()
        let eventKey = eventType.rawValue
        
        // Check rate limit using the dosingService's limiter
        // Note: We use the QuickLogViewModel's own rate limiter for UI state
        // This is just for API/storage consistency
        
        // Create the sleep event record
        let sleepEvent = StoredSleepEvent(
            id: UUID().uuidString,
            eventType: eventKey,
            timestamp: now,
            sessionId: nil, // TODO: Link to current session ID
            notes: notes,
            source: source
        )
        
        // Persist to sleep_events table
        storage.insertSleepEvent(sleepEvent)
        
        // Also log via core services for API sync
        do {
            await dosingService.perform(.logEvent(name: eventKey, at: now))
        } catch {
            // Non-blocking: event is already persisted locally
            print("API sync failed for sleep event: \(error)")
        }
        
        return .success(timestamp: now, eventType: eventKey)
    }
    
    /// Get tonight's sleep events for display
    public func getTonightSleepEvents() -> [StoredSleepEvent] {
        return storage.fetchTonightSleepEvents()
    }
    
    /// Get sleep event counts for current session
    public func getSleepEventSummary() -> [String: Int] {
        // For now, return counts from tonight
        let events = storage.fetchTonightSleepEvents()
        var counts: [String: Int] = [:]
        for event in events {
            counts[event.eventType, default: 0] += 1
        }
        return counts
    }
    
    /// Export data using core services
    public func exportData() async -> String {
        do {
            // Use the analytics export endpoint from core
            await dosingService.perform(.exportAnalytics)
            return "Export initiated successfully"
        } catch {
            return "Export failed: \(error.localizedDescription)"
        }
    }
    
    /// Request notification permissions
    public func requestNotificationPermissions() async -> Bool {
        return await notificationService.requestPermissions()
    }
    
    // MARK: - Private Methods
    
    private func addEvent(type: DoseEventType, timestamp: Date) {
        let event = DoseEvent(type: type, timestamp: timestamp)
        recentEvents.insert(event, at: 0)
        
        // Keep only last 50 events for UI
        if recentEvents.count > 50 {
            recentEvents.removeLast()
        }
    }
    
    private func updateContext() {
        currentContext = windowCalculator.context(
            dose1At: dose1Time,
            dose2TakenAt: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount
        )
    }
    
    private func startPeriodicUpdates() {
        // Schedule on main run loop to ensure main thread execution
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            // Timer fires on main thread when scheduled on main run loop
            // But to be safe, ensure we're on MainActor
            Task { @MainActor [weak self] in
                self?.updateContext()
            }
        }
        // Ensure timer runs on main run loop
        if let timer = updateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    /// Call this when done with the integration to clean up resources
    public func cleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Remove data cleared observer
        if let observer = dataClearedObserver {
            NotificationCenter.default.removeObserver(observer)
            dataClearedObserver = nil
        }
    }
    
    /// Reset current session (useful for testing or starting fresh)
    public func resetSession() {
        dose1Time = nil
        dose2Time = nil
        snoozeCount = 0
        dose2Skipped = false
        recentEvents.removeAll()
        updateContext()
        notificationService.cancelAllNotifications()
    }
}

// MARK: - Event Model for UI
public struct DoseEvent: Identifiable, Equatable {
    public let id = UUID()
    public let type: DoseEventType
    public let timestamp: Date
    
    public init(type: DoseEventType, timestamp: Date) {
        self.type = type
        self.timestamp = timestamp
    }
}

public enum DoseEventType: String, CaseIterable {
    case dose1 = "dose1"
    case dose2 = "dose2"
    case snooze = "snooze"
    case skip = "skip"
    case bathroom = "bathroom"
    case lightsOut = "lights_out"
    case wakeFinal = "wake_final"
}

/// Result of a sleep event logging attempt
public enum SleepEventLogResult {
    case success(timestamp: Date, eventType: String)
    case rateLimited(remainingSeconds: Int)
    case error(String)
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
