import XCTest
import DoseCore
import SQLite3
@testable import DoseTap

@MainActor
final class SupplyStorageTests: XCTestCase {
    func testReopenDatabasePreservesSupplyAndCorrectionHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("supply.sqlite").path
        var backup = SupplyBackup(reminder: SupplyReminderDocument(current:
            SupplyReminderEntry(year: 2035, month: 10, day: 4, hour: 9, minute: 0)))
        var corrected = backup.reminder!.current
        corrected.day = 5
        backup.reminder!.replace(with: corrected, at: Date())
        do { try EventStorage(dbPath: path).saveSupply(backup) }
        XCTAssertEqual(try EventStorage(dbPath: path).loadSupply(), backup)
    }
    func testRoundTripRestoreAndResetPreserveIndependentRecords() throws {
        let storage = EventStorage.inMemory()
        var backup = SupplyBackup(reminder: SupplyReminderDocument(current:
            SupplyReminderEntry(year: 2026, month: 10, day: 4, hour: 9, minute: 0)))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        backup.bottleStarts = [SupplyBottleStart(openedAt: now, recordedAt: now)]
        try storage.saveSupply(backup)
        try storage.saveSupply(backup)
        XCTAssertEqual(try storage.loadSupply(), backup)
        backup.reminder = nil
        try storage.saveSupply(backup)
        XCTAssertEqual(try storage.loadSupply().bottleStarts.count, 1)
        storage.clearAllData()
        XCTAssertEqual(try storage.loadSupply(), SupplyBackup())
    }

    func testInvalidRestoreAndWriteFailurePreserveSavedSource() throws {
        let storage = EventStorage.inMemory()
        let original = SupplyBackup()
        try storage.saveSupply(original)
        var invalid = original
        invalid.version = 99
        XCTAssertThrowsError(try storage.saveSupply(invalid))
        XCTAssertEqual(try storage.loadSupply(), original)
        sqlite3_exec(storage.db, "PRAGMA query_only = ON", nil, nil, nil)
        XCTAssertThrowsError(try storage.saveSupply(original))
        XCTAssertEqual(try storage.loadSupply(), original)
    }
}
