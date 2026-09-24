import XCTest
@testable import DoseCore

final class StudioWorkbookMedicationTests: XCTestCase {
    func testMedicationViewsLeadAndHaveStableEmptyColumns() throws {
        let sheets = try project([])
        XCTAssertEqual(Array(sheets.prefix(3).map(\.name)), ["Overview", "Dose Summary", "Medication Log"])
        let log = try XCTUnwrap(sheets.first { $0.name == "Medication Log" })
        XCTAssertTrue(log.rows.isEmpty)
        XCTAssertTrue(log.columns.contains("Amount"))
        XCTAssertTrue(log.columns.contains("Recorded (UTC)"))
    }

    func testMidnightPairShowsAmountRecordingDelayAndIndependentNoAlarmChoice() throws {
        let first = event("d1", "dose1", "2026-01-01T23:00:00Z", ["amount_mg": 4500, "dose2_reminder_enabled": false])
        let second = event("d2", "dose2", "2026-01-02T01:50:30Z", ["entry_mode": "retrospective", "recorded_at_utc": "2026-01-02T07:00:30Z", "reason": "forgot_to_tap"])
        let sheets = try project([group([first, second])])
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose interval"), .durationMinutes(170.5))
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose 1 amount"), .number(4500))
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose 2 amount"), .blank)
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose 2 reminder"), .text("No alarm"))
        XCTAssertEqual(cell(sheets, "Dose Summary", "Reminder interval"), .blank)
        let log = try XCTUnwrap(sheets.first { $0.name == "Medication Log" })
        let row = log.rows.first { $0[log.columns.firstIndex(of: "Dose / record")!] == .text("Dose 2") }!
        XCTAssertEqual(row[log.columns.firstIndex(of: "Recording delay")!], .durationMinutes(310))
        XCTAssertEqual(row[log.columns.firstIndex(of: "Reason")!], .text("forgot_to_tap"))
        XCTAssertEqual(cell(sheets, "Nights", "Dose interval"), .durationMinutes(170.5))
    }

    func testSummaryConflictAndSkipNeverProduceInterval() throws {
        for events in [[event("d1", "dose1", "2026-01-01T23:00:00Z"), event("skip", "dose2_skipped", "2026-01-02T03:00:00Z")],
                       [event("d1", "dose1", "2026-01-01T23:00:00Z"), event("d2", "dose2", "2026-01-02T02:00:00Z")]] {
            var g = group(events); g["dose1TimeUTC"] = "2026-01-01T23:00:00Z"; g["dose2TimeUTC"] = "2026-01-02T01:50:00Z"
            let sheets = try project([g])
            XCTAssertEqual(cell(sheets, "Nights", "Dose interval"), .blank)
            XCTAssertEqual(cell(sheets, "Dose Summary", "Dose interval"), .blank)
            XCTAssertEqual(cell(sheets, "Dose Summary", "Dose 2 outcome"), .text("Conflicting dose records"))
        }
    }

    func testCreationIsNotRecordingAndAuditRowsAreNotAdministrations() throws {
        var first = event("d1", "dose1", "2026-01-01T23:00:00Z")
        first["createdAtStoredUTC"] = "2026-01-02T08:00:00Z"
        let correction = event("edit", "history_correction", "2026-01-02T09:00:00Z", ["removed_from_effective_record": true])
        var g = group([first, first, correction]); g["normalizedEvents"] = [first]
        let sheets = try project([g]); let log = try XCTUnwrap(sheets.first { $0.name == "Medication Log" })
        XCTAssertEqual(log.rows.count, 2)
        XCTAssertTrue(log.rows.allSatisfy { $0[log.columns.firstIndex(of: "Recorded (UTC)")!] == .blank })
        XCTAssertTrue(log.rows.allSatisfy { $0[log.columns.firstIndex(of: "Recording delay")!] == .blank })
        XCTAssertTrue(log.rows.contains { $0[log.columns.firstIndex(of: "Outcome / status")!] == .text("Audit only — not an administration") })
    }

