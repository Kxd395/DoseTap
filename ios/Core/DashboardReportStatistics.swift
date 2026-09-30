import Foundation

/// Descriptive occurrence-time statistics only. No historical regimen inference.
public struct DashboardReportStatistics: Sendable {
    public struct Month: Identifiable, Sendable {
        public var id: String { key }
        public let key: String
        public let count: Int
        public let median: Double
    }
    public struct Bucket: Identifiable, Sendable {
        public var id: Int { hour }
        public let hour: Int
        public let count: Int
        public var label: String { hour == 6 ? "6h+" : "\(hour)–\(hour + 1)h" }
    }
    public let days: [DashboardReportDoseDay]
    public let values: [Double]
    public var mean: Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    public var median: Double? { percentile(0.5) }
    public var lowerQuartile: Double? { percentile(0.25) }
    public var upperQuartile: Double? { percentile(0.75) }
    public var minimum: Double? { values.first }
    public var maximum: Double? { values.last }
    public func count(_ state: DashboardDoseDayState) -> Int { days.filter { $0.state == state }.count }
    public init(days: [DashboardReportDoseDay]) {
        self.days = days.sorted { $0.treatmentDate > $1.treatmentDate }
        values = days.filter { $0.state == .paired }.compactMap(\.intervalMinutes)
            .filter { $0.isFinite && $0 > 0 }.sorted()
    }
    /// Inclusive, linearly interpolated quantiles: position = p * (n - 1).
    private func percentile(_ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let position = p * Double(values.count - 1), low = Int(position)
        let high = min(low + 1, values.count - 1)
        return values[low] + (values[high] - values[low]) * (position - Double(low))
    }
    public var months: [Month] {
        let groups = Dictionary(grouping: days.filter { $0.state == .paired && $0.intervalMinutes != nil },
                                by: { String($0.treatmentDate.prefix(7)) })
        return groups.keys.sorted().compactMap { key in
            let stats = Self(days: groups[key]!)
            guard let median = stats.median else { return nil }
            return Month(key: key, count: stats.values.count, median: median)
        }
    }
    public var distribution: [Bucket] {
        (0...6).map { hour in
            Bucket(hour: hour, count: values.filter { min(6, Int(min($0 / 60, 6))) == hour }.count)
        }
    }
    public static func selected(_ days: [DashboardReportDoseDay], range: DashboardReportingRange,
                                capturedAt: Date, timeZone: TimeZone) -> [DashboardReportDoseDay] {
        guard let window = range.window(asOf: capturedAt, timeZone: timeZone) else { return [] }
        return days.filter { window.contains($0.treatmentDate) }
    }

    /// Anchor the frozen report at capture, using the same 18:00 rule as phone.
    /// Timezone is explicit because the v1 envelope does not carry a source zone.
    public static func selected(_ days: [DashboardReportDoseDay], count: Int,
                                capturedAt: Date, timeZone: TimeZone) -> [DashboardReportDoseDay] {
        let last = sessionKey(for: capturedAt, timeZone: timeZone, rolloverHour: 18)
        guard count > 0 else { return days.filter { $0.treatmentDate <= last } }
        let format = DateFormatter(); format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "yyyy-MM-dd"
        guard let end = format.date(from: last) else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: end) else { return [] }
        let first = format.string(from: start)
        return days.filter { $0.treatmentDate >= first && $0.treatmentDate <= last }
    }
}
