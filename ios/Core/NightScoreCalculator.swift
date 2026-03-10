import Foundation

// MARK: - Night Score Input

/// All data needed to compute a night quality score.
/// The caller maps its storage models into this lightweight struct.
public struct NightScoreInput: Sendable, Equatable {
    /// Interval between dose 1 and dose 2 in minutes. `nil` if dose 2 was not taken.
    public let intervalMinutes: Double?
    /// Whether dose 2 was skipped (not missed — intentionally skipped).
    public let dose2Skipped: Bool
    /// Whether dose 1 was taken at all.
    public let dose1Taken: Bool
    /// Whether dose 2 was taken.
    public let dose2Taken: Bool
    /// Whether a morning check-in was completed.
    public let checkInCompleted: Bool
    /// Whether key bedtime events were logged (e.g., lights_out).
    public let lightsOutLogged: Bool
    /// Whether a wake event was logged.
    public let wakeFinalLogged: Bool
    /// Total sleep duration in minutes from HealthKit/WHOOP, if available.
    public let totalSleepMinutes: Double?
    /// Deep sleep minutes, if available.
    public let deepSleepMinutes: Double?

    public init(
        intervalMinutes: Double? = nil,
        dose2Skipped: Bool = false,
        dose1Taken: Bool = false,
        dose2Taken: Bool = false,
        checkInCompleted: Bool = false,
        lightsOutLogged: Bool = false,
        wakeFinalLogged: Bool = false,
        totalSleepMinutes: Double? = nil,
        deepSleepMinutes: Double? = nil
    ) {
        self.intervalMinutes = intervalMinutes
        self.dose2Skipped = dose2Skipped
        self.dose1Taken = dose1Taken
        self.dose2Taken = dose2Taken
        self.checkInCompleted = checkInCompleted
        self.lightsOutLogged = lightsOutLogged
        self.wakeFinalLogged = wakeFinalLogged
        self.totalSleepMinutes = totalSleepMinutes
        self.deepSleepMinutes = deepSleepMinutes
    }
}

// MARK: - Night Score Result

/// Breakdown of how the night score was calculated.
public struct NightScoreResult: Sendable, Equatable {
    /// Overall score 0-100.
    public let score: Int
    /// Human-readable label for the score ("Excellent", "Good", "Fair", "Needs Work").
    public let label: String
    /// Individual component scores (0.0-1.0 each) for transparency.
    public let components: Components

    public struct Components: Sendable, Equatable {
        /// 0.0-1.0: How close the interval was to the 165m target.
        public let intervalAccuracy: Double
        /// 0.0-1.0: Were both doses taken? Was dose 2 skipped vs. missed?
        public let doseCompleteness: Double
        /// 0.0-1.0: Were key events logged? (lights_out, wake_final, check-in)
        public let sessionCompleteness: Double
        /// 0.0-1.0: Sleep quality metrics (totalSleep, deepSleep). Nil if no data.
        public let sleepQuality: Double?
    }
}

// MARK: - Calculator

/// Pure-function calculator for night quality scores.
///
/// Design: deterministic, no side effects, no I/O. Inject all data via ``NightScoreInput``.
/// All weights and thresholds are exposed as static constants for testability.
public enum NightScoreCalculator {

    // MARK: Weights (must sum to 1.0 when sleep data is available; re-normalised otherwise)

    /// Weight for dose interval accuracy.
    public static let intervalWeight: Double = 0.40
    /// Weight for dose completeness (both doses taken).
    public static let doseWeight: Double = 0.25
    /// Weight for session completeness (events logged, check-in done).
    public static let sessionWeight: Double = 0.20
    /// Weight for sleep quality (from HealthKit/WHOOP). Redistributed when absent.
    public static let sleepWeight: Double = 0.15

    // MARK: Thresholds

