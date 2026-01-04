import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Diagnostic Logger

/// Session-scoped diagnostic logger that writes JSONL to per-session folders.
///
/// Per SSOT v2.14.0 contract:
/// - Every log MUST have a session_id
/// - Views MAY NOT call this directly (only SessionRepository, DoseWindowCalculator, AlarmService, CheckIn)
/// - Logs are stored in Documents/diagnostics/sessions/{session_id}/
/// - Format: events.jsonl (append-only), errors.jsonl (errors only), meta.json (static context)
///
/// Thread Safety: Uses actor isolation for all file operations.
///
public actor DiagnosticLogger {
    
    // MARK: - Singleton
    
    public static let shared = DiagnosticLogger()
    
    // MARK: - Configuration
    
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let dateFormatter: ISO8601DateFormatter
    
    /// Monotonically increasing sequence number per session (for forensic reconstruction)
    /// Key: sessionId, Value: last sequence number written
    private var sessionSequence: [String: Int] = [:]
    
    /// Root directory for diagnostics
    private var diagnosticsRoot: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("diagnostics/sessions", isDirectory: true)
    }
    
    /// Whether logging is enabled (can be disabled in settings)
    public var isEnabled: Bool = true
    
    /// Maximum age of sessions to keep (in days)
    public var retentionDays: Int = 14
    
    // MARK: - Initialization
    
    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        
        // Use built-in ISO8601 encoding (thread-safe, no custom closure)
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .iso8601
    }
    
    // MARK: - Public API
    
    /// Log a diagnostic event.
    /// - Parameters:
    ///   - event: The event type
    ///   - level: Log level (default: .info)
    ///   - sessionId: Session identifier (YYYY-MM-DD) - REQUIRED
    ///   - context: Builder closure to add context fields
    public func log(
        _ event: DiagnosticEvent,
        level: DiagnosticLevel = .info,
        sessionId: String,
        context: ((inout DiagnosticLogEntry) -> Void)? = nil
    ) {
        guard isEnabled else { return }
        guard !sessionId.isEmpty else {
            print("⚠️ DiagnosticLogger: Rejected event \(event.rawValue) - missing session_id")
            return
        }
        
        var entry = DiagnosticLogEntry(
            ts: Date(),
            level: level,
            event: event,
            sessionId: sessionId,
            appVersion: Self.appVersion,
            build: Self.buildType
        )
        
        // Assign monotonically increasing sequence number for this session
        let seq = (sessionSequence[sessionId] ?? 0) + 1
        sessionSequence[sessionId] = seq
        entry.seq = seq
        
        // Allow caller to add context
        context?(&entry)
        
        // Write to events.jsonl
        appendEntry(entry, to: "events.jsonl", sessionId: sessionId)
        
        // Also write errors to errors.jsonl for quick triage
        if level == .error || level == .warning {
            appendEntry(entry, to: "errors.jsonl", sessionId: sessionId)
        }
        
        #if DEBUG
        print("📋 \(event.rawValue) [\(sessionId)]")
        #endif
    }
    
    /// Ensure session metadata is written (call once when session starts)
    public func ensureSessionMetadata(sessionId: String) {
        guard isEnabled else { return }
        
        let sessionDir = sessionDirectory(for: sessionId)
        let metaFile = sessionDir.appendingPathComponent("meta.json")
        
        // Only write if doesn't exist
        guard !fileManager.fileExists(atPath: metaFile.path) else { return }
        
        // Create session directory if needed
        try? fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        
        let metadata = SessionMetadata(
            sessionId: sessionId,
            createdAt: Date(),
            appVersion: Self.appVersion,
            buildNumber: Self.buildNumber,
            buildType: Self.buildType,
            deviceModel: Self.deviceModel,
            osVersion: Self.osVersion,
            timezone: TimeZone.current.identifier,
            timezoneOffsetMinutes: TimeZone.current.secondsFromGMT() / 60,
            constantsHash: Self.constantsHash
        )
        
        do {
            let data = try encoder.encode(metadata)
            try data.write(to: metaFile)
        } catch {
            print("⚠️ DiagnosticLogger: Failed to write meta.json: \(error)")
        }
    }
    
    /// Export a session's diagnostics as a temporary directory URL.
    /// Caller is responsible for sharing/copying the contents.
    public func exportSession(_ sessionId: String) -> URL? {
        let sessionDir = sessionDirectory(for: sessionId)
        guard fileManager.fileExists(atPath: sessionDir.path) else { return nil }
        return sessionDir
    }
    
    /// List all available session IDs with diagnostics
    public func availableSessions() -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: diagnosticsRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
            .sorted(by: >)  // Most recent first
    }
    
    /// Prune old sessions beyond retention period
    public func pruneOldSessions() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let cutoffString = ISO8601DateFormatter.string(from: cutoff, timeZone: .current, formatOptions: [.withFullDate])
        let cutoffPrefix = String(cutoffString.prefix(10))  // YYYY-MM-DD
        
        let sessions = availableSessions()
        for sessionId in sessions {
            if sessionId < cutoffPrefix {
                let sessionDir = sessionDirectory(for: sessionId)
                try? fileManager.removeItem(at: sessionDir)
                #if DEBUG
                print("🗑️ DiagnosticLogger: Pruned old session \(sessionId)")
                #endif
            }
        }
    }
    
    /// Get the file path for a session's events log (for testing/debugging)
    public func eventsFilePath(for sessionId: String) -> URL {
        return sessionDirectory(for: sessionId).appendingPathComponent("events.jsonl")
    }
    
    // MARK: - Private Helpers
    
    private func sessionDirectory(for sessionId: String) -> URL {
        return diagnosticsRoot.appendingPathComponent(sessionId, isDirectory: true)
    }
    
    private func appendEntry(_ entry: DiagnosticLogEntry, to filename: String, sessionId: String) {
        let sessionDir = sessionDirectory(for: sessionId)
        let file = sessionDir.appendingPathComponent(filename)
        
        // Create directory if needed
        if !fileManager.fileExists(atPath: sessionDir.path) {
            try? fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            ensureSessionMetadata(sessionId: sessionId)
        }
        
        // Encode entry as single line JSON
        guard let jsonData = try? encoder.encode(entry),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        jsonString += "\n"
        
        // Append to file
        if fileManager.fileExists(atPath: file.path) {
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                if let data = jsonString.data(using: .utf8) {
                    handle.write(data)
                }
                // closeFile() deprecated but works on all platforms; close() requires iOS 13+
                handle.closeFile()
            }
        } else {
            try? jsonString.write(to: file, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - Static Device/App Info
    
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
    
    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    
    private static var buildType: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
    
    private static var deviceModel: String {
        #if canImport(UIKit) && !os(watchOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
        #else
        return "unknown"
        #endif
    }
    
    private static var osVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
    
    private static var constantsHash: String? {
        // Load constants.json and compute simple hash for drift detection
        guard let url = Bundle.main.url(forResource: "constants", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        // Simple hash: first 8 chars of SHA-256 would be ideal, but we'll use count + checksum for simplicity
        let checksum = data.reduce(0) { ($0 &+ UInt32($1)) & 0xFFFFFFFF }
        return String(format: "%08x", checksum)
    }
}

// MARK: - Convenience Extensions

public extension DiagnosticLogger {
    
    /// Log session started event
    func logSessionStarted(sessionId: String) {
        log(.sessionStarted, sessionId: sessionId)
    }
    
    /// Log phase transition
    func logPhaseEntered(
        sessionId: String,
        phase: String,
        previousPhase: String? = nil,
        elapsedMinutes: Int? = nil,
        remainingMinutes: Int? = nil
    ) {
        log(.sessionPhaseEntered, sessionId: sessionId) { entry in
            entry.phase = phase
            entry.previousPhase = previousPhase
            entry.elapsedMinutes = elapsedMinutes
            entry.remainingMinutes = remainingMinutes
        }
    }
    
    /// Log dose taken
    func logDoseTaken(
        sessionId: String,
        dose: Int,
        at timestamp: Date,
        elapsedMinutes: Int? = nil
    ) {
        let event: DiagnosticEvent = dose == 1 ? .dose1Taken : .dose2Taken
        log(event, sessionId: sessionId) { entry in
            if dose == 1 {
                entry.dose1Time = timestamp
            } else {
                entry.dose2Time = timestamp
            }
            entry.elapsedMinutes = elapsedMinutes
        }
    }
    
    /// Log session completion
    func logSessionCompleted(
        sessionId: String,
        terminalState: String,
        dose1Time: Date? = nil,
        dose2Time: Date? = nil
    ) {
        let event: DiagnosticEvent
        switch terminalState {
        case "completed": event = .sessionCompleted
        case "skipped": event = .sessionSkipped
        case "expired", "incomplete_slept_through": event = .sessionExpired
        default: event = .sessionCompleted
        }
        
        log(event, sessionId: sessionId) { entry in
            entry.terminalState = terminalState
            entry.dose1Time = dose1Time
            entry.dose2Time = dose2Time
            // Include constants_hash on terminal events for config drift detection
            entry.constantsHash = Self.constantsHash
        }
    }
    
    /// Log alarm event
    func logAlarm(
        _ event: DiagnosticEvent,
        sessionId: String,
        alarmId: String,
        reason: String? = nil
    ) {
        log(event, sessionId: sessionId) { entry in
            entry.alarmId = alarmId
            entry.reason = reason
        }
    }
    
    /// Log window boundary event
    func logWindowBoundary(
        _ event: DiagnosticEvent,
        sessionId: String,
        phase: String,
        elapsedMinutes: Int,
        remainingMinutes: Int? = nil
    ) {
        log(event, sessionId: sessionId) { entry in
            entry.phase = phase
            entry.elapsedMinutes = elapsedMinutes
            entry.remainingMinutes = remainingMinutes
        }
    }
    
    /// Log error
    func logError(
        _ event: DiagnosticEvent,
        sessionId: String,
        reason: String
    ) {
        log(event, level: .error, sessionId: sessionId) { entry in
            entry.reason = reason
        }
    }
    
    // MARK: - Tier 1: App Lifecycle
    
    /// Log app foregrounded
    func logAppForegrounded(sessionId: String, backgroundDurationSeconds: Int? = nil) {
        log(.appForegrounded, sessionId: sessionId) { entry in
            entry.backgroundDurationSeconds = backgroundDurationSeconds
        }
    }
    
    /// Log app backgrounded
    func logAppBackgrounded(sessionId: String) {
        log(.appBackgrounded, sessionId: sessionId)
    }
    
    /// Log app launched
    func logAppLaunched(sessionId: String) {
        log(.appLaunched, sessionId: sessionId)
    }
    
    // MARK: - Tier 1: Timezone & Time
    
    /// Log timezone change
    func logTimezoneChanged(
        sessionId: String,
        previousTimezone: String,
        newTimezone: String,
        previousOffset: Int,
        newOffset: Int
    ) {
        log(.timezoneChanged, level: .warning, sessionId: sessionId) { entry in
            entry.previousTimezone = previousTimezone
            entry.newTimezone = newTimezone
            entry.previousTimezoneOffset = previousOffset
            entry.newTimezoneOffset = newOffset
            // Include constants_hash to distinguish "did time move or did rules change?"
            entry.constantsHash = Self.constantsHash
        }
    }
    
    /// Log significant time change
    func logTimeSignificantChange(sessionId: String, timeDeltaSeconds: Int) {
        log(.timeSignificantChange, level: .warning, sessionId: sessionId) { entry in
            entry.timeDeltaSeconds = timeDeltaSeconds
            entry.constantsHash = Self.constantsHash
        }
    }
    
    // MARK: - Tier 1: Notification Delivery
    
    /// Log notification delivered
    func logNotificationDelivered(sessionId: String, notificationId: String, category: String? = nil) {
        log(.notificationDelivered, sessionId: sessionId) { entry in
            entry.notificationId = notificationId
            entry.notificationCategory = category
        }
    }
    
    /// Log notification tapped
    func logNotificationTapped(sessionId: String, notificationId: String, category: String? = nil) {
        log(.notificationTapped, sessionId: sessionId) { entry in
            entry.notificationId = notificationId
            entry.notificationCategory = category
        }
    }
    
    /// Log notification dismissed
    func logNotificationDismissed(sessionId: String, notificationId: String, category: String? = nil) {
        log(.notificationDismissed, sessionId: sessionId) { entry in
            entry.notificationId = notificationId
            entry.notificationCategory = category
        }
    }
    
    // MARK: - Tier 1: Undo Flow
    
    /// Log undo window opened
    func logUndoWindowOpened(sessionId: String, targetType: String) {
        log(.undoWindowOpened, sessionId: sessionId) { entry in
            entry.undoTargetType = targetType
        }
    }
    
    /// Log undo executed
    func logUndoExecuted(sessionId: String, targetType: String) {
        log(.undoExecuted, sessionId: sessionId) { entry in
            entry.undoTargetType = targetType
        }
    }
    
    /// Log undo expired
    func logUndoExpired(sessionId: String, targetType: String) {
        log(.undoExpired, sessionId: sessionId) { entry in
            entry.undoTargetType = targetType
        }
    }
    
    // MARK: - Tier 2: Sleep Events
    
    /// Log sleep event logged
    func logSleepEventLogged(sessionId: String, eventType: String, eventId: String) {
        log(.sleepEventLogged, sessionId: sessionId) { entry in
            entry.sleepEventType = eventType
            entry.sleepEventId = eventId
        }
    }
    
    /// Log sleep event deleted
    func logSleepEventDeleted(sessionId: String, eventType: String, eventId: String) {
        log(.sleepEventDeleted, sessionId: sessionId) { entry in
            entry.sleepEventType = eventType
            entry.sleepEventId = eventId
        }
    }
    
    // MARK: - Tier 2: Pre-Sleep Log
    
    /// Log pre-sleep started
    func logPreSleepStarted(sessionId: String) {
        log(.preSleepLogStarted, sessionId: sessionId)
    }
    
    /// Log pre-sleep saved
    func logPreSleepSaved(sessionId: String) {
        log(.preSleepLogSaved, sessionId: sessionId)
    }
    
    /// Log pre-sleep abandoned
    func logPreSleepAbandoned(sessionId: String) {
        log(.preSleepLogAbandoned, sessionId: sessionId)
    }
    
    // MARK: - Invariant Violations
    
    /// Log something that "should never happen"
    /// Always logged at error level; always warrants investigation.
    ///
    /// - Parameters:
    ///   - name: Short identifier for the invariant (e.g., "negative_elapsed", "dose2_before_window")
    ///   - sessionId: Session ID (required even for invariant violations)
    ///   - reason: Human-readable explanation of what went wrong
    func logInvariantViolation(
        name: String,
        sessionId: String,
        reason: String
    ) {
        log(.invariantViolation, level: .error, sessionId: sessionId) { entry in
            entry.invariantName = name
            entry.reason = reason
            entry.constantsHash = Self.constantsHash
        }
    }
}
