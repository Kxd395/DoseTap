import XCTest
@testable import DoseCore

/// External event-link acceptance draft; no DoseCore implementation or test-target registration yet.
final class WorkSleepEventDraftTests: XCTestCase {
    private let sleep = Date(timeIntervalSince1970: 1_790_000_000)
    private func shift(_ position: Int, block: String = "explicit:block") -> WorkShiftEvent {
        var value = WorkShiftEvent(timeZoneIdentifier: "America/New_York", recordedAt: sleep.addingTimeInterval(-3600))
        value.status = .worked; value.attendanceConfirmed = true
        value.blockID = block; value.firstShiftDate = "2026-09-20"; value.position = position; value.blockShiftCount = 3
        return value
    }
    private func association(before: WorkWakingStatus, after: WorkWakingStatus,
                             preceding: UUID? = nil, following: UUID? = nil) -> WorkSleepAssociation {
        var value = WorkSleepAssociation(sleepID: "session:overnight", precedingDate: "2026-09-21", followingDate: "2026-09-22",
            timeZoneIdentifier: "America/New_York", plannedAt: sleep.addingTimeInterval(-1800), recordedAt: sleep.addingTimeInterval(36_000))
        value.daytimeAssociationReviewed = false
        value.eventContext = .init(mainSleepStart: sleep, mainSleepEnd: sleep.addingTimeInterval(28_800),
            precedingStatus: before, followingStatus: after, precedingShiftID: preceding, followingShiftID: following,
            wakingPeriodsReviewed: true)
        return value
    }
    private func classify(_ value: WorkSleepAssociation, shifts: [WorkShiftEvent], basis: WorkContextBasis = .confirmed) -> WorkPhaseResult {
        var document = WorkContextDocument(); document.schemaVersion = 3; document.shiftEvents = shifts; document.associations = [value]
        return document.classify(value, basis: basis, asOf: sleep.addingTimeInterval(40_000))
    }
    func testReviewedOvernightEventLinksUseOneExplicitBlockWithoutInventingActualTimes() {
        let first = shift(1), second = shift(2)
        let value = association(before: .work, after: .work, preceding: first.shiftID, following: second.shiftID)
        let result = classify(value, shifts: [first, second])
        XCTAssertEqual(result.phase, .between); XCTAssertEqual(result.classificationVersion, 2)
        XCTAssertEqual(result.precedingPosition, 1); XCTAssertEqual(result.followingPosition, 2)
        XCTAssertEqual(result.blockID, "explicit:block"); XCTAssertNil(first.actualMinutes)
    }
    func testUnknownAttendanceOrUnrelatedBlockCannotBecomeConfirmedBetween() {
        var first = shift(1); var second = shift(2)
        first.scheduledEnd = sleep.addingTimeInterval(-60)
        let value = association(before: .work, after: .work, preceding: first.shiftID, following: second.shiftID)
        second.status = .scheduled; second.attendanceConfirmed = false
        XCTAssertEqual(classify(value, shifts: [first, second]).phase, .unknown)
        XCTAssertEqual(classify(value, shifts: [first, second], basis: .planned).phase, .between)
        first.scheduledEnd = nil
        XCTAssertEqual(classify(value, shifts: [first, second], basis: .planned).phase, .unknown, "Worked without recorded planned evidence cannot invent a plan")
        second.status = .worked; second.attendanceConfirmed = true; second.blockID = "another:block"
        XCTAssertEqual(classify(value, shifts: [first, second]).phase, .unknown)
    }
    func testMissingSleepBoundaryOrNapRoleCannotAdvanceCycle() {
        let next = shift(1); var value = association(before: .off, after: .work, following: next.shiftID)
        XCTAssertEqual(classify(value, shifts: [next]).phase, .entering)
        value.isMainSleep = false
        XCTAssertEqual(classify(value, shifts: [next]).phase, .unknown)
        value.isMainSleep = true; value.eventContext?.mainSleepEnd = nil
        XCTAssertEqual(classify(value, shifts: [next]).phase, .unknown)
    }
    func testReviewedLaterMainSleepIndexIsExplicitAndNeverInferredFromDates() {
        var value = association(before: .off, after: .off)
        XCTAssertNil(classify(value, shifts: []).postBlockMainSleepIndex)
        value.eventContext?.postBlockMainSleepIndex = 3
        let result = classify(value, shifts: [])
        XCTAssertEqual(result.phase, .off); XCTAssertEqual(result.postBlockMainSleepIndex, 3)
        XCTAssertEqual(result.positionLabel, "Post-block main sleep 3")
    }
    func testMorningCancellationDoesNotRewriteCapturedAnticipatedWork() throws {
        var planned = shift(1); planned.status = .scheduled; planned.attendanceConfirmed = false
        var document = WorkContextDocument(); document.schemaVersion = 3; document.shiftEvents = [planned]
        document.occurrences = [.init(workDate: "2026-09-21", timeZoneIdentifier: "America/New_York",
            plannedWorking: false, recordedAt: sleep.addingTimeInterval(-4000))]
        let capture = try XCTUnwrap(document.capturePlan(preSleepLogID: "pre-sleep", sessionID: "session:overnight",
            at: sleep.addingTimeInterval(-3000)))
        var cancelled = planned; cancelled.id = UUID(); cancelled.status = .notWorked
        cancelled.attendanceConfirmed = true; cancelled.recordedAt = sleep.addingTimeInterval(30_000)
        document.shiftEvents?.append(cancelled)
        var value = association(before: .off, after: .off, following: planned.shiftID)
        value.planSnapshotID = capture.id; document.associations = [value]
        XCTAssertEqual(document.classify(value, basis: .planned, asOf: sleep.addingTimeInterval(40_000)).phase, .entering)
        XCTAssertEqual(document.classify(value, basis: .confirmed, asOf: sleep.addingTimeInterval(40_000)).phase, .off)
    }
    func testLaterOffAnswerCannotInventOffEvidenceInAnEarlierCapturedPlan() throws {
        var planned = shift(1); planned.status = .scheduled; planned.attendanceConfirmed = false
        var document = WorkContextDocument(); document.schemaVersion = 3; document.shiftEvents = [planned]
        let capture = try XCTUnwrap(document.capturePlan(preSleepLogID: "pre-sleep", sessionID: "session:overnight",
            at: sleep.addingTimeInterval(-3000)))
        var value = association(before: .off, after: .work, following: planned.shiftID)
        value.planSnapshotID = capture.id; document.associations = [value]
        XCTAssertEqual(document.classify(value, basis: .planned, asOf: sleep.addingTimeInterval(40_000)).phase, .unknown)
    }

}
