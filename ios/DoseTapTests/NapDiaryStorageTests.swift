import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class NapDiaryStorageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func document() -> NapDiaryDocument {
        var value = NapDiaryDocument()
        value.episodes = [.init(id: "synthetic-nap", day: NapEpisode.day(now, "UTC"), timeZoneID: "UTC",
            start: now.addingTimeInterval(-3600), end: now, estimatedSleepMinutes: 20, recordedAt: now)]
        return value
    }
    func execute(_ sql: String, _ storage: EventStorage) {
        XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
    }
    func testDurableReopenAndStaleRevisionDoesNotReplaceHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("naps.sqlite").path
        let storage = EventStorage(dbPath: path), original = document()
        try storage.saveNapDiary(original, expectedRevision: nil)
        let reopened = EventStorage(dbPath: path)
        XCTAssertEqual(try reopened.napDiary(), original)
        var correction = original
        var episode = original.episodes[0]; episode.revision = UUID(); episode.predecessor = original.episodes[0].revision
        episode.reason = "Corrected estimate"; episode.estimatedSleepMinutes = 10
        correction.episodes.append(episode); correction.revision = UUID()
        try reopened.saveNapDiary(correction, expectedRevision: original.revision)
        XCTAssertThrowsError(try storage.saveNapDiary(original, expectedRevision: original.revision))
        XCTAssertEqual(try storage.napDiary(), correction)
    }
    func testAppendOnlyGuardAndRollbackAfterFailedWrite() throws {
        let storage = EventStorage.inMemory(), original = document()
        try storage.saveNapDiary(original, expectedRevision: nil)
        var replaced = original; replaced.episodes.removeAll(); replaced.revision = UUID()
        XCTAssertThrowsError(try storage.saveNapDiary(replaced, expectedRevision: original.revision))
        execute("CREATE TRIGGER fail_nap_write BEFORE UPDATE ON nap_diary BEGIN SELECT RAISE(ABORT,'synthetic failure'); END", storage)
        var next = original; next.revision = UUID()
        XCTAssertThrowsError(try storage.saveNapDiary(next, expectedRevision: original.revision))
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
        XCTAssertEqual(try storage.napDiary(), original)
        execute("DROP TRIGGER fail_nap_write", storage)
        try storage.saveNapDiary(next, expectedRevision: original.revision)
        XCTAssertEqual(try storage.napDiary(), next)
    }
    func testRawSnapshotAndClearAllIncludeIndependentLedger() throws {
        let storage = EventStorage.inMemory(), value = document()
        try storage.saveNapDiary(value, expectedRevision: nil)
        let snapshot = try storage.dashboardSnapshot(sourceID: "synthetic", sequence: 1, capturedAt: now)
        let section = try XCTUnwrap(snapshot.sections.first { $0.dataset == .daytimeDiary })
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(section.rows)) as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { $0["sourceTable"] as? String == "nap_diary" })
        let columns = try XCTUnwrap(row["columns"] as? [String: [String: Any]])
        let payload = try XCTUnwrap(columns["payload"]?["text"] as? String)
        XCTAssertEqual(try JSONDecoder().decode(NapDiaryDocument.self, from: Data(payload.utf8)), value)
        XCTAssertTrue(try storage.dashboardLocalSessions().isEmpty)
        storage.clearAllData()
        XCTAssertNil(try storage.napDiary())
    }
    func testCorruptOrUnreadableStorageDoesNotBecomeAnEmptyDiary() throws {
        let storage = EventStorage.inMemory()
        execute("INSERT INTO nap_diary(id,payload) VALUES(1,'invalid JSON')", storage)
        XCTAssertThrowsError(try storage.napDiary())
        XCTAssertThrowsError(try storage.saveNapDiary(document(), expectedRevision: nil))
        execute("DROP TABLE nap_diary", storage)
        XCTAssertThrowsError(try storage.napDiary())
    }
    func testEmbeddedNULTrailingGarbageAndNonTextPayloadAreRejected() throws {
        let storage = EventStorage.inMemory(), value = document()
        try storage.saveNapDiary(value, expectedRevision: nil)
        execute("UPDATE nap_diary SET payload = payload || char(0) || 'corrupt'", storage)
        XCTAssertThrowsError(try storage.napDiary())
        execute("UPDATE nap_diary SET payload = X'7B7D'", storage)
        XCTAssertThrowsError(try storage.napDiary())
    }

    func testReviewedTimerKeepsOriginalZoneAfterTravelAndDetectsSourceChange() throws {
        let storage = EventStorage.inMemory(), repository = SessionRepository(storage: storage)
        let asOf = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-02T00:00:00Z"))
        execute("""
        INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('nap-session','2026-08-31','2026-09-01T01:00:00Z');
        INSERT INTO sleep_events(id,event_type,timestamp,session_date,session_id) VALUES('start','nap_start','2026-09-01T01:00:00Z','2026-08-31','nap-session'),('end','nap_end','2026-09-01T01:30:00Z','2026-08-31','nap-session');
        """, storage)
        let source = try XCTUnwrap(repository.napTimerEpisodes(asOf: asOf, timeZoneID: "America/New_York").first)
        var reviewed = source; reviewed.sourceEvidenceKey = source.evidenceKey; reviewed.estimatedSleepMinutes = 20
        var document = NapDiaryDocument(); document.episodes = [reviewed]
        try storage.saveNapDiary(document, expectedRevision: nil)
        let traveled = try repository.reviewedNapEpisodes(asOf: asOf, defaultTimeZoneID: "UTC")
        XCTAssertThrowsError(try repository.reviewedNapEpisodes(asOf: asOf, defaultTimeZoneID: "Invalid/Zone"))
        XCTAssertThrowsError(try repository.reviewedNapEpisodes(asOf: Date(timeIntervalSince1970: .nan), defaultTimeZoneID: "UTC"))
        XCTAssertEqual(traveled.count, 1); XCTAssertEqual(traveled.first?.day, "2026-08-31")
        XCTAssertEqual(traveled.first?.timeZoneID, "America/New_York"); XCTAssertEqual(traveled.first?.sourceNeedsReview, false)
        execute("UPDATE sleep_events SET timestamp='2026-09-01T01:40:00Z' WHERE id='end'", storage)
        XCTAssertEqual(try repository.reviewedNapEpisodes(asOf: asOf, defaultTimeZoneID: "UTC").first?.sourceNeedsReview, true)
        execute("DELETE FROM sleep_events", storage)
        XCTAssertEqual(try repository.reviewedNapEpisodes(asOf: asOf, defaultTimeZoneID: "UTC").first?.sourceNeedsReview, true)
    }

}
