import XCTest
@testable import DoseCore

final class ReviewedNightSleepProjectionTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func date(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    private var window: ReviewedSleepWindow {
        .init(sessionID: "synthetic-night", start: date(0), end: date(405),
              entryTimeZone: TimeZone(secondsFromGMT: 0)!, reviewedAt: date(450))
    }
    private func sample(_ id: String, _ start: Double, _ end: Double,
                        _ stage: SleepEvidenceSample.Stage = .asleep) -> SleepEvidenceSample {
        .init(sampleID: id, start: date(start), end: date(end), rawCategory: 99, stage: stage,
              origin: .init(sourceName: "Private source", bundleIdentifier: "private.bundle"))
    }
    private func project(_ samples: [SleepEvidenceSample]) throws -> ReviewedNightSleepProjection {
        let evidence = try XCTUnwrap(SleepEvidenceResolution.calculate(start: date(0), end: date(405), samples: samples))
        return try XCTUnwrap(.calculate(window: window, evidence: evidence, generatedAt: date(480)))
    }

    func testSplitNightRetainsBothBlocksAndUnmeasuredGap() throws {
        let result = try project([sample("first", -10, 180), sample("second", 285, 420)])
        XCTAssertEqual(result.coverage.asleepMinutes, 300)
        XCTAssertEqual(result.coverage.unmeasuredMinutes, 105)
        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.bands.map(\.state), [.asleep, .unmeasured, .asleep])
        XCTAssertEqual(result.bands.first?.start, window.start)
        XCTAssertEqual(result.bands.last?.end, window.end)
        XCTAssertEqual(result.window, window)
        XCTAssertEqual(result.generatedAt, date(480))
    }

    func testStageChangesAndDuplicateSamplesDoNotCreateExtraBands() throws {
        let samples = [sample("first", 0, 100, .core), sample("second", 100, 405, .rem)]
        let first = try project(samples)
        XCTAssertEqual(first.bands.count, 1)
        XCTAssertEqual(first.bands.first?.state, .asleep)
        XCTAssertEqual(first, try project(samples.reversed() + samples))
    }

    func testConflictAndUnknownRemainUnmeasuredWithoutDiscardingKnownSleep() throws {
        let result = try project([sample("sleep", 0, 300), sample("awake", 100, 120, .awake),
                                  sample("unknown", 300, 405, .unknown)])
        XCTAssertEqual(result.status, .conflict)
        XCTAssertEqual(result.conflictMinutes, 20)
        XCTAssertEqual(result.coverage.asleepMinutes, 280)
        XCTAssertEqual(result.coverage.unmeasuredMinutes, 125)
        XCTAssertEqual(result.bands.map(\.state), [.asleep, .conflict, .asleep, .unmeasured])
    }

    func testEmptyAndObservedAwakeHaveDifferentValues() throws {
        let empty = try project([]), awake = try project([sample("awake", 0, 405, .awake)])
        XCTAssertEqual(empty.status, .unavailable)
        XCTAssertNil(empty.coverage.asleepMinutes)
        XCTAssertEqual(awake.status, .available)
        XCTAssertEqual(awake.coverage.asleepMinutes, 0)
        XCTAssertEqual(awake.coverage.awakeMinutes, 405)
    }

    func testRejectsMismatchedBoundsMalformedEvidenceAndInvalidGenerationTime() throws {
        let wrong = try XCTUnwrap(SleepEvidenceResolution.calculate(start: date(1), end: date(405), samples: []))
        XCTAssertNil(ReviewedNightSleepProjection.calculate(window: window, evidence: wrong, generatedAt: date(480)))
        let invalid = try XCTUnwrap(SleepEvidenceResolution.calculate(start: date(0), end: date(405),
            samples: [sample("invalid", 30, 20)]))
        XCTAssertNil(ReviewedNightSleepProjection.calculate(window: window, evidence: invalid, generatedAt: date(480)))
        let valid = try XCTUnwrap(SleepEvidenceResolution.calculate(start: date(0), end: date(405), samples: []))
        for time in [date(440), Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: .nan)] {
            XCTAssertNil(ReviewedNightSleepProjection.calculate(window: window, evidence: valid, generatedAt: time))
        }
    }

    func testSerializationKeepsDefinitionsAndExcludesRawProviderIdentity() throws {
        let result = try project([sample("private-sample-id", 0, 405)])
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(ReviewedNightSleepProjection.self, from: data), result)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        for value in ["private-sample-id", "Private source", "private.bundle"] { XCTAssertFalse(json.contains(value)) }
        XCTAssertTrue(json.contains("reviewed_night_projection_v1"))
        XCTAssertTrue(json.contains("sleep_evidence_consensus_v1"))
    }

    func testFreshProviderDeletionDoesNotReuseEarlierTotals() throws {
        let first = try project([sample("removed", 0, 405)])
        let refreshed = try project([])
        XCTAssertEqual(first.coverage.asleepMinutes, 405)
        XCTAssertNil(refreshed.coverage.asleepMinutes)
        XCTAssertEqual(refreshed.bands.map(\.state), [.unmeasured])
    }

    func testRepeatedLocalHourUsesAbsoluteElapsedTime() throws {
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-11-01T01:30:00-04:00"))
        let end = try XCTUnwrap(formatter.date(from: "2026-11-01T01:30:00-05:00"))
        let now = end.addingTimeInterval(3600)
        let reviewed = ReviewedSleepWindow(sessionID: "dst-night", start: start, end: end,
            entryTimeZone: try XCTUnwrap(TimeZone(identifier: "America/New_York")), reviewedAt: now)
        let raw = SleepEvidenceSample(sampleID: "dst", start: start, end: end, rawCategory: 1,
            stage: .asleep, origin: .init(sourceName: "Synthetic", bundleIdentifier: nil))
        let evidence = try XCTUnwrap(SleepEvidenceResolution.calculate(start: start, end: end, samples: [raw]))
        let result = try XCTUnwrap(ReviewedNightSleepProjection.calculate(window: reviewed, evidence: evidence, generatedAt: now))
        XCTAssertEqual(result.coverage.asleepMinutes, 60)
        XCTAssertEqual(result.window.startUTCOffsetSeconds, -14400)
        XCTAssertEqual(result.window.endUTCOffsetSeconds, -18000)
    }
}
