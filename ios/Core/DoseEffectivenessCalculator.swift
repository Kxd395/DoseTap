import Foundation

// MARK: - Input / Output Models

/// A single night's data point for dose-effectiveness analysis.
/// The caller maps from ``UnifiedSleepSession`` into this lightweight struct.
public struct DoseEffectivenessDataPoint: Sendable, Equatable {
    /// Date of the session (for chart labeling).
    public let date: Date
    /// Dose 1 → Dose 2 interval in minutes. `nil` if dose 2 not taken/skipped.
    public let intervalMinutes: Double?
    /// Whether dose 2 was skipped intentionally.
    public let dose2Skipped: Bool
    /// Total sleep in minutes (from HealthKit or WHOOP). `nil` if unavailable.
    public let totalSleepMinutes: Double?
    /// Deep sleep in minutes. `nil` if unavailable.
    public let deepSleepMinutes: Double?
    /// WHOOP recovery score 0-100. `nil` if unavailable.
    public let recoveryScore: Int?
    /// Average HRV in ms. `nil` if unavailable.
    public let averageHRV: Double?
    /// Number of awakenings during the night.
    public let awakenings: Int?

    public init(
        date: Date,
        intervalMinutes: Double? = nil,
        dose2Skipped: Bool = false,
        totalSleepMinutes: Double? = nil,
        deepSleepMinutes: Double? = nil,
        recoveryScore: Int? = nil,
        averageHRV: Double? = nil,
        awakenings: Int? = nil
    ) {
        self.date = date
        self.intervalMinutes = intervalMinutes
        self.dose2Skipped = dose2Skipped
        self.totalSleepMinutes = totalSleepMinutes
        self.deepSleepMinutes = deepSleepMinutes
        self.recoveryScore = recoveryScore
        self.averageHRV = averageHRV
        self.awakenings = awakenings
    }
}

/// Result of dose-effectiveness analysis across multiple nights.
public struct DoseEffectivenessReport: Sendable, Equatable {
    /// Summary statistics for nights in the optimal window (150-165m).
    public let optimalZone: ZoneSummary
    /// Summary statistics for nights in the acceptable window (166-240m).
    public let acceptableZone: ZoneSummary
    /// Summary statistics for non-compliant nights (dose 2 skipped, <150m, or >240m).
    public let nonCompliant: ZoneSummary
    /// Total nights analyzed.
    public let totalNights: Int
    /// Nights with both interval and at least one sleep quality metric.
    public let pairableNights: Int
    /// Overall compliance rate (nights with dose 2 in 150-240m / total nights).
    public let complianceRate: Double
    /// Trend: average interval over the most recent 7 nights vs prior 7.
    public let recentTrend: Trend?

    /// Summary for a single timing zone.
    public struct ZoneSummary: Sendable, Equatable {
        public let count: Int
        public let averageInterval: Double?
        public let averageTotalSleep: Double?
        public let averageDeepSleep: Double?
        public let averageRecovery: Double?
        public let averageHRV: Double?
        public let averageAwakenings: Double?
    }

    /// Direction of recent dose-interval change.
    public enum Trend: Sendable, Equatable {
        /// Recent interval is shorter (trending toward target).
        case improving(delta: Double)
        /// Recent interval is longer (trending away from target).
        case worsening(delta: Double)
        /// Within ±3 minutes — stable.
        case stable
    }
}

// MARK: - Interval Formatting

/// User-selectable format for displaying dose intervals.
///
/// Usage:
/// ```swift
/// let fmt = IntervalFormat.hoursMinutes
/// fmt.string(from: 165)  // "2:45"
/// fmt.string(from: 90)   // "1:30"
///
/// let fmt2 = IntervalFormat.minutes
/// fmt2.string(from: 165) // "165m"
/// ```
public enum IntervalFormat: String, Sendable, CaseIterable, Codable {
    /// Display as raw minutes, e.g. "165m"
    case minutes = "mm"
    /// Display as hours:minutes, e.g. "2:45"
    case hoursMinutes = "h:mm"

    /// Format an interval value (in minutes) to a display string.
    /// Returns "—" for `nil`.
    public func string(from intervalMinutes: Double?) -> String {
        guard let m = intervalMinutes else { return "—" }
        switch self {
        case .minutes:
            // Drop decimals when whole, otherwise show 1 decimal
            if m.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(m))m"
            }
            return String(format: "%.1fm", m)
        case .hoursMinutes:
            let totalMinutes = Int(m.rounded())
            let h = totalMinutes / 60
            let min = totalMinutes % 60
            return "\(h):\(String(format: "%02d", min))"
        }
    }

    /// Human-readable label for settings UI.
    public var displayName: String {
        switch self {
        case .minutes: return "Minutes (165m)"
        case .hoursMinutes: return "Hours:Minutes (2:45)"
        }
    }
}

// MARK: - Report Formatting Extension

extension DoseEffectivenessReport.ZoneSummary {
    /// The average interval formatted with the given format.
    public func formattedAverageInterval(_ format: IntervalFormat) -> String {
        format.string(from: averageInterval)
    }
}

// MARK: - Calculator

/// Pure-function analytics: given a set of nights, produces a ``DoseEffectivenessReport``.
///
/// Design principles:
/// - Deterministic, no side effects, no I/O.
/// - Tolerates partial data: a night with no sleep metrics still counts for compliance.
/// - Zone boundaries match SSOT: optimal = 150-165m, acceptable = 166-240m.
public enum DoseEffectivenessCalculator {

