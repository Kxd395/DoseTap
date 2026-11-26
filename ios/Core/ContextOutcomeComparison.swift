import Foundation

/// One exact session/outcome observation. Unknown times are never reconstructed from treatment dates.
public struct ContextOutcomeObservation: Equatable, Sendable, Identifiable {
    public let id: String
    public let sessionID: String
    public let treatmentDate: String
    public let occurredAt: Date?
    public let context: String?
    public let compatibilityStratum: String?
    public let source: String
    public let unit: String
    public let value: Double?
    public let category: String?
    public let state: DashboardMetricState
    public let reason: String
    public let relationship: String

    public init(id: String, sessionID: String, treatmentDate: String, occurredAt: Date?, context: String?,
                compatibilityStratum: String?, source: String, unit: String, value: Double?, category: String?,
                state: DashboardMetricState, reason: String, relationship: String) {
        self.id = id; self.sessionID = sessionID; self.treatmentDate = treatmentDate; self.occurredAt = occurredAt
        self.context = context; self.compatibilityStratum = compatibilityStratum; self.source = source
        self.unit = unit; self.value = value; self.category = category; self.state = state
        self.reason = reason; self.relationship = relationship
    }
    public var contextLabel: String { Self.nonempty(context) ?? "Unknown context" }
    public var stratumLabel: String { Self.nonempty(compatibilityStratum) ?? "Unknown compatibility · " + id }
    fileprivate static func nonempty(_ value: String?) -> String? {
        value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
    fileprivate var groupKey: [String] {
        // Tagged keys prevent literal labels from colliding with missing values.
        [Self.nonempty(context) == nil ? "missing" : "known", contextLabel,
         Self.nonempty(compatibilityStratum) == nil ? "unknown:" + id : "known", stratumLabel, source, unit]
    }
}

/// Descriptive only: no ranking, causal model, scale conversion or treatment recommendation.
public struct ContextOutcomeComparison: Sendable {
    public static let derivationVersion = "context-outcomes-v1"
    public struct Group: Identifiable, Sendable {
        public let id: String
        public let observations: [ContextOutcomeObservation]
        public let eligible: [ContextOutcomeObservation]
        public var context: String { observations[0].contextLabel }
        public var stratum: String { observations[0].stratumLabel }
        public var source: String { observations[0].source }
        public var unit: String { observations[0].unit }
        public var summary: DiaryMetricSummary { .init(eligible.map(\.value)) }
        public var categoryCounts: [String: Int] {
            Dictionary(grouping: eligible.compactMap(\.category), by: { $0 }).mapValues(\.count)
        }
        public var excludedCount: Int { observations.count - eligible.count }
    }
    public let observations: [ContextOutcomeObservation]
    public let asOf: Date
    public let timeZoneID: String
    public let filterDescription: String
    public let metric: String
    public let includePartial: Bool
    public let conflictingIDs: Set<String>
    public init(observations: [ContextOutcomeObservation], asOf: Date, timeZoneID: String,
                filterDescription: String, metric: String, includePartial: Bool = false) {
        let grouped = Dictionary(grouping: observations, by: \.id)
        conflictingIDs = Set(grouped.filter { _, rows in rows.contains { $0 != rows.first } }.keys)
        self.observations = grouped.keys.sorted().flatMap { id -> [ContextOutcomeObservation] in
            var unique: [ContextOutcomeObservation] = []
            for row in grouped[id] ?? [] where !unique.contains(row) { unique.append(row) }
            return unique
        }
        self.asOf = asOf; self.timeZoneID = timeZoneID; self.filterDescription = filterDescription
        self.metric = metric; self.includePartial = includePartial
    }
    public func exclusionReason(_ row: ContextOutcomeObservation) -> String? {
        guard asOf.timeIntervalSince1970.isFinite, TimeZone(identifier: timeZoneID) != nil else { return "Invalid report clock or timezone" }
        guard !row.id.isEmpty, !row.sessionID.isEmpty, !conflictingIDs.contains(row.id) else { return "Identity needs review" }
        guard ContextOutcomeObservation.nonempty(row.source) != nil, ContextOutcomeObservation.nonempty(row.unit) != nil else { return "Source or unit unavailable" }
        if let date = row.occurredAt, !date.timeIntervalSince1970.isFinite || date > asOf { return "Invalid or future occurrence time" }
        guard row.state == .available || (includePartial && row.state == .partial) else { return row.state.rawValue + ": " + row.reason }
        if let value = row.value {
            guard value.isFinite, value >= 0, row.category == nil else { return "Conflicting or invalid value" }
        } else if ContextOutcomeObservation.nonempty(row.category) == nil { return "Outcome unavailable" }
        return nil
    }
    public var eligible: [ContextOutcomeObservation] { observations.filter { exclusionReason($0) == nil } }
    public var eligibleCount: Int { eligible.count }
    public var excludedCount: Int { observations.count - eligibleCount }
    public var unknownContextCount: Int { observations.filter { ContextOutcomeObservation.nonempty($0.context) == nil }.count }
    public var groups: [Group] {
        Dictionary(grouping: observations, by: \.groupKey).map { key, rows in
            let data = (try? JSONEncoder().encode(key)) ?? Data()
            return Group(id: data.base64EncodedString(), observations: rows,
                         eligible: rows.filter { exclusionReason($0) == nil })
        }.sorted { $0.id < $1.id }
    }
    public var csv: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func stamp(_ date: Date?) -> String {
            guard let date, date.timeIntervalSince1970.isFinite else { return "" }
            return formatter.string(from: date)
        }
        func cell(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = trimmed.first.map { "=+-@".contains($0) } == true ? "'" + text : text
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let headers = ["derivation_version", "as_of_utc", "timezone", "filters", "metric", "include_partial", "available", "excluded", "unknown_context", "observation_id", "session_id", "treatment_date", "occurred_at_utc", "context", "compatibility_stratum", "source", "unit", "value", "category", "state", "reason", "relationship", "exclusion"]
        var rows = [headers]
        if observations.isEmpty {
            rows.append([Self.derivationVersion, stamp(asOf), timeZoneID, filterDescription, metric, String(includePartial),
                         "0", "0", "0"] + Array(repeating: "", count: headers.count - 9))
        }
        for row in observations {
            rows.append([Self.derivationVersion, stamp(asOf), timeZoneID, filterDescription, metric, String(includePartial),
                         String(eligibleCount), String(excludedCount), String(unknownContextCount), row.id, row.sessionID,
                         row.treatmentDate, stamp(row.occurredAt), row.contextLabel, row.stratumLabel, row.source, row.unit,
                         row.value.flatMap { $0.isFinite ? String($0) : nil } ?? "", row.category ?? "", row.state.rawValue,
                         row.reason, row.relationship, exclusionReason(row) ?? ""])
        }
        return rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
