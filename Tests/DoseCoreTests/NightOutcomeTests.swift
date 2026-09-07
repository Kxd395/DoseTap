import XCTest
@testable import DoseCore

final class NightOutcomeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func sample(_ from: Double, _ to: Double, _ asleep: Bool) -> RecordedSleepInterval {
        .init(start: start.addingTimeInterval(from * 60), end: start.addingTimeInterval(to * 60), asleep: asleep)
    }

    func testSleepEstimateClipsUnionsAndSubtractsAwake() {
        let estimate = PostDoseSleepEstimate.calculate(dose2: start, finalWake: start.addingTimeInterval(120 * 60),
            intervals: [sample(-20, 60, true), sample(30, 130, true), sample(40, 50, false)])
        XCTAssertEqual(estimate?.asleepMinutes, 110)
        XCTAssertEqual(estimate?.coveredMinutes, 120)
    }

    func testMissingIsNotZeroAndGapsAreUnmeasured() {
        XCTAssertNil(PostDoseSleepEstimate.calculate(dose2: start, finalWake: start, intervals: []))
        XCTAssertNil(PostDoseSleepEstimate.calculate(dose2: start, finalWake: start.addingTimeInterval(3600), intervals: []))
        let partial = PostDoseSleepEstimate.calculate(dose2: start, finalWake: start.addingTimeInterval(3600), intervals: [sample(20, 40, true)])
        XCTAssertEqual(partial?.asleepMinutes, 20)
        XCTAssertEqual(partial?.coveredMinutes, 20)
        XCTAssertEqual(partial?.intervalMinutes, 60)
        let awake = PostDoseSleepEstimate.calculate(dose2: start, finalWake: start.addingTimeInterval(3600), intervals: [sample(0, 60, false)])
        XCTAssertEqual(awake?.asleepMinutes, 0)
    }

    func testMedianCountsOnlyUsableObservationsAndIQRIsExplicit() {
        let summary = DiaryMetricSummary([nil, 10, 20, 30, 40, .nan, -.infinity, -1])
        XCTAssertEqual(summary.count, 4)
        XCTAssertEqual(summary.median, 25)
        XCTAssertEqual(summary.lowerQuartile, 17.5)
        XCTAssertEqual(summary.upperQuartile, 32.5)
        XCTAssertNil(DiaryMetricSummary([]).median)
    }

    func testDiaryValidationAndLegacyWakeMapping() {
        var diary = NightOutcomeDiary()
        XCTAssertEqual(diary.wakeMethod, .unknown)
        XCTAssertNil(diary.sleepiness)
        diary.sleepiness = 11
        XCTAssertNotNil(diary.validationError(now: start))
        diary.sleepiness = 0
        diary.assessedAt = start
        XCTAssertNil(diary.validationError(now: start))
        diary.assessedAt = start.addingTimeInterval(1)
        XCTAssertNotNil(diary.validationError(now: start))
        XCTAssertEqual(Dose2WakeKind(legacy: "alarm_then_snooze"), .alarm)
        XCTAssertEqual(Dose2WakeKind(legacy: "already_awake"), .other)
        XCTAssertEqual(Dose2WakeKind(legacy: nil), .unknown)
    }
}
