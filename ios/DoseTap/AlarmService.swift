import Foundation
import UserNotifications
import AVFoundation
import AudioToolbox
import DoseCore
import os.log

private let alarmLog = Logger(subsystem: "com.dosetap.app", category: "AlarmService")

// MARK: - Notification Center Boundary

/// Narrow, injectable boundary around `UNUserNotificationCenter`.
/// Alarm scheduling must be observable and fault-injectable; direct fire-and-forget
/// calls make partial writes indistinguishable from success.
@MainActor
protocol AlarmNotificationCenterClient: AnyObject {
    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?)
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func pendingRequests() async -> [UNNotificationRequest]
    func removePendingRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

@MainActor
private final class SystemAlarmNotificationCenterClient: AlarmNotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        center.delegate = delegate
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

struct AlarmConfiguration: Equatable {
    var notificationsEnabled: Bool
    var windowOpenAlert: Bool
    var fifteenMinWarning: Bool
    var fiveMinWarning: Bool
    var soundEnabled: Bool
    var criticalAlertsEnabled: Bool
    var snoozeDurationMinutes: Int
    var maxSnoozes: Int

    @MainActor
    static var current: AlarmConfiguration {
        let settings = UserSettingsManager.shared
        return AlarmConfiguration(
            notificationsEnabled: settings.notificationsEnabled,
            windowOpenAlert: settings.windowOpenAlert,
            fifteenMinWarning: settings.fifteenMinWarning,
            fiveMinWarning: settings.fiveMinWarning,
            soundEnabled: settings.soundEnabled,
            criticalAlertsEnabled: settings.criticalAlertsEnabled,
            snoozeDurationMinutes: settings.snoozeDurationMinutes,
            maxSnoozes: settings.maxSnoozes
        )
    }
}

struct PersistedAlarmSchedule: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var dose1Time: Date
    var absoluteWakeDeadline: Date
    var createdAt: Date
    var originTimeZoneIdentifier: String
    var lastReconciledTimeZoneIdentifier: String
    var snoozeCount: Int
    var wakeVerified: Bool
    var remindersVerified: Bool
    var expectedWakeRequestIDs: [String]
    var expectedReminderRequestIDs: [String]
}

/// Alarm service for scheduling and managing wake alarms
/// Handles snooze functionality with proper notification rescheduling
@MainActor
public class AlarmService: NSObject, ObservableObject {

    static let shared = AlarmService()
    private static let fallbackAlarmSystemSoundID: SystemSoundID = 1005

    // MARK: - Notification IDs
    enum NotificationID {
        static let dose2Alarm = "dosetap_dose2_alarm"
        static let dose2PreAlarm = "dosetap_dose2_pre_alarm"
        static let followUp = "dosetap_followup"
        static let secondDose = "dosetap_second_dose"         // Window open reminder
        static let windowWarning15 = "dosetap_window_15min"   // 15 min warning
        static let windowWarning5 = "dosetap_window_5min"     // 5 min warning
    }

    private enum NotificationCategory {
        static let alarm = "dosetap_alarm"
    }

    private enum NotificationAction {
        static let snooze = "dosetap_alarm_snooze"
        static let stop = "dosetap_alarm_stop"
    }

    static let wakeNotificationIdentifiers = [
        NotificationID.dose2Alarm,
        NotificationID.dose2PreAlarm,
        "\(NotificationID.followUp)_1",
        "\(NotificationID.followUp)_2",
        "\(NotificationID.followUp)_3",
    ]

    static let reminderNotificationIdentifiers = [
        NotificationID.secondDose,
        NotificationID.windowWarning15,
        NotificationID.windowWarning5,
    ]
    
    // MARK: - Published Properties
    @Published public var targetWakeTime: Date?
    @Published public var alarmScheduled: Bool = false
    @Published public var snoozeCount: Int = 0
    @Published public var reminderScheduled: Bool = false
    @Published public var isAlarmRinging: Bool = false
    @Published public private(set) var lastSchedulingError: String?
    @Published public private(set) var reconciledTimeZoneIdentifier: String?
    
    private let notificationClient: any AlarmNotificationCenterClient
    private let defaults: UserDefaults
    private let nowProvider: () -> Date
    private let timeZoneProvider: () -> TimeZone
    private let configurationProvider: () -> AlarmConfiguration
    private var audioPlayer: AVAudioPlayer?
    private var vibrationTimer: Timer?
    private var usesSystemSoundFallback: Bool = false
    private var alarmAcknowledged: Bool = false
    private let criticalAlertsCapabilityFlag = "CriticalAlertsCapabilityEnabled"
    private var notificationSnoozeHandler: (@MainActor () async -> Bool)?
    private var persistedSchedule: PersistedAlarmSchedule?
    private var scheduleGenerations: [NotificationGroup: UInt64] = [:]
    private var failuresByGroup: [NotificationGroup: AlarmSchedulingFailure] = [:]

    private static let persistedScheduleKey = "alarmService_schedule_v1"
    private static let legacyTargetWakeTimeKey = "alarmService_targetWakeTime"

    enum NotificationGroup: String, Hashable, Sendable {
        case wake
        case reminders
    }

    public struct AlarmScheduleReceipt: Equatable, Sendable {
        public let group: String
        public let scheduledIdentifiers: [String]
        public let absoluteDeadline: Date?
        public let timeZoneIdentifier: String
    }

    public struct AlarmSchedulingFailure: Error, Equatable, Sendable {
        public enum Code: String, Equatable, Sendable {
            case notificationsDisabled
            case authorizationDenied
            case authorizationRequired
            case invalidDeadline
            case addFailed
            case verificationFailed
            case cancelled
            case missingReconstructionMetadata
        }

        public let code: Code
        public let failedIdentifier: String?
        public let detail: String
        public let previousScheduleRestored: Bool

        public var userMessage: String {
            switch code {
            case .notificationsDisabled:
                return "Notifications are disabled. Enable them to schedule Dose 2 alarms."
            case .authorizationDenied:
                return "Notification permission is denied. Open iOS Settings, then retry the alarm."
            case .authorizationRequired:
                return "Notification permission must be granted before an alarm can be scheduled."
            case .invalidDeadline:
                return "The Dose 2 alarm deadline is no longer in the future. Review the session before retrying."
            case .addFailed:
                return "DoseTap could not schedule every required notification. Retry the alarm."
            case .verificationFailed:
                return "DoseTap could not verify every required notification. Retry the alarm."
            case .cancelled:
                return "Alarm scheduling was cancelled before it could be verified."
            case .missingReconstructionMetadata:
                return "DoseTap needs the active Dose 1 time before it can repair this alarm."
            }
        }
    }

    public enum AlarmScheduleResult: Equatable, Sendable {
        case scheduled(AlarmScheduleReceipt)
        case notNeeded(reason: String)
        case failed(AlarmSchedulingFailure)

