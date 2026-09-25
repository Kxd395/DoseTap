import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class MedicationCaptureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func repository(_ storage: EventStorage) -> SessionRepository {
        SessionRepository(storage: storage, clock: { self.now }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
    }
    func testIndependentCaptureSurvivesReopenAndPreservesRecordingTime() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let storage = EventStorage(dbPath: path), repo = repository(storage)
        let occurrence = now.addingTimeInterval(-3600)
        XCTAssertFalse(try repo.logMedicationEntry(entryID: "stable", medicationId: "adderall_xr", doseMg: 20, takenAt: occurrence).isDuplicate)
        XCTAssertNil(repo.dose1Time)
        let reopened = EventStorage(dbPath: path)
        let row = try XCTUnwrap(reopened.medicationCaptureRows(column: "id", value: "stable").first)
        XCTAssertNil(row.sessionId)
        XCTAssertEqual(row.takenAtUTC, occurrence)
        XCTAssertEqual(row.createdAt, now)
        XCTAssertEqual(row.formulation, "xr")
        XCTAssertEqual(try reopened.medicationExportRecords(sessionDate: row.sessionDate).count, 1)
    }
    func testStableRetryAndConflictingReuse() throws {
        let storage = EventStorage(dbPath: ":memory:"), repo = repository(storage)
        for _ in 0..<2 {
            XCTAssertFalse(try repo.logMedicationEntry(entryID: "retry", medicationId: "modafinil", doseMg: 100, takenAt: now).isDuplicate)
        }
        XCTAssertEqual(try storage.medicationCaptureRows(column: "id", value: "retry").count, 1)
        XCTAssertThrowsError(try repo.logMedicationEntry(entryID: "retry", medicationId: "modafinil", doseMg: 200, takenAt: now))
    }
    func testRejectsFutureInvalidAmountAndUnknownMedication() throws {
        let repo = repository(EventStorage(dbPath: ":memory:"))
        for amount in [0, -1, Int(Int32.max) + 1] {
            XCTAssertThrowsError(try repo.logMedicationEntry(medicationId: "adderall_ir", doseMg: amount, takenAt: now))
        }
        XCTAssertThrowsError(try repo.logMedicationEntry(medicationId: "unknown", doseMg: 10, takenAt: now))
        XCTAssertThrowsError(try repo.logMedicationEntry(medicationId: "adderall_ir", doseMg: 10, takenAt: now.addingTimeInterval(1)))
        XCTAssertThrowsError(try repo.logMedicationEntry(medicationId: "adderall_ir", doseMg: 10, takenAt: Date(timeIntervalSince1970: .infinity)))
    }
    func testDuplicateAcrossDateBoundaryAndStaleConsent() throws {
        let storage = EventStorage(dbPath: ":memory:"), repo = repository(storage)
        let prior = now.addingTimeInterval(-60)
        let seed = StoredMedicationEntry(id: "prior", sessionId: "legacy", sessionDate: "different-date",
            medicationId: "adderall_ir", doseMg: 10, takenAtUTC: prior, createdAt: prior)
        XCTAssertTrue(storage.insertMedicationEvent(seed))
        XCTAssertTrue(try repo.logMedicationEntry(entryID: "second", medicationId: "adderall_ir", doseMg: 10, takenAt: now).isDuplicate)
        let reviewed = try repo.medicationDuplicateReview(medicationId: "adderall_ir", takenAt: now).tokens
        XCTAssertEqual(reviewed.count, 1)
        XCTAssertFalse(try repo.logMedicationEntry(entryID: "second", medicationId: "adderall_ir", doseMg: 10, takenAt: now,
            confirmedDuplicate: true, reviewedDuplicateTokens: reviewed).isDuplicate)
        XCTAssertTrue(try repo.logMedicationEntry(entryID: "third", medicationId: "adderall_ir", doseMg: 10, takenAt: now,
            confirmedDuplicate: true, reviewedDuplicateTokens: reviewed).isDuplicate)
        XCTAssertEqual(try storage.medicationCaptureRows(column: "medication_id", value: "adderall_ir").count, 2)
        XCTAssertEqual(try storage.medicationCaptureRows(column: "id", value: "prior").first?.sessionId, "legacy")
    }
    func testWriteFailureCanRetrySameIDAndReadFailureDoesNotWrite() throws {
        let storage = EventStorage(dbPath: ":memory:"), repo = repository(storage)
        storage.medicationFaultInjector = { point in point == .insert ? MedicationStorageInjectedFailure(code: .diskFull, sqliteCode: 13, detail: "Test") : nil }
        XCTAssertThrowsError(try repo.logMedicationEntry(entryID: "retry", medicationId: "modafinil", doseMg: 100, takenAt: now))
        XCTAssertTrue(try storage.medicationCaptureRows(column: "id", value: "retry").isEmpty)
        storage.medicationFaultInjector = nil
        XCTAssertFalse(try repo.logMedicationEntry(entryID: "retry", medicationId: "modafinil", doseMg: 100, takenAt: now).isDuplicate)
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE medication_events SET taken_at_utc = 'bad'", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try repo.medicationDuplicateReview(medicationId: "modafinil", takenAt: now).tokens)
        XCTAssertThrowsError(try repo.logMedicationEntry(entryID: "new", medicationId: "modafinil", doseMg: 100, takenAt: now))
    }
    func testCommitFailureRollsBackAndChangedDuplicateContentNeedsReview() throws {
        let storage = EventStorage(dbPath: ":memory:"), repo = repository(storage)
        storage.medicationFaultInjector = { point in point == .commit ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Test") : nil }
        XCTAssertThrowsError(try repo.logMedicationEntry(entryID: "original", medicationId: "modafinil", doseMg: 100, takenAt: now))
        XCTAssertTrue(try storage.medicationCaptureRows(column: "id", value: "original").isEmpty)
        storage.medicationFaultInjector = nil
        _ = try repo.logMedicationEntry(entryID: "original", medicationId: "modafinil", doseMg: 100, takenAt: now)
        let review = try repo.medicationDuplicateReview(medicationId: "modafinil", takenAt: now)
        XCTAssertEqual(review.entries.first?.doseMg, 100)
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE medication_events SET dose_mg = 200 WHERE id = 'original'", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(try repo.logMedicationEntry(entryID: "additional", medicationId: "modafinil", doseMg: 100, takenAt: now,
            confirmedDuplicate: true, reviewedDuplicateTokens: review.tokens).isDuplicate)
        XCTAssertTrue(try storage.medicationCaptureRows(column: "id", value: "additional").isEmpty)
    }
    func testIndependentCaptureLeavesActiveNightUntouched() throws {
        let storage = EventStorage(dbPath: ":memory:"), repo = repository(storage)
        XCTAssertTrue(repo.setDose1Time(now.addingTimeInterval(-3600)).isCommitted)
        let first = repo.dose1Time, identity = repo.activeSessionId
        _ = try repo.logMedicationEntry(entryID: "daytime", medicationId: "adderall_xr", doseMg: 20, takenAt: now)
        XCTAssertEqual(repo.dose1Time, first)
        XCTAssertEqual(repo.activeSessionId, identity)
        XCTAssertNil(repo.dose2Time)
        XCTAssertNil(try storage.medicationCaptureRows(column: "id", value: "daytime").first?.sessionId)
    }

    func testNightDeletionAndResetPreserveIndependentMedicationAndDoNotSyncItsDeletion() throws {
        for action in ["history", "reset", "sync"] {
            let storage = EventStorage(dbPath: ":memory:"), repo = repository(storage)
            XCTAssertTrue(repo.setDose1Time(now.addingTimeInterval(-3600)).isCommitted)
            _ = try repo.logMedicationEntry(entryID: "independent", medicationId: "adderall_xr", doseMg: 20, takenAt: now)
            let original = try XCTUnwrap(storage.medicationCaptureRows(column: "id", value: "independent").first)
            XCTAssertEqual(original.sessionDate, repo.activeSessionDate)
            let linked = StoredMedicationEntry(id: "legacy-linked", sessionId: "legacy-night", sessionDate: original.sessionDate,
                medicationId: "modafinil", doseMg: 100, takenAtUTC: now, createdAt: now)
            XCTAssertTrue(storage.insertMedicationEvent(linked))
            switch action {
            case "history": repo.deleteSession(sessionDate: original.sessionDate)
            case "reset": repo.clearTonight()
            default: repo.deleteSessionFromSync(sessionDate: original.sessionDate)
            }
            let remaining = try XCTUnwrap(storage.medicationCaptureRows(column: "id", value: "independent").first)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            XCTAssertEqual(try encoder.encode(remaining), try encoder.encode(original))
            XCTAssertTrue(try storage.medicationCaptureRows(column: "id", value: "legacy-linked").isEmpty)
            XCTAssertEqual(try storage.medicationExportRecords(sessionDate: original.sessionDate).count, 1)
            let tombstones = storage.fetchCloudKitTombstones().filter { $0.recordType == "DoseTapMedicationEvent" }
            XCTAssertEqual(Set(tombstones.map(\.recordName)), action == "sync" ? [] : ["legacy-linked"])
            storage.clearAllData()
            XCTAssertTrue(try storage.medicationCaptureRows(column: "id", value: "independent").isEmpty,
                          "Explicit Clear All Data still removes independent records")
        }
    }

}
