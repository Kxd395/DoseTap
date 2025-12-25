import Foundation
import Combine
import UserNotifications
import DoseCore
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Session Repository
/// Single source of truth for session state. UI should bind to this, not DoseTapCore directly.
/// All mutations flow through here and automatically notify observers.

@MainActor
public final class SessionRepository: ObservableObject {
    
    // MARK: - Singleton
    public static let shared = SessionRepository()
    
    // MARK: - Published State (UI binds to these)
    @Published public private(set) var activeSessionDate: String?
    @Published public private(set) var dose1Time: Date?
    @Published public private(set) var dose2Time: Date?
    @Published public private(set) var snoozeCount: Int = 0
    @Published public private(set) var dose2Skipped: Bool = false
    
    /// Emits whenever session data changes (for observers that need explicit signal)
    public let sessionDidChange = PassthroughSubject<Void, Never>()
    
    // MARK: - Dependencies
    private let storage: EventStorage
    
    // MARK: - Initialization
    
    /// Initialize with default shared storage
    public convenience init() {
        self.init(storage: EventStorage.shared)
    }
    
    /// Initialize with injected storage (for testing)
    public init(storage: EventStorage) {
        self.storage = storage
        reload()
    }
    
    // MARK: - Load / Reload
    
    /// Reload active session state from storage
    public func reload() {
        let currentDate = storage.currentSessionDate()
        let (d1, d2, snooze, skipped) = storage.loadCurrentSession()
        
        // Only set activeSessionDate if there's actual data
        if d1 != nil || d2 != nil || snooze > 0 || skipped {
            activeSessionDate = currentDate
        } else {
            activeSessionDate = nil
        }
        
        dose1Time = d1
        dose2Time = d2
        snoozeCount = snooze
        dose2Skipped = skipped
        
        sessionDidChange.send()
        
        print("📊 SessionRepository reloaded: session=\(activeSessionDate ?? "none"), dose1=\(d1?.description ?? "nil"), dose2=\(d2?.description ?? "nil")")
    }
    
    // MARK: - Mutations
    
    /// Delete a session by date string. If it's the active session, clears state.
    /// Also cancels any pending notifications for the session.
    public func deleteSession(sessionDate: String) {
        let wasActiveSession = (sessionDate == activeSessionDate) || 
                               (sessionDate == storage.currentSessionDate())
        
        // Delete from storage
        storage.deleteSession(sessionDate: sessionDate)
        
        // If we deleted the active session, clear in-memory state AND cancel notifications
        if wasActiveSession {
            activeSessionDate = nil
            dose1Time = nil
            dose2Time = nil
            snoozeCount = 0
            dose2Skipped = false
            
            // P0-3 FIX: Cancel any pending notifications for this session
            // Notifications should not fire for deleted sessions
            cancelPendingNotifications()
            
            print("🗑️ SessionRepository: Active session deleted, state and notifications cleared")
        } else {
            print("🗑️ SessionRepository: Inactive session \(sessionDate) deleted, active state preserved")
        }
        
        sessionDidChange.send()
    }
    
    /// Cancel all pending dose-related notifications
    /// Called when active session is deleted to prevent orphan notifications
    private func cancelPendingNotifications() {
        let notificationCenter = UNUserNotificationCenter.current()
        
        // Cancel all pending dose notifications
        // These identifiers match those used in EnhancedNotificationService
        let notificationIDs = [
            "dose_reminder",
            "window_opening",
            "window_closing",
            "window_critical",
            "wake_alarm",
            "wake_alarm_pre",
            "wake_alarm_follow1",
            "wake_alarm_follow2",
            "wake_alarm_follow3",
            "hard_stop",
            "hard_stop_5min",
            "hard_stop_2min",
            "hard_stop_30sec",
            "hard_stop_expired"
        ]
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: notificationIDs)
        print("🔕 SessionRepository: Cancelled pending notifications for deleted session")
    }
    
    /// Record dose 1 time
    public func setDose1Time(_ time: Date) {
        dose1Time = time
        activeSessionDate = storage.currentSessionDate()
        
        // Persist to storage
        storage.saveDose1(timestamp: time)
        
        sessionDidChange.send()
    }
    
    /// Record dose 2 time
    public func setDose2Time(_ time: Date, isEarly: Bool = false, isExtraDose: Bool = false) {
        if !isExtraDose {
            dose2Time = time
        }
        
        // Persist to storage
        storage.saveDose2(timestamp: time, isEarly: isEarly, isExtraDose: isExtraDose)
        
        sessionDidChange.send()
    }
    
    /// Increment snooze count
    public func incrementSnooze() {
        snoozeCount += 1
        
        // Persist to storage
        storage.saveSnooze(count: snoozeCount)
        
        sessionDidChange.send()
    }
    
    /// Mark dose 2 as skipped
    public func skipDose2() {
        dose2Skipped = true
        
        // Persist to storage
        storage.saveDoseSkipped()
        
        sessionDidChange.send()
    }
    
    /// Clear tonight's session (for reset/testing)
    public func clearTonight() {
        let currentDate = storage.currentSessionDate()
        storage.deleteSession(sessionDate: currentDate)
        
        activeSessionDate = nil
        dose1Time = nil
        dose2Time = nil
        snoozeCount = 0
        dose2Skipped = false
        
        sessionDidChange.send()
    }
    
    // MARK: - Queries
    
    /// Check if a given session date is the active/current session
    public func isActiveSession(_ sessionDate: String) -> Bool {
        return sessionDate == storage.currentSessionDate()
    }
    
    /// Get the current session date string (based on 6PM boundary)
    public func currentSessionDateString() -> String {
        return storage.currentSessionDate()
    }
    
    // MARK: - Computed Context (for UI binding)
    
    /// Lazily initialized window calculator for context computation
    private static let windowCalculator = DoseWindowCalculator()
    
    /// Computed dose window context based on current session state.
    /// This is THE context that UI should bind to - it derives from repository state.
    public var currentContext: DoseWindowContext {
        SessionRepository.windowCalculator.context(
            dose1At: dose1Time,
            dose2TakenAt: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount
        )
    }
}
