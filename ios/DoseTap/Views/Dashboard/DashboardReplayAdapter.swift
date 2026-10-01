import Foundation
import DoseCore

extension DashboardNightAggregate {
    var replayID: String { sessionID ?? id }
}

extension DashboardAnalyticsModel {
    var replayDisplaySnapshots: [DashboardReplaySnapshot] {
        let access = providerAccess.revision
        if let cachedReplaySnapshots, cachedReplayAccess == access { return cachedReplaySnapshots }
        invalidReplayEndpointIDs = []
        let result = visibleInspectionNights.map { night in
            let base = replaySnapshot(for: night, reviewed: night.replayID == selectedReplayID ? replayCoverageState.result : nil)
            do { return try applyingReplayChoices(base) }
            catch {
                invalidReplayEndpointIDs.insert(base.sessionID)
                return DashboardReplaySnapshot(sessionID: base.sessionID, treatmentDate: base.treatmentDate,
                    asOf: base.asOf, timeZoneID: base.timeZoneID, sourcePolicy: base.sourcePolicy,
                    filterDescription: base.filterDescription + "; endpoint selection needs review", markers: base.markers,
                    dose2NotTaken: base.dose2NotTaken, identityResolved: false,
                    reviewedProjection: base.reviewedProjection, mainEpisodeIntervals: base.mainEpisodeIntervals)
            }
        }
        cachedReplaySnapshots = result; cachedReplayAccess = access
        return result
    }
    func applyingReplayChoices(_ base: DashboardReplaySnapshot) throws -> DashboardReplaySnapshot {
        let result = try base.addingSelectedEndpoints(replayPresentation.endpointSelections[base.sessionID] ?? [])
        guard let choice = replayPresentation.dosePairs[base.sessionID] else { return result }
        return try result.selectingDosePair(dose1ID: choice.dose1ID, dose2ID: choice.dose2ID)
    }

    var selectedReplayID: String? {
        let matches = nights.filter { $0.id == inspection.selectedObservationID }
        return matches.count == 1 ? matches.first?.replayID : nil
    }
    func selectReplayID(_ value: String?) {
        guard let value else { inspection.selectedObservationID = nil; return }
        let matches = nights.filter { $0.replayID == value }
        if matches.count == 1 { inspection.selectedObservationID = matches[0].id }
    }

