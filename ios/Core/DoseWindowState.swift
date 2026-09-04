import Foundation

public struct DoseWindowConfig {
    public let minIntervalMin: Int
    public let maxIntervalMin: Int
    public let nearWindowThresholdMin: Int
    public let defaultTargetMin: Int
    public let snoozeStepMin: Int
    public var maxSnoozes: Int
    /// Delay after the planned window ends before emphasizing the unresolved-record prompt.
    /// This value never changes medication state on its own.
    public let unresolvedPromptDelayMin: Int

    public init(minIntervalMin: Int = 150,
                maxIntervalMin: Int = 240,
                nearWindowThresholdMin: Int = 15,
                defaultTargetMin: Int = 165,
                snoozeStepMin: Int = 10,
                maxSnoozes: Int = 3,
                unresolvedPromptDelayMin: Int = 30) {
        self.minIntervalMin = minIntervalMin
        self.maxIntervalMin = maxIntervalMin
        self.nearWindowThresholdMin = nearWindowThresholdMin
        self.defaultTargetMin = defaultTargetMin
        self.snoozeStepMin = snoozeStepMin
        self.maxSnoozes = maxSnoozes
        self.unresolvedPromptDelayMin = unresolvedPromptDelayMin
    }
}

/// Shared timing classification. Only display code may round elapsed minutes.
public enum MedicationTiming: Equatable, Sendable {
    case invalid, early, inWindow, late

    public static func classify(elapsedSeconds: TimeInterval, config: DoseWindowConfig = DoseWindowConfig()) -> Self {
        guard elapsedSeconds.isFinite, elapsedSeconds >= 0 else { return .invalid }
        if elapsedSeconds < Double(config.minIntervalMin) * 60 { return .early }
        if elapsedSeconds >= Double(config.maxIntervalMin) * 60 { return .late }
        return .inWindow
    }

    public static func classify(dose1: Date, dose2: Date, config: DoseWindowConfig = DoseWindowConfig()) -> Self {
        classify(elapsedSeconds: dose2.timeIntervalSince(dose1), config: config)
    }
}

public enum DoseActionPrimaryCTA: Equatable {
    case takeNow
    case takeBeforeWindowEnds(remaining: TimeInterval)
    case waitingUntilEarliest(remaining: TimeInterval)
    /// The planned window ended with no recorded Dose 2 outcome. The user may
    /// record an occurrence that already happened or explicitly mark it missed.
    case resolveExpiredRecord(reason: String)
    case disabled(String)
}

public enum DoseSecondaryActionState: Equatable {
    case snoozeEnabled(remaining: TimeInterval)
    case snoozeDisabled(reason: String)
    case skipEnabled
    case skipDisabled(reason: String)
}

public enum DoseWindowPhase: Equatable, Sendable {
    case noDose1
    case beforeWindow
    case active
    case nearClose
    case closed
    case completed
    case finalizing  // User pressed Wake Up, awaiting morning check-in
}

public enum DoseWindowError: Equatable, Error { case windowExceeded, dose1Required, snoozeLimitReached }

public struct DoseWindowContext: Equatable {
    public let phase: DoseWindowPhase
    public let primary: DoseActionPrimaryCTA
    public let snooze: DoseSecondaryActionState
    public let skip: DoseSecondaryActionState
    public let elapsedSinceDose1: TimeInterval?
    public let remainingToMax: TimeInterval?
    public let errors: [DoseWindowError]
    public let snoozeCount: Int
}

public struct DoseWindowCalculator {
    public let config: DoseWindowConfig
    public let now: () -> Date
    public init(config: DoseWindowConfig = DoseWindowConfig(), now: @escaping () -> Date = { Date() }) {
        self.config = config; self.now = now
    }

