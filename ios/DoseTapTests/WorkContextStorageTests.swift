import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class WorkContextStorageTests: XCTestCase {
    func document() -> WorkContextDocument {
        var value = WorkContextDocument()
        value.rosters = [.init(effectiveFrom: "2026-09-01", effectiveTo: "2026-12-31", timeZoneIdentifier: "UTC", weekdays: [3, 4, 5], recordedAt: Date(timeIntervalSince1970: 1_700_000_000))]
        return value
    }
    func testRoundTripHistoryAndNoMedicationMutation() throws {
        let storage = EventStorage.inMemory()
        let original = document()
        try storage.saveWorkContext(original, expectedRevision: nil)
        var revised = original; revised.revision = UUID()
        revised.occurrences.append(.init(workDate: "2026-09-22", timeZoneIdentifier: "UTC", attendance: .worked, recordedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        try storage.saveWorkContext(revised, expectedRevision: original.revision)
        XCTAssertEqual(try storage.loadWorkContext(), revised)
        XCTAssertEqual(storage.countDoseEvents(), 0)
        XCTAssertThrowsError(try storage.saveWorkContext(original, expectedRevision: original.revision))
        XCTAssertEqual(try storage.loadWorkContext(), revised)
        var destructive = revised; destructive.rosters = []; destructive.revision = UUID()
        XCTAssertThrowsError(try storage.saveWorkContext(destructive, expectedRevision: revised.revision))
        XCTAssertEqual(try storage.loadWorkContext(), revised)
    }
    func testFailedSaveAndUnreadablePayloadFailClosed() throws {
        let storage = EventStorage.inMemory(), value = document()
        try storage.saveWorkContext(value, expectedRevision: nil)
        sqlite3_exec(storage.db, "PRAGMA query_only = ON", nil, nil, nil)
        var next = value; next.revision = UUID()
        XCTAssertThrowsError(try storage.saveWorkContext(next, expectedRevision: value.revision))
        XCTAssertEqual(try storage.loadWorkContext(), value)
        sqlite3_exec(storage.db, "PRAGMA query_only = OFF", nil, nil, nil)
        sqlite3_exec(storage.db, "UPDATE work_block_context SET payload = 'unreadable'", nil, nil, nil)
        XCTAssertThrowsError(try storage.loadWorkContext())
        XCTAssertThrowsError(try storage.saveWorkContext(value, expectedRevision: nil))
    }
    func testDurableReopenAndClearAll() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("work.sqlite").path, value = document()
        do { try EventStorage(dbPath: path).saveWorkContext(value, expectedRevision: nil) }
        let reopened = EventStorage(dbPath: path)
        XCTAssertEqual(try reopened.loadWorkContext(), value)
        reopened.clearAllData()
        XCTAssertNil(try reopened.loadWorkContext())
    }
    func testSnapshotRetainsIndependentWorkContextSource() throws {
        let storage = EventStorage.inMemory(), value = document()
        try storage.saveWorkContext(value, expectedRevision: nil)
        let snapshot = try storage.dashboardSnapshot(sourceID: "fixture", sequence: 1, capturedAt: Date())
        let section = try XCTUnwrap(snapshot.sections.first { $0.dataset == .workSchedule })
        XCTAssertEqual(section.rowCount, 1)
    }
    func testPayloadRejectsBlobEmbeddedNULAndInvalidUTF8() throws {
        let storage = EventStorage.inMemory(), value = document()
        try storage.saveWorkContext(value, expectedRevision: nil)
        let valid = try JSONEncoder().encode(value)
        let malformedUTF8 = valid.dropLast() + Data(",\"extra\":\"".utf8) + Data([0xff]) + Data("\"}".utf8)
        for (payload, blob) in [(valid, true), (valid + Data([0]) + Data("tail".utf8), false), (Data(malformedUTF8), false)] {
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(storage.db, "UPDATE work_block_context SET payload = ?", -1, &statement, nil), SQLITE_OK)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let bound = payload.withUnsafeBytes { bytes in
                blob ? sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), transient)
                    : sqlite3_bind_text(statement, 1, bytes.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(bytes.count), transient)
            }
            XCTAssertEqual(bound, SQLITE_OK); XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE); sqlite3_finalize(statement)
            XCTAssertThrowsError(try storage.loadWorkContext())
        }
    }

    func testProspectiveCaptureJoinsTransactionAndPreservesFirstSnapshot() throws {
        let storage = EventStorage.inMemory(), value = document(), now = Date()
        try storage.saveWorkContext(value, expectedRevision: nil)
        XCTAssertThrowsError(try storage.captureWorkPlanInCurrentTransaction(preSleepLogID: "pre", sessionID: nil, capturedAt: now))
        XCTAssertEqual(sqlite3_exec(storage.db, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        let rolledBack = try XCTUnwrap(storage.captureWorkPlanInCurrentTransaction(preSleepLogID: "pre", sessionID: nil, capturedAt: now))
        XCTAssertEqual(try storage.loadWorkContext()?.planSnapshots?.first?.id, rolledBack.id)
        XCTAssertEqual(sqlite3_exec(storage.db, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try storage.loadWorkContext(), value)
        XCTAssertEqual(sqlite3_exec(storage.db, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        let saved = try XCTUnwrap(storage.captureWorkPlanInCurrentTransaction(preSleepLogID: "pre", sessionID: nil, capturedAt: now))
        XCTAssertEqual(try storage.captureWorkPlanInCurrentTransaction(preSleepLogID: "pre", sessionID: nil, capturedAt: now.addingTimeInterval(1))?.id, saved.id)
        XCTAssertEqual(sqlite3_exec(storage.db, "COMMIT", nil, nil, nil), SQLITE_OK)
        let persisted = try XCTUnwrap(storage.loadWorkContext())
        var destructive = persisted; destructive.planSnapshots = []; destructive.revision = UUID()
        XCTAssertThrowsError(try storage.saveWorkContext(destructive, expectedRevision: persisted.revision))
        var shifted = persisted; shifted.revision = UUID(); shifted.shiftEvents = [.init(timeZoneIdentifier: "UTC", recordedAt: now)]
        try storage.saveWorkContext(shifted, expectedRevision: persisted.revision)
        destructive = shifted; destructive.shiftEvents = []; destructive.revision = UUID()
        XCTAssertThrowsError(try storage.saveWorkContext(destructive, expectedRevision: shifted.revision))
    }

}
