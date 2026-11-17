import XCTest
import DoseCore
@testable import DoseTapStudio

final class MedicationLedgerImportTests: XCTestCase {
    @MainActor
    func testBuild108UpgradeArchiveRoundTrip() async throws {
        guard let path = ProcessInfo.processInfo.environment["DT_IOS_BUILD108_FIXTURE"] else {
            throw XCTSkip("Set DT_IOS_BUILD108_FIXTURE to the extracted iPhone upgrade archive.")
        }
        let directory = URL(fileURLWithPath: path)
        let input = try Data(contentsOf: directory.appendingPathComponent("insights_bundle.json"))
        let store = DataStore()
        await store.loadAll(from: directory)
        XCTAssertEqual(store.importStatus, .success(store.events.count))
        XCTAssertEqual(store.importedInsightsBundleData, input)
        XCTAssertTrue(store.events.contains {
            $0.sourceRecordId?.uppercased() == "D3499911-CCA6-4C58-952B-2A611C88871E" && $0.sessionDate == "2026-09-20"
        })

        let imported = try XCTUnwrap(store.importedInsightsBundle)
        XCTAssertEqual(imported.schemaVersion, 6)
        let records = try XCTUnwrap(imported.independentSourceRecords)
        XCTAssertEqual(records.count, 9)
        XCTAssertEqual(Set(records.map(\.sourceTable)), Set(StudioIndependentSourceRecord.sourceTables))
        let checkIns = records.filter { $0.sourceTable == "daytime_checkins" }
        XCTAssertEqual(Set(checkIns.map(\.recordID)).count, 2)
        let observations = try checkIns.map { try XCTUnwrap($0.columns["observation_id"]?.text) }
        XCTAssertEqual(Set(observations).count, 1)

        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: input) as? [String: Any])
        let originalRows = try XCTUnwrap(original["independentSourceRecords"])
        let encodedRows = try JSONEncoder().encode(records)
        let encoded = try JSONSerialization.jsonObject(with: encodedRows)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: encoded, options: .sortedKeys),
                       try JSONSerialization.data(withJSONObject: originalRows, options: .sortedKeys))

        let inventory = try String(contentsOf: directory.appendingPathComponent("inventory.csv"), encoding: .utf8)
        let sheets = try StudioWorkbookProjection.sheets(bundleData: input, inventoryCSV: inventory)
        let fields = try XCTUnwrap(sheets.first { $0.name == "Source Fields" })
        for record in records {
            let payload = record.columns["payload"]?.text
            XCTAssertTrue(fields.rows.contains { row in
                row.contains(.text(record.sourceTable)) && (payload.map { row.contains(.text($0)) } ?? true)
            }, "Workbook omitted fields for \(record.sourceTable) record \(record.recordID)")
        }
    }

    func testSchemaSixIndependentRawRowsSurviveImportAndReexport() throws {
        let row: [String: Any] = ["sourceTable": "daytime_events", "columns": [
            "revision_id": ["type": "text", "text": "event-revision"],
            "payload": ["type": "text", "text": "{\"unknown\":null,\"score\":0}"]]]
        let object: [String: Any] = ["schemaVersion": 6, "archiveScope": "manual_full_local_records", "independentRecordsIncluded": true, "dateGroups": [],
            "exportedAtUTC": "2026-09-30T12:00:00Z", "independentSourceRecords": [row],
            "medicationPresetLedger": ["schemaVersion": 1, "presetRevisions": [], "administrations": []]]
        let imported = try Importer().parseInsightsBundle(JSONSerialization.data(withJSONObject: object))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(imported)) as? [String: Any])
        XCTAssertEqual((restored["independentSourceRecords"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(restored["schemaVersion"] as? Int, 6)
        XCTAssertTrue(imported.sessions.isEmpty)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: restored["independentSourceRecords"]!, options: .sortedKeys),
                       try JSONSerialization.data(withJSONObject: [row], options: .sortedKeys))
        var invalid = object; invalid.removeValue(forKey: "independentSourceRecords")
        XCTAssertThrowsError(try Importer().parseInsightsBundle(JSONSerialization.data(withJSONObject: invalid)))
        invalid = object
        invalid["schemaVersion"] = 5
        XCTAssertThrowsError(try Importer().parseInsightsBundle(JSONSerialization.data(withJSONObject: invalid)))
        invalid.removeValue(forKey: "independentSourceRecords")
        invalid["archiveScope"] = NSNull()
        invalid["independentRecordsIncluded"] = NSNull()
        XCTAssertThrowsError(try Importer().parseInsightsBundle(JSONSerialization.data(withJSONObject: invalid)))
    }

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
