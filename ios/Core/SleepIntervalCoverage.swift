import Foundation

/// Recorded coverage inside explicit absolute bounds, not a sleep-session selector.
/// Callers resolve provider/source conflicts before supplying measured intervals.
public struct SleepIntervalCoverage: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case available, partial, unavailable
    }

    public let derivationVersion: String
    public let start: Date
    public let end: Date
    public let asleepMinutes: Double?
    public let awakeMinutes: Double?
    public let coveredMinutes: Double
    public let unmeasuredMinutes: Double
    public let intervalMinutes: Double
    public let status: Status
    public var coveragePercent: Double { coveredMinutes / intervalMinutes * 100 }

    /// Clips and unions all eligible intervals. Explicit awake evidence wins over
    /// overlapping asleep evidence, matching the existing post-dose calculation.
    /// No observations means unavailable, not an observed zero minutes asleep.
    public static func calculate(start: Date, end: Date, intervals: [RecordedSleepInterval]) -> Self? {
        let duration = end.timeIntervalSince(start)
        guard start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite,
              duration.isFinite, duration > 0 else { return nil }

        let clipped = intervals.compactMap { sample -> (start: Double, end: Double, asleep: Bool)? in
            let lower = sample.start.timeIntervalSince(start)
            let upper = sample.end.timeIntervalSince(start)
            guard lower.isFinite, upper.isFinite, upper > lower else { return nil }
            let clippedStart = max(0, lower), clippedEnd = min(duration, upper)
            return clippedEnd > clippedStart ? (clippedStart, clippedEnd, sample.asleep) : nil
        }
        let boundaries = Set([0, duration] + clipped.flatMap { [$0.start, $0.end] }).sorted()
        var asleep = 0.0, awake = 0.0, unmeasured = 0.0
        for (lower, upper) in zip(boundaries, boundaries.dropFirst()) {
            let active = clipped.filter { $0.start < upper && $0.end > lower }
            let seconds = upper - lower
            if active.contains(where: { !$0.asleep }) {
                awake += seconds
            } else if !active.isEmpty {
                asleep += seconds
            } else {
                unmeasured += seconds
            }
        }
        let covered = asleep + awake
        let status: Status = covered == 0 ? .unavailable : (unmeasured > 0 ? .partial : .available)
        return .init(
            derivationVersion: "recorded_interval_coverage_v1", start: start, end: end,
            asleepMinutes: covered > 0 ? asleep / 60 : nil,
            awakeMinutes: covered > 0 ? awake / 60 : nil,
            coveredMinutes: covered / 60, unmeasuredMinutes: unmeasured / 60,
            intervalMinutes: duration / 60, status: status
        )
    }
}
