import DoseCore
import Foundation
import SQLite3
import XCTest
@testable import DoseTap

@MainActor
final class Build108UpgradeExportTests: XCTestCase {
    func testBuild108ReminderLedgerPlansWithoutChangingStoredRows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try createBuild108Database(at: url.path)
        let storage = EventStorage(dbPath: url.path)
        let rows = try storage.exportIndependentSourceRecords(in: "daytime_prompt_state")
        XCTAssertEqual(rows.count, 1)
        let payload = try XCTUnwrap(rows.first?.columns["payload"]?.text)
        var ledger = try DaytimePromptLedger.decodePayload(Data(payload.utf8))
        XCTAssertTrue(ledger.enabled)
        XCTAssertNil(ledger.current?.rule)
        XCTAssertEqual(ledger.current?.hour, 14)
        XCTAssertEqual(ledger.current?.timeZone, "UTC")
        XCTAssertTrue(ledger.prompts.isEmpty)

        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let planned = ledger.prepareHorizon(at: now)
        XCTAssertEqual(planned.count, 7)
        XCTAssertEqual(try DaytimePromptLedger.decodePayload(ledger.encodedPayload()), ledger)
        XCTAssertEqual(try storage.exportIndependentSourceRecords(in: "daytime_prompt_state"), rows)
    }

    func testBuild108ReminderChangePreservesOtherCollectionsAndUnknownFields() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try createBuild108Database(at: url.path)
        let storage = EventStorage(dbPath: url.path)
        let repo = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler())
        let table = "daytime_prompt_state"
        let others = try storage.exportIndependentSourceRecords().filter { $0.sourceTable != table }
        let original = try repo.daytimePrompts()
        var planned = original
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(planned.prepareHorizon(at: now).count, 7)
        try repo.saveDaytimePrompts(planned, replacing: original)
        let reopened = EventStorage(dbPath: url.path)
        XCTAssertEqual(try reopened.daytimePrompts(), planned)
        XCTAssertEqual(try reopened.exportIndependentSourceRecords().filter { $0.sourceTable != table }, others)
        XCTAssertTrue(try reopened.nativeDaytimeTables().isEmpty)
        XCTAssertFalse(reopened.clearAllData())

        XCTAssertEqual(sqlite3_exec(storage.db, """
            UPDATE daytime_prompt_state SET payload = json_set(payload, '$.schedules[0].futureOption', 42)
            """, nil, nil, nil), SQLITE_OK)
        let futureRows = try storage.exportIndependentSourceRecords(in: table)
        XCTAssertEqual(try repo.daytimePrompts(), planned)
        var paused = planned
        paused.enabled = false
        XCTAssertThrowsError(try repo.saveDaytimePrompts(paused, replacing: planned))
        XCTAssertEqual(try storage.exportIndependentSourceRecords(in: table), futureRows)
    }

    func testManualAndScheduledExportsFromBuild108Database() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manualFolder = root.appendingPathComponent("manual")
        try FileManager.default.createDirectory(at: manualFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let path = root.appendingPathComponent("upgrade.sqlite").path
        try createBuild108Database(at: path)
        let storage = EventStorage(dbPath: path)
        XCTAssertNil(storage.databaseInitializationFailure)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let repository = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler(),
                                           clock: { now }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
        XCTAssertEqual(repository.dose1Time, now)

        let exporter = StudioBundleExporter()
        try await exporter.writeStudioExportBundle(using: repository, to: manualFolder)
        let bundle = try Data(contentsOf: manualFolder.appendingPathComponent("insights_bundle.json"))
        let rootObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bundle) as? [String: Any])
        XCTAssertEqual(rootObject["schemaVersion"] as? Int, 6)
        XCTAssertEqual(rootObject["archiveScope"] as? String, "manual_full_local_records")
        let records = try XCTUnwrap(rootObject["independentSourceRecords"] as? [[String: Any]])
        XCTAssertEqual(records.count, 9)
        XCTAssertEqual(Set(records.compactMap { $0["sourceTable"] as? String }).count, 8)
        let groups = try XCTUnwrap(rootObject["dateGroups"] as? [[String: Any]])
        XCTAssertEqual(groups.compactMap { $0["sessionDate"] as? String }, ["2026-09-20"])

        let manual = try exporter.archiveExportDirectory(manualFolder)
        let workbook = root.appendingPathComponent("review.xlsx")
        try ExcelWorkbookFileExporter.write(from: manualFolder, to: workbook)
        let scheduled = try exporter.writeScheduledArchive(using: repository, to: root)
        for (url, name) in [(manual, "build108-upgrade-manual.zip"), (workbook, "build108-upgrade.xlsx"),
                            (scheduled, "build108-upgrade-scheduled.zip")] {
            let attachment = XCTAttachment(contentsOfFile: url)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testDaytimeCorrectionAppendsOnBuild108AndPreservesOriginalArchiveRows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try createBuild108Database(at: url.path)
        let now = Date(timeIntervalSince1970: 1_790_000_100)
        let originalRows: [StoredExportSourceRecord]
        let correction: DaytimeCheckIn
        do {
            let storage = EventStorage(dbPath: url.path)
            let repo = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler(), clock: { now })
            originalRows = try repo.exportIndependentSourceRecords()
            let ledger = try repo.daytimeCheckIns()
            let original = try XCTUnwrap(ledger.current.first)
            XCTAssertEqual(ledger.revisions.first?.response, 0)
            XCTAssertEqual(original.status, .unsure)
            correction = try original.corrected(response: 5, status: .answered, reason: "Reviewed", recordedAt: now)
            try repo.saveDaytimeCheckIn(correction)
            XCTAssertTrue(try storage.nativeDaytimeTables().isEmpty)
            XCTAssertFalse(storage.clearAllData())
        }
        let reopened = EventStorage(dbPath: url.path)
        XCTAssertEqual(try reopened.daytimeCheckIns().current, [correction])
        let rows = try reopened.exportIndependentSourceRecords()
        XCTAssertEqual(rows.count, originalRows.count + 1)
        XCTAssertEqual(rows.filter { $0.columns["revision_id"]?.text != correction.revisionID.uuidString }, originalRows)
    }

    private func createBuild108Database(at path: String) throws {
        let resource = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Build108SyntheticUpgrade",
                                                                withExtension: "sql"))
        let dump = try String(contentsOf: resource, encoding: .utf8)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &connection), SQLITE_OK)
        let db = try XCTUnwrap(connection)
        defer { sqlite3_close(db) }
        let result = sqlite3_exec(db, dump, nil, nil, nil)
        XCTAssertEqual(result, SQLITE_OK, String(cString: sqlite3_errmsg(db)))
    }
}
