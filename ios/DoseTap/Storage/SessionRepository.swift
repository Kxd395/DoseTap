import Foundation
import Combine
import UserNotifications
import DoseCore
#if canImport(OSLog)
import OSLog
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Notification Scheduling Protocol

/// Protocol for notification scheduling to enable testing without real UNUserNotificationCenter
public protocol NotificationScheduling: Sendable {
    func cancelNotifications(withIdentifiers ids: [String])
}

/// Production implementation wrapping UNUserNotificationCenter
public final class SystemNotificationScheduler: NotificationScheduling {
    public static let shared = SystemNotificationScheduler()
    
    public func cancelNotifications(withIdentifiers ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

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
    @Published public private(set) var awaitingRolloverMessage: String?
    
    /// Emits whenever session data changes (for observers that need explicit signal)
    public let sessionDidChange = PassthroughSubject<Void, Never>()
    
    // MARK: - Dependencies
    private let storage: EventStorage
    private let notificationScheduler: NotificationScheduling
    private let clock: () -> Date
    private let timeZoneProvider: () -> TimeZone
    private let rolloverHour: Int
    private var rolloverTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    @Published public private(set) var currentSessionKey: String
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "com.dosetap.app", category: "SessionRepository")
    #endif
    
    /// Canonical list of notification identifiers that are session-scoped.
    /// Tests and production code should both use this list to ensure consistency.
    public static let sessionNotificationIdentifiers: [String] = [
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
        "hard_stop_expired",
        "snooze_reminder"
    ]
    
    // MARK: - Initialization
    
    /// Initialize with default shared storage and system notification scheduler
    public convenience init() {
        self.init(storage: EventStorage.shared, notificationScheduler: SystemNotificationScheduler.shared)
    }
    
