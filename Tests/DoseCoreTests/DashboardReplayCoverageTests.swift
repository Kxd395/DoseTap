import XCTest
@testable import DoseCore

final class DashboardReplayCoverageTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    func snapshot(asOf: Date? = nil, zone: String = "UTC", projection: ReviewedNightSleepProjection? = nil,
                  end: Double = 900) -> DashboardReplaySnapshot {
        .init(sessionID: "s", treatmentDate: "2026-09-21", asOf: asOf ?? base.addingTimeInterval(2000),
            timeZoneID: zone, sourcePolicy: "Apple Health reviewed", filterDescription: "test",
            markers: [.init(id: "d2", sessionID: "s", kind: .dose2, occurredAt: base, source: "actual"),
                      .init(id: "end", sessionID: "s", kind: .reportedWake, occurredAt: base.addingTimeInterval(end), source: "diary")],
            reviewedProjection: projection)
    }
    func projection() throws -> ReviewedNightSleepProjection {
        let window = ReviewedSleepWindow(sessionID: "s", start: base.addingTimeInterval(100),
            end: base.addingTimeInterval(800), entryTimeZone: TimeZone(secondsFromGMT: 0)!, reviewedAt: base.addingTimeInterval(1000))
        let origin = SleepEvidenceSample.Origin(sourceName: "test", bundleIdentifier: nil)
        let evidence = try XCTUnwrap(SleepEvidenceResolution.calculate(start: window.start, end: window.end, samples: [
            .init(sampleID: "a", start: base.addingTimeInterval(100), end: base.addingTimeInterval(500), rawCategory: 0, stage: .asleep, origin: origin),
            .init(sampleID: "b", start: base.addingTimeInterval(400), end: base.addingTimeInterval(600), rawCategory: 0, stage: .awake, origin: origin),
            .init(sampleID: "c", start: base.addingTimeInterval(700), end: base.addingTimeInterval(800), rawCategory: 0, stage: .asleep, origin: origin)]))
        return try XCTUnwrap(.calculate(window: window, evidence: evidence, generatedAt: base.addingTimeInterval(1000)))
    }
    func testClippedNamedSpanPartitionsAndConflictIsSubsetOfUnmeasured() throws {
        let value = DashboardPostDoseCoverage.calculate(snapshot: snapshot(projection: try projection()), preset: .dose2ToReportedWake)
        XCTAssertEqual(value.state, .partial)
        XCTAssertEqual(value.elapsedMinutes, 15)
        XCTAssertEqual(try XCTUnwrap(value.asleepMinutes), 400 / 60, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(value.awakeMinutes), 100 / 60, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(value.unmeasuredMinutes), 400 / 60, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(value.conflictMinutes), 100 / 60, accuracy: 0.0001)
        XCTAssertEqual(value.bands.first?.start, base)
        XCTAssertEqual(value.bands.last?.end, base.addingTimeInterval(900))
        XCTAssertEqual(value.startID, "d2"); XCTAssertEqual(value.endID, "end")
    }
    func testUncheckedOrNonpositiveSpansDoNotInventZeroCoverage() throws {
        let unchecked = DashboardPostDoseCoverage.calculate(snapshot: snapshot(), preset: .dose2ToReportedWake)
        XCTAssertEqual(unchecked.state, .unavailable); XCTAssertNil(unchecked.asleepMinutes)
        let reversed = DashboardPostDoseCoverage.calculate(snapshot: snapshot(projection: try projection(), end: -10), preset: .dose2ToReportedWake)
        XCTAssertEqual(reversed.state, .needsReview); XCTAssertNil(reversed.asleepMinutes)
    }
    func testMalformedSnapshotCannotFeedChartsIntervalsOrCoverage() {
        for snap in [snapshot(asOf: Date(timeIntervalSince1970: .infinity)), snapshot(asOf: Date(timeIntervalSince1970: .nan)), snapshot(zone: "Invalid/Zone")] {
            XCTAssertEqual(snap.interval(.dose2ToReportedWake).state, .needsReview)
            XCTAssertNil(snap.position(of: base, alignment: .clock))
            XCTAssertNil(snap.position(of: base, alignment: .dose2))
        }
        let huge = Double.greatestFiniteMagnitude
        let snap = DashboardReplaySnapshot(sessionID: "s", treatmentDate: "2026-09-21",
            asOf: Date(timeIntervalSince1970: huge), timeZoneID: "UTC", sourcePolicy: "test", filterDescription: "test",
            markers: [.init(id: "d2", sessionID: "s", kind: .dose2, occurredAt: Date(timeIntervalSince1970: -huge), source: "test")])
        XCTAssertNil(snap.position(of: Date(timeIntervalSince1970: huge), alignment: .dose2))
    }
}
