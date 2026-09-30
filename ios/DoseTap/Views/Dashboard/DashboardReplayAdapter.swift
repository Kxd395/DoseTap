import Foundation
import DoseCore

extension DashboardNightAggregate {
    var replayID: String { sessionID ?? id }
}

extension DashboardAnalyticsModel {
    func replaySnapshot(for night: DashboardNightAggregate, reviewed: ReviewedNightSleepResult? = nil) -> DashboardReplaySnapshot {
        let identity = night.replayID
        var markers: [DashboardReplayMarker] = []
        func append(_ kind: DashboardReplayMarker.Kind, _ date: Date?, _ id: String, _ source: String, recorded: Date? = nil) {
            guard let date else { return }
            markers.append(.init(id: id, sessionID: identity, kind: kind, occurredAt: date, recordedAt: recorded, source: source))
        }
        for event in night.doseEvents {
            let kind: DashboardReplayMarker.Kind
            switch CanonicalDoseEventType(canonicalizing: event.eventType) {
            case .dose1: kind = .dose1
            case .dose2: kind = .dose2
            default: continue
            }
            let metadata = event.metadata.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            let recorded = (metadata?["recorded_at_utc"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            append(kind, event.timestamp, event.id, "Patient-reported administration", recorded: recorded)
            if kind == .dose1, metadata?["dose2_reminder_enabled"] as? Bool != false,
               let target = metadata?["reminder_interval_minutes"] as? Int, (1...1440).contains(target) {
                append(.reminder, event.timestamp.addingTimeInterval(Double(target) * 60), event.id + ":reminder",
                       "Reminder target recorded with Dose 1; not delivery evidence")
            }
        }
        for event in night.events {
            append(.event, event.timestamp, "event:" + event.id, "Recorded " + event.eventType)
        }
        if let log = night.preSleepLog, log.completionState == "complete" {
            append(.foodFinish, log.answers?.lastFood?.finishedAt, "food:" + log.id, "Pre-sleep food diary")
            append(.caffeine, log.answers?.caffeineLastIntakeAt, "caffeine:" + log.id, "Pre-sleep caffeine diary")
        }
        if !night.outcomeReadFailed {
            append(.reportedWake, night.outcome?.finalWakeAt, "wake:" + identity, "Explicit final-awakening diary")
        }
        // The aggregate supplies a provider summary only after the shared identity policy resolves its association.
        if sleepSource == .appleHealth, let health = night.healthSummary {
            append(.deviceSleepEnd, health.finalWake, "health:end:" + identity, "Apple Health " + (health.finalWakeBasis ?? "selected main episode"))
            append(.mainSleepStart, health.sleepOnset, "health:start:" + identity, "Apple Health selected main episode")
        }
        let projection = reviewed?.projection.flatMap { $0.window.sessionID == night.sessionID ? $0 : nil }
        if let metric = reviewed?.doseSleepMetrics?.dose2ToSleep, metric.status == .available, projection != nil {
            append(.returnSleep, metric.end, "reviewed:return:" + identity, "Apple Health reviewed-window boundary")
        }
        return .init(sessionID: identity, treatmentDate: night.sessionDate,
            asOf: max(reportingAsOf, projection?.generatedAt ?? reportingAsOf), timeZoneID: reportingTimeZone.identifier,
            sourcePolicy: sleepSource.rawValue + " main episode; " + night.providerAssociation,
            filterDescription: rangeDescription, markers: markers, dose2NotTaken: night.dose2Skipped,
            identityResolved: night.sessionID != nil && !night.identityNeedsReview, reviewedProjection: projection)
    }

    /// The existing reviewed-window loader is date-scoped. Never use it when a date contains multiple identities.
    func replayCoverage(sessionID: String) async -> ReviewedNightSleepResult {
        guard let night = populatedNights.first(where: { $0.replayID == sessionID }),
              let identity = night.sessionID, !night.identityNeedsReview,
              Set(nights.filter { $0.sessionDate == night.sessionDate }.compactMap(\.sessionID)).count == 1 else {
            return .init(status: .needsReview)
        }
        let access = providerAccess.revision
        let result = await sessionRepo.reviewedNightSleep(sessionDate: night.sessionDate)
        guard access == providerAccess.revision,
              populatedNights.contains(where: { $0.replayID == sessionID && $0.sessionID == identity && !$0.identityNeedsReview }) else {
            return .init(status: .stale)
        }
        guard result.window == nil || result.window?.sessionID == identity else { return .init(status: .needsReview) }
        return result
    }
}
