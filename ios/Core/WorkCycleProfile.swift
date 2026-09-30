import Foundation

public enum WorkComparisonGrouping: String, CaseIterable, Sendable { case none, workPhase, spacingReference }

public struct WorkCycleObservation: Identifiable, Equatable, Sendable {
    public let sleepID: String
    public let sleepDate: String
    public let phase: WorkPhase
    public let position: String
    public let blockID: String?
    public internal(set) var value: Double?
    public internal(set) var metricEvidence: WorkCycleMetricEvidence?
    public internal(set) var contributionReason = "legacy_observation"
    public var intervalMinutes: Double?
    public var stratumID: String?
    public var stratumLabel: String?
    public var rosterID: UUID?
    public var isOverride: Bool
    public var detail: String
    public var associationID: UUID?
    public var contextSnapshotAt: Date?
    public var planSnapshotID: UUID?
    public var id: String { sleepID }
    public init(sleepID: String, sleepDate: String, phase: WorkPhase, position: String, blockID: String?, value: Double?, rosterID: UUID? = nil, detail: String = "", associationID: UUID? = nil, contextSnapshotAt: Date? = nil, isOverride: Bool = false, intervalMinutes: Double? = nil, stratumID: String? = nil, stratumLabel: String? = nil, planSnapshotID: UUID? = nil) {
        self.sleepID = sleepID; self.sleepDate = sleepDate; self.phase = phase; self.position = position
        self.blockID = blockID; self.value = value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.intervalMinutes = intervalMinutes.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.stratumID = stratumID; self.stratumLabel = stratumLabel; self.planSnapshotID = planSnapshotID
        self.rosterID = rosterID; self.detail = detail
        self.associationID = associationID; self.contextSnapshotAt = contextSnapshotAt; self.isOverride = isOverride
    }
    public func groupSymbol(_ grouping: WorkComparisonGrouping) -> String {
        switch grouping {
        case .none: return "circle"
        case .workPhase:
            return phase.comparisonSymbol
        case .spacingReference:
            switch groupLabel(grouping) { case "Shorter than reference": return "diamond"; case "Within reference": return "circle"; case "Longer than reference": return "triangle"; default: return "cross" }
        }
    }
    public func groupLabel(_ grouping: WorkComparisonGrouping) -> String {
        switch grouping {
        case .none: return "All observations"
        case .workPhase: return phase.label
        case .spacingReference:
            guard let intervalMinutes, intervalMinutes.isFinite, intervalMinutes > 0 else { return "Interval unavailable" }
            if intervalMinutes < 150 { return "Shorter than reference" }
            return intervalMinutes <= 240 ? "Within reference" : "Longer than reference"
        }
    }
}

