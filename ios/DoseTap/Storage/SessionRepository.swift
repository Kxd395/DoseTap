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
        currentSessionKey = storage.currentSessionDate()
        var state = storage.loadCurrentSessionState()

        if let d1 = state.dose1Time, let d2 = state.dose2Time {
            let delta = d2.timeIntervalSince(d1)
            if delta < 0 || delta > 12 * 60 * 60 {
                if let sessionDate = state.sessionDate {
                    print("⚠️ SessionRepository: Clearing stale dose2 time for session \(sessionDate)")
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
        
        print("📊 SessionRepository reloaded: session=\(activeSessionDate ?? "none"), dose1=\(dose1Time?.description ?? "nil"), dose2=\(dose2Time?.description ?? "nil")")
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
            print("🔄 SessionRepository: Rollover \(currentSessionKey) -> \(newKey) (reason: \(reason))")
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

    private func loadDoseEvents(sessionId: String?, sessionDate: String) -> [DoseCore.StoredDoseEvent] {
        storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
    }

    private func sessionDateToDate(_ sessionDate: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZoneProvider()
        return formatter.date(from: sessionDate)
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
            print("⏳ SessionRepository: Auto-closed session \(sessionDate) (cutoff reached)")
            return
        }
        
        if now >= prep && start < prep {
            closeActiveSession(at: now, terminalState: "incomplete_prep_rollover", reason: "prep_time.\(reason)")
            print("🌙 SessionRepository: Soft rollover at prep time for session \(sessionDate)")
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
        dose2Skipped = true
        let now = clock()
        let session = ensureActiveSession(for: now, reason: "skip")
        activeSessionDate = session.sessionDate
        
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
        print("🧾 Pre-sleep log saved session=\(sessionKey) count=\(count) latest_utc=\(latest)")
        #endif
        
        sessionDidChange.send()
        return log
    }
    
    /// Clear tonight's session (for reset/testing)
    public func clearTonight() {
        let currentDate = activeSessionDate ?? storage.currentSessionDate()
        storage.deleteSession(sessionDate: currentDate)
        
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
        print("↩️ SessionRepository: Dose 1 cleared (undo)")
    }
    
    /// Clear Dose 2 (for undo)
    public func clearDose2() {
        let sessionDate = activeSessionDate ?? currentSessionKey
        dose2Time = nil
        
        // Clear from storage
        storage.clearDose2(sessionDateOverride: sessionDate)
        
        sessionDidChange.send()
        print("↩️ SessionRepository: Dose 2 cleared (undo)")
    }
    
    /// Clear skip status (for undo)
    public func clearSkip() {
        let sessionDate = activeSessionDate ?? currentSessionKey
        dose2Skipped = false
        
        // Clear from storage
        storage.clearSkip(sessionDateOverride: sessionDate)
        
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
        
        print("☀️ SessionRepository: Wake Final logged at \(time)")
    }
    
    /// Mark morning check-in as completed
    /// This transitions session from "finalizing" to "completed"
    public func completeCheckIn() {
        guard let sessionId = activeSessionId, let sessionDate = activeSessionDate else {
            print("⚠️ SessionRepository: Check-in completed without active session")
            return
        }
        
        awaitingRolloverMessage = nil
        
        Task {
            await DiagnosticLogger.shared.log(.checkinCompleted, sessionId: sessionId)
        }
        
        closeActiveSession(at: clock(), terminalState: "checkin_completed", reason: "morning_checkin")
        print("✅ SessionRepository: Morning check-in completed, session closed for \(sessionDate)")
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
        
        let sessionId = activeSessionId ?? currentSessionIdString()
        let sessionDate = activeSessionDate ?? storage.currentSessionDate()
        print("😴 SessionRepository: Auto-marking session as slept-through (window + grace expired)")
        
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
    
    /// Get the current session date string (based on 6PM boundary)
    public func currentSessionDateString() -> String {
        return activeSessionDate ?? currentSessionKey
    }

    /// Get the current session id (falls back to session_date for legacy rows)
    public func currentSessionIdString() -> String {
        return activeSessionId ?? activeSessionDate ?? currentSessionKey
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
        let sessionId: String? = sessionDate == activeSessionDate ? activeSessionId : nil
        
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
        let sessionDate = sessionDateOverride ?? activeSessionDate ?? currentSessionKey
        let resolvedSessionId = activeSessionId ?? checkIn.sessionId
        
        // Convert to EventStorage's StoredMorningCheckIn type
        let storedCheckIn = StoredMorningCheckIn(
            id: checkIn.id,
            sessionId: resolvedSessionId,
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
        
        if resolvedSessionId == activeSessionId {
            // Mark check-in completed for the active session
            completeCheckIn()
        } else {
            Task {
                await DiagnosticLogger.shared.log(.checkinCompleted, sessionId: resolvedSessionId)
            }
            storage.closeHistoricalSession(
                sessionId: resolvedSessionId,
                sessionDate: sessionDate,
                end: clock(),
                terminalState: "checkin_completed"
            )
        }
        
        #if canImport(OSLog)
        logger.info("Morning check-in saved for session \(sessionDate)")
        #endif
        
    }
    
    /// Fetch morning check-in for a session
    public func fetchMorningCheckIn(for sessionDate: String) -> StoredMorningCheckIn? {
        // EventStorage returns DoseCore type, convert to local type
        guard let coreCheckIn = storage.fetchMorningCheckIn(sessionKey: sessionDate) else { return nil }
        return convertMorningCheckIn(coreCheckIn)
    }
    
    /// Fetch morning check-in for current session
    public func fetchMorningCheckInForCurrentSession() -> StoredMorningCheckIn? {
        let key = activeSessionId ?? activeSessionDate ?? currentSessionKey
        guard let coreCheckIn = storage.fetchMorningCheckIn(sessionKey: key) else { return nil }
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
    
    /// Fetch tonight's sleep events for current session
    public func fetchTonightSleepEvents() -> [StoredSleepEvent] {
        if let sessionId = activeSessionId {
            return storage.fetchSleepEvents(forSessionId: sessionId)
        }
        if let sessionDate = activeSessionDate {
            return storage.fetchSleepEvents(forSession: sessionDate)
        }
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

    /// Fetch dose events for the active session (ordered by timestamp asc).
    public func fetchDoseEventsForActiveSession() -> [DoseCore.StoredDoseEvent] {
        let sessionDate = activeSessionDate ?? currentSessionKey
        return loadDoseEvents(sessionId: activeSessionId, sessionDate: sessionDate)
    }

    /// Fetch dose events for a specific session date (ordered by timestamp asc).
    public func fetchDoseEvents(forSessionDate sessionDate: String) -> [DoseCore.StoredDoseEvent] {
        loadDoseEvents(sessionId: fetchSessionId(forSessionDate: sessionDate), sessionDate: sessionDate)
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

    /// Fetch session id for a given session date (if available).
    public func fetchSessionId(forSessionDate sessionDate: String) -> String? {
        return storage.fetchSessionId(forSessionDate: sessionDate)
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
    
    /// Update event time for a sleep event
    /// - Parameters:
    ///   - eventId: The event UUID
    ///   - newTime: The corrected time
    public func updateEventTime(eventId: String, newTime: Date) {
        storage.updateSleepEventTime(eventId: eventId, newTime: newTime)
        sessionDidChange.send()
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
        let excluded = activeSessionDate ?? currentSessionKey
        return storage.mostRecentIncompleteSession(excluding: excluded)
    }
    
    /// Link pre-sleep log to session
    public func linkPreSleepLogToSession(sessionId: String) {
        let sessionDate = activeSessionDate ?? currentSessionKey
        storage.linkPreSleepLogToSession(sessionId: sessionId, sessionDate: sessionDate)
    }
    
    /// Clear tonight's events (for session reset)
    public func clearTonightsEvents() {
        storage.clearTonightsEvents(sessionDateOverride: activeSessionDate ?? currentSessionKey)
    }
    
    /// Fetch pre-sleep log by session ID
    public func fetchMostRecentPreSleepLog(sessionId: String) -> StoredPreSleepLog? {
        return storage.fetchMostRecentPreSleepLog(sessionId: sessionId)
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
        storage.insertSleepEvent(
            id: id,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: session.sessionDate,
            sessionId: session.sessionId,
            colorHex: colorHex,
            notes: notes
        )
    }
    
    // MARK: - Night Review Support
    
    /// Fetch list of recent session keys for picker
    public func getRecentSessionKeys(limit: Int = 30) -> [String] {
        return storage.fetchRecentSessionsLocal(days: limit).map { $0.sessionDate }
    }
    
    /// Fetch sleep events for a specific session (local type)
    public func fetchSleepEventsLocal(for sessionKey: String) -> [StoredSleepEvent] {
        return storage.fetchSleepEvents(forSession: sessionKey)
    }
}
