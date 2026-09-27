import XCTest
@testable import DoseCore

final class CloudDashboardSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private func snapshot(sequence: UInt64 = 1) -> CloudDashboardSnapshot {
        CloudDashboardSnapshot(sourceID: "phone-a", sequence: sequence, capturedAt: now,
            sections: DashboardDataset.allCases.map {
                DashboardSnapshotSection(dataset: $0, rows: Data("[]".utf8), rowCount: 0)
            })
    }
    private func cache() -> CloudDashboardCache {
        CloudDashboardCache(accountScope: "account-a", sourceID: "phone-a")
    }
    func testValidRoundTripAndIdempotentRetry() throws {
        let original = snapshot()
        let decoded = try JSONDecoder().decode(CloudDashboardSnapshot.self,
            from: JSONEncoder().encode(original))
        var c = cache()
        XCTAssertTrue(try c.accept(decoded, accountScope: "account-a", now: now))
        XCTAssertFalse(try c.accept(decoded, accountScope: "account-a", now: now))
        XCTAssertEqual(c.snapshot, original)
    }
    func testCorruptOrMissingSectionCannotReplaceLastGoodSnapshot() throws {
        var c = cache(); try c.accept(snapshot(), accountScope: "account-a", now: now)
        var bad = snapshot(sequence: 2)
        bad.sections[0].rows = Data("[{}]".utf8)
        XCTAssertThrowsError(try c.accept(bad, accountScope: "account-a", now: now))
        bad = snapshot(sequence: 2); bad.sections.removeLast()
        XCTAssertThrowsError(try c.accept(bad, accountScope: "account-a", now: now))
        XCTAssertEqual(c.snapshot?.sequence, 1)
    }
    func testStaleAndConflictingRevisionRejected() throws {
        var c = cache(); try c.accept(snapshot(sequence: 2), accountScope: "account-a", now: now)
        XCTAssertThrowsError(try c.accept(snapshot(), accountScope: "account-a", now: now))
        var conflict = snapshot(sequence: 2); conflict.capturedAt = now.addingTimeInterval(-1)
        XCTAssertThrowsError(try c.accept(conflict, accountScope: "account-a", now: now))
        XCTAssertEqual(c.snapshot?.sequence, 2)
    }
    func testAccountAndSourceSwitchClearsDataAndRejectsOldResponse() throws {
        var c = cache(); try c.accept(snapshot(), accountScope: "account-a", now: now)
        c.select(accountScope: "account-b", sourceID: "phone-b")
        XCTAssertNil(c.snapshot)
        XCTAssertThrowsError(try c.accept(snapshot(), accountScope: "account-a", now: now))
        XCTAssertThrowsError(try c.accept(snapshot(), accountScope: "account-b", now: now))
        c.select(accountScope: nil, sourceID: nil)
        XCTAssertThrowsError(try c.accept(snapshot(), accountScope: "account-a", now: now))
    }
    func testUnavailableProviderIsExplicitButLocalFailureRejects() throws {
        var s = snapshot()
        let i = s.sections.firstIndex { $0.dataset == .appleHealth }!
        s.sections[i] = DashboardSnapshotSection(unavailable: .appleHealth, reason: "not_requested")
        var c = cache(); XCTAssertTrue(try c.accept(s, accountScope: "account-a", now: now))
        s.sequence = 2
        s.sections[0] = DashboardSnapshotSection(unavailable: .sessions, reason: "read_failed")
        XCTAssertThrowsError(try c.accept(s, accountScope: "account-a", now: now))
    }
    func testUnknownSchemaDuplicateCountAndMalformedPayloadRejected() {
        var cases: [CloudDashboardSnapshot] = []
        var s = snapshot(); s.schemaVersion = 99; cases.append(s)
        s = snapshot(); s.sections.append(s.sections[0]); cases.append(s)
        s = snapshot(); s.sections[0] = DashboardSnapshotSection(dataset: .sessions,
            rows: Data("[]".utf8), rowCount: 1); cases.append(s)
        s = snapshot(); s.sections[0] = DashboardSnapshotSection(dataset: .sessions,
            rows: Data("{}".utf8), rowCount: 0); cases.append(s)
        s = snapshot(); s.capturedAt = now.addingTimeInterval(1); cases.append(s)
        s = snapshot(); s.sequence = 0; cases.append(s)
        for invalid in cases {
            var c = cache()
            XCTAssertThrowsError(try c.accept(invalid, accountScope: "account-a", now: now))
            XCTAssertNil(c.snapshot)
        }
    }
    func testAbsentAmendmentLedgerIsNotReportedAsZero() throws {
        var s = snapshot()
        let i = s.sections.firstIndex { $0.dataset == .amendments }!
        s.sections[i] = DashboardSnapshotSection(notCollected: .amendments)
        var c = cache()
        try c.accept(s, accountScope: "account-a", now: now)
        XCTAssertNil(c.snapshot?.sections[i].rowCount)
        s.sequence = 2
        s.sections[0] = DashboardSnapshotSection(notCollected: .sessions)
        XCTAssertThrowsError(try c.accept(s, accountScope: "account-a", now: now))
        s = snapshot(sequence: 2)
        s.sections[i].notCollectedBySource = true
        XCTAssertThrowsError(try c.accept(s, accountScope: "account-a", now: now))
    }
    func testCompleteEmptyGenerationReplacesRowsWithoutPhoneMutation() throws {
        var s = snapshot()
        s.sections[0] = DashboardSnapshotSection(dataset: .sessions,
            rows: Data("[{\"id\":\"synthetic\"}]".utf8), rowCount: 1)
        var c = cache(); try c.accept(s, accountScope: "account-a", now: now)
        try c.accept(snapshot(sequence: 2), accountScope: "account-a", now: now)
        XCTAssertEqual(c.snapshot?.sections[0].rowCount, 0)
    }
}