public struct WorkCycleSummary: Equatable, Sendable {
    public let availableCount: Int
    public let missingCount: Int
    public let eligibleCount: Int
    public let notApplicableCount: Int
    public let partialCount: Int
    public let partialIncludedCount: Int
    public let distinctBlockCount: Int
    public let unresolvedBlockCount: Int
    public let median: Double?
    public let lowerQuartile: Double?
    public let upperQuartile: Double?
    public init(observations: [WorkCycleObservation]) {
        let values = observations.compactMap(\.value).sorted()
        availableCount = values.count
        notApplicableCount = observations.filter { $0.metricEvidence?.metric.state == .notApplicable }.count
        eligibleCount = observations.count - notApplicableCount
        missingCount = eligibleCount - values.count
        partialCount = observations.filter { $0.metricEvidence?.metric.state == .partial }.count
        partialIncludedCount = observations.filter { $0.metricEvidence?.metric.state == .partial && $0.value != nil }.count
        distinctBlockCount = Set(observations.filter { $0.value != nil }.compactMap(\.blockID)).count
        unresolvedBlockCount = observations.filter { $0.blockID == nil }.count
        func quantile(_ fraction: Double) -> Double? {
            guard !values.isEmpty else { return nil }
            let index = Double(values.count - 1) * fraction
            let low = Int(index), high = min(low + 1, values.count - 1)
            return values[low] + (values[high] - values[low]) * (index - Double(low))
        }
        median = quantile(0.5)
        lowerQuartile = values.count >= 2 ? quantile(0.25) : nil
        upperQuartile = values.count >= 2 ? quantile(0.75) : nil
    }
    public static func csv(_ observations: [WorkCycleObservation], metric: String, basis: WorkContextBasis, range: String, revision: UUID, asOf: Date, grouping: WorkComparisonGrouping = .none, phaseFilter: String = "All", positionFilter: String = "All", matrixEncoding: String = "Values") -> String {
        let summary = WorkCycleSummary(observations: observations)
        let headers = ["sleep_id", "sleep_date", "phase", "position", "block_id", "value_minutes", "value_state", "metric", "context_basis", "range", "context_revision", "as_of_utc", "classification_version", "roster_revision", "detail", "eligible_observations", "missing_observations", "distinct_known_blocks", "reference", "association_revision", "context_snapshot_at_utc", "is_override", "override_reason", "interval_minutes", "grouping", "group_label", "phase_filter", "position_filter", "matrix_encoding", "context_stratum_id", "context_stratum_label", "group_symbol", "row_type", "plan_snapshot_id", "reference_lower_minutes", "reference_upper_minutes", "raw_metric_value", "contribution_reason", "metric_id", "metric_source", "metric_definition_version", "metric_unit", "metric_start_utc", "metric_end_utc", "available_observations", "not_applicable_observations", "partial_observations", "partial_included_observations", "notes_policy"]
        let stamp = ISO8601DateFormatter().string(from: asOf)
        if observations.isEmpty {
            let metadata = ["row_type": "comparison_metadata", "reference_lower_minutes": "150", "reference_upper_minutes": "240", "available_observations": "0", "not_applicable_observations": "0", "partial_observations": "0", "partial_included_observations": "0", "notes_policy": "free_text_omitted", "metric": metric, "context_basis": basis.rawValue, "range": range, "context_revision": revision.uuidString, "as_of_utc": stamp, "classification_version": "1", "grouping": grouping.rawValue, "phase_filter": phaseFilter, "position_filter": positionFilter, "matrix_encoding": matrixEncoding, "eligible_observations": "0", "missing_observations": "0", "distinct_known_blocks": "0", "reference": "Built-in spacing reference; not a prescription."]
            return ReportCSV.row(headers) + "\r\n" + ReportCSV.row(headers.map { metadata[$0] ?? "" }) + "\r\n"
        }
        return ([ReportCSV.row(headers)] + observations.map { row in
            ReportCSV.row([row.sleepID, row.sleepDate, row.phase.rawValue, row.position, row.blockID ?? "", row.value.map { String($0) } ?? "", row.metricEvidence?.metric.state.rawValue ?? (row.value == nil ? "unavailable" : "available"), metric, basis.rawValue, range, revision.uuidString, stamp, "1", row.rosterID?.uuidString ?? "", "", String(summary.eligibleCount), String(summary.missingCount), String(summary.distinctBlockCount), "Built-in spacing reference; not a prescription.", row.associationID?.uuidString ?? "", row.contextSnapshotAt.map { ISO8601DateFormatter().string(from: $0) } ?? "", row.isOverride ? "true" : "false", "", row.intervalMinutes.map(String.init(describing:)) ?? "", grouping.rawValue, row.groupLabel(grouping), phaseFilter, positionFilter, matrixEncoding, row.stratumID ?? "", row.stratumLabel ?? "", row.groupSymbol(grouping), "observation", row.planSnapshotID?.uuidString ?? "", "150", "240",
                row.metricEvidence?.metric.value.map(String.init(describing:)) ?? "", row.contributionReason,
                row.metricEvidence?.metricID ?? "", row.metricEvidence?.source ?? "", row.metricEvidence?.definitionVersion ?? "",
                row.metricEvidence?.metric.unit ?? "minutes", row.metricEvidence?.start.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                row.metricEvidence?.end.map { ISO8601DateFormatter().string(from: $0) } ?? "", String(summary.availableCount),
                String(summary.notApplicableCount), String(summary.partialCount), String(summary.partialIncludedCount), "free_text_omitted"])
        }).joined(separator: "\r\n") + "\r\n"
    }
}

public extension WorkPhaseResult {
    var positionLabel: String {
        switch phase {
        case .entering: return followingPosition.map { "Before shift \($0)" } ?? "Entering • position unknown"
        case .between:
            if let precedingPosition, let followingPosition { return "Between \(precedingPosition) and \(followingPosition)" }
            return "Between • positions unknown"
        case .after: return postBlockMainSleepIndex == 1 ? "First post-block main sleep" : "After block • index unknown"
        case .off: return "Later off-block • index unknown"
        case .unknown: return "Unknown / review"
        }
    }
}

public extension WorkPhase {
    var comparisonSymbol: String {
        switch self { case .entering: return "circle"; case .between: return "square"; case .after: return "triangle"; case .off: return "diamond"; case .unknown: return "cross" }
    }
}
