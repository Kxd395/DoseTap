import Foundation

/// Frozen descriptive context produced by a shared domain projection for this report period.
/// It is not a numeric observation and cannot enter metric denominators or clinical scores.
public struct PhysicianReportContext: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let lines: [String]
    public let source: String
    public let definitionVersion: String
    public let recordIDs: [String]
    public init(id: String, title: String, lines: [String], source: String, definitionVersion: String, recordIDs: [String]) throws {
        self.id = id; self.title = title; self.lines = lines; self.source = source
        self.definitionVersion = definitionVersion; self.recordIDs = recordIDs
        try validate()
    }
    public func validate() throws {
        guard [id, title, source, definitionVersion].allSatisfy({ !$0.isEmpty && $0.count <= 300 }),
              lines.count <= 10000, lines.allSatisfy({ $0.count <= 4000 }),
              recordIDs.allSatisfy({ !$0.isEmpty && $0.count <= 300 }) else { throw PhysicianReviewError.invalidText }
    }
}

public struct PhysicianMonthCoverage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { month }
    public let month: String
    public let start: Date
    public let endExclusive: Date
    public let calendarDayCount: Int
    public let observationCount: Int
    public let observationDays: Int
    public var description: String {
        "\(month): \(calendarDayCount) calendar days; \(observationCount) dated source rows on \(observationDays) dates." +
            (observationCount == 0 ? " No observations recorded. Missing information is not a zero metric." : " Source rows are not independent episodes or fully assessed days.")
    }
}

public extension PhysicianReportSnapshot {
    /// Calendar coverage is independent of metric eligibility and includes empty months.
    var monthlyCoverage: [PhysicianMonthCoverage] {
        guard let zone = TimeZone(identifier: period.timeZoneIdentifier), (try? period.validate()) != nil else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"
        let dated = observations.compactMap(\.observedAt).filter(period.contains)
        let grouped = Dictionary(grouping: dated, by: formatter.string)
        var cursor = period.start, result: [PhysicianMonthCoverage] = []
        while cursor < period.endExclusive, let month = calendar.dateInterval(of: .month, for: cursor) {
            let end = min(month.end, period.endExclusive), key = formatter.string(from: cursor), dates = grouped[key] ?? []
            let last = Date(timeIntervalSince1970: end.timeIntervalSince1970.nextDown)
            let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: cursor), to: calendar.startOfDay(for: last)).day ?? -1) + 1
            result.append(.init(month: key, start: cursor, endExclusive: end, calendarDayCount: days,
                observationCount: dates.count, observationDays: Set(dates.map(calendar.startOfDay)).count))
            guard end > cursor else { break }; cursor = end
        }
        return result
    }

    /// Summary cells never invent an eligible observation or metric value for an empty calendar month.
    var summaryCSV: String {
        let formatter = ISO8601DateFormatter()
        let header = ["snapshot_id", "format_version", "period_start", "period_end_exclusive", "timezone", "row_type", "month", "metric", "unit", "source", "definition_version", "calendar_days", "dates_represented", "eligible_observations", "available_observations", "partial_observations", "unavailable_observations", "review_observations", "not_applicable", "not_collected", "unplaced", "median", "lower_quartile", "upper_quartile", "source_rows", "detail", "included_partial_observations", "include_partial_metrics", "comparison_label"]
        let prefix = [id.uuidString, version, formatter.string(from: period.start), formatter.string(from: period.endExclusive), period.timeZoneIdentifier]
        var rows = [header]
        for value in summaries + monthlySummaries {
            rows.append(prefix + [value.month == nil ? "full_period_metric" : "monthly_metric", value.month ?? "", value.metricID,
                value.unit, value.source, value.definitionVersion, String(value.calendarDayCount), String(value.assessedDays),
                String(value.eligibleCount), String(value.availableCount), String(value.partialCount), String(value.unavailableCount),
                String(value.reviewCount), String(value.notApplicableCount), String(value.notCollectedCount), String(value.unplacedCount),
                value.median.map { String($0) } ?? "", value.lowerQuartile.map { String($0) } ?? "",
                value.upperQuartile.map { String($0) } ?? "", "", includePartialMetrics == true ? "Available and explicitly included finite dated partial values contribute." : "Only available values contribute.",
                String(value.includedPartialCount ?? 0), includePartialMetrics == true ? "yes" : "no", value.comparisonLabel ?? ""])
        }
        for coverage in monthlyCoverage {
            var row = Array(repeating: "", count: header.count)
            for (index, value) in prefix.enumerated() { row[index] = value }
            row[5] = "calendar_coverage"; row[6] = coverage.month; row[11] = String(coverage.calendarDayCount)
            row[12] = String(coverage.observationDays); row[24] = String(coverage.observationCount); row[25] = coverage.description
            row[27] = includePartialMetrics == true ? "yes" : "no"
            rows.append(row)
        }
        for context in contexts ?? [] {
            var row = Array(repeating: "", count: header.count)
            for (index, value) in prefix.enumerated() { row[index] = value }
            row[5] = "descriptive_context"; row[7] = context.title; row[9] = context.source; row[10] = context.definitionVersion
            row[25] = context.lines.joined(separator: "\n") + "\nSource records: " + context.recordIDs.joined(separator: " | ")
            row[27] = includePartialMetrics == true ? "yes" : "no"
            rows.append(row)
        }
        return rows.map(ReportCSV.row).joined(separator: "\r\n") + "\r\n"
    }
}
