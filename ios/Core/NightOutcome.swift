import Foundation

public enum Dose2WakeKind: String, Codable, CaseIterable, Sendable {
    case natural, alarm, other, unknown
    public init(legacy: String?) {
        switch legacy {
        case "natural": self = .natural
        case "alarm", "alarm_then_snooze": self = .alarm
        case "already_awake", "external_interrupt", "other": self = .other
        default: self = .unknown
        }
    }
}

public enum FollowingDayKind: String, Codable, CaseIterable, Sendable {
    case workday, dayOff, unknown
}

/// Personal diary observations, never an instruction or medication event.
public struct NightOutcomeDiary: Codable, Equatable, Sendable {
    public var wakeMethod: Dose2WakeKind = .unknown
    public var backupAlarmSet: Bool?
    public var dayType: FollowingDayKind = .unknown
    public var finalWakeAt: Date?
    public var sleepiness: Int?
    public var assessedAt: Date?
    public init() {}

    public func validationError(now: Date) -> String? {
        if let sleepiness, !(0...10).contains(sleepiness) { return "Choose a sleepiness rating from 0 to 10." }
        if (sleepiness == nil) != (assessedAt == nil) { return "Save the assessment time with the sleepiness rating." }
        for date in [finalWakeAt, assessedAt].compactMap({ $0 }) {
            if !date.timeIntervalSince1970.isFinite || date > now { return "Observation times cannot be in the future." }
        }
        if let finalWakeAt, let assessedAt, assessedAt < finalWakeAt { return "Assess next-day sleepiness after final awakening." }
        return nil
    }

    /// Filling an unanswered field is a new observation; changing an answer is a correction.
    public func changesAnsweredFields(of old: Self) -> Bool {
        (old.wakeMethod != .unknown && wakeMethod != old.wakeMethod)
        || (old.backupAlarmSet != nil && backupAlarmSet != old.backupAlarmSet)
        || (old.dayType != .unknown && dayType != old.dayType)
        || (old.finalWakeAt != nil && finalWakeAt != old.finalWakeAt)
        || (old.sleepiness != nil && (sleepiness != old.sleepiness || assessedAt != old.assessedAt))
    }
}

public struct RecordedSleepInterval: Sendable {
    public let start: Date
    public let end: Date
    public let asleep: Bool
    public init(start: Date, end: Date, asleep: Bool) { self.start = start; self.end = end; self.asleep = asleep }
}

public struct PostDoseSleepEstimate: Sendable {
    public let asleepMinutes: Double
    public let coveredMinutes: Double
    public let intervalMinutes: Double
    public var hasCoverageGaps: Bool { coveredMinutes < intervalMinutes - 1.0 / 60 }

    /// Union overlapping samples, clip to the actual dose/final-wake interval,
    /// and let explicitly recorded awake intervals override overlapping asleep samples.
    /// Missing coverage remains missing; an all-awake recorded interval is a genuine zero.
    public static func calculate(dose2: Date, finalWake: Date, intervals: [RecordedSleepInterval]) -> Self? {
        let duration = finalWake.timeIntervalSince(dose2)
        guard duration.isFinite, duration > 0 else { return nil }
        let clipped = intervals.compactMap { sample -> (Double, Double, Bool)? in
            let rawStart = sample.start.timeIntervalSince(dose2), rawEnd = sample.end.timeIntervalSince(dose2)
            guard rawStart.isFinite, rawEnd.isFinite, rawEnd > rawStart else { return nil }
            let start = max(0, rawStart), end = min(duration, rawEnd)
            return end > start ? (start, end, sample.asleep) : nil
        }
        guard !clipped.isEmpty else { return nil }
        let boundaries = Set(clipped.flatMap { [$0.0, $0.1] }).sorted()
        var asleep = 0.0, covered = 0.0
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let active = clipped.filter { $0.0 < end && $0.1 > start }
            if !active.isEmpty { covered += end - start }
            if active.contains(where: { $0.2 }) && !active.contains(where: { !$0.2 }) { asleep += end - start }
        }
        return .init(asleepMinutes: asleep / 60, coveredMinutes: covered / 60, intervalMinutes: duration / 60)
    }
}

public struct DiaryMetricSummary: Sendable {
    public let count: Int
    public let median: Double?
    public let lowerQuartile: Double?
    public let upperQuartile: Double?
    /// Linear-interpolated quantiles (R-7); each metric supplies its own usable observations.
    public init(_ observations: [Double?]) {
        let values = observations.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }.sorted()
        count = values.count
        func quantile(_ probability: Double) -> Double? {
            guard !values.isEmpty else { return nil }
            let position = Double(values.count - 1) * probability
            let lower = Int(position), upper = min(lower + 1, values.count - 1)
            return values[lower] + (values[upper] - values[lower]) * (position - Double(lower))
        }
        median = quantile(0.5); lowerQuartile = quantile(0.25); upperQuartile = quantile(0.75)
    }
}
