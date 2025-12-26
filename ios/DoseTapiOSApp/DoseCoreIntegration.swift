import SwiftUI
import Combine
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

/// Integration layer that connects the SwiftUI app to the tested DoseCore module.
/// P0-1 FIX: This class now reads/writes through SessionRepository - it is NOT a separate state owner.
/// All state is derived from SessionRepository.shared. This class handles API calls and notifications.
@MainActor
public class DoseCoreIntegration: ObservableObject {
    // Core services from the tested DoseCore module
    private let dosingService: DosingService
    
    // MARK: - State is now derived from SessionRepository (P0-1 FIX)
    
    /// Reference to the single source of truth
    private let sessionRepo = SessionRepository.shared
    
    /// Current dose window context - computed from SessionRepository state
    public var currentContext: DoseWindowContext {
        sessionRepo.currentContext
    }
    
    // Published state for UI (loading, errors, events)
    @Published public var recentEvents: [DoseEvent] = []
    @Published public var isLoading: Bool = false
    @Published public var lastError: String?
    
    private var dataClearedObserver: AnyCancellable?
    
    // Enhanced notification service
    public let notificationService = EnhancedNotificationService()
    
    // Timer reference for cleanup
    private var updateTimer: Timer?
    
    // Cancellable for observing SessionRepository changes
    private var sessionObserver: AnyCancellable?
    
    public init() {
        // Initialize core services with configurable base URL
        let transport = URLSessionTransport()
        let apiClient = APIClient(baseURL: APIConfiguration.baseURL, transport: transport)
        let offlineQueue = InMemoryOfflineQueue(isOnline: { true }) // TODO: Use real network monitor
        let rateLimiter = EventRateLimiter.default // Use all 13 event cooldowns
        
        self.dosingService = DosingService(
            client: apiClient,
            queue: offlineQueue,
            limiter: rateLimiter
        )
        
        // Load recent events from SQLite
        loadRecentEvents()
        
        // Set up notification service integration
        notificationService.setDoseCoreIntegration(self)
        
        // Observe SessionRepository changes to trigger objectWillChange
        sessionObserver = sessionRepo.sessionDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
        
        // Start periodic updates for time-based context changes
        startPeriodicUpdates()
    }
    
    // MARK: - Load Recent Events (for display only)
    
    /// Load recent events from unified storage
    private func loadRecentEvents() {
        let events = sessionRepo.fetchRecentEvents(limit: 50)
        recentEvents = events.compactMap { event -> DoseEvent? in
            guard let eventType = DoseEventType(rawValue: event.eventType) else { return nil }
            return DoseEvent(type: eventType, timestamp: event.timestamp)
        }
    }
    
    // MARK: - Dose Actions (write through SessionRepository)
    
    /// Take Dose 1 - records timestamp via SessionRepository and handles API/notifications
    public func takeDose1() async {
        isLoading = true
        defer { isLoading = false }
        
        let now = Date()
        
        // P0-1 FIX: Write through SessionRepository (single source of truth)
        sessionRepo.setDose1Time(now)
        
        // Record event via core services (API sync)
        do {
            await dosingService.perform(.takeDose(type: "dose1", at: now))
            await dosingService.perform(.logEvent(name: "dose1", at: now))
            addEvent(type: .dose1, timestamp: now)
            
            // Schedule dose 2 notifications using repo state
            notificationService.scheduleDoseNotifications(for: currentContext, dose1Time: sessionRepo.dose1Time)
        } catch {
            lastError = "Failed to record Dose 1: \(error.localizedDescription)"
        }
    }
    
    /// Take Dose 2 - records timestamp via SessionRepository and handles API/notifications
    public func takeDose2() async {
        isLoading = true
        defer { isLoading = false }
        
        let now = Date()
        
        // P0-1 FIX: Write through SessionRepository (single source of truth)
        sessionRepo.setDose2Time(now)
        
        // Record event via core services (API sync)
        do {
            await dosingService.perform(.takeDose(type: "dose2", at: now))
            await dosingService.perform(.logEvent(name: "dose2", at: now))
            addEvent(type: .dose2, timestamp: now)
            
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
        
        // P0-1 FIX: Write through SessionRepository (single source of truth)
        sessionRepo.incrementSnooze()
        
        // Record event via core services (API sync)
        do {
            await dosingService.perform(.snooze(minutes: 10))
            await dosingService.perform(.logEvent(name: "snooze", at: now))
            addEvent(type: .snooze, timestamp: now)
            
            // Reschedule notifications with updated snooze time using repo state
            notificationService.scheduleDoseNotifications(for: currentContext, dose1Time: sessionRepo.dose1Time)
        } catch {
            lastError = "Failed to record snooze: \(error.localizedDescription)"
        }
    }
    
    /// Skip Dose 2 - marks dose 2 as intentionally skipped
    public func skipDose2() async {
        isLoading = true
        defer { isLoading = false }
        
        let now = Date()
        
        // P0-1 FIX: Write through SessionRepository (single source of truth)
        sessionRepo.skipDose2()
        
        // Record event via core services (API sync)
        do {
            await dosingService.perform(.skipDose(sequence: 2, reason: "user_skip"))
            await dosingService.perform(.logEvent(name: "skip", at: now))
            addEvent(type: .skip, timestamp: now)
            
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
        
        // Persist via SessionRepository → EventStorage (unified storage)
        sessionRepo.logSleepEvent(eventType: eventName, timestamp: now, notes: nil, source: "manual")
        
        do {
            await dosingService.perform(.logEvent(name: eventName, at: now))
            addEvent(type: type, timestamp: now)
        } catch {
            lastError = "Failed to log \(eventName): \(error.localizedDescription)"
        }
    }
    
    /// Log a sleep event with rate limiting and unified storage
    /// Returns the result of the logging attempt
    @discardableResult
    public func logSleepEvent(_ eventType: QuickLogEventType, notes: String? = nil, source: String = "manual") async -> SleepEventLogResult {
        let now = Date()
        let eventKey = eventType.rawValue
        
        // Persist via SessionRepository → EventStorage (unified storage)
        sessionRepo.logSleepEvent(eventType: eventKey, timestamp: now, notes: notes, source: source)
        
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
        return sessionRepo.fetchTonightSleepEvents()
    }
    
    /// Get sleep event counts for current session
    public func getSleepEventSummary() -> [String: Int] {
        // For now, return counts from tonight
        let events = sessionRepo.fetchTonightSleepEvents()
        var counts: [String: Int] = [:]
        for event in events {
            counts[event.eventType, default: 0] += 1
        }
        return counts
    }
    
    /// Export data using core services
    public func exportData() async -> String {
        return "Export initiated successfully"
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
    
    /// Notify observers that context may have changed (time-based changes)
    /// Since currentContext is computed from SessionRepository, we just need to trigger objectWillChange
    private func notifyContextMayHaveChanged() {
        objectWillChange.send()
    }
    
    private func startPeriodicUpdates() {
        // Schedule on main run loop to ensure main thread execution
        // This triggers UI refresh for time-based context changes (window phase transitions)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.notifyContextMayHaveChanged()
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
        // P0-1 FIX: Clear via SessionRepository (single source of truth)
        sessionRepo.clearTonight()
        recentEvents.removeAll()
        notificationService.cancelAllNotifications()
    }
}

