import XCTest
@testable import DoseCore

final class SupplyReminderTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let ny = TimeZone(identifier: "America/New_York")!
    private let iso = ISO8601DateFormatter()

    func testReceivedDateAdds21CalendarDaysAcrossMonthAndDST() {
        var entry = SupplyReminderEntry(year: 2026, month: 2, day: 20, hour: 9, minute: 0)
        entry.mode = .receivedDate
        XCTAssertEqual(entry.fireDate(in: ny), iso.date(from: "2026-03-13T13:00:00Z"))
        XCTAssertEqual(entry.day, 20)
    }

    func testDirectAndCycleEndDatesRemainDistinct() throws {
        var entry = SupplyReminderEntry(year: 2026, month: 10, day: 4, hour: 9, minute: 30)
        XCTAssertEqual(entry.fireDate(in: utc), iso.date(from: "2026-10-04T09:30:00Z"))
        entry.mode = .cycleEnd
        entry.leadDays = 7
        XCTAssertEqual(entry.fireDate(in: utc), iso.date(from: "2026-09-27T09:30:00Z"))
        XCTAssertEqual(entry.day, 4)
    }

    func testWallClockFollowsTimezoneWithoutChangingSource() {
        let entry = SupplyReminderEntry(year: 2026, month: 10, day: 4, hour: 9, minute: 30)
        XCTAssertEqual(entry.fireDate(in: ny), iso.date(from: "2026-10-04T13:30:00Z"))
        XCTAssertEqual(entry.fireDate(in: utc), iso.date(from: "2026-10-04T09:30:00Z"))
    }

    func testDSTGapRequiresCorrectionAndFoldUsesFirstOccurrence() {
        let gap = SupplyReminderEntry(year: 2026, month: 3, day: 8, hour: 2, minute: 30)
        XCTAssertNil(gap.fireDate(in: ny))
        let fold = SupplyReminderEntry(year: 2026, month: 11, day: 1, hour: 1, minute: 30)
        XCTAssertEqual(fold.fireDate(in: ny), iso.date(from: "2026-11-01T05:30:00Z"))
    }

    func testInvalidCalendarDateAndLeadTimeAreRejected() {
        var entry = SupplyReminderEntry(year: 2026, month: 2, day: 30, hour: 9, minute: 0)
        XCTAssertFalse(entry.isValid)
        entry.day = 28
        entry.leadDays = -1
        XCTAssertFalse(entry.isValid)
        entry.leadDays = 0
        XCTAssertTrue(entry.isValid)
    }

    func testCorrectionAndBackupPreserveExactPreviousSource() throws {
        let original = SupplyReminderEntry(year: 2026, month: 10, day: 4, hour: 9, minute: 30)
        var document = SupplyReminderDocument(current: original)
        var changed = original
        changed.day = 5
        document.replace(with: changed, at: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(document.history, [original])
        XCTAssertNotEqual(document.current.revision, original.revision)
        let restored = try JSONDecoder().decode(SupplyReminderDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(restored, document)
        XCTAssertTrue(restored.isValid)
        document.version = 2
        XCTAssertFalse(document.isValid)
    }

    func testBackupFileDecodeEnforcesActualByteLimit() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SupplyReminderTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let value = SupplyBackup()
        let encoded = try JSONEncoder().encode(value)
        try encoded.write(to: url)

        XCTAssertEqual(
            try SupplyBackupFileCodec.decode(contentsOf: url, maximumBytes: encoded.count),
            value
        )
        XCTAssertThrowsError(
            try SupplyBackupFileCodec.decode(contentsOf: url, maximumBytes: encoded.count - 1)
        ) { error in
            XCTAssertEqual(error as? SupplyBackupFileError, .tooLarge)
        }
    }

    func testBackupFileDecodeRejectsOneBytePastDefaultLimitBeforeDecoding() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SupplyReminderTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0x20, count: SupplyBackupFileCodec.maximumBytes + 1).write(to: url)

        XCTAssertThrowsError(try SupplyBackupFileCodec.decode(contentsOf: url)) { error in
            XCTAssertEqual(error as? SupplyBackupFileError, .tooLarge)
        }
    }

    func testBackupValidationCapsImportedCollectionCounts() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var value = SupplyBackup()
        value.bottleStarts = (0...SupplyBackup.maximumRecordCount).map { offset in
            SupplyBottleStart(openedAt: date, recordedAt: date.addingTimeInterval(TimeInterval(offset)))
        }
        XCTAssertFalse(value.isValid)

        var document = SupplyReminderDocument(
            current: SupplyReminderEntry(year: 2026, month: 9, day: 5, hour: 9, minute: 0)
        )
        document.history = (0...SupplyBackup.maximumRecordCount).map { _ in
            var entry = document.current
            entry.revision = UUID()
            return entry
        }
        XCTAssertFalse(document.isValid)
    }
}
