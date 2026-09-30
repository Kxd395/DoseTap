import XCTest
@testable import DoseCore

final class StudioWorkbookProjectionTests: XCTestCase {
    func testIndependentRoadmapRecordsSurviveWithoutInventedNights() throws {
        let payload = "{\"revision\":1,\"score\":0,\"note\":\"=1+1\"}"
        let row: [String: Any] = ["sourceTable": "daytime_checkins", "columns": [
            "revision_id": ["type": "text", "text": "revision-1"],
            "payload": ["type": "text", "text": payload]]]
        let bundle: [String: Any] = ["schemaVersion": 6, "archiveScope": "manual_full_local_records", "independentRecordsIncluded": true, "dateGroups": [],
            "medicationPresetLedger": ["schemaVersion": 1, "presetRevisions": [], "administrations": []],
            "independentSourceRecords": [row, row]]
        let original = try JSONSerialization.data(withJSONObject: bundle)
        let prepared = try StudioDoseTimingExport.prepare(bundleData: original)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: prepared.bundleData) as? [String: Any])
        XCTAssertEqual(root["schemaVersion"] as? Int, 6)
        XCTAssertEqual((root["independentSourceRecords"] as? [Any])?.count, 2)
        let data = try StudioWorkbookData(bundleData: prepared.bundleData, inventoryCSV: "")
        XCTAssertTrue(data.groups.isEmpty)
        XCTAssertEqual(data.records.count, 1)
        XCTAssertEqual(data.records.first?.id, "revision-1")
        XCTAssertTrue(data.records.first?.groupKeys.isEmpty == true)
        XCTAssertEqual(data.identity(for: try XCTUnwrap(data.records.first)), "Independent of treatment dates")
        let fields = data.sourceFieldsSheet()
        XCTAssertTrue(fields.rows.contains { $0.contains(.text(payload)) })
        XCTAssertTrue(fields.rows.contains { $0.contains(.text("=1+1")) })
        XCTAssertEqual(try ReportCSV.rows(prepared.sessionsCSV).count, 1)
    }

    func testIndependentRecordsRequireSchemaAndStrictTypedValues() throws {
        let base: [String: Any] = ["schemaVersion": 6, "archiveScope": "manual_full_local_records", "independentRecordsIncluded": true, "dateGroups": [],
            "medicationPresetLedger": ["schemaVersion": 1, "presetRevisions": [], "administrations": []]]
        for value: Any in [NSNull(), "invalid", [["sourceTable": "daytime_events", "columns": ["payload": ["type": "real", "text": "bad"]]]]] {
            var root = base; root["independentSourceRecords"] = value
            XCTAssertThrowsError(try StudioWorkbookData(bundleData: JSONSerialization.data(withJSONObject: root), inventoryCSV: ""))
        }
        XCTAssertThrowsError(try StudioWorkbookData(bundleData: JSONSerialization.data(withJSONObject: base), inventoryCSV: ""))
        var legacy = base; legacy["schemaVersion"] = 5; legacy["independentSourceRecords"] = []
        XCTAssertThrowsError(try StudioWorkbookData(bundleData: JSONSerialization.data(withJSONObject: legacy), inventoryCSV: ""))
        legacy.removeValue(forKey: "independentSourceRecords")
        XCTAssertThrowsError(try StudioWorkbookData(bundleData: JSONSerialization.data(withJSONObject: legacy), inventoryCSV: ""))
    }

    func testIndependentCatalogRetainsEveryTableAndConflictingRevisionVariant() throws {
        var rows: [[String: Any]] = StudioIndependentSourceRecord.sourceTables.map { table in
            ["sourceTable": table, "columns": [
                StudioIndependentSourceRecord.primaryKeys[table]!: ["type": "text", "text": "original"],
                "missing": ["type": "null"], "zero": ["type": "integer", "integer": 0],
                "binary": ["type": "blob", "blobBase64": "AAE="], "payload": ["type": "text", "text": "{}"]]]
        }
        var conflict = rows[0]
        var columns = try XCTUnwrap(conflict["columns"] as? [String: Any])
        columns["payload"] = ["type": "text", "text": "{\"correction\":true}"]
        conflict["columns"] = columns; rows.append(conflict)
        let root: [String: Any] = ["schemaVersion": 6, "archiveScope": "manual_full_local_records", "independentRecordsIncluded": true, "dateGroups": [], "independentSourceRecords": rows,
            "medicationPresetLedger": ["schemaVersion": 1, "presetRevisions": [], "administrations": []]]
        let data = try StudioWorkbookData(bundleData: JSONSerialization.data(withJSONObject: root), inventoryCSV: "")
        XCTAssertEqual(data.records.count, StudioIndependentSourceRecord.sourceTables.count + 1)
        XCTAssertEqual(Set(data.records.map(\.table)), Set(StudioIndependentSourceRecord.sourceTables))
        XCTAssertEqual(data.records.filter { data.identity(for: $0) == "Needs record review" }.count, 2)
        XCTAssertTrue(data.groups.isEmpty)
        let fields = data.sourceFieldsSheet()
        XCTAssertTrue(fields.rows.contains { $0.contains(.text("Explicit null")) })
        XCTAssertTrue(fields.rows.contains { $0.contains(.number(0)) })
    }

    func testSeventeenNamedSheetsEmptySourcesAndNoInventedObservations() throws {
        let result = try project([])
        XCTAssertEqual(result.map(\.name), ["Overview", "Dose Summary", "Medication Log", "Nights", "Night Review", "Events", "Pre-sleep",
            "Morning", "Pain", "Daytime", "Sleep Measures", "Sleep Intervals", "Medications", "Inventory",
            "Source Fields", "Review Issues", "Field Guide"])
        for name in ["Nights", "Events", "Pre-sleep", "Morning", "Pain", "Daytime", "Sleep Measures",
                     "Sleep Intervals", "Medications", "Inventory"] {
            XCTAssertTrue(sheet(name, result).rows.isEmpty, name)
        }
        XCTAssertEqual(Set(result.map(\.tableName)).count, result.count)
        XCTAssertTrue(result.allSatisfy { table in table.rows.allSatisfy { $0.count == table.columns.count } })
    }

    func testFixedWindowUsesLatestExportedDateAndKeepsZeroMissingAndExcludedSeparate() throws {
        let result = try project([
            group("2026-01-01", health: ["totalSleepMinutes": 120], collected: ["followingDayType": "workday"]),
            group("2026-01-08"),
            group("2026-01-09", health: ["totalSleepMinutes": 0], collected: ["followingDayType": "dayOff"]),
            group("2026-01-10", status: "raw_only", health: ["totalSleepMinutes": 999])
        ])
        let overview = sheet("Overview", result)
        let recent = try XCTUnwrap(overview.rows.first {
            value($0, "Period", overview) == .text("7 days") &&
            value($0, "Provider", overview) == .text("Apple Health") &&
            value($0, "Population", overview) == .text("All date groups")
        })
        XCTAssertEqual(value(recent, "Usable measurements", overview), .number(1))
        XCTAssertEqual(value(recent, "Eligible date groups", overview), .number(2))
        XCTAssertEqual(value(recent, "Missing measurements", overview), .number(1))
        XCTAssertEqual(value(recent, "Excluded date groups", overview), .number(1))
        XCTAssertEqual(value(recent, "Mean sleep", overview), .durationMinutes(0))
        let all = try XCTUnwrap(overview.rows.first {
            value($0, "Period", overview) == .text("All exported dates") &&
            value($0, "Provider", overview) == .text("Apple Health") &&
            value($0, "Population", overview) == .text("All date groups")
        })
        XCTAssertEqual(value(all, "Mean sleep", overview), .durationMinutes(60))
        XCTAssertEqual(value(all, "Median sleep", overview), .durationMinutes(60))
        XCTAssertEqual(sheet("Nights", result).rows.count, 4)
        XCTAssertEqual(overview.chart?.values.last!, nil)
    }

    func testOriginalEventsAreNotCountedAgainFromNormalizedViewAndUnknownVocabularySurvives() throws {
        let event: [String: Any] = ["id": "00012", "sourceTable": "sleep_events", "eventType": "future_event",
            "occurredAtUTC": "2026-11-01T06:30:00.123Z", "createdAtStoredUTC": "2026-11-01T06:31:00Z",
            "sessionId": "session-a", "details": "=HYPERLINK(\"https://example.invalid\")"]
        var item = group("2026-10-31")
        item["rawEvents"] = [event, event]
        item["normalizedEvents"] = [event]
        let result = try project([item], timezone: "America/New_York")
        let events = sheet("Events", result)
        XCTAssertEqual(events.rows.count, 1)
        let row = try XCTUnwrap(events.rows.first)
        XCTAssertEqual(value(row, "Event type", events), .text("future_event"))
        XCTAssertEqual(value(row, "Record ID", events), .text("00012"))
        XCTAssertEqual(value(row, "Details", events), .text("=HYPERLINK(\"https://example.invalid\")"))
        XCTAssertEqual(value(row, "Occurred (UTC)", events), .date(date("2026-11-01T06:30:00.123Z")))
        XCTAssertEqual(value(row, "Occurred (local)", events), .text("2026-11-01T01:30:00.123-05:00"))
    }

    func testQuestionnaireAcrossDatesIsOneOriginalAndPainEntriesStayIndependentIncludingZero() throws {
        let answers: [String: Any] = ["roomTemp": "cool", "sleepingSetup": ["pets": "on_bed"],
            "painEntries": [["area": "back", "side": "center", "intensity": 0],
                            ["area": "foot", "side": "left", "intensity": 7, "sensations": ["burning"]]]]
        let source = preSource(answers)
        var a = group("2026-01-01", status: "raw_only")
        var b = group("2026-01-02", status: "raw_only")
        a["rawSourceRecords"] = [source]; b["rawSourceRecords"] = [source]
        a["preSleep"] = ["bodyPain": "severe", "rawAnswersJson": json(answers)]
        let result = try project([a, b])
        let pre = sheet("Pre-sleep", result), pain = sheet("Pain", result)
        XCTAssertEqual(pre.rows.count, 1)
        XCTAssertEqual(value(pre.rows[0], "Treatment dates", pre), .text("2026-01-01; 2026-01-02"))
        XCTAssertEqual(value(pre.rows[0], "Date association", pre), .text("Multiple dates — review"))
        XCTAssertEqual(pain.rows.count, 2)
        XCTAssertEqual(Set(pain.rows.map { text(value($0, "Intensity (0–10)", pain)) }), ["0.0", "7.0"])
        XCTAssertTrue(pre.columns.contains("answers.sleepingSetup.pets"))
    }

    func testConflictingVariantsRetainedAndExcludePreviouslyResolvedAnalytics() throws {
        var a = group("2026-01-01", health: ["totalSleepMinutes": 300])
        var b = group("2026-01-02", health: ["totalSleepMinutes": 400])
        a["rawSourceRecords"] = [preSource(["notes": "first"])]
        b["rawSourceRecords"] = [preSource(["notes": "second"])]
        let result = try project([a, b])
        XCTAssertEqual(sheet("Pre-sleep", result).rows.count, 2)
        let issues = sheet("Review Issues", result)
        XCTAssertTrue(issues.rows.contains { value($0, "Category", issues) == .text("Conflicting source variants") })
        let nights = sheet("Nights", result)
        XCTAssertTrue(nights.rows.allSatisfy { value($0, "Identity permits summaries", nights) == .text("No") })
    }

    func testEveryUnknownFieldRetainedAndLongStringsSplitWithoutTruncation() throws {
        let long = String(repeating: "🌙", count: 20_000) + "END"
        var item = group("2026-01-01")
        item["future"] = ["large": long, "empty": "", "null": NSNull(), "array": [],
                          "zero": 0, "unsafe": "literal\u{0000}value"] as [String: Any]
        let result = try project([item])
        let fields = sheet("Source Fields", result)
        let parts = fields.rows.filter { text(value($0, "Field path", fields)).hasSuffix("/future/large") }
            .sorted { numeric(value($0, "Part", fields)) < numeric(value($1, "Part", fields)) }
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.map { text(value($0, "Value", fields)) }.joined(), long)
        XCTAssertTrue(fields.rows.contains { value($0, "Value status", fields) == .text("Explicit null") })
        XCTAssertTrue(fields.rows.contains { value($0, "Value status", fields) == .text("Empty text") })
        XCTAssertTrue(fields.rows.contains { value($0, "Value status", fields) == .text("Empty array") })
        XCTAssertTrue(fields.rows.contains { text(value($0, "Value", fields)) == "literal\\u0000value" })
        XCTAssertTrue(result.flatMap(\.rows).flatMap { $0 }.allSatisfy {
            if case .text(let string) = $0 { return string.utf16.count <= 32_767 && !string.contains("\u{0000}") }
            return true
        })
    }

    func testDoseTwoIntervalEvidenceDoesNotInventUnexportedReviewedLatencyMetrics() throws {
        var item = group("2026-01-01", health: ["recordedIntervals": [
            interval("01:00", "02:00", asleep: true), interval("02:00", "02:20", asleep: false),
            interval("02:20", "03:00", asleep: true)]])
        item["dose2TimeUTC"] = "2026-01-02T02:10:00Z"
        let result = try project([item])
        let review = sheet("Night Review", result)
        let returned = try XCTUnwrap(review.rows.first { value($0, "Measure or event", review) == .text("Dose 2 to observed return to sleep") })
        XCTAssertEqual(value(returned, "Value", review), .blank)
        XCTAssertTrue(text(value(returned, "Status or evidence", review)).contains("not exported"))
        let awake = try XCTUnwrap(review.rows.first { value($0, "Measure or event", review) == .text("Observed awake interval around Dose 2") })
        XCTAssertEqual(value(awake, "Value", review), .durationMinutes(20))
        XCTAssertEqual(value(awake, "Start (UTC)", review), .date(date("2026-01-02T02:00:00Z")))
        XCTAssertEqual(value(awake, "End (UTC)", review), .date(date("2026-01-02T02:20:00Z")))
        item["healthKit"] = ["recordedIntervals": [interval("01:00", "03:00", asleep: true)]]
        let conflictReview = sheet("Night Review", try project([item]))
        let conflict = try XCTUnwrap(conflictReview.rows.first {
            value($0, "Measure or event", conflictReview) == .text("Dose 2 to observed return to sleep")
        })
        XCTAssertEqual(value(conflict, "Value", conflictReview), .blank)
        XCTAssertTrue(text(value(conflict, "Status or evidence", conflictReview)).contains("asleep"))
    }

    func testInventoryCSVQuotedNewlineNumericValuesAndSourceTextIDs() throws {
        let csv = "id,as_of_utc,bottles_remaining,doses_remaining,notes\r\n000001,2026-01-01T12:00:00Z,0,2.5,\"line one\nline two, comma\"\r\n"
        let result = try project([], inventory: csv)
        let inventory = sheet("Inventory", result)
        XCTAssertEqual(inventory.rows.count, 1)
        XCTAssertEqual(value(inventory.rows[0], "id", inventory), .text("000001"))
        XCTAssertEqual(value(inventory.rows[0], "bottles_remaining", inventory), .number(0))
        XCTAssertEqual(value(inventory.rows[0], "doses_remaining", inventory), .number(2.5))
        XCTAssertEqual(value(inventory.rows[0], "notes", inventory), .text("line one\nline two, comma"))
    }

    func testUnsupportedAndContradictorySchemasRejectRatherThanGuess() throws {
        XCTAssertThrowsError(try StudioWorkbookProjection.sheets(bundleData: Data(json(["schemaVersion": 99, "dateGroups": []]).utf8), inventoryCSV: ""))
        XCTAssertThrowsError(try StudioWorkbookProjection.sheets(bundleData: Data(json(["schemaVersion": 3, "dateGroups": [], "sessions": []]).utf8), inventoryCSV: ""))
        XCTAssertThrowsError(try project([["sessionDate": "2026-01-01"]]))
    }

    func testContradictoryResolvedSessionIDsStayOutOfCombinedMetrics() throws {
        var item = group("2026-01-01", health: ["totalSleepMinutes": 300])
        item["identityResolution"] = ["version": 1, "status": "resolved",
                                      "sessionIds": ["session-a", "session-b"], "reasons": []]
        let nights = sheet("Nights", try project([item]))
        XCTAssertEqual(value(nights.rows[0], "Identity permits summaries", nights), .text("No"))
        XCTAssertEqual(value(nights.rows[0], "Apple Health sleep", nights), .blank)
    }

    func testControlEscapesDoNotCollideWithLiteralBackslashText() {
        XCTAssertEqual(SW.escapedControls("control:\u{0000}; literal:\\u0000"),
                       "control:\\u0000; literal:\\\\u0000")
        XCTAssertEqual(SW.escapedControls("literal:\\u0000"), "literal:\\u0000")
    }

    func testDeclaredSessionAcrossDatesIsExcludedEvenWithoutSharedSourceRows() throws {
        var first = group("2026-01-01", health: ["totalSleepMinutes": 300])
        var second = group("2026-01-02", health: ["totalSleepMinutes": 400])
        let identity: [String: Any] = ["version": 1, "status": "resolved", "sessionIds": ["shared-session"], "reasons": []]
        first["identityResolution"] = identity
        second["identityResolution"] = identity
        let nights = sheet("Nights", try project([first, second]))
        XCTAssertEqual(nights.rows.count, 2)
        XCTAssertTrue(nights.rows.allSatisfy { value($0, "Identity permits summaries", nights) == .text("No") })
        XCTAssertTrue(nights.rows.allSatisfy { value($0, "Apple Health sleep", nights) == .blank })
    }

    func testChartRetainsAbsentCalendarDateAsGapWithoutInventingNight() throws {
        let result = try project([group("2026-01-01", health: ["totalSleepMinutes": 300]),
                                  group("2026-01-03", health: ["totalSleepMinutes": 400])])
        let chart = try XCTUnwrap(sheet("Overview", result).chart)
        XCTAssertEqual(chart.categories, ["2026-01-01", "2026-01-02", "2026-01-03"])
        XCTAssertEqual(chart.values, [300, nil, 400])
        XCTAssertEqual(sheet("Nights", result).rows.count, 2)
    }

    func testIntervalOverlapListsActualEventOnlyNotQuestionnaireTimestamp() throws {
        var item = group("2026-01-01", health: ["recordedIntervals": [interval("01:00", "02:00", asleep: false)]])
        item["rawEvents"] = [["id": "bathroom-id", "sourceTable": "sleep_events", "eventType": "bathroom",
                              "occurredAtUTC": "2026-01-02T01:30:00Z"]]
        item["rawSourceRecords"] = [["sourceTable": "morning_checkins", "columns": [
            "id": ["type": "text", "text": "morning-id"],
            "timestamp": ["type": "text", "text": "2026-01-02T01:35:00Z"]]]]
        let intervals = sheet("Sleep Intervals", try project([item]))
        let overlaps = text(value(intervals.rows[0], "Event overlaps", intervals))
        XCTAssertTrue(overlaps.contains("bathroom-id"))
        XCTAssertFalse(overlaps.contains("morning-id"))
    }

    func testLongAndCaseCollidingFutureKeysProduceUniqueSortableHeadersAndRetainOriginalPaths() throws {
        let longKey = String(repeating: "field", count: 100)
        var item = group("2026-01-01")
        item["rawSourceRecords"] = [preSource([longKey: "long value", "MixedCase": 1, "mixedcase": 2])]
        let result = try project([item]), pre = sheet("Pre-sleep", result)
        XCTAssertEqual(Set(pre.columns.map { $0.lowercased() }).count, pre.columns.count)
        XCTAssertTrue(pre.columns.allSatisfy { $0.utf16.count <= 255 })
        let source = sheet("Source Fields", result)
        XCTAssertTrue(source.rows.contains { text(value($0, "Path part", source)).hasSuffix("/" + longKey) })
    }

    private func project(_ groups: [[String: Any]], timezone: String = "UTC", inventory: String = "") throws -> [WorkbookSheet] {
        let object: [String: Any] = ["schemaVersion": 3, "exportVersion": "2.8", "appVersion": "test",
            "exportedAtUTC": "2026-01-11T12:00:00Z", "timeZoneIdentifier": timezone, "dateGroups": groups]
        return try StudioWorkbookProjection.sheets(bundleData: Data(json(object).utf8), inventoryCSV: inventory)
    }
    private func group(_ date: String, status: String = "resolved", health: [String: Any]? = nil,
                       collected: [String: Any]? = nil) -> [String: Any] {
        var result: [String: Any] = ["sessionDate": date, "identityResolution": ["version": 1, "status": status,
            "sessionIds": [date + "-session"], "reasons": status == "resolved" ? [] : ["multiple_session_identities"]],
            "rawEvents": [], "normalizedEvents": [], "rawSourceRecords": []]
        if let health { result["healthKit"] = health }; if let collected { result["collectedNight"] = collected }
        return result
    }
    private func preSource(_ answers: [String: Any]) -> [String: Any] {
        ["sourceTable": "pre_sleep_logs", "columns": [
            "id": ["type": "text", "text": "pre-id"], "session_id": ["type": "text", "text": "session-a"],
            "created_at": ["type": "text", "text": "2026-01-01T21:00:00Z"],
            "answers_json": ["type": "text", "text": json(answers)],
            "completion_state": ["type": "text", "text": "completed"]]]
    }
    private func interval(_ start: String, _ end: String, asleep: Bool) -> [String: Any] {
        ["start": "2026-01-02T\(start):00Z", "end": "2026-01-02T\(end):00Z", "asleep": asleep]
    }
    private func json(_ object: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)! }
    private func sheet(_ name: String, _ sheets: [WorkbookSheet]) -> WorkbookSheet { sheets.first { $0.name == name }! }
    private func value(_ row: [WorkbookCell], _ column: String, _ sheet: WorkbookSheet) -> WorkbookCell { row[sheet.columns.firstIndex(of: column)!] }
    private func text(_ cell: WorkbookCell) -> String {
        switch cell { case .text(let value): return value; case .number(let value): return String(value); default: return "" }
    }
    private func numeric(_ cell: WorkbookCell) -> Double { if case .number(let value) = cell { return value }; return 0 }
    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)!
    }
}