    // MARK: Zone Boundaries (match SSOT)

    /// Lower bound of the dose window.
    public static let windowMin: Double = 150
    /// Upper end of the "optimal" zone.
    public static let optimalMax: Double = 165
    /// Upper bound of the dose window.
    public static let windowMax: Double = 240
    /// Trend stability threshold in minutes.
    public static let trendStableThreshold: Double = 3

    // MARK: Public API

    /// Analyze a collection of nights and return the effectiveness report.
    /// - Parameter nights: Unordered collection of data points (will be sorted internally).
    /// - Returns: ``DoseEffectivenessReport`` summarising zone stats, compliance, and trend.
    public static func analyze(_ nights: [DoseEffectivenessDataPoint]) -> DoseEffectivenessReport {
        guard !nights.isEmpty else { return emptyReport }

        let sorted = nights.sorted { $0.date < $1.date }

        // Partition into zones
        var optimal: [DoseEffectivenessDataPoint] = []
        var acceptable: [DoseEffectivenessDataPoint] = []
        var nonCompliant: [DoseEffectivenessDataPoint] = []

        for night in sorted {
            guard let iv = night.intervalMinutes, !night.dose2Skipped else {
                nonCompliant.append(night)
                continue
            }
            switch iv {
            case windowMin...optimalMax:
                optimal.append(night)
            case (optimalMax + 0.001)...windowMax:
                acceptable.append(night)
            default:
                nonCompliant.append(night)
            }
        }

        let compliant = optimal.count + acceptable.count
        let pairableCount = sorted.filter { $0.intervalMinutes != nil && hasSleepMetric($0) }.count

        return DoseEffectivenessReport(
            optimalZone: summarize(optimal),
            acceptableZone: summarize(acceptable),
            nonCompliant: summarize(nonCompliant),
            totalNights: sorted.count,
            pairableNights: pairableCount,
            complianceRate: Double(compliant) / Double(sorted.count),
            recentTrend: computeTrend(sorted)
        )
    }

    // MARK: Helpers

    private static func summarize(_ points: [DoseEffectivenessDataPoint]) -> DoseEffectivenessReport.ZoneSummary {
        guard !points.isEmpty else {
            return .init(count: 0, averageInterval: nil, averageTotalSleep: nil,
                         averageDeepSleep: nil, averageRecovery: nil,
                         averageHRV: nil, averageAwakenings: nil)
        }
        return .init(
            count: points.count,
            averageInterval: average(points.compactMap(\.intervalMinutes)),
            averageTotalSleep: average(points.compactMap(\.totalSleepMinutes)),
            averageDeepSleep: average(points.compactMap(\.deepSleepMinutes)),
            averageRecovery: average(points.compactMap(\.recoveryScore).map(Double.init)),
            averageHRV: average(points.compactMap(\.averageHRV)),
            averageAwakenings: average(points.compactMap(\.awakenings).map(Double.init))
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func hasSleepMetric(_ dp: DoseEffectivenessDataPoint) -> Bool {
        dp.totalSleepMinutes != nil || dp.deepSleepMinutes != nil ||
        dp.recoveryScore != nil || dp.averageHRV != nil
    }

    private static func computeTrend(_ sorted: [DoseEffectivenessDataPoint]) -> DoseEffectivenessReport.Trend? {
        // Need at least 4 nights to compare recent vs prior halves
        let withInterval = sorted.filter { $0.intervalMinutes != nil }
        guard withInterval.count >= 4 else { return nil }

        let midpoint = withInterval.count / 2
        let priorHalf = Array(withInterval.prefix(midpoint))
        let recentHalf = Array(withInterval.suffix(from: midpoint))

        guard let priorAvg = average(priorHalf.compactMap(\.intervalMinutes)),
              let recentAvg = average(recentHalf.compactMap(\.intervalMinutes)) else {
            return nil
        }

        let delta = recentAvg - priorAvg
        if abs(delta) <= trendStableThreshold {
            return .stable
        } else if delta < 0 {
            // Shorter interval = closer to 165m target (if coming from >165)
            return .improving(delta: abs(delta))
        } else {
            return .worsening(delta: delta)
        }
    }

    private static var emptyReport: DoseEffectivenessReport {
        .init(
            optimalZone: summarize([]),
            acceptableZone: summarize([]),
            nonCompliant: summarize([]),
            totalNights: 0,
            pairableNights: 0,
            complianceRate: 0,
            recentTrend: nil
        )
    }
}

// MARK: - Convenience: Map from UnifiedSleepSession

extension DoseEffectivenessDataPoint {
    /// Create a data point from a ``UnifiedSleepSession``.
    public init(session: UnifiedSleepSession) {
        self.init(
            date: session.date,
            intervalMinutes: session.doseData.intervalMinutes.map(Double.init),
            dose2Skipped: session.doseData.dose2Skipped,
            totalSleepMinutes: session.totalSleepDuration.map { $0 / 60.0 },
            deepSleepMinutes: session.healthData?.sleepStages.map { $0.deep / 60.0 },
            recoveryScore: session.whoopData?.recoveryScore,
            averageHRV: session.healthData?.averageHRV ?? session.whoopData?.hrv,
            awakenings: session.healthData.map(\.awakenings) ?? session.whoopData?.disturbances
        )
    }
}