    /// Initialize with injected storage (for testing)
    public init(
        storage: EventStorage,
        notificationScheduler: NotificationScheduling = SystemNotificationScheduler.shared,
        clock: @escaping () -> Date = { Date() },
        timeZoneProvider: @escaping () -> TimeZone = { TimeZone.autoupdatingCurrent },
        rolloverHour: Int = 18
    ) {
        self.storage = storage
        self.notificationScheduler = notificationScheduler
        self.clock = clock
        self.timeZoneProvider = timeZoneProvider
        self.rolloverHour = rolloverHour
        self.currentSessionKey = sessionKey(for: clock(), timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        
        storage.setNowProvider(clock)
        storage.setTimeZoneProvider(timeZoneProvider)
        reload()
        registerForTimeChanges()
        scheduleRolloverTimer()
    }

    deinit {
        rolloverTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    // MARK: - Load / Reload
    
    /// Reload active session state from storage
    public func reload() {
        let currentDate = storage.currentSessionDate()
        currentSessionKey = currentDate
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
        scheduleRolloverTimer()
    }

    /// Manual hook to recompute session key after external time or timezone changes.
    public func refreshForTimeChange() {
        updateSessionKeyIfNeeded(reason: "manual_refresh", forceReload: true)
    }

    private func clearInMemoryState() {
        activeSessionDate = nil
        dose1Time = nil
        dose2Time = nil
        snoozeCount = 0
        dose2Skipped = false
        wakeFinalTime = nil
        checkInCompleted = false
        dose1TimezoneOffsetMinutes = nil
        awaitingRolloverMessage = nil
    }

    private func updateSessionKeyIfNeeded(reason: String, forceReload: Bool = false) {
        let identity = SessionIdentity(date: clock(), timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        let newKey = identity.key
        let changed = newKey != currentSessionKey
        
        if changed {
            print("🔄 SessionRepository: Rollover \(currentSessionKey) -> \(newKey) (reason: \(reason))")
            #if canImport(OSLog)
            logger.info("Session rollover: \(self.currentSessionKey, privacy: .public) -> \(newKey, privacy: .public) (reason: \(reason, privacy: .public))")
            #endif
            currentSessionKey = newKey
            clearInMemoryState()
        }
        
        if changed || forceReload {
            reload()
        }
        scheduleRolloverTimer()
    }

    private func scheduleRolloverTimer() {
        rolloverTimer?.invalidate()
        let now = clock()
        let fireDate = nextRollover(after: now, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        let interval = max(1, fireDate.timeIntervalSince(now))
        rolloverTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateSessionKeyIfNeeded(reason: "rollover_timer", forceReload: true)
            }
        }
        if let timer = rolloverTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func registerForTimeChanges() {
        #if canImport(UIKit)
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.updateSessionKeyIfNeeded(reason: "significant_time_change", forceReload: true)
                }
            }
        )
        observers.append(
            center.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.updateSessionKeyIfNeeded(reason: "timezone_change", forceReload: true)
                }
            }
        )
        observers.append(
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.updateSessionKeyIfNeeded(reason: "app_active", forceReload: false)
                }
            }
        )
        #endif
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
            #if canImport(OSLog)
            logger.info("Active session \(sessionDate, privacy: .public) deleted; state + notifications cleared")
            #endif
        } else {
            print("🗑️ SessionRepository: Inactive session \(sessionDate) deleted, active state preserved")
            #if canImport(OSLog)
            logger.info("Inactive session \(sessionDate, privacy: .public) deleted; active state preserved")
            #endif
        }
        
        sessionDidChange.send()
    }
    
    /// Cancel all pending dose-related notifications
    /// Called when active session is deleted to prevent orphan notifications
    private func cancelPendingNotifications() {
        // Use the canonical list of session notification identifiers
        notificationScheduler.cancelNotifications(withIdentifiers: Self.sessionNotificationIdentifiers)
        #if canImport(OSLog)
        logger.info("Cancelled session-scoped notifications: \(Self.sessionNotificationIdentifiers.joined(separator: ","))")
        #endif
        print("🔕 SessionRepository: Cancelled pending notifications for deleted session")
    }
    
    /// Record dose 1 time
    public func setDose1Time(_ time: Date) {
        dose1Time = time
        let key = sessionKey(for: time, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        currentSessionKey = key
        activeSessionDate = key
        
        // Record timezone offset when Dose 1 is taken (track both autoupdating and default time zones)
        dose1TimezoneOffsetMinutes = timeZoneProvider().secondsFromGMT(for: time) / 60
        
        // Persist to storage
        storage.saveDose1(timestamp: time)
        
        sessionDidChange.send()
    }
    
    /// Record dose 2 time
    public func setDose2Time(_ time: Date, isEarly: Bool = false, isExtraDose: Bool = false) {
        if !isExtraDose {
            dose2Time = time
        }
        let key = sessionKey(for: time, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        currentSessionKey = key
        activeSessionDate = key
        
        // Persist to storage
        storage.saveDose2(timestamp: time, isEarly: isEarly, isExtraDose: isExtraDose)
        
        sessionDidChange.send()
    }
    
    /// Increment snooze count
    public func incrementSnooze() {
        snoozeCount += 1
        let key = sessionKey(for: clock(), timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        currentSessionKey = key
        activeSessionDate = key
        
        // Persist to storage
        storage.saveSnooze(count: snoozeCount)
        
        sessionDidChange.send()
    }
    
    /// Mark dose 2 as skipped
    public func skipDose2() {
        dose2Skipped = true
        let now = clock()
        let key = sessionKey(for: now, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        currentSessionKey = key
        activeSessionDate = key
        
        // Persist to storage
        storage.saveDoseSkipped()
        
        // Session is considered complete; cancel any pending notifications (including wake alarms)
        cancelPendingNotifications()
        #if canImport(OSLog)
        logger.info("Dose 2 skipped; notifications cancelled")
        #endif
        
        sessionDidChange.send()
    }
    
    // MARK: - Pre-Sleep Log
    
    /// Session key to use when saving pre-sleep logs.
    /// If no active session yet (no Dose 1), target the upcoming night.
    public func preSleepDisplaySessionKey(for date: Date = Date()) -> String {
        if dose1Time != nil || activeSessionDate != nil {
            return currentSessionKey
        }
        return preSleepSessionKey(for: date, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
    }
    
    /// Save pre-sleep log and broadcast change; throws on persistence failure.
    @discardableResult
    public func savePreSleepLog(
        answers: PreSleepLogAnswers,
        completionState: String = "complete",
        existingLog: StoredPreSleepLog? = nil
    ) throws -> StoredPreSleepLog {
        let now = clock()
        let sessionKey = existingLog?.sessionId ?? preSleepDisplaySessionKey(for: now)
        let log = try storage.savePreSleepLogOrThrow(
            sessionId: sessionKey,
            answers: answers,
            completionState: completionState,
            now: now,
            timeZone: timeZoneProvider(),
            existingLog: existingLog
        )
        
        #if DEBUG
        let count = storage.fetchPreSleepLogCount(sessionId: sessionKey)
        let latest = storage.fetchMostRecentPreSleepLog(sessionId: sessionKey)?.createdAtUtc ?? "nil"
        print("🧾 Pre-sleep log saved session=\(sessionKey) count=\(count) latest_utc=\(latest)")
        #endif
        
        sessionDidChange.send()
        return log
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
        awaitingRolloverMessage = nil
        
        sessionDidChange.send()
    }
    
    // MARK: - Timezone Change Detection

    private func timezoneOffsets(at date: Date) -> [Int] {
        let primary = timeZoneProvider().secondsFromGMT(for: date) / 60
        let defaultOffset = NSTimeZone.default.secondsFromGMT(for: date) / 60
        if primary == defaultOffset {
            return [primary]
        }
        return [primary, defaultOffset]
    }
    
    private func timezoneDelta(from referenceOffset: Int, at date: Date) -> Int? {
        for offset in timezoneOffsets(at: date) {
            let delta = offset - referenceOffset
            if delta != 0 {
                return delta
            }
        }
        return nil
    }
    
    private func timezoneChangeDescription(delta: Int) -> String {
        let hours = abs(delta) / 60
        let minutes = abs(delta) % 60
        let direction = delta > 0 ? "east" : "west"
        
        if hours == 0 {
            return "Timezone shifted \(minutes) minutes \(direction)"
        } else if minutes == 0 {
            let hourWord = hours == 1 ? "hour" : "hours"
            return "Timezone shifted \(hours) \(hourWord) \(direction)"
        } else {
            let hourWord = hours == 1 ? "hour" : "hours"
            return "Timezone shifted \(hours) \(hourWord) \(minutes) minutes \(direction)"
        }
    }
    
    /// Check if timezone has changed since Dose 1 was taken
    /// Returns a human-readable description if changed, nil otherwise
    public func checkTimezoneChange() -> String? {
        guard let referenceOffset = dose1TimezoneOffsetMinutes else {
            return nil
        }
        let now = clock()
        guard let delta = timezoneDelta(from: referenceOffset, at: now) else {
            return nil
        }
        return timezoneChangeDescription(delta: delta)
    }
    
    /// Check if timezone has changed (boolean convenience)
    public var hasTimezoneChanged: Bool {
        guard let referenceOffset = dose1TimezoneOffsetMinutes else {
            return false
        }
        let now = clock()
        return timezoneDelta(from: referenceOffset, at: now) != nil
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
        let key = sessionKey(for: time, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        currentSessionKey = key
        activeSessionDate = key
        
        // Persist as sleep event for the correct session key
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "wake_final",
            timestamp: time,
            sessionDate: key,
            colorHex: nil,
            notes: nil
        )
        storage.updateTerminalState(sessionDate: key, state: "completed_wake")
        
        let rolloverDate = nextRollover(after: time, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        if clock() >= rolloverDate {
            awaitingRolloverMessage = nil
            updateSessionKeyIfNeeded(reason: "wake_final_after_rollover", forceReload: true)
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.timeZone = timeZoneProvider()
            awaitingRolloverMessage = "Ended, waiting for rollover at \(formatter.string(from: rolloverDate))"
            sessionDidChange.send()
        }
        
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
        #if canImport(OSLog)
        logger.info("Session auto-marked slept-through; notifications cancelled")
        #endif
        
        sessionDidChange.send()
    }
    
    // MARK: - Queries
    
    /// Check if a given session date is the active/current session
    public func isActiveSession(_ sessionDate: String) -> Bool {
        return sessionDate == storage.currentSessionDate()
    }
    
    /// Get the current session date string (based on 6PM boundary)
    public func currentSessionDateString() -> String {
        return currentSessionKey
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
        let guardMinutes = DoseCore.MedicationConfig.duplicateGuardMinutes
        
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
        sessionKey(for: date, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
    }
    
    // MARK: - Export Support
    
    /// Get all session dates from storage (for export)
    /// Returns array of session date strings in descending order (newest first)
    public func getAllSessions() -> [String] {
        return storage.getAllSessionDates()
    }
    
    // MARK: - Morning Check-In
    
    /// Save morning check-in through unified storage
    /// - Parameters:
    ///   - checkIn: The morning check-in data (from SQLiteStoredMorningCheckIn)
    ///   - sessionDateOverride: Optional session date (uses current if nil)
    public func saveMorningCheckIn(_ checkIn: SQLiteStoredMorningCheckIn, sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? currentSessionKey
        
        // Convert to EventStorage's StoredMorningCheckIn type
        let storedCheckIn = StoredMorningCheckIn(
            id: checkIn.id,
            sessionId: checkIn.sessionId,
            timestamp: checkIn.timestamp,
            sessionDate: sessionDate,
            sleepQuality: checkIn.sleepQuality,
            feelRested: checkIn.feelRested,
            grogginess: checkIn.grogginess,
            sleepInertiaDuration: checkIn.sleepInertiaDuration,
            dreamRecall: checkIn.dreamRecall,
            hasPhysicalSymptoms: checkIn.hasPhysicalSymptoms,
            physicalSymptomsJson: checkIn.physicalSymptomsJson,
            hasRespiratorySymptoms: checkIn.hasRespiratorySymptoms,
            respiratorySymptomsJson: checkIn.respiratorySymptomsJson,
            mentalClarity: checkIn.mentalClarity,
            mood: checkIn.mood,
            anxietyLevel: checkIn.anxietyLevel,
            readinessForDay: checkIn.readinessForDay,
            hadSleepParalysis: checkIn.hadSleepParalysis,
            hadHallucinations: checkIn.hadHallucinations,
            hadAutomaticBehavior: checkIn.hadAutomaticBehavior,
            fellOutOfBed: checkIn.fellOutOfBed,
            hadConfusionOnWaking: checkIn.hadConfusionOnWaking,
            usedSleepTherapy: checkIn.usedSleepTherapy,
            sleepTherapyJson: checkIn.sleepTherapyJson,
            hasSleepEnvironment: checkIn.hasSleepEnvironment,
            sleepEnvironmentJson: checkIn.sleepEnvironmentJson,
            notes: checkIn.notes
        )
        
        storage.saveMorningCheckIn(storedCheckIn, forSession: sessionDate)
        
        // Mark check-in completed
        completeCheckIn()
        
        #if canImport(OSLog)
        logger.info("Morning check-in saved for session \(sessionDate)")
        #endif
        
        sessionDidChange.send()
    }
    
    /// Fetch morning check-in for a session
    public func fetchMorningCheckIn(for sessionDate: String) -> StoredMorningCheckIn? {
        // EventStorage returns DoseCore type, convert to local type
        guard let coreCheckIn = storage.fetchMorningCheckIn(sessionKey: sessionDate) else { return nil }
        return convertMorningCheckIn(coreCheckIn)
    }
    
    /// Fetch morning check-in for current session
    public func fetchMorningCheckInForCurrentSession() -> StoredMorningCheckIn? {
        guard let coreCheckIn = storage.fetchMorningCheckIn(sessionKey: currentSessionKey) else { return nil }
        return convertMorningCheckIn(coreCheckIn)
    }
    
    /// Convert DoseCore.StoredMorningCheckIn to local StoredMorningCheckIn
    private func convertMorningCheckIn(_ core: DoseCore.StoredMorningCheckIn) -> StoredMorningCheckIn {
        return StoredMorningCheckIn(
            id: core.id,
            sessionId: core.sessionId,
            timestamp: core.timestamp,
            sessionDate: core.sessionDate,
            sleepQuality: core.sleepQuality,
            feelRested: core.feelRested,
            grogginess: core.grogginess,
            sleepInertiaDuration: core.sleepInertiaDuration,
            dreamRecall: core.dreamRecall,
            hasPhysicalSymptoms: core.hasPhysicalSymptoms,
            physicalSymptomsJson: core.physicalSymptomsJson,
            hasRespiratorySymptoms: core.hasRespiratorySymptoms,
            respiratorySymptomsJson: core.respiratorySymptomsJson,
            mentalClarity: core.mentalClarity,
            mood: core.mood,
            anxietyLevel: core.anxietyLevel,
            readinessForDay: core.readinessForDay,
            hadSleepParalysis: core.hadSleepParalysis,
            hadHallucinations: core.hadHallucinations,
            hadAutomaticBehavior: core.hadAutomaticBehavior,
            fellOutOfBed: core.fellOutOfBed,
            hadConfusionOnWaking: core.hadConfusionOnWaking,
            usedSleepTherapy: core.usedSleepTherapy,
            sleepTherapyJson: core.sleepTherapyJson,
            hasSleepEnvironment: core.hasSleepEnvironment,
            sleepEnvironmentJson: core.sleepEnvironmentJson,
            notes: core.notes
        )
    }
    
    // MARK: - Sleep Events (Quick Log)
    
    /// Log a sleep event (bathroom, lights_out, wake_final, etc.)
    /// - Parameters:
    ///   - eventType: The type of event (e.g., "bathroom", "lights_out")
    ///   - timestamp: When the event occurred
    ///   - notes: Optional notes
    ///   - source: Event source (default "manual")
    public func logSleepEvent(
        eventType: String,
        timestamp: Date = Date(),
        notes: String? = nil,
        source: String = "manual"
    ) {
        let key = sessionKey(for: timestamp, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: key,
            colorHex: nil,
            notes: notes
        )
        
        #if canImport(OSLog)
        logger.info("Sleep event '\(eventType)' logged for session \(key)")
        #endif
        
        sessionDidChange.send()
    }
    
    /// Fetch tonight's sleep events for current session
    public func fetchTonightSleepEvents() -> [StoredSleepEvent] {
        return storage.fetchSleepEvents(forSession: currentSessionKey)
    }
    
    /// Fetch sleep events for a specific session date
    public func fetchSleepEvents(for sessionDate: String) -> [StoredSleepEvent] {
        return storage.fetchSleepEvents(forSession: sessionDate)
    }
    
    /// Fetch sleep events for a specific session (alternate label)
    public func fetchSleepEvents(forSession sessionDate: String) -> [StoredSleepEvent] {
        return storage.fetchSleepEvents(forSession: sessionDate)
    }
    
    /// Delete a sleep event by ID
    public func deleteSleepEvent(id: String) {
        storage.deleteSleepEvent(id: id)
        sessionDidChange.send()
    }
    
    // MARK: - Data Management
    
    /// Clear all data from storage (factory reset)
    /// ⚠️ DESTRUCTIVE: This removes all dose logs, sleep events, check-ins, etc.
    public func clearAllData() {
        storage.clearAllData()
        
        // Reset in-memory state
        activeSessionDate = nil
        dose1Time = nil
        dose2Time = nil
        snoozeCount = 0
        dose2Skipped = false
        wakeFinalTime = nil
        checkInCompleted = false
        dose1TimezoneOffsetMinutes = nil
        awaitingRolloverMessage = nil
        
        // Recompute session key
        currentSessionKey = sessionKey(for: clock(), timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        
        #if canImport(OSLog)
        logger.info("All data cleared")
        #endif
        
        sessionDidChange.send()
    }
    
    /// Clear all sleep events (preserves dose logs)
    public func clearAllSleepEvents() {
        storage.clearAllSleepEvents()
        sessionDidChange.send()
    }
    
    /// Clear old data older than specified days
    public func clearOldData(olderThanDays days: Int) {
        storage.clearOldData(olderThanDays: days)
        sessionDidChange.send()
    }
    
    /// Fetch recent events across all sessions (for display/history)
    public func fetchRecentEvents(limit: Int = 50) -> [StoredSleepEvent] {
        return storage.fetchEvents(limit: limit)
    }
    
    // MARK: - Timeline Support
    
    /// Fetch all sleep events for timeline display
    public func fetchAllSleepEvents(limit: Int = 500) -> [StoredSleepEvent] {
        // Use local method that returns local types
        return storage.fetchAllSleepEventsLocal(limit: limit)
    }
    
    /// Fetch all dose logs for timeline display
    public func fetchAllDoseLogs(limit: Int = 500) -> [StoredDoseLog] {
        // Use fetchRecentSessionsLocal and convert to dose logs
        let sessions = storage.fetchRecentSessionsLocal(days: 365)
        return sessions.prefix(limit).compactMap { session -> StoredDoseLog? in
            // StoredDoseLog requires non-nil dose1Time
            guard let dose1Time = session.dose1Time else { return nil }
            return StoredDoseLog(
                id: session.sessionDate,
                sessionDate: session.sessionDate,
                dose1Time: dose1Time,
                dose2Time: session.dose2Time,
                dose2Skipped: session.dose2Skipped,
                snoozeCount: session.snoozeCount
            )
        }
    }
    
    /// Filter session dates to those that still exist
    public func filterExistingSessionDates(_ dates: [String]) -> [String] {
        return storage.filterExistingSessionDates(dates)
    }
    
    /// Export all data to CSV
    public func exportToCSV() -> String {
        return storage.exportToCSV()
    }
    
    // MARK: - Pre-Sleep Log Support
    
    /// Fetch the most recent pre-sleep log for prefilling forms
    public func fetchMostRecentPreSleepLog() -> StoredPreSleepLog? {
        return storage.fetchMostRecentPreSleepLog()
    }
    
    // MARK: - Additional Storage Facade Methods (Views must use these, not EventStorage directly)
    
    /// Get schema version for debug display
    public func getSchemaVersion() -> Int {
        return storage.getSchemaVersion()
    }
    
    /// Get session date string for a given date
    public func sessionDateString(for date: Date) -> String {
        return storage.sessionDateString(for: date)
    }
    
    /// Fetch recent sessions for history display
    public func fetchRecentSessions(days: Int = 7) -> [SessionSummary] {
        // Use local method that returns local types
        return storage.fetchRecentSessionsLocal(days: days)
    }
    
    /// Fetch dose log for a specific session
    public func fetchDoseLog(forSession sessionDate: String) -> StoredDoseLog? {
        return storage.fetchDoseLog(forSession: sessionDate)
    }
    
    /// Most recent incomplete session (for check-in prompts)
    public func mostRecentIncompleteSession() -> String? {
        return storage.mostRecentIncompleteSession()
    }
    
    /// Link pre-sleep log to session
    public func linkPreSleepLogToSession(sessionId: String) {
        storage.linkPreSleepLogToSession(sessionKey: sessionId)
    }
    
    /// Clear tonight's events (for session reset)
    public func clearTonightsEvents() {
        storage.clearTonightsEvents()
    }
    
    /// Fetch pre-sleep log by session ID
    public func fetchMostRecentPreSleepLog(sessionId: String) -> StoredPreSleepLog? {
        return storage.fetchMostRecentPreSleepLog(sessionId: sessionId)
    }
    
    /// Save dose 1 timestamp (convenience for direct dose saving)
    public func saveDose1(timestamp: Date) {
        storage.saveDose1(timestamp: timestamp)
    }
    
    /// Save dose 2 timestamp with optional flags
    public func saveDose2(timestamp: Date, isEarly: Bool = false, isExtraDose: Bool = false) {
        storage.saveDose2(timestamp: timestamp, isEarly: isEarly, isExtraDose: isExtraDose)
    }
    
    /// Insert sleep event (for event logging)
    public func insertSleepEvent(id: String, eventType: String, timestamp: Date, colorHex: String?, notes: String? = nil) {
        storage.insertSleepEvent(id: id, eventType: eventType, timestamp: timestamp, colorHex: colorHex, notes: notes)
    }
}
