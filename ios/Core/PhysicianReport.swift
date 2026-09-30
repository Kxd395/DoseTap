import Foundation

public enum PhysicianMetricState: String, Codable, Sendable {
    case available, partial, unavailable, notApplicable, needsReview, notCollected
    public var label: String {
        switch self {
        case .available: return "Available"
        case .partial: return "Partially recorded"
        case .unavailable: return "Unavailable"
        case .notApplicable: return "Not applicable"
        case .needsReview: return "Needs review"
        case .notCollected: return "Not collected"
        }
    }
}

/// An already-derived observation. Reports never infer medication or sleep metrics.
public struct PhysicianReportObservation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let observedAt: Date?
    public let metricID: String
    public let value: Double?
    public let state: PhysicianMetricState
    public let unit: String
    public let source: String
    public let definitionVersion: String
    public let detail: String
    public let recordIDs: [String]
    public let requiresReview: Bool
    public let detailOnly: Bool?
    public let comparisonLabel: String?
    public init(id: String, observedAt: Date?, metricID: String, value: Double?, state: PhysicianMetricState,
                unit: String, source: String, definitionVersion: String, detail: String,
                recordIDs: [String], requiresReview: Bool = false, detailOnly: Bool = false, comparisonLabel: String? = nil) {
        self.id = id; self.observedAt = observedAt; self.metricID = metricID; self.value = value
        self.state = state; self.unit = unit; self.source = source; self.definitionVersion = definitionVersion
        self.detail = detail; self.recordIDs = recordIDs; self.requiresReview = requiresReview
        self.detailOnly = detailOnly ? true : nil; self.comparisonLabel = comparisonLabel
    }
    fileprivate var stratum: [String] { [metricID, unit, source, definitionVersion] }
}

public struct VisitPreparationNote: Codable, Equatable, Identifiable, Sendable {
    public enum Opportunity: String, Codable, CaseIterable, Sendable {
        case observed, noRecentOpportunity, avoidedOrStopped, uncertainRecollection, notCollected
        public var label: String {
            switch self {
            case .observed: return "Opportunity with observation"
            case .noRecentOpportunity: return "No recent opportunity"
            case .avoidedOrStopped: return "Activity avoided or stopped"
            case .uncertainRecollection: return "Uncertain recollection"
            case .notCollected: return "No information collected"
            }
        }
    }
    public let id: UUID
    public let activity: String
    public let opportunity: Opportunity
    public let comment: String
    public let evidenceIDs: [String]
    public let reviewedAt: Date
    public let selectedForSharing: Bool
    public init(id: UUID = UUID(), activity: String, opportunity: Opportunity, comment: String,
                evidenceIDs: [String], reviewedAt: Date, selectedForSharing: Bool) {
        self.id = id; self.activity = activity; self.opportunity = opportunity; self.comment = comment
        self.evidenceIDs = evidenceIDs; self.reviewedAt = reviewedAt; self.selectedForSharing = selectedForSharing
    }
}

public struct PhysicianMetricSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String { ([month ?? "full", metricID, unit, source, definitionVersion, comparisonLabel ?? ""]).joined(separator: " | ") }
    public let comparisonLabel: String?
    public let includedPartialCount: Int?
    public var numericContributionCount: Int { availableCount + (includedPartialCount ?? 0) }
    public let month: String?
    public let metricID: String
    public let unit: String
    public let source: String
    public let definitionVersion: String
    public let eligibleCount: Int
    public let availableCount: Int
    public let unavailableCount: Int
    public let partialCount: Int
    public let reviewCount: Int
    public let notApplicableCount: Int
    public let notCollectedCount: Int
    public let calendarDayCount: Int
    public let assessedDays: Int
    public let availableDays: Int
    public let unplacedCount: Int
    public let median: Double?
    public let lowerQuartile: Double?
    public let upperQuartile: Double?
}

public struct PhysicianReportSnapshot: Codable, Equatable, Identifiable, Sendable {
    public static let formatVersion = "physician-review.v1"
    public let id: UUID
    public let version: String
    public let period: PhysicianReportPeriod
    public let generatedAt: Date
    public let appVersion: String
    public let coverageDescription: String
    public let observations: [PhysicianReportObservation]
    public let notes: [VisitPreparationNote]
    public let questions: [String]
    public let contexts: [PhysicianReportContext]?
    public let includePartialMetrics: Bool?
    public let summaries: [PhysicianMetricSummary]
    public let monthlySummaries: [PhysicianMetricSummary]

