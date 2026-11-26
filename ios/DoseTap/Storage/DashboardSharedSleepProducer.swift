import Foundation
import SQLite3
import DoseCore

@MainActor
extension EventStorage {
    /// Called only inside the raw-row export snapshot transaction. No HealthKit query,
    /// preferences, cache writes, date-based matching or association repair occurs here.
    func dashboardSharedSleepEpisodes(evidence: DashboardSleepEvidence, capturedAt: Date) throws -> [DashboardSharedSleepEpisode] {
        guard databaseInitializationFailure == nil, let db, sqlite3_get_autocommit(db) == 0 else {
            throw ExportReadError.unreadable
        }
        try evidence.validate(capturedAt: capturedAt)
        guard let zone = TimeZone(identifier: evidence.timeZoneID) else { throw ExportReadError.unreadable }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let segments = evidence.samples.map { sample in
            HealthKitService.SleepSegment(start: sample.start, end: sample.end,
                stage: .from(hkValue: sample.rawCategory), source: sample.origin.sourceName, evidence: sample)
        }
        let days = Int(ceil(evidence.queryEnd.timeIntervalSince(evidence.queryStart) / 86_400)) + 2
        let summaries = HealthKitService.dashboardSleepSummaries(segments: segments, days: days,
            through: evidence.queryEnd, calendar: calendar)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
        // Malformed unrelated legacy records must not erase the opted-in raw packet.
        // They cannot establish a reviewed local binding, so sidecars remain unbound.
        let locals = (try? dashboardLocalSessions(inTransaction: true)) ?? []
        let associations = (try? dashboardAssociations()) ?? []
        let reviews = (try? dashboardDoseReviews(now: capturedAt)) ?? [:]
        let episodeCounts = Dictionary(grouping: summaries, by: \.id).mapValues(\.count)
        var candidates: [String: DashboardProviderAssociation] = [:]
        for summary in summaries where episodeCounts[summary.id] == 1 {
            let matches = associations.filter { association in
                association.provider == "apple-health" && association.episodeID == summary.id &&
                association.episodeFingerprint == summary.associationFingerprint &&
                association.sessionDate == formatter.string(from: summary.date) &&
                UUID(uuidString: association.revision) != nil &&
                locals.filter { !$0.needsReview && $0.sessionID == association.sessionID &&
                    $0.sessionDate == association.sessionDate && $0.fingerprint == association.sessionFingerprint }.count == 1
            }
            if matches.count == 1 { candidates[summary.id] = matches[0] }
        }
        let owners = Dictionary(grouping: candidates.values, by: \.sessionID).mapValues(\.count)
        return summaries.compactMap { summary in
            guard episodeCounts[summary.id] == 1 else { return nil }
            let candidate = candidates[summary.id]
            let binding = candidate.flatMap { owners[$0.sessionID] == 1 ? $0 : nil }
            let day = formatter.string(from: summary.date)
            var episode = DashboardSharedSleepEpisode(episodeID: summary.id, treatmentDate: day, source: summary.source,
                sessionID: binding?.sessionID, associationRevision: binding.flatMap { UUID(uuidString: $0.revision) },
                intervals: summary.recordedIntervals, bedTime: summary.bedTime, sleepOnset: summary.sleepOnset,
                finalWake: summary.finalWake, observationEnd: summary.observationEnd,
                finalWakeBasis: summary.finalWakeBasis, derivationVersion: summary.derivationVersion,
                totalSleepMinutes: summary.totalSleepMinutes, queryStart: evidence.queryStart,
                queryEnd: evidence.queryEnd, completedAt: evidence.completedAt, timeZoneID: evidence.timeZoneID)
            if binding == nil, let review = reviews[summary.id]?.current {
                episode.review = DashboardSharedProviderDoseReview.project(review, episodeID: summary.id,
                    treatmentDate: day, providerFingerprint: summary.associationFingerprint, capturedAt: capturedAt)
            }
            // A malformed derivation is unavailable. Its original raw samples remain
            // in the provider section for inspection; never manufacture a sleep total.
            guard (try? episode.validate(capturedAt: capturedAt)) != nil else { return nil }
            return episode
        }
    }
}
