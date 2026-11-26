import XCTest
@testable import DoseCore

final class DaytimeEventTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func testUnknownDurationAndExplicitEventKinds() throws {
        let value = try DaytimeEvent(kind: .struggling, occurredAt: now, recordedAt: now, timeZoneIdentifier: "UTC")
        XCTAssertNil(value.durationSeconds)
        XCTAssertFalse(value.isReportedSleep)
        XCTAssertTrue(try DaytimeEvent(kind: .unplannedSleep, occurredAt: now, recordedAt: now, timeZoneIdentifier: "UTC").isReportedSleep)
        XCTAssertThrowsError(try DaytimeEvent(kind: .unclear, occurredAt: now, recordedAt: now, timeZoneIdentifier: "UTC", durationSeconds: -1))
    }
    func testCorrectionRetainsOriginalAndRejectsFork() throws {
        let value = try DaytimeEvent(kind: .unplannedSleep, occurredAt: now, recordedAt: now, timeZoneIdentifier: "UTC")
        let correction = try value.corrected(kind: .unclear, note: "Unsure", reason: "Correcting", recordedAt: now)
        XCTAssertEqual(try DaytimeEventLedger(revisions: [value, correction]).current, [correction])
        let fork = try value.corrected(kind: .struggling, note: "", reason: "Fork", recordedAt: now)
        XCTAssertThrowsError(try DaytimeEventLedger(revisions: [value, correction, fork]))
        XCTAssertThrowsError(try DaytimeEventLedger(revisions: [correction]))
    }
    func testReviewNeverImpliesZeroFromUnknownAndDeduplicatesReferences() throws {
        let id = UUID()
        let review = try DaytimeEventReview(from: now.addingTimeInterval(-3600), to: now, status: .eventsReported, eventIDs: [id])
        XCTAssertEqual(review.eventIDs.count, 1)
        XCTAssertThrowsError(try DaytimeEventReview(from: now, to: now, status: .noneReported, eventIDs: [id]))
        XCTAssertThrowsError(try DaytimeEventReview(from: now, to: now, status: .eventsReported, eventIDs: [id, id]))
        XCTAssertThrowsError(try DaytimeEventReview(from: now.addingTimeInterval(1), to: now, status: .unsure))
        XCTAssertEqual(try DaytimeEventReview(from: now, to: now, status: .unsure).status, .unsure)
    }
}
