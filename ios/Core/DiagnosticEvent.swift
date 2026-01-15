import Foundation

// MARK: - Diagnostic Event Types

/// Diagnostic events mirror SSOT state names exactly.
/// Each event is a state fact, not a UI action.
///
/// Per SSOT v2.14.0 Diagnostic Logging contract:
/// - Views MAY NOT emit diagnostic events directly
/// - Every event MUST have a session_id
/// - Log only transitions and invariants, not ticks
///
public enum DiagnosticEvent: String, Codable, Sendable {
    // MARK: - Session Lifecycle
    
    /// Session started (first activity of the night)
    case sessionStarted = "session.started"
    
    /// Phase changed (beforeWindow → active → nearClose → closed)
    case sessionPhaseEntered = "session.phase.entered"
    
    /// Session completed normally (Dose 2 taken)
    case sessionCompleted = "session.completed"
    
    /// Session expired (window closed without action)
    case sessionExpired = "session.expired"
    
    /// User explicitly skipped Dose 2
    case sessionSkipped = "session.skipped"
    
    /// System auto-expired session (slept through)
    case sessionAutoExpired = "session.autoExpired"
    
    /// Session rolled over to new day
    case sessionRollover = "session.rollover"
    
    // MARK: - Dose Window Boundaries
    
    /// Window opened (150 minutes elapsed)
    case doseWindowOpened = "dose.window.opened"
    
    /// Window near close (<15 minutes remaining)
    case doseWindowNearClose = "dose.window.nearClose"
    
    /// Window expired (240 minutes elapsed)
    case doseWindowExpired = "dose.window.expired"
    
    /// Action blocked by guard (e.g., snooze limit)
    case doseWindowBlocked = "dose.window.blocked"
    
    /// User required to confirm override (e.g., late dose)
    case doseWindowOverrideRequired = "dose.window.override.required"
    
    // MARK: - Dose Actions
    
    /// Dose 1 taken
    case dose1Taken = "dose.1.taken"
    
    /// Dose 2 taken
    case dose2Taken = "dose.2.taken"

    /// Extra dose taken (dose 3+)
    case doseExtraTaken = "dose.extra.taken"
    
    /// Dose 2 skipped by user
    case dose2Skipped = "dose.2.skipped"
    
    /// Dose undone via undo snackbar
    case doseUndone = "dose.undone"
    
    /// Snooze activated
    case snoozeActivated = "dose.snooze.activated"
    
    // MARK: - Alarms / Notifications
    
    /// Alarm scheduled
    case alarmScheduled = "alarm.scheduled"
    
    /// Alarm cancelled
    case alarmCancelled = "alarm.cancelled"
    
    /// Alarm suppressed (e.g., <15m remaining)
    case alarmSuppressed = "alarm.suppressed"
    
    /// Alarm auto-cancelled on session completion
    case alarmAutoCancelled = "alarm.autoCancelled"
    
    // MARK: - Morning Check-In
    
    /// Check-in flow started
    case checkinStarted = "checkin.started"
    
    /// Check-in completed
    case checkinCompleted = "checkin.completed"
    
    /// Check-in skipped
    case checkinSkipped = "checkin.skipped"
    
    // MARK: - App Lifecycle (Tier 1 - Critical for Safety Debugging)
    
    /// App came to foreground
    case appForegrounded = "app.foregrounded"
    
    /// App went to background
    case appBackgrounded = "app.backgrounded"
    
    /// App launched (cold start)
    case appLaunched = "app.launched"
    
    /// App terminated
    case appTerminated = "app.terminated"
    
    // MARK: - Time & Timezone (Tier 1 - Critical for Safety Debugging)
    
    /// Timezone changed mid-session
    case timezoneChanged = "timezone.changed"
    
    /// Significant time change (clock jumped, travel, manual change)
    case timeSignificantChange = "time.significantChange"
    
    // MARK: - Notification Delivery (Tier 1 - Critical for Safety Debugging)
    
    /// Notification was delivered to device
    case notificationDelivered = "notification.delivered"
    
