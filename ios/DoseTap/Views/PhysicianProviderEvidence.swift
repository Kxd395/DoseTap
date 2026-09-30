import Foundation
import DoseCore

@MainActor
extension DashboardAnalyticsModel {
    func physicianProviderEvidence(_ night: DashboardNightAggregate, metric: WorkCycleMetric) throws -> String {
        guard metric == .mainSleep || metric == .sleepAfterDose2 else { return "" }
        let freshness: DashboardSleepMetricProjection.Freshness = providerSnapshotIsCurrent(sleepSource == .appleHealth ? .health : .whoop) ? .current : .stale
        let projection = DosePatternPresentation.sleepProjection(night, source: sleepSource,
            outcome: metric == .mainSleep ? .mainSleep : .postDose2, freshness: freshness)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        func raw<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        var lines = ["Shared measurement coverage and boundary policy (Unix-second timestamps; nonfinite raw values are strings, never contributions): " + (try raw(projection))]
        if sleepSource == .appleHealth, let summary = night.healthSummary {
            lines += ["Apple source: \(summary.source); episode derivation: \(summary.derivationVersion ?? "unavailable"); final-end basis: \(summary.finalWakeBasis ?? "unavailable").",
                "Raw original provider total: \(summary.totalSleepMinutes) minutes; recorded observation intervals: " + (try raw(summary.recordedIntervals)),
                "Named original bounds: " + (try raw(["sleepOnset": summary.sleepOnset, "finalWake": summary.finalWake, "observationEnd": summary.observationEnd]))]
        } else if sleepSource == .whoop, let summary = night.whoopSummary {
            lines += ["WHOOP sleep ID: \(summary.sleepId). Original episode end is not reported final awakening.",
                "Raw legacy total: \(summary.totalSleepMinutes) minutes; validated quantitative total: \(summary.quantitativeSleepMinutes.map(String.init(describing:)) ?? "unavailable"). Review reason: \(summary.sleepEvidenceReviewReason ?? "none recorded").",
                "Original endpoint evidence: " + (try raw(summary.endpointEvidence)), "Scoring evidence: " + (try raw(summary.stageEvidence))]
        }
        return lines.joined(separator: "\n")
    }
}
