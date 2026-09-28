import XCTest
@testable import DoseCore

final class StudioWorkbookSupplyTests: XCTestCase {
    private func bundle(_ supply: SupplyBackup) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 4, "dateGroups": [],
            "supplyStateEncoding": "json-date-seconds-since-2001-v1",
            "supplyStateJSON": String(decoding: encoder.encode(supply), as: UTF8.self)])
    }

    func testExactDatesVoidsAndReminderHistorySurviveFinalizationAndSortableSheet() throws {
        let time = Date(timeIntervalSince1970: 1_700_000_000.125)
        var entry = SupplyReminderEntry(year: 2026, month: 10, day: 3, hour: 9, minute: 0)
        entry.changedAt = time; entry.source = "=not_a_formula"
        var reminder = SupplyReminderDocument(current: entry)
        reminder.replace(with: entry, at: time.addingTimeInterval(1.125))
        var supply = SupplyBackup(reminder: reminder)
        let receipt = UUID(), opening = UUID()
        try supply.receiveBottles(id: receipt, count: 3, receivedAt: time, recordedAt: time, now: time)
        try supply.startBottle(id: opening, receiptID: receipt, openedAt: time, recordedAt: time, now: time)
        try supply.voidBottleStart(id: opening, at: time.addingTimeInterval(10), now: time.addingTimeInterval(10))
        let input = try bundle(supply), output = try StudioDoseTimingExport.prepare(bundleData: input)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: input) as? [String: Any])
        let finalized = try XCTUnwrap(JSONSerialization.jsonObject(with: output.bundleData) as? [String: Any])
        XCTAssertEqual(original["supplyStateJSON"] as? String, finalized["supplyStateJSON"] as? String)
        let data = try StudioWorkbookData(bundleData: output.bundleData, inventoryCSV: "")
        XCTAssertEqual(data.supplyState, supply)
        let sheets = try StudioWorkbookProjection.sheets(bundleData: output.bundleData, inventoryCSV: "")
        let sheet = try XCTUnwrap(sheets.first { $0.name == "Bottle & Supply" })
        XCTAssertEqual(sheet.rows.count, 4)
        XCTAssertTrue(sheet.rows.allSatisfy { $0.count == sheet.columns.count })
        let row = try XCTUnwrap(sheet.rows.first { $0.contains(.text(opening.uuidString)) })
        XCTAssertEqual(row[try XCTUnwrap(sheet.columns.firstIndex(of: "Occurred (UTC)"))], .date(time))
        XCTAssertTrue(row.contains(.text("Voided")))
        XCTAssertTrue(row.contains(.text(receipt.uuidString)))
        XCTAssertTrue(try XCTUnwrap(sheets.first { $0.name == "Inventory" }).rows.isEmpty)
        let fields = try XCTUnwrap(sheets.first { $0.name == "Source Fields" })
        XCTAssertTrue(fields.rows.contains { $0.contains(.text("/supplyStateJSON/bottleStarts/0/id")) && $0.contains(.text(opening.uuidString)) })
        XCTAssertFalse(fields.rows.contains { $0.contains(.text(original["supplyStateJSON"] as! String)) })
        let parts = try ExcelWorkbookWriter.parts(sheets: [sheet])
        XCTAssertTrue(String(decoding: try XCTUnwrap(parts["xl/tables/table1.xml"]), as: UTF8.self).contains("autoFilter"))
        XCTAssertFalse(String(decoding: try XCTUnwrap(parts["xl/worksheets/sheet1.xml"]), as: UTF8.self).contains("<f>"))
    }

    func testLegacyAbsenceAndEmptyExportStayDistinct() throws {
        let legacy = Data(#"{"schemaVersion":4,"dateGroups":[]}"#.utf8)
        XCTAssertNil(try StudioWorkbookData(bundleData: legacy, inventoryCSV: "").supplyState)
        XCTAssertEqual(try StudioWorkbookProjection.sheets(bundleData: legacy, inventoryCSV: "").count, 17)
        let sheets = try StudioWorkbookProjection.sheets(bundleData: bundle(SupplyBackup()), inventoryCSV: "")
        XCTAssertEqual(sheets.count, 18)
        XCTAssertTrue(try XCTUnwrap(sheets.first { $0.name == "Bottle & Supply" }).rows.isEmpty)
    }

    func testMalformedPresentSupplyCannotSilentlyPublishWithoutIt() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bundle(SupplyBackup())) as? [String: Any])
        for value: Any in [NSNull(), "not json", "{}", #"{"version":99,"bottleStarts":[]}"#] {
            root["supplyStateJSON"] = value
            XCTAssertThrowsError(try StudioDoseTimingExport.prepare(bundleData: JSONSerialization.data(withJSONObject: root)))
        }
        root["supplyStateJSON"] = "{\"version\":1,\"bottleStarts\":[]}"
        root["supplyStateEncoding"] = "unknown"
        XCTAssertThrowsError(try StudioWorkbookProjection.sheets(bundleData: JSONSerialization.data(withJSONObject: root), inventoryCSV: ""))
        root.removeValue(forKey: "supplyStateJSON")
        XCTAssertThrowsError(try StudioWorkbookProjection.sheets(bundleData: JSONSerialization.data(withJSONObject: root), inventoryCSV: ""))
    }
}
