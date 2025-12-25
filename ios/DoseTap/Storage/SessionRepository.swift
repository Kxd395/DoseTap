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
public final class SessionRepository: ObservableObject, @preconcurrency DoseTapSessionRepository {
    
    // MARK: - Singleton
    public static let shared = SessionRepository()
    
    // MARK: - Published State (UI binds to these)
    @Published public private(set) var activeSessionDate: String?
    @Published public private(set) var dose1Time: Date?
    @Published public private(set) var dose2Time: Date?
    @Published public private(set) var snoozeCount: Int = 0
    @Published public private(set) var dose2Skipped: Bool = false
    @Published public private(set) var wakeFinalTime: Date?       // When user pressed Wake Up
    @Published public private(set) var checkInCompleted: Bool = false  // Morning check-in done
    @Published public private(set) var dose1TimezoneOffsetMinutes: Int?  // Timezone when Dose 1 was taken
    
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
            wakeFinalTime = nil
            checkInCompleted = false
            dose1TimezoneOffsetMinutes = nil
            
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
        
        // Record timezone offset when Dose 1 is taken
        dose1TimezoneOffsetMinutes = DoseWindowCalculator.currentTimezoneOffsetMinutes()
        
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
        wakeFinalTime = nil
        checkInCompleted = false
        dose1TimezoneOffsetMinutes = nil
        
