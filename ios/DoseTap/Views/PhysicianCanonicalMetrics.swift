import Foundation
import CryptoKit
import DoseCore

@MainActor
extension DashboardAnalyticsModel {
    func physicianCanonicalNightMetrics(for period: PhysicianReportPeriod) throws -> [PhysicianReportObservation] {
        var observations: [PhysicianReportObservation] = []
        let nightsByID = Dictionary(grouping: visibleInspectionNights, by: \.id)
        let iso = ISO8601DateFormatter()
        for metric in WorkCycleMetric.allCases {
            guard let comparison = workCycleComparison(metric: metric, period: period) else { throw PhysicianReviewError.invalidRevision }
            for row in comparison.observations {
                guard let night = nightsByID[row.id]?.first, let evidence = row.metricEvidence else { throw PhysicianReviewError.invalidRevision }
                let suffix: String, title: String
                switch metric {
                case .doseInterval: suffix = ":spacing"; title = "Dose 1 to Dose 2 spacing"
                case .mainSleep: suffix = sleepSource == .appleHealth ? ":apple-sleep" : ":whoop-sleep"; title = "Primary episode sleep"
                case .sleepAfterDose2: suffix = ":observed-after-d2:" + (sleepSource == .appleHealth ? DashboardSleepMetricProjection.Source.appleHealth : .whoop).rawValue; title = "Observed sleep after Dose 2"
                }
                let raw = evidence.metric
                let state = PhysicianMetricState(rawValue: row.contributionState.rawValue) ?? .needsReview
                let providerID = sleepSource == .appleHealth ? night.healthSummary?.id : night.whoopSummary?.sleepId
                let ids = night.dosePattern.evidenceIDs + [providerID, row.associationID?.uuidString,
                    row.planSnapshotID?.uuidString, row.rosterID?.uuidString].compactMap { $0 }
                let contextID = row.stratumID ?? "unknown:" + row.id
                let hash = SHA256.hash(data: Data(contextID.utf8)).map { String(format: "%02x", $0) }.joined()
                let stamp = evidence.start ?? (metric == .sleepAfterDose2 ? night.dose2Time : nil)
                    ?? (metric == .mainSleep ? (sleepSource == .appleHealth ? night.healthSummary?.sleepOnset : night.whoopSummary?.date) : nil)
                    ?? night.dose1Time ?? night.dose2Time
                let lines = ["Treatment date: \(row.sleepDate); observation: \(row.id). \(night.dosePattern.pattern.label).",
                    "Raw source value: \(raw.value.map(String.init(describing:)) ?? "unknown") \(raw.unit); state \(raw.state.rawValue); reason \(raw.reason).",
                    "Original validated bounds: \(evidence.start.map(iso.string) ?? "unavailable") to \(evidence.end.map(iso.string) ?? "unavailable").",
                    "Numeric contribution: \(row.contributionReason). Source value and state remain inspectable when withheld.",
                    "Compatibility: \(row.stratumLabel ?? "Unknown — kept separate"); exact stratum \(contextID).",
                    evidence.start == nil ? "A source/dose timestamp may anchor this missing-result row; it does not establish a measured sleep onset." : "Membership uses the original source occurrence."]
                observations.append(.init(id: night.id + suffix, observedAt: stamp, metricID: title + " • " + night.dosePattern.pattern.label,
                    value: row.value, state: state, unit: raw.unit, source: evidence.source,
                    definitionVersion: evidence.definitionVersion + "|context:" + hash, detail: lines.joined(separator: "\n"),
                    recordIDs: ids, requiresReview: state == .needsReview || night.identityNeedsReview,
                    comparisonLabel: row.stratumLabel ?? "Context unknown — kept separate"))
            }
        }
        return observations
    }

