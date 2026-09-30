import Foundation

public enum DashboardMetricState: String, Codable, Sendable {
    case available, partial, unavailable, notApplicable, needsReview
}

public struct DashboardMetricValue: Codable, Equatable, Sendable {
    public let value: Double?
    public let state: DashboardMetricState
    public let reason: String
    public let unit: String
    public init(value: Double?, state: DashboardMetricState, reason: String, unit: String) {
        self.value = value?.isFinite == true ? value : nil
        self.state = value != nil && value?.isFinite != true ? .needsReview : state
        self.reason = reason; self.unit = unit
    }
}

public struct DashboardDosePattern: Codable, Equatable, Sendable {
    public static let version = "dose-pattern.v1"
    public enum Pattern: String, Codable, CaseIterable, Sendable {
        case twoReported, singlePlanned, singleOmitted, singleUnknownPlan
        case incomplete, noneReported, needsReview, inProgress
        public var label: String {
            switch self {
            case .twoReported: return "Two doses reported"
            case .singlePlanned: return "One dose, one-dose plan recorded"
            case .singleOmitted: return "One dose, Dose 2 not taken"
            case .singleUnknownPlan: return "One dose confirmed, plan unknown"
            case .incomplete: return "Dose history incomplete"
            case .noneReported: return "No doses reported taken"
            case .needsReview: return "Other / needs review"
            case .inProgress: return "In progress"
            }
        }
    }
    public struct Administration: Codable, Equatable, Sendable {
        public let id: String
        public let sessionID: String
        public let slot: Int
        public let occurredAt: Date?
        public init(id: String, sessionID: String, slot: Int, occurredAt: Date?) {
            self.id = id; self.sessionID = sessionID; self.slot = slot; self.occurredAt = occurredAt
        }
    }
    public let pattern: Pattern
    public let reportedCount: Int
    public let countComplete: Bool
    public let interval: DashboardMetricValue
    public let postDose2State: DashboardMetricState
    public let pairIDs: [String]
    public let evidenceIDs: [String]

    public static func derive(sessionID: String, administrations: [Administration], confirmedCount: Int?,
                              historicalPlanCount: Int?, secondNotTaken: Bool, sessionOpen: Bool) -> Self {
        let byID = Dictionary(grouping: administrations, by: \.id)
        let rows = byID.values.compactMap(\.first).sorted { $0.id < $1.id }
        let count = max(rows.count, confirmedCount ?? 0)
        let complete = confirmedCount != nil || (secondNotTaken && rows.count == 1 && !sessionOpen)
        func make(_ pattern: Pattern, _ state: DashboardMetricState, _ reason: String,
                  value: Double? = nil, post: DashboardMetricState = .unavailable, pair: [String] = []) -> Self {
            Self(pattern: pattern, reportedCount: count, countComplete: complete,
                 interval: .init(value: value, state: state, reason: reason, unit: "minutes"),
                 postDose2State: post, pairIDs: pair, evidenceIDs: rows.map(\.id))
        }
        let duplicatedConflict = byID.values.contains { values in values.contains { $0 != values.first } }
        guard !sessionID.isEmpty, !duplicatedConflict,
              rows.allSatisfy({ !$0.id.isEmpty && $0.sessionID == sessionID && (1...2).contains($0.slot)
                  && ($0.occurredAt.map { $0.timeIntervalSince1970.isFinite } ?? true) }),
              Set(rows.map(\.slot)).count == rows.count, rows.count <= 2,
              confirmedCount.map({ (0...2).contains($0) && $0 >= rows.count }) ?? true,
              historicalPlanCount.map({ (1...2).contains($0) }) ?? true else {
            return make(.needsReview, .needsReview, "conflicting_administrations", post: .needsReview)
        }
        let d1 = rows.first { $0.slot == 1 }, d2 = rows.first { $0.slot == 2 }
        guard !(secondNotTaken && (d2 != nil || count > 1)), !(d2 != nil && d1 == nil) else {
            return make(.needsReview, .needsReview, "conflicting_outcomes", post: .needsReview)
        }
        if count == 2 {
            guard let first = d1?.occurredAt, let second = d2?.occurredAt else {
                return make(.twoReported, .unavailable, "occurrence_time_missing",
                            post: d2?.occurredAt == nil ? .unavailable : .available)
            }
            let elapsed = second.timeIntervalSince(first)
            guard elapsed.isFinite && elapsed > 0 else {
                return make(.needsReview, .needsReview, "nonpositive_pair", post: .needsReview)
            }
            return make(.twoReported, .available, "reported_occurrence_pair", value: elapsed / 60,
                        post: .available, pair: [d1!.id, d2!.id])
        }
        if confirmedCount == 0 { return make(.noneReported, .notApplicable, "no_administration", post: .notApplicable) }
        if count == 1 && (confirmedCount == 1 || (secondNotTaken && !sessionOpen)) {
            let pattern: Pattern = secondNotTaken ? .singleOmitted : historicalPlanCount == 1 ? .singlePlanned : .singleUnknownPlan
            return make(pattern, .notApplicable, "single_administration", post: .notApplicable)
        }
        return make(sessionOpen ? .inProgress : .incomplete, .unavailable,
                    sessionOpen ? "outcome_pending" : "dose_outcome_unknown")
    }
}
