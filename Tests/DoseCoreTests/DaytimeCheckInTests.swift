import XCTest
@testable import DoseCore

final class DaytimeCheckInTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func entry(score: Int? = 0, status: DaytimeCheckIn.Status = .answered) throws -> DaytimeCheckIn {
        try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: score, status: status)
    }
    func testZeroIsAnsweredAndMissingIsNotZero() throws {
        XCTAssertEqual(try entry().response, 0)
        XCTAssertNil(try entry(score: nil, status: .incomplete).response)
        XCTAssertThrowsError(try entry(score: nil))
        XCTAssertThrowsError(try entry(score: 0, status: .skipped))
        XCTAssertThrowsError(try entry(score: 11))
    }
    func testTimeAndCopingValidation() throws {
        XCTAssertThrowsError(try DaytimeCheckIn(assessedAt: now.addingTimeInterval(1), recordedAt: now, timeZoneIdentifier: "UTC", response: 2))
        XCTAssertThrowsError(try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "bad zone", response: 2))
        XCTAssertThrowsError(try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 2, copingActions: [.movement]))
        let value = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-7200), recordedAt: now, timeZoneIdentifier: "America/New_York", response: 2, origin: .retrospective, coping: .yes, copingActions: [.movement])
        XCTAssertEqual(value.recordedAt.timeIntervalSince(value.assessedAt), 7200)
        XCTAssertEqual(value.origin, .retrospective)
    }
    func testCorrectionPreservesIdentityAndRejectsFork() throws {
        let original = try entry()
        let next = try original.corrected(response: 4, status: .answered, reason: "Corrected entry", recordedAt: now.addingTimeInterval(60))
        let ledger = try DaytimeCheckInLedger(revisions: [next, original])
        XCTAssertEqual(ledger.current, [next])
        XCTAssertEqual(next.createdAt, original.createdAt)
        XCTAssertEqual(next.assessedAt, original.assessedAt)
        XCTAssertThrowsError(try original.corrected(response: 3, status: .answered, reason: " ", recordedAt: now))
        let fork = try original.corrected(response: 5, status: .answered, reason: "Other correction", recordedAt: now)
        XCTAssertThrowsError(try DaytimeCheckInLedger(revisions: [original, next, fork]))
        XCTAssertThrowsError(try DaytimeCheckInLedger(revisions: [next]))
    }
    func testRepeatedObservationsAndRoundTrip() throws {
        let a = try entry(), b = try entry()
        XCTAssertNotEqual(a.id, b.id)
        let ledger = try DaytimeCheckInLedger(revisions: [a, b])
        XCTAssertEqual(ledger.current.count, 2)
        XCTAssertEqual(try DaytimeCheckIn.decode(a.encoded()), a)
        var json = try JSONSerialization.jsonObject(with: Data(a.encoded().utf8)) as! [String: Any]
        json["response"] = 99
        XCTAssertThrowsError(try DaytimeCheckIn.decode(String(data: JSONSerialization.data(withJSONObject: json), encoding: .utf8)!))
    }
}
