import SwiftUI
import Foundation

/// Comprehensive error and edge case handling for DoseTap
/// Manages window exceeded, snooze limits, already taken doses, and other edge cases
@available(iOS 15.0, *)
@MainActor
class ErrorHandler: ObservableObject {
    @Published var currentError: DoseTapError?
    @Published var currentWarning: DoseTapWarning?
    @Published var showErrorAlert = false
    @Published var showWarningBanner = false
    
    private let eventStoreAdapter: EventStoreAdapter
    private let timeEngine = TimeEngine()
    private let snoozeController = SnoozeController()
    
    init(eventStoreAdapter: EventStoreAdapter) {
        self.eventStoreAdapter = eventStoreAdapter
    }
    
    // MARK: - Public Interface
    
    /// Validate and handle dose logging with comprehensive error checking
    /// - Parameters:
    ///   - type: The dose event type to log
    ///   - timestamp: Optional timestamp (defaults to now)
    /// - Returns: Success status and any error details
    func validateAndLogDose(type: DoseEvent.EventType, at timestamp: Date = Date()) async -> (success: Bool, error: DoseTapError?) {
        // Clear previous errors
        currentError = nil
        currentWarning = nil
        
        // Get current events
        let events = await eventStoreAdapter.shared.all()
        
        // Perform validation based on dose type
        switch type {
        case .dose1:
            return await validateFirstDose(events: events, timestamp: timestamp)
        case .dose2:
            return await validateSecondDose(events: events, timestamp: timestamp)
        case .snooze:
            return await validateSnooze(events: events, timestamp: timestamp)
        case .bathroom, .lights_out, .wake_final:
            // These events have minimal validation
            return await logEventSafely(type: type, timestamp: timestamp)
        }
    }
    
    /// Check for window state and provide warnings
    /// - Parameter events: Current event list
    /// - Returns: Any warnings about the current state
    func checkWindowWarnings(events: [DoseEvent]) -> DoseTapWarning? {
        guard let dose1Event = events.last(where: { $0.type == .dose1 }) else {
            return nil
        }
        
        let windowState = timeEngine.state(dose1At: dose1Event.utcTs)
        
        switch windowState {
        case .waitingForTarget(let remaining):
            if remaining < 300 { // 5 minutes
                return .windowOpeningSoon(remaining)
            }
        case .targetWindowOpen(_, let remainingToMax):
            if remainingToMax < 600 { // 10 minutes
                return .windowClosingSoon(remainingToMax)
            }
        case .windowExceeded:
            return .windowExceeded
        case .noDose1:
            break
        }
        
        return nil
    }
    
    /// Present error to user with appropriate UI
    /// - Parameter error: The error to present
    func presentError(_ error: DoseTapError) {
        currentError = error
        showErrorAlert = true
        
        // Log error for analytics/debugging
        logError(error)
    }
    
    /// Present warning to user with banner
    /// - Parameter warning: The warning to present
    func presentWarning(_ warning: DoseTapWarning) {
        currentWarning = warning
        showWarningBanner = true
        
        // Auto-dismiss warning after delay
        Task {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            await MainActor.run {
                if currentWarning == warning { // Only dismiss if it's still the same warning
                    dismissWarning()
                }
            }
        }
    }
    
    /// Dismiss current warning
    func dismissWarning() {
        currentWarning = nil
        showWarningBanner = false
    }
    
    /// Clear all errors and warnings
    func clearAll() {
        currentError = nil
        currentWarning = nil
        showErrorAlert = false
        showWarningBanner = false
    }
    
    // MARK: - Private Validation Methods
    
    private func validateFirstDose(events: [DoseEvent], timestamp: Date) async -> (success: Bool, error: DoseTapError?) {
        // Check if first dose already taken today
        let todayStart = Calendar.current.startOfDay(for: timestamp)
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
        
        let todayDose1 = events.first { event in
            event.type == .dose1 && 
            event.utcTs >= todayStart && 
            event.utcTs < todayEnd
        }
        
        if todayDose1 != nil {
            let error = DoseTapError.dose1AlreadyTaken(at: todayDose1!.utcTs)
            presentError(error)
            return (false, error)
        }
        
        // Check if timestamp is reasonable (not too far in past/future)
        let now = Date()
        let maxPastHours: TimeInterval = 12 * 60 * 60 // 12 hours
        let maxFutureMinutes: TimeInterval = 30 * 60 // 30 minutes
        
        if timestamp < now.addingTimeInterval(-maxPastHours) {
            let error = DoseTapError.timestampTooOld(timestamp)
            presentError(error)
            return (false, error)
        }
        
        if timestamp > now.addingTimeInterval(maxFutureMinutes) {
            let error = DoseTapError.timestampTooFuture(timestamp)
            presentError(error)
            return (false, error)
        }
        
        // Log the dose
        return await logEventSafely(type: .dose1, timestamp: timestamp)
    }
    
