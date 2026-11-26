import Foundation
import DoseCore

/// Categorical answers retain their original confirmation state. There is no numerical scale conversion.
struct WorkCycleCategoryReport {
    let sourceRows: [ContextOutcomeObservation]
    let comparison: ContextOutcomeComparison
    let workRows: [WorkCycleObservation]
    let basis: WorkContextBasis
    let monthly: Bool
    var unknownWorkCount: Int {
        let known = Set(workRows.filter { $0.phase != .unknown }.map(\.id))
        return comparison.observations.filter { !known.contains($0.id) }.count
    }
    var csv: String? {
        guard let table = try? ReportCSV.rows(comparison.csv), let header = table.first,
              let index = header.firstIndex(of: "observation_id") else { return nil }
        let work = Dictionary(uniqueKeysWithValues: workRows.map { ($0.id, $0) })
        let groupColumns = ["observation_id", "context", "compatibility_stratum", "source", "unit"]
        guard groupColumns.allSatisfy({ header.contains($0) }) else { return nil }
        let groupIndexes = groupColumns.compactMap { header.firstIndex(of: $0) }
        let groups = Dictionary(grouping: comparison.groups.flatMap { group in
            let counts = [String(group.eligible.count), String(group.excludedCount), String(knownBlocks(for: group.eligible.map(\.id)).count)]
            return group.observations.map { ([$0.id, $0.contextLabel, $0.stratumLabel, $0.source, $0.unit], counts) }
        }, by: { $0.0 }).mapValues { entries in
            let values = Set(entries.map { $0.1 }); return values.count == 1 ? entries[0].1 : ["", "", ""]
        }
        let columns = ["work_basis", "work_block_id", "work_phase", "work_position", "association_revision", "group_eligible", "group_excluded", "group_distinct_known_blocks"]
        let body = table.dropFirst().map { values -> String in
            let id = values.indices.contains(index) ? values[index] : "", row = work[id]
            let fields = [basis.rawValue, row?.blockID ?? "", row?.phase.rawValue ?? "unknown", row?.position ?? "Unknown / review", row?.associationID?.uuidString ?? ""]
            return ReportCSV.row(values + fields + (groups[groupIndexes.map { values.indices.contains($0) ? values[$0] : "" }] ?? ["0", "0", "0"]))
        }
        return ([ReportCSV.row(header + columns)] + body).joined(separator: "\r\n") + "\r\n"
    }
    var knownBlockCount: Int { knownBlocks(for: comparison.eligible.map(\.id)).count }
    func knownBlocks(for ids: [String]) -> Set<String> {
        let included = Set(ids)
        return Set(workRows.filter { included.contains($0.id) }.compactMap(\.blockID))
    }
    init(sourceRows: [ContextOutcomeObservation], workRows: [WorkCycleObservation], asOf: Date,
         timeZoneID: String, filters: String, metric: String, basis: WorkContextBasis,
         period: PhysicianReportPeriod? = nil, monthly: Bool = false) {
        self.sourceRows = sourceRows
        let work = WorkCycleComparison(observations: workRows)
        self.workRows = work.observations.filter { !work.conflictingIDs.contains($0.id) }
        self.basis = basis; self.monthly = monthly
        let indexed = Dictionary(uniqueKeysWithValues: self.workRows.map { ($0.id, $0) })
        let rows = sourceRows.map { row -> ContextOutcomeObservation in
            let work = indexed[row.id]
            let phase = work.flatMap { $0.phase == .unknown ? nil : $0.phase.label + " • " + $0.position }
            let context = monthly ? String(row.treatmentDate.prefix(7)) + " • " + (phase ?? "Unknown work context") : phase
            var state = row.state, reason = row.reason
            if let period, row.occurredAt.map({ period.contains($0) }) != true {
                state = .unavailable; reason = "Outcome assessment time unavailable or outside the exact period"
            }
            return .init(id: row.id, sessionID: row.sessionID, treatmentDate: row.treatmentDate,
                occurredAt: row.occurredAt, context: context, compatibilityStratum: row.compatibilityStratum,
                source: row.source, unit: row.unit, value: nil, category: row.category, state: state,
                reason: reason, relationship: row.relationship)
        }
        comparison = .init(observations: rows, asOf: asOf, timeZoneID: timeZoneID,
            filterDescription: filters + "; work basis=" + basis.rawValue + "; months=" + String(monthly), metric: metric)
    }
}

extension DashboardAnalyticsModel {
    /// Uses the same canonical visible IDs and frozen work publication as the duration comparison.
    func workCycleCategoryReport(metric: ContextMorningMetric, period: PhysicianReportPeriod? = nil,
                                 monthly: Bool = false) -> WorkCycleCategoryReport? {
        guard !metric.duration, let work = workCycleComparison(metric: .doseInterval, period: period) else { return nil }
        let original = contextOutcomeReport(metric: metric, grouping: .workPhase)
        return WorkCycleCategoryReport(sourceRows: original.observations, workRows: work.observations,
            asOf: reportingAsOf, timeZoneID: reportingTimeZone.identifier, filters: original.filterDescription,
            metric: metric.rawValue, basis: inspection.workContextBasis, period: period, monthly: monthly)
    }
}
