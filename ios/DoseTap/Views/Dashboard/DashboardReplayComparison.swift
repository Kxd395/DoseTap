import Foundation
import DoseCore

enum ReplayComparedOutcome: String, Codable, CaseIterable, Identifiable {
    case mainSleep = "Selected main sleep", sleepiness = "Recorded sleepiness 0–10"
    var id: String { rawValue }
}

/// One exact session/episode row, frozen identically for plots, source tables and exports.
struct ReplayComparisonRow: Codable, Identifiable {
    let observationID: String
    let replayID: String
    let treatmentDate: String
    let interval: DashboardIntervalObservation
    let outcome: ReplayComparedOutcome
    let metric: DashboardMetricValue
    let source: String
    let sourceRecordID: String?
    let observedAt: Date?
    let capturedAt: Date?
    let definition: String
    let contextID: String
    let includePartial: Bool
    let referenceVersion: String?
    let referenceGroup: String?
    var dosePattern: DashboardDosePattern.Pattern? = nil
    var workBeforeSleep: DashboardWorkBeforeSleep = .unknown
    var isConfirmedSingle: Bool {
        [.singlePlanned, .singleOmitted, .singleUnknownPlan].contains(dosePattern)
    }
    /// Zero is a labeled category position, never a measured interval.
    var sleepComparisonX: Double? {
        outcome == .mainSleep && interval.preset == .dose1ToDose2 && isConfirmedSingle ? 0 : x
    }
    var id: String { observationID }
    var x: Double? { interval.eligibleMinutes(includePartial: includePartial) }
    var y: Double? {
        guard metric.state == .available || (includePartial && metric.state == .partial),
              let value = metric.value, value.isFinite else { return nil }
        return value
    }
    var paired: Bool { sleepComparisonX != nil && y != nil }
    var binLower: Double? {
        guard let x else { return nil }
        let lower = floor(x / 30) * 30
        return lower.isFinite && (lower + 30).isFinite && lower + 30 > lower ? lower : nil
    }
    static func binLabel(_ lower: Double) -> String { "\(lower.formatted())–<\((lower + 30).formatted()) min" }
    var csv: String {
        func number(_ value: Double?) -> String { value.map(String.init(describing:)) ?? "" }
        func stamp(_ value: Date?) -> String { value.map { $0.timeIntervalSinceReferenceDate.isFinite ? ISO8601DateFormatter().string(from: $0) : "invalid_timestamp" } ?? "" }
        return ReportCSV.row(["observation_id", "interval_preset", "interval_minutes", "interval_state", "interval_reason", "start_id", "end_id", "reference_version", "reference_group", "outcome", "outcome_value", "outcome_unit", "outcome_state", "outcome_reason", "outcome_source", "outcome_source_id", "outcome_observed_at", "outcome_captured_at", "definition", "context_id", "include_partial", "paired_included", "dose_pattern", "work_before_sleep", "single_dose_category"]) + "\n"
            + ReportCSV.row([observationID, interval.preset.rawValue, number(interval.minutes), interval.state.rawValue, interval.reason,
                interval.startID ?? "", interval.endID ?? "", referenceVersion ?? "", referenceGroup ?? "",
                outcome.rawValue, number(metric.value), metric.unit, metric.state.rawValue, metric.reason, source, sourceRecordID ?? "",
                stamp(observedAt), stamp(capturedAt), definition, contextID, String(includePartial), String(paired), dosePattern?.rawValue ?? "", workBeforeSleep.rawValue, String(isConfirmedSingle)])
    }
}

extension DashboardAnalyticsModel {
    func replayComparison(for snapshot: DashboardReplaySnapshot, outcome: ReplayComparedOutcome,
                          preset: DashboardIntervalPreset) -> ReplayComparisonRow? {
        let matches = nights.filter { $0.replayID == snapshot.sessionID }
        guard matches.count == 1, let night = matches.first else { return nil }
        return replayComparison(for: snapshot, night: night, outcome: outcome, preset: preset)
    }

    func replayComparisons(for snapshots: [DashboardReplaySnapshot], outcome: ReplayComparedOutcome,
                           preset: DashboardIntervalPreset) -> [ReplayComparisonRow] {
        let indexed = Dictionary(grouping: nights, by: \.replayID)
        return snapshots.compactMap { snapshot in
            guard let matches = indexed[snapshot.sessionID], matches.count == 1, let night = matches.first else { return nil }
            return replayComparison(for: snapshot, night: night, outcome: outcome, preset: preset)
        }
    }

    private func replayComparison(for snapshot: DashboardReplaySnapshot, night: DashboardNightAggregate,
                                  outcome: ReplayComparedOutcome, preset: DashboardIntervalPreset) -> ReplayComparisonRow {
        let source = sleepSource == .appleHealth ? DashboardProviderAccess.Provider.health : .whoop
        let capture = source == .health ? healthSnapshot?.window.asOf : whoopSnapshot?.window.asOf
        let fixture = DashboardReplayUITestFixture.enabled
        let freshness: DashboardSleepMetricProjection.Freshness = fixture || providerSnapshotIsCurrent(source) ? .current : .stale
        let metric: DashboardMetricValue
        let sourceName: String
        let sourceID: String?
        let observed: Date?
        let definition: String
        if outcome == .mainSleep {
            let projection = DosePatternPresentation.sleepProjection(night, source: sleepSource, outcome: .mainSleep, freshness: freshness)
            metric = projection.metric; sourceName = projection.source.rawValue
            sourceID = source == .health ? night.healthSummary?.id : night.whoopSummary?.sleepId
            observed = source == .health ? night.healthSummary?.sleepOnset : night.whoopSummary?.originalSleepInterval?.start
            definition = [projection.definition.rawValue, projection.boundaryBasis.rawValue, projection.derivationVersion].joined(separator: ":")
        } else {
            sourceName = "Patient-reported night outcome diary"; sourceID = night.sessionID
            observed = night.outcome?.assessedAt; definition = "night-outcome.sleepiness_0_10.v1"
            if night.identityNeedsReview || night.outcomeReadFailed || night.outcome?.validationError(now: snapshot.asOf) != nil {
                metric = .init(value: nil, state: .needsReview, reason: "Outcome identity, read or occurrence requires review", unit: "0–10 ordinal score")
            } else if let rating = night.outcome?.sleepiness, observed != nil, sourceID != nil {
                metric = .init(value: Double(rating), state: .available, reason: "Explicit rating and assessment time; not ESS", unit: "0–10 ordinal score")
            } else {
                metric = .init(value: nil, state: .unavailable, reason: "No explicit timed sleepiness assessment for this session", unit: "0–10 ordinal score")
            }
        }
        return .init(observationID: night.id, replayID: snapshot.sessionID, treatmentDate: snapshot.treatmentDate,
            interval: snapshot.interval(preset), outcome: outcome, metric: metric, source: sourceName,
            sourceRecordID: sourceID, observedAt: observed,
            capturedAt: outcome == .mainSleep ? capture ?? (fixture ? snapshot.asOf : nil) : snapshot.asOf,
            definition: definition, contextID: night.contextStratum(for: sleepSource).id,
            includePartial: inspection.includePartialMetrics, referenceVersion: snapshot.interval(preset).referenceVersion,
            referenceGroup: snapshot.interval(preset).referenceGroup,
            dosePattern: doseReviewReadReady ? night.dosePattern.pattern : nil, workBeforeSleep: workBeforeSleep(for: night.id))
    }
}
