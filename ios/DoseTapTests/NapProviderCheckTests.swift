import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class NapProviderCheckTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func episode() -> NapEpisode {
        .init(id: "synthetic", day: NapEpisode.day(now, "UTC"), timeZoneID: "UTC",
              start: now.addingTimeInterval(-3600), end: now, recordedAt: now)
    }
    func evidence(_ value: NapEpisode, stage: SleepEvidenceSample.Stage = .asleep) throws -> SleepEvidenceResolution {
        let start = try XCTUnwrap(value.start), end = try XCTUnwrap(value.end)
        return try XCTUnwrap(.calculate(start: start, end: end, samples: [
            .init(sampleID: "synthetic-sample", start: start, end: start.addingTimeInterval(600), rawCategory: 1,
                  stage: stage, origin: .init(sourceName: "Synthetic", bundleIdentifier: "synthetic.tests"))]))
    }
    func testDisabledAccessDoesNotReadProviderOrPublishValues() async throws {
        let model = NapProviderCheck(), nap = episode(); var queried = false
        await model.check(episode: nap, clock: { self.now }, current: { nap }, allowed: { false }, query: { _, _ in queried = true; return try self.evidence(nap) })
        XCTAssertFalse(queried); XCTAssertNil(model.evidence); XCTAssertFalse(model.busy)
    }
    func testRevokedAccessAndChangedEpisodeDiscardCompletedQuery() async throws {
        let model = NapProviderCheck(), nap = episode(); var allowed = true
        await model.check(episode: nap, clock: { self.now }, current: { nap }, allowed: { allowed }, query: { _, _ in
            allowed = false; return try self.evidence(nap)
        })
        XCTAssertNil(model.evidence); XCTAssertNil(model.checkedAt)
        var current = nap
        await model.check(episode: nap, clock: { self.now }, current: { current }, allowed: { true }, query: { _, _ in
            current.estimatedSleepMinutes = 4; return try self.evidence(nap)
        })
        XCTAssertNil(model.evidence); XCTAssertTrue(model.message.contains("changed"))
    }
    func testPartialCoverageStaysPartialAndInvalidationClearsIt() async throws {
        let model = NapProviderCheck(), nap = episode()
        await model.check(episode: nap, clock: { self.now }, current: { nap }, allowed: { true }, query: { _, _ in try self.evidence(nap) })
        XCTAssertEqual(model.evidence?.status, .partial)
        XCTAssertEqual(model.evidence?.coverage.asleepMinutes, 10)
        XCTAssertEqual(model.evidence?.coverage.unmeasuredMinutes, 50)
        XCTAssertEqual(model.checkedAt, now)
        model.invalidate(); XCTAssertNil(model.evidence); XCTAssertNil(model.checkedAt)
    }
    func testFailureWrongBoundsAndInvalidationDuringQueryNeverPublish() async throws {
        let model = NapProviderCheck(), nap = episode()
        await model.check(episode: nap, clock: { self.now }, current: { nap }, allowed: { true }, query: { _, _ in throw NapDiaryStorageError.unreadable })
        XCTAssertNil(model.evidence); XCTAssertFalse(model.busy)
        var other = nap; other.start = nap.start!.addingTimeInterval(1)
        await model.check(episode: nap, clock: { self.now }, current: { nap }, allowed: { true }, query: { _, _ in try self.evidence(other) })
        XCTAssertNil(model.evidence)
        await model.check(episode: nap, clock: { self.now }, current: { nap }, allowed: { true }, query: { _, _ in
            model.invalidate(); return try self.evidence(nap)
        })
        XCTAssertNil(model.evidence); XCTAssertFalse(model.busy)
    }
    func testConflictingProviderEvidenceIsUnknownRatherThanAwake() async throws {
        let model = NapProviderCheck(), nap = episode()
        let samples = try evidence(nap).samples + evidence(nap, stage: .awake).samples
        let result = try XCTUnwrap(SleepEvidenceResolution.calculate(start: nap.start!, end: nap.end!, samples: samples))
        await model.check(episode: nap, clock: { self.now }, current: { nap }, allowed: { true }, query: { _, _ in result })
        XCTAssertEqual(model.evidence?.status, .conflict)
        XCTAssertEqual(model.evidence?.conflictMinutes, 10)
        XCTAssertEqual(model.evidence?.coverage.unmeasuredMinutes, 60)
        XCTAssertNil(model.evidence?.coverage.awakeMinutes)
    }

}