    /// User tapped notification
    case notificationTapped = "notification.tapped"
    
    /// Notification dismissed without action
    case notificationDismissed = "notification.dismissed"
    
    // MARK: - Undo Flow (Tier 1 - Critical for Safety Debugging)
    
    /// Undo window opened (5s timer started)
    case undoWindowOpened = "undo.windowOpened"
    
    /// User executed undo
    case undoExecuted = "undo.executed"
    
    /// Undo window expired without action
    case undoExpired = "undo.expired"
    
    // MARK: - Sleep Events (Tier 2 - Session Context)
    
    /// Sleep event logged (bathroom, lights_out, etc.)
    case sleepEventLogged = "sleepEvent.logged"
    
    /// Sleep event deleted
    case sleepEventDeleted = "sleepEvent.deleted"
    
    /// Sleep event edited
    case sleepEventEdited = "sleepEvent.edited"
    
    // MARK: - Pre-Sleep Log (Tier 2 - Session Context)
    
    /// Pre-sleep questionnaire started
    case preSleepLogStarted = "preSleepLog.started"
    
    /// Pre-sleep questionnaire saved
    case preSleepLogSaved = "preSleepLog.saved"
    
    /// Pre-sleep questionnaire abandoned
    case preSleepLogAbandoned = "preSleepLog.abandoned"
    
    // MARK: - Errors
    
    /// Storage error
    case errorStorage = "error.storage"
    
    /// Notification error
    case errorNotification = "error.notification"
    
    /// Timezone change detected
    case errorTimezone = "error.timezone"
    
    // MARK: - Invariant Violations (Should Never Happen)
    
    /// Something that "should never happen" did happen.
    /// Examples: elapsed_minutes < 0, dose2 in beforeWindow without override,
    /// session_id empty, impossible state transitions.
    /// These are gold during rare bugs—always warrant investigation.
    case invariantViolation = "invariant.violation"
}

// MARK: - Diagnostic Level

/// Log levels for diagnostic events
public enum DiagnosticLevel: String, Codable, Sendable {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
}

// MARK: - Diagnostic Log Entry

/// A single diagnostic log entry with full context.
/// Serialized as JSON to events.jsonl
public struct DiagnosticLogEntry: Codable, Sendable {
    /// ISO8601 timestamp with timezone offset
    public let ts: Date
    
    /// Monotonically increasing sequence number per session (for forensic reconstruction)
    /// Allows reconstruction even under timestamp collision or file truncation
    public var seq: Int?
    
    /// Log level
    public let level: DiagnosticLevel
    
    /// Event type (dot-notation)
    public let event: DiagnosticEvent
    
    /// Session identifier (UUID string for active sessions; legacy sessions may use session_date)
    /// Note: This is a logical grouping key and should not be parsed as a date.
    public let sessionId: String
    
    /// App version
    public let appVersion: String
    
    /// Build type (debug/release)
    public let build: String
    
    // MARK: - Optional Context Fields
    
    /// Current phase (for phase-related events)
    public var phase: String?
    
    /// Dose 1 timestamp
    public var dose1Time: Date?
    
    /// Dose 2 timestamp
    public var dose2Time: Date?

    /// Dose index within session (1, 2, 3+)
    public var doseIndex: Int?
    
    /// Elapsed minutes since Dose 1
    public var elapsedMinutes: Int?

    /// Elapsed minutes since previous dose
    public var elapsedSincePrevDoseMinutes: Int?

    /// True if dose 2 was taken after window close
    public var isLate: Bool?
    
    /// Remaining minutes in window
    public var remainingMinutes: Int?
    
    /// Snooze count
    public var snoozeCount: Int?
    
    /// Terminal state (completed, skipped, expired)
    public var terminalState: String?
    
    /// Reason for blocked/suppressed events
    public var reason: String?
    
    /// Alarm/notification identifier
    public var alarmId: String?
    
    /// Previous phase (for transitions)
    public var previousPhase: String?
    
    // MARK: - Tier 1 Context Fields (App Lifecycle, Timezone, Undo)
    
