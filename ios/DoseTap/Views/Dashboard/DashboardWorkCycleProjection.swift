import Foundation
import DoseCore

enum WorkCycleMetric: String, CaseIterable {
    case mainSleep = "Main sleep", doseInterval = "D1–D2 interval", sleepAfterDose2 = "Sleep after Dose 2"
    case shiftEndToSleep = "Actual shift end to main sleep", timeBetweenShifts = "Actual time between linked shifts"
    case recordedWork24h = "Recorded work in prior 24 hours", dose2ToRequiredWake = "Dose 2 to recorded required wake"
    var isProviderSleep: Bool { self == .mainSleep || self == .sleepAfterDose2 }
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
        let actuals = metric.isProviderSleep || metric == .doseInterval || metric == .dose2ToRequiredWake ? [:] : document?.timingEvidences(for: Array(associations.values), lookbackSeconds: 86400, asOf: reportingAsOf) ?? [:]
        let source = sleepSource
        let freshness: DashboardSleepMetricProjection.Freshness = providerSnapshotIsCurrent(source == .appleHealth ? .health : .whoop) ? .current : .stale
        let rows = nights.map { night -> WorkCycleObservation in
            let classification = workClassification(for: night.id)
            let association = associations[night.id]
            let snapshot = association?.planSnapshotID.flatMap { snapshots[$0] }
            let actual = association.flatMap { actuals[$0.id] }
            let evidence = workCycleEvidence(night, metric: metric, source: source, freshness: freshness, actual: actual)
            let context: DashboardContextStratum
            if !metric.isProviderSleep, let start = evidence.start, let end = evidence.end, start < end,
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
            row.classificationVersion = classification?.classificationVersion ?? 1; row.firstShiftDate = classification?.firstShiftDate
            row.metricSourceRecordIDs = metric == .dose2ToRequiredWake ? replayWakeTarget(for: night).sources.map { $0.eventID + ":" + $0.revision.uuidString }
                : metric == .doseInterval ? night.dosePattern.pairIDs : metric.isProviderSleep ? [] : actual?.sourceRevisionIDs.map(\.uuidString) ?? []
            row.intervalMinutes = row.applying(intervalEvidence, includePartial: false, period: period, asOf: reportingAsOf).value
            return row.applying(evidence, includePartial: inspection.includePartialMetrics, period: period, asOf: reportingAsOf)
        }
        return WorkCycleComparison(observations: rows)
    }

    private func appleMainSleepBounds(_ summary: HealthKitService.SleepNightSummary?) -> (bounds: DateInterval?, issue: String?) {
        guard let summary else { return (nil, nil) }
        let named = [summary.sleepOnset, summary.finalWake].compactMap { $0 }
        guard named.allSatisfy({ $0.timeIntervalSince1970.isFinite && $0 <= reportingAsOf }),
              summary.sleepOnset.flatMap({ start in summary.finalWake.map { start < $0 } }) != false else {
            return (nil, "invalid_named_sleep_bounds")
        }
        let asleep = summary.recordedIntervals.filter(\.asleep)
        guard !asleep.isEmpty else { return (nil, nil) }
        guard asleep.allSatisfy({ $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite
            && $0.start < $0.end && $0.end <= reportingAsOf }),
              let first = asleep.map(\.start).min(), let last = asleep.map(\.end).max() else {
            return (nil, "invalid_recorded_sleep_bounds")
        }
        guard summary.sleepOnset.map({ $0 == first }) != false,
              summary.finalWake.map({ $0 == last }) != false else {
            return (nil, "inconsistent_recorded_sleep_bounds")
        }
        return (DateInterval(start: first, end: last), nil)
    }

    private func workCycleEvidence(_ night: DashboardNightAggregate, metric: WorkCycleMetric,
                                   source: DashboardSleepSource, freshness: DashboardSleepMetricProjection.Freshness, actual: WorkShiftTimingEvidence? = nil) -> WorkCycleMetricEvidence {
        let pattern = night.dosePattern
        if metric == .doseInterval {
            let first = pattern.pairIDs.first.flatMap { id in night.doseEvents.first { $0.id == id }?.timestamp }
            let last = pattern.pairIDs.count == 2 ? night.doseEvents.first { $0.id == pattern.pairIDs[1] }?.timestamp : nil
            return .init(metricID: "dose1_to_dose2", source: "patient-reported-administrations", definitionVersion: DashboardDosePattern.version,
                metric: pattern.interval, start: first, end: last)
        }
        if !metric.isProviderSleep {
            if metric == .dose2ToRequiredWake {
                let target = replayWakeTarget(for: night)
                let second = pattern.pairIDs.count == 2 ? night.doseEvents.first { $0.id == pattern.pairIDs[1] }?.timestamp : nil
                let end = target.requiredWake
                let value = second.flatMap { start in end.flatMap { $0 >= start ? $0.timeIntervalSince(start) / 60 : nil } }
                let state: DashboardMetricState = pattern.interval.state == .notApplicable ? .notApplicable
                    : pattern.interval.state == .needsReview || target.state == .needsReview || second.flatMap({ start in end.map { $0 < start } }) == true ? .needsReview
                    : value == nil ? .unavailable : .available
                return .init(metricID: "dose2_to_recorded_required_wake", source: "saved_work_wake_warning", definitionVersion: DashboardRecordedWakeTarget.version,
                    metric: .init(value: value, state: state, reason: state == .available ? "saved_required_wake_not_actual_awakening" : target.reason, unit: "minutes"), start: second, end: end)
            }
            let evidence = metric == .shiftEndToSleep ? actual?.shiftEndToMainSleep : metric == .timeBetweenShifts ? actual?.betweenShifts : actual?.recordedWorkMinutes
            return evidence ?? .init(metricID: metric.rawValue, source: "reviewed_actual_shift_events", definitionVersion: "actual_shift_intervals_v1",
                metric: .init(value: nil, state: .unavailable, reason: "explicit_main_sleep_shift_links_unavailable", unit: "minutes"), start: nil, end: nil)
        }
        let projection = DosePatternPresentation.sleepProjection(night, source: source,
            outcome: metric == .mainSleep ? .mainSleep : .postDose2, freshness: freshness)
        let start: Date?, end: Date?
        var boundaryIssue: String?
        var metricValue = projection.metric
        if metric == .sleepAfterDose2 {
            start = night.dose2Time
            end = source == .appleHealth ? night.outcome?.finalWakeAt ?? night.healthSummary?.finalWake : nil
        } else {
            if source == .appleHealth {
                let checked = appleMainSleepBounds(night.healthSummary)
                start = checked.bounds?.start; end = checked.bounds?.end; boundaryIssue = checked.issue
            } else {
                let bounds = night.whoopSummary?.originalSleepInterval
                start = bounds?.start; end = bounds?.end
                if let reason = night.whoopSummary?.sleepEvidenceReviewReason {
                    metricValue = .init(value: nil, state: .needsReview, reason: reason, unit: "minutes")
                    boundaryIssue = "invalid_whoop_sleep_evidence"
                }
            }
        }
        return .init(metricID: projection.definition.rawValue, source: projection.source.rawValue,
            definitionVersion: projection.derivationVersion + ":" + projection.boundaryBasis.rawValue,
            metric: metricValue, start: start, end: end, boundaryIssue: boundaryIssue)
    }
}

