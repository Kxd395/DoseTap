import Foundation
import SQLite3
import XCTest
@testable import DoseTap

@MainActor
final class Build108UpgradeExportTests: XCTestCase {
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