    public init(period: PhysicianReportPeriod, observations: [PhysicianReportObservation],
                notes: [VisitPreparationNote], questions: [String], appVersion: String, generatedAt: Date, coverageDescription: String = "", contexts: [PhysicianReportContext] = [], includePartialMetrics: Bool = false) throws {
        try period.validate()
        guard generatedAt.timeIntervalSince1970.isFinite, generatedAt >= period.capturedAt,
              !appVersion.isEmpty, appVersion.count <= 100,
              Set(observations.map(\.id)).count == observations.count,
              Set(notes.map(\.id)).count == notes.count,
              questions.count <= 20, questions.allSatisfy({ $0.count <= 2000 }) else { throw PhysicianReviewError.invalidText }
        for value in observations {
            guard !value.id.isEmpty, value.stratum.allSatisfy({ !$0.isEmpty && $0.count <= 300 }),
                  value.value.map(\.isFinite) != false, value.comparisonLabel.map({ !$0.isEmpty && $0.count <= 2000 }) != false,
                  value.observedAt.map({ $0.timeIntervalSince1970.isFinite && $0 <= generatedAt }) != false,
                  value.state != .available || value.value != nil else { throw PhysicianReviewError.invalidText }
        }
        guard Set(contexts.map(\.id)).count == contexts.count else { throw PhysicianReviewError.invalidText }
        for context in contexts { try context.validate() }
        self.contexts = contexts.isEmpty ? nil : contexts
        self.includePartialMetrics = includePartialMetrics ? true : nil
        let selected = observations.filter { $0.observedAt.map(period.contains) ?? true }
        let evidence = Set(selected.map(\.id) + selected.flatMap(\.recordIDs))
        guard notes.allSatisfy({ Set($0.evidenceIDs).isSubset(of: evidence) && $0.activity.count <= 300 && $0.comment.count <= 4000 &&
            $0.reviewedAt.timeIntervalSince1970.isFinite && $0.reviewedAt <= generatedAt }) else { throw PhysicianReviewError.invalidText }
        id = UUID(); version = Self.formatVersion; self.period = period; self.generatedAt = generatedAt
        self.appVersion = appVersion; self.coverageDescription = coverageDescription
        // Unknown-time reports remain explicitly unplaced, not silently excluded.
        self.observations = selected.sorted {
            $0.observedAt == $1.observedAt ? $0.id < $1.id : ($0.observedAt ?? .distantPast) > ($1.observedAt ?? .distantPast)
        }
        self.notes = notes.filter(\.selectedForSharing); self.questions = questions
        summaries = Self.aggregate(self.observations, period: period, monthly: false, includePartial: includePartialMetrics)
        monthlySummaries = Self.aggregate(self.observations, period: period, monthly: true, includePartial: includePartialMetrics)
    }

