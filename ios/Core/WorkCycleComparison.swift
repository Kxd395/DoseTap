import Foundation

/// Metric evidence survives exclusion from a particular chart or reporting period.
public struct WorkCycleMetricEvidence: Equatable, Sendable {
    public let metricID: String
    public let source: String
    public let definitionVersion: String
    public let metric: DashboardMetricValue
    public let boundaryIssue: String?
    public var start: Date?
    public var end: Date?
    public init(metricID: String, source: String, definitionVersion: String, metric: DashboardMetricValue,
                start: Date?, end: Date?, boundaryIssue: String? = nil) {
        self.metricID = metricID; self.source = source; self.definitionVersion = definitionVersion
        self.metric = metric; self.start = start; self.end = end; self.boundaryIssue = boundaryIssue
    }
}

public extension WorkCycleObservation {
    func applying(_ evidence: WorkCycleMetricEvidence, includePartial: Bool,
                  period: PhysicianReportPeriod? = nil, asOf: Date? = nil) -> Self {
        var result = self
        result.metricEvidence = evidence; result.value = nil; result.contributionState = evidence.metric.state
        result.contributionReason = evidence.metric.reason
        func review(_ reason: String) -> Self {
            var excluded = result; excluded.contributionState = .needsReview; excluded.contributionReason = reason
            return excluded
        }
        let capture = asOf ?? period?.capturedAt
        if let capture, !capture.timeIntervalSince1970.isFinite { return review("invalid_capture_time") }
        if let issue = evidence.boundaryIssue {
            return review(issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || issue.count > 300
                ? "invalid_boundary_issue" : issue)
        }
        guard [evidence.metricID, evidence.source, evidence.definitionVersion, evidence.metric.unit]
            .allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 300 }) else {
            return review("invalid_metric_metadata")
        }
        guard evidence.metric.state == .available || evidence.metric.state == .partial else { return result }
        guard [evidence.start, evidence.end].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              evidence.start.flatMap({ start in evidence.end.map { start < $0 || (start == $0 && evidence.metric.value == 0) } }) != false else {
            return review("invalid_metric_bounds")
        }
        if let capture, [evidence.start, evidence.end].compactMap({ $0 }).contains(where: { $0 > capture }) {
            return review("metric_bounds_after_capture")
        }
        if evidence.metric.state == .partial && !includePartial {
            result.contributionReason = "partial_excluded"; return result
        }
        guard let value = evidence.metric.value, value.isFinite, value >= 0 else {
            return review("invalid_duration_value")
        }
        if let period {
            guard (try? period.validate()) != nil else { return review("invalid_reporting_period") }
            guard let start = evidence.start, let end = evidence.end else {
                result.contributionState = .unavailable; result.contributionReason = "metric_bounds_unavailable"; return result
            }
            guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, (start < end || (start == end && value == 0)) else {
                return review("invalid_metric_bounds")
            }
            guard period.contains(start), period.contains(end) else {
                result.contributionState = .unavailable; result.contributionReason = "metric_bounds_outside_selected_period"; return result
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
        public var needsReviewCount: Int { rows.filter { $0.contributionState == .needsReview || $0.metricEvidence?.metric.state == .needsReview }.count }
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
                conflicting.append(id); row.value = nil; row.contributionState = .needsReview; row.contributionReason = "conflicting_observation_identity"
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

/// Frozen selected-view metadata, independent of whether its filters return any observations.
public struct WorkCycleExportContext: Equatable, Sendable {
    public let selectedSource: String, selectedDefinition: String, timeZoneIdentifier: String
    public let periodStart: Date?, periodEndExclusive: Date?
    public let dosePatternFilter: String?, contextStratumFilter: String?, selectedObservationID: String?
    public let includePartialMetrics: Bool, visualization: String, monthlySummaries: Bool
    public let periodPolicy: String, providerSnapshotState: String
    public init(selectedSource: String, selectedDefinition: String, timeZoneIdentifier: String,
                periodStart: Date?, periodEndExclusive: Date?, dosePatternFilter: String?, contextStratumFilter: String?,
                includePartialMetrics: Bool, selectedObservationID: String?, visualization: String, monthlySummaries: Bool,
                periodPolicy: String = "reviewed_exact", providerSnapshotState: String = "unavailable") {
        self.selectedSource = selectedSource; self.selectedDefinition = selectedDefinition; self.timeZoneIdentifier = timeZoneIdentifier
        self.periodStart = periodStart; self.periodEndExclusive = periodEndExclusive; self.dosePatternFilter = dosePatternFilter
        self.contextStratumFilter = contextStratumFilter; self.includePartialMetrics = includePartialMetrics
        self.selectedObservationID = selectedObservationID; self.visualization = visualization; self.monthlySummaries = monthlySummaries
        self.periodPolicy = periodPolicy; self.providerSnapshotState = providerSnapshotState
    }
    static let headers = ["selected_source", "selected_definition", "selected_timezone", "selected_period_start_utc",
        "selected_period_end_exclusive_utc", "dose_pattern_filter", "context_stratum_filter", "include_partial_metrics",
        "selected_observation_id", "visualization", "summary_period", "period_policy", "provider_snapshot_state", "view_context_state"]
    var fields: [String: String] {
        let valid = TimeZone(identifier: timeZoneIdentifier) != nil
            && ["reviewed_exact", "treatment_date_membership"].contains(periodPolicy)
            && ["current", "stale", "unavailable"].contains(providerSnapshotState)
            && [selectedSource, selectedDefinition, visualization].allSatisfy { !$0.isEmpty && $0.count <= 300 }
            && [periodStart, periodEndExclusive].compactMap { $0 }.allSatisfy { $0.timeIntervalSince1970.isFinite }
            && periodStart.flatMap { start in periodEndExclusive.map { start < $0 } } != false
        return ["selected_source": selectedSource, "selected_definition": selectedDefinition, "selected_timezone": timeZoneIdentifier,
            "selected_period_start_utc": Self.stamp(periodStart), "selected_period_end_exclusive_utc": Self.stamp(periodEndExclusive),
            "dose_pattern_filter": dosePatternFilter ?? "All", "context_stratum_filter": contextStratumFilter ?? "All",
            "include_partial_metrics": includePartialMetrics ? "true" : "false", "selected_observation_id": selectedObservationID ?? "",
            "visualization": visualization, "summary_period": monthlySummaries ? "calendar_month" : "selected_period",
            "period_policy": periodPolicy, "provider_snapshot_state": providerSnapshotState, "view_context_state": valid ? "available" : "needsReview"]
    }
    static func stamp(_ date: Date?) -> String {
        guard let date, date.timeIntervalSince1970.isFinite else { return "" }
        return ISO8601DateFormatter().string(from: date)
    }
}
