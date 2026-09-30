import Foundation

public struct WorkCycleObservation: Identifiable, Equatable, Sendable {
    public let sleepID: String
    public let sleepDate: String
    public let phase: WorkPhase
    public let position: String
    public let blockID: String?
    public let value: Double?
    public var rosterID: UUID?
    public var detail: String
    public var id: String { sleepID }
    public init(sleepID: String, sleepDate: String, phase: WorkPhase, position: String, blockID: String?, value: Double?, rosterID: UUID? = nil, detail: String = "") {
        self.sleepID = sleepID; self.sleepDate = sleepDate; self.phase = phase; self.position = position
        self.blockID = blockID; self.value = value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.rosterID = rosterID; self.detail = detail
    }
}

public struct WorkCycleSummary: Equatable, Sendable {
    public let availableCount: Int
    public let missingCount: Int
    public let distinctBlockCount: Int
    public let unresolvedBlockCount: Int
    public let median: Double?
    public let lowerQuartile: Double?
    public let upperQuartile: Double?
    public init(observations: [WorkCycleObservation]) {
        let values = observations.compactMap(\.value).sorted()
        availableCount = values.count; missingCount = observations.count - values.count
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
    public static func csv(_ observations: [WorkCycleObservation], metric: String, basis: WorkContextBasis, range: String, revision: UUID, asOf: Date) -> String {
        let summary = WorkCycleSummary(observations: observations)
        let headers = ["sleep_id", "sleep_date", "phase", "position", "block_id", "value_minutes", "value_state", "metric", "context_basis", "range", "context_revision", "as_of_utc", "classification_version", "roster_revision", "detail", "eligible_observations", "missing_observations", "distinct_known_blocks", "reference"]
        let stamp = ISO8601DateFormatter().string(from: asOf)
        return ([ReportCSV.row(headers)] + observations.map { row in
            ReportCSV.row([row.sleepID, row.sleepDate, row.phase.rawValue, row.position, row.blockID ?? "", row.value.map { String($0) } ?? "", row.value == nil ? "unavailable" : "available", metric, basis.rawValue, range, revision.uuidString, stamp, "1", row.rosterID?.uuidString ?? "", row.detail, String(summary.availableCount), String(summary.missingCount), String(summary.distinctBlockCount), "Built-in spacing reference; not a prescription."])
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
        case .after: return "First post-block main sleep"
        case .off: return "Later off-block • index unknown"
        case .unknown: return "Unknown / review"
        }
    }
}