    private func validateSecondDose(events: [DoseEvent], timestamp: Date) async -> (success: Bool, error: DoseTapError?) {
        // Find most recent first dose
        guard let dose1Event = events.last(where: { $0.type == .dose1 }) else {
            let error = DoseTapError.noDose1ForDose2
            presentError(error)
            return (false, error)
        }
        
        // Check if second dose already taken for this cycle
        let dose2EventsAfterDose1 = events.filter { event in
            event.type == .dose2 && event.utcTs > dose1Event.utcTs
        }
        
        if !dose2EventsAfterDose1.isEmpty {
            let error = DoseTapError.dose2AlreadyTaken(at: dose2EventsAfterDose1.first!.utcTs)
            presentError(error)
            return (false, error)
        }
        
        // Check window state
        let windowState = timeEngine.state(dose1At: dose1Event.utcTs)
        
        switch windowState {
        case .noDose1:
            let error = DoseTapError.noDose1ForDose2
            presentError(error)
            return (false, error)
            
        case .waitingForTarget(let remaining):
            // Allow with warning if close to target
            if remaining > 300 { // More than 5 minutes early
                let error = DoseTapError.dose2TooEarly(remaining)
                presentError(error)
                return (false, error)
            } else {
                // Show warning but allow
                let warning = DoseTapWarning.dose2SlightlyEarly(remaining)
                presentWarning(warning)
            }
            
        case .windowExceeded:
            // Allow with warning
            let warning = DoseTapWarning.dose2Late
            presentWarning(warning)
            
        case .targetWindowOpen:
            // Perfect timing, no warnings needed
            break
        }
        
        // Log the dose
        return await logEventSafely(type: .dose2, timestamp: timestamp)
    }
    
    private func validateSnooze(events: [DoseEvent], timestamp: Date) async -> (success: Bool, error: DoseTapError?) {
        guard let dose1Event = events.last(where: { $0.type == .dose1 }) else {
            let error = DoseTapError.noActiveDoseForSnooze
            presentError(error)
            return (false, error)
        }
        
        // Check if dose2 already taken
        let dose2Taken = events.contains { event in
            event.type == .dose2 && event.utcTs > dose1Event.utcTs
        }
        
        if dose2Taken {
            let error = DoseTapError.cannotSnoozeAfterDose2
            presentError(error)
            return (false, error)
        }
        
        // Use snooze controller validation
        let result = snoozeController.snooze(dose1At: dose1Event.utcTs, dose2Taken: dose2Taken)
        
        if !result.success {
            let error = DoseTapError.snoozeRejected(result.rejectionReason!)
            presentError(error)
            return (false, error)
        }
        
        // Log the snooze
        return await logEventSafely(type: .snooze, timestamp: timestamp)
    }
    
    private func logEventSafely(type: DoseEvent.EventType, timestamp: Date) async -> (success: Bool, error: DoseTapError?) {
        do {
            let _ = await eventStoreAdapter.log(type: type, at: timestamp)
            return (true, nil)
        } catch {
            let doseTapError = DoseTapError.eventLoggingFailed(error.localizedDescription)
            presentError(doseTapError)
            return (false, doseTapError)
        }
    }
    
    private func logError(_ error: DoseTapError) {
        // In a real app, this would send to analytics/crash reporting
        print("DoseTap Error: \(error.localizedDescription)")
    }
}

// MARK: - Error Types

enum DoseTapError: LocalizedError, Equatable {
    case dose1AlreadyTaken(at: Date)
    case dose2AlreadyTaken(at: Date)
    case noDose1ForDose2
    case dose2TooEarly(TimeInterval)
    case noActiveDoseForSnooze
    case cannotSnoozeAfterDose2
    case snoozeRejected(SnoozeController.RejectionReason)
    case timestampTooOld(Date)
    case timestampTooFuture(Date)
    case eventLoggingFailed(String)
    case networkUnavailable
    case storageError(String)
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .dose1AlreadyTaken(let date):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "First dose already taken today at \(formatter.string(from: date))"
            
