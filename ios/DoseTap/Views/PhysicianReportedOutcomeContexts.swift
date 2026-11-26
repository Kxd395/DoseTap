import Foundation
import CryptoKit
import DoseCore

@MainActor
extension DashboardAnalyticsModel {
    func physicianWorkCategoryContexts(for period: PhysicianReportPeriod) throws -> [PhysicianReportContext] {
        var result: [PhysicianReportContext] = []
        for metric in ContextMorningMetric.allCases where !metric.duration {
            for monthly in [false, true] {
                guard let report = workCycleCategoryReport(metric: metric, period: period, monthly: monthly) else { throw PhysicianReviewError.invalidRevision }
                let scope = monthly ? "Monthly" : "Full period"
                for group in report.comparison.groups {
                    let identity = [metric.rawValue, String(monthly), group.id].joined(separator: "|")
                    let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
                    let categories = group.categoryCounts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
                    let lines = ["\(group.eligible.count)/\(group.observations.count) observations eligible; \(group.excludedCount) excluded; \(report.knownBlocks(for: group.eligible.map(\.id)).count) distinct known blocks among eligible observations.",
                        "Original eligible categories: " + (categories.isEmpty ? "none confirmed" : categories.joined(separator: "; ")),
                        "Work basis: \(report.basis.rawValue); context: \(group.context); compatible stratum: \(group.stratum); source: \(group.source).",
                        "Categorical observations are not numerical scores. Missing assessment timestamps remain unplaced; monthly labels use treatment dates for context only."]
                        + group.observations.map { row in
                            let original = report.sourceRows.first { $0.id == row.id && $0.category == row.category }
                            return "\(row.id): original category \(row.category ?? "unavailable"); source state \(original?.state.rawValue ?? "unavailable"); report state \(row.state.rawValue); exclusion \(report.comparison.exclusionReason(row) ?? "none"); \(row.relationship)."
                        }
                    result.append(try .init(id: "work-category:" + hash, title: scope + " • " + metric.rawValue + " • " + group.context,
                        lines: lines, source: group.source, definitionVersion: ContextOutcomeComparison.derivationVersion + ":work-phase-position",
                        recordIDs: group.observations.map(\.id)))
                }
                if report.comparison.groups.isEmpty {
                    result.append(try .init(id: "work-category:empty:" + metric.rawValue + ":" + String(monthly),
                        title: scope + " • " + metric.rawValue, lines: ["No matching categorical observations; no responses or zeros inferred.",
                            "Work basis: " + report.basis.rawValue + "; " + report.comparison.filterDescription],
                        source: "Shared categorical work comparison", definitionVersion: ContextOutcomeComparison.derivationVersion, recordIDs: []))
                }
            }
        }
        return result
    }

    func physicianAssessedNapContexts(for period: PhysicianReportPeriod) throws -> [PhysicianReportContext] {
        let report = try workCycleNapDayReport(period: period)
        let iso = ISO8601DateFormatter()
        var result = [try PhysicianReportContext(id: "nap-assessment-coverage", title: "Independent nap assessment coverage",
            lines: ["\(report.assessedDayCount)/\(report.rows.count) recorded original day/timezone identities have a fully covered, evidence-bound reviewed episode count.",
                "No nap-to-work association exists; every day retains Unknown work context. Missing days and partial boundary days are not zero-count days.",
                "Exact period: \(report.window.start.map(iso.string) ?? "unavailable") to \(iso.string(from: report.window.endExclusive)) exclusive; source cutoff \(iso.string(from: report.window.asOf)).",
                "Read document revision: \(report.documentRevision?.uuidString ?? "unavailable"). Planned, unplanned, rest-attempt and unknown intent remain separate."],
            source: "Shared original civil-day nap projection", definitionVersion: "original_civil_day_nap_records_v1",
            recordIDs: [report.documentRevision?.uuidString].compactMap { $0 })]
        let months = Dictionary(grouping: report.rows) { String($0.day.prefix(7)) + " • " + $0.timeZoneID }
        for month in months.keys.sorted() {
            let rows = months[month] ?? []
            let lines = rows.map { row in
                let intents = [NapIntent.planned, .unplanned, .rest, .unknown].map { "\($0.rawValue): \(row.intentCounts[$0] ?? 0)" }.joined(separator: "; ")
                return "\(row.day) · \(row.timeZoneID): reviewed episode count \(row.recordCount.map(String.init) ?? "unavailable"); \(row.review.rawValue); full original-day coverage \(row.completePeriodCoverage); \(row.reason). Retained record intent categories: \(intents). Review recorded \(row.recordedAt.map(iso.string) ?? "unavailable"); work context \(row.phase.label)."
            }
            result.append(try .init(id: "nap-assessment-month:" + month, title: "Nap day detail • " + month,
                lines: lines, source: "Shared original civil-day nap projection", definitionVersion: "original_civil_day_nap_records_v1",
                recordIDs: rows.flatMap { [$0.reviewID?.uuidString].compactMap { $0 } + $0.episodeIDs + $0.evidenceKeys + $0.sourceEventIDs }))
        }
        return result
    }
}