        public var failure: AlarmSchedulingFailure? {
            if case .failed(let failure) = self { return failure }
            return nil
        }
    }

    public enum ReconciliationReason: String, Sendable {
        case appActive = "app_active"
        case significantTimeChange = "significant_time_change"
        case timeZoneChange = "timezone_change"
        case manualRetry = "manual_retry"
        case test = "test"
    }

    public struct AlarmReconciliationReport: Equatable, Sendable {
        public let reason: ReconciliationReason
        public let detectedMissingIdentifiers: [String]
        public let repairedIdentifiers: [String]
        public let wakeResult: AlarmScheduleResult
        public let reminderResult: AlarmScheduleResult
    }
    
    private var canUseCriticalAlerts: Bool {
        let capabilityEnabled = (Bundle.main.object(forInfoDictionaryKey: criticalAlertsCapabilityFlag) as? Bool) == true
        return configurationProvider().criticalAlertsEnabled && capabilityEnabled
    }
    
    // MARK: - Initialization
    
    public override init() {
        notificationClient = SystemAlarmNotificationCenterClient()
        defaults = .standard
        nowProvider = { Date() }
        timeZoneProvider = { .current }
        configurationProvider = { AlarmConfiguration.current }
        super.init()
        finishInitialization()
    }

    init(
        notificationClient: any AlarmNotificationCenterClient,
        defaults: UserDefaults,
        nowProvider: @escaping () -> Date,
        timeZoneProvider: @escaping () -> TimeZone,
        configurationProvider: @escaping () -> AlarmConfiguration
    ) {
        self.notificationClient = notificationClient
        self.defaults = defaults
        self.nowProvider = nowProvider
        self.timeZoneProvider = timeZoneProvider
        self.configurationProvider = configurationProvider
        super.init()
        finishInitialization()
    }

    private func finishInitialization() {
        notificationClient.setDelegate(self)
        registerNotificationCategories()
        loadTargetWakeTime()
        configureAudioSession()
    }

    private func registerNotificationCategories() {
        let snoozeMinutes = configuredSnoozeDurationMinutes
        let snooze = UNNotificationAction(
            identifier: NotificationAction.snooze,
            title: "Snooze \(snoozeMinutes) min",
            options: []
        )
        let stop = UNNotificationAction(
            identifier: NotificationAction.stop,
            title: "Open DoseTap to Log Dose 2",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: NotificationCategory.alarm,
            actions: [snooze, stop],
            intentIdentifiers: [],
            options: []
        )
        notificationClient.setNotificationCategories([category])
    }

    public var maxSnoozesAllowed: Int {
        configuredMaxSnoozes
    }

    public var snoozeDurationMinutes: Int {
        configuredSnoozeDurationMinutes
    }

    func configureNotificationSnoozeHandler(_ handler: @escaping @MainActor () async -> Bool) {
        notificationSnoozeHandler = handler
    }

    func resetNotificationSnoozeHandlerForTests() {
        notificationSnoozeHandler = nil
    }

    @discardableResult
    func handleNotificationSnoozeAction() async -> Bool {
        guard let notificationSnoozeHandler else {
            alarmLog.error("Blocked notification snooze because dose command handler is unavailable")
            return false
        }
        let didSnooze = await notificationSnoozeHandler()
        if didSnooze {
            stopRinging(acknowledge: false)
        }
        return didSnooze
    }
    
