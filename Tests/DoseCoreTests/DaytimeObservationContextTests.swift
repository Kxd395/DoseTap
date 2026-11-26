import XCTest
@testable import DoseCore

final class DaytimeObservationContextTests: XCTestCase {
    let start = ISO8601DateFormatter().date(from: "2026-09-21T08:00:00Z")!
    var asOf: Date { start.addingTimeInterval(7200) }
    func observation(offset: Double = 300, setting: DaytimeCheckIn.Setting = .work) throws -> DaytimeCheckIn {
        try DaytimeCheckIn(assessedAt: start.addingTimeInterval(offset), recordedAt: asOf, timeZoneIdentifier: "UTC", response: 4, setting: setting)
    }
    func shift(position: Int = 1) -> WorkShiftEvent {
        var value = WorkShiftEvent(timeZoneIdentifier: "UTC", recordedAt: asOf)
        value.status = .worked; value.attendanceConfirmed = true; value.actualTimePrecision = .reportedMinute
        value.scheduledStart = start; value.scheduledEnd = start.addingTimeInterval(3600)
        value.actualStart = value.scheduledStart; value.actualEnd = value.scheduledEnd
        value.position = position; value.blockShiftCount = 3
        return value
    }
    func work(_ values: [WorkShiftEvent]) -> WorkContextDocument {
        var doc = WorkContextDocument(); doc.schemaVersion = 2; doc.shiftEvents = values; return doc
    }
    func medication() throws -> DashboardContextTimeline {
        let value = try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(), supersedesRevisionID: nil, labelName: "Synthetic reference", ingredient: "Synthetic ingredient", releaseProfile: .immediateRelease,
            components: [.init(id: UUID(), form: .tablet, strengthMilligrams: 5, unitCount: 1)], instructions: "Synthetic instructions", schedule: .scheduled,
            effectiveFrom: start.addingTimeInterval(-86400), effectiveUntil: nil, recordedAt: start.addingTimeInterval(-86400))
        return try DashboardContextTimeline(presets: .init(presetRevisions: [MedicationPresetExportSnapshot.encode(value)], administrations: []), content: [], capturedAt: asOf)
    }
    func testStructuralComparisonKeepsOccurrenceIDsAsProvenance() throws {
        let a = try observation(), b = try observation(offset: 600), med = try medication()
        let first = shift(), second = shift()
        let one = try DaytimeObservationContext(observation: a, work: work([first]), basis: .planned, medication: med, asOf: asOf)
        let two = try DaytimeObservationContext(observation: b, work: work([second]), basis: .planned, medication: med, asOf: asOf)
        XCTAssertEqual(one.groupingKey, two.groupingKey)
        XCTAssertNotEqual(one.shiftID, two.shiftID)
        XCTAssertEqual(one.shiftRevisionID, first.id)
        XCTAssertEqual(one.shiftThird, 0)
        let confirmed = try DaytimeObservationContext(observation: a, work: work([first]), basis: .confirmed, medication: med, asOf: asOf)
        XCTAssertNotEqual(one.groupingKey, confirmed.groupingKey)
    }
    func testUnknownAmbiguousAndUnknownMedicationStaySeparate() throws {
        let a = try observation(), b = try observation(offset: 600), med = try medication()
        let unknown = try DaytimeObservationContext(observation: a, work: nil, basis: .confirmed, medication: med, asOf: asOf)
        let other = try DaytimeObservationContext(observation: b, work: nil, basis: .confirmed, medication: med, asOf: asOf)
        XCTAssertEqual(unknown.workStatus, .unknown); XCTAssertNotEqual(unknown.groupingKey, other.groupingKey)
        let ambiguous = try DaytimeObservationContext(observation: a, work: work([shift(), shift()]), basis: .confirmed, medication: med, asOf: asOf)
        XCTAssertEqual(ambiguous.workStatus, .ambiguous)
        let doc = work([shift()])
        let noMed = try DaytimeObservationContext(observation: a, work: doc, basis: .confirmed, medication: nil, asOf: asOf)
        let noMedOther = try DaytimeObservationContext(observation: b, work: doc, basis: .confirmed, medication: nil, asOf: asOf)
        XCTAssertNotEqual(noMed.groupingKey, noMedOther.groupingKey)
    }
    func testOffWorkRequiresExplicitObservationAndRevisionsRecalculateWithoutMutation() throws {
        let off = try observation(setting: .offWork), a = try observation(), med = try medication()
        let context = try DaytimeObservationContext(observation: off, work: nil, basis: .confirmed, medication: med, asOf: asOf)
        XCTAssertEqual(context.workStatus, .reportedOffWork)
        XCTAssertTrue(context.workLabel.contains("Reported off work"))
        let payload = try a.encoded()
        let first = try DaytimeObservationContext(observation: a, work: work([shift()]), basis: .planned, medication: med, asOf: asOf)
        let changed = try DaytimeObservationContext(observation: a, work: work([shift(position: 2)]), basis: .planned, medication: med, asOf: asOf)
        XCTAssertNotEqual(first.groupingKey, changed.groupingKey)
        XCTAssertEqual(try a.encoded(), payload)
    }
    func testAnalysisUsesExactContextsAndRejectsStaleCaptureOrMissingMapping() throws {
        let a = try observation(), b = try observation(offset: 600), med = try medication(), doc = work([shift()])
        let first = try DaytimeObservationContext(observation: a, work: doc, basis: .planned, medication: med, asOf: asOf)
        let second = try DaytimeObservationContext(observation: b, work: doc, basis: .confirmed, medication: med, asOf: asOf)
        let report = try DaytimeDiaryAnalysis(observations: [a,b], events: [], start: start, end: asOf, now: asOf, timeZone: TimeZone(secondsFromGMT: 0)!, contexts: [a.id:first,b.id:second])
        XCTAssertEqual(report.groups.count, 2)
        XCTAssertTrue(report.groups.allSatisfy { $0.contextLabel != nil })
        XCTAssertThrowsError(try DaytimeDiaryAnalysis(observations: [a,b], events: [], start: start, end: asOf, now: asOf, timeZone: .current, contexts: [a.id:first]))
        XCTAssertThrowsError(try DaytimeObservationContext(observation: a, work: doc, basis: .planned, medication: med, asOf: asOf.addingTimeInterval(1)))
    }
    func testTemporalThirdsAndHalfOpenEndAreExactWithoutInferringWorkload() throws {
        let med = try medication(), doc = work([shift()])
        for (offset, expected) in [(0.0, 0), (1200.0, 1), (2400.0, 2)] {
            let value = try DaytimeObservationContext(observation: observation(offset: offset), work: doc, basis: .confirmed, medication: med, asOf: asOf)
            XCTAssertEqual(value.shiftThird, expected)
        }
        let ended = try DaytimeObservationContext(observation: observation(offset: 3600), work: doc, basis: .confirmed, medication: med, asOf: asOf)
        XCTAssertEqual(ended.workStatus, .unknown)
        var missingPosition = shift(); missingPosition.position = nil
        let one = try DaytimeObservationContext(observation: observation(), work: work([missingPosition]), basis: .planned, medication: med, asOf: asOf)
        let two = try DaytimeObservationContext(observation: observation(), work: work([missingPosition]), basis: .planned, medication: med, asOf: asOf)
        XCTAssertNotEqual(one.groupingKey, two.groupingKey)
    }

    func testMalformedWorkAndConflictingOffSettingAreNotComparable() throws {
        let row = try observation(), med = try medication()
        var invalid = work([shift()]); invalid.schemaVersion = -1
        XCTAssertThrowsError(try DaytimeObservationContext(observation: row, work: invalid, basis: .planned, medication: med, asOf: asOf))
        let conflict = try DaytimeObservationContext(observation: observation(setting: .offWork), work: work([shift()]), basis: .confirmed, medication: med, asOf: asOf)
        XCTAssertEqual(conflict.workStatus, .ambiguous); XCTAssertNil(conflict.shiftID)
        let point = try DaytimeWorkContext(at: row.assessedAt, sourceRecordID: "event-1", reportedSetting: nil, work: work([shift()]), basis: .confirmed, asOf: asOf)
        XCTAssertEqual(point.status, .matched)
        XCTAssertFalse(point.sourceRecordIDs.isEmpty)
    }
    func testAnalysisRejectsContextForDifferentObservationEvenUnderSameDictionaryKey() throws {
        let a = try observation(), b = try observation(), med = try medication()
        let wrong = try DaytimeObservationContext(observation: b, work: work([shift()]), basis: .confirmed, medication: med, asOf: asOf)
        XCTAssertThrowsError(try DaytimeDiaryAnalysis(observations: [a], events: [], start: start, end: asOf, now: asOf, timeZone: .current, contexts: [a.id: wrong]))
        let descriptive = try DaytimeDiaryAnalysis(observations: [a], events: [], start: start, end: asOf, now: asOf, timeZone: .current)
        XCTAssertNil(descriptive.observationContexts)
        XCTAssertTrue(descriptive.contextScopeLabel.contains("not adjusted"))
    }

}
