import Foundation
import XCTest
@testable import DoseCore

final class DaytimeAuthoringTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testZeroAndUnsureRoundTripAsDistinctRevisions() throws {
        let original = try DaytimeCheckIn(assessedAt: now, recordedAt: now,
                                         timeZoneIdentifier: "America/New_York", response: 0)
        let correction = try original.corrected(response: nil, status: .unsure, reason: "Reviewed",
                                                recordedAt: now.addingTimeInterval(60))
        let restored = try [original, correction].map { try DaytimeCheckIn.decode($0.encoded()) }
        let ledger = try DaytimeCheckInLedger(revisions: restored.reversed())
        XCTAssertEqual(restored, [original, correction])
        XCTAssertEqual(restored.first?.response, 0)
        XCTAssertNil(correction.response)
        XCTAssertEqual(ledger.current, [correction])
        XCTAssertEqual(correction.id, original.id)
        XCTAssertEqual(correction.assessedAt, original.assessedAt)
        XCTAssertEqual(correction.utcOffsetSeconds, original.utcOffsetSeconds)
    }

    func testBlankReasonAndStaleBranchAreRejected() throws {
        let original = try DaytimeCheckIn(assessedAt: now, recordedAt: now,
                                         timeZoneIdentifier: "UTC", response: 4)
        XCTAssertThrowsError(try original.corrected(response: 5, status: .answered, reason: " ",
                                                    recordedAt: now))
        let first = try original.corrected(response: 5, status: .answered, reason: "First review",
                                           recordedAt: now.addingTimeInterval(1))
        let stale = try original.corrected(response: 6, status: .answered, reason: "Stale review",
                                           recordedAt: now.addingTimeInterval(2))
        XCTAssertThrowsError(try DaytimeCheckInLedger(revisions: [original, first, stale]))
    }
}