    func physicianWorkComparisons(for period: PhysicianReportPeriod) throws -> [PhysicianReportContext] {
        var result: [PhysicianReportContext] = []
        for metric in WorkCycleMetric.allCases {
            guard let comparison = workCycleComparison(metric: metric, period: period) else { throw PhysicianReviewError.invalidRevision }
            for group in comparison.selectedPeriod + comparison.monthly {
                let summary = group.summary
                let hash = SHA256.hash(data: Data((metric.rawValue + group.id).utf8)).map { String(format: "%02x", $0) }.joined()
                let scope = group.month.map { "Month " + $0 } ?? "Full period"
                let lines = ["\(summary.availableCount)/\(summary.eligibleCount) eligible candidate observations contribute; \(summary.missingCount) missing/excluded; \(summary.notApplicableCount) not applicable.",
                    "\(group.needsReviewCount) observations need review; \(summary.partialCount) raw partial observations; \(summary.partialIncludedCount) included by the captured policy. Missing original bounds/out-of-period intervals do not contribute.",
                    "\(group.representedDateCount) treatment dates represented; \(summary.distinctBlockCount) distinct known blocks among contributing observations; \(summary.unresolvedBlockCount) rows have unresolved block links.",
                    "Median: \(summary.median.map(String.init(describing:)) ?? "unavailable") \(group.unit); Q1: \(summary.lowerQuartile.map(String.init(describing:)) ?? "unavailable"); Q3: \(summary.upperQuartile.map(String.init(describing:)) ?? "unavailable").",
                    "Basis: \(inspection.workContextBasis.rawValue); source: \(group.source); comparison: \(group.stratumLabel).",
                    "Context revision: \(workInspectionContext?.revision.uuidString ?? "unavailable"). Candidate counts use the shared selected treatment-night set; exact source endpoints govern numeric contribution."]
                    + group.rows.map { "\($0.id): \($0.contributionReason); raw state \($0.metricEvidence?.metric.state.rawValue ?? "unavailable"); actual source bounds \($0.metricEvidence?.start.map { ISO8601DateFormatter().string(from: $0) } ?? "unavailable") to \($0.metricEvidence?.end.map { ISO8601DateFormatter().string(from: $0) } ?? "unavailable")." }
                result.append(try .init(id: "work-comparison:" + hash,
                    title: scope + " • " + metric.rawValue + " • " + group.phase.label + " • " + group.position,
                    lines: lines, source: group.source, definitionVersion: group.definitionVersion,
                    recordIDs: group.observationIDs + [workInspectionContext?.revision.uuidString].compactMap { $0 }))
            }
            if !comparison.duplicateIDs.isEmpty || !comparison.unplacedIDs.isEmpty || !comparison.conflictingIDs.isEmpty {
                let lines = ["Duplicate IDs: " + comparison.duplicateIDs.joined(separator: ", "),
                    "Conflicting IDs: " + comparison.conflictingIDs.joined(separator: ", "),
                    "Unplaced IDs: " + comparison.unplacedIDs.joined(separator: ", ")]
                    + comparison.rawObservations.map { "\($0.id): raw value \($0.metricEvidence?.metric.value.map(String.init(describing:)) ?? "unknown"); state \($0.metricEvidence?.metric.state.rawValue ?? "unavailable"); \($0.contributionReason)." }
                result.append(try .init(id: "work-comparison:identity:" + metric.rawValue, title: "Work comparison identity review • " + metric.rawValue,
                    lines: lines, source: "Shared dashboard work-cycle projection", definitionVersion: "work-cycle-report.v1",
                    recordIDs: comparison.rawObservations.map(\.id)))
            }
            if comparison.observations.isEmpty {
                result.append(try .init(id: "work-comparison:empty:" + metric.rawValue, title: "Work comparison • " + metric.rawValue,
                    lines: ["No candidate observations match the captured selection. No expected work nights or zero measurements were invented.",
                        "Basis: \(inspection.workContextBasis.rawValue); source: \(sleepSource.rawValue); partial values \(inspection.includePartialMetrics ? "included" : "excluded").",
                        "Context revision: \(workInspectionContext?.revision.uuidString ?? "unavailable")."],
                    source: "Shared dashboard work-cycle projection", definitionVersion: "work-cycle-report.v1", recordIDs: []))
            }
        }
        return result
    }
}