        sessionDidChange.send()
    }
    
    // MARK: - Timezone Change Detection
    
    /// Check if timezone has changed since Dose 1 was taken
    /// Returns a human-readable description if changed, nil otherwise
    public func checkTimezoneChange() -> String? {
        guard let referenceOffset = dose1TimezoneOffsetMinutes else {
            return nil
        }
        
        let calculator = DoseWindowCalculator()
        return calculator.timezoneChangeDescription(from: referenceOffset)
    }
    
    /// Check if timezone has changed (boolean convenience)
    public var hasTimezoneChanged: Bool {
        guard let referenceOffset = dose1TimezoneOffsetMinutes else {
            return false
        }
        
        let calculator = DoseWindowCalculator()
        return calculator.timezoneChange(from: referenceOffset) != nil
    }
    
    // MARK: - Undo Support
    
    /// Clear Dose 1 (for undo)
    public func clearDose1() {
        dose1Time = nil
        activeSessionDate = nil
        dose1TimezoneOffsetMinutes = nil
        
        // Clear from storage
        storage.clearDose1()
        
        sessionDidChange.send()
        print("↩️ SessionRepository: Dose 1 cleared (undo)")
    }
    
    /// Clear Dose 2 (for undo)
    public func clearDose2() {
        dose2Time = nil
        
        // Clear from storage
        storage.clearDose2()
        
        sessionDidChange.send()
        print("↩️ SessionRepository: Dose 2 cleared (undo)")
    }
    
    /// Clear skip status (for undo)
    public func clearSkip() {
        dose2Skipped = false
        
        // Clear from storage
        storage.clearSkip()
        
        sessionDidChange.send()
        print("↩️ SessionRepository: Skip cleared (undo)")
    }
    
    /// Decrement snooze count (for undo)
    public func decrementSnoozeCount() {
        if snoozeCount > 0 {
            snoozeCount -= 1
            
            // Persist to storage
            storage.saveSnooze(count: snoozeCount)
            
            sessionDidChange.send()
            print("↩️ SessionRepository: Snooze count decremented to \(snoozeCount) (undo)")
        }
    }
    
    // MARK: - Session Finalization (Wake Up & Check-In)
    
    /// Record when user pressed "Wake Up & End Session"
    /// This puts the session into "finalizing" state
    public func setWakeFinalTime(_ time: Date) {
        wakeFinalTime = time
        
        // TODO: Persist to storage
        // storage.saveWakeFinal(timestamp: time)
        
        sessionDidChange.send()
        print("☀️ SessionRepository: Wake Final logged at \(time)")
    }
    
    /// Mark morning check-in as completed
    /// This transitions session from "finalizing" to "completed"
    public func completeCheckIn() {
        checkInCompleted = true
        
        // TODO: Persist to storage
        // storage.saveCheckInCompleted()
        
        sessionDidChange.send()
        print("✅ SessionRepository: Morning check-in completed, session finalized")
    }
    
    /// Clear wake final time (for undo)
    public func clearWakeFinal() {
        wakeFinalTime = nil
        checkInCompleted = false
        
        sessionDidChange.send()
        print("↩️ SessionRepository: Wake Final cleared (undo)")
    }
    
    // MARK: - Sleep-Through Handling
    
    /// Check if session has expired due to sleeping through dose window
    /// Called on app foreground to auto-mark incomplete sessions
    /// Returns true if session was auto-expired
    @discardableResult
    public func checkAndHandleExpiredSession() -> Bool {
        let calculator = DoseWindowCalculator()
        
        if calculator.shouldAutoExpireSession(
            dose1At: dose1Time,
            dose2TakenAt: dose2Time,
            dose2Skipped: dose2Skipped
        ) {
            markSessionSleptThrough()
            return true
        }
        
        return false
    }
    
    /// Mark the current session as incomplete due to sleeping through
    /// This auto-skips Dose 2 with a special reason and resets for new session
    private func markSessionSleptThrough() {
        guard dose1Time != nil else { return }
        
        print("😴 SessionRepository: Auto-marking session as slept-through (window + grace expired)")
        
        // Save skip with slept-through reason
        storage.saveDoseSkipped(reason: "slept_through")
        
        // Update terminal state
        storage.updateTerminalState(sessionDate: activeSessionDate ?? storage.currentSessionDate(), state: "incomplete_slept_through")
        
        // Reset in-memory state for new session
        dose2Skipped = true
        wakeFinalTime = nil
        checkInCompleted = false
        
        // Cancel any pending notifications
        cancelPendingNotifications()
        
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
            snoozeCount: snoozeCount,
            wakeFinalAt: wakeFinalTime,
            checkInCompleted: checkInCompleted
        )
    }
    
    // MARK: - Medication Logging
    
    /// Log a medication entry (e.g., Adderall)
    /// Returns the DuplicateGuardResult for UI to handle
    public func logMedicationEntry(
        medicationId: String,
        doseMg: Int,
        takenAt: Date,
        notes: String? = nil,
        confirmedDuplicate: Bool = false
    ) -> DuplicateGuardResult {
        let sessionDate = computeSessionDate(for: takenAt)
        
        // Check for duplicate within guard window (if not already confirmed)
        if !confirmedDuplicate {
            let guardResult = checkDuplicateGuard(medicationId: medicationId, takenAt: takenAt, sessionDate: sessionDate)
            if guardResult.isDuplicate {
                return guardResult
            }
        }
        
        // Get session_id if we have an active session matching this date
        let sessionId: String?
        if sessionDate == activeSessionDate {
            sessionId = activeSessionDate
        } else {
            sessionId = nil
        }
        
        let entry = StoredMedicationEntry(
            sessionId: sessionId,
            sessionDate: sessionDate,
            medicationId: medicationId,
            doseMg: doseMg,
            takenAtUTC: takenAt,
            notes: notes,
            confirmedDuplicate: confirmedDuplicate
        )
        
        storage.insertMedicationEvent(entry)
        
        print("💊 SessionRepository: Logged medication \(medicationId) \(doseMg)mg at \(takenAt)")
        sessionDidChange.send()
        
        return .notDuplicate
    }
    
    /// Check if a medication entry would be a duplicate
    public func checkDuplicateGuard(medicationId: String, takenAt: Date, sessionDate: String) -> DuplicateGuardResult {
        let guardMinutes = MedicationConfig.duplicateGuardMinutes
        
        if let existing = storage.findRecentMedicationEntry(
            medicationId: medicationId,
            sessionDate: sessionDate,
            withinMinutes: guardMinutes,
            ofTime: takenAt
        ) {
            let deltaSeconds = abs(takenAt.timeIntervalSince(existing.takenAtUTC))
            let minutesDelta = Int(deltaSeconds / 60)
            
            // Convert StoredMedicationEntry to MedicationEntry for return
            let entry = MedicationEntry(
                id: existing.id,
                sessionId: existing.sessionId,
                sessionDate: existing.sessionDate,
                medicationId: existing.medicationId,
                doseMg: existing.doseMg,
                takenAtUTC: existing.takenAtUTC,
                notes: existing.notes,
                confirmedDuplicate: existing.confirmedDuplicate,
                createdAt: existing.createdAt
            )
            
            return DuplicateGuardResult(isDuplicate: true, existingEntry: entry, minutesDelta: minutesDelta)
        }
        
        return .notDuplicate
    }
    
    /// Convenience: Check duplicate without needing to compute session date
    public func checkDuplicateMedication(medicationId: String, takenAt: Date) -> DuplicateGuardResult {
        let sessionDate = computeSessionDate(for: takenAt)
        return checkDuplicateGuard(medicationId: medicationId, takenAt: takenAt, sessionDate: sessionDate)
    }
    
    /// List medication entries for a session date
    public func listMedicationEntries(for sessionDate: String) -> [MedicationEntry] {
        storage.fetchMedicationEvents(sessionDate: sessionDate).map { stored in
            MedicationEntry(
                id: stored.id,
                sessionId: stored.sessionId,
                sessionDate: stored.sessionDate,
                medicationId: stored.medicationId,
                doseMg: stored.doseMg,
                takenAtUTC: stored.takenAtUTC,
                notes: stored.notes,
                confirmedDuplicate: stored.confirmedDuplicate,
                createdAt: stored.createdAt
            )
        }
    }
    
    /// List medication entries for current session
    public func listMedicationEntriesForCurrentSession() -> [MedicationEntry] {
        let sessionDate = currentSessionDateString()
        return listMedicationEntries(for: sessionDate)
    }
    
    /// Delete a medication entry
    public func deleteMedicationEntry(id: String) {
        storage.deleteMedicationEvent(id: id)
        sessionDidChange.send()
    }
    
    /// Compute session date for a given timestamp using 6PM boundary
    /// Times before 6PM belong to previous day's session
    private func computeSessionDate(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        let sessionDay: Date
        if hour < 18 { // Before 6 PM
            sessionDay = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        } else {
            sessionDay = date
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: sessionDay)
    }
}
