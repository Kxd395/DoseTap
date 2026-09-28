import XCTest
import DoseCore
import SQLite3
@testable import DoseTap

@MainActor
final class SupplyStorageTests: XCTestCase {
    func testQuantityRoundTripAllocationAndFailureDoNotCreateMedication() throws {
        let storage = EventStorage.inMemory(), now = Date(timeIntervalSince1970: 1_801_179_600)
        let bottle = UUID(), prep = UUID()
        var value = SupplyBackup()
        value.bottleStarts = [.init(id: bottle, openedAt: now, recordedAt: now)]
        try value.recordQuantity(.init(id: UUID(), bottleID: bottle, kind: .baseline, amountMg: 90_000,
            occurredAt: now, recordedAt: now, reason: "Reported"), now: now)
        try value.recordQuantity(.init(id: prep, bottleID: bottle, kind: .preparation, amountMg: 4_500,
            occurredAt: now, recordedAt: now, reason: "Prepared"), now: now)
        try storage.saveSupply(value)
        XCTAssertEqual(storage.countDoseEvents(), 0)
        try usageDose(storage, id: "actual-dose", at: now, type: "dose1")
        let evidence = try XCTUnwrap(storage.supplyDoseEvidence().first)
        try value.recordQuantity(.init(id: UUID(), bottleID: bottle, kind: .doseLink, amountMg: 0,
            occurredAt: now, recordedAt: now, reason: "Allocated", preparationID: prep, dose: evidence), now: now)
        try storage.saveSupply(value)
        XCTAssertEqual(try storage.loadSupply(), value)
        XCTAssertEqual(try storage.loadSupply().remainingBottleMg(bottle), 85_500)
        XCTAssertEqual(storage.countDoseEvents(), 1)
        sqlite3_exec(storage.db, "PRAGMA query_only = ON", nil, nil, nil)
        var failed = value
        try failed.recordQuantity(.init(id: UUID(), bottleID: bottle, kind: .baseline, amountMg: 40_000,
            occurredAt: now, recordedAt: now, reason: "Reconciled"), now: now)
        XCTAssertThrowsError(try storage.saveSupply(failed))
        XCTAssertEqual(try storage.loadSupply(), value)
    }

    func testQuantityDoseEvidenceExcludesAmbiguityAndDetectsCorrection() throws {
        let storage = EventStorage.inMemory(), now = Date(timeIntervalSince1970: 1_801_179_600)
        try usageDose(storage, id: "actual", at: now, type: "dose1")
        let snapshot = try XCTUnwrap(storage.supplyDoseEvidence().first)
        XCTAssertEqual(snapshot.eventID, "actual")
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp='2027-01-28T23:41:00Z' WHERE id='actual'", nil, nil, nil), SQLITE_OK)
        XCTAssertFalse(try storage.supplyDoseEvidence().contains(snapshot))
        try usageDose(storage, id: "duplicate", at: now, type: "dose1")
        XCTAssertTrue(try storage.supplyDoseEvidence().isEmpty)
        try usageDose(storage, id: "conflicting", at: now, type: "dose2", session: "other")
        XCTAssertTrue(try storage.supplyDoseEvidence().isEmpty)
    }

