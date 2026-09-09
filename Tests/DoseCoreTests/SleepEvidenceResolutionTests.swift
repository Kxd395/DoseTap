import XCTest
@testable import DoseCore

final class SleepEvidenceResolutionTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func date(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    private func sample(_ id: String, _ start: Double, _ end: Double, _ stage: SleepEvidenceSample.Stage) -> SleepEvidenceSample {
        .init(sampleID: id, start: date(start), end: date(end), rawCategory: 99, stage: stage,
              origin: .init(sourceName: "Synthetic watch", bundleIdentifier: "test.sleep"))
    }
    private func resolve(_ samples: [SleepEvidenceSample]) throws -> SleepEvidenceResolution {
        try XCTUnwrap(.calculate(start: date(0), end: date(60), samples: samples))
    }
    func testSleepAwakeConflictIsUnmeasuredAndEvidenceIsRetained() throws {
        let raw = [sample("sleep", -10, 60, .core), sample("awake", 20, 30, .awake)]
        let result = try resolve(raw)
        XCTAssertEqual(result.samples, raw)
        XCTAssertEqual(result.coverage.asleepMinutes, 50)
        XCTAssertEqual(result.coverage.awakeMinutes, 0)
        XCTAssertEqual(result.coverage.unmeasuredMinutes, 10)
        XCTAssertEqual(result.conflictMinutes, 10)
        XCTAssertEqual(result.status, .conflict)
        XCTAssertEqual(result.slices.first?.start, date(0))
        XCTAssertEqual(result.slices.filter { $0.state == .conflict }.first?.sampleIDs, ["awake", "sleep"])
    }
    func testDuplicatesAndOrderCannotChooseAWinningSource() throws {
        let raw = [sample("a", 0, 40, .core), sample("b", 20, 60, .rem)]
        let first = try resolve(raw), repeated = try resolve(raw.reversed() + raw)
        XCTAssertEqual(first.slices, repeated.slices)
        XCTAssertEqual(first.coverage, repeated.coverage)
        XCTAssertEqual(first.conflictMinutes, 20)
        XCTAssertEqual(first.coverage.asleepMinutes, 40)
    }
    func testUnspecifiedAndDetailedSleepAgreeButUnknownDoesNotBecomeSleep() throws {
        let result = try resolve([sample("a", 0, 60, .asleep), sample("b", 0, 60, .deep),
                                  sample("bed", 0, 60, .inBed), sample("unknown", 15, 25, .unknown)])
        XCTAssertEqual(result.coverage.asleepMinutes, 50)
        XCTAssertEqual(result.conflictMinutes, 10)
        XCTAssertEqual(result.slices.first?.state, .asleep)
    }
    func testAllAwakeAndNoDataHaveDifferentMeanings() throws {
        let awake = try resolve([sample("awake", 0, 60, .awake)])
        XCTAssertEqual(awake.coverage.asleepMinutes, 0)
        XCTAssertEqual(awake.status, .available)
        let empty = try resolve([])
        XCTAssertNil(empty.coverage.asleepMinutes)
        XCTAssertEqual(empty.status, .unavailable)
        let unknown = try resolve([sample("u", 0, 60, .unknown), sample("b", 0, 60, .inBed)])
        XCTAssertNil(unknown.coverage.asleepMinutes)
        XCTAssertEqual(unknown.conflictMinutes, 0)
    }
    func testGapsOutsideEvidenceAndInvalidSamplesDoNotFillCoverage() throws {
        let raw = [sample("a", -10, 10, .core), sample("b", 50, 70, .core),
                   sample("outside", 80, 90, .awake), sample("reversed", 30, 20, .awake)]
        let result = try resolve(raw)
        XCTAssertEqual(result.coverage.asleepMinutes, 20)
        XCTAssertEqual(result.coverage.unmeasuredMinutes, 40)
        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.rejectedSampleCount, 1)
        XCTAssertEqual(result.samples, raw)
        XCTAssertNil(SleepEvidenceResolution.calculate(start: date(60), end: date(0), samples: raw))
    }
    func testSourceSnapshotRoundTripAndFreshDeletionRecompute() throws {
        var origin = SleepEvidenceSample.Origin(sourceName: "Test", bundleIdentifier: "test.source")
        origin.sourceVersion = "1.2"; origin.productType = "Watch"; origin.operatingSystemVersion = "26.5.0"
        origin.timeZoneID = "America/New_York"; origin.receivedAt = date(90)
        origin.deviceModel = "Synthetic"; origin.deviceSoftwareVersion = "1"
        let raw = SleepEvidenceSample(sampleID: "sample-A", start: date(-10), end: date(60),
            rawCategory: 3, stage: .core, origin: origin)
        let decoded = try JSONDecoder().decode(SleepEvidenceSample.self, from: JSONEncoder().encode(raw))
        XCTAssertEqual(decoded, raw)
        let conflict = try resolve([raw, sample("b", 10, 20, .awake)])
        XCTAssertEqual(conflict.conflictMinutes, 10)
        XCTAssertEqual(try resolve([raw]).conflictMinutes, 0)
        XCTAssertEqual(try resolve([raw]).coverage.asleepMinutes, 60)
    }
    func testAbsoluteRepeatedHourAndTouchingEndpoints() throws {
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-11-01T01:30:00-04:00"))
        let end = try XCTUnwrap(formatter.date(from: "2026-11-01T01:30:00-05:00"))
        let midpoint = start.addingTimeInterval(1800)
        let origin = SleepEvidenceSample.Origin(sourceName: "Test", bundleIdentifier: nil)
        let samples = [SleepEvidenceSample(sampleID: "a", start: start, end: midpoint, rawCategory: 1, stage: .asleep, origin: origin),
                       SleepEvidenceSample(sampleID: "b", start: midpoint, end: end, rawCategory: 2, stage: .awake, origin: origin)]
        let result = try XCTUnwrap(SleepEvidenceResolution.calculate(start: start, end: end, samples: samples))
        XCTAssertEqual(result.coverage.asleepMinutes, 30)
        XCTAssertEqual(result.coverage.awakeMinutes, 30)
        XCTAssertEqual(result.conflictMinutes, 0)
    }
}