    public func context(dose1At: Date?, dose2TakenAt: Date?, dose2Skipped: Bool, snoozeCount: Int, wakeFinalAt: Date? = nil, checkInCompleted: Bool = false) -> DoseWindowContext {
        func canonicalSkipState(for phase: DoseWindowPhase) -> DoseSecondaryActionState {
            switch DoseRegistrationPolicy.evaluateSkipState(
                dose1Time: dose1At,
                dose2Time: dose2TakenAt,
                dose2Skipped: dose2Skipped,
                windowPhase: phase
            ) {
            case .allowed:
                return .skipEnabled
            case .blocked(let reason):
                return .skipDisabled(reason: reason)
            case .requiresConfirmation:
                return .skipDisabled(reason: "Confirmation required")
            }
        }

        // If wake final logged but check-in not done, we're in finalizing state
        if wakeFinalAt != nil && !checkInCompleted {
            return DoseWindowContext(phase: .finalizing, primary: .disabled("Complete Check-In"), snooze: .snoozeDisabled(reason: "Session ending"), skip: canonicalSkipState(for: .finalizing), elapsedSinceDose1: elapsed(from: dose1At), remainingToMax: nil, errors: [], snoozeCount: snoozeCount)
        }
        
        // If check-in is completed, session is done
        if checkInCompleted {
            return DoseWindowContext(phase: .completed, primary: .disabled("Session Complete"), snooze: .snoozeDisabled(reason: "Completed"), skip: canonicalSkipState(for: .completed), elapsedSinceDose1: elapsed(from: dose1At), remainingToMax: nil, errors: [], snoozeCount: snoozeCount)
        }
        
        if dose2TakenAt != nil || dose2Skipped {
            return DoseWindowContext(phase: .completed, primary: .disabled("Completed"), snooze: .snoozeDisabled(reason: "Completed"), skip: canonicalSkipState(for: .completed), elapsedSinceDose1: elapsed(from: dose1At), remainingToMax: nil, errors: [], snoozeCount: snoozeCount)
        }
        guard let d1 = dose1At else {
            return DoseWindowContext(phase: .noDose1, primary: .disabled("Log Dose 1 first"), snooze: .snoozeDisabled(reason: "Dose 1 required"), skip: canonicalSkipState(for: .noDose1), elapsedSinceDose1: nil, remainingToMax: nil, errors: [.dose1Required], snoozeCount: snoozeCount)
        }
        let current = now(); let elapsed = current.timeIntervalSince(d1)
        let minS = Double(config.minIntervalMin) * 60
        let maxS = Double(config.maxIntervalMin) * 60
        let remaining = maxS - elapsed
        if MedicationTiming.classify(elapsedSeconds: elapsed, config: config) == .early || elapsed < 0 {
            return DoseWindowContext(phase: .beforeWindow, primary: .waitingUntilEarliest(remaining: minS - elapsed), snooze: .snoozeDisabled(reason: "Too early"), skip: canonicalSkipState(for: .beforeWindow), elapsedSinceDose1: elapsed, remainingToMax: remaining, errors: [], snoozeCount: snoozeCount)
        }
        if MedicationTiming.classify(elapsedSeconds: elapsed, config: config) == .late {
            // The timing window ended, but the treatment record remains unresolved
            // until the user records an actual occurrence or explicitly marks it missed.
            return DoseWindowContext(phase: .closed, primary: .resolveExpiredRecord(reason: "Dose 2 record unresolved"), snooze: .snoozeDisabled(reason: "Window ended"), skip: canonicalSkipState(for: .closed), elapsedSinceDose1: elapsed, remainingToMax: 0, errors: [.windowExceeded], snoozeCount: snoozeCount)
        }
        let nearThresholdS = Double(config.nearWindowThresholdMin) * 60
        let snoozeState: DoseSecondaryActionState
        if remaining <= nearThresholdS {
            snoozeState = .snoozeDisabled(reason: "<\(config.nearWindowThresholdMin)m left")
            return DoseWindowContext(phase: .nearClose, primary: .takeBeforeWindowEnds(remaining: remaining), snooze: snoozeState, skip: canonicalSkipState(for: .nearClose), elapsedSinceDose1: elapsed, remainingToMax: remaining, errors: [], snoozeCount: snoozeCount)
        } else {
            if config.maxSnoozes > 0 && snoozeCount >= config.maxSnoozes {
                snoozeState = .snoozeDisabled(reason: "Snooze limit")
            } else {
                snoozeState = .snoozeEnabled(remaining: remaining)
            }
            return DoseWindowContext(phase: .active, primary: .takeNow, snooze: snoozeState, skip: canonicalSkipState(for: .active), elapsedSinceDose1: elapsed, remainingToMax: remaining, errors: [], snoozeCount: snoozeCount)
        }
    }

