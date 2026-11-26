import XCTest
@testable import DoseCore

extension DaytimeObservationContextTests {
    func wakeReference(_ at: Date) throws -> DaytimeWakeReference {
        try DaytimeWakeReference(sourceID: "main-source", revision: String(repeating: "a", count: 64), at: at)
    }
    func testWakeElapsedBandsAreExactHalfOpenAndVersioned() throws {
        let row = try observation()
        for (seconds, band) in [(0.0, 0), (3599.999, 0), (3600.0, 1)] {
            let reference = try wakeReference(row.assessedAt.addingTimeInterval(-seconds))
            let source = try DaytimeWakeEvidence(reference: reference, recordedAt: row.assessedAt)
            let value = try DaytimeWakeContext(observation: row, references: [reference], sources: [source], asOf: asOf)
            XCTAssertEqual(value.status, .current)
            XCTAssertEqual(try XCTUnwrap(value.elapsedSeconds), seconds, accuracy: 0.00001)
            XCTAssertEqual(value.elapsedHourBand, band)
            XCTAssertEqual(value.definitionVersion, 1)
            XCTAssertTrue(value.label.contains("hour"))
            XCTAssertEqual(try DaytimeWakeContext(observation: row, references: [reference, reference], sources: [source], asOf: asOf).status, .current)
        }
    }
    func testWakeCorrectionRecalculatesSameSourceWithoutChangingObservation() throws {
        let row = try observation(), original = try wakeReference(start.addingTimeInterval(-3600))
        let updated = try DaytimeWakeReference(sourceID: original.sourceID, revision: String(repeating: "b", count: 64), at: start)
        let before = try row.encoded()
        let value = try DaytimeWakeContext(observation: row, references: [original], sources: [DaytimeWakeEvidence(reference: updated, recordedAt: asOf)], asOf: asOf)
        XCTAssertEqual(value.status, .revised)
        XCTAssertEqual(value.elapsedSeconds, 300)
        XCTAssertEqual(value.originalReferences, [original])
        XCTAssertEqual(value.currentSource?.reference, updated)
        XCTAssertEqual(try row.encoded(), before)
    }
    func testWakePromptMillisecondRoundingDoesNotChangeSemanticRevision() throws {
        let row = try observation(), reference = try wakeReference(start.addingTimeInterval(0.123))
        let exact = try DaytimeWakeReference(sourceID: reference.sourceID, revision: reference.revision, at: start.addingTimeInterval(0.1234))
        let value = try DaytimeWakeContext(observation: row, references: [reference], sources: [DaytimeWakeEvidence(reference: exact, recordedAt: asOf)], asOf: asOf)
        XCTAssertEqual(value.status, .current)
        XCTAssertEqual(try XCTUnwrap(value.elapsedSeconds), row.assessedAt.timeIntervalSince(exact.at), accuracy: 0.000001)
        XCTAssertEqual(value.originalReferences, [reference])
    }
    func testWakeUnavailableNeverSubstitutesNearestOrCreatesAnchor() throws {
        let row = try observation(), reference = try wakeReference(start)
        let other = try DaytimeWakeReference(sourceID: "different", revision: String(repeating: "a", count: 64), at: start)
        let sources = [try DaytimeWakeEvidence(reference: other, recordedAt: asOf)]
        XCTAssertEqual(try DaytimeWakeContext(observation: row, references: [reference], sources: sources, asOf: asOf).status, .unavailable)
        XCTAssertEqual(try DaytimeWakeContext(observation: row, references: [], sources: sources, asOf: asOf).status, .notLinked)
        XCTAssertEqual(try DaytimeWakeContext(observation: row, references: nil, sources: sources, asOf: asOf).status, .unavailable)
        XCTAssertEqual(try DaytimeWakeContext(observation: row, references: [reference], sources: nil, asOf: asOf).status, .unavailable)
    }
    func testWakeConflictAndCorrectedAfterAssessmentStayUnresolved() throws {
        let row = try observation(), reference = try wakeReference(start)
        let other = try DaytimeWakeReference(sourceID: "different", revision: String(repeating: "a", count: 64), at: start)
        let future = try DaytimeWakeReference(sourceID: reference.sourceID, revision: String(repeating: "b", count: 64), at: row.assessedAt.addingTimeInterval(1))
        let invalid = try DaytimeWakeContext(observation: row, references: [reference], sources: [DaytimeWakeEvidence(reference: future, recordedAt: asOf)], asOf: asOf)
        XCTAssertEqual(invalid.status, .afterAssessment); XCTAssertNil(invalid.elapsedSeconds)
        XCTAssertEqual(try DaytimeWakeContext(observation: row, references: [reference, other], sources: [], asOf: asOf).status, .ambiguous)
    }
    func testWakeContextRejectsMalformedSourcesAndLaterCapture() throws {
        let row = try observation(), reference = try wakeReference(start)
        XCTAssertThrowsError(try DaytimeWakeReference(sourceID: "", revision: reference.revision, at: start))
        XCTAssertThrowsError(try DaytimeWakeReference(sourceID: reference.sourceID, revision: "bad", at: start))
        XCTAssertThrowsError(try DaytimeWakeReference(sourceID: reference.sourceID, revision: reference.revision, at: Date(timeIntervalSince1970: .infinity)))
        let ancient = try DaytimeWakeReference(sourceID: reference.sourceID, revision: reference.revision, at: Date(timeIntervalSince1970: -1e30))
        XCTAssertThrowsError(try DaytimeWakeContext(observation: row, references: [ancient], sources: [DaytimeWakeEvidence(reference: ancient, recordedAt: asOf)], asOf: asOf))
        let later = try DaytimeWakeEvidence(reference: reference, recordedAt: asOf.addingTimeInterval(1))
        XCTAssertThrowsError(try DaytimeWakeContext(observation: row, references: [reference], sources: [later], asOf: asOf))
        let source = try DaytimeWakeEvidence(reference: reference, recordedAt: asOf)
        XCTAssertThrowsError(try DaytimeWakeContext(observation: row, references: [reference], sources: [source, source], asOf: asOf))
    }
    func testWakeContextPartitionsExistingComparableStrata() throws {
        let row = try observation(setting: .offWork), med = try medication()
        let first = try wakeReference(start), second = try wakeReference(start.addingTimeInterval(-3600))
        let a = try DaytimeWakeContext(observation: row, references: [first], sources: [DaytimeWakeEvidence(reference: first, recordedAt: asOf)], asOf: asOf)
        let b = try DaytimeWakeContext(observation: row, references: [second], sources: [DaytimeWakeEvidence(reference: second, recordedAt: asOf)], asOf: asOf)
        let one = try DaytimeObservationContext(observation: row, work: nil, basis: .confirmed, medication: med, asOf: asOf, wake: a)
        let two = try DaytimeObservationContext(observation: row, work: nil, basis: .confirmed, medication: med, asOf: asOf, wake: b)
        XCTAssertNotEqual(one.groupingKey, two.groupingKey)
        XCTAssertEqual(one.wake?.elapsedSeconds, 300)
        let wrongCapture = try DaytimeWakeContext(observation: row, references: [first], sources: [], asOf: asOf.addingTimeInterval(1))
        XCTAssertThrowsError(try DaytimeObservationContext(observation: row, work: nil, basis: .confirmed, medication: med, asOf: asOf, wake: wrongCapture))
    }
}