    /// Ideal dose 2 interval in minutes.
    public static let targetIntervalMin: Double = 165
    /// Minimum acceptable interval.
    public static let minIntervalMin: Double = 150
    /// Maximum acceptable interval.
    public static let maxIntervalMin: Double = 240
    /// Total sleep goal in minutes (7 hours).
    public static let sleepGoalMinutes: Double = 420
    /// Deep sleep goal in minutes (1.5 hours).
    public static let deepSleepGoalMinutes: Double = 90

    // MARK: Compute

    /// Calculate the night score from the given input.
    public static func calculate(_ input: NightScoreInput) -> NightScoreResult {
        let interval = intervalScore(input)
        let dose = doseScore(input)
        let session = sessionScore(input)
        let sleep = sleepScore(input)

        let raw: Double
        if let sleepVal = sleep {
            raw = interval * intervalWeight
                + dose * doseWeight
                + session * sessionWeight
                + sleepVal * sleepWeight
        } else {
            // Redistribute sleep weight proportionally among the other three.
            let total = intervalWeight + doseWeight + sessionWeight
            raw = interval * (intervalWeight / total)
                + dose * (doseWeight / total)
                + session * (sessionWeight / total)
        }

        let score = clampScore(raw)

        return NightScoreResult(
            score: score,
            label: label(for: score),
            components: .init(
                intervalAccuracy: interval,
                doseCompleteness: dose,
                sessionCompleteness: session,
                sleepQuality: sleep
            )
        )
    }

    // MARK: - Component Scorers (internal for testing)

    /// 0.0-1.0 score for how close the interval is to the target.
    static func intervalScore(_ input: NightScoreInput) -> Double {
        guard let interval = input.intervalMinutes else {
            // No interval means dose 2 not taken.
            return input.dose2Skipped ? 0.3 : 0.0 // Skipping intentionally is slightly better than missing.
        }
        guard interval >= minIntervalMin && interval <= maxIntervalMin else {
            // Out of window entirely.
            return 0.1
        }
        // Linear falloff from 1.0 at target to 0.5 at window edges.
        let deviation = abs(interval - targetIntervalMin)
        let maxDeviation = max(targetIntervalMin - minIntervalMin, maxIntervalMin - targetIntervalMin) // 75m
        let normalized = 1.0 - (deviation / maxDeviation) * 0.5
        return max(0.0, min(1.0, normalized))
    }

    /// 0.0-1.0 score for dose completeness.
    static func doseScore(_ input: NightScoreInput) -> Double {
        if input.dose1Taken && input.dose2Taken { return 1.0 }
        if input.dose1Taken && input.dose2Skipped { return 0.5 }
        if input.dose1Taken { return 0.3 } // dose 2 missed
        return 0.0 // no dose 1
    }

    /// 0.0-1.0 score for session completeness (events + check-in).
    static func sessionScore(_ input: NightScoreInput) -> Double {
        var score = 0.0
        if input.lightsOutLogged { score += 0.30 }
        if input.wakeFinalLogged { score += 0.30 }
        if input.checkInCompleted { score += 0.40 }
        return score
    }

    /// Optional 0.0-1.0 score for sleep quality. `nil` when no data is available.
    static func sleepScore(_ input: NightScoreInput) -> Double? {
        guard let total = input.totalSleepMinutes else { return nil }
        let totalRatio = min(total / sleepGoalMinutes, 1.0) // cap at 1.0
        if let deep = input.deepSleepMinutes {
            let deepRatio = min(deep / deepSleepGoalMinutes, 1.0)
            return totalRatio * 0.6 + deepRatio * 0.4
        }
        return totalRatio
    }

    // MARK: Helpers

    private static func clampScore(_ raw: Double) -> Int {
        max(0, min(100, Int((raw * 100).rounded())))
    }

    private static func label(for score: Int) -> String {
        switch score {
        case 85...100: return "Excellent"
        case 70..<85:  return "Good"
        case 50..<70:  return "Fair"
        default:       return "Needs Work"
        }
    }
}
