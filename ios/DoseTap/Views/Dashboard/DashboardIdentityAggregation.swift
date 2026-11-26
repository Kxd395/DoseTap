import Foundation
import DoseCore

extension DashboardAnalyticsModel {
    func identityAggregates(local: [DashboardLocalSession], health: [String: HealthKitService.SleepNightSummary],
                            whoop: [String: WHOOPNightSummary], associations: [DashboardProviderAssociation] = [],
                            contextTimeline: DashboardContextTimeline? = nil) -> [DashboardNightAggregate] {
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
            row.contentObservations = session.contentObservations
            row.sessionActive = session.sessionActive
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
                        : "Sleep awaiting a session match"
                    if let evidence = row.unmatchedProviderEvidence,
                       let match = associations.first(where: { $0.episodeID == evidence.episode }),
                       match.provider == evidence.provider, match.episodeFingerprint == evidence.fingerprint,
                       let index = result.firstIndex(where: { $0.sessionID == match.sessionID && $0.sessionDate == key }),
                       !result[index].identityNeedsReview, result[index].localFingerprint == match.sessionFingerprint {
                        if source == "health" { result[index].healthSummary = row.healthSummary }
                        else { result[index].whoopSummary = row.whoopSummary }
                        result[index].providerAssociation = "Explicit provider match · v1"
                        result[index].providerAssociationLabels[source] = result[index].providerAssociation
                    } else if candidates.count == 1, let index = candidates.first,
                              let evidence = row.unmatchedProviderEvidence,
                              !associations.contains(where: { $0.episodeID == evidence.episode || ($0.sessionID == result[index].sessionID && $0.provider == evidence.provider) }),
                              Self.supportsAutomaticSleepMatch(session: result[index], provider: row) {
                        if source == "health" { result[index].healthSummary = row.healthSummary }
                        else { result[index].whoopSummary = row.whoopSummary }
                        result[index].providerAssociation = "Automatic time match · v1 (not manually reviewed)"
                        result[index].providerAssociationLabels[source] = result[index].providerAssociation
                    } else { result.append(row) }
                }
        }
        if let contextTimeline {
            for index in result.indices { result[index].applyContext(contextTimeline) }
        }
        return result.sorted { $0.sessionDate == $1.sessionDate ? $0.id < $1.id : $0.sessionDate > $1.sessionDate }
    }
    /// A transient primary-episode association, never a stored or reviewed relationship.
    private static func supportsAutomaticSleepMatch(session: DashboardNightAggregate, provider: DashboardNightAggregate) -> Bool {
        guard session.sessionID != nil, !session.identityNeedsReview,
              let first = session.dose1Time, first.timeIntervalSince1970.isFinite else { return false }
        let doses = session.doseEvents.filter { [CanonicalDoseEventType.dose1, .dose2, .extraDose].contains(CanonicalDoseEventType(canonicalizing: $0.eventType)) }
        let firsts = doses.filter { CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose1 }
        let seconds = doses.filter { CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose2 }
        guard firsts.count == 1, seconds.count <= 1, doses.count == firsts.count + seconds.count,
              !(session.dose2Skipped && !seconds.isEmpty) else { return false }
        let start: Date?, end: Date?
        if let health = provider.healthSummary {
            start = health.sleepOnset ?? health.bedTime
            end = health.observationEnd ?? health.finalWake
        } else {
            start = provider.whoopSummary?.originalSleepInterval?.start
            end = provider.whoopSummary?.originalSleepInterval?.end
        }
        guard let start, let end, start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              end > start, end.timeIntervalSince(start) <= 16 * 3600,
              first >= start.addingTimeInterval(-120 * 60), first <= start.addingTimeInterval(30 * 60), first < end else { return false }
        return seconds.allSatisfy { $0.timestamp.timeIntervalSince1970.isFinite && $0.timestamp > first && $0.timestamp < end }
    }

}
