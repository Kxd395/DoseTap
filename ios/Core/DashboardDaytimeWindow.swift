import Foundation

/// Exact observation bounds, independent of overnight treatment-date membership.
public struct DashboardDaytimeWindow: Equatable, Sendable {
    public let range: DashboardReportingRange
    public let start: Date?
    public let endExclusive: Date
    public let asOf: Date
    public let timeZone: TimeZone
    public let calendarDayCount: Int
    public var isEmpty: Bool { start.map { $0 >= endExclusive } ?? true }

    public func contains(_ instant: Date) -> Bool {
        guard let start, instant.timeIntervalSince1970.isFinite else { return false }
        return instant >= start && instant < endExclusive
    }
}

extension DashboardReportingRange {
    public func daytimeWindow(asOf: Date, timeZone: TimeZone,
                              reviewedPeriod: PhysicianReportPeriod? = nil,
                              earliestEvidenceAt: Date? = nil) throws -> DashboardDaytimeWindow {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        func supported(_ instant: Date) -> Bool {
            guard instant.timeIntervalSince1970.isFinite else { return false }
            let fields = calendar.dateComponents([.era, .year], from: instant)
            return fields.era == 1 && fields.year.map { (1...9999).contains($0) } == true
        }
        guard supported(asOf) else { throw PhysicianReviewError.invalidDate }
        let today = calendar.startOfDay(for: asOf)
        var start: Date?, end = asOf
        switch self {
        case .custom, .sinceCompletedVisit:
            guard let period = reviewedPeriod, period.version == PhysicianReportPeriod.definitionVersion,
                  period.capturedAt == asOf, period.timeZoneIdentifier == timeZone.identifier,
                  supported(period.start), supported(period.endExclusive),
                  period.start < period.endExclusive, period.endExclusive <= asOf,
                  (self == .sinceCompletedVisit) == (period.completedVisitID != nil) else {
                throw PhysicianReviewError.invalidPeriod
            }
            start = period.start; end = period.endExclusive
        case .all:
            guard reviewedPeriod == nil else { throw PhysicianReviewError.invalidPeriod }
            if let earliestEvidenceAt {
                guard supported(earliestEvidenceAt), earliestEvidenceAt <= asOf else {
                    throw PhysicianReviewError.invalidDate
                }
                start = earliestEvidenceAt
            }
        default:
            guard reviewedPeriod == nil else { throw PhysicianReviewError.invalidPeriod }
            let component: Calendar.Component, offset: Int
            switch self {
            case .week: component = .day; offset = -6
            case .twoWeeks: component = .day; offset = -13
            case .fourWeeks: component = .day; offset = -27
            case .month: component = .day; offset = -29
            case .quarter: component = .day; offset = -89
            case .sixMonths: component = .month; offset = -6
            case .year: component = .month; offset = -12
            case .all, .custom, .sinceCompletedVisit: throw PhysicianReviewError.invalidPeriod
            }
            guard let lower = calendar.date(byAdding: component, value: offset, to: today), supported(lower) else {
                throw PhysicianReviewError.invalidDate
            }
            start = lower
        }
        var dayCount = 0
        if let start {
            guard supported(start), start <= end,
                  let distance = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                                        to: calendar.startOfDay(for: end)).day else {
                throw PhysicianReviewError.invalidPeriod
            }
            if start < end { dayCount = distance + (end == calendar.startOfDay(for: end) ? 0 : 1) }
            guard dayCount >= 0 else { throw PhysicianReviewError.invalidPeriod }
        }
        if let period = reviewedPeriod {
            guard dayCount == period.calendarDayCount, dayCount > 0, dayCount <= 36600 else {
                throw PhysicianReviewError.invalidPeriod
            }
        }
        return DashboardDaytimeWindow(range: self, start: start, endExclusive: end,
                                      asOf: asOf, timeZone: timeZone, calendarDayCount: dayCount)
    }
}
