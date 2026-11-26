import Foundation

/// Civil treatment-date membership; independent of provider measurements and row identity.
public enum DashboardReportingRange: String, CaseIterable, Identifiable, Sendable {
    case week = "7D", twoWeeks = "14D", fourWeeks = "28D", month = "30D", quarter = "90D"
    case sixMonths = "6M", year = "1Y", all = "All"
    case custom = "Custom", sinceCompletedVisit = "Since visit"
    public var id: String { rawValue }
    public static var presetCases: [Self] { allCases.filter { $0 != .custom && $0 != .sinceCompletedVisit } }

    public var label: String {
        switch self {
        case .week: return "7 Days"
        case .twoWeeks: return "14 Days"
        case .fourWeeks: return "28 Days"
        case .month: return "30 Days"
        case .quarter: return "90 Days"
        case .sixMonths: return "6 Months"
        case .year: return "12 Months"
        case .all: return "All Time"
        case .custom: return "Custom period"
        case .sinceCompletedVisit: return "Since last completed visit"
        }
    }

    public func window(asOf: Date, timeZone: TimeZone, reviewedPeriod: PhysicianReportPeriod? = nil) -> DashboardReportingWindow? {
        if self == .custom || self == .sinceCompletedVisit {
            return reviewedWindow(asOf: asOf, timeZone: timeZone, period: reviewedPeriod)
        }
        guard asOf.timeIntervalSince1970.isFinite else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        func supported(_ date: Date) -> Bool {
            let fields = calendar.dateComponents([.era, .year], from: date)
            return fields.era == 1 && fields.year.map { (1...9999).contains($0) } == true
        }
        guard supported(asOf) else { return nil }
        let today = calendar.startOfDay(for: asOf)
        guard let anchor = calendar.date(byAdding: .day, value: calendar.component(.hour, from: asOf) < 18 ? -1 : 0, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: anchor) else { return nil }
        let unit: Calendar.Component
        let count: Int
        switch self {
        case .week: unit = .day; count = 7
        case .twoWeeks: unit = .day; count = 14
        case .fourWeeks: unit = .day; count = 28
        case .month: unit = .day; count = 30
        case .quarter: unit = .day; count = 90
        case .sixMonths: unit = .month; count = 6
        case .year: unit = .month; count = 12
        case .all: unit = .day; count = 0
        case .custom, .sinceCompletedVisit: return nil
        }
        guard let lower = calendar.date(byAdding: unit, value: -count, to: end),
              let preceding = calendar.date(byAdding: unit, value: -count, to: lower),
              let totalDays = calendar.dateComponents([.day], from: preceding, to: end).day else { return nil }
        let queryDays = self == .all ? 730 : min(730, totalDays + 2)
        guard let queryStart = calendar.date(byAdding: .day, value: -queryDays, to: asOf),
              let firstQueriedNight = calendar.date(byAdding: .day, value: -(queryDays - 1), to: anchor) else { return nil }
        guard [anchor, end, lower, preceding, queryStart, firstQueriedNight].allSatisfy(supported),
              self == .all || (preceding < lower && lower < end) else { return nil }
        let formatter = DateFormatter(); formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let lastKey = formatter.string(from: anchor)
        guard DashboardReportingWindow.isValidDateKey(lastKey) else { return nil }
        return DashboardReportingWindow(range: self, asOf: asOf, timeZone: timeZone,
            start: self == .all ? nil : lower, endExclusive: end,
            priorStart: self == .all ? nil : preceding,
            firstTreatmentDate: self == .all ? nil : formatter.string(from: lower),
            lastTreatmentDate: lastKey,
            priorFirstTreatmentDate: self == .all ? nil : formatter.string(from: preceding),
            healthQueryDays: queryDays, healthQueryStart: queryStart,
            healthFirstTreatmentDate: formatter.string(from: firstQueriedNight), reviewedPeriod: nil)
    }

