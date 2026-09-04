import Foundation
import Combine
import UserNotifications
import DoseCore
import os.log
#if canImport(OSLog)
import OSLog
#endif

private let repoLogger = Logger(subsystem: "com.dosetap.app", category: "SessionRepository")
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
public final class SessionRepository: ObservableObject, @preconcurrency DoseTapSessionStateProviding {
    
    // MARK: - Singleton
    public static let shared = SessionRepository()
    
    // MARK: - Published State (UI binds to these)
    @Published public private(set) var activeSessionDate: String?
    @Published public private(set) var activeSessionId: String?
    @Published public private(set) var activeSessionStart: Date?
    @Published public private(set) var activeSessionEnd: Date?
    @Published public private(set) var dose1Time: Date?
    @Published public private(set) var dose2Time: Date?
    @Published public private(set) var snoozeCount: Int = 0
    @Published public private(set) var dose2Skipped: Bool = false
    @Published public private(set) var wakeFinalTime: Date?       // When user pressed Wake Up
    @Published public private(set) var checkInCompleted: Bool = false  // Morning check-in done
    @Published public private(set) var dose1TimezoneOffsetMinutes: Int?  // Timezone when Dose 1 was taken
    @Published public private(set) var awaitingRolloverMessage: String?
    @Published public private(set) var lastMedicationMutationError: MedicationMutationFailure?
    
    /// Emits whenever session data changes (for observers that need explicit signal)
    public let sessionDidChange = PassthroughSubject<Void, Never>()
    
    // MARK: - Phase Tracking (for diagnostic logging)
    /// Tracks last known phase to detect transitions at edges
    var lastLoggedPhase: DoseWindowPhase?
    
    // MARK: - Dependencies
    let storage: EventStorage
    private let notificationScheduler: NotificationScheduling
    let clock: () -> Date
    let timeZoneProvider: () -> TimeZone
    let rolloverHour: Int
    private var rolloverTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let shouldAssertDoseStateInvariantFailure: Bool
    @Published fileprivate(set) var currentSessionKey: String
    #if canImport(OSLog)
    let logger = Logger(subsystem: "com.dosetap.app", category: "SessionRepository")
    #endif
    
    /// Canonical list of notification identifiers that are session-scoped.
    /// Tests and production code should both use this list to ensure consistency.
    public static let sessionNotificationIdentifiers: [String] = [
        // AlarmService.NotificationID.wakeAlarm
        "dosetap_dose2_alarm",
        // AlarmService.NotificationID.preAlarm
        "dosetap_dose2_pre_alarm",
        // AlarmService.NotificationID.followUp_1..._3
        "dosetap_followup_1",
        "dosetap_followup_2",
        "dosetap_followup_3",
        // AlarmService.NotificationID.secondDose
        "dosetap_second_dose",
        // AlarmService.NotificationID.windowWarning15/windowWarning5
        "dosetap_window_15min",
        "dosetap_window_5min"
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
        rolloverHour: Int = 18,
        shouldAssertDoseStateInvariantFailure: Bool = false
    ) {
        self.storage = storage
        self.notificationScheduler = notificationScheduler
        self.clock = clock
        self.timeZoneProvider = timeZoneProvider
        self.rolloverHour = rolloverHour
        self.shouldAssertDoseStateInvariantFailure = shouldAssertDoseStateInvariantFailure
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
        currentSessionKey = storage.currentSessionDate()
        var state = storage.loadCurrentSessionState()

        if let d1 = state.dose1Time, let d2 = state.dose2Time {
            let delta = d2.timeIntervalSince(d1)
            if delta < 0 || delta > 12 * 60 * 60 {
                if let sessionDate = state.sessionDate {
                    repoLogger.warning("SessionRepo: Clearing stale dose2 time for session \(sessionDate)")
                    storage.clearDose2(sessionDateOverride: sessionDate, sessionId: state.sessionId)
                    state = storage.loadCurrentSessionState()
                }
            }
        }

        if recoverPersistedDoseStateIfNeeded(reason: "reload") {
            state = storage.loadCurrentSessionState()
        }

        let resolvedSessionId = state.sessionId ?? state.sessionDate
        let hasSessionData = resolvedSessionId != nil
            || state.dose1Time != nil
            || state.dose2Time != nil
            || state.snoozeCount > 0
            || state.dose2Skipped
        
        if state.sessionEnd == nil, hasSessionData {
            activeSessionId = resolvedSessionId
            activeSessionDate = state.sessionDate
            activeSessionStart = state.sessionStart
            activeSessionEnd = nil
            dose1Time = state.dose1Time
            dose2Time = state.dose2Time
            snoozeCount = state.snoozeCount
            dose2Skipped = state.dose2Skipped
        } else {
            clearInMemoryState()
        }
        
        sessionDidChange.send()
        evaluateSessionBoundaries(reason: "reload")
        validateDoseStateInvariant(reason: "reload")
        
        repoLogger.info("SessionRepo reloaded: session=\(self.activeSessionDate ?? "none"), dose1=\(self.dose1Time?.description ?? "nil"), dose2=\(self.dose2Time?.description ?? "nil")")
        scheduleRolloverTimer()
    }

    /// Manual hook to recompute session key after external time or timezone changes.
    public func refreshForTimeChange() {
        updateSessionKeyIfNeeded(reason: "manual_refresh", forceReload: true)
    }

    private func clearInMemoryState() {
        activeSessionDate = nil
        activeSessionId = nil
        activeSessionStart = nil
        activeSessionEnd = nil
        dose1Time = nil
        dose2Time = nil
        snoozeCount = 0
        dose2Skipped = false
        wakeFinalTime = nil
        checkInCompleted = false
        dose1TimezoneOffsetMinutes = nil
        awaitingRolloverMessage = nil
        lastLoggedPhase = nil  // Reset phase tracking
    }

