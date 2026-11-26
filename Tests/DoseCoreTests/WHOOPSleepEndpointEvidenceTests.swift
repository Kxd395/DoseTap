import XCTest
@testable import DoseCore

final class WHOOPSleepEndpointEvidenceTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    func evidence(start: Date? = nil, end: Date?) -> WHOOPSleepEndpointEvidence {
        .init(sleepID: "sleep-1", originalStart: start ?? self.start, originalEnd: end,
              providerTimeZoneOffset: "-04:00", providerUpdatedAt: self.start.addingTimeInterval(40_000))
    }
    func testTransportPreservesOriginalTimestampsAndProvenance() throws {
        let value = evidence(end: start.addingTimeInterval(28_800))
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(WHOOPSleepEndpointEvidence.self, from: data)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.provenance, "whoop.v2.activity.sleep.start-end")
        XCTAssertEqual(decoded.originalStart, start)
        XCTAssertEqual(decoded.originalEnd, start.addingTimeInterval(28_800))
        XCTAssertEqual(decoded.providerTimeZoneOffset, "-04:00")
        XCTAssertEqual(decoded.validatedInterval?.duration, 28_800)
    }
    func testMissingReversedEqualAndNonfiniteEndsStayUnavailable() {
        for end in [nil, start, start.addingTimeInterval(-1), Date(timeIntervalSince1970: .infinity)] {
            let value = evidence(end: end)
            XCTAssertEqual(value.originalEnd, end)
            XCTAssertNil(value.validatedInterval)
            XCTAssertFalse(value.endpointsAreWithin(startInclusive: start, endExclusive: start.addingTimeInterval(90_000), asOf: start.addingTimeInterval(100_000)))
        }
        XCTAssertNil(WHOOPSleepEndpointEvidence(sleepID: "sleep-1", originalStart: nil,
            originalEnd: start, providerTimeZoneOffset: nil, providerUpdatedAt: nil).validatedInterval)
    }
    func testBothNamedEndpointsMustBelongToHalfOpenPeriodAndNotFuture() {
        let value = evidence(end: start.addingTimeInterval(28_800))
        let later = start.addingTimeInterval(90_000)
        XCTAssertTrue(value.endpointsAreWithin(startInclusive: start, endExclusive: later, asOf: later))
        XCTAssertFalse(value.endpointsAreWithin(startInclusive: start.addingTimeInterval(1), endExclusive: later, asOf: later))
        XCTAssertFalse(value.endpointsAreWithin(startInclusive: start, endExclusive: start.addingTimeInterval(28_800), asOf: later))
        XCTAssertFalse(value.endpointsAreWithin(startInclusive: start, endExclusive: start.addingTimeInterval(20_000), asOf: later))
        XCTAssertFalse(value.endpointsAreWithin(startInclusive: start, endExclusive: later, asOf: start.addingTimeInterval(28_799)))
        XCTAssertFalse(value.endpointsAreWithin(startInclusive: later, endExclusive: start, asOf: later))
    }
    func testTransportRejectsChangedProvenanceButPreservesInvalidRawInterval() throws {
        let value = evidence(end: start.addingTimeInterval(-1))
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(WHOOPSleepEndpointEvidence.self, from: data), value)
        let altered = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "whoop.v2.activity.sleep.start-end", with: "inferred")
        XCTAssertThrowsError(try JSONDecoder().decode(WHOOPSleepEndpointEvidence.self, from: Data(altered.utf8)))
    }
}
