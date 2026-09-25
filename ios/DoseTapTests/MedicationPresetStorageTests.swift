import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class MedicationPresetStorageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func preset(previous: MedicationPresetRevision? = nil, name: String = "Synthetic label") throws -> MedicationPresetRevision {
        try MedicationPresetRevision(presetID: previous?.presetID ?? UUID(), revisionID: UUID(),
            supersedesRevisionID: previous?.revisionID, labelName: name, ingredient: "Synthetic ingredient",
            releaseProfile: .extendedRelease,
            components: [MedicationPresetComponent(id: UUID(), form: .tablet,
                strengthMilligrams: Decimal(string: "1.12345678901234567890123456789")!, unitCount: 1)],
            instructions: "Entered label instructions", schedule: .scheduled,
            effectiveFrom: now, effectiveUntil: nil, recordedAt: now)
    }
    func actual(_ preset: MedicationPresetRevision) throws -> ConfirmedMedicationAdministration {
        try ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: preset.components,
            occurredAt: nil, precision: .unknown, timeZoneIdentifier: nil, utcOffsetSeconds: nil,
            confirmedAt: now, recordedAt: now)
    }
    func repo(_ storage: EventStorage) -> SessionRepository {
        SessionRepository(storage: storage, clock: { self.now }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
    }
    func testRestartRetainsIndependentUnknownTimeAndExactAmounts() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let storage = EventStorage(dbPath: path), repository = repo(storage)
        let p = try preset(), a = try actual(p)
        try repository.saveMedicationPresetRevision(p)
        try repository.saveConfirmedMedicationAdministration(a)
        XCTAssertNil(repository.dose1Time)
        let before = try repository.medicationPresetExportSnapshot()
        XCTAssertEqual(try repo(EventStorage(dbPath: path)).medicationPresetExportSnapshot(), before)
        XCTAssertEqual(try MedicationPresetExportSnapshot.decodeAdministration(before.administrations[0]), a)
        XCTAssertTrue(before.presetRevisions[0].contains("1.12345678901234567890123456789"))
        XCTAssertTrue(try repository.sessionDatesForExport().isEmpty)
    }
    func testIdempotentRetriesAndStaleRevisionBranchRejected() throws {
        let repository = repo(EventStorage(dbPath: ":memory:")), p = try preset()
        try repository.saveMedicationPresetRevision(p)
        try repository.saveMedicationPresetRevision(p)
        let a = try actual(p)
        try repository.saveConfirmedMedicationAdministration(a)
        try repository.saveConfirmedMedicationAdministration(a)
        try repository.saveMedicationPresetRevision(preset(previous: p, name: "New label"))
        XCTAssertThrowsError(try repository.saveMedicationPresetRevision(preset(previous: p)))
        let snapshot = try repository.medicationPresetExportSnapshot()
        XCTAssertEqual(snapshot.presetRevisions.count, 2)
        XCTAssertEqual(snapshot.administrations.count, 1)
        XCTAssertEqual(try MedicationPresetExportSnapshot.decodeAdministration(snapshot.administrations[0]).preset, p)
    }
    func testMissingOrMismatchedRevisionCannotCreateAdministration() throws {
        let repository = repo(EventStorage(dbPath: ":memory:")), p = try preset()
        XCTAssertThrowsError(try repository.saveConfirmedMedicationAdministration(actual(p)))
        try repository.saveMedicationPresetRevision(p)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        object["labelName"] = "Conflicting same revision"
        let conflicting = try JSONDecoder().decode(MedicationPresetRevision.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try repository.saveMedicationPresetRevision(conflicting))
        XCTAssertThrowsError(try repository.saveConfirmedMedicationAdministration(actual(conflicting)))
        XCTAssertTrue(try repository.medicationPresetExportSnapshot().administrations.isEmpty)
    }
    func testInsertAndCommitFailureRollBackAndRetry() throws {
        for point: MedicationStorageFaultPoint in [.insert, .commit] {
            let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage), p = try preset()
            storage.medicationFaultInjector = { $0 == point ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Synthetic") : nil }
            XCTAssertThrowsError(try repository.saveMedicationPresetRevision(p))
            XCTAssertTrue(try repository.medicationPresetExportSnapshot().presetRevisions.isEmpty)
            storage.medicationFaultInjector = nil
            try repository.saveMedicationPresetRevision(p)
            let a = try actual(p)
            storage.medicationFaultInjector = { $0 == point ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Synthetic") : nil }
            XCTAssertThrowsError(try repository.saveConfirmedMedicationAdministration(a))
            XCTAssertTrue(try repository.medicationPresetExportSnapshot().administrations.isEmpty)
            storage.medicationFaultInjector = nil
            try repository.saveConfirmedMedicationAdministration(a)
            XCTAssertEqual(try repository.medicationPresetExportSnapshot().administrations.count, 1)
        }
    }
    func testMalformedOrMismatchedIndexFailsExportAndSubsequentWrites() throws {
        for sql in ["UPDATE medication_preset_revisions SET payload='bad'",
                    "UPDATE medication_preset_revisions SET recorded_at_utc='wrong'",
                    "UPDATE confirmed_medication_administrations SET occurred_at_utc='invented'"] {
            let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage), p = try preset()
            try repository.saveMedicationPresetRevision(p)
            try repository.saveConfirmedMedicationAdministration(actual(p))
            XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
            XCTAssertThrowsError(try repository.medicationPresetExportSnapshot())
            XCTAssertThrowsError(try repository.saveMedicationPresetRevision(preset()))
        }
    }
    func testNightDeletionPreservesLedgerButClearAllRemovesIt() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage), p = try preset()
        XCTAssertTrue(repository.setDose1Time(now.addingTimeInterval(-3600)).isCommitted)
        let identity = repository.activeSessionId
        try repository.saveMedicationPresetRevision(p)
        try repository.saveConfirmedMedicationAdministration(actual(p))
        XCTAssertEqual(repository.activeSessionId, identity)
        XCTAssertNil(repository.dose2Time)
        let before = try repository.medicationPresetExportSnapshot()
        repository.clearTonight()
        storage.clearOldData(olderThanDays: 1)
        XCTAssertEqual(try repository.medicationPresetExportSnapshot(), before)
        storage.clearAllData()
        XCTAssertTrue(try repository.medicationPresetExportSnapshot().presetRevisions.isEmpty)
        XCTAssertTrue(try repository.medicationPresetExportSnapshot().administrations.isEmpty)
    }
}
