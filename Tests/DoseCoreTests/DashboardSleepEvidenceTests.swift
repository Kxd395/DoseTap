import XCTest
@testable import DoseCore

final class DashboardSleepEvidenceTests: XCTestCase {
    private let end = Date(timeIntervalSince1970: 1_800_000_000)
    private func sample(id: String = "sample-a", raw: Int = 3,
                        stage: SleepEvidenceSample.Stage = .core) -> SleepEvidenceSample {
        var origin = SleepEvidenceSample.Origin(sourceName: "Synthetic Watch", bundleIdentifier: "example.test")
        origin.receivedAt = end
        return .init(sampleID: id, start: end.addingTimeInterval(-3600), end: end,
                     rawCategory: raw, stage: stage, origin: origin)
    }
    private func packet(_ samples: [SleepEvidenceSample] = []) -> DashboardSleepEvidence {
        .init(queryStart: end.addingTimeInterval(-86400), queryEnd: end,
              completedAt: end, timeZoneID: "America/New_York", samples: samples)
    }
    private func snapshot(_ evidence: DashboardSleepEvidence) throws -> CloudDashboardSnapshot {
        var s = CloudDashboardSnapshot(sourceID: "phone", sequence: 1, capturedAt: end,
            sections: DashboardDataset.allCases.map { .init(dataset: $0, rows: Data("[]".utf8), rowCount: 0) })
        s.sections[s.sections.firstIndex { $0.dataset == .appleHealth }!] = try evidence.section()
        return s
    }
    func testRoundTripRetainsOriginalBoundariesStageAndSource() throws {
        var p = packet([sample()]); p.queryStart = end.addingTimeInterval(-1800)
        let s = try snapshot(p)
        let decoded = try JSONDecoder().decode(CloudDashboardSnapshot.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(try DashboardSleepEvidence.read(from: decoded), p)
        XCTAssertEqual(p.samples[0].start, end.addingTimeInterval(-3600))
        XCTAssertEqual(p.samples[0].origin.bundleIdentifier, "example.test")
    }
    func testEmptySuccessDiffersFromLegacyUnavailable() throws {
        XCTAssertEqual(try DashboardSleepEvidence.read(from: snapshot(packet()))?.samples.count, 0)
        var s = try snapshot(packet())
        let i = s.sections.firstIndex { $0.dataset == .appleHealth }!
        s.sections[i] = .init(unavailable: .appleHealth, reason: "not_requested")
        XCTAssertNil(try DashboardSleepEvidence.read(from: s))
        s.sections[i] = .init(dataset: .appleHealth, rows: Data("[]".utf8), rowCount: 0)
        XCTAssertNil(try DashboardSleepEvidence.read(from: s))
    }
    func testInvalidMetadataAndDuplicateSamplesRejected() throws {
        var cases: [DashboardSleepEvidence] = []
        var p = packet(); p.version = 9; cases.append(p)
        p = packet(); p.queryStart = end; cases.append(p)
        p = packet(); p.queryStart = end.addingTimeInterval(-30 * 86400 - 1); cases.append(p)
        p = packet(); p.completedAt = end.addingTimeInterval(-1); cases.append(p)
        p = packet(); p.timeZoneID = "invalid"; cases.append(p)
        cases += [packet([sample(), sample()]), packet([sample(id: "")]), packet([sample(raw: 2, stage: .core)])]
        for invalid in cases { XCTAssertThrowsError(try invalid.validate(capturedAt: end)) }
    }
    func testUnknownStageRetainedAndUnboundedSamplesRejected() throws {
        try packet([sample(raw: 999, stage: .unknown)]).validate(capturedAt: end)
        let future = SleepEvidenceSample(sampleID: "future", start: end, end: end.addingTimeInterval(1),
            rawCategory: 2, stage: .awake, origin: .init(sourceName: "test", bundleIdentifier: nil))
        XCTAssertThrowsError(try packet([future]).validate(capturedAt: end))
        XCTAssertThrowsError(try packet(Array(repeating: sample(), count: 10_001)).validate(capturedAt: end))
    }
    func testMalformedProviderCannotReplaceCacheEvenWithValidHash() throws {
        let good = try snapshot(packet([sample()]))
        var cache = CloudDashboardCache(accountScope: "nearby", sourceID: "phone")
        try cache.accept(good, accountScope: "nearby", now: end)
        var bad = good; bad.sequence = 2
        let i = bad.sections.firstIndex { $0.dataset == .appleHealth }!
        bad.sections[i] = .init(dataset: .appleHealth, rows: Data("[{\"version\":99}]".utf8), rowCount: 1)
        XCTAssertThrowsError(try cache.accept(bad, accountScope: "nearby", now: end))
        XCTAssertEqual(cache.snapshot, good)
        var p = packet(); p.completedAt = end.addingTimeInterval(1)
        bad.sections[i] = .init(dataset: .appleHealth, rows: try JSONEncoder().encode([p]), rowCount: 1)
        XCTAssertThrowsError(try cache.accept(bad, accountScope: "nearby", now: end))
    }
}
