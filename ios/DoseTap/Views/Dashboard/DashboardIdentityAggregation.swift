import Foundation
import DoseCore

extension DashboardAnalyticsModel {
    func identityAggregates(local: [DashboardLocalSession], health: [String: HealthKitService.SleepNightSummary],
                            whoop: [String: WHOOPNightSummary], associations: [DashboardProviderAssociation] = []) -> [DashboardNightAggregate] {
        var result = local.map { session -> DashboardNightAggregate in
            let metrics = Self.deriveDoseMetrics(from: session.doses)
            let events = session.events.sorted { $0.timestamp < $1.timestamp }
            var row = DashboardNightAggregate(sessionDate: session.sessionDate,
                dose1Time: metrics.dose1Time, dose2Time: metrics.dose2Time, dose2Skipped: metrics.dose2Skipped,
                snoozeCount: metrics.snoozeCount, extraDoseCount: metrics.extraDoseCount, events: events,
                morningCheckIn: session.morning, preSleepLog: session.preSleep, healthSummary: nil, whoopSummary: nil,
                duplicateClusterCount: buildStoredEventDuplicateGroups(events: events).count,
                napSummary: SessionRepository.napSummary(events: events))
            row.sessionID = session.sessionID; row.stableID = session.id; row.doseEvents = session.doses
            row.localFingerprint = session.fingerprint
            row.sessionClosed = session.sessionClosed; row.identityNeedsReview = session.needsReview
            row.outcome = session.outcome; row.outcomeReadFailed = session.outcomeReadFailed
            return row
        }
        let indexes = Dictionary(grouping: result.indices, by: { result[$0].sessionDate })
        for key in Set(health.keys).union(whoop.keys).sorted() {
            let candidates = indexes[key] ?? []
                for source in ["health", "whoop"] {
                    guard source == "health" ? health[key] != nil : whoop[key] != nil else { continue }
                    var row = DashboardNightAggregate(sessionDate: key, dose1Time: nil, dose2Time: nil,
                        dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0, events: [], morningCheckIn: nil,
                        preSleepLog: nil, healthSummary: source == "health" ? health[key] : nil,
                        whoopSummary: source == "whoop" ? whoop[key] : nil, duplicateClusterCount: 0,
                        napSummary: .init(count: 0, totalMinutes: 0))
                    row.stableID = source == "health" ? health[key]!.id : "whoop:\(whoop[key]!.id)"
                    row.providerAssociation = candidates.isEmpty ? "Provider-only sleep; no session association"
                        : "Ambiguous session association; provider-only sleep"
                    if let evidence = row.unmatchedProviderEvidence,
                       let match = associations.first(where: { $0.episodeID == evidence.episode }),
                       match.provider == evidence.provider, match.episodeFingerprint == evidence.fingerprint,
                       let index = result.firstIndex(where: { $0.sessionID == match.sessionID && $0.sessionDate == key }),
                       !result[index].identityNeedsReview, result[index].localFingerprint == match.sessionFingerprint {
                        if source == "health" { result[index].healthSummary = row.healthSummary }
                        else { result[index].whoopSummary = row.whoopSummary }
                        result[index].providerAssociation = "Explicit provider match · v1"
                    } else { result.append(row) }
                }
        }
        return result.sorted { $0.sessionDate == $1.sessionDate ? $0.id < $1.id : $0.sessionDate > $1.sessionDate }
    }
}
