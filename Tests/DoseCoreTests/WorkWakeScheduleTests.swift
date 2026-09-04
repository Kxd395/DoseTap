import XCTest
@testable import DoseCore

final class WorkWakeScheduleTests: XCTestCase {
    private let parse = ISO8601DateFormatter()
    func testEachSelectedModeResolvesFridayWakeDateAndOneDayException() throws {
        let dose1 = try XCTUnwrap(parse.date(from: "2026-09-04T03:10:00Z"))
        let now = try XCTUnwrap(parse.date(from: "2026-09-04T06:10:00Z"))
        for mode in WorkWarningTarget.allCases {
            var plan = WorkWakeSchedule(timeZoneIdentifier: "America/New_York", workingWeekdays: [6], wakeMinutes: 420, target: mode, cutoffMinutes: 115, bufferMinutes: 305)
            let warning = try XCTUnwrap(plan.warning(sessionId: "night", sessionDate: "2026-09-03", dose1: dose1, now: now, doseTargetMinutes: 165))
            XCTAssertEqual(warning.wakeDate, "2026-09-04")
            XCTAssertEqual(warning.target, mode)
            plan.exceptions[warning.wakeDate] = WorkWakeException(isWorking: false, wakeMinutes: nil)
            XCTAssertNil(plan.warning(sessionId: "night", sessionDate: "2026-09-03", dose1: dose1, now: now, doseTargetMinutes: 165))
            XCTAssertEqual(plan.workingWeekdays, [6])
            let restored = try JSONDecoder().decode(WorkWakeSchedule.self, from: JSONEncoder().encode(plan))
            XCTAssertEqual(restored, plan)
        }
    }
    func testDSTGapAndRepeatedHourUseSavedTimezone() throws {
        let plan = WorkWakeSchedule(timeZoneIdentifier: "America/New_York", workingWeekdays: Set(1...7), wakeMinutes: 420, target: .fixedCutoff, cutoffMinutes: 150)
        let gap = try XCTUnwrap(plan.warning(sessionId: "gap", sessionDate: "2026-03-07", dose1: parse.date(from: "2026-03-08T04:45:00Z")!, now: parse.date(from: "2026-03-08T08:00:00Z")!, doseTargetMinutes: 165))
        XCTAssertEqual(gap.targetAt, parse.date(from: "2026-03-08T07:00:00Z"))
        var foldPlan = plan
        foldPlan.cutoffMinutes = 90
        let fold = try XCTUnwrap(foldPlan.warning(sessionId: "fold", sessionDate: "2026-10-31", dose1: parse.date(from: "2026-11-01T03:00:00Z")!, now: parse.date(from: "2026-11-01T06:00:00Z")!, doseTargetMinutes: 165))
        XCTAssertEqual(fold.targetAt, parse.date(from: "2026-11-01T05:30:00Z"))
    }

    func testRetrospectiveWarningUsesActualOccurrenceWithoutReopeningLiveWindow() throws {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = WorkWakeSchedule(timeZoneIdentifier: "UTC", workingWeekdays: Set(1...7), target: .doseTarget)
        let late = first.addingTimeInterval(241 * 60)
        XCTAssertNil(plan.warning(sessionId: "a", sessionDate: "2027-01-14", dose1: first, now: late, doseTargetMinutes: 165))
        XCTAssertNotNil(plan.warning(sessionId: "a", sessionDate: "2027-01-14", dose1: first, now: late, doseTargetMinutes: 165, retrospective: true))
        XCTAssertNil(plan.warning(sessionId: "a", sessionDate: "2027-01-14", dose1: first, now: first.addingTimeInterval(160 * 60), doseTargetMinutes: 165, retrospective: true))
    }

    func testUnknownScheduleAndClosedWindowDoNotProduceWorkAdvisory() throws {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(WorkWakeSchedule().warning(sessionId: "a", sessionDate: "2027-01-14", dose1: first, now: first.addingTimeInterval(180 * 60), doseTargetMinutes: 165))
        let configured = WorkWakeSchedule(timeZoneIdentifier: "UTC", workingWeekdays: Set(1...7), wakeMinutes: 420, target: .doseTarget, cutoffMinutes: 115, bufferMinutes: 60)
        XCTAssertNil(configured.warning(sessionId: "a", sessionDate: "2027-01-14", dose1: first, now: first.addingTimeInterval(240 * 60), doseTargetMinutes: 165))
        XCTAssertNil(configured.warning(sessionId: "a", sessionDate: "bad-date", dose1: first, now: first.addingTimeInterval(180 * 60), doseTargetMinutes: 165))
    }
}
