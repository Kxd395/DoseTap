import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class ExcelExportTests: XCTestCase {
    func testWorkbookUsesFinalizedBundleWithoutChangingSourceOrRecords() throws {
        let storage = EventStorage.inMemory()
        let repo = SessionRepository(storage: storage)
        XCTAssertEqual(sqlite3_exec(storage.db, """
        INSERT INTO dose_events(id,session_id,event_type,timestamp,session_date)
        VALUES('excel-dose','excel-session','dose1','2030-04-05T23:00:00Z','2030-04-05');
        INSERT INTO sleep_events(id,session_id,event_type,timestamp,session_date,notes)
        VALUES('excel-event','excel-session','future_quick_log','2030-04-06T01:00:00Z','2030-04-05','=1+1');
        """, nil, nil, nil), SQLITE_OK)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("excel-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try StudioBundleExporter().writeStudioExportBundleForTesting(using: repo, to: folder, sessionDates: ["2030-04-05"])
        let input = folder.appendingPathComponent("insights_bundle.json")
        let original = try Data(contentsOf: input)
        let before = try storage.eventExportRecords(sessionDate: "2030-04-05")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let beforeData = try encoder.encode(before)
        let destination = folder.appendingPathComponent("review.xlsx")
        try ExcelWorkbookFileExporter.write(from: folder, to: destination)
        let data = try Data(contentsOf: destination)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try encoder.encode(storage.eventExportRecords(sessionDate: "2030-04-05")), beforeData)
        let sheets = try StudioWorkbookProjection.sheets(bundleData: original,
            inventoryCSV: String(contentsOf: folder.appendingPathComponent("inventory.csv"), encoding: .utf8))
        XCTAssertEqual(sheets.count, 15)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "org.openxmlformats.spreadsheetml.sheet")
        attachment.name = "DoseTap-synthetic-review.xlsx"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testInvalidInputCannotPublishWorkbook() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("excel-invalid-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("not json".utf8).write(to: folder.appendingPathComponent("insights_bundle.json"))
        try Data("id\n".utf8).write(to: folder.appendingPathComponent("inventory.csv"))
        let destination = folder.appendingPathComponent("review.xlsx")
        XCTAssertThrowsError(try ExcelWorkbookFileExporter.write(from: folder, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