    private func validateDoseStateInvariant(reason: String) {
        let violations = storage.validateActiveDoseStateInvariant()
        guard !violations.isEmpty else { return }

        let details = violations
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")

        repoLogger.error("Dose state invariant violation reason=\(reason, privacy: .public) details=\(details, privacy: .public)")

        #if DEBUG
        if shouldAssertDoseStateInvariantFailure {
            assertionFailure("Dose state invariant violation reason=\(reason): \(details)")
        }
        #endif

        if let sessionId = activeSessionId ?? activeSessionDate ?? storage.loadCurrentSessionState().sessionDate {
            Task {
                await DiagnosticLogger.shared.log(.invariantViolation, sessionId: sessionId) { entry in
                    entry.invariantName = "dose_state_ssot"
                    entry.reason = reason
                }
            }
        }
    }

    private func logBlockedDoseStateMutation(action: String, reason: String, sessionId: String?) {
        repoLogger.error("Blocked dose state mutation action=\(action, privacy: .public) reason=\(reason, privacy: .public)")

        guard let sessionId else { return }
        Task {
            await DiagnosticLogger.shared.log(.invariantViolation, sessionId: sessionId) { entry in
                entry.invariantName = "blocked_\(action)_state_mutation"
                entry.reason = reason
            }
        }
    }

    @discardableResult
    func recordMedicationMutation(
        _ result: MedicationMutationResult
    ) -> MedicationMutationResult {
        switch result {
        case .committed:
            lastMedicationMutationError = nil
        case .failed(let failure):
            lastMedicationMutationError = failure
            repoLogger.error(
                "Medication mutation failed operation=\(failure.operation.rawValue, privacy: .public) stage=\(failure.stage.rawValue, privacy: .public) code=\(failure.code.rawValue, privacy: .public)"
            )
            if let sessionId = activeSessionId ?? activeSessionDate {
                Task {
                    await DiagnosticLogger.shared.log(
                        .invariantViolation,
                        sessionId: sessionId
                    ) { entry in
                        entry.invariantName = "medication_mutation_failed"
                        entry.reason = "\(failure.operation.rawValue).\(failure.stage.rawValue).\(failure.code.rawValue)"
                    }
                }
            }
        }
        return result
    }

    func failedMedicationMutation(
        operation: MedicationMutationOperation,
        detail: String,
        sessionId: String?
    ) -> MedicationMutationResult {
        logBlockedDoseStateMutation(
            action: operation.rawValue,
            reason: detail,
            sessionId: sessionId
        )
        return recordMedicationMutation(.failed(MedicationMutationFailure(
            operation: operation,
            code: .precondition,
            stage: .preflight,
            detail: detail
        )))
    }

    private struct MedicationSessionCandidate {
        let sessionId: String
        let sessionDate: String
        let sessionStart: Date
        let isNew: Bool
    }

    /// Resolve a medication session without mutating published state. The
    /// storage transaction is the commit point; only its success may publish
    /// this candidate to the UI.
    private func medicationSessionCandidate(
        for timestamp: Date
    ) -> MedicationSessionCandidate {
        if let activeSessionDate,
           activeSessionEnd == nil {
            return MedicationSessionCandidate(
                sessionId: activeSessionId ?? activeSessionDate,
                sessionDate: activeSessionDate,
                sessionStart: activeSessionStart ?? dose1Time ?? timestamp,
                isNew: false
            )
        }

        let stored = storage.loadCurrentSessionState()
        if stored.sessionEnd == nil,
           let storedSessionDate = stored.sessionDate,
           let storedSessionId = stored.sessionId ?? stored.sessionDate {
            return MedicationSessionCandidate(
                sessionId: storedSessionId,
                sessionDate: storedSessionDate,
                sessionStart: stored.sessionStart ?? stored.dose1Time ?? timestamp,
                isNew: false
            )
        }

        return MedicationSessionCandidate(
            sessionId: UUID().uuidString,
            sessionDate: sessionKey(
                for: timestamp,
                timeZone: timeZoneProvider(),
                rolloverHour: rolloverHour
            ),
            sessionStart: timestamp,
            isNew: true
        )
    }

    private func recoverPersistedDoseStateIfNeeded(reason: String) -> Bool {
        let violations = storage.validateActiveDoseStateInvariant()
        guard !violations.isEmpty else { return false }

        let snapshot = storage.loadCurrentSessionState()
        guard let sessionDate = snapshot.sessionDate else { return false }
        let sessionId = snapshot.sessionId ?? sessionDate
        let details = violations
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")

        repoLogger.error("Recovering invalid active dose state reason=\(reason, privacy: .public) details=\(details, privacy: .public)")
        storage.markCurrentSessionInvalid(
            sessionDate: sessionDate,
            sessionId: sessionId,
            endedAt: clock(),
            terminalState: "invalid_dose_state"
        )

        Task {
            await DiagnosticLogger.shared.log(.invariantViolation, sessionId: sessionId) { entry in
                entry.invariantName = "dose_state_ssot_recovered"
                entry.reason = reason
            }
        }

        return true
    }