    /// Revalidate decoded snapshots before rendering or re-exporting local/imported data.
    public func validate() throws {
        let checked = try Self(period: period, observations: observations, notes: notes, questions: questions,
                               appVersion: appVersion, generatedAt: generatedAt, coverageDescription: coverageDescription, contexts: contexts ?? [], includePartialMetrics: includePartialMetrics == true)
        guard version == Self.formatVersion, checked.observations == observations, checked.notes == notes,
              checked.contexts == contexts, checked.includePartialMetrics == includePartialMetrics, checked.summaries == summaries, checked.monthlySummaries == monthlySummaries else {
            throw PhysicianReviewError.invalidRevision
        }
    }
    public func recentDetail(days: Int) -> [PhysicianReportObservation] {
        guard [14, 28].contains(days), let zone = TimeZone(identifier: period.timeZoneIdentifier) else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let lastIncluded = Date(timeIntervalSince1970: period.endExclusive.timeIntervalSince1970.nextDown)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: lastIncluded)) else { return [] }
        return observations.filter { $0.observedAt.map { $0 >= max(period.start, start) } ?? false }
    }
    public func jsonData() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard var object = try JSONSerialization.jsonObject(with: encoder.encode(self)) as? [String: Any] else { throw PhysicianReviewError.invalidText }
        object["monthlyCoverage"] = try JSONSerialization.jsonObject(with: encoder.encode(monthlyCoverage))
        object["timestampEncoding"] = "seconds since 2001-01-01T00:00:00Z"
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
    public var detailCSV: String {
        let formatter = ISO8601DateFormatter()
        var rows = [["snapshot_id", "format_version", "period_start", "period_end_exclusive", "timezone", "observation_id", "observed_at", "metric", "value", "unit", "state", "source", "definition_version", "record_ids", "requires_review", "detail", "detail_only", "comparison_label", "include_partial_metrics"]]
        rows += observations.map { value in
            [id.uuidString, version, formatter.string(from: period.start), formatter.string(from: period.endExclusive),
             period.timeZoneIdentifier, value.id, value.observedAt.map(formatter.string) ?? "Unknown occurrence time",
             value.metricID, value.value.map { String($0) } ?? "", value.unit, value.state.rawValue, value.source,
             value.definitionVersion, value.recordIDs.joined(separator: " | "), value.requiresReview ? "yes" : "no", value.detail, value.detailOnly == true ? "yes" : "no", value.comparisonLabel ?? "", includePartialMetrics == true ? "yes" : "no"]
        }
        return rows.map(ReportCSV.row).joined(separator: "\r\n") + "\r\n"
    }
    private static func aggregate(_ values: [PhysicianReportObservation], period: PhysicianReportPeriod,
                                  monthly: Bool, includePartial: Bool) -> [PhysicianMetricSummary] {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: period.timeZoneIdentifier)
        formatter.dateFormat = "yyyy-MM-dd"
        let groups = Dictionary(grouping: values.filter { $0.detailOnly != true }, by: { value in
            value.stratum + [value.comparisonLabel ?? "", monthly ? value.observedAt.map { String(formatter.string(from: $0).prefix(7)) } ?? "Unknown date" : "full"]
        })
        return groups.map { key, rows in
            let available = rows.filter { $0.state == .available && $0.observedAt != nil }
            let partial = includePartial ? rows.filter { $0.state == .partial && $0.observedAt != nil && $0.value != nil } : []
            let numbers = (available + partial).compactMap(\.value).sorted()
            func quantile(_ p: Double) -> Double? {
                guard !numbers.isEmpty else { return nil }
                let position = Double(numbers.count - 1) * p, low = Int(position), high = min(low + 1, numbers.count - 1)
                return numbers[low] + (numbers[high] - numbers[low]) * (position - Double(low))
            }
            func count(_ state: PhysicianMetricState) -> Int { rows.filter { $0.state == state }.count }
            var calendar = formatter.calendar!; calendar.timeZone = formatter.timeZone!
            var dayCount = period.calendarDayCount
            if monthly {
                if let date = rows.compactMap(\.observedAt).first,
                   let month = calendar.dateInterval(of: .month, for: date) {
                    let lower = calendar.startOfDay(for: max(month.start, period.start))
                    let upper = calendar.startOfDay(for: Date(timeIntervalSince1970: min(month.end, period.endExclusive).timeIntervalSince1970.nextDown))
                    dayCount = max(0, (calendar.dateComponents([.day], from: lower, to: upper).day ?? -1) + 1)
                } else { dayCount = 0 }
            }
            return PhysicianMetricSummary(comparisonLabel: rows.first?.comparisonLabel, includedPartialCount: partial.isEmpty ? nil : partial.count,
                month: monthly ? key[5] : nil, metricID: key[0], unit: key[1], source: key[2], definitionVersion: key[3],
                eligibleCount: rows.filter { $0.observedAt != nil && $0.state != .notApplicable && $0.state != .notCollected }.count,
                availableCount: available.count, unavailableCount: count(.unavailable), partialCount: count(.partial),
                reviewCount: count(.needsReview), notApplicableCount: count(.notApplicable), notCollectedCount: count(.notCollected),
                calendarDayCount: dayCount, assessedDays: Set(rows.filter { $0.state != .notCollected && $0.state != .notApplicable }.compactMap(\.observedAt).map(formatter.string)).count,
                availableDays: Set(available.compactMap(\.observedAt).map(formatter.string)).count,
                unplacedCount: rows.filter { $0.observedAt == nil }.count,
                median: quantile(0.5), lowerQuartile: quantile(0.25), upperQuartile: quantile(0.75))
        }.sorted { $0.id < $1.id }
    }
}
