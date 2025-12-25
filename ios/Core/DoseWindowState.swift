import Foundation

public struct DoseWindowConfig {
    public let minIntervalMin: Int
    public let maxIntervalMin: Int
    public let nearWindowThresholdMin: Int
    public let defaultTargetMin: Int
    public let snoozeStepMin: Int
    public var maxSnoozes: Int

    public init(minIntervalMin: Int = 150,
                maxIntervalMin: Int = 240,
                nearWindowThresholdMin: Int = 15,
                defaultTargetMin: Int = 165,
                snoozeStepMin: Int = 10,
                maxSnoozes: Int = 3) {
        self.minIntervalMin = minIntervalMin
        self.maxIntervalMin = maxIntervalMin
        self.nearWindowThresholdMin = nearWindowThresholdMin
        self.defaultTargetMin = defaultTargetMin
        self.snoozeStepMin = snoozeStepMin
        self.maxSnoozes = maxSnoozes
    }
}

public enum DoseActionPrimaryCTA: Equatable {
    case takeNow
    case takeBeforeWindowEnds(remaining: TimeInterval)
    case waitingUntilEarliest(remaining: TimeInterval)
    case takeWithOverride(reason: String)  // Window expired but user can override
    case disabled(String)
}

public enum DoseSecondaryActionState: Equatable {
    case snoozeEnabled(remaining: TimeInterval)
    case snoozeDisabled(reason: String)
    case skipEnabled
    case skipDisabled(reason: String)
}

public enum DoseWindowPhase: Equatable {
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
        // If wake final logged but check-in not done, we're in finalizing state
        if wakeFinalAt != nil && !checkInCompleted {
            return DoseWindowContext(phase: .finalizing, primary: .disabled("Complete Check-In"), snooze: .snoozeDisabled(reason: "Session ending"), skip: .skipDisabled(reason: "Session ending"), elapsedSinceDose1: elapsed(from: dose1At), remainingToMax: nil, errors: [], snoozeCount: snoozeCount)
        }
        
        // If check-in is completed, session is done
        if checkInCompleted {
            return DoseWindowContext(phase: .completed, primary: .disabled("Session Complete"), snooze: .snoozeDisabled(reason: "Completed"), skip: .skipDisabled(reason: "Completed"), elapsedSinceDose1: elapsed(from: dose1At), remainingToMax: nil, errors: [], snoozeCount: snoozeCount)
        }
        
        if dose2TakenAt != nil || dose2Skipped {
            return DoseWindowContext(phase: .completed, primary: .disabled("Completed"), snooze: .snoozeDisabled(reason: "Completed"), skip: .skipDisabled(reason: "Completed"), elapsedSinceDose1: elapsed(from: dose1At), remainingToMax: nil, errors: [], snoozeCount: snoozeCount)
        }
        guard let d1 = dose1At else {
            return DoseWindowContext(phase: .noDose1, primary: .disabled("Log Dose 1 first"), snooze: .snoozeDisabled(reason: "Dose 1 required"), skip: .skipDisabled(reason: "Dose 1 required"), elapsedSinceDose1: nil, remainingToMax: nil, errors: [.dose1Required], snoozeCount: snoozeCount)
        }
        let current = now(); let elapsed = current.timeIntervalSince(d1)
        let minS = Double(config.minIntervalMin) * 60
        let maxS = Double(config.maxIntervalMin) * 60
        let remaining = maxS - elapsed
        if elapsed < minS {
            return DoseWindowContext(phase: .beforeWindow, primary: .waitingUntilEarliest(remaining: minS - elapsed), snooze: .snoozeDisabled(reason: "Too early"), skip: .skipEnabled, elapsedSinceDose1: elapsed, remainingToMax: remaining, errors: [], snoozeCount: snoozeCount)
        }
        if elapsed >= maxS {
            // Window expired - allow override with explicit confirmation
            return DoseWindowContext(phase: .closed, primary: .takeWithOverride(reason: "Window expired"), snooze: .snoozeDisabled(reason: "Window closed"), skip: .skipEnabled, elapsedSinceDose1: elapsed, remainingToMax: 0, errors: [.windowExceeded], snoozeCount: snoozeCount)
        }
        let nearThresholdS = Double(config.nearWindowThresholdMin) * 60
        let snoozeState: DoseSecondaryActionState
        if remaining <= nearThresholdS {
            snoozeState = .snoozeDisabled(reason: "<\(config.nearWindowThresholdMin)m left")
            return DoseWindowContext(phase: .nearClose, primary: .takeBeforeWindowEnds(remaining: remaining), snooze: snoozeState, skip: .skipEnabled, elapsedSinceDose1: elapsed, remainingToMax: remaining, errors: [], snoozeCount: snoozeCount)
        } else {
            if config.maxSnoozes > 0 && snoozeCount >= config.maxSnoozes {
                snoozeState = .snoozeDisabled(reason: "Snooze limit")
            } else {
                snoozeState = .snoozeEnabled(remaining: remaining)
            }
            return DoseWindowContext(phase: .active, primary: .takeNow, snooze: snoozeState, skip: .skipEnabled, elapsedSinceDose1: elapsed, remainingToMax: remaining, errors: [], snoozeCount: snoozeCount)
        }
    }

    private func elapsed(from dose1At: Date?) -> TimeInterval? { dose1At.map { now().timeIntervalSince($0) } }
}
