import XCTest
@testable import DoseCore

final class DashboardSharedSleepEpisodeTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_790_740_800)
    func episode() -> DashboardSharedSleepEpisode {
        .init(episodeID: "apple-health:sample", treatmentDate: "2026-09-30", source: "Apple Watch",
              sessionID: nil, associationRevision: nil, intervals: [.init(start: start, end: start.addingTimeInterval(3600), asleep: true)],
              bedTime: nil, sleepOnset: start, finalWake: start.addingTimeInterval(3600),
              observationEnd: start.addingTimeInterval(3600), finalWakeBasis: "last_asleep_end",
              derivationVersion: "v1", totalSleepMinutes: 60,
              queryStart: start.addingTimeInterval(-3600), queryEnd: start.addingTimeInterval(7200),
              completedAt: start.addingTimeInterval(7300), timeZoneID: "America/New_York")
    }
    func testRoundTripPreservesReceiptAndContainsNoFingerprint() throws {
        let value = episode(); let bytes = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(DashboardSharedSleepEpisode.self, from: bytes), value)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).lowercased().contains("fingerprint"))
        XCTAssertNoThrow(try value.validate(capturedAt: start.addingTimeInterval(8000)))
    }
    func testUnpairedBindingRejected() {
        var value = episode(); value.sessionID = "session-one"
        XCTAssertThrowsError(try value.validate(capturedAt: start.addingTimeInterval(8000)))
    }
    func testFutureReceiptRejected() {
        XCTAssertThrowsError(try episode().validate(capturedAt: start))
    }
    func testTotalsCannotDisagreeWithIntervals() {
        var value = episode(); value.totalSleepMinutes = 120
        XCTAssertThrowsError(try value.validate(capturedAt: start.addingTimeInterval(8000)))
    }
    func testInvalidDecodedBoundsRejected() throws {
        var value = episode(); value.queryStart = value.queryEnd
        let decoded = try JSONDecoder().decode(DashboardSharedSleepEpisode.self, from: JSONEncoder().encode(value))
        XCTAssertThrowsError(try decoded.validate(capturedAt: start.addingTimeInterval(8000)))
    }
    func testAwakeIsZeroAndGapIsPartial() throws {
        var value = episode(); value.intervals = [.init(start: start, end: start.addingTimeInterval(600), asleep: false)]
        value.totalSleepMinutes = 0; value.sleepOnset = nil; value.finalWake = nil
        XCTAssertNoThrow(try value.validate(capturedAt: start.addingTimeInterval(8000)))
        XCTAssertEqual(value.coverage?.status, .partial)
        XCTAssertEqual(value.coverage?.asleepMinutes, 0)
    }
    func testSharedReviewIsBoundToExactProviderContext() throws {
        var value = episode()
        let fingerprint = try XCTUnwrap(DashboardDoseReview.observationFingerprint(observationID: value.episodeID,
            sessionDate: value.treatmentDate, events: [], providerFingerprint: "private-current"))
        let review = DashboardDoseReview(observationID: value.episodeID, sourceFingerprint: fingerprint,
            confirmedCount: 1, historicalPlanCount: 1, secondNotTaken: nil, recordedAt: value.completedAt, reason: "Reviewed")
        value.review = DashboardSharedProviderDoseReview.project(review, episodeID: value.episodeID,
            treatmentDate: value.treatmentDate, providerFingerprint: "private-current", capturedAt: value.completedAt)
        XCTAssertNotNil(value.review)
        XCTAssertNil(DashboardSharedProviderDoseReview.project(review, episodeID: value.episodeID,
            treatmentDate: value.treatmentDate, providerFingerprint: "corrected", capturedAt: value.completedAt))
        XCTAssertNoThrow(try value.validate(capturedAt: value.completedAt))
        value.sessionID = "local"; value.associationRevision = UUID()
        XCTAssertThrowsError(try value.validate(capturedAt: value.completedAt))
    }
    func testSidecarRequiresOriginalOptedInQueryReceipt() throws {
        let value = episode()
        let snapshot = CloudDashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: value.completedAt,
            sections: DashboardDataset.allCases.map { .init(dataset: $0, rows: Data("[]".utf8), rowCount: 0) })
        XCTAssertThrowsError(try DashboardSharedSleepEpisode.validate([value], in: snapshot))
    }

    func testPacketSupportAndExactIdentityBinding() throws {
        var value = episode()
        let packet = DashboardSleepEvidence(queryStart: value.queryStart, queryEnd: value.queryEnd,
            completedAt: value.completedAt, timeZoneID: value.timeZoneID,
            samples: [.init(sampleID: "sample", start: start, end: start.addingTimeInterval(3600),
                rawCategory: 1, stage: .asleep, origin: .init(sourceName: "Apple Watch", bundleIdentifier: nil))])
        var snapshot = CloudDashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: value.completedAt,
            sections: DashboardDataset.allCases.map { .init(dataset: $0, rows: Data("[]".utf8), rowCount: 0) })
        snapshot.sections[snapshot.sections.firstIndex { $0.dataset == .appleHealth }!] = try packet.section()
        XCTAssertNoThrow(try DashboardSharedSleepEpisode.validate([value], in: snapshot))
        value.sessionID = "a"; value.associationRevision = UUID()
        XCTAssertThrowsError(try DashboardSharedSleepEpisode.validate([value], in: snapshot))
        let rows = Data(#"[{"sourceTable":"sleep_sessions","columns":{"session_id":{"type":"text","text":"a"},"session_date":{"type":"text","text":"2026-09-30"}}}]"#.utf8)
        snapshot.sections[snapshot.sections.firstIndex { $0.dataset == .sessions }!] = .init(dataset: .sessions, rows: rows, rowCount: 1)
        XCTAssertNoThrow(try DashboardSharedSleepEpisode.validate([value], in: snapshot))
        value.treatmentDate = "2026-09-29"
        XCTAssertThrowsError(try DashboardSharedSleepEpisode.validate([value], in: snapshot))
    }
    func testRepeatedEpisodesAndUnsupportedIntervalsRejected() throws {
        let value = episode()
        let packet = DashboardSleepEvidence(queryStart: value.queryStart, queryEnd: value.queryEnd,
            completedAt: value.completedAt, timeZoneID: value.timeZoneID, samples: [])
        var snapshot = CloudDashboardSnapshot(sourceID: "test", sequence: 1, capturedAt: value.completedAt,
            sections: DashboardDataset.allCases.map { .init(dataset: $0, rows: Data("[]".utf8), rowCount: 0) })
        snapshot.sections[snapshot.sections.firstIndex { $0.dataset == .appleHealth }!] = try packet.section()
        XCTAssertThrowsError(try DashboardSharedSleepEpisode.validate([value], in: snapshot))
        XCTAssertThrowsError(try DashboardSharedSleepEpisode.validate([value, value], in: snapshot))
    }

}
