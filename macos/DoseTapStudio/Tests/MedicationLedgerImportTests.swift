import XCTest
import DoseCore
@testable import DoseTapStudio

final class MedicationLedgerImportTests: XCTestCase {
    func testIndependentLedgerSurvivesImportReexportWithoutNights() throws {
        let time = Date(timeIntervalSince1970: 1_790_000_000)
        let part = try MedicationPresetComponent(id: UUID(), form: .tablet,
            strengthMilligrams: Decimal(string: "1.1234567890123456789")!, unitCount: 1)
        let preset = try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(), supersedesRevisionID: nil,
            labelName: "Synthetic", ingredient: "Synthetic ingredient", releaseProfile: .extendedRelease,
            components: [part], instructions: "Entered label", schedule: .scheduled,
            effectiveFrom: time, effectiveUntil: nil, recordedAt: time)
        let actual = try ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: [part],
            occurredAt: nil, precision: .unknown, timeZoneIdentifier: nil, utcOffsetSeconds: nil,
            confirmedAt: time, recordedAt: time.addingTimeInterval(30))
        let ledger = try MedicationPresetExportSnapshot(presetRevisions: [MedicationPresetExportSnapshot.encode(preset)],
            administrations: [MedicationPresetExportSnapshot.encode(actual)])
        let object: [String: Any] = ["schemaVersion": 5, "exportVersion": "3.0", "dateGroups": [],
            "exportedAtUTC": "2026-09-25T12:00:00Z", "medicationPresetLedger": try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger))]
        let imported = try Importer().parseInsightsBundle(JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(imported.sessions.isEmpty)
        XCTAssertEqual(imported.medicationPresetLedger, ledger)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let restored = try Importer().parseInsightsBundle(encoder.encode(imported))
        XCTAssertEqual(restored.medicationPresetLedger, ledger)
        XCTAssertEqual(try MedicationPresetExportSnapshot.decodeAdministration(try XCTUnwrap(restored.medicationPresetLedger?.administrations.first)), actual)
    }

    func testMissingInvalidAndLegacyLedgerFailClosed() throws {
        for fragment in ["", #", "medicationPresetLedger":null"#,
                         #", "medicationPresetLedger":{"schemaVersion":1,"presetRevisions":["{}"],"administrations":[]}"#] {
            let data = Data((#"{"schemaVersion":5,"exportedAtUTC":"2026-09-25T12:00:00Z","dateGroups":[]"# + fragment + "}").utf8)
            XCTAssertThrowsError(try Importer().parseInsightsBundle(data))
        }
        let legacy = Data(#"{"schemaVersion":4,"exportedAtUTC":"2026-09-25T12:00:00Z","dateGroups":[],"medicationPresetLedger":{"schemaVersion":1,"presetRevisions":[],"administrations":[]}}"#.utf8)
        XCTAssertThrowsError(try Importer().parseInsightsBundle(legacy))
    }
}