    // MARK: - Audio Session
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            alarmLog.error("Failed to configure audio session: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Permission
    
    public func requestPermission() async -> Bool {
        do {
            let options: UNAuthorizationOptions = canUseCriticalAlerts
                ? [.alert, .sound, .badge, .criticalAlert]
                : [.alert, .sound, .badge]
            let granted = try await notificationClient.requestAuthorization(options: options)
            alarmLog.info("Notification permission \(granted ? "granted" : "denied", privacy: .public)")
            return granted
        } catch {
            alarmLog.error("Permission request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    // MARK: - Schedule Dose 2 Reminders
    
    /// Schedule Dose 2 window reminders after Dose 1 is taken
    /// - Parameter dose1Time: Time Dose 1 was taken
    @discardableResult
    public func scheduleDose2Reminders(dose1Time: Date) async -> AlarmScheduleResult {
        let now = nowProvider()
        let timeZone = timeZoneProvider()
        let requests = makeReminderRequests(
            dose1Time: dose1Time,
            now: now,
            timeZone: timeZone
        )
        let prior = persistedSchedule
        ensureReconstructionMetadata(dose1Time: dose1Time, now: now, timeZone: timeZone)

        let result = await performScheduleTransaction(
            group: .reminders,
            requests: requests,
            absoluteDeadline: nil
        )

        switch result {
        case .scheduled(let receipt):
            reminderScheduled = true
            persistedSchedule?.remindersVerified = true
            persistedSchedule?.expectedReminderRequestIDs = receipt.scheduledIdentifiers
            persistedSchedule?.lastReconciledTimeZoneIdentifier = timeZone.identifier
            reconciledTimeZoneIdentifier = timeZone.identifier
            savePersistedSchedule()
        case .notNeeded:
            reminderScheduled = false
            // An empty desired set is verified only while scheduling is
            // enabled. Disabled notifications retain unverified intent so an
            // explicit retry can rebuild the group later.
            persistedSchedule?.remindersVerified = configurationProvider().notificationsEnabled
            persistedSchedule?.expectedReminderRequestIDs = []
            savePersistedSchedule()
        case .failed(let failure):
            if failure.previousScheduleRestored, let prior {
                persistedSchedule = prior
                reminderScheduled = prior.remindersVerified
            } else {
                reminderScheduled = false
                persistedSchedule?.remindersVerified = false
                persistedSchedule?.expectedReminderRequestIDs = []
                savePersistedSchedule()
            }
        }

        record(result: result, for: .reminders)
        return result
    }
    
    /// Cancel Dose 2 reminders and retain the actual cancellation cause in the
    /// privacy-safe diagnostic trail.
    public func cancelDose2Reminders(sessionId: String, reason: String = "dose2_completed_or_skipped") {
        invalidateScheduling(for: .reminders)
        let ids = Self.reminderNotificationIdentifiers
        notificationClient.removePendingRequests(withIdentifiers: ids)
        notificationClient.removeDeliveredNotifications(withIdentifiers: ids)
        reminderScheduled = false
        persistedSchedule?.remindersVerified = false
        persistedSchedule?.expectedReminderRequestIDs = []
        savePersistedSchedule()
        alarmLog.info("Dose 2 reminders cancelled")
        
        // Diagnostic logging: alarms cancelled
        for id in ids {
            Task {
                await DiagnosticLogger.shared.logAlarm(
                    .alarmCancelled,
                    sessionId: sessionId,
                    alarmId: id,
                    reason: reason
                )
            }
        }
    }
    
    // MARK: - Schedule Wake Alarm
    
    /// Schedule wake alarm for Dose 2
    /// - Parameters:
    ///   - time: Target wake time
    ///   - dose1Time: Time of Dose 1 (for window calculations)
    @discardableResult
    public func scheduleDose2Alarm(at time: Date, dose1Time: Date) async -> AlarmScheduleResult {
        // Keep action titles in sync with current user snooze settings.
        registerNotificationCategories()
        let now = nowProvider()
        let timeZone = timeZoneProvider()

        // Validate wake time is in the future
        guard time > now else {
            alarmLog.warning("Cannot schedule alarm in the past")
            let failure = AlarmSchedulingFailure(
                code: .invalidDeadline,
                failedIdentifier: NotificationID.dose2Alarm,
                detail: "Wake deadline is not in the future",
                previousScheduleRestored: false
            )
            let result = AlarmScheduleResult.failed(failure)
            record(result: result, for: .wake)
            return result
        }

        let prior = persistedSchedule
        let candidate = makeScheduleMetadata(
            dose1Time: dose1Time,
            targetWakeTime: time,
            prior: prior,
            now: now,
            timeZone: timeZone
        )

        // Persist an unverified candidate for first-time scheduling so a failed
        // add can be retried without asking the user to log Dose 1 again. During
        // snooze/reschedule, retain a previously verified schedule until replacement succeeds.
        if prior?.wakeVerified != true {
            persistedSchedule = candidate
            targetWakeTime = time
            alarmScheduled = false
            savePersistedSchedule()
        }

        let requests = makeWakeRequests(
            targetWakeTime: time,
            dose1Time: dose1Time,
            now: now,
            timeZone: timeZone
        )
        let result = await performScheduleTransaction(
            group: .wake,
            requests: requests,
            absoluteDeadline: time
        )

        switch result {
        case .scheduled(let receipt):
            var committed = candidate
            committed.wakeVerified = true
            committed.expectedWakeRequestIDs = receipt.scheduledIdentifiers
            committed.lastReconciledTimeZoneIdentifier = timeZone.identifier
            persistedSchedule = committed
            targetWakeTime = time
            alarmScheduled = true
            alarmAcknowledged = false
            reconciledTimeZoneIdentifier = timeZone.identifier
            savePersistedSchedule()
            alarmLog.info("Dose 2 alarm scheduled for \(self.formatTime(time), privacy: .private)")
        case .notNeeded:
            persistedSchedule = candidate
            persistedSchedule?.wakeVerified = false
            persistedSchedule?.expectedWakeRequestIDs = []
            targetWakeTime = time
            alarmScheduled = false
            savePersistedSchedule()
        case .failed(let failure):
            if failure.previousScheduleRestored, let prior {
                persistedSchedule = prior
                targetWakeTime = prior.absoluteWakeDeadline
                alarmScheduled = prior.wakeVerified
                snoozeCount = prior.snoozeCount
            } else {
                persistedSchedule = candidate
                persistedSchedule?.wakeVerified = false
                persistedSchedule?.expectedWakeRequestIDs = []
                targetWakeTime = time
                alarmScheduled = false
                savePersistedSchedule()
            }
        }

        record(result: result, for: .wake)
        return result
    }
    
    // MARK: - Snooze
    
    /// Snooze the alarm by adding 10 minutes to current target time
    /// - Parameter dose1Time: Original Dose 1 time for window recalculation
    /// - Returns: New target time, or nil if snooze not allowed
    public func snoozeAlarm(dose1Time: Date?) async -> Date? {
        let maxSnoozes = configuredMaxSnoozes
        guard maxSnoozes > 0 else {
            alarmLog.warning("Snooze disabled; max snoozes is 0")
            return nil
        }
        guard snoozeCount < maxSnoozes else {
            alarmLog.warning("Max snoozes reached: \(maxSnoozes, privacy: .public)")
            return nil
        }
        guard let currentTarget = targetWakeTime, let d1 = dose1Time else {
            alarmLog.warning("No alarm to snooze")
            return nil
        }
        guard configurationProvider().notificationsEnabled else {
            alarmLog.warning("Snooze unavailable while notifications are disabled")
            return nil
        }

        let decisionTime = nowProvider()
        let context = DoseWindowCalculator(now: { decisionTime }).context(
            dose1At: d1,
            dose2TakenAt: nil,
            dose2Skipped: false,
            snoozeCount: snoozeCount
        )
        let policyInput = DoseRegistrationInput(
            dose1Time: d1,
            dose2Time: nil,
            dose2Skipped: false,
            snoozeCount: snoozeCount,
            windowPhase: context.phase,
            surface: .notificationAction
        )
        guard case .allowed = DoseRegistrationPolicy.evaluateSnooze(
            input: policyInput,
            at: decisionTime,
            config: DoseCore.DoseWindowConfig(maxSnoozes: maxSnoozes)
        ) else {
            alarmLog.warning("Snooze blocked by canonical dose-window policy")
            return nil
        }
        
        // Check if snooze is allowed (not within 15 min of window close)
        let snoozeMinutes = configuredSnoozeDurationMinutes
        let windowClose = d1.addingTimeInterval(240 * 60)
        let newTarget = currentTarget.addingTimeInterval(TimeInterval(snoozeMinutes * 60))
        let nearCloseThreshold = windowClose.addingTimeInterval(-15 * 60)
        
        if newTarget > nearCloseThreshold {
            alarmLog.warning("Snooze would exceed near-close threshold")
            return nil
        }
        
        // Schedule new alarm at snoozed time
        let result = await scheduleDose2Alarm(at: newTarget, dose1Time: d1)
        guard case .scheduled = result,
              targetWakeTime == newTarget,
              alarmScheduled else {
            alarmLog.error("Snooze reschedule failed")
            return nil
        }
        snoozeCount += 1
        persistedSchedule?.snoozeCount = snoozeCount
        savePersistedSchedule()
        pruneExpiredReminderRequests(dose1Time: d1, now: decisionTime)
        
        alarmLog.info("Alarm snoozed +\(snoozeMinutes, privacy: .public)m to \(self.formatTime(newTarget), privacy: .private) (snooze \(self.snoozeCount, privacy: .public)/\(maxSnoozes, privacy: .public))")
        
        return newTarget
    }

    @discardableResult
    public func undoSnooze(minutes: Int, dose1Time: Date?) async -> Bool {
        guard minutes > 0 else {
            alarmLog.warning("Cannot undo snooze with non-positive minutes")
            return false
        }
        guard let currentTarget = targetWakeTime, let d1 = dose1Time else {
            alarmLog.warning("Cannot undo snooze without active target and Dose 1 time")
            return false
        }

        let restoredTarget = currentTarget.addingTimeInterval(-TimeInterval(minutes * 60))
        let result = await scheduleDose2Alarm(at: restoredTarget, dose1Time: d1)
        guard case .scheduled = result,
              targetWakeTime == restoredTarget,
              alarmScheduled else {
            alarmLog.error("Undo snooze reschedule failed")
            return false
        }
        if snoozeCount > 0 {
            snoozeCount -= 1
        }
        persistedSchedule?.snoozeCount = snoozeCount
        savePersistedSchedule()
        alarmLog.info("Snooze undo restored alarm target")
        return true
    }

    // MARK: - Ringing Control

    public func checkForDueAlarm(now: Date = Date()) {
        guard let target = targetWakeTime else { return }
        if SessionRepository.shared.dose2Time != nil || SessionRepository.shared.dose2Skipped {
            clearDose2AlarmState()
            cancelAllAlarms()
            return
        }
        guard alarmScheduled else { return }
        guard !alarmAcknowledged else {
            // Defensive cleanup in case a stale target survives an acknowledged alarm.
            clearDose2AlarmState()
            return
        }
        if target <= now {
            startRinging()
        }
    }

    public func startRinging() {
        guard !isAlarmRinging else { return }
        isAlarmRinging = true
        playAlarmSound()
        startVibrationLoop()
    }

    public func stopRinging(acknowledge: Bool = true) {
        isAlarmRinging = false
        alarmAcknowledged = acknowledge
        stopAlarmSound()
        stopVibrationLoop()
        usesSystemSoundFallback = false
        if acknowledge {
            targetWakeTime = nil
            clearSavedTargetWakeTime()
        }
    }

    public func acknowledgeAlarm() {
        clearDose2AlarmState()
        cancelAllAlarms()
    }
    
    // MARK: - Cancel
    
    /// Cancel all scheduled alarms
    public func cancelAllAlarms() {
        invalidateScheduling(for: .wake)
        invalidateScheduling(for: .reminders)
        let ids = Self.wakeNotificationIdentifiers + Self.reminderNotificationIdentifiers
        notificationClient.removePendingRequests(withIdentifiers: ids)
        notificationClient.removeDeliveredNotifications(withIdentifiers: ids)
        
        alarmScheduled = false
        reminderScheduled = false
        persistedSchedule?.wakeVerified = false
        persistedSchedule?.remindersVerified = false
        persistedSchedule?.expectedWakeRequestIDs = []
        persistedSchedule?.expectedReminderRequestIDs = []
        savePersistedSchedule()
        alarmLog.info("All alarms cancelled")
    }

    /// Cancel only wake-alarm roles. Dose-window safety reminders are deliberately
    /// excluded so snooze and wake-target edits cannot erase them.
    public func cancelWakeAlarms() {
        invalidateScheduling(for: .wake)
        notificationClient.removePendingRequests(withIdentifiers: Self.wakeNotificationIdentifiers)
        notificationClient.removeDeliveredNotifications(withIdentifiers: Self.wakeNotificationIdentifiers)
        alarmScheduled = false
        persistedSchedule?.wakeVerified = false
        persistedSchedule?.expectedWakeRequestIDs = []
        savePersistedSchedule()
    }

    /// Clear in-memory and persisted wake-alarm target state.
    public func clearDose2AlarmState() {
        stopRinging(acknowledge: true)
        targetWakeTime = nil
        clearSavedTargetWakeTime()
        snoozeCount = 0
        alarmScheduled = false
        reminderScheduled = false
        failuresByGroup.removeAll()
        lastSchedulingError = nil
        reconciledTimeZoneIdentifier = nil
    }
    
    /// Reset for new session
    public func resetForNewSession(closingSessionId: String) {
        cancelAllAlarms()
        cancelDose2Reminders(sessionId: closingSessionId, reason: "new_session_reset")
        clearDose2AlarmState()
        reminderScheduled = false
    }
    
    // MARK: - Private Helpers
    
    static func absoluteDateComponents(
        for date: Date,
        in timeZone: TimeZone
    ) -> DateComponents {
        // A named civil timezone is ambiguous during the repeated hour at the
        // end of daylight-saving time. Freeze the zone's offset *at this
        // absolute instant* so UNCalendarNotificationTrigger cannot choose the
        // other occurrence of the same wall-clock components. The named zone
        // remains in notification userInfo and persisted reconciliation data.
        let triggerTimeZone = TimeZone(
            secondsFromGMT: timeZone.secondsFromGMT(for: date)
        ) ?? TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = triggerTimeZone
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.calendar = calendar
        components.timeZone = triggerTimeZone
        return components
    }

    private func makeNotificationRequest(
        id: String,
        title: String,
        body: String,
        at date: Date,
        timeZone: TimeZone,
        group: NotificationGroup,
        sound: UNNotificationSound?,
        isCritical: Bool = false,
        category: String? = nil
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.interruptionLevel = isCritical ? .critical : .timeSensitive
        content.userInfo = [
            "dosetap_absolute_deadline": date.timeIntervalSince1970,
            "dosetap_schedule_timezone": timeZone.identifier,
            "dosetap_notification_group": group.rawValue,
        ]
        if let category {
            content.categoryIdentifier = category
        }

        let components = Self.absoluteDateComponents(for: date, in: timeZone)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private func makeWakeRequests(
        targetWakeTime: Date,
        dose1Time: Date,
        now: Date,
        timeZone: TimeZone
    ) -> [UNNotificationRequest] {
        let windowClose = dose1Time.addingTimeInterval(240 * 60)
        let minutesRemaining = Int(windowClose.timeIntervalSince(targetWakeTime) / 60)
        var requests: [UNNotificationRequest] = []

        requests.append(makeNotificationRequest(
            id: NotificationID.dose2Alarm,
            title: "🔔 WAKE UP - Time for Dose 2",
            body: "Take your second dose now! \(TimeIntervalMath.formatMinutes(minutesRemaining)) remaining in window.",
            at: targetWakeTime,
            timeZone: timeZone,
            group: .wake,
            sound: alarmNotificationSound(),
            isCritical: canUseCriticalAlerts,
            category: NotificationCategory.alarm
        ))

        let preAlarmTime = targetWakeTime.addingTimeInterval(-5 * 60)
        if preAlarmTime > now {
            requests.append(makeNotificationRequest(
                id: NotificationID.dose2PreAlarm,
                title: "⏰ Dose 2 Alarm in 5 Minutes",
                body: "Your Dose 2 alarm will sound soon",
                at: preAlarmTime,
                timeZone: timeZone,
                group: .wake,
                sound: .default,
                category: NotificationCategory.alarm
            ))
        }

        for index in 1...3 {
            let followUpTime = targetWakeTime.addingTimeInterval(TimeInterval(index * 2 * 60))
            if followUpTime > now, followUpTime < windowClose {
                requests.append(makeNotificationRequest(
                    id: "\(NotificationID.followUp)_\(index)",
                    title: "🔔 REMINDER \(index) - Dose 2 Still Waiting",
                    body: "\(TimeIntervalMath.formatMinutes(max(0, minutesRemaining - (index * 2)))) left in window!",
                    at: followUpTime,
                    timeZone: timeZone,
                    group: .wake,
                    sound: alarmNotificationSound(),
                    isCritical: canUseCriticalAlerts,
                    category: NotificationCategory.alarm
                ))
            }
        }

        return requests
    }

    private func makeReminderRequests(
        dose1Time: Date,
        now: Date,
        timeZone: TimeZone
    ) -> [UNNotificationRequest] {
        let configuration = configurationProvider()
        let windowOpen = dose1Time.addingTimeInterval(150 * 60)
        let windowClose = dose1Time.addingTimeInterval(240 * 60)
        let warning15 = windowClose.addingTimeInterval(-15 * 60)
        let warning5 = windowClose.addingTimeInterval(-5 * 60)
        var requests: [UNNotificationRequest] = []

        if configuration.windowOpenAlert, windowOpen > now {
            requests.append(makeNotificationRequest(
                id: NotificationID.secondDose,
                title: "💊 Dose Window Now Open",
                body: "Your Dose 2 window has opened (150 min). Take Dose 2 when ready.",
                at: windowOpen,
                timeZone: timeZone,
                group: .reminders,
                sound: .default
            ))
        }
        if configuration.fifteenMinWarning, warning15 > now {
            requests.append(makeNotificationRequest(
                id: NotificationID.windowWarning15,
                title: "⚠️ 15 Minutes Remaining",
                body: "Only \(TimeIntervalMath.formatMinutes(15)) left in your dose window!",
                at: warning15,
                timeZone: timeZone,
                group: .reminders,
                sound: .default
            ))
        }
        if configuration.fiveMinWarning, warning5 > now {
            requests.append(makeNotificationRequest(
                id: NotificationID.windowWarning5,
                title: "🚨 5 Minutes Remaining!",
                body: "Final warning - take Dose 2 NOW or skip!",
                at: warning5,
                timeZone: timeZone,
                group: .reminders,
                sound: notificationSound(isCritical: true),
                isCritical: canUseCriticalAlerts
            ))
        }

        return requests
    }

    private func performScheduleTransaction(
        group: NotificationGroup,
        requests: [UNNotificationRequest],
        absoluteDeadline: Date?
    ) async -> AlarmScheduleResult {
        let allGroupIdentifiers = identifiers(for: group)
        guard configurationProvider().notificationsEnabled else {
            invalidateScheduling(for: group)
            notificationClient.removePendingRequests(withIdentifiers: allGroupIdentifiers)
            return .notNeeded(reason: "Notifications disabled")
        }

        let authorization = await notificationClient.authorizationStatus()
        switch authorization {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            invalidateScheduling(for: group)
            notificationClient.removePendingRequests(withIdentifiers: allGroupIdentifiers)
            return .failed(AlarmSchedulingFailure(
                code: .authorizationDenied,
                failedIdentifier: nil,
                detail: "Notification authorization is denied",
                previousScheduleRestored: false
            ))
        case .notDetermined:
            invalidateScheduling(for: group)
            notificationClient.removePendingRequests(withIdentifiers: allGroupIdentifiers)
            return .failed(AlarmSchedulingFailure(
                code: .authorizationRequired,
                failedIdentifier: nil,
                detail: "Notification authorization is not determined",
                previousScheduleRestored: false
            ))
        @unknown default:
            invalidateScheduling(for: group)
            notificationClient.removePendingRequests(withIdentifiers: allGroupIdentifiers)
            return .failed(AlarmSchedulingFailure(
                code: .authorizationDenied,
                failedIdentifier: nil,
                detail: "Notification authorization status is unsupported",
                previousScheduleRestored: false
            ))
        }

        let generation = beginScheduling(for: group)
        let priorRequests = await notificationClient.pendingRequests()
            .filter { allGroupIdentifiers.contains($0.identifier) }
        guard isCurrent(generation, for: group) else {
            notificationClient.removePendingRequests(withIdentifiers: allGroupIdentifiers)
            return .failed(cancelledFailure())
        }

        guard !requests.isEmpty else {
            notificationClient.removePendingRequests(withIdentifiers: allGroupIdentifiers)
            return .notNeeded(reason: "No enabled future notifications")
        }

        let desiredIdentifiers = Set(requests.map(\.identifier))
        for request in requests {
            do {
                try await notificationClient.add(request)
            } catch {
                guard isCurrent(generation, for: group) else {
                    notificationClient.removePendingRequests(withIdentifiers: allGroupIdentifiers)
                    return .failed(cancelledFailure())
                }
                let restored = await rollback(group: group, to: priorRequests)
                await logSchedulingError(
                    identifier: request.identifier,
                    detail: error.localizedDescription
                )
                return .failed(AlarmSchedulingFailure(
                    code: .addFailed,
                    failedIdentifier: request.identifier,
                    detail: error.localizedDescription,
                    previousScheduleRestored: restored && !priorRequests.isEmpty
                ))
            }

            guard isCurrent(generation, for: group) else {
                notificationClient.removePendingRequests(withIdentifiers: allGroupIdentifiers)
                return .failed(cancelledFailure())
            }
        }

        let staleIdentifiers = allGroupIdentifiers.filter { !desiredIdentifiers.contains($0) }
        if !staleIdentifiers.isEmpty {
            notificationClient.removePendingRequests(withIdentifiers: staleIdentifiers)
        }

        let pending = await notificationClient.pendingRequests()
        guard isCurrent(generation, for: group) else {
            notificationClient.removePendingRequests(withIdentifiers: allGroupIdentifiers)
            return .failed(cancelledFailure())
        }

        let actualByIdentifier = Dictionary(
            uniqueKeysWithValues: pending
                .filter { allGroupIdentifiers.contains($0.identifier) }
                .map { ($0.identifier, $0) }
        )
        let missing = desiredIdentifiers.filter { actualByIdentifier[$0] == nil }.sorted()
        let unexpected = Set(actualByIdentifier.keys).subtracting(desiredIdentifiers).sorted()
        let mismatched = requests.compactMap { desired -> String? in
            guard let actual = actualByIdentifier[desired.identifier] else { return nil }
            return requestsMatch(actual, desired) ? nil : desired.identifier
        }.sorted()

        guard missing.isEmpty, unexpected.isEmpty, mismatched.isEmpty else {
            let restored = await rollback(group: group, to: priorRequests)
            let detail = "missing=\(missing.joined(separator: ",")); unexpected=\(unexpected.joined(separator: ",")); mismatched=\(mismatched.joined(separator: ","))"
            await logSchedulingError(identifier: nil, detail: detail)
            return .failed(AlarmSchedulingFailure(
                code: .verificationFailed,
                failedIdentifier: missing.first ?? mismatched.first ?? unexpected.first,
                detail: detail,
                previousScheduleRestored: restored && !priorRequests.isEmpty
            ))
        }

        let receipt = AlarmScheduleReceipt(
            group: group.rawValue,
            scheduledIdentifiers: desiredIdentifiers.sorted(),
            absoluteDeadline: absoluteDeadline,
            timeZoneIdentifier: timeZoneProvider().identifier
        )
        await logVerifiedSchedule(requests)
        return .scheduled(receipt)
    }

    private func rollback(
        group: NotificationGroup,
        to priorRequests: [UNNotificationRequest]
    ) async -> Bool {
        let allIdentifiers = identifiers(for: group)
        notificationClient.removePendingRequests(withIdentifiers: allIdentifiers)
        do {
            for request in priorRequests {
                try await notificationClient.add(request)
            }
        } catch {
            alarmLog.error("Notification rollback failed: \(error.localizedDescription, privacy: .public)")
            notificationClient.removePendingRequests(withIdentifiers: allIdentifiers)
            return false
        }
        let restored = await notificationClient.pendingRequests()
            .filter { allIdentifiers.contains($0.identifier) }
        let restoredByIdentifier = Dictionary(
            uniqueKeysWithValues: restored.map { ($0.identifier, $0) }
        )
        let didRestore = Set(restoredByIdentifier.keys)
            == Set(priorRequests.map(\.identifier))
            && priorRequests.allSatisfy { prior in
                guard let actual = restoredByIdentifier[prior.identifier] else {
                    return false
                }
                return requestsMatch(actual, prior)
            }
        if !didRestore {
            notificationClient.removePendingRequests(withIdentifiers: allIdentifiers)
        }
        return didRestore
    }

    private func requestsMatch(
        _ actual: UNNotificationRequest,
        _ desired: UNNotificationRequest
    ) -> Bool {
        guard
            let actualTrigger = actual.trigger as? UNCalendarNotificationTrigger,
            let desiredTrigger = desired.trigger as? UNCalendarNotificationTrigger,
            let actualDate = actualTrigger.nextTriggerDate(),
            let desiredDate = desiredTrigger.nextTriggerDate()
        else {
            return false
        }
        return abs(actualDate.timeIntervalSince(desiredDate)) < 1
            && actualTrigger.dateComponents.timeZone?.identifier
                == desiredTrigger.dateComponents.timeZone?.identifier
            && (actual.content.userInfo["dosetap_schedule_timezone"] as? String)
                == (desired.content.userInfo["dosetap_schedule_timezone"] as? String)
    }

    private func identifiers(for group: NotificationGroup) -> [String] {
        switch group {
        case .wake: return Self.wakeNotificationIdentifiers
        case .reminders: return Self.reminderNotificationIdentifiers
        }
    }

    private func beginScheduling(for group: NotificationGroup) -> UInt64 {
        let next = (scheduleGenerations[group] ?? 0) &+ 1
        scheduleGenerations[group] = next
        return next
    }

    private func invalidateScheduling(for group: NotificationGroup) {
        _ = beginScheduling(for: group)
    }

    private func isCurrent(_ generation: UInt64, for group: NotificationGroup) -> Bool {
        scheduleGenerations[group] == generation
    }

    private func cancelledFailure() -> AlarmSchedulingFailure {
        AlarmSchedulingFailure(
            code: .cancelled,
            failedIdentifier: nil,
            detail: "Scheduling generation was invalidated",
            previousScheduleRestored: false
        )
    }

    private func record(result: AlarmScheduleResult, for group: NotificationGroup) {
        switch result {
        case .scheduled, .notNeeded:
            failuresByGroup.removeValue(forKey: group)
        case .failed(let failure):
            failuresByGroup[group] = failure
        }
        lastSchedulingError = failuresByGroup
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { $0.value.userMessage }
            .joined(separator: " ")
            .nilIfEmpty
    }

    private func logVerifiedSchedule(_ requests: [UNNotificationRequest]) async {
        let sessionId = SessionRepository.shared.currentSessionIdString()
        for request in requests {
            let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            alarmLog.info("Verified notification \(request.identifier, privacy: .public)")
            await DiagnosticLogger.shared.logAlarm(
                .alarmScheduled,
                sessionId: sessionId,
                alarmId: request.identifier,
                scheduledFor: date
            )
        }
    }

    private func logSchedulingError(identifier: String?, detail: String) async {
        alarmLog.error("Failed to schedule notification \(identifier ?? "unknown", privacy: .public): \(detail, privacy: .public)")
        let sessionId = SessionRepository.shared.currentSessionIdString()
        await DiagnosticLogger.shared.logError(
            .errorNotification,
            sessionId: sessionId,
            reason: "Failed to schedule \(identifier ?? "unknown"): \(detail)"
        )
    }

    // MARK: Reconciliation and Retry

    /// Reconcile persisted intent with pending notification requests. Medication
    /// deadlines are absolute `Date` values; timezone changes only alter the
    /// calendar representation used by `UNCalendarNotificationTrigger`.
    @discardableResult
    public func reconcilePendingRequests(
        reason: ReconciliationReason,
        dose1Time fallbackDose1Time: Date? = nil,
        forceReschedule: Bool = false
    ) async -> AlarmReconciliationReport {
        let now = nowProvider()
        let timeZone = timeZoneProvider()

        if persistedSchedule == nil,
           let fallbackDose1Time,
           let targetWakeTime {
            persistedSchedule = makeScheduleMetadata(
                dose1Time: fallbackDose1Time,
                targetWakeTime: targetWakeTime,
                prior: nil,
                now: now,
                timeZone: timeZone
            )
            savePersistedSchedule()
        }

        guard let metadata = persistedSchedule else {
            if targetWakeTime == nil {
                let result = AlarmScheduleResult.notNeeded(
                    reason: "No persisted alarm schedule"
                )
                record(result: result, for: .wake)
                record(result: result, for: .reminders)
                return AlarmReconciliationReport(
                    reason: reason,
                    detectedMissingIdentifiers: [],
                    repairedIdentifiers: [],
                    wakeResult: result,
                    reminderResult: result
                )
            }
            let failure = AlarmSchedulingFailure(
                code: .missingReconstructionMetadata,
                failedIdentifier: nil,
                detail: "No persisted Dose 1 and absolute wake deadline",
                previousScheduleRestored: false
            )
            let result = AlarmScheduleResult.failed(failure)
            record(result: result, for: .wake)
            record(result: result, for: .reminders)
            return AlarmReconciliationReport(
                reason: reason,
                detectedMissingIdentifiers: [],
                repairedIdentifiers: [],
                wakeResult: result,
                reminderResult: result
            )
        }

        targetWakeTime = metadata.absoluteWakeDeadline
        snoozeCount = metadata.snoozeCount

        let wakeRequests = metadata.absoluteWakeDeadline > now
            ? makeWakeRequests(
                targetWakeTime: metadata.absoluteWakeDeadline,
                dose1Time: metadata.dose1Time,
                now: now,
                timeZone: timeZone
            )
            : []
        let reminderRequests = makeReminderRequests(
            dose1Time: metadata.dose1Time,
            now: now,
            timeZone: timeZone
        )
        let pending = await notificationClient.pendingRequests()
        let wakeIssues = reconciliationIssues(
            desired: wakeRequests,
            pending: pending,
            group: .wake
        )
        let reminderIssues = reconciliationIssues(
            desired: reminderRequests,
            pending: pending,
            group: .reminders
        )
        let detected = (wakeIssues + reminderIssues).sorted()
        let force = forceReschedule
            || reason == .timeZoneChange
            || reason == .significantTimeChange

        let wakeResult: AlarmScheduleResult
        let wakeNeedsRepair = force || !wakeIssues.isEmpty || !metadata.wakeVerified
        if wakeRequests.isEmpty {
            invalidateScheduling(for: .wake)
            notificationClient.removePendingRequests(withIdentifiers: Self.wakeNotificationIdentifiers)
            alarmScheduled = false
            persistedSchedule?.wakeVerified = false
            persistedSchedule?.expectedWakeRequestIDs = []
            wakeResult = .notNeeded(reason: "Absolute wake deadline has passed")
            record(result: wakeResult, for: .wake)
        } else if wakeNeedsRepair {
            wakeResult = await scheduleDose2Alarm(
                at: metadata.absoluteWakeDeadline,
                dose1Time: metadata.dose1Time
            )
        } else {
            let identifiers = wakeRequests.map(\.identifier).sorted()
            wakeResult = .scheduled(AlarmScheduleReceipt(
                group: NotificationGroup.wake.rawValue,
                scheduledIdentifiers: identifiers,
                absoluteDeadline: metadata.absoluteWakeDeadline,
                timeZoneIdentifier: timeZone.identifier
            ))
            alarmScheduled = true
            record(result: wakeResult, for: .wake)
        }

        let reminderResult: AlarmScheduleResult
        let reminderNeedsRepair = force
            || !reminderIssues.isEmpty
            || !metadata.remindersVerified
        if reminderNeedsRepair {
            reminderResult = await scheduleDose2Reminders(dose1Time: metadata.dose1Time)
        } else if reminderRequests.isEmpty {
            reminderResult = .notNeeded(reason: "No enabled future reminders")
            reminderScheduled = false
            record(result: reminderResult, for: .reminders)
        } else {
            let identifiers = reminderRequests.map(\.identifier).sorted()
            reminderResult = .scheduled(AlarmScheduleReceipt(
                group: NotificationGroup.reminders.rawValue,
                scheduledIdentifiers: identifiers,
                absoluteDeadline: nil,
                timeZoneIdentifier: timeZone.identifier
            ))
            reminderScheduled = true
            record(result: reminderResult, for: .reminders)
        }

        persistedSchedule?.lastReconciledTimeZoneIdentifier = timeZone.identifier
        reconciledTimeZoneIdentifier = timeZone.identifier
        savePersistedSchedule()

        let repaired = [wakeResult, reminderResult].flatMap { result -> [String] in
            guard case .scheduled(let receipt) = result else { return [] }
            if receipt.group == NotificationGroup.wake.rawValue, wakeNeedsRepair {
                return receipt.scheduledIdentifiers
            }
            if receipt.group == NotificationGroup.reminders.rawValue, reminderNeedsRepair {
                return receipt.scheduledIdentifiers
            }
            return []
        }.sorted()

        alarmLog.info("Alarm reconciliation \(reason.rawValue, privacy: .public): detected=\(detected.count, privacy: .public), repaired=\(repaired.count, privacy: .public)")
        return AlarmReconciliationReport(
            reason: reason,
            detectedMissingIdentifiers: detected,
            repairedIdentifiers: repaired,
            wakeResult: wakeResult,
            reminderResult: reminderResult
        )
    }

    @discardableResult
    public func retryLastSchedule(
        dose1Time: Date? = nil
    ) async -> AlarmReconciliationReport {
        await reconcilePendingRequests(
            reason: .manualRetry,
            dose1Time: dose1Time,
            forceReschedule: true
        )
    }

    private func reconciliationIssues(
        desired: [UNNotificationRequest],
        pending: [UNNotificationRequest],
        group: NotificationGroup
    ) -> [String] {
        let groupIdentifiers = Set(identifiers(for: group))
        let desiredByIdentifier = Dictionary(
            uniqueKeysWithValues: desired.map { ($0.identifier, $0) }
        )
        let pendingByIdentifier = Dictionary(
            uniqueKeysWithValues: pending
                .filter { groupIdentifiers.contains($0.identifier) }
                .map { ($0.identifier, $0) }
        )
        var issues = Set<String>()

        for (identifier, desiredRequest) in desiredByIdentifier {
            guard let actual = pendingByIdentifier[identifier] else {
                issues.insert(identifier)
                continue
            }
            if !requestsMatch(actual, desiredRequest) {
                issues.insert(identifier)
            }
        }
        for identifier in pendingByIdentifier.keys where desiredByIdentifier[identifier] == nil {
            issues.insert(identifier)
        }
        return issues.sorted()
    }

    private func pruneExpiredReminderRequests(dose1Time: Date, now: Date) {
        let desired = Set(makeReminderRequests(
            dose1Time: dose1Time,
            now: now,
            timeZone: timeZoneProvider()
        ).map(\.identifier))
        let stale = Self.reminderNotificationIdentifiers.filter { !desired.contains($0) }
        guard !stale.isEmpty else { return }
        notificationClient.removePendingRequests(withIdentifiers: stale)
        notificationClient.removeDeliveredNotifications(withIdentifiers: stale)
        persistedSchedule?.expectedReminderRequestIDs.removeAll { !desired.contains($0) }
        savePersistedSchedule()
    }

    // MARK: Persisted reconstruction metadata

    private func makeScheduleMetadata(
        dose1Time: Date,
        targetWakeTime: Date,
        prior: PersistedAlarmSchedule?,
        now: Date,
        timeZone: TimeZone
    ) -> PersistedAlarmSchedule {
        PersistedAlarmSchedule(
            schemaVersion: PersistedAlarmSchedule.currentSchemaVersion,
            dose1Time: dose1Time,
            absoluteWakeDeadline: targetWakeTime,
            createdAt: prior?.createdAt ?? now,
            originTimeZoneIdentifier: prior?.originTimeZoneIdentifier ?? timeZone.identifier,
            lastReconciledTimeZoneIdentifier: timeZone.identifier,
            snoozeCount: prior?.snoozeCount ?? snoozeCount,
            wakeVerified: false,
            remindersVerified: prior?.remindersVerified ?? false,
            expectedWakeRequestIDs: [],
            expectedReminderRequestIDs: prior?.expectedReminderRequestIDs ?? []
        )
    }

    private func ensureReconstructionMetadata(
        dose1Time: Date,
        now: Date,
        timeZone: TimeZone
    ) {
        guard persistedSchedule == nil else { return }
        let defaultTarget = targetWakeTime
            ?? dose1Time.addingTimeInterval(
                TimeInterval(DoseCore.DoseWindowConfig().defaultTargetMin * 60)
            )
        persistedSchedule = makeScheduleMetadata(
            dose1Time: dose1Time,
            targetWakeTime: defaultTarget,
            prior: nil,
            now: now,
            timeZone: timeZone
        )
        targetWakeTime = defaultTarget
        savePersistedSchedule()
    }

    private func savePersistedSchedule() {
        guard let persistedSchedule else {
            defaults.removeObject(forKey: Self.persistedScheduleKey)
            defaults.removeObject(forKey: Self.legacyTargetWakeTimeKey)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        do {
            let data = try encoder.encode(persistedSchedule)
            defaults.set(data, forKey: Self.persistedScheduleKey)
            defaults.removeObject(forKey: Self.legacyTargetWakeTimeKey)
        } catch {
            alarmLog.error("Failed to persist alarm reconstruction metadata: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearSavedTargetWakeTime() {
        persistedSchedule = nil
        defaults.removeObject(forKey: Self.persistedScheduleKey)
        defaults.removeObject(forKey: Self.legacyTargetWakeTimeKey)
    }

    private func loadTargetWakeTime() {
        if let data = defaults.data(forKey: Self.persistedScheduleKey) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            if let metadata = try? decoder.decode(PersistedAlarmSchedule.self, from: data),
               metadata.schemaVersion == PersistedAlarmSchedule.currentSchemaVersion {
                persistedSchedule = metadata
                targetWakeTime = metadata.absoluteWakeDeadline
                snoozeCount = metadata.snoozeCount
                // Persisted flags are intent/provenance only. Pending requests are
                // re-verified asynchronously before the UI claims success.
                alarmScheduled = false
                reminderScheduled = false
                reconciledTimeZoneIdentifier = metadata.lastReconciledTimeZoneIdentifier
                lastSchedulingError = "Alarm status needs verification after restart."
                return
            }
        }

        if let timestamp = defaults.object(forKey: Self.legacyTargetWakeTimeKey) as? TimeInterval {
            let savedTime = Date(timeIntervalSince1970: timestamp)
            if savedTime > nowProvider() {
                targetWakeTime = savedTime
                alarmScheduled = false
                lastSchedulingError = AlarmSchedulingFailure(
                    code: .missingReconstructionMetadata,
                    failedIdentifier: nil,
                    detail: "Legacy target requires Dose 1 reconstruction",
                    previousScheduleRestored: false
                ).userMessage
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        AppFormatters.detailedTime.string(from: date)
    }

    private func notificationSound(isCritical: Bool) -> UNNotificationSound? {
        guard configurationProvider().soundEnabled else { return nil }
        if isCritical && canUseCriticalAlerts {
            return .defaultCritical
        }
        return .default
    }

    private func alarmNotificationSound() -> UNNotificationSound? {
        return notificationSound(isCritical: true)
    }

    private func playAlarmSound() {
        guard UserSettingsManager.shared.soundEnabled else { return }
        usesSystemSoundFallback = true
        AudioServicesPlaySystemSound(Self.fallbackAlarmSystemSoundID)
    }

    private func stopAlarmSound() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func startVibrationLoop() {
        let settings = UserSettingsManager.shared
        vibrationTimer?.invalidate()
        let shouldVibrate = settings.hapticsEnabled
        let shouldPlayFallbackTone = settings.soundEnabled && usesSystemSoundFallback
        guard shouldVibrate || shouldPlayFallbackTone else { return }
        let fallbackSoundID = Self.fallbackAlarmSystemSoundID
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            if shouldVibrate {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
            if shouldPlayFallbackTone {
                AudioServicesPlaySystemSound(fallbackSoundID)
            }
        }
        if let timer = vibrationTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopVibrationLoop() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }

    private var configuredSnoozeDurationMinutes: Int {
        max(1, min(30, configurationProvider().snoozeDurationMinutes))
    }

    private var configuredMaxSnoozes: Int {
        max(0, min(10, configurationProvider().maxSnoozes))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - UNUserNotificationCenterDelegate

extension AlarmService: UNUserNotificationCenterDelegate {
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Diagnostic logging: notification delivered (shown while app in foreground)
        let notificationId = notification.request.identifier
        Task { @MainActor in
            let sessionId = SessionRepository.shared.currentSessionIdString()
            await DiagnosticLogger.shared.logNotificationDelivered(
                sessionId: sessionId,
                notificationId: notificationId,
                category: notification.request.content.categoryIdentifier
            )

            if notificationId == NotificationID.dose2Alarm || notificationId.hasPrefix(NotificationID.followUp) {
                self.startRinging()
            }
        }
        
        // Show notification even when app is in foreground.
        // Respect live sound toggle changes.
        var options: UNNotificationPresentationOptions = [.banner, .badge]
        if UserSettingsManager.shared.soundEnabled {
            options.insert(.sound)
        }
        completionHandler(options)
    }
    
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Diagnostic logging: notification tapped
        let notificationId = response.notification.request.identifier
        let actionId = response.actionIdentifier
        
        Task { @MainActor in
            let sessionId = SessionRepository.shared.currentSessionIdString()
            
            if actionId == UNNotificationDismissActionIdentifier {
                await DiagnosticLogger.shared.logNotificationDismissed(
                    sessionId: sessionId,
                    notificationId: notificationId,
                    category: response.notification.request.content.categoryIdentifier,
                    actionId: actionId
                )
            } else {
                await DiagnosticLogger.shared.logNotificationTapped(
                    sessionId: sessionId,
                    notificationId: notificationId,
                    category: response.notification.request.content.categoryIdentifier,
                    actionId: actionId
                )
            }

            if actionId == NotificationAction.snooze {
                await self.handleNotificationSnoozeAction()
            } else if actionId == NotificationAction.stop {
                // Opening the app is not a medication record. Keep the alarm
                // active until the user explicitly logs Dose 2 or a skip.
                self.startRinging()
            } else if actionId == UNNotificationDefaultActionIdentifier {
                if notificationId == NotificationID.dose2Alarm || notificationId.hasPrefix(NotificationID.followUp) {
                    self.startRinging()
                }
            }
        }
        
        completionHandler()
    }
}
