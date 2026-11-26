import Foundation
import DoseCore

extension DashboardNightAggregate {
    func contextStratum(for source: DashboardSleepSource) -> DashboardContextStratum {
        // WHOOP summary transport does not supply the episode's original end boundary.
        source == .appleHealth ? contextStratum : .unknown(observationID: id + ":whoop")
    }
    mutating func applyContext(_ timeline: DashboardContextTimeline) {
        contextProjection = nil; contextAnnotations = []
        guard !identityNeedsReview, !outcomeReadFailed, healthSummary != nil || whoopSummary == nil else { return }
        // Dose/provider observations define the envelope; form completion and treatment dates do not.
        var points = [dose1Time, dose2Time].compactMap { $0 }
        if let health = healthSummary {
            points += health.recordedIntervals.flatMap { [$0.start, $0.end] }
            points += [health.bedTime, health.sleepOnset, health.observationEnd, health.finalWake].compactMap { $0 }
        }
        guard let start = points.min(), let end = points.max(), start < end else { return }
        contextProjection = timeline.stratum(observationID: id, start: start, end: end, content: contentObservations)
        let sourceIDs = Set(contextStratum.sourceRecordIDs + contentObservations.map(\.sourceRecordID))
        contextAnnotations = timeline.annotations.filter { value in
            if !sourceIDs.isDisjoint(with: value.sourceRecordIDs) { return true }
            return value.effectiveAt.map { $0 >= start && $0 < end } ?? false
        }
    }
}
