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
public final class SessionRepository: ObservableObject, @preconcurrency DoseTapSessionRepository {
    
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
    
    /// Emits whenever session data changes (for observers that need explicit signal)
    public let sessionDidChange = PassthroughSubject<Void, Never>()
    
    // MARK: - Phase Tracking (for diagnostic logging)
    /// Tracks last known phase to detect transitions at edges
    private var lastLoggedPhase: DoseWindowPhase?
    
    // MARK: - Dependencies
    let storage: EventStorage
    private let notificationScheduler: NotificationScheduling
    let clock: () -> Date
    let timeZoneProvider: () -> TimeZone
    let rolloverHour: Int
    private var rolloverTimer: Timer?
    private var observers: [NSObjectProtocol] = []
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
        currentSessionKey = storage.currentSessionDate()
        var state = storage.loadCurrentSessionState()

        if let d1 = state.dose1Time, let d2 = state.dose2Time {
            let delta = d2.timeIntervalSince(d1)
            if delta < 0 || delta > 12 * 60 * 60 {
                if let sessionDate = state.sessionDate {
                    repoLogger.warning("SessionRepo: Clearing stale dose2 time for session \(sessionDate)")
                    storage.clearDose2(sessionDateOverride: sessionDate)
                    state = storage.loadCurrentSessionState()
                }
            }
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

    // MARK: - Schedule Helpers

    private func timeFromMinutes(_ minutes: Int, on date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        
        let day = calendar.startOfDay(for: date)
        let hour = minutes / 60
        let minute = minutes % 60
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func nextOccurrence(of minutes: Int, after date: Date, timeZone: TimeZone) -> Date {
        let candidate = timeFromMinutes(minutes, on: date, timeZone: timeZone)
        if candidate > date {
            return candidate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let nextDay = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return timeFromMinutes(minutes, on: nextDay, timeZone: timeZone)
    }
    
    private func prepTime(for date: Date) -> Date {
        let minutes = UserSettingsManager.shared.prepTimeMinutes
        return timeFromMinutes(minutes, on: date, timeZone: timeZoneProvider())
    }

    private func isDoseEventType(_ eventType: String) -> Bool {
        switch eventType {
        case "dose1", "dose2", "extra_dose":
            return true
        default:
            return false
        }
    }

    private func doseWindowCloseTime(dose1Time: Date) -> Date {
        let config = DoseCore.DoseWindowConfig()
        return dose1Time.addingTimeInterval(TimeInterval(config.maxIntervalMin * 60))
    }

    func loadDoseEvents(sessionId: String?, sessionDate: String) -> [DoseCore.StoredDoseEvent] {
        storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
    }

    static func parseSessionDate(_ sessionDate: String, in timeZone: TimeZone) -> Date? {
        let parts = sessionDate.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }
    
    private func sessionDateToDate(_ sessionDate: String) -> Date? {
        Self.parseSessionDate(sessionDate, in: timeZoneProvider())
    }

    private func scheduledSleepStart(for sessionDate: String) -> Date? {
        guard let day = sessionDateToDate(sessionDate) else { return nil }
        let minutes = UserSettingsManager.shared.sleepStartMinutes
        return timeFromMinutes(minutes, on: day, timeZone: timeZoneProvider())
    }
    
    private func cutoffTime(for sessionStart: Date) -> Date {
        let settings = UserSettingsManager.shared
        let wake = nextOccurrence(of: settings.wakeTimeMinutes, after: sessionStart, timeZone: timeZoneProvider())
        return wake.addingTimeInterval(TimeInterval(settings.missedCheckInCutoffHours * 3600))
    }
    
    /// Evaluate session boundaries driven by schedule (prep time + missed check-in cutoff).
    public func evaluateSessionBoundaries(reason: String) {
        guard activeSessionId != nil, let sessionDate = activeSessionDate else { return }
        guard activeSessionEnd == nil else { return }
        
        let now = clock()
        let prep = prepTime(for: now)
        let scheduledStart = scheduledSleepStart(for: sessionDate)
        let start = activeSessionStart ?? dose1Time ?? scheduledStart ?? now
        let cutoff = cutoffTime(for: start)
        
        if now >= cutoff {
            closeActiveSession(at: now, terminalState: "incomplete_missed_checkin", reason: "missed_checkin_cutoff.\(reason)")
            repoLogger.info("SessionRepo: Auto-closed session \(sessionDate) (cutoff reached)")
            return
        }
        
        if now >= prep && start < prep {
            closeActiveSession(at: now, terminalState: "incomplete_prep_rollover", reason: "prep_time.\(reason)")
            repoLogger.info("SessionRepo: Soft rollover at prep time for session \(sessionDate)")
        }
    }
    
    // MARK: - Mutations

    /// Ensure there is an active session for the given timestamp.
    private func ensureActiveSession(for timestamp: Date, reason: String) -> (sessionId: String, sessionDate: String) {
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
    private func closeActiveSession(at endTime: Date, terminalState: String, reason: String) {
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
    public func setDose1Time(_ time: Date) {
        let session = ensureActiveSession(for: time, reason: "dose1")
        dose1Time = time
        if activeSessionStart == nil {
            activeSessionStart = time
        }
        activeSessionDate = session.sessionDate
        dose2Time = nil
        dose2Skipped = false
        snoozeCount = 0
        wakeFinalTime = nil
        checkInCompleted = false
        
        // Record timezone offset when Dose 1 is taken (track both autoupdating and default time zones)
        dose1TimezoneOffsetMinutes = timeZoneProvider().secondsFromGMT(for: time) / 60
        
        // Persist to storage
        // Keep Dose 1 canonical per session: repeated calls are edits, not additional dose events.
        storage.clearDose1(sessionDateOverride: session.sessionDate)
        storage.saveDose1(timestamp: time, sessionId: session.sessionId, sessionDateOverride: session.sessionDate)
        storage.linkPreSleepLogToSession(sessionId: session.sessionId, sessionDate: session.sessionDate)
        
        // Diagnostic logging: session started + dose 1 taken
        Task {
            await DiagnosticLogger.shared.logDoseTaken(sessionId: session.sessionId, doseIndex: 1, at: time)
        }
        
        sessionDidChange.send()
        scheduleRolloverTimer()
    }
    
    /// Record dose 2+ time (dose index is derived from session events, not the clock).
    public func setDose2Time(_ time: Date, isEarly: Bool = false, isExtraDose: Bool = false) {
        let session = ensureActiveSession(for: time, reason: "dose2")
        let doseEvents = loadDoseEvents(sessionId: session.sessionId, sessionDate: session.sessionDate)
        let doseTakenEvents = doseEvents.filter { isDoseEventType($0.eventType) }
        let sortedEvents = doseTakenEvents.sorted { $0.timestamp < $1.timestamp }
        
        let nextDoseIndex = sortedEvents.count + 1
        let isExtra = nextDoseIndex >= 3
        if isExtraDose && !isExtra {
            Task {
                await DiagnosticLogger.shared.log(.invariantViolation, sessionId: session.sessionId) { entry in
                    entry.invariantName = "extra_dose_without_dose2"
                }
            }
        }
        
        let isDose2 = nextDoseIndex == 2 && !isExtra
        let firstDoseTime = dose1Time ?? sortedEvents.first?.timestamp
        let isLate = isDose2 && firstDoseTime.map { time > doseWindowCloseTime(dose1Time: $0) } == true
        let previousDoseTime = sortedEvents.last?.timestamp
        let elapsedSincePrev = previousDoseTime.map { TimeIntervalMath.minutesBetween(start: $0, end: time) }
        let elapsedSinceFirst = firstDoseTime.map { TimeIntervalMath.minutesBetween(start: $0, end: time) }
        
        if isDose2 {
            dose2Time = time
            if dose2Skipped {
                dose2Skipped = false
                storage.clearSkip(sessionDateOverride: session.sessionDate)
            }
        }
        activeSessionDate = session.sessionDate
        
        // Persist to storage
        storage.saveDose2(
            timestamp: time,
            isEarly: isEarly,
            isExtraDose: isExtra,
            isLate: isLate,
            sessionId: session.sessionId,
            sessionDateOverride: session.sessionDate
        )
        
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
    }
    
    /// Increment snooze count
    public func incrementSnooze() {
        let now = clock()
        let session = ensureActiveSession(for: now, reason: "snooze")
        snoozeCount += 1
        activeSessionDate = session.sessionDate
        
        // Persist to storage
        storage.saveSnooze(count: snoozeCount, sessionId: session.sessionId, sessionDateOverride: session.sessionDate)
        
        // Diagnostic logging: snooze activated
        Task {
            await DiagnosticLogger.shared.log(.snoozeActivated, sessionId: session.sessionId) { entry in
                entry.snoozeCount = self.snoozeCount
            }
        }
        
        sessionDidChange.send()
    }
    
    /// Mark dose 2 as skipped
    public func skipDose2() {
        let now = clock()
        let session = ensureActiveSession(for: now, reason: "skip")
        activeSessionDate = session.sessionDate
        dose2Skipped = true
        
        // Persist to storage
        storage.saveDoseSkipped(sessionId: session.sessionId, sessionDateOverride: session.sessionDate)
        
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
        let sessionDate = activeSessionDate ?? currentSessionKey
        dose1Time = nil
        activeSessionDate = nil
        dose1TimezoneOffsetMinutes = nil
        
        // Clear from storage
        storage.clearDose1(sessionDateOverride: sessionDate)
        
        sessionDidChange.send()
        repoLogger.info("SessionRepo undo: Dose 1 cleared (undo)")
    }
    
    /// Clear Dose 2 (for undo)
    public func clearDose2() {
        let sessionDate = activeSessionDate ?? currentSessionKey
        dose2Time = nil
        
        // Clear from storage
        storage.clearDose2(sessionDateOverride: sessionDate)
        
        sessionDidChange.send()
        repoLogger.info("SessionRepo undo: Dose 2 cleared (undo)")
    }
    
    /// Clear skip status (for undo)
    public func clearSkip() {
        let sessionDate = activeSessionDate ?? currentSessionKey
        dose2Skipped = false
        
        // Clear from storage
        storage.clearSkip(sessionDateOverride: sessionDate)
        
        sessionDidChange.send()
        repoLogger.info("SessionRepo undo: Skip cleared (undo)")
    }
    
    /// Decrement snooze count (for undo)
    public func decrementSnoozeCount() {
        if snoozeCount > 0 {
            snoozeCount -= 1
            
            // Persist to storage
            storage.saveSnooze(count: snoozeCount)
            
            sessionDidChange.send()
            repoLogger.info("SessionRepo undo: Snooze count decremented to \(self.snoozeCount) (undo)")
        }
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
        
        let sessionId = activeSessionId ?? currentSessionIdString()
        let sessionDate = activeSessionDate ?? storage.currentSessionDate()
        repoLogger.info("SessionRepo: Auto-marking session as slept-through (window + grace expired)")
        
        // Save skip with slept-through reason
        storage.saveDoseSkipped(reason: "slept_through", sessionId: sessionId, sessionDateOverride: sessionDate)
        
        // Update terminal state
        storage.updateTerminalState(sessionDate: sessionDate, sessionId: sessionId, state: "incomplete_slept_through")
        
        // Diagnostic logging: session auto-expired
        Task {
            await DiagnosticLogger.shared.log(.sessionAutoExpired, sessionId: sessionId) { entry in
                entry.terminalState = "incomplete_slept_through"
                entry.dose1Time = self.dose1Time
                entry.reason = "slept_through"
            }
        }
        
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
    
    // MARK: - Computed Context (for UI binding)
    
    /// Lazily initialized window calculator for context computation
    private static let windowCalculator = DoseWindowCalculator()
    
    /// Computed dose window context based on current session state.
    /// This is THE context that UI should bind to - it derives from repository state.
    public var currentContext: DoseWindowContext {
        let context = SessionRepository.windowCalculator.context(
            dose1At: dose1Time,
            dose2TakenAt: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount,
            wakeFinalAt: wakeFinalTime,
            checkInCompleted: checkInCompleted
        )
        
        // Log phase transitions (edges only)
        checkAndLogPhaseTransition(newPhase: context.phase, context: context)
        
        return context
    }
    
    /// Check if phase changed and log transition (diagnostic logging at edges)
    private func checkAndLogPhaseTransition(newPhase: DoseWindowPhase, context: DoseWindowContext) {
        guard let sessionId = activeSessionId ?? activeSessionDate else { return }
        guard newPhase != lastLoggedPhase else { return }
        
        let previousPhase = lastLoggedPhase
        lastLoggedPhase = newPhase
        
        // Map phase to diagnostic event
        let event: DiagnosticEvent
        switch newPhase {
        case .active where previousPhase == .beforeWindow:
            event = .doseWindowOpened
        case .nearClose where previousPhase == .active:
            event = .doseWindowNearClose
        case .closed where previousPhase == .nearClose || previousPhase == .active:
            event = .doseWindowExpired
        default:
            event = .sessionPhaseEntered
        }
        
        let elapsed = context.elapsedSinceDose1.map { Int($0 / 60) }
        let remaining = context.remainingToMax.map { Int($0 / 60) }
        
        Task {
            await DiagnosticLogger.shared.log(event, sessionId: sessionId) { entry in
                entry.phase = String(describing: newPhase)
                entry.previousPhase = previousPhase.map { String(describing: $0) }
                entry.elapsedMinutes = elapsed
                entry.remainingMinutes = remaining
                entry.snoozeCount = context.snoozeCount
            }
        }
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
        let session = ensureActiveSession(for: timestamp, reason: "sleep_event")
        let eventId = UUID().uuidString
        
        storage.insertSleepEvent(
            id: eventId,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: session.sessionDate,
            sessionId: session.sessionId,
            colorHex: nil,
            notes: notes
        )
        
        // Diagnostic logging (Tier 2: Session Context)
        Task {
            await DiagnosticLogger.shared.logSleepEventLogged(
                sessionId: session.sessionId,
                eventType: eventType,
                eventId: eventId
            )
        }
        
        #if canImport(OSLog)
        logger.info("Sleep event '\(eventType)' logged for session \(session.sessionDate)")
        #endif
        
        sessionDidChange.send()
    }
    
    /// Delete a sleep event by ID
    public func deleteSleepEvent(id: String) {
        // Get event type before deleting (for diagnostic logging)
        let events = storage.fetchSleepEvents(forSession: currentSessionKey)
        let eventType = events.first(where: { $0.id == id })?.eventType ?? "unknown"
        
        storage.deleteSleepEvent(id: id)
        
        // Diagnostic logging (Tier 2: Session Context)
        Task {
            await DiagnosticLogger.shared.logSleepEventDeleted(
                sessionId: currentSessionKey,
                eventType: eventType,
                eventId: id
            )
        }
        
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
    
    // MARK: - Time Editing Methods (Manual Entry Support)
    
    /// Update Dose 1 time for a past session
    /// - Parameters:
    ///   - newTime: The corrected time
    ///   - sessionDate: The session date string (YYYY-MM-DD format)
    public func updateDose1Time(newTime: Date, sessionDate: String) {
        storage.updateDose1Time(newTime: newTime, sessionDate: sessionDate)
        
        // If editing current session, update in-memory state
        if sessionDate == activeSessionDate {
            dose1Time = newTime
            sessionDidChange.send()
        }
        
        // Log the edit
        Task {
            await DiagnosticLogger.shared.log(.dose1Taken, sessionId: sessionDate) { entry in
                entry.dose1Time = newTime
                entry.reason = "time_adjusted"
            }
        }
    }
    
    /// Update Dose 2 time for a past session
    /// - Parameters:
    ///   - newTime: The corrected time
    ///   - sessionDate: The session date string (YYYY-MM-DD format)
    public func updateDose2Time(newTime: Date, sessionDate: String) {
        storage.updateDose2Time(newTime: newTime, sessionDate: sessionDate)
        
        // If editing current session, update in-memory state
        if sessionDate == activeSessionDate {
            dose2Time = newTime
            sessionDidChange.send()
        }
        
        // Log the edit
        Task {
            await DiagnosticLogger.shared.log(.dose2Taken, sessionId: sessionDate) { entry in
                entry.dose2Time = newTime
                entry.reason = "time_adjusted"
            }
        }
    }

    /// Backfill or correct Dose 1 from a morning check-in when the overnight tap was missed.
    public func reconcileDose1(sessionDate: String, takenAt: Date, amountMg: Int?) {
        upsertDoseEvent(
            eventType: "dose1",
            sessionDate: sessionDate,
            timestamp: takenAt,
            amountMg: amountMg
        )

        if sessionDate == activeSessionDate {
            dose1Time = takenAt
            sessionDidChange.send()
        }
    }

    /// Backfill or correct Dose 2 from a morning check-in when the overnight tap was missed.
    public func reconcileDose2(sessionDate: String, takenAt: Date, amountMg: Int?) {
        storage.clearSkip(sessionDateOverride: sessionDate)
        upsertDoseEvent(
            eventType: "dose2",
            sessionDate: sessionDate,
            timestamp: takenAt,
            amountMg: amountMg
        )

        if sessionDate == activeSessionDate {
            dose2Time = takenAt
            dose2Skipped = false
            sessionDidChange.send()
        }
    }

    /// Mark Dose 2 skipped during morning reconciliation without reopening the active-session flow.
    public func reconcileDose2Skipped(sessionDate: String, timestamp: Date = Date()) {
        let existingSkip = fetchDoseEvents(forSessionDate: sessionDate)
            .first { $0.eventType == "dose2_skipped" }
        let metadata = doseEventMetadata(amountMg: nil, source: "morning_reconciliation")

        if let existingSkip {
            storage.updateDoseEventMetadata(eventId: existingSkip.id, metadata: metadata)
        } else {
            storage.insertDoseEvent(
                eventType: "dose2_skipped",
                timestamp: timestamp,
                sessionKey: sessionDate,
                metadata: metadata
            )
        }

        if sessionDate == activeSessionDate {
            dose2Skipped = true
            dose2Time = nil
            sessionDidChange.send()
        }
    }

    private func upsertDoseEvent(
        eventType: String,
        sessionDate: String,
        timestamp: Date,
        amountMg: Int?
    ) {
        let existing = fetchDoseEvents(forSessionDate: sessionDate)
            .first { $0.eventType == eventType }
        let metadata = doseEventMetadata(amountMg: amountMg, source: "morning_reconciliation")

        if let existing {
            switch eventType {
            case "dose1":
                storage.updateDose1Time(newTime: timestamp, sessionDate: sessionDate)
            case "dose2":
                storage.updateDose2Time(newTime: timestamp, sessionDate: sessionDate)
            default:
                break
            }
            storage.updateDoseEventMetadata(eventId: existing.id, metadata: metadata)
        } else {
            storage.insertDoseEvent(
                eventType: eventType,
                timestamp: timestamp,
                sessionKey: sessionDate,
                metadata: metadata
            )
        }
    }

    private func doseEventMetadata(amountMg: Int?, source: String) -> String? {
        var metadata: [String: Any] = ["source": source]
        if let amountMg {
            metadata["amount_mg"] = amountMg
        }
        guard let data = try? JSONSerialization.data(withJSONObject: metadata) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    /// Update event time for a sleep event
    /// - Parameters:
    ///   - eventId: The event UUID
    ///   - newTime: The corrected time
    public func updateEventTime(eventId: String, newTime: Date) {
        storage.updateSleepEventTime(eventId: eventId, newTime: newTime)
        sessionDidChange.send()
    }
    
    // MARK: - Additional Storage Facade Methods (Views must use these, not EventStorage directly)
    
    /// Link pre-sleep log to session
    public func linkPreSleepLogToSession(sessionId: String) {
        let sessionDate = activeSessionDate ?? currentSessionKey
        storage.linkPreSleepLogToSession(sessionId: sessionId, sessionDate: sessionDate)
    }
    
    /// Clear tonight's events (for session reset)
    public func clearTonightsEvents() {
        storage.clearTonightsEvents(sessionDateOverride: activeSessionDate ?? currentSessionKey)
    }
    
    /// Save dose 1 timestamp - SSOT: Updates in-memory state AND persists to storage
    /// Use this or setDose1Time() - they are now equivalent
    public func saveDose1(timestamp: Date) {
        setDose1Time(timestamp)
    }
    
    /// Save dose 2 timestamp with optional flags - SSOT: Updates in-memory state AND persists to storage
    /// Use this or setDose2Time() - they are now equivalent
    public func saveDose2(timestamp: Date, isEarly: Bool = false, isExtraDose: Bool = false) {
        setDose2Time(timestamp, isEarly: isEarly, isExtraDose: isExtraDose)
    }

    /// Insert sleep event (for event logging)
    public func insertSleepEvent(id: String, eventType: String, timestamp: Date, colorHex: String?, notes: String? = nil) {
        let session = ensureActiveSession(for: timestamp, reason: "sleep_event_insert")
        let normalizedType = eventType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        storage.insertSleepEvent(
            id: id,
            eventType: normalizedType,
            timestamp: timestamp,
            sessionDate: session.sessionDate,
            sessionId: session.sessionId,
            colorHex: colorHex,
            notes: notes
        )
    }

    /// Upsert sleep event imported from sync with explicit session identity.
    public func upsertSleepEventFromSync(
        id: String,
        eventType: String,
        timestamp: Date,
        sessionDate: String,
        sessionId: String?,
        colorHex: String?,
        notes: String?
    ) {
        storage.insertSleepEvent(
            id: id,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: sessionDate,
            sessionId: sessionId ?? sessionDate,
            colorHex: colorHex,
            notes: notes
        )
    }

    /// Upsert dose event imported from sync with explicit id.
    public func upsertDoseEventFromSync(
        id: String,
        eventType: String,
        timestamp: Date,
        sessionDate: String,
        sessionId: String?,
        metadata: String?
    ) {
        storage.upsertDoseEvent(
            id: id,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: sessionDate,
            sessionId: sessionId ?? sessionDate,
            metadata: metadata
        )
    }

    /// Upsert morning check-in imported from sync.
    public func upsertMorningCheckInFromSync(_ checkIn: StoredMorningCheckIn) {
        if let existing = fetchMorningCheckIn(for: checkIn.sessionDate) {
            if existing.timestamp > checkIn.timestamp {
                return
            }
        }
        storage.saveMorningCheckIn(checkIn, forSession: checkIn.sessionDate)
    }

    /// Upsert pre-sleep log imported from sync.
    public func upsertPreSleepLogFromSync(_ log: StoredPreSleepLog, sessionDate: String) {
        storage.upsertPreSleepLogFromSync(log, sessionDate: sessionDate)
    }

    /// Upsert medication event imported from sync.
    public func upsertMedicationEventFromSync(_ entry: StoredMedicationEntry) {
        storage.upsertMedicationEvent(entry)
    }

    /// Delete a sleep event imported as removed by sync.
    public func deleteSleepEventFromSync(id: String) {
        storage.deleteSleepEvent(id: id, recordCloudKitDeletion: false)
    }

    /// Delete a dose event imported as removed by sync.
    public func deleteDoseEventFromSync(id: String) {
        storage.deleteDoseEvent(id: id, recordCloudKitDeletion: false)
    }

    /// Delete a morning check-in imported as removed by sync.
    public func deleteMorningCheckInFromSync(id: String) {
        storage.deleteMorningCheckIn(id: id, recordCloudKitDeletion: false)
    }

    /// Delete a pre-sleep log imported as removed by sync.
    public func deletePreSleepLogFromSync(id: String) {
        storage.deletePreSleepLog(id: id, recordCloudKitDeletion: false)
    }

    /// Delete a medication event imported as removed by sync.
    public func deleteMedicationEventFromSync(id: String) {
        storage.deleteMedicationEvent(id: id, recordCloudKitDeletion: false)
    }

    /// Delete a whole session imported as removed by sync.
    public func deleteSessionFromSync(sessionDate: String) {
        storage.deleteSession(sessionDate: sessionDate, recordCloudKitDeletion: false)
    }

    /// Reload and broadcast after a sync import batch is applied.
    public func finalizeSyncImport() {
        reload()
    }
    
}