#if DEBUG && targetEnvironment(simulator)
extension DashboardAnalyticsModel {
    /// Display-only fixture: no repository mutation and no attendance inference from user data.
    func workEventDisplayFixture() -> WorkContextDocument? {
        guard let night = nights.first, let start = night.healthSummary?.sleepOnset, let end = night.healthSummary?.finalWake else { return nil }
        var before = WorkShiftEvent(timeZoneIdentifier: reportingTimeZone.identifier, recordedAt: start.addingTimeInterval(-86400))
        before.workDate = night.sessionDate; before.blockID = "synthetic-explicit-block"; before.firstShiftDate = night.sessionDate
        before.position = 1; before.blockShiftCount = 2; before.scheduledStart = start.addingTimeInterval(-28800); before.scheduledEnd = start.addingTimeInterval(-3600)
        var after = before; after.id = UUID(); after.shiftID = UUID(); after.position = 2
        after.scheduledStart = end.addingTimeInterval(3600); after.scheduledEnd = end.addingTimeInterval(32400)
        var association = WorkSleepAssociation(sleepID: night.id, precedingDate: night.sessionDate, followingDate: night.sessionDate,
            timeZoneIdentifier: reportingTimeZone.identifier, plannedAt: start.addingTimeInterval(-3600), recordedAt: reportingAsOf)
        association.eventContext = .init(mainSleepStart: start, mainSleepEnd: end, precedingStatus: .work, followingStatus: .work,
            precedingShiftID: before.shiftID, followingShiftID: after.shiftID, wakingPeriodsReviewed: true)
        var document = WorkContextDocument(); document.schemaVersion = 3; document.shiftEvents = [before, after]; document.associations = [association]
        return document
    }
}
#endif
