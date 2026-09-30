import Foundation
import DoseCore

extension DashboardNightAggregate {
    var reviewFingerprint: String? {
        DashboardDoseReview.observationFingerprint(observationID: id, sessionDate: sessionDate,
            events: doseEvents, providerFingerprint: unmatchedProviderEvidence?.fingerprint)
    }

    var doseReview: DashboardDoseReview? {
        guard let fingerprint = reviewFingerprint,
              let review = doseReviewLedger?.current(matching: fingerprint), review.observationID == id,
              review.validationError(now: review.recordedAt) == nil else { return nil }
        return review
    }

    var dosePattern: DashboardDosePattern {
        let administrations = doseEvents.compactMap { event -> DashboardDosePattern.Administration? in
            let slot: Int
            switch CanonicalDoseEventType(canonicalizing: event.eventType) {
            case .dose1: slot = 1
            case .dose2: slot = 2
            case .extraDose: slot = 3
            case .dose2Skipped, .snooze, .historyCorrection: return nil
            case nil: slot = 0
            }
            return .init(id: event.id, sessionID: event.sessionId ?? "", slot: slot, occurredAt: event.timestamp)
        }
        let duplicateConflict = Dictionary(grouping: doseEvents, by: \.id).values.contains { rows in
            Set(rows.compactMap { DashboardDoseReview.fingerprint([$0]) }).count > 1
        }
        let omission = doseEvents.contains { CanonicalDoseEventType(canonicalizing: $0.eventType) == .dose2Skipped }
        let inconsistent = identityNeedsReview || reviewFingerprint == nil || duplicateConflict
            || doseEvents.contains { $0.sessionDate != sessionDate }
            || (omission && doseReview?.secondNotTaken == false)
        return .derive(sessionID: inconsistent ? "" : (sessionID ?? id), administrations: administrations,
            confirmedCount: doseReview?.confirmedCount, historicalPlanCount: doseReview?.historicalPlanCount,
            secondNotTaken: omission || doseReview?.secondNotTaken == true,
            sessionOpen: sessionActive && !sessionClosed)
    }
}

extension DashboardAnalyticsModel {
    func saveDoseHistoryReview(review: DashboardDoseReview, observationID: String, expectedRevision: UUID?) throws {
        guard doseReviewReadReady, !isLoading, review.observationID == observationID,
              let displayed = nights.first(where: { $0.id == observationID }), !displayed.identityNeedsReview,
              let fingerprint = displayed.reviewFingerprint, review.sourceFingerprint == fingerprint else {
            throw DashboardDoseReviewError.changed
        }
        if let message = review.validationError(now: now()) { throw DashboardDoseReviewError.invalid(message) }
        let snapshot = try sessionRepo.dashboardIdentitySnapshot()
        let current: DashboardNightAggregate?
        if displayed.sessionID != nil {
            current = identityAggregates(local: snapshot.sessions, health: [:], whoop: [:])
                .first { $0.id == observationID }
        } else {
            guard let evidence = displayed.unmatchedProviderEvidence,
                  providerSnapshotIsCurrent(evidence.provider == "apple-health" ? .health : .whoop) else {
                throw DashboardDoseReviewError.changed
            }
            current = identityAggregates(local: snapshot.sessions, health: healthSnapshot?.values ?? [:],
                whoop: whoopSnapshot?.values ?? [:], associations: snapshot.associations)
                .first { $0.id == observationID }
            guard current?.unmatchedProviderEvidence?.fingerprint == evidence.fingerprint else {
                throw DashboardDoseReviewError.changed
            }
        }
        guard let current, !current.identityNeedsReview, current.sessionID == displayed.sessionID,
              current.sessionDate == displayed.sessionDate, current.reviewFingerprint == fingerprint else {
            throw DashboardDoseReviewError.changed
        }
        try sessionRepo.saveDashboardDoseReview(review, sessionDate: current.sessionDate, expectedRevision: expectedRevision, allowDateCorrection: true)
        refresh()
    }
}