    func testDSTAbsoluteIntervalAndUnknownTimeWithIndependentMedication() throws {
        let d1 = event("d1", "dose1", "2026-11-01T05:30:00Z")
        let d2 = event("d2", "dose2", "2026-11-01T06:30:00Z")
        var g = group([d1, d2]); g["medications"] = [["id": "other", "medicationId": "recorded-medicine", "doseMg": 25, "doseUnit": "mg", "takenAtUTC": "2026-11-01T07:00:00Z"]]
        let sheets = try project([g], timezone: "America/New_York")
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose interval"), .durationMinutes(60))
        XCTAssertEqual(try XCTUnwrap(sheets.first { $0.name == "Medication Log" }).rows.count, 3)
        let unknown = try project([group([event("d2", "dose2", nil)])])
        XCTAssertEqual(cell(unknown, "Dose Summary", "Dose 2 outcome"), .text("Taken — time unavailable"))
        XCTAssertEqual(cell(unknown, "Dose Summary", "Dose interval"), .blank)
    }

    func testRawOnlyAndDuplicatesRetainSourceWithoutChoosingDose() throws {
        var g = group([event("a", "dose1", "2026-01-01T23:00:00Z"), event("b", "dose1", "2026-01-01T23:01:00Z")])
        XCTAssertEqual(cell(try project([g]), "Dose Summary", "Dose 1 outcome"), .text("Conflicting dose records"))
        g["identityResolution"] = ["version": 1, "status": "raw_only", "sessionIds": ["one", "two"], "reasons": ["multiple_session_identities"]]
        let sheets = try project([g])
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose 1 taken (local)"), .blank)
        XCTAssertEqual(try XCTUnwrap(sheets.first { $0.name == "Medication Log" }).rows.count, 2)
    }

    func testCorrectedDoseDoesNotMasqueradeAsDelayedInitialRecording() throws {
        let first = event("d1", "dose1", "2026-01-01T23:00:00Z")
        let corrected = event("d2", "dose2", "2026-01-02T02:00:00Z", ["recorded_at_utc": "2026-01-05T12:00:00Z", "correction": ["corrected_at_utc": "2026-01-05T12:00:00Z", "previous_events": []]])
        let sheets = try project([group([first, corrected])])
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose 2 recording delay"), .blank)
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose 2 recording (local)"), .blank)
        let log = try XCTUnwrap(sheets.first { $0.name == "Medication Log" })
        let row = try XCTUnwrap(log.rows.last)
        XCTAssertEqual(row[try XCTUnwrap(log.columns.firstIndex(of: "Recording delay"))], .blank)
        XCTAssertEqual(row[try XCTUnwrap(log.columns.firstIndex(of: "Outcome / status"))], .text("Taken — corrected record"))
    }

    func testRemovedDoseCannotBeResurrectedFromSummaryOnlyTimestamp() throws {
        var g = group([event("edit", "history_correction", "2026-01-03T12:00:00Z", ["removed_from_effective_record": true])])
        g["dose1TimeUTC"] = "2026-01-01T23:00:00Z"; g["dose2TimeUTC"] = "2026-01-02T02:00:00Z"
        let sheets = try project([g])
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose interval"), .blank)
        XCTAssertEqual(cell(sheets, "Nights", "Dose interval"), .blank)
    }

    private func event(_ id: String, _ kind: String, _ time: String?, _ metadata: [String: Any] = [:]) -> [String: Any] {
        var e: [String: Any] = ["id": id, "sourceTable": "dose_events", "eventType": kind, "details": String(data: try! JSONSerialization.data(withJSONObject: metadata), encoding: .utf8)!]
        if let time { e["occurredAtUTC"] = time }; return e
    }
    private func group(_ events: [[String: Any]]) -> [String: Any] {
        ["sessionDate": "2026-01-01", "identityResolution": ["version": 1, "status": "resolved", "sessionIds": ["session"], "reasons": []], "rawEvents": events]
    }
    private func project(_ groups: [[String: Any]], timezone: String = "UTC") throws -> [WorkbookSheet] {
        try StudioWorkbookProjection.sheets(bundleData: JSONSerialization.data(withJSONObject: ["schemaVersion": 3, "timeZoneIdentifier": timezone, "dateGroups": groups]), inventoryCSV: "")
    }
    private func cell(_ sheets: [WorkbookSheet], _ name: String, _ column: String) -> WorkbookCell {
        guard let sheet = sheets.first(where: { $0.name == name }), let index = sheet.columns.firstIndex(of: column), let row = sheet.rows.first else { XCTFail("Missing \(name)/\(column)"); return .blank }
        return row[index]
    }
}