        case .dose2AlreadyTaken(let date):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Second dose already taken at \(formatter.string(from: date))"
            
        case .noDose1ForDose2:
            return "Cannot take second dose without taking first dose"
            
        case .dose2TooEarly(let remaining):
            let minutes = Int(remaining / 60)
            return "Second dose window opens in \(minutes) minutes"
            
        case .noActiveDoseForSnooze:
            return "No active dose timer to snooze"
            
        case .cannotSnoozeAfterDose2:
            return "Cannot snooze after second dose is taken"
            
        case .snoozeRejected(let reason):
            return "Cannot snooze: \(reason.userMessage)"
            
        case .timestampTooOld(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "Timestamp \(formatter.string(from: date)) is too old"
            
        case .timestampTooFuture(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "Timestamp \(formatter.string(from: date)) is too far in the future"
            
        case .eventLoggingFailed(let message):
            return "Failed to log event: \(message)"
            
        case .networkUnavailable:
            return "Network connection unavailable"
            
        case .storageError(let message):
            return "Storage error: \(message)"
            
        case .rateLimitExceeded:
            return "Too many requests. Please wait a moment."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .dose1AlreadyTaken:
            return "Check your dose history or reset if needed"
            
        case .dose2AlreadyTaken:
            return "Check your dose history to confirm timing"
            
        case .noDose1ForDose2:
            return "Take your first dose before taking the second dose"
            
        case .dose2TooEarly:
            return "Wait for the target window to open, or take now with reduced effectiveness"
            
        case .noActiveDoseForSnooze:
            return "Take your first dose to start the timer"
            
        case .cannotSnoozeAfterDose2:
            return "The dose cycle is complete - no snoozing needed"
            
        case .snoozeRejected:
            return "Check the timing and try again later"
            
        case .timestampTooOld, .timestampTooFuture:
            return "Use a more recent timestamp or current time"
            
        case .eventLoggingFailed:
            return "Check your connection and try again"
            
        case .networkUnavailable:
            return "Check your internet connection"
            
        case .storageError:
            return "Restart the app or check available storage"
            
        case .rateLimitExceeded:
            return "Wait 30 seconds before trying again"
        }
    }
}

// MARK: - Warning Types

enum DoseTapWarning: Equatable {
    case windowOpeningSoon(TimeInterval)
    case windowClosingSoon(TimeInterval)
    case windowExceeded
    case dose2SlightlyEarly(TimeInterval)
    case dose2Late
    case backgroundRefreshDisabled
    case notificationsDisabled
    
    var message: String {
        switch self {
        case .windowOpeningSoon(let remaining):
            let minutes = Int(remaining / 60)
            return "Target window opens in \(minutes) minutes"
            
        case .windowClosingSoon(let remaining):
            let minutes = Int(remaining / 60)
            return "Window closes in \(minutes) minutes"
            
        case .windowExceeded:
            return "Optimal window has passed"
            
        case .dose2SlightlyEarly(let remaining):
            let minutes = Int(remaining / 60)
            return "Taking \(minutes) minutes before target window"
            
        case .dose2Late:
            return "Taking dose after optimal window"
            
        case .backgroundRefreshDisabled:
            return "Enable background refresh for accurate timing"
            
        case .notificationsDisabled:
            return "Enable notifications for dose reminders"
        }
    }
    
    var severity: WarningSeverity {
        switch self {
        case .windowOpeningSoon, .windowClosingSoon:
            return .info
        case .dose2SlightlyEarly, .dose2Late:
            return .medium
        case .windowExceeded:
            return .high
        case .backgroundRefreshDisabled, .notificationsDisabled:
            return .medium
        }
    }
}

enum WarningSeverity {
    case info
    case medium
    case high
    
    var color: Color {
        switch self {
        case .info:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }
}

// MARK: - Extension for SnoozeController

extension SnoozeController.RejectionReason {
    var userMessage: String {
        switch self {
        case .dose1Required:
            return "Take first dose to start timer"
        case .snoozeCapReached:
            return "Maximum snoozes reached"
        case .windowClosed:
            return "Dose window has closed"
        case .dose2Taken:
            return "Second dose already taken"
        }
    }
}
