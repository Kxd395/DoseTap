import Foundation

/// Metric evidence survives exclusion from a particular chart or reporting period.
public struct WorkCycleMetricEvidence: Equatable, Sendable {
    public let metricID: String
    public let source: String
    public let definitionVersion: String
    public let metric: DashboardMetricValue
    public var start: Date?
    public var end: Date?
    public init(metricID: String, source: String, definitionVersion: String, metric: DashboardMetricValue,
                start: Date?, end: Date?) {
        self.metricID = metricID; self.source = source; self.definitionVersion = definitionVersion
        self.metric = metric; self.start = start; self.end = end
    }
}

public extension WorkCycleObservation {
    func applying(_ evidence: WorkCycleMetricEvidence, includePartial: Bool,
                  period: PhysicianReportPeriod? = nil) -> Self {
        var result = self
        result.metricEvidence = evidence; result.value = nil
        result.contributionReason = evidence.metric.reason
        guard [evidence.metricID, evidence.source, evidence.definitionVersion, evidence.metric.unit]
            .allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 300 }) else {
            result.contributionReason = "invalid_metric_metadata"; return result
        }
        guard evidence.metric.state == .available || evidence.metric.state == .partial else { return result }
        if evidence.metric.state == .partial && !includePartial {
            result.contributionReason = "partial_excluded"; return result
        }
        guard let value = evidence.metric.value, value.isFinite, value >= 0 else {
            result.contributionReason = "invalid_duration_value"; return result
        }
        guard [evidence.start, evidence.end].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              evidence.start.flatMap({ start in evidence.end.map { start < $0 } }) != false else {
            result.contributionReason = "invalid_metric_bounds"; return result
        }
        if let period {
            guard (try? period.validate()) != nil else { result.contributionReason = "invalid_reporting_period"; return result }
            guard let start = evidence.start, let end = evidence.end else {
                result.contributionReason = "metric_bounds_unavailable"; return result
            }
            guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, start < end else {
                result.contributionReason = "invalid_metric_bounds"; return result
            }
            guard period.contains(start), period.contains(end) else {
                result.contributionReason = "metric_bounds_outside_selected_period"; return result
            }
        }
        result.value = value
        result.contributionReason = evidence.metric.state == .partial ? "included_partial" : "included"
        return result
    }
}

/// Descriptive comparison groups. Calendar gaps never become invented expected work nights.
public struct WorkCycleComparison: Sendable {
    public struct Group: Identifiable, Sendable {
        public let id: String
        public let month: String?
        public let phase: WorkPhase
        public let position: String
        public let stratumID: String
        public let stratumLabel: String
        public let metricID: String
        public let source: String
        public let definitionVersion: String
        public let unit: String
        public let rows: [WorkCycleObservation]
        public var observationIDs: [String] { rows.map(\.id) }
        public var summary: WorkCycleSummary { WorkCycleSummary(observations: rows) }
        public var notApplicableCount: Int { rows.filter { $0.metricEvidence?.metric.state == .notApplicable }.count }
        public var eligibleCount: Int { rows.count - notApplicableCount }
        public var partialCount: Int { rows.filter { $0.metricEvidence?.metric.state == .partial }.count }
        public var partialIncludedCount: Int { rows.filter { $0.metricEvidence?.metric.state == .partial && $0.value != nil }.count }
        public var needsReviewCount: Int { rows.filter { $0.metricEvidence?.metric.state == .needsReview || $0.contributionReason == "conflicting_observation_identity" }.count }
        public var representedDateCount: Int { Set(rows.map(\.sleepDate)).count }
    }
    public let rawObservations: [WorkCycleObservation]
    public let observations: [WorkCycleObservation]
    public let duplicateIDs: [String]
    public let conflictingIDs: [String]
    public let unplacedIDs: [String]
    public let selectedPeriod: [Group]
    public let monthly: [Group]

    public init(observations inputs: [WorkCycleObservation]) {
        rawObservations = inputs
        var duplicate: [String] = [], conflicting: [String] = [], unplaced: [String] = []
        var checked: [WorkCycleObservation] = []
        for (id, rows) in Dictionary(grouping: inputs, by: \.id) {
            guard var row = rows.first else { continue }
            if rows.count > 1 { duplicate.append(id) }
            if rows.contains(where: { $0 != row }) {
                conflicting.append(id); row.value = nil; row.contributionReason = "conflicting_observation_identity"
            }
            guard !id.isEmpty, DashboardReportingWindow.isValidDateKey(row.sleepDate) else { unplaced.append(id); continue }
            checked.append(row)
        }
        observations = checked.sorted { $0.sleepDate == $1.sleepDate ? $0.id < $1.id : $0.sleepDate < $1.sleepDate }
        duplicateIDs = duplicate.sorted(); conflictingIDs = conflicting.sorted(); unplacedIDs = unplaced.sorted()
        selectedPeriod = Self.groups(observations, monthly: false)
        monthly = Self.groups(observations, monthly: true)
    }
    private static func groups(_ rows: [WorkCycleObservation], monthly: Bool) -> [Group] {
        func components(_ row: WorkCycleObservation) -> [String] {
            let context = row.stratumID.flatMap { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } ?? "unknown:" + row.id
            return [monthly ? String(row.sleepDate.prefix(7)) : "", row.phase.rawValue, row.position, context,
                    row.metricEvidence?.metricID ?? "unspecified", row.metricEvidence?.source ?? "unspecified",
                    row.metricEvidence?.definitionVersion ?? "unspecified", row.metricEvidence?.metric.unit ?? "minutes"]
        }
        let grouped = Dictionary(grouping: rows) { components($0) }
        return grouped.compactMap { fields, rows in
            guard let row = rows.first else { return nil }
            return Group(id: fields.map { "\($0.utf8.count):\($0)" }.joined(), month: monthly ? fields[0] : nil,
                phase: row.phase, position: fields[2], stratumID: fields[3],
                stratumLabel: row.stratumLabel ?? "Context unknown — kept separate", metricID: fields[4], source: fields[5],
                definitionVersion: fields[6], unit: fields[7], rows: rows.sorted { $0.id < $1.id })
        }.sorted { $0.id < $1.id }
    }
}
