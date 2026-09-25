import XCTest
@testable import DoseCore

final class StudioMedicationLedgerFormatTests: XCTestCase {
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
