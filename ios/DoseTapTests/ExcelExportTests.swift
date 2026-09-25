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
        INSERT INTO dose_events(id,session_id,event_type,timestamp,session_date,metadata)
        VALUES('excel-dose','excel-session','dose1','2030-04-05T23:00:00Z','2030-04-05','{"amount_mg":4500,"dose2_reminder_enabled":false}'),
        ('excel-dose2','excel-session','dose2','2030-04-06T01:50:00Z','2030-04-05','{"recorded_at_utc":"2030-04-06T07:00:00Z","entry_mode":"retrospective","reason":"forgot_to_tap"}');
        INSERT INTO sleep_events(id,session_id,event_type,timestamp,session_date,notes)
        VALUES('excel-event','excel-session','future_quick_log','2030-04-06T01:00:00Z','2030-04-05','=1+1');
        """, nil, nil, nil), SQLITE_OK)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("excel-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try StudioBundleExporter().writeStudioExportBundleForTesting(using: repo, to: folder, sessionDates: ["2030-04-05"])
        let input = folder.appendingPathComponent("insights_bundle.json")
        let original = try Data(contentsOf: input)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        XCTAssertEqual(root["schemaVersion"] as? Int, 4)
        let csv = try ReportCSV.rows(String(contentsOf: folder.appendingPathComponent("sessions.csv"), encoding: .utf8))
        XCTAssertEqual(csv.count, 2)
        XCTAssertEqual(csv[1][2], "")
        XCTAssertEqual(csv[1][9], "2030-04-05")
        XCTAssertEqual(csv[1][10], "excel-session")
        XCTAssertEqual(csv[1][11], "10200.0")
        XCTAssertEqual(csv[1][12], "available")
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
        XCTAssertEqual(sheets.count, 17)
        let summary = try XCTUnwrap(sheets.first { $0.name == "Dose Summary" })
        XCTAssertEqual(summary.rows.count, 1)
        XCTAssertEqual(summary.rows[0][try XCTUnwrap(summary.columns.firstIndex(of: "Dose interval"))], .durationMinutes(170))
        XCTAssertEqual(summary.rows[0][try XCTUnwrap(summary.columns.firstIndex(of: "Dose 1 amount"))], .number(4500))
        XCTAssertEqual(summary.rows[0][try XCTUnwrap(summary.columns.firstIndex(of: "Dose 2 reminder"))], .text("No alarm"))
        let log = try XCTUnwrap(sheets.first { $0.name == "Medication Log" })
        XCTAssertEqual(log.rows.count, 2)
        XCTAssertEqual(log.rows[1][try XCTUnwrap(log.columns.firstIndex(of: "Recording delay"))], .durationMinutes(310))
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
