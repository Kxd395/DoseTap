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

struct DashboardProviderMatchReview {
    let providerRowID: String
    let sessionID: String
    let episodeFingerprint: String
    let sessionFingerprint: String
    let associationRevision: String?
}

extension DashboardAnalyticsModel {
    func providerMatchReview(providerRowID: String, sessionID: String) throws -> DashboardProviderMatchReview {
        guard let source = nights.first(where: { $0.id == providerRowID }), let evidence = source.unmatchedProviderEvidence,
              let target = nights.first(where: { $0.sessionID == sessionID }), let fingerprint = target.localFingerprint,
              !target.identityNeedsReview, source.sessionDate == target.sessionDate,
              providerSnapshotIsCurrent(evidence.provider == "apple-health" ? .health : .whoop) else { throw ExportReadError.unreadable }
        return .init(providerRowID: providerRowID, sessionID: sessionID, episodeFingerprint: evidence.fingerprint,
            sessionFingerprint: fingerprint, associationRevision: savedProviderAssociations.first { $0.episodeID == evidence.episode }?.revision)
    }
    func saveProviderAssociation(_ review: DashboardProviderMatchReview) throws {
        let providerRowID = review.providerRowID, sessionID = review.sessionID
        guard let provider = nights.first(where: { $0.id == providerRowID }),
              let evidence = provider.unmatchedProviderEvidence,
              providerSnapshotIsCurrent(evidence.provider == "apple-health" ? .health : .whoop),
              let displayed = nights.first(where: { $0.sessionID == sessionID }),
              evidence.fingerprint == review.episodeFingerprint, displayed.localFingerprint == review.sessionFingerprint else { throw ExportReadError.unreadable }
        let snapshot = try sessionRepo.dashboardIdentitySnapshot()
        guard let current = snapshot.sessions.first(where: { $0.sessionID == sessionID }), !current.needsReview,
              current.sessionDate == provider.sessionDate, current.fingerprint == displayed.localFingerprint else {
            throw ExportReadError.unreadable
        }
        let previous = snapshot.associations.first { $0.episodeID == evidence.episode }
        guard previous?.revision == review.associationRevision else { throw ExportReadError.unreadable }
        let match = DashboardProviderAssociation(episodeID: evidence.episode, provider: evidence.provider,
            sessionID: sessionID, sessionDate: current.sessionDate, sessionFingerprint: current.fingerprint,
            episodeFingerprint: evidence.fingerprint, revision: UUID().uuidString)
        try sessionRepo.saveDashboardAssociation(match, expectedRevision: review.associationRevision)
        refresh()
    }
    func removeProviderAssociation(providerEpisodeID: String, expectedRevision: String) throws {
        let snapshot = try sessionRepo.dashboardIdentitySnapshot()
        guard let match = snapshot.associations.first(where: { $0.episodeID == providerEpisodeID }),
              match.revision == expectedRevision else { throw ExportReadError.unreadable }
        try sessionRepo.removeDashboardAssociation(match)
        refresh()
    }
}
