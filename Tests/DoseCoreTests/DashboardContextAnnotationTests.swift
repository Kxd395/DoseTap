import XCTest
@testable import DoseCore

final class DashboardContextAnnotationTests: XCTestCase {
    let origin = Date(timeIntervalSince1970: 1_790_000_000)
    func preset(_ id: UUID = UUID(), revision: UUID = UUID(), parent: UUID? = nil,
                start: Double = 0, end: Double? = nil) throws -> MedicationPresetRevision {
        try .init(presetID: id, revisionID: revision, supersedesRevisionID: parent, labelName: "Synthetic label",
            ingredient: "Synthetic ingredient", releaseProfile: .immediateRelease,
            components: [.init(id: UUID(), form: .tablet, strengthMilligrams: 5, unitCount: 1)],
            instructions: "Patient-entered instructions", schedule: .scheduled,
            effectiveFrom: origin.addingTimeInterval(start), effectiveUntil: end.map { origin.addingTimeInterval($0) },
            recordedAt: origin.addingTimeInterval(-100))
    }
    func timeline(_ presets: [MedicationPresetRevision], actual: [ConfirmedMedicationAdministration] = [],
                  content: [DashboardContentObservation] = []) throws -> DashboardContextTimeline {
        try .init(presets: .init(presetRevisions: presets.map(MedicationPresetExportSnapshot.encode),
            administrations: actual.map(MedicationPresetExportSnapshot.encode)), content: content,
            capturedAt: origin.addingTimeInterval(1000))
    }
    func version(_ version: String?, id: String = "form") throws -> DashboardContentObservation {
        try .init(sourceRecordID: id, instrumentID: "custom-diary", contentVersion: version,
            language: "en", observedAt: origin.addingTimeInterval(20))
    }
    func testExplicitEffectiveDatesAndSourceRemainSeparateFromRecordedTime() throws {
        let p = try preset(start: 30)
        let t = try timeline([p])
        let a = try XCTUnwrap(t.annotations.first)
        XCTAssertEqual(a.effectiveAt, origin.addingTimeInterval(30))
        XCTAssertEqual(a.observedAt, p.recordedAt)
        XCTAssertEqual(a.source, "patientEnteredLabel")
        XCTAssertEqual(a.sourceRecordIDs, [p.revisionID.uuidString])
        XCTAssertTrue(a.detail.contains("not proof"))
        XCTAssertEqual(try JSONDecoder().decode([DashboardContextAnnotation].self,
            from: JSONEncoder().encode(t.annotations)), t.annotations)
    }
    func testSameReferenceAndContentShareStratumButChangedVersionsDoNot() throws {
        let t = try timeline([preset()]), old = try version("v1"), new = try version("v2", id: "form2")
        let one = t.stratum(observationID: "a", start: origin, end: nil, content: [old])
        let same = t.stratum(observationID: "b", start: origin.addingTimeInterval(2), end: nil, content: [old])
        let changed = t.stratum(observationID: "c", start: origin, end: nil, content: [new])
        XCTAssertEqual(one.status, .documentedReference)
        XCTAssertEqual(one.id, same.id)
        XCTAssertNotEqual(one.id, changed.id)
    }
    func testSupersessionChangesStratumAtExplicitBoundaryAndCrossingIsIsolated() throws {
        let first = try preset(), second = try preset(first.presetID, parent: first.revisionID, start: 60)
        let t = try timeline([first, second])
        let before = t.stratum(observationID: "a", start: origin, end: origin.addingTimeInterval(60), content: [])
        let after = t.stratum(observationID: "b", start: origin.addingTimeInterval(60), end: nil, content: [])
        XCTAssertNotEqual(before.id, after.id)
        XCTAssertEqual(before.status, .documentedReference)
        XCTAssertEqual(after.sourceRecordIDs, [second.revisionID.uuidString])
        let crossing = t.stratum(observationID: "c", start: origin, end: origin.addingTimeInterval(61), content: [])
        XCTAssertEqual(crossing.status, .crossesChange)
        XCTAssertNotEqual(crossing.id, t.stratum(observationID: "d", start: origin, end: origin.addingTimeInterval(61), content: []).id)
    }
    func testUnknownTimesAndExpiredReferenceNeverBecomeCurrentRegimen() throws {
        let t = try timeline([preset(end: 60)])
        for time in [nil, origin.addingTimeInterval(-1), origin.addingTimeInterval(60)] as [Date?] {
            let value = t.stratum(observationID: "a", start: time, end: nil, content: [])
            XCTAssertEqual(value.status, .unknown)
            XCTAssertNotEqual(value.id, t.stratum(observationID: "b", start: time, end: nil, content: []).id)
        }
        XCTAssertEqual(t.stratum(observationID: "a", start: origin, end: nil, content: [try version(nil)]).status, .unknown)
    }
    func testQuestionnaireVersionIsUnplacedRatherThanFirstResponseRollout() throws {
        let content = try version("v2"), t = try timeline([], content: [content])
        let annotation = try XCTUnwrap(t.annotations.first)
        XCTAssertNil(annotation.effectiveAt)
        XCTAssertEqual(annotation.observedAt, content.observedAt)
        XCTAssertTrue(annotation.needsReview)
        XCTAssertTrue(annotation.detail.contains("rollout"))
    }
    func testUnknownAdministrationOccurrenceRemainsUnplacedAndDoesNotCreateReference() throws {
        let p = try preset(start: 50)
        let actual = try ConfirmedMedicationAdministration(id: UUID(), preset: p, actualComponents: p.components,
            occurredAt: nil, precision: .unknown, timeZoneIdentifier: nil, utcOffsetSeconds: nil,
            confirmedAt: origin, recordedAt: origin)
        let t = try timeline([p], actual: [actual])
        let annotation = try XCTUnwrap(t.annotations.first { $0.kind == .administration })
        XCTAssertNil(annotation.effectiveAt)
        XCTAssertEqual(annotation.observedAt, actual.recordedAt)
        XCTAssertEqual(t.stratum(observationID: "a", start: origin, end: nil, content: []).status, .unknown)
    }
    func testPeriodSelectionIncludesExplicitBaselineWithoutMovingItsDate() throws {
        let t = try timeline([preset(start: -50)])
        let selected = t.annotations(from: origin, to: origin.addingTimeInterval(60), includeBaseline: true)
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.effectiveAt, origin.addingTimeInterval(-50))
        XCTAssertTrue(t.annotations(from: origin, to: origin.addingTimeInterval(60), includeBaseline: false).isEmpty)
    }
    func testAbsoluteBoundariesAcrossDSTAndInvalidObservationWindows() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T06:00:00Z"))
        let first = try preset(start: date.timeIntervalSince(origin) - 600)
        let second = try preset(first.presetID, parent: first.revisionID, start: date.timeIntervalSince(origin))
        let dst = try DashboardContextTimeline(presets: .init(presetRevisions: [first, second].map(MedicationPresetExportSnapshot.encode),
            administrations: []), content: [], capturedAt: date.addingTimeInterval(3600))
        XCTAssertNotEqual(dst.stratum(observationID: "first 1AM", start: date.addingTimeInterval(-1), end: nil, content: []).id,
            dst.stratum(observationID: "second 1AM", start: date, end: nil, content: []).id)
        let t = try timeline([preset()])
        XCTAssertEqual(t.stratum(observationID: "future", start: date, end: nil, content: []).status, .unknown)
        XCTAssertEqual(t.stratum(observationID: "backwards", start: origin, end: origin.addingTimeInterval(-1), content: []).status, .unknown)
        XCTAssertEqual(t.stratum(observationID: "invalid", start: Date(timeIntervalSince1970: .nan), end: nil, content: []).status, .unknown)
    }
    func testMissingLanguageCannotCollideWithExplicitSentinelText() throws {
        let t = try timeline([preset()])
        let missing = try DashboardContentObservation(sourceRecordID: "a", instrumentID: "diary", contentVersion: "v1", language: nil, observedAt: origin)
        let literal = try DashboardContentObservation(sourceRecordID: "b", instrumentID: "diary", contentVersion: "v1", language: "not-recorded", observedAt: origin)
        XCTAssertNotEqual(t.stratum(observationID: "a", start: origin, end: nil, content: [missing]).id,
            t.stratum(observationID: "b", start: origin, end: nil, content: [literal]).id)
    }
    func testMalformedContentAndFutureObservationsFailClosed() throws {
        XCTAssertThrowsError(try DashboardContentObservation(sourceRecordID: "x", instrumentID: "", contentVersion: "v1", language: nil, observedAt: origin))
        XCTAssertThrowsError(try DashboardContentObservation(sourceRecordID: "x", instrumentID: "diary", contentVersion: "", language: nil, observedAt: origin))
        let future = try DashboardContentObservation(sourceRecordID: "x", instrumentID: "diary", contentVersion: "v1", language: nil,
            observedAt: origin.addingTimeInterval(2000))
        XCTAssertThrowsError(try timeline([], content: [future]))
    }
}
