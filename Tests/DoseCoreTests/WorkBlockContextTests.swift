import XCTest
@testable import DoseCore

final class WorkBlockContextTests: XCTestCase {
    let early = Date(timeIntervalSince1970: 1_700_000_000)
    let late = Date(timeIntervalSince1970: 1_800_000_000)
    func document() -> WorkContextDocument {
        var value = WorkContextDocument()
        value.rosters = [WorkRoster(effectiveFrom: "2026-09-01", effectiveTo: "2026-12-31", timeZoneIdentifier: "America/New_York", weekdays: [3, 4, 5], recordedAt: early)]
        return value
    }
    func context(_ value: WorkContextDocument, _ previous: String, _ following: String, basis: WorkContextBasis = .planned) -> WorkPhaseResult {
        let association = WorkSleepAssociation(sleepID: "sleep", precedingDate: previous, followingDate: following, timeZoneIdentifier: "America/New_York", plannedAt: late, recordedAt: late)
        return value.classify(association, basis: basis, asOf: late)
    }
    func testSevenCyclePositions() {
        let phases: [WorkPhase] = [.entering, .between, .between, .after, .off, .off, .off]
        for (index, expected) in phases.enumerated() {
            let result = context(document(), "2026-09-\(21 + index)", "2026-09-\(22 + index)")
            XCTAssertEqual(result.phase, expected)
            XCTAssertEqual(result.postBlockMainSleepIndex, expected == .after ? 1 : nil)
        }
    }
    func testLaterOffSleepKeepsBlockButDoesNotInferMissingMainSleepIndex() {
        let after = context(document(), "2026-09-24", "2026-09-25")
        let off = context(document(), "2026-09-26", "2026-09-27")
        XCTAssertEqual(after.firstShiftDate, off.firstShiftDate)
        XCTAssertNotNil(off.blockID)
        XCTAssertNil(off.postBlockMainSleepIndex)
    }
    func testPlannedDoesNotEstablishAttendance() {
        XCTAssertEqual(context(document(), "2026-09-21", "2026-09-22", basis: .confirmed).phase, .unknown)
    }
    func testEffectiveDatesAndTimezoneRequired() {
        XCTAssertEqual(context(document(), "2026-08-24", "2026-08-25").phase, .unknown)
        var value = document(); value.rosters[0].timeZoneIdentifier = "UTC"
        XCTAssertEqual(context(value, "2026-09-21", "2026-09-22").phase, .unknown)
    }
    func testCancelledWednesdaySplitsConfirmedBlockButPreservesPlan() {
        var value = document()
        for (date, status) in [("2026-09-22", WorkAttendance.worked), ("2026-09-23", .notWorked)] {
            value.occurrences.append(WorkOccurrence(workDate: date, timeZoneIdentifier: "America/New_York", attendance: status, recordedAt: early))
        }
        XCTAssertEqual(context(value, "2026-09-22", "2026-09-23", basis: .confirmed).phase, .after)
        XCTAssertEqual(context(value, "2026-09-22", "2026-09-23").phase, .between)
    }
    func testExtraShiftAndHistoricalSnapshot() {
        var value = document()
        value.occurrences.append(WorkOccurrence(workDate: "2026-09-25", timeZoneIdentifier: "America/New_York", plannedWorking: true, recordedAt: late))
        XCTAssertEqual(context(value, "2026-09-24", "2026-09-25").phase, .between)
        var association = WorkSleepAssociation(sleepID: "night", precedingDate: "2026-09-24", followingDate: "2026-09-25", timeZoneIdentifier: "America/New_York", plannedAt: early, recordedAt: late)
        XCTAssertEqual(value.classify(association, basis: .planned, asOf: late).phase, .after)
        association.isMainSleep = false
        XCTAssertEqual(value.classify(association, basis: .planned, asOf: late).phase, .unknown)
    }
    func testDSTUsesLocalDatesAndRejectsMissingDays() {
        var value = document(); value.rosters[0].weekdays = [1]
        XCTAssertEqual(context(value, "2026-10-31", "2026-11-01").phase, .entering)
        XCTAssertEqual(context(value, "2026-10-31", "2026-11-02").phase, .unknown)
        XCTAssertEqual(context(value, "2026-02-30", "2026-03-01").phase, .unknown)
    }
    func testOverrideNeedsReasonAndDoesNotInventBlock() {
        let value = document()
        var association = WorkSleepAssociation(sleepID: "night", precedingDate: "2026-09-21", followingDate: "2026-09-22", timeZoneIdentifier: "America/New_York", plannedAt: late, recordedAt: late)
        association.overridePhase = .after
        XCTAssertFalse(association.isValid)
        association.overrideReason = "Reviewed swapped shift"
        let result = value.classify(association, basis: .planned, asOf: late)
        XCTAssertEqual(result.phase, .after); XCTAssertNil(result.blockID)
        XCTAssertTrue(result.isOverride)
    }
    func testUnknownActualTimesRemainUnknownAndValidation() {
        var occurrence = WorkOccurrence(workDate: "2026-09-22", timeZoneIdentifier: "America/New_York", attendance: .worked, recordedAt: early)
        XCTAssertNil(occurrence.actualStart); XCTAssertNil(occurrence.actualEnd)
        occurrence.actualStart = late; occurrence.actualEnd = early
        XCTAssertFalse(occurrence.isValid)
        var value = document(); value.rosters[0].weekdays = [0]
        XCTAssertFalse(value.isValid)
    }
    func testBatchClassificationMatchesSingleResultAndToleratesRepeatedAssociation() {
        let association = WorkSleepAssociation(sleepID: "night", precedingDate: "2026-09-21", followingDate: "2026-09-22", timeZoneIdentifier: "America/New_York", plannedAt: late, recordedAt: late)
        var value = document(); value.associations = [association]
        XCTAssertEqual(Set(value.classificationsBySleepID(["night", "unreviewed"], basis: .planned, asOf: late).keys), ["night"])
        XCTAssertEqual(value.classifications([association, association], basis: .planned, asOf: late)[association.id], value.classify(association, basis: .planned, asOf: late))
    }
    func testSleepIndexPreservesLatestAndFirstEqualTimestampSemantics() {
        var first = WorkSleepAssociation(sleepID: "night", precedingDate: "2026-09-21", followingDate: "2026-09-22", timeZoneIdentifier: "America/New_York", plannedAt: early, recordedAt: early)
        first.overridePhase = .entering; first.overrideReason = "First reviewed phase"
        var latest = first; latest.id = UUID(); latest.recordedAt = late
        latest.overridePhase = .after; latest.overrideReason = "Later reviewed phase"
        var tied = latest; tied.id = UUID(); tied.overridePhase = .off
        var future = latest; future.id = UUID(); future.recordedAt = late.addingTimeInterval(1)
        var unrelated = latest; unrelated.id = UUID(); unrelated.sleepID = "unrelated"
        var value = document(); value.associations = [first, latest, tied, future, unrelated]
        XCTAssertEqual(value.association(for: "night", asOf: late)?.id, latest.id)
        let result = value.classificationsBySleepID(["night", "absent"], basis: .planned, asOf: late)
        XCTAssertEqual(Set(result.keys), ["night"])
        XCTAssertEqual(result["night"]?.phase, .after)
    }
    func testPlannedExceptionDoesNotEraseConfirmedAttendance() {
        var value = document()
        value.occurrences = [.init(workDate: "2026-09-22", timeZoneIdentifier: "America/New_York", attendance: .worked, recordedAt: early), .init(workDate: "2026-09-23", timeZoneIdentifier: "America/New_York", attendance: .notWorked, recordedAt: early), .init(workDate: "2026-09-22", timeZoneIdentifier: "America/New_York", plannedWorking: false, recordedAt: late)]
        XCTAssertEqual(context(value, "2026-09-22", "2026-09-23", basis: .confirmed).phase, .after)
    }
    func testResolvedShiftAnchorsPreserveIndependentRevisionsAndCancellation() throws {
        var value = document(), shift = WorkOccurrence(workDate: "2026-09-22", timeZoneIdentifier: "America/New_York", plannedWorking: true, recordedAt: early)
        shift.scheduledTimesReviewed = true; shift.scheduledStart = early; shift.scheduledEnd = early.addingTimeInterval(3600)
        value.occurrences = [shift]
        XCTAssertEqual(value.resolvedWorkDate("2026-09-22", timeZoneIdentifier: "America/New_York", asOf: late)?.scheduledEnd, shift.scheduledEnd)
        value.occurrences.append(.init(workDate: "2026-09-22", timeZoneIdentifier: "America/New_York", attendance: .worked, recordedAt: late))
        XCTAssertEqual(value.resolvedWorkDate("2026-09-22", timeZoneIdentifier: "America/New_York", asOf: late)?.shiftSourceID, shift.id)
        value.occurrences.append(.init(workDate: "2026-09-22", timeZoneIdentifier: "America/New_York", plannedWorking: false, recordedAt: late.addingTimeInterval(1)))
        XCTAssertNil(value.resolvedWorkDate("2026-09-22", timeZoneIdentifier: "America/New_York", asOf: late.addingTimeInterval(1))?.scheduledStart)
    }
    func testExplicitAnchorClearDoesNotEraseOtherAnchorHistory() {
        var value = document(), shift = WorkOccurrence(workDate: "2026-09-22", timeZoneIdentifier: "America/New_York", plannedWorking: true, recordedAt: early)
        shift.scheduledStart = early; shift.scheduledEnd = early.addingTimeInterval(3600); shift.plannedBreakAt = early.addingTimeInterval(1800)
        var clear = WorkOccurrence(workDate: shift.workDate, timeZoneIdentifier: shift.timeZoneIdentifier, recordedAt: late)
        clear.scheduledTimesReviewed = true; value.occurrences = [shift, clear]
        let resolved = value.resolvedWorkDate(shift.workDate, timeZoneIdentifier: shift.timeZoneIdentifier, asOf: late)
        XCTAssertNil(resolved?.scheduledStart); XCTAssertEqual(resolved?.shiftSourceID, clear.id)
        XCTAssertEqual(resolved?.plannedBreakAt, shift.plannedBreakAt)
    }
    func testInvalidAnalysisTimestampCannotClassify() {
        let association = WorkSleepAssociation(sleepID: "night", precedingDate: "2026-09-21", followingDate: "2026-09-22", timeZoneIdentifier: "America/New_York", plannedAt: late, recordedAt: late)
        XCTAssertEqual(document().classify(association, basis: .planned, asOf: Date(timeIntervalSince1970: .infinity)).phase, .unknown)
    }
    func testDateResolverAcceptsCanonicalUTCZoneName() {
        var value = document(); value.rosters[0].timeZoneIdentifier = "UTC"
        XCTAssertEqual(value.resolvedWorkDate("2026-09-22", timeZoneIdentifier: "GMT", asOf: late)?.plannedWorking, true)
    }
    func testRevisionRoundTripAndDuplicateIDsRejected() throws {
        var value = document()
        XCTAssertEqual(try JSONDecoder().decode(WorkContextDocument.self, from: JSONEncoder().encode(value)), value)
        value.rosters.append(value.rosters[0]); XCTAssertFalse(value.isValid)
    }
}
