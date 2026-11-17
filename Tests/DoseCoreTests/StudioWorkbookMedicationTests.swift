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

    func testNonpositiveIntervalsAreReviewedWithoutExcludingSleepOrRewritingEvents() throws {
        for second in ["2026-01-01T23:00:00Z", "2026-01-01T22:59:00Z"] {
            var g = group([event("d1", "dose1", "2026-01-01T23:00:00Z"), event("d2", "dose2", second)])
            g["healthKit"] = ["totalSleepMinutes": 300]
            let sheets = try project([g])
            XCTAssertEqual(cell(sheets, "Dose Summary", "Dose interval"), .blank)
            XCTAssertEqual(cell(sheets, "Dose Summary", "Dose interval eligibility"), .text("nonpositive_dose_interval"))
            XCTAssertEqual(cell(sheets, "Nights", "Apple Health sleep"), .durationMinutes(300))
            let issues = try XCTUnwrap(sheets.first { $0.name == "Review Issues" })
            XCTAssertTrue(issues.rows.contains { $0.contains(.text("nonpositive_dose_interval")) })
            let log = try XCTUnwrap(sheets.first { $0.name == "Medication Log" })
            XCTAssertEqual(log.rows.count, 2)
            let overview = try XCTUnwrap(sheets.first { $0.name == "Overview" })
            XCTAssertTrue(overview.note.contains("1 date groups with record-review flags; 1 record-review issues; 1 unavailable-provider measurements"))
        }
    }

    func testPositiveSubsecondIntervalRemainsEligible() throws {
        let sheets = try project([group([event("d1", "dose1", "2026-01-01T23:00:00Z"), event("d2", "dose2", "2026-01-01T23:00:00.500Z")])])
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose interval eligibility"), .text("available"))
        XCTAssertEqual(cell(sheets, "Dose Summary", "Dose interval"), .durationMinutes(0.5 / 60))
    }

    func testFinalizedCSVAndJSONShareReviewAndPreserveSources() throws {
        let first = event("d1", "dose1", "2026-01-01T23:00:00Z", ["dose2_reminder_enabled": true, "reminder_interval_minutes": 180])
        for second in ["2026-01-01T23:00:00Z", "2026-01-02T02:00:00.500Z"] {
            let g = group([first, event("d2", "dose2", second)])
            let original = try JSONSerialization.data(withJSONObject: ["schemaVersion": 3, "dateGroups": [g]])
            let result = try StudioDoseTimingExport.prepare(bundleData: original)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: result.bundleData) as? [String: Any])
            XCTAssertEqual(root["schemaVersion"] as? Int, 4)
            let emitted = try XCTUnwrap((root["dateGroups"] as? [[String: Any]])?.first)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: emitted["rawEvents"]!, options: .sortedKeys),
                           try JSONSerialization.data(withJSONObject: g["rawEvents"]!, options: .sortedKeys))
            let csv = try ReportCSV.rows(result.sessionsCSV)
            XCTAssertEqual(csv[1][2], "") // no current/historical target invented
            XCTAssertEqual(csv[1][9], "2026-01-01")
            XCTAssertEqual(csv[1][10], "session")
            XCTAssertEqual(csv[1][15], "true")
            XCTAssertEqual(csv[1][16], "180.0")
            let review = try XCTUnwrap(emitted["doseTimingReview"] as? [String: Any])
            let zero = second == "2026-01-01T23:00:00Z"
            XCTAssertEqual(csv[1][12], zero ? "needs_review" : "available")
            XCTAssertEqual(review["status"] as? String, csv[1][12])
            XCTAssertEqual(review["rawIntervalSeconds"] as? Double, zero ? 0 : 10800.5)
            XCTAssertEqual(csv[1][11], zero ? "" : "10800.5")
            let sheets = try StudioWorkbookProjection.sheets(bundleData: result.bundleData, inventoryCSV: "")
            XCTAssertEqual(cell(sheets, "Dose Summary", "Dose interval eligibility"), .text(csv[1][13]))
        }
    }

    func testCSVSkipIsExplicitAndRawOnlyGroupIsRetainedOnlyInJSON() throws {
        let events = [event("first", "dose1", "2026-01-01T23:00:00Z"), event("skip", "dose2_skipped", "2026-01-02T03:00:00Z")]
        var raw = group([]); raw["sessionDate"] = "2026-01-02"
        raw["identityResolution"] = ["version": 1, "status": "raw_only", "sessionIds": ["x", "y"], "reasons": ["multiple_session_identities"]]
        let result = try StudioDoseTimingExport.prepare(bundleData: JSONSerialization.data(withJSONObject: ["schemaVersion": 3, "dateGroups": [group(events), raw]]))
        let csv = try ReportCSV.rows(result.sessionsCSV)
        XCTAssertEqual(csv.count, 2)
        guard csv.count == 2 else { return }
        XCTAssertEqual(csv[1][4], "explicitly_skipped")
        XCTAssertEqual(csv[1][11], "")
        XCTAssertEqual(csv[1][13], "dose2_explicitly_skipped")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: result.bundleData) as? [String: Any])
        XCTAssertEqual((root["dateGroups"] as? [[String: Any]])?.count, 2)
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
