import XCTest
@testable import DoseCore

final class SleepIntervalCoverageTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)
    private func sample(_ from: Double, _ to: Double, _ asleep: Bool = true) -> RecordedSleepInterval {
        .init(start: anchor.addingTimeInterval(from * 60), end: anchor.addingTimeInterval(to * 60), asleep: asleep)
    }
    private func coverage(_ minutes: Double, _ samples: [RecordedSleepInterval]) throws -> SleepIntervalCoverage {
        try XCTUnwrap(SleepIntervalCoverage.calculate(start: anchor,
            end: anchor.addingTimeInterval(minutes * 60), intervals: samples))
    }

    func testSeparatedBlocksRemainInWindowAndGapIsUnmeasured() throws {
        // 22:00-01:00 and 02:45-04:45; a later outside nap is excluded.
        let value = try coverage(405, [sample(0, 180), sample(285, 405), sample(600, 660)])
        XCTAssertEqual(value.asleepMinutes, 300)
        XCTAssertEqual(value.awakeMinutes, 0)
        XCTAssertEqual(value.coveredMinutes, 300)
        XCTAssertEqual(value.unmeasuredMinutes, 105)
        XCTAssertEqual(value.intervalMinutes, 405)
        XCTAssertEqual(value.status, .partial)
    }

    func testNoCoverageIsNotAnObservedZero() throws {
        let empty = try coverage(60, [])
        XCTAssertEqual(empty.status, .unavailable)
        XCTAssertNil(empty.asleepMinutes)
        XCTAssertNil(empty.awakeMinutes)
        XCTAssertEqual(empty.unmeasuredMinutes, 60)
        let awake = try coverage(60, [sample(0, 60, false)])
        XCTAssertEqual(awake.status, .available)
        XCTAssertEqual(awake.asleepMinutes, 0)
        XCTAssertEqual(awake.awakeMinutes, 60)
        let partial = try coverage(60, [sample(10, 20, false)])
        XCTAssertEqual(partial.status, .partial)
        XCTAssertEqual(partial.asleepMinutes, 0) // Zero only within observed coverage.
        XCTAssertEqual(partial.unmeasuredMinutes, 50)
    }

    func testClippingUnionAndAwakeOverridePreserveExistingPostDosePolicy() throws {
        let inputs = [sample(-20, 60), sample(30, 130), sample(40, 50, false)]
        let value = try coverage(120, inputs)
        XCTAssertEqual(value.asleepMinutes, 110)
        XCTAssertEqual(value.awakeMinutes, 10)
        XCTAssertEqual(value.coveragePercent, 100)
        let postDose = PostDoseSleepEstimate.calculate(dose2: anchor, finalWake: anchor.addingTimeInterval(7200), intervals: inputs)
        XCTAssertEqual(postDose?.asleepMinutes, value.asleepMinutes)
        XCTAssertEqual(postDose?.coveredMinutes, value.coveredMinutes)
    }

    func testReorderAndDuplicatesDoNotChangeResult() throws {
        let inputs = [sample(0, 20), sample(10, 30), sample(15, 25, false)]
        XCTAssertEqual(try coverage(60, inputs), try coverage(60, Array(inputs.reversed()) + inputs))
    }

    func testTouchingEndpointsDoNotContributeCoverage() throws {
        let value = try coverage(60, [sample(-10, 0), sample(60, 90), sample(20, 20)])
        XCTAssertEqual(value.status, .unavailable)
    }

    func testInvalidWindowsAndSamplesCannotInventTime() throws {
        for end in [anchor, anchor.addingTimeInterval(-1), Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: .nan)] {
            XCTAssertNil(SleepIntervalCoverage.calculate(start: anchor, end: end, intervals: []))
        }
        XCTAssertNil(SleepIntervalCoverage.calculate(start: Date(timeIntervalSince1970: -.infinity), end: anchor, intervals: []))
        let value = try coverage(60, [sample(40, 20), sample(.nan, 30), sample(0, .infinity), sample(10, 20)])
        XCTAssertEqual(value.asleepMinutes, 10)
        XCTAssertEqual(value.unmeasuredMinutes, 50)
    }

    func testSubsecondGapIsRetainedInCoverageStatus() throws {
        let value = try coverage(1, [sample(0, 0.5), sample(0.5 + 0.25 / 60, 1)])
        XCTAssertEqual(value.status, .partial)
        XCTAssertEqual(value.unmeasuredMinutes, 0.25 / 60, accuracy: 0.000001)
    }

    func testDSTUsesElapsedTimeAndResultEncodesVersion() throws {
        let parser = ISO8601DateFormatter()
        let start = try XCTUnwrap(parser.date(from: "2026-11-01T00:30:00-04:00"))
        let end = try XCTUnwrap(parser.date(from: "2026-11-01T02:30:00-05:00"))
        let result = try XCTUnwrap(SleepIntervalCoverage.calculate(start: start, end: end,
            intervals: [.init(start: start, end: end, asleep: true)]))
        XCTAssertEqual(result.intervalMinutes, 180)
        XCTAssertEqual(result.asleepMinutes, 180)
        XCTAssertEqual(result.derivationVersion, "recorded_interval_coverage_v1")
        XCTAssertEqual(try JSONDecoder().decode(SleepIntervalCoverage.self, from: JSONEncoder().encode(result)), result)
    }

    func testMinuteGridOracleAndConservation() throws {
        for mask in 0..<256 {
            let inputs = (0..<4).flatMap { minute -> [RecordedSleepInterval] in
                var entries: [RecordedSleepInterval] = []
                if mask & (1 << minute) != 0 { entries.append(sample(Double(minute), Double(minute + 1))) }
                if mask & (1 << (minute + 4)) != 0 { entries.append(sample(Double(minute), Double(minute + 1), false)) }
                return entries
            }
            let value = try coverage(4, inputs)
            let awake = (0..<4).filter { mask & (1 << ($0 + 4)) != 0 }.count
            let asleep = (0..<4).filter { mask & (1 << $0) != 0 && mask & (1 << ($0 + 4)) == 0 }.count
            XCTAssertEqual(value.coveredMinutes, Double(awake + asleep))
            XCTAssertEqual(value.asleepMinutes ?? 0, Double(asleep))
            XCTAssertEqual(value.awakeMinutes ?? 0, Double(awake))
            XCTAssertEqual(value.coveredMinutes + value.unmeasuredMinutes, value.intervalMinutes)
        }
    }
}
