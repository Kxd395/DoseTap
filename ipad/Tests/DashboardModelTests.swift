import XCTest
import DoseCore
@testable import DoseTapDashboard

@MainActor
final class DashboardModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture(source: String = "phone-a", sequence: UInt64 = 1) -> CloudDashboardSnapshot {
        CloudDashboardSnapshot(sourceID: source, sequence: sequence, capturedAt: now,
            sections: DashboardDataset.allCases.map {
                DashboardSnapshotSection(dataset: $0, rows: Data("[]".utf8), rowCount: 0)
            })
    }
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("report.json")
    }
    private func accept(_ snapshot: CloudDashboardSnapshot, into model: DashboardModel) throws {
        model.receive(try JSONEncoder().encode(snapshot), context: model.connection.contextID)
    }
    func testPersistenceReloadPinAndExplicitForget() throws {
        let url = try temporaryURL(), first = fixture()
        let model = DashboardModel(cacheURL: url, now: { self.now })
        try accept(first, into: model)
        XCTAssertEqual(model.snapshot, first); XCTAssertNil(model.error)
        XCTAssertEqual(try JSONDecoder().decode(CloudDashboardSnapshot.self, from: Data(contentsOf: url)), first)
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let reloaded = DashboardModel(cacheURL: url, now: { self.now })
        XCTAssertEqual(reloaded.snapshot, first); XCTAssertEqual(reloaded.report?.sourceID, first.sourceID)
        try accept(fixture(source: "phone-b", sequence: 2), into: reloaded)
        XCTAssertEqual(reloaded.snapshot, first); XCTAssertNotNil(reloaded.error)
        let oldContext = reloaded.connection.contextID
        reloaded.forgetReport()
        XCTAssertNotEqual(reloaded.connection.contextID, oldContext)
        XCTAssertNil(reloaded.snapshot); XCTAssertNil(reloaded.report); XCTAssertNil(reloaded.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try accept(fixture(source: "phone-b"), into: reloaded)
        XCTAssertEqual(reloaded.snapshot?.sourceID, "phone-b"); XCTAssertNil(reloaded.error)
    }
    func testInvalidStaleConflictingAndWrongSourcePreserveLastGoodBytes() throws {
        let url = try temporaryURL(), first = fixture(sequence: 3)
        let model = DashboardModel(cacheURL: url, now: { self.now })
        try accept(first, into: model)
        let saved = try Data(contentsOf: url)
        var corrupt = fixture(sequence: 4); corrupt.sections[0].rowCount = 1
        var conflict = first; conflict.capturedAt = now.addingTimeInterval(-1)
        var badProjection = fixture(sequence: 4)
        let index = try XCTUnwrap(badProjection.sections.firstIndex { $0.dataset == .medicationEntries })
        badProjection.sections[index] = DashboardSnapshotSection(dataset: .medicationEntries,
            rows: Data("[{\"sourceTable\":\"dose_events\",\"columns\":{}}]".utf8), rowCount: 1)
        for candidate in [corrupt, fixture(sequence: 2), conflict, fixture(source: "phone-b", sequence: 4), badProjection] {
            try accept(candidate, into: model)
            XCTAssertEqual(model.snapshot, first); XCTAssertNotNil(model.error)
            XCTAssertEqual(model.report?.sourceID, first.sourceID)
            XCTAssertEqual(try Data(contentsOf: url), saved)
        }
        model.receive(Data("invalid".utf8), context: model.connection.contextID)
        XCTAssertEqual(model.snapshot, first); XCTAssertEqual(try Data(contentsOf: url), saved)
        try accept(fixture(sequence: 4), into: model)
        XCTAssertEqual(model.snapshot?.sequence, 4); XCTAssertNil(model.error)
    }
    func testOldConnectionCannotReplaceReportAfterStop() throws {
        let url = try temporaryURL(), model = DashboardModel(cacheURL: url, now: { self.now })
        try accept(fixture(), into: model)
        let oldContext = model.connection.contextID
        model.connection.stop()
        model.receive(try JSONEncoder().encode(fixture(sequence: 2)), context: oldContext)
        XCTAssertEqual(model.snapshot?.sequence, 1); XCTAssertNil(model.error)
        XCTAssertEqual(DashboardModel(cacheURL: url, now: { self.now }).snapshot?.sequence, 1)
    }
    func testCorruptCacheBlocksReplacementUntilExplicitForget() throws {
        let url = try temporaryURL(), invalid = Data("corrupt".utf8)
        try invalid.write(to: url)
        let model = DashboardModel(cacheURL: url, now: { self.now })
        XCTAssertNil(model.report); XCTAssertNotNil(model.error)
        try accept(fixture(), into: model)
        XCTAssertNil(model.snapshot); XCTAssertEqual(try Data(contentsOf: url), invalid)
        model.forgetReport(); XCTAssertNil(model.error)
        try accept(fixture(), into: model)
        XCTAssertEqual(model.snapshot?.sourceID, "phone-a"); XCTAssertNil(model.error)
    }
    func testPersistenceFailureDoesNotPublishUncachedReport() throws {
        let blockedParent = try temporaryURL()
        let model = DashboardModel(cacheURL: blockedParent.appendingPathComponent("report.json"), now: { self.now })
        try Data("file".utf8).write(to: blockedParent)
        try accept(fixture(), into: model)
        XCTAssertNil(model.snapshot); XCTAssertNil(model.report); XCTAssertNotNil(model.error)
        XCTAssertEqual(try Data(contentsOf: blockedParent), Data("file".utf8))
    }
    func testOversizedIncomingAndSavedReportAreRejected() throws {
        let url = try temporaryURL(), model = DashboardModel(cacheURL: url, now: { self.now })
        try accept(fixture(), into: model)
        let oversized = Data(repeating: 32, count: 32 * 1024 * 1024 + 1)
        model.receive(oversized, context: model.connection.contextID)
        XCTAssertEqual(model.snapshot?.sequence, 1); XCTAssertNotNil(model.error)
        try oversized.write(to: url)
        let reloaded = DashboardModel(cacheURL: url, now: { self.now })
        XCTAssertNil(reloaded.snapshot); XCTAssertNotNil(reloaded.error)
        try accept(fixture(source: "phone-b"), into: reloaded)
        XCTAssertNil(reloaded.snapshot)
    }
    func testVisibleConnectionErrorAndUnavailableRequest() throws {
        let model = DashboardModel(cacheURL: try temporaryURL(), now: { self.now })
        model.presentConnectionError("Pairing code could not be accepted.")
        XCTAssertEqual(model.error, "Pairing code could not be accepted.")
        model.request(); XCTAssertNotNil(model.error); XCTAssertNil(model.snapshot)
    }
    func testUnassignedQuestionnaireRemainsInSavedReportAcrossRestart() throws {
        let url = try temporaryURL(), model = DashboardModel(cacheURL: url, now: { self.now })
        var snapshot = fixture()
        let index = try XCTUnwrap(snapshot.sections.firstIndex { $0.dataset == .morning })
        let rows = Data(#"[{"sourceTable":"morning_checkins","columns":{"id":{"type":"text","text":"orphan"},"session_id":{"type":"null"},"session_date":{"type":"null"},"sleep_quality":{"type":"real","real":3}}}]"#.utf8)
        snapshot.sections[index] = .init(dataset: .morning, rows: rows, rowCount: 1)
        try accept(snapshot, into: model)
        XCTAssertNil(model.error); XCTAssertEqual(model.questionnaires?.unassignedSourceRowCount, 1)
        XCTAssertEqual(model.questionnaires?.days.count, 0)
        let reopened = DashboardModel(cacheURL: url, now: { self.now })
        XCTAssertNil(reopened.error); XCTAssertEqual(reopened.snapshot, snapshot)
        XCTAssertEqual(reopened.questionnaires?.unassignedSourceRowCount, 1)
        reopened.forgetReport(); XCTAssertNil(reopened.questionnaires)
    }
}
