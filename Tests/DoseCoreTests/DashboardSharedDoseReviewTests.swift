import XCTest
@testable import DoseCore

final class DashboardSharedDoseReviewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func dose(_ time: Date, id: String = "d1", session: String = "s") -> StoredDoseEvent {
        .init(id: id, eventType: "dose1", timestamp: time, sessionDate: "2027-01-15", sessionId: session)
    }
    func testOnlyCurrentLocalReviewIsSharedWithoutFingerprint() throws {
        let events = [dose(now.addingTimeInterval(-3600))]
        let review = DashboardDoseReview(observationID: "session:s", sourceFingerprint: try XCTUnwrap(DashboardDoseReview.observationFingerprint(observationID: "session:s", sessionDate: "2027-01-15", events: events, providerFingerprint: nil)), confirmedCount: 1, historicalPlanCount: 1, secondNotTaken: nil, recordedAt: now, reason: "Reviewed")
        let shared = try XCTUnwrap(DashboardSharedDoseReview.project(review, sessionID: "s", treatmentDate: "2027-01-15", events: events, capturedAt: now))
        XCTAssertEqual(shared.confirmedCount, 1)
        XCTAssertEqual(shared.evidenceIDs, ["d1"])
        let data = try JSONEncoder().encode(shared)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("sourceFingerprint"))
        XCTAssertNil(DashboardSharedDoseReview.project(review, sessionID: "s", treatmentDate: "2027-01-15", events: [dose(now.addingTimeInterval(-1800))], capturedAt: now))
        XCTAssertNil(DashboardSharedDoseReview.project(review, sessionID: "other", treatmentDate: "2027-01-15", events: events, capturedAt: now))
    }
    func testProviderReviewIsNeverSharedByLocalProjection() throws {
        let events = [dose(now.addingTimeInterval(-3600))]
        let review = DashboardDoseReview(observationID: "provider:private-episode", sourceFingerprint: try XCTUnwrap(DashboardDoseReview.observationFingerprint(observationID: "session:s", sessionDate: "2027-01-15", events: events, providerFingerprint: nil)), confirmedCount: 0, historicalPlanCount: nil, secondNotTaken: nil, recordedAt: now, reason: "Reviewed")
        XCTAssertNil(DashboardSharedDoseReview.project(review, sessionID: "s", treatmentDate: "2027-01-15", events: events, capturedAt: now))
    }
    func testFutureAndUnresolvedEvidenceCannotBeShared() throws {
        let events = [dose(now.addingTimeInterval(1))]
        let review = DashboardDoseReview(observationID: "session:s", sourceFingerprint: try XCTUnwrap(DashboardDoseReview.observationFingerprint(observationID: "session:s", sessionDate: "2027-01-15", events: events, providerFingerprint: nil)), confirmedCount: 1, historicalPlanCount: nil, secondNotTaken: nil, recordedAt: now, reason: "Reviewed")
        XCTAssertNil(DashboardSharedDoseReview.project(review, sessionID: "s", treatmentDate: "2027-01-15", events: events, capturedAt: now))
        XCTAssertNil(DashboardSharedDoseReview.project(review, sessionID: "", treatmentDate: "2027-01-15", events: [], capturedAt: now))
    }
    func testZeroCountReviewRemainsBoundToOriginalTreatmentDate() throws {
        let binding = try XCTUnwrap(DashboardDoseReview.observationFingerprint(observationID: "session:s", sessionDate: "2027-01-15", events: []))
        let review = DashboardDoseReview(observationID: "session:s", sourceFingerprint: binding, confirmedCount: 0, historicalPlanCount: nil, secondNotTaken: nil, recordedAt: now, reason: "Reviewed")
        let shared = try XCTUnwrap(DashboardSharedDoseReview.project(review, sessionID: "s", treatmentDate: "2027-01-15", events: [], capturedAt: now))
        XCTAssertEqual(shared.confirmedCount, 0)
        XCTAssertNil(DashboardSharedDoseReview.project(review, sessionID: "s", treatmentDate: "2027-01-16", events: [], capturedAt: now))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(shared)) as? [String: Any])
        object["confirmedCount"] = 3
        let malformed = try JSONDecoder().decode(DashboardSharedDoseReview.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try malformed.validate(capturedAt: now))
    }

    func testSnapshotRejectsUnboundReviewsAndRetainsLegacyCompatibility() throws {
        let binding = try XCTUnwrap(DashboardDoseReview.observationFingerprint(observationID: "session:s", sessionDate: "2027-01-15", events: []))
        let review = DashboardDoseReview(observationID: "session:s", sourceFingerprint: binding, confirmedCount: 0, historicalPlanCount: nil, secondNotTaken: nil, recordedAt: now, reason: "Reviewed")
        let shared = try XCTUnwrap(DashboardSharedDoseReview.project(review, sessionID: "s", treatmentDate: "2027-01-15", events: [], capturedAt: now))
        var snapshot = CloudDashboardSnapshot(sourceID: "synthetic", sequence: 1, capturedAt: now,
            sections: DashboardDataset.allCases.map { .init(dataset: $0, rows: Data("[]".utf8), rowCount: 0) })
        var cache = CloudDashboardCache(accountScope: "test", sourceID: "synthetic")
        XCTAssertTrue(try cache.accept(snapshot, accountScope: "test", now: now))
        XCTAssertNil(try JSONDecoder().decode(CloudDashboardSnapshot.self, from: JSONEncoder().encode(snapshot)).doseReviews)
        snapshot.sequence = 2; snapshot.doseReviews = [shared]
        XCTAssertThrowsError(try cache.accept(snapshot, accountScope: "test", now: now))
        let rows = Data(#"[{"sourceTable":"sleep_sessions","columns":{"session_id":{"type":"text","text":"s"},"session_date":{"type":"text","text":"2027-01-15"}}}]"#.utf8)
        let index = try XCTUnwrap(snapshot.sections.firstIndex { $0.dataset == .sessions })
        snapshot.sections[index] = .init(dataset: .sessions, rows: rows, rowCount: 1)
        XCTAssertTrue(try cache.accept(snapshot, accountScope: "test", now: now))
        snapshot.sequence = 3; snapshot.doseReviews = [shared, shared]
        XCTAssertThrowsError(try cache.accept(snapshot, accountScope: "test", now: now))
        XCTAssertEqual(cache.snapshot?.sequence, 2)
    }

    func testCompletedVisitsAreSanitizedAndUntrustedNotesRejected() throws {
        let visit = try PhysicianVisit(occurredAt: now.addingTimeInterval(-3600), recordedAt: now,
                                      note: "Private preparation", now: now)
        var ledger = PhysicianVisitLedger(); try ledger.append(visit, now: now)
        let sanitized = try ledger.dashboardShared(now: now)
        XCTAssertEqual(sanitized.current.first?.id, visit.id)
        XCTAssertEqual(sanitized.current.first?.note, "")
        var snapshot = CloudDashboardSnapshot(sourceID: "synthetic", sequence: 1, capturedAt: now,
            sections: DashboardDataset.allCases.map { .init(dataset: $0, rows: Data("[]".utf8), rowCount: 0) })
        snapshot.completedVisits = sanitized
        var cache = CloudDashboardCache(accountScope: "test", sourceID: "synthetic")
        XCTAssertTrue(try cache.accept(snapshot, accountScope: "test", now: now))
        snapshot.sequence = 2; snapshot.completedVisits = ledger
        XCTAssertThrowsError(try cache.accept(snapshot, accountScope: "test", now: now))
        XCTAssertEqual(cache.snapshot?.sequence, 1)
    }

}
