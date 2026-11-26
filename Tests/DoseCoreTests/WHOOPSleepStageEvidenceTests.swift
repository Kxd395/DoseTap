import XCTest
@testable import DoseCore

final class WHOOPSleepStageEvidenceTests: XCTestCase {
    func evidence(_ state: String? = "SCORED", _ light: Int? = 0, _ deep: Int? = 0, _ rem: Int? = 0) -> WHOOPSleepStageEvidence {
        .init(sleepID: "sleep-1", scoreState: state, lightMilliseconds: light, deepMilliseconds: deep, remMilliseconds: rem)
    }
    func testExplicitScoredCompleteZeroAndSubminuteAmountsRemainDistinct() throws {
        XCTAssertEqual(evidence().sleepMinutes, 0)
        XCTAssertEqual(try XCTUnwrap(evidence("SCORED", 1_000, 2_000, 3_000).sleepMinutes), 0.1, accuracy: 0.000001)
        let original = evidence("SCORED", 1_001, 2_002, 3_003)
        let restored = try JSONDecoder().decode(WHOOPSleepStageEvidence.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.lightMilliseconds, 1_001)
        XCTAssertEqual(try XCTUnwrap(restored.sleepMinutes), 0.1001, accuracy: 0.000001)
    }
    func testMissingUnscoredIncompleteAndNegativeEvidenceIsNotNumeric() {
        for value in [evidence(nil), evidence("PENDING_SCORE"), evidence("UNSCORABLE"),
                      evidence("SCORED", nil), evidence("SCORED", 0, nil),
                      evidence("SCORED", 0, 0, nil), evidence("SCORED", -1, 60_000, 0)] {
            XCTAssertNil(value.sleepMinutes)
        }
    }
    func testLegacyPayloadDoesNotAcquireScoredProvenanceOnRoundTrip() throws {
        let legacy = Data(#"{"lightMilliseconds":60000,"deepMilliseconds":0,"remMilliseconds":0}"#.utf8)
        let value = try JSONDecoder().decode(WHOOPSleepStageEvidence.self, from: legacy)
        XCTAssertEqual(value.lightMilliseconds, 60_000)
        XCTAssertNil(value.scoreState); XCTAssertNil(value.provenance); XCTAssertNil(value.version)
        XCTAssertNil(value.sleepMinutes)
        let roundTrip = try JSONDecoder().decode(WHOOPSleepStageEvidence.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(roundTrip, value); XCTAssertNil(roundTrip.sleepMinutes)
        for key in ["sleepID", "scoreState", "provenance", "version"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence())) as? [String: Any])
            object.removeValue(forKey: key)
            let missing = try JSONDecoder().decode(WHOOPSleepStageEvidence.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(missing.sleepMinutes, key)
        }
    }
    func testLargeOriginalIntegersCannotOverflowSummation() throws {
        let value = evidence("SCORED", Int.max, Int.max, Int.max)
        XCTAssertTrue(try XCTUnwrap(value.sleepMinutes).isFinite)
        XCTAssertEqual(value.remMilliseconds, Int.max)
    }
}
