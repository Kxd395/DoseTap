import XCTest
@testable import DoseCore

final class WorkShiftTimingDraftTests: XCTestCase {
    private let sleep = Date(timeIntervalSince1970: 1_790_000_000)
    func testActualGapsUseExplicitLinksAndUnknownTimesCannotBecomeScheduledHours() throws {
        let asOf = sleep.addingTimeInterval(72_000)
        var previous = WorkShiftEvent(timeZoneIdentifier: "UTC", recordedAt: asOf)
        previous.status = .worked; previous.attendanceConfirmed = true; previous.actualTimePrecision = .reportedMinute
        previous.actualStart = sleep.addingTimeInterval(-21_600); previous.actualEnd = sleep.addingTimeInterval(-3600)
        previous.scheduledStart = sleep.addingTimeInterval(-46_800); previous.scheduledEnd = sleep
        var following = WorkShiftEvent(timeZoneIdentifier: "UTC", recordedAt: asOf)
        following.status = .worked; following.attendanceConfirmed = true; following.actualTimePrecision = .reportedMinute
        following.actualStart = sleep.addingTimeInterval(36_000); following.actualEnd = sleep.addingTimeInterval(54_000)
        var association = WorkSleepAssociation(sleepID: "session:actual", precedingDate: "2026-09-21", followingDate: "2026-09-22",
            timeZoneIdentifier: "UTC", plannedAt: sleep, recordedAt: asOf)
        association.eventContext = .init(mainSleepStart: sleep, mainSleepEnd: sleep.addingTimeInterval(28_800),
            precedingStatus: .work, followingStatus: .work, precedingShiftID: previous.shiftID,
            followingShiftID: following.shiftID, wakingPeriodsReviewed: true)
        var document = WorkContextDocument(); document.schemaVersion = 3
        document.shiftEvents = [previous, following]; document.associations = [association]
        let actual = document.timingEvidence(for: association, lookbackStart: sleep.addingTimeInterval(-86_400),
            lookbackEnd: sleep, asOf: asOf)
        XCTAssertEqual(actual.shiftEndToMainSleep.metric.value, 60)
        XCTAssertEqual(actual.betweenShifts.metric.value, 660)
        XCTAssertEqual(actual.recordedWorkMinutes.metric.value, 300)
        let batch = document.timingEvidences(for: [association], lookbackSeconds: 86400, asOf: asOf)
        XCTAssertEqual(batch[association.id]?.recordedWorkMinutes.metric.value, actual.recordedWorkMinutes.metric.value)
        var missingSleep = association; missingSleep.eventContext?.mainSleepStart = nil
        let unanchored = document.timingEvidence(for: missingSleep, lookbackStart: sleep.addingTimeInterval(-86400), lookbackEnd: sleep, asOf: asOf)
        XCTAssertNil(unanchored.recordedWorkMinutes.metric.value, "A missing main-sleep start cannot be replaced by the supplied report clock")
        XCTAssertEqual(unanchored.betweenShifts.metric.value, 660)
        previous.actualTimePrecision = .approximate; document.shiftEvents = [previous, following]
        XCTAssertNil(document.timingEvidence(for: association, lookbackStart: sleep.addingTimeInterval(-86400), lookbackEnd: sleep, asOf: asOf).shiftEndToMainSleep.metric.value)
        previous.actualTimePrecision = .reportedMinute
        previous.actualEnd = nil; document.shiftEvents = [previous, following]
        let missing = document.timingEvidence(for: association, lookbackStart: sleep.addingTimeInterval(-86_400),
            lookbackEnd: sleep, asOf: asOf)
        XCTAssertNil(missing.shiftEndToMainSleep.metric.value)
        XCTAssertNil(missing.betweenShifts.metric.value)
        XCTAssertNil(missing.recordedWorkMinutes.metric.value, "Scheduled 13-hour span cannot fill missing actual work")
    }
}