    private func elapsed(from dose1At: Date?) -> TimeInterval? { dose1At.map { now().timeIntervalSince($0) } }
    
    // MARK: - Unresolved Record Prompt

    /// Returns whether the UI should emphasize completion of an unresolved Dose 2
    /// record. This is presentation-only: callers must not infer taken, skipped,
    /// missed, closed, or unavailable from the passage of time.
    public func shouldPromptForUnresolvedDose2(
        dose1At: Date?,
        dose2TakenAt: Date?,
        dose2Skipped: Bool
    ) -> Bool {
        guard let d1 = dose1At,
              dose2TakenAt == nil,
              !dose2Skipped else {
            return false
        }
        
        let elapsed = now().timeIntervalSince(d1)
        let promptThresholdSeconds = Double(config.maxIntervalMin + config.unresolvedPromptDelayMin) * 60
        
        return elapsed >= promptThresholdSeconds
    }
    
    // MARK: - Late Dose 1 Detection
    
    /// Check if current time is in the "late night" zone (midnight to 6 AM)
    /// When Dose 1 is taken in this window, it belongs to the PREVIOUS day's sleep session
    /// Returns the session date that Dose 1 would be assigned to if taken now
    public func lateDose1Info() -> (isLateNight: Bool, sessionDateLabel: String) {
        let current = now()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: current)
        
        let isLateNight = hour < 6 // Midnight to 5:59 AM
        
        // Calculate which date the session belongs to
        let sessionDate: Date
        if isLateNight {
            sessionDate = calendar.date(byAdding: .day, value: -1, to: current) ?? current
        } else {
            sessionDate = current
        }
        
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d" // e.g., "Wednesday, Dec 25"
        let sessionDateLabel = formatter.string(from: sessionDate)
        
        return (isLateNight, sessionDateLabel)
    }
    
    // MARK: - Timezone Change Detection
    
    /// Get the current timezone offset from UTC in minutes
    /// Used to detect if timezone has changed during a session
    public static func currentTimezoneOffsetMinutes() -> Int {
        return TimeZone.current.secondsFromGMT() / 60
    }
    
    /// Check if timezone has changed since a reference offset
    /// Returns the delta in minutes (positive = moved east, negative = moved west)
    /// Returns nil if no change
    public func timezoneChange(from referenceOffsetMinutes: Int) -> Int? {
        let currentOffset = Self.currentTimezoneOffsetMinutes()
        let delta = currentOffset - referenceOffsetMinutes
        
        if delta == 0 {
            return nil
        }
        
        return delta
    }
    
    /// Human-readable timezone change description
    /// E.g., "Timezone shifted 3 hours east" or "Timezone shifted 1 hour west"
    public func timezoneChangeDescription(from referenceOffsetMinutes: Int) -> String? {
        guard let delta = timezoneChange(from: referenceOffsetMinutes) else {
            return nil
        }
        
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
    
    // MARK: - Session Date Calculation
    
    /// Calculate the session date string for a given timestamp.
    /// Sessions use a 6 PM boundary:
    /// - 6:00 PM to 11:59 PM → that calendar day
    /// - 12:00 AM to 5:59 PM → previous calendar day
    /// This groups overnight doses (11 PM Dose 1 → 2 AM Dose 2) into a single session.
    /// 
    /// - Parameters:
    ///   - timestamp: The date/time to evaluate
    ///   - timeZone: The timezone to use for boundary calculation. Defaults to user's current timezone.
    /// - Returns: ISO8601 date string (e.g., "2025-12-26")
    public func sessionDateString(for timestamp: Date, in timeZone: TimeZone? = nil) -> String {
        return sessionKey(for: timestamp, timeZone: timeZone ?? .current, rolloverHour: 18)
    }
    
    /// Get remaining minutes until window closes for a specific session state.
    /// Returns nil if no dose 1 or window already closed.
    public func remainingMinutes(
        dose1At: Date?,
        dose2TakenAt: Date?,
        dose2Skipped: Bool,
        snoozeCount: Int
    ) -> Int? {
        let ctx = context(
            dose1At: dose1At,
            dose2TakenAt: dose2TakenAt,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount
        )
        guard let remaining = ctx.remainingToMax else { return nil }
        return Int(remaining / 60)
    }
}
