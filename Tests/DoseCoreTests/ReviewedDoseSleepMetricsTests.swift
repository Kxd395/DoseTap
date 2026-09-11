import XCTest
@testable import DoseCore

final class ReviewedDoseSleepMetricsTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func date(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }
    private func dose(_ type: String, _ seconds: Double) -> StoredDoseEvent {
        .init(id: type, eventType: type, timestamp: date(seconds), sessionDate: "2027-01-15", sessionId: "night")
    }
    private func projection(_ bands: [(Double, Double, SleepEvidenceSample.Stage)]) throws -> ReviewedNightSleepProjection {
        let samples = bands.enumerated().map { index, band in
            SleepEvidenceSample(sampleID: "\(index)", start: date(band.0), end: date(band.1), rawCategory: 99,
                                stage: band.2, origin: .init(sourceName: "Synthetic", bundleIdentifier: nil))
        }
        let window = ReviewedSleepWindow(sessionID: "night", start: date(0), end: date(14400),
            entryTimeZone: TimeZone(secondsFromGMT: 0)!, reviewedAt: date(15000))
        let evidence = try XCTUnwrap(SleepEvidenceResolution.calculate(start: window.start, end: window.end, samples: samples))
        return try XCTUnwrap(.calculate(window: window, evidence: evidence, generatedAt: date(15000)))
    }
    private var bands: [(Double, Double, SleepEvidenceSample.Stage)] {
        [(0, 600, .awake), (600, 9600, .asleep), (9600, 10920, .awake), (10920, 14400, .asleep)]
    }
    private func result(_ custom: [(Double, Double, SleepEvidenceSample.Stage)]? = nil,
                        first: Double = 0, second: Double = 10080) throws -> ReviewedDoseSleepMetrics {
        .calculate(projection: try projection(custom ?? bands), doses: [dose("dose1", first), dose("dose2", second)])
    }
    func testSameEpisodeDurationsAndProvenance() throws {
        let value = try result()
        XCTAssertEqual(value.dose1ToSleep.seconds, 600)
        XCTAssertEqual(value.awakeningToDose2.seconds, 480)
        XCTAssertEqual(value.dose2ToSleep.seconds, 840)
        XCTAssertEqual(value.dose2Awakening.seconds, 1320)
        XCTAssertEqual(value.dose2ToSleep.start, date(10080))
        XCTAssertEqual(value.dose2ToSleep.end, date(10920))
        XCTAssertEqual(value.dose2ToSleep.startSource, .recordedDose)
        XCTAssertEqual(value.dose2ToSleep.endSource, .appleHealthConsensus)
        XCTAssertEqual(value.derivationVersion, "reviewed_dose_sleep_v1")
        XCTAssertEqual(value.generatedAt, date(15000))
        XCTAssertEqual(value.sessionID, "night")
        XCTAssertEqual(try JSONDecoder().decode(ReviewedDoseSleepMetrics.self, from: JSONEncoder().encode(value)), value)
    }
    func testExactAndAdjacentDose2Boundaries() throws {
        for (second, pre, post) in [(9600.0, 0.0, 1320.0), (9601, 1, 1319), (10919, 1319, 1), (10920, 1320, 0)] {
            let value = try result(second: second)
            XCTAssertEqual(value.awakeningToDose2.seconds, pre)
            XCTAssertEqual(value.dose2ToSleep.seconds, post)
        }
        for second in [9599.0, 10921] {
            let value = try result(second: second)
            XCTAssertEqual(value.dose2ToSleep.reason, .alreadyAsleep)
            XCTAssertEqual(value.dose2ToSleep.status, .conflict)
            XCTAssertNil(value.dose2ToSleep.seconds)
        }
    }
    func testInitialOnsetExactBoundaryAndEarlierSleep() throws {
        XCTAssertEqual(try result(first: 600).dose1ToSleep.seconds, 0)
        XCTAssertEqual(try result(first: 599).dose1ToSleep.seconds, 1)
        XCTAssertEqual(try result(first: 601).dose1ToSleep.reason, .alreadyAsleep)
        XCTAssertEqual(try result(first: 9700).dose1ToSleep.reason, .alreadyAsleep)
        XCTAssertEqual(try result([(0, 14400, .asleep)]).dose1ToSleep.reason, .missingInitialOnset)
    }
    func testMissingAndSkippedDoseAreNotZero() throws {
        let p = try projection(bands)
        for doses in [[], [dose("dose1", 0)], [dose("dose1", 0), dose("dose2_skipped", 10080)]] {
            let value = ReviewedDoseSleepMetrics.calculate(projection: p, doses: doses)
            XCTAssertEqual(value.dose2ToSleep.reason, .missingDose)
            XCTAssertNil(value.dose2ToSleep.seconds)
        }
    }
    func testInvalidDoseRecordsFailClosed() throws {
        for doses in [[dose("dose1", 0), dose("dose1", 1)], [dose("dose2", 10080)],
                      [dose("dose1", 1), dose("dose2", 0)], [dose("dose1", -1)],
                      [dose("dose1", .nan)], [dose("dose1", 0), dose("dose2", 10080), dose("dose2_skipped", 10100)]] {
            let value = ReviewedDoseSleepMetrics.calculate(projection: try projection(bands), doses: doses)
            XCTAssertEqual(value.dose1ToSleep.reason, .invalidDoseRecords)
            XCTAssertNil(value.dose2ToSleep.seconds)
        }
    }
    func testGapsAndConflictsAreNotInventedOnsets() throws {
        let gap = [(0.0, 300.0, SleepEvidenceSample.Stage.awake), (600, 9600, .asleep),
                   (9600, 10920, .awake), (10920, 14400, .asleep)]
        XCTAssertEqual(try result(gap).dose1ToSleep.reason, .boundaryGap)
        XCTAssertEqual(try result(gap).dose2ToSleep.seconds, 840)
        let conflict = bands + [(300, 400, .asleep)]
        XCTAssertEqual(try result(conflict).dose1ToSleep.reason, .conflictingEvidence)
        XCTAssertEqual(try result(conflict).dose1ToSleep.status, .conflict)
        let postGap = [(0.0, 600.0, SleepEvidenceSample.Stage.awake), (600, 9600, .asleep),
                       (9600, 10500, .awake), (10920, 14400, .asleep)]
        let value = try result(postGap)
        XCTAssertEqual(value.awakeningToDose2.seconds, 480)
        XCTAssertEqual(value.dose2ToSleep.reason, .boundaryGap)
        XCTAssertNil(value.dose2Awakening.seconds)
        XCTAssertEqual(try result(postGap, second: 10500).awakeningToDose2.reason, .boundaryGap)
        XCTAssertEqual(try result(bands + [(10500, 10600, .asleep)]).dose2ToSleep.reason, .conflictingEvidence)
    }
    func testMissingReturnOrAwakeningAndAllAwake() throws {
        let noReturn = [(0.0, 600.0, SleepEvidenceSample.Stage.awake), (600, 9600, .asleep), (9600, 14400, .awake)]
        XCTAssertEqual(try result(noReturn).awakeningToDose2.seconds, 480)
        XCTAssertEqual(try result(noReturn).dose2ToSleep.reason, .missingReturn)
        let awake = try result([(0, 14400, .awake)])
        XCTAssertEqual(awake.dose1ToSleep.reason, .missingInitialOnset)
        XCTAssertEqual(awake.dose2ToSleep.reason, .missingAwakening)
        XCTAssertNil(awake.dose2ToSleep.seconds)
        XCTAssertEqual(try result([]).dose1ToSleep.reason, .boundaryGap)
    }
    func testSplitStagesReorderingAndFreshDeletion() throws {
        let split = [(0.0, 600.0, SleepEvidenceSample.Stage.awake), (600, 4000, .core), (4000, 9600, .rem),
                     (9600, 10920, .awake), (10920, 14400, .deep)]
        XCTAssertEqual(try result(split).dose2ToSleep, try result(Array(split.reversed()) + split).dose2ToSleep)
        XCTAssertEqual(try result(second: 10140).dose2ToSleep.seconds, 780)
        XCTAssertNil(try result([]).dose2ToSleep.seconds)
    }
    func testMalformedProjectionAndMismatchedSessionFailClosed() throws {
        let original = try projection(bands)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["bands"] = []
        let malformed = try JSONDecoder().decode(ReviewedNightSleepProjection.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(ReviewedDoseSleepMetrics.calculate(projection: malformed, doses: []).dose1ToSleep.reason, .invalidProjection)
        let wrong = StoredDoseEvent(id: "wrong", eventType: "dose1", timestamp: date(0), sessionDate: "2027-01-15", sessionId: "other")
        XCTAssertEqual(ReviewedDoseSleepMetrics.calculate(projection: original, doses: [wrong]).dose1ToSleep.reason, .invalidDoseRecords)
    }
    func testUnrelatedLaterConflictDoesNotEraseResolvedEpisode() throws {
        let value = try result(bands + [(12000, 13000, .awake)])
        XCTAssertEqual(value.dose2ToSleep.seconds, 840)
        let missingWake = [(0.0, 600.0, SleepEvidenceSample.Stage.awake), (600, 9000, .asleep),
                           (9600, 10920, .awake), (10920, 14400, .asleep)]
        XCTAssertEqual(try result(missingWake).dose2ToSleep.reason, .boundaryGap)
    }
    func testElapsedAcrossDSTUsesAbsoluteTimes() throws {
        let format = ISO8601DateFormatter()
        let start = try XCTUnwrap(format.date(from: "2026-11-01T01:30:00-04:00"))
        let end = try XCTUnwrap(format.date(from: "2026-11-01T01:30:00-05:00"))
        let windowEnd = end.addingTimeInterval(3600), now = end.addingTimeInterval(7200)
        let window = ReviewedSleepWindow(sessionID: "dst", start: start, end: windowEnd,
            entryTimeZone: TimeZone(identifier: "America/New_York")!, reviewedAt: now)
        let origin = SleepEvidenceSample.Origin(sourceName: "Synthetic", bundleIdentifier: nil)
        let samples = [SleepEvidenceSample(sampleID: "awake", start: start, end: end, rawCategory: 2, stage: .awake, origin: origin),
                       SleepEvidenceSample(sampleID: "sleep", start: end, end: windowEnd, rawCategory: 1, stage: .asleep, origin: origin)]
        let evidence = try XCTUnwrap(SleepEvidenceResolution.calculate(start: start, end: windowEnd, samples: samples))
        let p = try XCTUnwrap(ReviewedNightSleepProjection.calculate(window: window, evidence: evidence, generatedAt: now))
        let dose = StoredDoseEvent(id: "dst-dose", eventType: "dose1", timestamp: start, sessionDate: "2026-11-01", sessionId: "dst")
        XCTAssertEqual(ReviewedDoseSleepMetrics.calculate(projection: p, doses: [dose]).dose1ToSleep.seconds, 3600)
    }
}