    private func updateSessionKeyIfNeeded(reason: String, forceReload: Bool = false) {
        let identity = SessionIdentity(date: clock(), timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        let newKey = identity.key
        let changed = newKey != currentSessionKey
        
        if changed {
            let oldKey = currentSessionKey
            repoLogger.info("SessionRepo: Rollover \(self.currentSessionKey) -> \(newKey) (reason: \(reason))")
            #if canImport(OSLog)
            logger.info("Session rollover: \(self.currentSessionKey, privacy: .public) -> \(newKey, privacy: .public) (reason: \(reason, privacy: .public))")
            #endif
            
            // Diagnostic logging: reporting key rollover
            Task {
                await DiagnosticLogger.shared.log(.sessionRollover, sessionId: oldKey) { entry in
                    entry.reason = reason
                }
            }
            
            currentSessionKey = newKey
        }
        
        if changed || forceReload {
            reload()
        } else {
            evaluateSessionBoundaries(reason: reason)
        }
        scheduleRolloverTimer()
    }

    private func scheduleRolloverTimer() {
        rolloverTimer?.invalidate()
        let now = clock()
        let timeZone = timeZoneProvider()
        var candidates: [Date] = [nextRollover(after: now, timeZone: timeZone, rolloverHour: rolloverHour)]

        if activeSessionId != nil, activeSessionEnd == nil {
            let prepCandidate = nextOccurrence(of: UserSettingsManager.shared.prepTimeMinutes, after: now, timeZone: timeZone)
            candidates.append(prepCandidate)

            let scheduledStart = activeSessionDate.flatMap { scheduledSleepStart(for: $0) }
            let start = activeSessionStart ?? dose1Time ?? scheduledStart ?? now
            let cutoff = cutoffTime(for: start)
            if cutoff > now {
                candidates.append(cutoff)
            }
        }

        let fireDate = candidates.min() ?? now.addingTimeInterval(3600)
        let interval = max(1, fireDate.timeIntervalSince(now))
        rolloverTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateSessionKeyIfNeeded(reason: "boundary_timer", forceReload: true)
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

    private func isDoseEventType(_ eventType: String) -> Bool {
        CanonicalDoseEventType(canonicalizing: eventType)?.countsAsTakenDose == true
    }

    private func doseWindowCloseTime(dose1Time: Date) -> Date {
        let config = DoseCore.DoseWindowConfig()
        return dose1Time.addingTimeInterval(TimeInterval(config.maxIntervalMin * 60))
    }

    func loadDoseEvents(sessionId: String?, sessionDate: String) -> [DoseCore.StoredDoseEvent] {
        storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
    }
    
    // MARK: - Mutations

    /// Ensure there is an active session for the given timestamp.
    func ensureActiveSession(for timestamp: Date, reason: String) -> (sessionId: String, sessionDate: String) {
        evaluateSessionBoundaries(reason: "ensure_active_session.\(reason)")

        if let activeSessionId = activeSessionId, let activeSessionDate = activeSessionDate, activeSessionEnd == nil {
            return (activeSessionId, activeSessionDate)
        }
        
        if let activeSessionDate = activeSessionDate {
            let resolvedSessionId = activeSessionId ?? activeSessionDate
            activeSessionId = resolvedSessionId
            if activeSessionStart == nil {
                activeSessionStart = dose1Time ?? timestamp
            }
            scheduleRolloverTimer()
            return (resolvedSessionId, activeSessionDate)
        }

        let storedState = storage.loadCurrentSessionState()
        let storedSessionId = storedState.sessionId ?? storedState.sessionDate
        let storedHasSessionData = storedSessionId != nil
            || storedState.dose1Time != nil
            || storedState.dose2Time != nil
            || storedState.snoozeCount > 0
            || storedState.dose2Skipped
        if storedState.sessionEnd == nil,
           storedHasSessionData,
           let storedSessionDate = storedState.sessionDate,
           let resolvedSessionId = storedSessionId {
            activeSessionId = resolvedSessionId
            activeSessionDate = storedSessionDate
            activeSessionStart = storedState.sessionStart ?? storedState.dose1Time ?? timestamp
            activeSessionEnd = nil
            dose1Time = storedState.dose1Time
            dose2Time = storedState.dose2Time
            snoozeCount = storedState.snoozeCount
            dose2Skipped = storedState.dose2Skipped
            wakeFinalTime = nil
            checkInCompleted = false
            currentSessionKey = storedSessionDate
            scheduleRolloverTimer()
            return (resolvedSessionId, storedSessionDate)
        }
        
        let sessionDate = sessionKey(for: timestamp, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        let sessionId = UUID().uuidString
        
        activeSessionId = sessionId
        activeSessionDate = sessionDate
        activeSessionStart = timestamp
        activeSessionEnd = nil
        dose1Time = nil
        dose2Time = nil
        snoozeCount = 0
        dose2Skipped = false
        wakeFinalTime = nil
        checkInCompleted = false
        dose1TimezoneOffsetMinutes = nil
        awaitingRolloverMessage = nil
        lastLoggedPhase = nil
        
        storage.startSession(sessionId: sessionId, sessionDate: sessionDate, start: timestamp)
        
        Task {
            await DiagnosticLogger.shared.ensureSessionMetadata(sessionId: sessionId)
            await DiagnosticLogger.shared.logSessionStarted(sessionId: sessionId)
        }

        scheduleRolloverTimer()
        
        return (sessionId, sessionDate)
    }

    /// Close the active session and clear in-memory state.
    func closeActiveSession(at endTime: Date, terminalState: String, reason: String) {
        guard let sessionId = activeSessionId, let sessionDate = activeSessionDate else { return }
        
        storage.closeSession(sessionId: sessionId, sessionDate: sessionDate, end: endTime, terminalState: terminalState)
        
        Task {
            await DiagnosticLogger.shared.logSessionCompleted(
                sessionId: sessionId,
                terminalState: terminalState,
                dose1Time: dose1Time,
                dose2Time: dose2Time
            )
            await DiagnosticLogger.shared.log(.sessionRollover, sessionId: sessionId) { entry in
                entry.reason = reason
            }
        }
        
        cancelPendingNotifications()
        AlarmService.shared.resetForNewSession()
        
        clearInMemoryState()
        sessionDidChange.send()
        scheduleRolloverTimer()
    }
    
    /// Delete a session by date string. If it's the active session, clears state.
    /// Also cancels any pending notifications for the session.
    public func deleteSession(sessionDate: String) {
        let wasActiveSession = (sessionDate == activeSessionDate) || 
                               (sessionDate == storage.currentSessionDate())
        
        // Delete from storage
        storage.deleteSession(sessionDate: sessionDate)
        
        // If we deleted the active session, clear in-memory state AND cancel notifications
        if wasActiveSession {
            // P0-3 FIX: Cancel any pending notifications for this session
            // Notifications should not fire for deleted sessions
            cancelPendingNotifications()
            clearInMemoryState()
            
            repoLogger.info("SessionRepo: Active session deleted, state and notifications cleared")
            #if canImport(OSLog)
            logger.info("Active session \(sessionDate, privacy: .public) deleted; state + notifications cleared")
            #endif
        } else {
            repoLogger.info("SessionRepo: Inactive session \(sessionDate) deleted, active state preserved")
            #if canImport(OSLog)
            logger.info("Inactive session \(sessionDate, privacy: .public) deleted; active state preserved")
            #endif
        }
        
        sessionDidChange.send()
    }

    /// Async compatibility wrapper for test/API parity.
    public func deleteSessionAsync(sessionDate: String) async {
        deleteSession(sessionDate: sessionDate)
    }
    
    /// Cancel all pending dose-related notifications
    /// Called when active session is deleted to prevent orphan notifications
    private func cancelPendingNotifications() {
        // Use the canonical list of session notification identifiers
        notificationScheduler.cancelNotifications(withIdentifiers: Self.sessionNotificationIdentifiers)
        #if canImport(OSLog)
        logger.info("Cancelled session-scoped notifications: \(Self.sessionNotificationIdentifiers.joined(separator: ","))")
        #endif
        repoLogger.info("SessionRepo: Cancelled pending notifications for deleted session")
    }
    
    /// Record dose 1 time
    @discardableResult
    public func setDose1Time(_ time: Date) -> MedicationMutationResult {
        evaluateSessionBoundaries(reason: "set_dose1_preflight")
        let session = medicationSessionCandidate(for: time)
        let result = recordMedicationMutation(storage.saveDose1(
            timestamp: time,
            sessionId: session.sessionId,
            sessionDateOverride: session.sessionDate,
            sessionStart: session.sessionStart
        ))
        guard result.isCommitted else {
            return result
        }

        activeSessionId = session.sessionId
        activeSessionDate = session.sessionDate
        activeSessionStart = session.sessionStart
        activeSessionEnd = nil
        currentSessionKey = session.sessionDate
        dose1Time = time
        dose2Time = nil
        dose2Skipped = false
        snoozeCount = 0
        wakeFinalTime = nil
        checkInCompleted = false
        
        // Record timezone offset when Dose 1 is taken (track both autoupdating and default time zones)
        dose1TimezoneOffsetMinutes = timeZoneProvider().secondsFromGMT(for: time) / 60
        
        storage.linkPreSleepLogToSession(sessionId: session.sessionId, sessionDate: session.sessionDate)
        validateDoseStateInvariant(reason: "set_dose1")
        
        // Diagnostic logging: session started + dose 1 taken
        Task {
            if session.isNew {
                await DiagnosticLogger.shared.ensureSessionMetadata(sessionId: session.sessionId)
                await DiagnosticLogger.shared.logSessionStarted(sessionId: session.sessionId)
            }
            await DiagnosticLogger.shared.logDoseTaken(sessionId: session.sessionId, doseIndex: 1, at: time)
        }
        
        sessionDidChange.send()
        scheduleRolloverTimer()
        return result
    }
    
    /// Record dose 2+ time (dose index is derived from session events, not the clock).
    @discardableResult
    public func setDose2Time(
        _ time: Date,
        isEarly: Bool,
        isExtraDose: Bool
    ) -> MedicationMutationResult {
        setDose2Time(
            time,
            isEarly: isEarly,
            isExtraDose: isExtraDose,
            reason: nil,
            reasonNotes: nil
        )
    }

    /// Record dose 2+ time with optional outcome context captured at action time.
    @discardableResult
    public func setDose2Time(
        _ time: Date,
        isEarly: Bool = false,
        isExtraDose: Bool = false,
        entryMode: DoseEntryMode? = nil,
        workWarning: WorkWakeWarning? = nil,
        recordedAt: Date? = nil,
        surface: RegistrationSurface? = nil,
        reason: String? = nil,
        reasonNotes: String? = nil
    ) -> MedicationMutationResult {
        evaluateSessionBoundaries(reason: "set_dose2_preflight")
        let storedState = storage.loadCurrentSessionState()
        let hasOpenActiveSession = activeSessionId != nil && activeSessionDate != nil && activeSessionEnd == nil
        let hasOpenStoredDose1 = storedState.sessionEnd == nil
            && storedState.dose1Time != nil
            && storedState.sessionDate != nil
        guard hasOpenActiveSession || hasOpenStoredDose1 else {
            return failedMedicationMutation(
                operation: .dose2,
                detail: "Take Dose 1 before recording Dose 2.",
                sessionId: storedState.sessionId ?? storedState.sessionDate
            )
        }

        let session: (sessionId: String, sessionDate: String, sessionStart: Date)
        if let activeSessionId,
           let activeSessionDate,
           activeSessionEnd == nil {
            session = (
                sessionId: activeSessionId,
                sessionDate: activeSessionDate,
                sessionStart: activeSessionStart ?? dose1Time ?? time
            )
        } else if storedState.sessionEnd == nil,
                  let storedSessionDate = storedState.sessionDate,
                  let storedSessionId = storedState.sessionId ?? storedState.sessionDate {
            session = (
                sessionId: storedSessionId,
                sessionDate: storedSessionDate,
                sessionStart: storedState.sessionStart ?? storedState.dose1Time ?? time
            )
        } else {
            return failedMedicationMutation(
                operation: .dose2,
                detail: "Take Dose 1 before recording Dose 2.",
                sessionId: storedState.sessionId ?? storedState.sessionDate
            )
        }

        let doseEvents = loadDoseEvents(sessionId: session.sessionId, sessionDate: session.sessionDate)
        let dose1Event = doseEvents.first { CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose1 }
        guard let firstDoseTime = dose1Event?.timestamp,
              doseEvents.filter({ CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose1 }).count == 1 else {
            return failedMedicationMutation(
                operation: .dose2,
                detail: "Take Dose 1 before recording Dose 2.",
                sessionId: session.sessionId
            )
        }

        let doseTakenEvents = doseEvents.filter { isDoseEventType($0.eventType) }
        let sortedEvents = doseTakenEvents.sorted { $0.timestamp < $1.timestamp }

        let nextDoseIndex = sortedEvents.count + 1
        let isExtra = nextDoseIndex >= 3
        if isExtra != isExtraDose {
            let detail = isExtra
                ? "Dose 2 is already recorded. An extra dose requires explicit confirmation."
                : "Record Dose 2 before adding an extra dose."
            return failedMedicationMutation(
                operation: isExtraDose ? .extraDose : .dose2,
                detail: detail,
                sessionId: session.sessionId
            )
        }

        let isDose2 = nextDoseIndex == 2 && !isExtra
        let isLate = isDose2 && time >= doseWindowCloseTime(dose1Time: firstDoseTime)
        let previousDoseTime = sortedEvents.last?.timestamp
        let elapsedSincePrev = previousDoseTime.map { TimeIntervalMath.minutesBetween(start: $0, end: time) }
        let elapsedSinceFirst = TimeIntervalMath.minutesBetween(start: firstDoseTime, end: time)
        
        let result = recordMedicationMutation(storage.saveDose2(
            timestamp: time,
            isEarly: isEarly,
            isExtraDose: isExtra,
            isLate: isLate,
            entryMode: entryMode,
            workWarning: workWarning,
            recordedAt: recordedAt,
            surface: surface,
            reason: reason,
            reasonNotes: reasonNotes,
            sessionId: session.sessionId,
            sessionDateOverride: session.sessionDate
        ))
        guard result.isCommitted else {
            return result
        }

        activeSessionId = session.sessionId
        activeSessionDate = session.sessionDate
        activeSessionStart = session.sessionStart
        activeSessionEnd = nil
        currentSessionKey = session.sessionDate
        if dose1Time == nil {
            dose1Time = firstDoseTime
        }
        if isDose2 {
            dose2Time = time
            dose2Skipped = false
        }
        activeSessionDate = session.sessionDate
        validateDoseStateInvariant(reason: isExtra ? "set_extra_dose" : "set_dose2")
        
        // Diagnostic logging: dose taken with index + elapsed info
        Task {
            await DiagnosticLogger.shared.logDoseTaken(
                sessionId: session.sessionId,
                doseIndex: nextDoseIndex,
                at: time,
                elapsedMinutes: elapsedSinceFirst,
                elapsedSincePrevDoseMinutes: elapsedSincePrev,
                isLate: isLate
            )
        }

        sessionDidChange.send()
        scheduleRolloverTimer()
        return result
    }
    
    /// Increment snooze count
    @discardableResult
    public func incrementSnooze() -> MedicationMutationResult {
        incrementSnoozeMutationIfActive()
    }

    @discardableResult
    public func incrementSnoozeIfActive() -> Bool {
        incrementSnoozeMutationIfActive().isCommitted
    }

    @discardableResult
    public func incrementSnoozeMutationIfActive() -> MedicationMutationResult {
        evaluateSessionBoundaries(reason: "snooze_preflight")

        guard let sessionId = activeSessionId,
              let sessionDate = activeSessionDate,
              activeSessionEnd == nil,
              dose1Time != nil,
              dose2Time == nil,
              !dose2Skipped else {
            return failedMedicationMutation(
                operation: .snooze,
                detail: "Snooze requires an open Dose 2 window and an active Dose 1 session.",
                sessionId: activeSessionId ?? activeSessionDate
            )
        }

        let nextCount = snoozeCount + 1
        let result = recordMedicationMutation(storage.saveSnooze(
            count: nextCount,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        ))
        guard result.isCommitted else {
            return result
        }

        snoozeCount = nextCount
        validateDoseStateInvariant(reason: "snooze")
        
        // Diagnostic logging: snooze activated
        Task {
            await DiagnosticLogger.shared.log(.snoozeActivated, sessionId: sessionId) { entry in
                entry.snoozeCount = self.snoozeCount
            }
        }
        
        sessionDidChange.send()
        return result
    }
    
    /// Mark dose 2 as skipped
    @discardableResult
    public func skipDose2() -> MedicationMutationResult {
        skipDose2(reason: nil, reasonNotes: nil, surface: nil)
    }

    /// Mark dose 2 as skipped with optional structured reason context.
    @discardableResult
    public func skipDose2(
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface? = nil
    ) -> MedicationMutationResult {
        evaluateSessionBoundaries(reason: "skip_dose2_preflight")
        guard let sessionId = activeSessionId,
              let sessionDate = activeSessionDate,
              activeSessionEnd == nil,
              dose1Time != nil,
              dose2Time == nil,
              !dose2Skipped else {
            return failedMedicationMutation(
                operation: .skipDose2,
                detail: "Dose 2 can be skipped only after Dose 1 in an open session.",
                sessionId: activeSessionId ?? activeSessionDate
            )
        }
        let session = (sessionId: sessionId, sessionDate: sessionDate)
        let result = recordMedicationMutation(storage.saveDoseSkipped(
            reason: reason,
            reasonNotes: reasonNotes,
            surface: surface,
            sessionId: session.sessionId,
            sessionDateOverride: session.sessionDate
        ))
        guard result.isCommitted else {
            return result
        }

        activeSessionDate = session.sessionDate
        dose2Skipped = true
        validateDoseStateInvariant(reason: "skip_dose2")
        
        // Diagnostic logging: dose 2 skipped + session completed
        Task {
            await DiagnosticLogger.shared.log(.dose2Skipped, sessionId: session.sessionId) { entry in
                entry.dose1Time = self.dose1Time
            }
        }
        
        // Session is considered complete; cancel any pending notifications (including wake alarms)
        cancelPendingNotifications()
        #if canImport(OSLog)
        logger.info("Dose 2 skipped; notifications cancelled")
        #endif
        
        sessionDidChange.send()
        return result
    }
    
    // MARK: - Pre-Sleep Log
    
    /// Session key to use when saving pre-sleep logs.
    /// If no active session yet (no Dose 1), target the upcoming night.
    public func preSleepDisplaySessionKey(for date: Date = Date()) -> String {
        if let activeSessionDate = activeSessionDate {
            return activeSessionDate
        }
        return preSleepSessionKey(for: date, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
    }

    /// Session key to use for pre-sleep log storage (prefers active session id).
    public func preSleepLogSessionKey(for date: Date = Date()) -> String {
        if let activeSessionId = activeSessionId {
            return activeSessionId
        }
        if let activeSessionDate = activeSessionDate {
            return activeSessionDate
        }
        return preSleepSessionKey(for: date, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
    }

    /// Planner-facing session key. Can move to upcoming night after morning check-in.
    public func plannerSessionKey(for date: Date = Date()) -> String {
        if let activeSessionDate = activeSessionDate {
            return activeSessionDate
        }
        if UserSettingsManager.shared.plannerUsesUpcomingNightAfterCheckIn {
            return preSleepSessionKey(for: date, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
        }
        return sessionKey(for: date, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
    }
    
    /// Save pre-sleep log and broadcast change; throws on persistence failure.
    @discardableResult
    public func savePreSleepLog(
        answers: PreSleepLogAnswers,
        completionState: String = "complete",
        existingLog: StoredPreSleepLog? = nil
    ) throws -> StoredPreSleepLog {
        let now = clock()
        let sessionKey = existingLog?.sessionId ?? preSleepLogSessionKey(for: now)
        
        // Diagnostic logging: Pre-sleep started (Tier 2) - log on first save, not edits
        if existingLog == nil {
            Task {
                await DiagnosticLogger.shared.log(.preSleepLogStarted, sessionId: sessionKey)
            }
        }
        
        let log = try storage.savePreSleepLogOrThrow(
            sessionId: sessionKey,
            answers: answers,
            completionState: completionState,
            now: now,
            timeZone: timeZoneProvider(),
            existingLog: existingLog
        )
        
        // Diagnostic logging: Pre-sleep saved or skipped (Tier 2)
        Task {
            let event: DiagnosticEvent = completionState == "skipped" ? .preSleepLogAbandoned : .preSleepLogSaved
            await DiagnosticLogger.shared.log(event, sessionId: sessionKey)
        }
        
        #if DEBUG
        let count = storage.fetchPreSleepLogCount(sessionId: sessionKey)
        let latest = storage.fetchMostRecentPreSleepLog(sessionId: sessionKey)?.createdAtUtc ?? "nil"
        repoLogger.debug("Pre-sleep log saved session=\(sessionKey) count=\(count) latest_utc=\(latest)")
        #endif
        
        sessionDidChange.send()
        return log
    }
    
    /// Clear tonight's session (for reset/testing)
    public func clearTonight() {
        let currentDate = activeSessionDate ?? currentSessionKey
        storage.deleteSession(sessionDate: currentDate)
        cancelPendingNotifications()
        
        clearInMemoryState()
        
        sessionDidChange.send()
    }
    
    // MARK: - Session Finalization (Wake Up & Check-In)
    
    /// Record when user pressed "Wake Up & End Session"
    /// This puts the session into "finalizing" state
    public func setWakeFinalTime(_ time: Date) {
        let session = ensureActiveSession(for: time, reason: "wake_final")
        wakeFinalTime = time
        activeSessionDate = session.sessionDate
        
        // Persist as sleep event for the correct session key
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "wake_final",
            timestamp: time,
            sessionDate: session.sessionDate,
            sessionId: session.sessionId,
            colorHex: nil,
            notes: nil
        )
        storage.updateTerminalState(sessionDate: session.sessionDate, sessionId: session.sessionId, state: "finalizing_wake")
        
        // Diagnostic logging: Check-in flow started (Tier 2)
        Task {
            await DiagnosticLogger.shared.log(.checkinStarted, sessionId: session.sessionId)
        }

        awaitingRolloverMessage = "Wake logged — complete check-in to close session"
        sessionDidChange.send()
        
        repoLogger.info("SessionRepo: Wake Final logged at \(time)")
    }
    
    /// Mark morning check-in as completed
    /// This transitions session from "finalizing" to "completed"
    public func completeCheckIn() {
        guard let sessionId = activeSessionId, let sessionDate = activeSessionDate else {
            repoLogger.warning("SessionRepo: Check-in completed without active session")
            return
        }
        
        awaitingRolloverMessage = nil
        
        Task {
            await DiagnosticLogger.shared.log(.checkinCompleted, sessionId: sessionId)
        }
        
        closeActiveSession(at: clock(), terminalState: "checkin_completed", reason: "morning_checkin")
        repoLogger.debug("SessionRepo: Morning check-in completed, session closed for \(sessionDate)")
    }
    
    /// Clear wake final time (for undo)
    public func clearWakeFinal() {
        // Diagnostic logging: Check-in skipped/abandoned (Tier 2)
        if let sessionId = activeSessionDate, wakeFinalTime != nil {
            Task {
                await DiagnosticLogger.shared.log(.checkinSkipped, sessionId: sessionId)
            }
        }
        
        wakeFinalTime = nil
        checkInCompleted = false
        
        sessionDidChange.send()
        repoLogger.info("SessionRepo undo: Wake Final cleared (undo)")
    }

    /// Clear Dose 1 (for undo).
    @discardableResult
    public func clearDose1() -> MedicationMutationResult {
        let sessionDate = activeSessionDate ?? currentSessionKey

        let result = recordMedicationMutation(
            storage.clearDoseSequence(sessionDateOverride: sessionDate, sessionId: activeSessionId)
        )
        guard result.isCommitted else { return result }
        clearInMemoryState()
        validateDoseStateInvariant(reason: "clear_dose1")

        sessionDidChange.send()
        repoLogger.info("SessionRepo undo: Dose sequence cleared after Dose 1 undo")
        return result
    }

    /// Clear Dose 2 (for undo).
    @discardableResult
    public func clearDose2() -> MedicationMutationResult {
        let sessionDate = activeSessionDate ?? currentSessionKey

        let result = recordMedicationMutation(
            storage.clearDose2(sessionDateOverride: sessionDate, sessionId: activeSessionId)
        )
        guard result.isCommitted else { return result }
        dose2Time = nil
        validateDoseStateInvariant(reason: "clear_dose2")

        sessionDidChange.send()
        repoLogger.info("SessionRepo undo: Dose 2 cleared (undo)")
        return result
    }

    /// Clear skip status (for undo).
    @discardableResult
    public func clearSkip() -> MedicationMutationResult {
        let sessionDate = activeSessionDate ?? currentSessionKey

        let result = recordMedicationMutation(
            storage.clearSkip(sessionDateOverride: sessionDate, sessionId: activeSessionId)
        )
        guard result.isCommitted else { return result }
        dose2Skipped = false
        validateDoseStateInvariant(reason: "clear_skip")

        sessionDidChange.send()
        repoLogger.info("SessionRepo undo: Skip cleared (undo)")
        return result
    }

    /// Decrement snooze count (for undo).
    @discardableResult
    public func decrementSnoozeCount() -> MedicationMutationResult {
        guard snoozeCount > 0 else {
            return failedMedicationMutation(
                operation: .rollbackSnooze,
                detail: "There is no snooze to undo.",
                sessionId: activeSessionId ?? activeSessionDate
            )
        }
        let sessionDate = activeSessionDate ?? currentSessionKey
        let nextCount = snoozeCount - 1
        let result = recordMedicationMutation(storage.rollbackLatestSnooze(
            toCount: nextCount,
            sessionDateOverride: sessionDate,
            sessionId: activeSessionId
        ))
        guard result.isCommitted else { return result }
        snoozeCount = nextCount
        validateDoseStateInvariant(reason: "decrement_snooze")

        sessionDidChange.send()
        repoLogger.info("SessionRepo undo: Snooze count decremented to \(self.snoozeCount) (undo)")
        return result
    }

    /// Update Dose 1 time for a past session.
    @discardableResult
    public func updateDose1Time(
        newTime: Date,
        sessionDate: String
    ) -> MedicationMutationResult {
        let result = recordMedicationMutation(
            storage.updateDose1Time(newTime: newTime, sessionDate: sessionDate)
        )
        guard result.isCommitted else { return result }

        if result.receipt?.sessionId == activeSessionId {
            dose1Time = newTime
            validateDoseStateInvariant(reason: "update_active_dose1_time")
            sessionDidChange.send()
        }

        Task {
            await DiagnosticLogger.shared.log(.dose1Taken, sessionId: sessionDate) { entry in
                entry.dose1Time = newTime
                entry.reason = "time_adjusted"
            }
        }
        return result
    }

    /// Update Dose 2 time for a past session.
    @discardableResult
    public func updateDose2Time(
        newTime: Date,
        sessionDate: String
    ) -> MedicationMutationResult {
        let result = recordMedicationMutation(
            storage.updateDose2Time(newTime: newTime, sessionDate: sessionDate)
        )
        guard result.isCommitted else { return result }

        if result.receipt?.sessionId == activeSessionId {
            dose2Time = newTime
            validateDoseStateInvariant(reason: "update_active_dose2_time")
            sessionDidChange.send()
        }

        Task {
            await DiagnosticLogger.shared.log(.dose2Taken, sessionId: sessionDate) { entry in
                entry.dose2Time = newTime
                entry.reason = "time_adjusted"
            }
        }
        return result
    }

    /// Backfill or correct Dose 1 from a morning check-in when the overnight tap was missed.
    @discardableResult
    public func reconcileDose1(
        sessionDate: String,
        takenAt: Date,
        amountMg: Int?
    ) -> MedicationMutationResult {
        guard let identity = storage.medicationSessionIdentity(nil, sessionDate: sessionDate) else {
            return failedMedicationMutation(operation: .reconcileDoseState, detail: "Select a specific medication session before reconciliation.", sessionId: nil)
        }
        let existing = fetchDoseEvents(forSessionDate: sessionDate)
            .first { CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose1 }
        let metadata = doseEventMetadata(
            existingMetadata: existing?.metadata,
            amountMg: amountMg,
            source: "morning_reconciliation"
        )
        let result = recordMedicationMutation(storage.reconcileDoseEvent(
            eventType: .dose1,
            timestamp: takenAt,
            sessionDate: sessionDate,
            sessionId: identity,
            metadata: metadata
        ))
        guard result.isCommitted else { return result }

        if result.receipt?.sessionId == activeSessionId {
            dose1Time = takenAt
            validateDoseStateInvariant(reason: "reconcile_active_dose1")
            sessionDidChange.send()
        }
        return result
    }

    /// Backfill or correct Dose 2 from a morning check-in when the overnight tap was missed.
    @discardableResult
    public func reconcileDose2(
        sessionDate: String,
        takenAt: Date,
        amountMg: Int?,
        reason: String? = nil,
        reasonNotes: String? = nil
    ) -> MedicationMutationResult {
        guard let identity = storage.medicationSessionIdentity(nil, sessionDate: sessionDate) else {
            return failedMedicationMutation(operation: .reconcileDoseState, detail: "Select a specific medication session before reconciliation.", sessionId: nil)
        }
        let existing = fetchDoseEvents(forSessionDate: sessionDate)
            .first { CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose2 }
        let metadata = doseEventMetadata(
            existingMetadata: existing?.metadata,
            amountMg: amountMg,
            source: "morning_reconciliation",
            reason: reason,
            reasonNotes: reasonNotes
        )
        let result = recordMedicationMutation(storage.reconcileDoseEvent(
            eventType: .dose2,
            timestamp: takenAt,
            sessionDate: sessionDate,
            sessionId: identity,
            metadata: metadata
        ))
        guard result.isCommitted else { return result }

        if result.receipt?.sessionId == activeSessionId {
            dose2Time = takenAt
            dose2Skipped = false
            validateDoseStateInvariant(reason: "reconcile_active_dose2")
            sessionDidChange.send()
        }
        return result
    }

    /// Mark Dose 2 skipped during morning reconciliation without reopening the active-session flow.
    @discardableResult
    public func reconcileDose2Skipped(
        sessionDate: String,
        timestamp: Date? = nil,
        reason: String? = nil,
        reasonNotes: String? = nil
    ) -> MedicationMutationResult {
        guard let identity = storage.medicationSessionIdentity(nil, sessionDate: sessionDate) else {
            return failedMedicationMutation(operation: .reconcileDoseState, detail: "Select a specific medication session before reconciliation.", sessionId: nil)
        }
        let existingSkip = fetchDoseEvents(forSessionDate: sessionDate)
            .first { CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose2Skipped }
        let metadata = doseEventMetadata(
            existingMetadata: existingSkip?.metadata,
            amountMg: nil,
            source: "morning_reconciliation",
            reason: reason,
            reasonNotes: reasonNotes
        )
        let result = recordMedicationMutation(storage.reconcileDoseEvent(
            eventType: .dose2Skipped,
            timestamp: timestamp ?? clock(),
            sessionDate: sessionDate,
            sessionId: identity,
            metadata: metadata
        ))
        guard result.isCommitted else { return result }

        if result.receipt?.sessionId == activeSessionId {
            dose2Skipped = true
            dose2Time = nil
            validateDoseStateInvariant(reason: "reconcile_active_dose2_skip")
            sessionDidChange.send()
        }
        return result
    }

    @discardableResult
    public func updateDose2OutcomeAnnotations(
        sessionDate: String,
        takenReason: String?,
        skipReason: String?,
        reasonNotes: String?
    ) -> MedicationMutationResult {
        guard let identity = storage.medicationSessionIdentity(nil, sessionDate: sessionDate) else {
            return failedMedicationMutation(operation: .reconcileDoseState, detail: "Select a specific medication session before editing its annotations.", sessionId: nil)
        }
        let events = storage.fetchDoseEvents(sessionId: identity, sessionDate: sessionDate)
        let dose2Event = events.first {
            CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose2
        }
        let skippedEvent = events.first {
            CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose2Skipped
        }
        let dose2Metadata = doseEventMetadata(
            existingMetadata: dose2Event?.metadata,
            amountMg: nil,
            source: nil,
            reason: takenReason,
            reasonNotes: reasonNotes
        )
        let skippedMetadata = doseEventMetadata(
            existingMetadata: skippedEvent?.metadata,
            amountMg: nil,
            source: nil,
            reason: skipReason,
            reasonNotes: reasonNotes
        )
        return recordMedicationMutation(storage.updateDose2OutcomeAnnotations(
            sessionDate: sessionDate,
            dose2Metadata: dose2Metadata,
            skippedMetadata: skippedMetadata,
            sessionId: identity
        ))
    }

    /// Update event time for a sleep event.
    public func updateEventTime(eventId: String, newTime: Date) {
        storage.updateSleepEventTime(eventId: eventId, newTime: newTime)
        sessionDidChange.send()
    }

    /// Update notes on a sleep event. Pass nil or empty to clear.
    public func updateEventNotes(eventId: String, notes: String?) {
        storage.updateSleepEventNotes(eventId: eventId, notes: notes)
        sessionDidChange.send()
    }
    
    // MARK: - Data Management
    
    /// Clear all data from storage (factory reset)
    /// ⚠️ DESTRUCTIVE: This removes all dose logs, sleep events, check-ins, etc.
    public func clearAllData() {
        storage.clearAllData()
        cancelPendingNotifications()
        
        // Reset in-memory state
        clearInMemoryState()
        
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
    
}