    /// Previous timezone identifier (for timezone.changed)
    public var previousTimezone: String?
    
    /// New timezone identifier (for timezone.changed)
    public var newTimezone: String?
    
    /// Previous timezone offset in minutes
    public var previousTimezoneOffset: Int?
    
    /// New timezone offset in minutes
    public var newTimezoneOffset: Int?
    
    /// Time difference in seconds (for time.significantChange)
    public var timeDeltaSeconds: Int?
    
    /// Notification identifier (for notification events)
    public var notificationId: String?
    
    /// Notification category (dose_reminder, window_opening, etc.)
    public var notificationCategory: String?
    
    /// Undo target type (dose1, dose2, sleepEvent)
    public var undoTargetType: String?
    
    /// Sleep event type (for sleepEvent.logged/deleted/edited)
    public var sleepEventType: String?
    
    /// Sleep event ID
    public var sleepEventId: String?
    
    /// Background time in seconds (for app.foregrounded)
    public var backgroundDurationSeconds: Int?
    
    /// Config hash for detecting drift (on session completion, timezone changes)
    public var constantsHash: String?
    
    /// Invariant name (for invariant.violation events)
    /// Examples: "negative_elapsed", "dose2_before_window", "empty_session_id"
    public var invariantName: String?
    
    public init(
        ts: Date = Date(),
        level: DiagnosticLevel = .info,
        event: DiagnosticEvent,
        sessionId: String,
        appVersion: String,
        build: String
    ) {
        self.ts = ts
        self.level = level
        self.event = event
        self.sessionId = sessionId
        self.appVersion = appVersion
        self.build = build
    }
    
    // MARK: - Codable with Custom Keys
    
    enum CodingKeys: String, CodingKey {
        case ts
        case seq
        case level
        case event
        case sessionId = "session_id"
        case appVersion = "app_version"
        case build
        case phase
        case dose1Time = "dose1_time"
        case dose2Time = "dose2_time"
        case doseIndex = "dose_index"
        case elapsedMinutes = "elapsed_minutes"
        case elapsedSincePrevDoseMinutes = "elapsed_since_prev_dose_minutes"
        case isLate = "is_late"
        case remainingMinutes = "remaining_minutes"
        case snoozeCount = "snooze_count"
        case terminalState = "terminal_state"
        case reason
        case alarmId = "alarm_id"
        case previousPhase = "previous_phase"
        // Tier 1 fields
        case previousTimezone = "previous_timezone"
        case newTimezone = "new_timezone"
        case previousTimezoneOffset = "previous_timezone_offset"
        case newTimezoneOffset = "new_timezone_offset"
        case timeDeltaSeconds = "time_delta_seconds"
        case notificationId = "notification_id"
        case notificationCategory = "notification_category"
        case undoTargetType = "undo_target_type"
        case sleepEventType = "sleep_event_type"
        case sleepEventId = "sleep_event_id"
        case backgroundDurationSeconds = "background_duration_seconds"
        case constantsHash = "constants_hash"
        case invariantName = "invariant_name"
    }
}

// MARK: - Session Metadata

/// Static context for a session, written to meta.json
public struct SessionMetadata: Codable, Sendable {
    /// Session identifier (UUID string or legacy session_date)
    public let sessionId: String
    
    /// When this session was created
    public let createdAt: Date
    
    /// App version
    public let appVersion: String
    
    /// Build number
    public let buildNumber: String
    
    /// Build type (debug/release)
    public let buildType: String
    
    /// Device model (e.g., iPhone15,3)
    public let deviceModel: String
    
    /// OS version
    public let osVersion: String
    
    /// Timezone identifier (e.g., America/New_York)
    public let timezone: String
    
    /// Timezone offset in minutes
    public let timezoneOffsetMinutes: Int
    
    /// Hash of constants.json for config drift detection
    public let constantsHash: String?
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case createdAt = "created_at"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case buildType = "build_type"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case timezone
        case timezoneOffsetMinutes = "timezone_offset_minutes"
        case constantsHash = "constants_hash"
    }
}
