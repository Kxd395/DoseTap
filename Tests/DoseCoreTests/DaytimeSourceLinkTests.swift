import XCTest
@testable import DoseCore

final class DaytimeSourceLinkTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let digest = String(repeating: "a", count: 64)
    func link(id: String = "nap:a", sourceIDs: [String] = ["timer-start", "timer-end"]) throws -> DaytimeSourceLink {
        try DaytimeSourceLink(kind: .nap, sourceID: id, evidenceKey: digest, sourceEventIDs: sourceIDs,
            sourceCalendarDay: "2026-09-21", timeZoneIdentifier: "UTC", start: now.addingTimeInterval(-3600),
            end: now, timePrecision: .recordedOccurrence, selectedAt: now)
    }
    func testReferenceRoundTripAndResponseCorrectionPreserveOriginalEvidence() throws {
        let reference = try link()
        let value = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: [reference])
        XCTAssertEqual(try DaytimeCheckIn.decode(value.encoded()).sourceLinks, [reference])
        let correction = try value.corrected(response: 5, status: .answered, reason: "Mistap", recordedAt: now.addingTimeInterval(1))
        XCTAssertEqual(correction.sourceLinks, value.sourceLinks)
        XCTAssertEqual(try DaytimeCheckInLedger(revisions: [value, correction]).current.first?.sourceLinks, value.sourceLinks)
    }
    func testUnknownDurationOnlyNapKeepsCalendarContextWithoutFabricatedTime() throws {
        let value = try DaytimeSourceLink(kind: .nap, sourceID: "manual-nap", evidenceKey: digest,
            sourceCalendarDay: "2026-09-20", timeZoneIdentifier: "America/New_York", timePrecision: .unknown, selectedAt: now)
        XCTAssertNil(value.start); XCTAssertNil(value.end); XCTAssertNil(value.sourceRevisionID)
        XCTAssertEqual(value.sourceCalendarDay, "2026-09-20")
        XCTAssertThrowsError(try DaytimeSourceLink(kind: .nap, sourceID: "future", evidenceKey: digest, sourceCalendarDay: "2026-09-30", timeZoneIdentifier: "UTC", selectedAt: now))
        XCTAssertThrowsError(try DaytimeSourceLink(kind: .nap, sourceID: "manual-nap", evidenceKey: digest, timePrecision: .unknown, selectedAt: now))
    }
    func testInvalidReferencesCannotBecomeRelatedEvents() throws {
        XCTAssertThrowsError(try DaytimeSourceLink(kind: .medication, sourceID: "", evidenceKey: digest, selectedAt: now))
        XCTAssertThrowsError(try DaytimeSourceLink(kind: .medication, sourceID: "dose", evidenceKey: "not-a-digest", selectedAt: now))
        XCTAssertThrowsError(try DaytimeSourceLink(kind: .medication, sourceID: "dose", evidenceKey: digest, start: now.addingTimeInterval(1), timePrecision: .reported, selectedAt: now))
        XCTAssertThrowsError(try DaytimeSourceLink(kind: .medication, sourceID: "dose", evidenceKey: digest, start: now, end: now.addingTimeInterval(-1), timePrecision: .reported, selectedAt: now))
        XCTAssertThrowsError(try DaytimeSourceLink(kind: .medication, sourceID: "dose", evidenceKey: digest, timePrecision: .reported, selectedAt: now))
    }
    func testDuplicateIdentityAndDuplicateUnderlyingEventsAreRejected() throws {
        let first = try link(), alias = try link(id: "nap:alias")
        for references in [[first, first], [first, alias]] {
            XCTAssertThrowsError(try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: references))
        }
        XCTAssertThrowsError(try DaytimeCheckIn(assessedAt: now, recordedAt: now.addingTimeInterval(-1), timeZoneIdentifier: "UTC", response: 4, sourceLinks: [first]))
    }
    func testLegacyObservationDoesNotGainRelatedSources() throws {
        let legacy = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4)
        XCTAssertNil(try DaytimeCheckIn.decode(legacy.encoded()).sourceLinks)
    }
    func testChangedSourceSnapshotCannotRewriteExistingObservation() throws {
        let original = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: [link()])
        let rewritten = try DaytimeCheckIn(id: original.id, predecessorID: original.revisionID, createdAt: original.createdAt,
            assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 5, correctionReason: "Corrected answer", sourceLinks: nil)
        XCTAssertThrowsError(try DaytimeCheckInLedger(revisions: [original, rewritten]))
        let tooMany = try (0..<33).map { try link(id: "nap:\($0)", sourceIDs: []) }
        XCTAssertThrowsError(try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: tooMany))
    }

    func testDecodedMalformedReferenceFailsClosed() throws {
        let value = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: [link()])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.encoded().utf8)) as? [String: Any])
        var sources = try XCTUnwrap(object["sourceLinks"] as? [[String: Any]])
        sources[0]["schemaVersion"] = 99; object["sourceLinks"] = sources
        let payload = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try DaytimeCheckIn.decode(String(decoding: payload, as: UTF8.self)))
    }

    func testHistoricalMedicationTimezoneIsPreservedWithoutInventingCalendarDate() throws {
        let value = try DaytimeSourceLink(kind: .medication, sourceID: "legacy", evidenceKey: digest,
            timeZoneIdentifier: "Historical/NoLongerRecognized", start: now, timePrecision: .reported, selectedAt: now)
        XCTAssertEqual(value.timeZoneIdentifier, "Historical/NoLongerRecognized")
        XCTAssertNil(value.sourceCalendarDay)
        XCTAssertThrowsError(try DaytimeSourceLink(kind: .nap, sourceID: "legacy", evidenceKey: digest,
            sourceCalendarDay: "2026-09-21", timeZoneIdentifier: "Historical/NoLongerRecognized", selectedAt: now))
    }

}
