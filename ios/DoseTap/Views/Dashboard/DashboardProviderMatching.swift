import Foundation

extension HealthKitService.SleepNightSummary {
    var associationFingerprint: String {
        dashboardFingerprint([id, String(totalSleepMinutes), String(wakeCount), derivationVersion ?? "",
            observationEnd.map { String($0.timeIntervalSince1970) } ?? "", finalWakeBasis ?? "",
            bedTime.map { String($0.timeIntervalSince1970) } ?? "", sleepOnset.map { String($0.timeIntervalSince1970) } ?? "",
            firstWake.map { String($0.timeIntervalSince1970) } ?? "", finalWake.map { String($0.timeIntervalSince1970) } ?? ""]
            + recordedIntervals.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
                .flatMap { [String($0.start.timeIntervalSince1970), String($0.end.timeIntervalSince1970), String($0.asleep)] })
    }
}
extension WHOOPNightSummary {
    var associationFingerprint: String {
        dashboardFingerprint([id, String(date.timeIntervalSince1970), String(totalSleepMinutes), String(remMinutes),
            String(deepMinutes), String(lightMinutes), String(awakeMinutes), String(hasCompleteSleepStages)])
    }
}

extension DashboardNightAggregate {
    var unmatchedProviderEvidence: (provider: String, episode: String, fingerprint: String)? {
        guard sessionID == nil, !identityNeedsReview else { return nil }
        if let healthSummary { return ("apple-health", healthSummary.id, healthSummary.associationFingerprint) }
        if let whoopSummary { return ("whoop", "whoop:\(whoopSummary.id)", whoopSummary.associationFingerprint) }
        return nil
    }
}

extension DashboardAnalyticsModel {
    func saveProviderAssociation(providerRowID: String, sessionID: String) throws {
        guard let provider = nights.first(where: { $0.id == providerRowID }),
              let evidence = provider.unmatchedProviderEvidence,
              providerSnapshotIsCurrent(evidence.provider == "apple-health" ? .health : .whoop),
              let displayed = nights.first(where: { $0.sessionID == sessionID }) else { throw ExportReadError.unreadable }
        let snapshot = try sessionRepo.dashboardIdentitySnapshot()
        guard let current = snapshot.sessions.first(where: { $0.sessionID == sessionID }), !current.needsReview,
              current.sessionDate == provider.sessionDate, current.fingerprint == displayed.localFingerprint else {
            throw ExportReadError.unreadable
        }
        let previous = snapshot.associations.first { $0.episodeID == evidence.episode }
        let match = DashboardProviderAssociation(episodeID: evidence.episode, provider: evidence.provider,
            sessionID: sessionID, sessionDate: current.sessionDate, sessionFingerprint: current.fingerprint,
            episodeFingerprint: evidence.fingerprint, revision: UUID().uuidString)
        try sessionRepo.saveDashboardAssociation(match, expectedRevision: previous?.revision)
        refresh()
    }
    func removeProviderAssociation(providerEpisodeID: String) throws {
        let snapshot = try sessionRepo.dashboardIdentitySnapshot()
        guard let match = snapshot.associations.first(where: { $0.episodeID == providerEpisodeID }) else { throw ExportReadError.unreadable }
        try sessionRepo.removeDashboardAssociation(match)
        refresh()
    }
}
