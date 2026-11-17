import XCTest
@testable import DoseCore

final class StudioWorkbookPresetTests: XCTestCase {
    func ledger(knownTime: Bool = false) throws -> MedicationPresetExportSnapshot {
        let time = Date(timeIntervalSince1970: 1_790_000_000)
        let part = try MedicationPresetComponent(id: UUID(), form: .tablet,
            strengthMilligrams: Decimal(string: "1.1234567890123456789")!, unitCount: 1)
        let preset = try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(), supersedesRevisionID: nil,
            labelName: "Synthetic", ingredient: "Synthetic ingredient", releaseProfile: .extendedRelease,
            components: [part], instructions: "Patient-entered label", schedule: .scheduled,
            effectiveFrom: time, effectiveUntil: nil, recordedAt: time)
        let actual = try ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: [part],
            occurredAt: knownTime ? time : nil, precision: knownTime ? .approximate : .unknown,
            timeZoneIdentifier: knownTime ? "America/New_York" : nil, utcOffsetSeconds: knownTime ? -14400 : nil,
            confirmedAt: time, recordedAt: time.addingTimeInterval(30))
        return try MedicationPresetExportSnapshot(presetRevisions: [MedicationPresetExportSnapshot.encode(preset)],
            administrations: [MedicationPresetExportSnapshot.encode(actual)])
    }

    func bundle(_ ledger: MedicationPresetExportSnapshot) throws -> Data {
        let encoded = try JSONEncoder().encode(ledger)
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 5, "exportVersion": "3.0",
            "dateGroups": [], "medicationPresetLedger": JSONSerialization.jsonObject(with: encoded)])
    }

    func testZeroNightsPreservesUnknownTimeAndExactDecimalThroughPreparation() throws {
        let source = try ledger(), original = try bundle(source)
        let prepared = try StudioDoseTimingExport.prepare(bundleData: original)
        struct Envelope: Decodable { let schemaVersion: Int; let medicationPresetLedger: MedicationPresetExportSnapshot }
        let result = try JSONDecoder().decode(Envelope.self, from: prepared.bundleData)
        XCTAssertEqual(result.schemaVersion, 5)
        XCTAssertEqual(result.medicationPresetLedger, source)
        XCTAssertEqual(try ReportCSV.rows(prepared.sessionsCSV).count, 1)
        let sheets = try StudioWorkbookProjection.sheets(bundleData: prepared.bundleData, inventoryCSV: "")
        let actual = try XCTUnwrap(sheets.first { $0.name == "Confirmed Medications" })
        XCTAssertEqual(actual.rows.count, 1)
        XCTAssertEqual(actual.rows[0][try XCTUnwrap(actual.columns.firstIndex(of: "Actual amount (mg, exact text)"))], .text("1.1234567890123456789"))
        XCTAssertEqual(actual.rows[0][try XCTUnwrap(actual.columns.firstIndex(of: "Occurred (UTC)"))], .blank)
        XCTAssertEqual(actual.rows[0][try XCTUnwrap(actual.columns.firstIndex(of: "Time precision"))], .text("unknown"))
        XCTAssertTrue(try XCTUnwrap(sheets.first { $0.name == "Dose Summary" }).rows.isEmpty)
        let parts = try ExcelWorkbookWriter.parts(sheets: sheets)
        let xml = String(decoding: try XCTUnwrap(parts["xl/worksheets/sheet5.xml"]), as: UTF8.self)
        XCTAssertTrue(xml.contains("1.1234567890123456789"))
        XCTAssertTrue(String(decoding: try XCTUnwrap(parts["xl/tables/table5.xml"]), as: UTF8.self).contains("autoFilter"))
        if let output = ProcessInfo.processInfo.environment["DOSETAP_LEDGER_WORKBOOK_FIXTURE"] {
            try ExcelWorkbookWriter.encode(sheets: sheets).write(to: URL(fileURLWithPath: output))
        }
        let fields = try XCTUnwrap(sheets.first { $0.name == "Source Fields" })
        XCTAssertTrue(fields.rows.contains { $0.contains(.text(source.administrations[0])) })
        XCTAssertFalse(fields.rows.contains { row in row.contains { if case .text(let s) = $0 { return s.contains("medicationPresetLedger") && s.contains("$parsed") }; return false } })
    }

    func testKnownTimeIsSortableDateAndLegacySheetLayoutIsPreserved() throws {
        let input = try bundle(ledger(knownTime: true))
        let sheets = try StudioWorkbookProjection.sheets(bundleData: input, inventoryCSV: "")
        let actual = try XCTUnwrap(sheets.first { $0.name == "Confirmed Medications" })
        XCTAssertEqual(actual.rows[0][try XCTUnwrap(actual.columns.firstIndex(of: "Occurred (UTC)"))], .date(Date(timeIntervalSince1970: 1_790_000_000)))
        XCTAssertEqual(sheets.count, 19)
        XCTAssertTrue(sheets.allSatisfy { table in table.rows.allSatisfy { $0.count == table.columns.count } })
        let legacy = Data(#"{"schemaVersion":4,"dateGroups":[]}"#.utf8)
        XCTAssertEqual(try StudioWorkbookProjection.sheets(bundleData: legacy, inventoryCSV: "").count, 17)
    }

    func testKnownTimeOutsideExcelRangeIsNotPresentedAsUnknown() throws {
        let source = try ledger()
        let preset = try MedicationPresetExportSnapshot.decodePreset(source.presetRevisions[0])
        let actual = try ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: preset.components,
            occurredAt: Date(timeIntervalSince1970: -2_240_611_200), precision: .exact,
            timeZoneIdentifier: "UTC", utcOffsetSeconds: 0, confirmedAt: preset.recordedAt, recordedAt: preset.recordedAt)
        let snapshot = try MedicationPresetExportSnapshot(presetRevisions: source.presetRevisions,
            administrations: [MedicationPresetExportSnapshot.encode(actual)])
        let sheets = try StudioWorkbookProjection.sheets(bundleData: bundle(snapshot), inventoryCSV: "")
        let sheet = try XCTUnwrap(sheets.first { $0.name == "Confirmed Medications" })
        for column in ["Occurred (UTC)", "Occurred (recorded offset)"] {
            XCTAssertEqual(sheet.rows[0][try XCTUnwrap(sheet.columns.firstIndex(of: column))],
                .text("Outside Excel date range; see Source Fields"))
        }
        XCTAssertEqual(sheet.rows[0][1], .text("Extended release (XR)"))
    }

    func testMissingMalformedAndMisversionedLedgerFailClosed() throws {
        for json in [#"{"schemaVersion":5,"dateGroups":[]}"#,
                     #"{"schemaVersion":5,"dateGroups":[],"medicationPresetLedger":null}"#,
                     #"{"schemaVersion":5,"dateGroups":[],"medicationPresetLedger":{"schemaVersion":1,"presetRevisions":["{}"],"administrations":[]}}"#,
                     #"{"schemaVersion":4,"dateGroups":[],"medicationPresetLedger":{"schemaVersion":1,"presetRevisions":[],"administrations":[]}}"#] {
            XCTAssertThrowsError(try StudioDoseTimingExport.prepare(bundleData: Data(json.utf8)))
            XCTAssertThrowsError(try StudioWorkbookProjection.sheets(bundleData: Data(json.utf8), inventoryCSV: ""))
        }
    }
}