    func replaySnapshot(for night: DashboardNightAggregate, reviewed: ReviewedNightSleepResult? = nil) -> DashboardReplaySnapshot {
        let identity = night.replayID
        var markers: [DashboardReplayMarker] = []
        func append(_ kind: DashboardReplayMarker.Kind, _ date: Date?, _ id: String, _ source: String, recorded: Date? = nil, sourceSessionID: String? = nil, quality: DashboardReplayMarker.EvidenceQuality? = nil, amount: String? = nil) {
            guard let date else { return }
            markers.append(.init(id: id, sessionID: sourceSessionID ?? identity, kind: kind, occurredAt: date, recordedAt: recorded, source: source, amountDescription: amount, evidenceQuality: quality))
        }
        for event in night.doseEvents {
            let kind: DashboardReplayMarker.Kind
            switch CanonicalDoseEventType(canonicalizing: event.eventType) {
            case .dose1: kind = .dose1
            case .dose2: kind = .dose2
            case .extraDose: kind = .extraDose
            default: continue
            }
            let metadata = event.metadata.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            let recorded = (metadata?["recorded_at_utc"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            append(kind, event.timestamp, event.id, "Patient-reported administration", recorded: recorded, sourceSessionID: event.sessionId ?? "", amount: DosePatternPresentation.recordedAmountMg(event).map { "\($0) mg" })
            if kind == .dose1, metadata?["dose2_reminder_enabled"] as? Bool != false,
               let target = metadata?["reminder_interval_minutes"] as? Int, (1...1440).contains(target) {
                append(.reminder, event.timestamp.addingTimeInterval(Double(target) * 60), event.id + ":reminder",
                       "Reminder target recorded with Dose 1; not delivery evidence")
            }
        }
        for event in night.events {
            let source: String
            if normalizeStoredEventType(event.eventType) == "lights_out", event.notes == "Pre-sleep check completed" {
                source = "Pre-sleep check completed; not confirmed lights out"
            } else if normalizeStoredEventType(event.eventType) == "lights_out", event.notes == "Pre-sleep check skipped" {
                source = "Pre-sleep check skipped; not confirmed lights out"
            } else { source = "Recorded " + normalizeStoredEventType(event.eventType).replacingOccurrences(of: "_", with: " ") }
            append(.event, event.timestamp, "event:" + event.id, source)
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
            append(.deviceSleepEnd, health.finalWake, "health:end:" + identity, "Apple Health " + (health.finalWakeBasis ?? "selected main episode"), quality: replayProviderQuality(.health, recordID: health.id))
            append(.mainSleepStart, health.sleepOnset, "health:start:" + identity, "Apple Health selected main episode", quality: replayProviderQuality(.health, recordID: health.id))
        }
        if sleepSource == .whoop, let whoop = night.whoopSummary, let interval = whoop.originalSleepInterval {
            var quality = replayProviderQuality(.whoop, recordID: whoop.sleepId)
            if currentReportWindow == nil {
                quality = .init(state: .needsReview, reason: "Reporting period is unresolved",
                    capturedAt: quality.capturedAt, providerRecordID: whoop.sleepId)
            } else if let window = currentReportWindow,
               whoop.endpointEvidence?.endpointsAreWithin(startInclusive: window.start ?? .distantPast,
                    endExclusive: window.endExclusive, asOf: reportingAsOf) != true {
                quality = .init(state: .notApplicable, reason: "Original episode endpoints are outside the half-open reporting period",
                    capturedAt: quality.capturedAt, providerRecordID: whoop.sleepId)
            }
            append(.whoopEpisodeStart, interval.start, "whoop:start:" + whoop.sleepId,
                "WHOOP original API episode start; not first measured asleep", quality: quality)
            append(.whoopEpisodeEnd, interval.end, "whoop:end:" + whoop.sleepId,
                "WHOOP original API episode end; not final measured asleep or reported wake", quality: quality)
        }
        let wake = replayWakeTarget(for: night)
        if let date = wake.requiredWake, let first = wake.sources.first {
            append(.requiredWake, date, "required-wake:" + first.revision.uuidString,
                "Saved required wake; revision " + first.revision.uuidString + "; " + first.timeZoneID
                    + "; source events: " + wake.sources.map(\.eventID).joined(separator: ","), sourceSessionID: first.sessionID)
        }
        let projection = reviewed?.projection.flatMap { $0.window.sessionID == night.sessionID ? $0 : nil }
        if let metric = reviewed?.doseSleepMetrics?.dose2ToSleep, metric.status == .available, projection != nil {
            append(.returnSleep, metric.end, "reviewed:return:" + identity, "Apple Health reviewed-window boundary", quality: .init(state: .available,
                    reason: "Explicit reviewed-window check", capturedAt: projection?.generatedAt))
        }
        return .init(sessionID: identity, treatmentDate: night.sessionDate,
            asOf: max(reportingAsOf, projection?.generatedAt ?? reportingAsOf), timeZoneID: reportingTimeZone.identifier,
            sourcePolicy: sleepSource.rawValue + " main episode; " + night.providerAssociation + (wake.state == .needsReview ? "; required wake needs review" : "") + (projection == nil ? "" : "; reviewed intervals: Apple Health"),
            filterDescription: rangeDescription, markers: markers, dose2NotTaken: night.dose2Skipped,
            identityResolved: !night.identityNeedsReview && night.doseEvents.allSatisfy { $0.sessionId == night.sessionID && $0.sessionId != nil } && (night.sessionID != nil || night.healthSummary != nil || night.whoopSummary != nil), reviewedProjection: projection,
            mainEpisodeIntervals: sleepSource == .appleHealth ? night.healthSummary?.recordedIntervals ?? [] : [])
    }

    func replayProviderQuality(_ provider: DashboardProviderAccess.Provider, recordID: String) -> DashboardReplayMarker.EvidenceQuality {
        let captured = provider == .health ? healthSnapshot?.window.asOf : whoopSnapshot?.window.asOf
        let fixture = DashboardReplayUITestFixture.enabled
        let current = fixture || providerSnapshotIsCurrent(provider)
        return .init(state: current ? .available : .partial,
            reason: current ? "Current provider capture" : "Retained provider endpoints; current capture unavailable",
            capturedAt: captured ?? (fixture ? reportingAsOf : nil), providerRecordID: recordID)
    }

    func replayWakeTarget(for night: DashboardNightAggregate) -> DashboardRecordedWakeTarget {
        .derive(sessionID: night.sessionID ?? "", events: night.doseEvents, asOf: reportingAsOf)
    }

    func replayCoverage(sessionID: String) async -> ReviewedNightSleepResult {
        if let fixture = DashboardReplayUITestFixture.coverage(model: self, sessionID: sessionID) { return fixture }
        return await dashboardReviewedCoverage(sessionID: sessionID)
    }
}
