import Foundation
import DoseCore

enum WorkCycleMetric: String, CaseIterable {
    case mainSleep = "Main sleep", doseInterval = "D1–D2 interval", sleepAfterDose2 = "Sleep after Dose 2"
}

extension DashboardAnalyticsModel {
    func workCycleComparisonIssue(metric: WorkCycleMetric) -> String? {
        if let inspectionFilterIssue { return inspectionFilterIssue }
        guard workContextReadReady, workInspectionAsOf == reportingAsOf else {
            return workContextIssue ?? "Refresh work context before comparing observations."
        }
        guard contextReadReady else { return "Comparison context is awaiting a complete local refresh." }
        guard doseReviewReadReady else { return "Dose evidence is awaiting a complete local refresh." }
        return nil
    }

    /// One bridge for the phone and physician report; no additional storage/provider reads.
    func workCycleComparison(metric: WorkCycleMetric, period: PhysicianReportPeriod? = nil) -> WorkCycleComparison? {
        projectWorkCycle(nights: visibleInspectionNights, metric: metric, period: period)
    }
    /// Domain values only: shared filters must not move comparison axes.
    func workCycleAxisObservations(metric: WorkCycleMetric) -> [WorkCycleObservation]? {
        projectWorkCycle(nights: populatedNights, metric: metric, period: reportingPeriod)?.observations
    }
    private func projectWorkCycle(nights: [DashboardNightAggregate], metric: WorkCycleMetric,
                                  period: PhysicianReportPeriod?) -> WorkCycleComparison? {
        guard workCycleComparisonIssue(metric: metric) == nil else { return nil }
        let document = workInspectionContext
        let associations = document?.associationsBySleepID(Set(nights.map(\.id)), asOf: reportingAsOf) ?? [:]
        let snapshots = Dictionary(uniqueKeysWithValues: (document?.planSnapshots ?? []).map { ($0.id, $0) })
        let source = sleepSource
        let freshness: DashboardSleepMetricProjection.Freshness = providerSnapshotIsCurrent(source == .appleHealth ? .health : .whoop) ? .current : .stale
        let rows = nights.map { night -> WorkCycleObservation in
            let classification = workClassification(for: night.id)
            let association = associations[night.id]
            let snapshot = association?.planSnapshotID.flatMap { snapshots[$0] }
            let evidence = workCycleEvidence(night, metric: metric, source: source, freshness: freshness)
            let context: DashboardContextStratum
            if metric == .doseInterval, let start = evidence.start, let end = evidence.end, start < end,
               let timeline = contextTimeline {
                context = timeline.stratum(observationID: night.id, start: start, end: end, content: night.contentObservations)
            } else { context = night.contextStratum(for: source) }
            let intervalEvidence = workCycleEvidence(night, metric: .doseInterval, source: source, freshness: freshness)
            var row = WorkCycleObservation(sleepID: night.id, sleepDate: night.sessionDate,
                phase: classification?.phase ?? .unknown, position: classification?.positionLabel ?? "Unknown / review",
                blockID: classification?.blockID, value: nil, rosterID: classification?.rosterID,
                detail: classification?.detail ?? "No reviewed main-sleep work association.", associationID: association?.id,
                contextSnapshotAt: inspection.workContextBasis == .planned ? (association?.planSnapshotID == nil ? association?.plannedAt : snapshot?.capturedAt) : reportingAsOf,
                isOverride: classification?.isOverride ?? false, stratumID: context.id, stratumLabel: context.label,
                planSnapshotID: inspection.workContextBasis == .planned ? association?.planSnapshotID : nil)
            row.intervalMinutes = row.applying(intervalEvidence, includePartial: false, period: period).value
            return row.applying(evidence, includePartial: inspection.includePartialMetrics, period: period)
        }
        return WorkCycleComparison(observations: rows)
    }

    private func appleMainSleepBounds(_ summary: HealthKitService.SleepNightSummary?) -> DateInterval? {
        guard let summary else { return nil }
        let asleep = summary.recordedIntervals.filter(\.asleep)
        guard !asleep.isEmpty, asleep.allSatisfy({ $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite
            && $0.start < $0.end && $0.end <= reportingAsOf }),
              let first = asleep.map(\.start).min(), let last = asleep.map(\.end).max(),
              summary.sleepOnset.map({ $0 == first }) != false,
              summary.finalWake.map({ $0 == last }) != false else { return nil }
        return DateInterval(start: first, end: last)
    }

    private func workCycleEvidence(_ night: DashboardNightAggregate, metric: WorkCycleMetric,
                                   source: DashboardSleepSource, freshness: DashboardSleepMetricProjection.Freshness) -> WorkCycleMetricEvidence {
        let pattern = night.dosePattern
        if metric == .doseInterval {
            let first = pattern.pairIDs.first.flatMap { id in night.doseEvents.first { $0.id == id }?.timestamp }
            let last = pattern.pairIDs.count == 2 ? night.doseEvents.first { $0.id == pattern.pairIDs[1] }?.timestamp : nil
            return .init(metricID: "dose1_to_dose2", source: "patient-reported-administrations", definitionVersion: DashboardDosePattern.version,
                metric: pattern.interval, start: first, end: last)
        }
        let projection = DosePatternPresentation.sleepProjection(night, source: source,
            outcome: metric == .mainSleep ? .mainSleep : .postDose2, freshness: freshness)
        let start: Date?, end: Date?
        if metric == .sleepAfterDose2 {
            start = night.dose2Time
            end = source == .appleHealth ? night.outcome?.finalWakeAt ?? night.healthSummary?.finalWake : nil
        } else {
            // Only named observed sleep endpoints bound the main-sleep total.
            // WHOOP's existing summary has no original end; exact-period contribution stays unavailable.
            let bounds = source == .appleHealth ? appleMainSleepBounds(night.healthSummary) : nil
            start = bounds?.start; end = bounds?.end
        }
        return .init(metricID: projection.definition.rawValue, source: projection.source.rawValue,
            definitionVersion: projection.derivationVersion + ":" + projection.boundaryBasis.rawValue,
            metric: projection.metric, start: start, end: end)
    }
}