    private func reviewedWindow(asOf: Date, timeZone: TimeZone, period: PhysicianReportPeriod?) -> DashboardReportingWindow? {
        guard let period, period.version == PhysicianReportPeriod.definitionVersion,
              period.capturedAt == asOf, period.timeZoneIdentifier == timeZone.identifier,
              [asOf, period.start, period.endExclusive].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              period.start < period.endExclusive, period.endExclusive <= asOf,
              (self == .sinceCompletedVisit) == (period.completedVisitID != nil) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        func treatmentDay(_ instant: Date) -> Date? {
            calendar.date(byAdding: .day, value: calendar.component(.hour, from: instant) < 18 ? -1 : 0,
                          to: calendar.startOfDay(for: instant))
        }
        let lastInstant = Date(timeIntervalSince1970: period.endExclusive.timeIntervalSince1970.nextDown)
        guard let lower = treatmentDay(period.start), let last = treatmentDay(lastInstant),
              let end = calendar.date(byAdding: .day, value: 1, to: last),
              let totalDays = calendar.dateComponents([.day], from: lower, to: end).day,
              totalDays > 0, totalDays < 36600 else { return nil }
        guard [lower, last, end].allSatisfy({
            let fields = calendar.dateComponents([.era, .year], from: $0)
            return fields.era == 1 && fields.year.map { (1...9999).contains($0) } == true
        }) else { return nil }
        let count = min(730, totalDays)
        guard let firstQueried = calendar.date(byAdding: .day, value: -(count - 1), to: last),
              let queryStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: firstQueried) else { return nil }
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let firstKey = formatter.string(from: lower), lastKey = formatter.string(from: last)
        guard DashboardReportingWindow.isValidDateKey(firstKey), DashboardReportingWindow.isValidDateKey(lastKey) else { return nil }
        return DashboardReportingWindow(range: self, asOf: asOf, timeZone: timeZone, start: lower,
            endExclusive: end, priorStart: nil, firstTreatmentDate: firstKey, lastTreatmentDate: lastKey,
            priorFirstTreatmentDate: nil, healthQueryDays: count, healthQueryStart: queryStart,
            healthFirstTreatmentDate: formatter.string(from: firstQueried), reviewedPeriod: period)
    }
}

public struct DashboardReportingWindow: Equatable, Sendable {
    public let range: DashboardReportingRange
    public let asOf: Date
    public let timeZone: TimeZone
    public let start: Date?
    public let endExclusive: Date
    public let priorStart: Date?
    public let firstTreatmentDate: String?
    public let lastTreatmentDate: String
    public let priorFirstTreatmentDate: String?
    public let healthQueryDays: Int
    public let healthQueryStart: Date
    public let healthFirstTreatmentDate: String
    public let reviewedPeriod: PhysicianReportPeriod?
    public var healthQueryEnd: Date { reviewedPeriod?.endExclusive ?? asOf }
    public var healthQueryTruncatesSelectedPeriod: Bool {
        firstTreatmentDate.map { healthFirstTreatmentDate > $0 } ?? false
    }

    /// The summary query enumerates at most 730 treatment nights, even in leap years.
    public var healthQueryTruncatesPriorPeriod: Bool {
        priorFirstTreatmentDate.map { healthFirstTreatmentDate > $0 } ?? false
    }

    public func contains(_ treatmentDate: String, prior: Bool = false) -> Bool {
        guard Self.isValidDateKey(treatmentDate) else { return false }
        if prior {
            guard let first = priorFirstTreatmentDate, let end = firstTreatmentDate else { return false }
            return treatmentDate >= first && treatmentDate < end
        }
        return treatmentDate <= lastTreatmentDate && firstTreatmentDate.map { treatmentDate >= $0 } != false
    }

    /// Strict ASCII Gregorian dates; no lenient parser normalization or time-zone conversion.
    static func isValidDateKey(_ key: String) -> Bool {
        let bytes = Array(key.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ [4, 7].contains($0.offset) || (48...57).contains($0.element) }),
              let year = Int(key.prefix(4)), year > 0,
              let month = Int(key.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(key.suffix(2)) else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...lengths[month - 1]).contains(day)
    }
}