    func testReopenDatabasePreservesSupplyAndCorrectionHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("supply.sqlite").path
        var backup = SupplyBackup(reminder: SupplyReminderDocument(current:
            SupplyReminderEntry(year: 2035, month: 10, day: 4, hour: 9, minute: 0)))
        var corrected = backup.reminder!.current
        corrected.day = 5
        backup.reminder!.replace(with: corrected, at: Date())
        let now = Date(timeIntervalSince1970: 1_700_000_100), received = now.addingTimeInterval(-100)
        let receipt = UUID(), first = UUID(), mistaken = UUID()
        backup.bottleStarts = [SupplyBottleStart(openedAt: received.addingTimeInterval(-100), recordedAt: received)]
        try backup.receiveBottles(id: receipt, count: 3, receivedAt: received, recordedAt: now, now: now)
        try backup.startBottle(id: first, receiptID: receipt, openedAt: received, recordedAt: now, now: now)
        try backup.startBottle(id: mistaken, receiptID: receipt, openedAt: received.addingTimeInterval(1), recordedAt: now, now: now)
        try backup.voidBottleStart(id: mistaken, at: now, now: now)
        do { try EventStorage(dbPath: path).saveSupply(backup) }
        let reopened = try EventStorage(dbPath: path).loadSupply()
        XCTAssertEqual(reopened, backup)
        XCTAssertEqual(reopened.version, 2)
        XCTAssertEqual(reopened.activeBottleStart?.id, first)
        XCTAssertEqual(reopened.trackedUnopenedBottleCount, 2)
        XCTAssertEqual(reopened.bottleStarts.last?.voidedAt, now)
    }
    func testRoundTripRestoreAndResetPreserveIndependentRecords() throws {
        let storage = EventStorage.inMemory()
        var backup = SupplyBackup(reminder: SupplyReminderDocument(current:
            SupplyReminderEntry(year: 2026, month: 10, day: 4, hour: 9, minute: 0)))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        backup.bottleStarts = [SupplyBottleStart(openedAt: now, recordedAt: now)]
        try storage.saveSupply(backup)
        try storage.saveSupply(backup)
        XCTAssertEqual(try storage.loadSupply(), backup)
        backup.reminder = nil
        try storage.saveSupply(backup)
        XCTAssertEqual(try storage.loadSupply().bottleStarts.count, 1)
        storage.clearAllData()
        XCTAssertEqual(try storage.loadSupply(), SupplyBackup())
    }

    func testInvalidRestoreAndWriteFailurePreserveSavedSource() throws {
        let storage = EventStorage.inMemory()
        let original = SupplyBackup()
        try storage.saveSupply(original)
        var invalid = original
        invalid.version = 99
        XCTAssertThrowsError(try storage.saveSupply(invalid))
        XCTAssertEqual(try storage.loadSupply(), original)
        sqlite3_exec(storage.db, "PRAGMA query_only = ON", nil, nil, nil)
        XCTAssertThrowsError(try storage.saveSupply(original))
        XCTAssertEqual(try storage.loadSupply(), original)
    }

    func testSupplyUsageCountsSavedNightAcrossMidnightAndRecomputesCorrections() throws {
        let storage = EventStorage.inMemory(), start = Date(timeIntervalSince1970: 1_801_179_600)
        try usageDose(storage, id: "first", at: start, type: "dose1")
        try usageDose(storage, id: "second", at: start.addingTimeInterval(10_800), type: "dose2")
        try usageDose(storage, id: "skip", at: start, type: "dose2_skipped", day: "2027-01-29", session: "b")
        try usageDose(storage, id: "snooze", at: start, type: "snooze")
        try usageDose(storage, id: "audit", at: start, type: "history_correction")
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO medication_events (id,session_date,medication_id,dose_mg,taken_at_utc) VALUES ('daytime','2027-01-28','adderall',15,'2027-01-28T23:40:00Z')", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try storage.supplyUsage(since: start, through: start.addingTimeInterval(10_800)),
                       .init(recordedNights: 1, recordedDoses: 2, excludedRows: 0))
        XCTAssertEqual(sqlite3_exec(storage.db, "DELETE FROM dose_events WHERE id = 'first'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try storage.supplyUsage(since: start, through: start).recordedNights, 0)
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp = '2000-01-01T00:00:00Z' WHERE id = 'second'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try storage.supplyUsage(since: start, through: start.addingTimeInterval(10_800)).recordedNights, 0)
    }

    func testSupplyUsageExcludesConflictsOutsideRangeAndLegacyIdentity() throws {
        let storage = EventStorage.inMemory(), now = Date(timeIntervalSince1970: 1_801_179_600)
        try usageDose(storage, id: "in", at: now, type: "dose1")
        try usageDose(storage, id: "outside", at: now.addingTimeInterval(-100), type: "dose2", session: "other")
        try usageDose(storage, id: "legacy", at: now, type: "dose1", day: "2027-01-29", session: "")
        try usageDose(storage, id: "placeholder", at: now, type: "dose1", day: "2027-01-30", session: "2027-01-30")
        try usageDose(storage, id: "blank", at: now, type: "dose1", day: "2027-01-31", session: "   ")
        try usageDose(storage, id: "null", at: now, type: "dose1", day: "2027-02-01")
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET session_id = NULL WHERE id = 'null'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try storage.supplyUsage(since: now, through: now),
                       .init(recordedNights: 0, recordedDoses: 0, excludedRows: 5))
    }

    func testSupplyUsageDuplicatesNeedReviewAndExtrasRemainSeparate() throws {
        let storage = EventStorage.inMemory(), now = Date(timeIntervalSince1970: 1_801_179_600)
        try usageDose(storage, id: "a", at: now, type: "dose1")
        try usageDose(storage, id: "duplicate", at: now, type: "Dose 1")
        try usageDose(storage, id: "extra1", at: now, type: "extra_dose", day: "2027-01-29", session: "b")
        try usageDose(storage, id: "extra2", at: now, type: "extra_dose", day: "2027-01-29", session: "b")
        XCTAssertEqual(try storage.supplyUsage(since: now, through: now),
                       .init(recordedNights: 1, recordedDoses: 2, excludedRows: 2))
    }

    func testSupplyUsageChecksAuthoritativeSessionIdentities() throws {
        for table in ["sleep_sessions", "current_session"] {
            let storage = EventStorage.inMemory(), now = Date(timeIntervalSince1970: 1_801_179_600)
            try usageDose(storage, id: "a", at: now, type: "dose1")
            let extras = table == "sleep_sessions" ? (", start_utc", ", '2000-01-01T00:00:00Z'") : (", id", ", 1")
            XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO \(table) (session_id, session_date\(extras.0)) VALUES ('other','2027-01-29'\(extras.1))", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(try storage.supplyUsage(since: now, through: now).recordedNights, 1)
            XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE \(table) SET session_date = '2027-01-28' WHERE session_id = 'other'", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(try storage.supplyUsage(since: now, through: now), .init(recordedNights: 0, recordedDoses: 0, excludedRows: 1))
            XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE \(table) SET session_id = 'a'", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(try storage.supplyUsage(since: now, through: now).recordedNights, 1)
            XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE \(table) SET session_date = '2027-01-29'", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(try storage.supplyUsage(since: now, through: now), .init(recordedNights: 0, recordedDoses: 0, excludedRows: 1))
        }
    }

    func testSupplyUsageExcludesOneSessionIdentityAssignedToMultipleDates() throws {
        let storage = EventStorage.inMemory(), now = Date(timeIntervalSince1970: 1_801_179_600)
        try usageDose(storage, id: "first", at: now, type: "dose1")
        try usageDose(storage, id: "otherDate", at: now.addingTimeInterval(-100), type: "dose1", day: "2027-01-29")
        XCTAssertEqual(try storage.supplyUsage(since: now, through: now), .init(recordedNights: 0, recordedDoses: 0, excludedRows: 1))
        XCTAssertEqual(try storage.supplyUsage(since: now.addingTimeInterval(-100), through: now), .init(recordedNights: 0, recordedDoses: 0, excludedRows: 2))
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET session_id = 'b' WHERE id = 'otherDate'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try storage.supplyUsage(since: now.addingTimeInterval(-100), through: now), .init(recordedNights: 2, recordedDoses: 2, excludedRows: 0))
    }

    func testSupplyUsageReadFailuresNeverBecomeZero() throws {
        let storage = EventStorage.inMemory(), now = Date(timeIntervalSince1970: 1_801_179_600)
        XCTAssertThrowsError(try storage.supplyUsage(since: now, through: now.addingTimeInterval(-1)))
        try usageDose(storage, id: "bad", at: now, type: "dose1")
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp = 'invalid'", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try storage.supplyUsage(since: now, through: now))
        XCTAssertEqual(sqlite3_exec(storage.db, "DROP TABLE dose_events", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try storage.supplyUsage(since: now, through: now))
    }

    func testBottleNoticeRetainsKnownStockWhenUsageFailsAndClearsAfterReceipt() throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage)
        let opened = ISO8601DateFormatter().date(from: "2027-01-28T22:00:00Z")!
        let now = opened.addingTimeInterval(3 * 86_400), receipt = UUID()
        var supply = SupplyBackup()
        try supply.receiveBottles(id: receipt, count: 1, receivedAt: opened, recordedAt: opened, now: now)
        try supply.startBottle(id: UUID(), receiptID: receipt, openedAt: opened, recordedAt: opened, now: now)
        try repo.saveSupply(supply)
        for index in 0..<3 {
            try usageDose(storage, id: "night-\(index)", at: opened.addingTimeInterval(Double(index * 86_400 + 3_600)),
                          type: "dose1", day: "2027-01-\(28 + index)", session: "session-\(index)")
        }
        let model = BottleSupplyModel(repository: repo)
        model.refresh(now: now)
        XCTAssertEqual(model.usage?.recordedNights, 3)
        XCTAssertTrue(model.refillNotice?.hasPrefix("Third recorded night") == true)
        XCTAssertNil(model.error)
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp = 'invalid' WHERE id = 'night-0'", nil, nil, nil), SQLITE_OK)
        model.refresh(now: now)
        XCTAssertEqual(model.supply, supply)
        XCTAssertNil(model.usage)
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.refillNotice?.hasPrefix("Last tracked bottle") == true)
        try supply.receiveBottles(id: UUID(), count: 3, receivedAt: now, recordedAt: now, now: now)
        try repo.saveSupply(supply)
        model.refresh(now: now)
        XCTAssertEqual(model.supply?.trackedUnopenedBottleCount, 3)
        XCTAssertNil(model.refillNotice)
        XCTAssertNil(model.usage)
        XCTAssertNotNil(model.error)
    }

    private func usageDose(_ storage: EventStorage, id: String, at date: Date, type: String,
                           day: String = "2027-01-28", session: String = "a") throws {
        let stamp = ISO8601DateFormatter().string(from: date)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO dose_events (id,event_type,timestamp,session_date,session_id) VALUES ('\(id)','\(type)','\(stamp)','\(day)','\(session)')", nil, nil, nil), SQLITE_OK)
    }
}
