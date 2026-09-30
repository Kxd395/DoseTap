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
}
