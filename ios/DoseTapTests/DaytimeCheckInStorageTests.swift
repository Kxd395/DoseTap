import XCTest
import SQLite3
import DoseCore
@testable import DoseTap

@MainActor
final class DaytimeCheckInStorageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000.123)
    func value() throws -> DaytimeCheckIn {
        try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 0)
    }
    func repo(_ storage: EventStorage) -> SessionRepository {
        SessionRepository(storage: storage, clock: { self.now.addingTimeInterval(100) }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
    }
    func testIndependentRepeatedObservationAndRestart() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repository = repo(EventStorage(dbPath: path)), a = try value(), b = try value()
        try repository.saveDaytimeCheckIn(a); try repository.saveDaytimeCheckIn(b)
        XCTAssertNil(repository.dose1Time)
        XCTAssertTrue(try repository.sessionDatesForExport().isEmpty)
        XCTAssertEqual(try repo(EventStorage(dbPath: path)).daytimeCheckIns().current.count, 2)
        XCTAssertTrue(try repository.daytimeCheckIns().current.contains(a))
    }
    func testFailedCommitRollbackAndRetryKeepExactIdentity() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage), a = try value()
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, sqliteCode: 13, detail: "Synthetic") : nil }
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(a))
        XCTAssertTrue(try repository.daytimeCheckIns().current.isEmpty)
        storage.medicationFaultInjector = nil
        try repository.saveDaytimeCheckIn(a); try repository.saveDaytimeCheckIn(a)
        XCTAssertEqual(try repository.daytimeCheckIns().revisions, [a])
    }
    func testCorrectionRejectsStaleAndChangedIDAndClearRemovesAll() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage), a = try value()
        try repository.saveDaytimeCheckIn(a)
        let next = try a.corrected(response: 4, status: .answered, reason: "Correction", recordedAt: now.addingTimeInterval(30))
        try repository.saveDaytimeCheckIn(next)
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(a.corrected(response: 6, status: .answered, reason: "Stale", recordedAt: now.addingTimeInterval(40))))
        let changed = try DaytimeCheckIn(id: a.id, revisionID: a.revisionID, assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 2)
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(changed))
        XCTAssertEqual(try repository.daytimeCheckIns().current, [next])
        storage.clearAllData()
        XCTAssertTrue(try repository.daytimeCheckIns().revisions.isEmpty)
    }
    func testCorruptPayloadFailsClosed() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO daytime_checkins VALUES ('bad', 'bad', '{}')", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try repository.daytimeCheckIns())
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(value()))
    }
}

extension DaytimeCheckInStorageTests {
    func testLinkedEventReviewCountsOneIndependentEvent() throws {
        let repository = repo(EventStorage(dbPath: ":memory:"))
        let event = try DaytimeEvent(kind: .unplannedSleep, occurredAt: now.addingTimeInterval(-600), recordedAt: now, timeZoneIdentifier: "UTC")
        try repository.saveDaytimeEvent(event); try repository.saveDaytimeEvent(event)
        let review = try DaytimeEventReview(from: now.addingTimeInterval(-3600), to: now, status: .eventsReported, eventIDs: [event.id])
        for _ in 0..<2 {
            let observation = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: nil, status: .incomplete, eventReview: review)
            try repository.saveDaytimeCheckIn(observation)
        }
        XCTAssertEqual(try repository.daytimeEvents().current.count, 1)
        XCTAssertEqual(try repository.daytimeCheckIns().current.count, 2)
        XCTAssertTrue(try repository.sessionDatesForExport().isEmpty)
    }
    func testUnknownEventReferenceRejectedWithoutSaving() throws {
        let repository = repo(EventStorage(dbPath: ":memory:"))
        let review = try DaytimeEventReview(from: now, to: now, status: .eventsReported, eventIDs: [UUID()])
        let observation = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, eventReview: review)
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(observation))
        XCTAssertTrue(try repository.daytimeCheckIns().current.isEmpty)
    }
    func testEventFailureAndCorrectionHistory() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage)
        let event = try DaytimeEvent(kind: .struggling, occurredAt: now, recordedAt: now, timeZoneIdentifier: "UTC")
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, sqliteCode: 13, detail: "Synthetic") : nil }
        XCTAssertThrowsError(try repository.saveDaytimeEvent(event))
        XCTAssertTrue(try repository.daytimeEvents().current.isEmpty)
        storage.medicationFaultInjector = nil
        try repository.saveDaytimeEvent(event)
        let corrected = try event.corrected(kind: .unclear, note: "Unsure", reason: "Correction", recordedAt: now)
        try repository.saveDaytimeEvent(corrected)
        XCTAssertEqual(try repository.daytimeEvents().revisions.count, 2)
        XCTAssertEqual(try repository.daytimeEvents().current, [corrected])
        storage.clearAllData(); XCTAssertTrue(try repository.daytimeEvents().revisions.isEmpty)
    }
}

extension DaytimeCheckInStorageTests {
    func testNearbySnapshotIncludesIndependentRevisions() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage), a = try value()
        try repository.saveDaytimeCheckIn(a)
        try repository.saveDaytimeEvent(DaytimeEvent(kind: .unclear, occurredAt: now, recordedAt: now, timeZoneIdentifier: "UTC"))
        let snapshot = try storage.dashboardSnapshot(sourceID: "synthetic", sequence: 1, capturedAt: now)
        let section = try XCTUnwrap(snapshot.sections.first { $0.dataset == .daytimeDiary })
        XCTAssertEqual(section.rowCount, 2)
        let text = String(data: try XCTUnwrap(section.rows), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("daytime_checkins")); XCTAssertTrue(text.contains("daytime_events"))
    }
}

extension DaytimeCheckInStorageTests {
    private func publishedDaytimeModel() -> DashboardAnalyticsModel {
        let model = DashboardAnalyticsModel(now: { self.now }, sessionRepo: repo(EventStorage(dbPath: ":memory:")), timeZone: { TimeZone(secondsFromGMT: 0)! })
        model.selectedRange = .month; model.lastRefresh = now
        return model
    }
    func testSharedDaytimeSelectionRejectsPendingAndUnpublishedBounds() throws {
        let model = publishedDaytimeModel()
        let selection = try model.validatedSharedDaytimeSelection()
        XCTAssertEqual(selection.asOf, now); XCTAssertEqual(selection.range, .month)
        XCTAssertNotNil(selection.contextIssue)
        model.isLoading = true
        XCTAssertThrowsError(try model.validatedSharedDaytimeSelection())
        model.isLoading = false; model.lastRefresh = nil
        XCTAssertThrowsError(try model.validatedSharedDaytimeSelection())
    }
    func testSharedDaytimeSelectionRejectsChangedTimezone() throws {
        let model = publishedDaytimeModel()
        model.reportingTimeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertThrowsError(try model.validatedSharedDaytimeSelection())
    }
    func testSharedDaytimeSelectionRejectsPreviousCustomPublication() throws {
        let model = publishedDaytimeModel()
        let input = PhysicianReportRange.custom(start: now.addingTimeInterval(-86400), endExclusive: now)
        model.selectedRange = .custom; model.customReportingRange = input; model.publishedCustomReportingRange = input
        model.reportingPeriod = try PhysicianReportPeriod.resolve(input, ledger: .init(), asOf: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertNoThrow(try model.validatedSharedDaytimeSelection())
        model.customReportingRange = .custom(start: now.addingTimeInterval(-172800), endExclusive: now)
        XCTAssertThrowsError(try model.validatedSharedDaytimeSelection())
    }
    func testDaytimeCapturedReadKeepsOriginalBeforeLaterCorrection() throws {
        let repository = repo(EventStorage(dbPath: ":memory:")), original = try value()
        try repository.saveDaytimeCheckIn(original)
        let later = try original.corrected(response: 8, status: .answered, reason: "Later correction", recordedAt: now.addingTimeInterval(30))
        try repository.saveDaytimeCheckIn(later)
        let capture = try DaytimeTrendRecords(repository: repository, asOf: now)
        XCTAssertEqual(capture.observations, [original])
        XCTAssertEqual(try DaytimeTrendRecords(repository: repository, asOf: now.addingTimeInterval(30)).observations, [later])
    }
}

extension DaytimeCheckInStorageTests {
    func testMainWakeSourceUsesExplicitAnswerAndStableSemanticRevision() throws {
        let storage = EventStorage.inMemory(), repository = repo(storage), key = "2026-09-20"
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('explicit-wake','2026-09-20','2026-09-21T00:00:00Z')", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('nap-only','nap_end','2026-09-19T12:00:00Z','2026-09-19')", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(try repository.daytimeMainWakeSources(asOf: now).isEmpty)
        var diary = NightOutcomeDiary(); diary.finalWakeAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970) - 60)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: key), reason: "", recordedAt: now).isCommitted)
        let first = try XCTUnwrap(repository.daytimeMainWakeSources(asOf: now).first)
        XCTAssertEqual(first.id, "explicit-wake"); XCTAssertEqual(first.at, diary.finalWakeAt)
        diary.dayType = .workday
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: key), reason: "Context added", recordedAt: now.addingTimeInterval(10)).isCommitted)
        XCTAssertEqual(try repository.daytimeMainWakeSources(asOf: now.addingTimeInterval(10)).first?.revision, first.revision)
        diary.finalWakeAt = diary.finalWakeAt?.addingTimeInterval(30)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: key), reason: "Wake corrected", recordedAt: now.addingTimeInterval(20)).isCommitted)
        XCTAssertNotEqual(try repository.daytimeMainWakeSources(asOf: now.addingTimeInterval(20)).first?.revision, first.revision)
        XCTAssertEqual(try repository.daytimeMainWakeSources(asOf: now).first?.revision, first.revision)
        diary.finalWakeAt = nil
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: key), reason: "Wake uncertain", recordedAt: now.addingTimeInterval(30)).isCommitted)
        XCTAssertTrue(try repository.daytimeMainWakeSources(asOf: now.addingTimeInterval(30)).isEmpty)
    }
    func testBatchWakeReadRetainsHistoryIdentityAndReadabilityChecks() throws {
        let corruptions = [
            "UPDATE checkin_submissions SET source_record_id='orphan',session_id='orphan' WHERE checkin_type='night_outcome'",
            "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('conflict','2026-09-20','2026-09-21T01:00:00Z')",
            "INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('bad','dose1','invalid','2026-09-20','explicit-wake')",
            "INSERT INTO dose_events(id,event_type,timestamp,session_date,session_id) VALUES('other-night','dose1','2026-09-21T00:00:00Z','2026-09-19','explicit-wake')"
        ]
        for sql in corruptions {
            let storage = EventStorage.inMemory(), repository = repo(storage)
            XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('explicit-wake','2026-09-20','2026-09-21T00:00:00Z')", nil, nil, nil), SQLITE_OK)
            var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-60)
            XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2026-09-20"), reason: "", recordedAt: now).isCommitted)
            XCTAssertEqual(try repository.daytimeMainWakeSources(asOf: now).first?.id, "explicit-wake")
            XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
            XCTAssertThrowsError(try repository.daytimeMainWakeSources(asOf: now))
            XCTAssertThrowsError(try repository.daytimeSleepEvidence(asOf: now))
            XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
        }
    }
    func testConcurrentWakeCommitCannotTearSleepEvidenceSnapshot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("wake.sqlite").path
        let storage = EventStorage(dbPath: path), repository = repo(storage)
        XCTAssertEqual(sqlite3_exec(storage.db, "PRAGMA journal_mode=WAL", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('explicit-wake','2026-09-20','2026-09-21T00:00:00Z'); INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('lights','lights_out','\(AppFormatters.iso8601Fractional.string(from: now.addingTimeInterval(-120)))','2026-09-20')", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(storage.saveNightOutcome(NightOutcomeDiary(), review: try storage.nightOutcomeSnapshot(sessionDate: "2026-09-20"), reason: "", recordedAt: now).isCommitted)
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &writer), SQLITE_OK)
        let connection = try XCTUnwrap(writer); defer { sqlite3_close(connection) }
        var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-60)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let record = NightOutcomeRecord(answers: diary, recordedAt: now, revisions: [])
        let probe = DaytimeEvidenceWriter(db: connection, payload: String(decoding: try encoder.encode(record), as: UTF8.self))
        sqlite3_trace_v2(storage.db, UInt32(SQLITE_TRACE_STMT), { _, context, statement, _ in
            if let context, let statement, let sql = sqlite3_sql(OpaquePointer(statement)),
               String(cString: sql).hasPrefix("SELECT session_date, source_record_id") {
                Unmanaged<DaytimeEvidenceWriter>.fromOpaque(context).takeUnretainedValue().writeOnce()
            }
            return SQLITE_OK
        }, Unmanaged.passUnretained(probe).toOpaque())
        defer { sqlite3_trace_v2(storage.db, 0, nil, nil) }
        let first = try repository.daytimeSleepEvidence(asOf: now)
        XCTAssertEqual(probe.result, SQLITE_DONE)
        XCTAssertTrue(first.sleepActive); XCTAssertTrue(first.wakes.isEmpty)
        let next = try repository.daytimeSleepEvidence(asOf: now)
        XCTAssertFalse(next.sleepActive); XCTAssertEqual(next.wakes.first?.id, "explicit-wake")
        XCTAssertEqual(sqlite3_get_autocommit(storage.db), 1)
    }
    func testMainWakeSourceRejectsUnreadableOutcomeAndInvalidCapture() throws {
        let storage = EventStorage.inMemory(), repository = repo(storage)
        XCTAssertThrowsError(try repository.daytimeMainWakeSources(asOf: Date(timeIntervalSince1970: .nan)))
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('explicit-wake','2026-09-20','2026-09-21T00:00:00Z')", nil, nil, nil), SQLITE_OK)
        var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-60)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2026-09-20"), reason: "", recordedAt: now).isCommitted)
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE checkin_submissions SET responses_json=responses_json || char(0) || 'trailing' WHERE checkin_type='night_outcome'", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try repository.daytimeMainWakeSources(asOf: now))
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE checkin_submissions SET responses_json='invalid JSON' WHERE checkin_type='night_outcome'", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try repository.daytimeMainWakeSources(asOf: now))
    }
}


extension DaytimeCheckInStorageTests {
    func testDaytimeInspectionOverlapRequiresExplicitChoice() throws {
        let a = try value(), b = try value()
        var state = DaytimeInspectionState()
        state.offer(at: now, observations: [a, b])
        XCTAssertNil(state.selectedObservationID)
        XCTAssertEqual(Set(state.offeredCandidateIDs), Set([a.id, b.id]))
        state.select(a.id)
        state.offer(at: now, observations: [a, b])
        XCTAssertEqual(state.selectedObservationID, a.id)
        XCTAssertEqual(state.offeredCandidateIDs.count, 2)
        let nearby = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-1), recordedAt: now, timeZoneIdentifier: "UTC", response: 0)
        state.offer(at: now, observations: [a, nearby], tolerance: 2)
        XCTAssertEqual(Set(state.offeredCandidateIDs), Set([a.id, nearby.id]))
        XCTAssertEqual(state.selectedObservationID, a.id)
        state.offer(at: now, observations: [a, nearby], tolerance: .infinity)
        XCTAssertTrue(state.offeredCandidateIDs.isEmpty)
        XCTAssertEqual(state.selectedObservationID, a.id)
    }
    func testDaytimeInspectionRetainsIdentityAcrossCaptureAndFilters() throws {
        let a = try value(), repository = repo(EventStorage(dbPath: ":memory:"))
        let model = DashboardAnalyticsModel(now: { self.now }, sessionRepo: repository, timeZone: { TimeZone(secondsFromGMT: 0)! })
        model.daytimeInspection.select(a.id)
        model.daytimeInspection.origin = .scheduled
        model.reportingAsOf = now.addingTimeInterval(30); model.selectedRange = .sixMonths
        XCTAssertEqual(model.daytimeInspection.selectedObservationID, a.id)
        XCTAssertEqual(model.daytimeInspection.origin, .scheduled)
        var state = model.daytimeInspection
        state.move(1, observations: [])
        XCTAssertEqual(state.selectedObservationID, a.id)
        let revision = try a.corrected(response: 7, status: .answered, reason: "Correction", recordedAt: now.addingTimeInterval(20))
        XCTAssertEqual(state.selected(in: [revision])?.revisionID, revision.revisionID)
        state.resetFilters()
        XCTAssertEqual(state.selectedObservationID, a.id)
        state.resetSelection()
        XCTAssertNil(state.selectedObservationID)
    }
    func testDaytimeInspectionNavigationAndUnansweredRows() throws {
        let a = try value()
        let b = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-10), recordedAt: now, timeZoneIdentifier: "UTC", response: nil, status: .incomplete)
        var state = DaytimeInspectionState()
        state.move(1, observations: [a, b]); XCTAssertNil(state.selectedObservationID)
        state.select(b.id); state.move(1, observations: [a, b])
        XCTAssertEqual(state.selectedObservationID, a.id)
        state.move(1, observations: [a, b]); XCTAssertEqual(state.selectedObservationID, a.id)
        state.offer(at: b.assessedAt, observations: [b]); XCTAssertEqual(state.selectedObservationID, a.id)
        XCTAssertTrue(state.offeredCandidateIDs.isEmpty)
    }
}

extension DaytimeCheckInStorageTests {
    func testNapSelectionPreservesReviewedIdentityWithoutDuplicatingNap() throws {
        let repository = repo(EventStorage(dbPath: ":memory:"))
        let episode = NapEpisode(day: NapEpisode.day(now, "UTC"), timeZoneID: "UTC", start: now.addingTimeInterval(-900), end: now.addingTimeInterval(-300), recordedAt: now)
        var document = NapDiaryDocument(); document.episodes = [episode]
        try repository.saveNapDiary(document, expectedRevision: nil)
        let candidate = try XCTUnwrap(repository.daytimeSourceCandidates(kind: .nap, asOf: now).first)
        XCTAssertEqual(candidate.link.sourceRevisionID, episode.revision.uuidString)
        XCTAssertEqual(candidate.link.sourceCalendarDay, episode.day)
        let row = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: [candidate.link])
        try repository.saveDaytimeCheckIn(row)
        XCTAssertEqual(try repository.napDiary()?.episodes.count, 1)
        XCTAssertEqual(try repository.daytimeCheckIns().current.first?.sourceLinks, [candidate.link])
        XCTAssertNil(repository.dose1Time)
    }
    func testChangedNapRejectsNewLinkButExactRetryAndCorrectionKeepHistoricalEvidence() throws {
        let repository = repo(EventStorage(dbPath: ":memory:"))
        let episode = NapEpisode(day: NapEpisode.day(now, "UTC"), timeZoneID: "UTC", start: now.addingTimeInterval(-900), recordedAt: now)
        var document = NapDiaryDocument(); document.episodes = [episode]
        try repository.saveNapDiary(document, expectedRevision: nil)
        let link = try XCTUnwrap(repository.daytimeSourceCandidates(kind: .nap, asOf: now).first?.link)
        let row = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: [link])
        try repository.saveDaytimeCheckIn(row)
        var corrected = episode; corrected.revision = UUID(); corrected.predecessor = episode.revision
        corrected.end = now.addingTimeInterval(-100); corrected.reason = "End reviewed"; corrected.recordedAt = now.addingTimeInterval(10)
        let previousRevision = document.revision; document.revision = UUID(); document.episodes.append(corrected)
        try repository.saveNapDiary(document, expectedRevision: previousRevision)
        let newRow = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: [link])
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(newRow))
        try repository.saveDaytimeCheckIn(row)
        try repository.saveDaytimeCheckIn(row.corrected(response: 5, status: .answered, reason: "Response", recordedAt: now.addingTimeInterval(20)))
        XCTAssertEqual(try repository.daytimeCheckIns().current.count, 1)
        XCTAssertEqual(try repository.daytimeCheckIns().current.first?.sourceLinks, [link])
    }
    func testOverlappingNapSourcesRemainIneligibleUntilReviewed() throws {
        let repository = repo(EventStorage(dbPath: ":memory:"))
        let first = NapEpisode(day: NapEpisode.day(now, "UTC"), timeZoneID: "UTC", start: now.addingTimeInterval(-900), end: now.addingTimeInterval(-300), recordedAt: now)
        let second = NapEpisode(day: first.day, timeZoneID: "UTC", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-100), recordedAt: now)
        var document = NapDiaryDocument(); document.episodes = [first, second]
        try repository.saveNapDiary(document, expectedRevision: nil)
        XCTAssertTrue(try repository.daytimeSourceCandidates(kind: .nap, asOf: now).isEmpty)
        XCTAssertEqual(try repository.napDiary()?.episodes.count, 2)
    }
    func testNapSourceReadJoinsTransactionWithoutCommittingIt() throws {
        let storage = EventStorage(dbPath: ":memory:"), repository = repo(storage)
        let episode = NapEpisode(day: NapEpisode.day(now, "UTC"), timeZoneID: "UTC", start: now.addingTimeInterval(-900), recordedAt: now)
        var document = NapDiaryDocument(); document.episodes = [episode]
        try repository.saveNapDiary(document, expectedRevision: nil)
        let link = try XCTUnwrap(repository.daytimeSourceCandidates(kind: .nap, asOf: now).first?.link)
        let row = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: [link])
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, sqliteCode: 13, detail: "Synthetic") : nil }
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(row))
        XCTAssertTrue(try repository.daytimeCheckIns().revisions.isEmpty)
        XCTAssertEqual(try repository.napDiary(), document)
        storage.medicationFaultInjector = nil
        try repository.saveDaytimeCheckIn(row)
        XCTAssertEqual(try repository.daytimeCheckIns().current, [row])
        XCTAssertEqual(try repository.napDiary(), document)
    }
    func testMissingSourceRollbackAndRetryPreservesLedger() throws {
        let repository = repo(EventStorage(dbPath: ":memory:"))
        let link = try DaytimeSourceLink(kind: .mainWake, sourceID: "missing", evidenceKey: String(repeating: "a", count: 64), start: now.addingTimeInterval(-100), timePrecision: .reported, selectedAt: now)
        let row = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: [link])
        XCTAssertThrowsError(try repository.saveDaytimeCheckIn(row))
        XCTAssertTrue(try repository.daytimeCheckIns().revisions.isEmpty)
        try repository.saveDaytimeCheckIn(value())
        XCTAssertEqual(try repository.daytimeCheckIns().current.count, 1)
    }
    func testMedicationCandidateKeepsUnknownOccurrenceAndActualComponents() throws {
        let repository = repo(EventStorage(dbPath: ":memory:"))
        let component = try MedicationPresetComponent(id: UUID(), form: .tablet, strengthMilligrams: 2, unitCount: 1)
        let preset = try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(), supersedesRevisionID: nil, labelName: "Synthetic", ingredient: "Synthetic ingredient", releaseProfile: .extendedRelease, components: [component], instructions: "Label", schedule: .scheduled, effectiveFrom: now, effectiveUntil: nil, recordedAt: now)
        try repository.saveMedicationPresetRevision(preset)
        let actual = try ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: [component], occurredAt: nil, precision: .unknown, timeZoneIdentifier: nil, utcOffsetSeconds: nil, confirmedAt: now, recordedAt: now)
        try repository.saveConfirmedMedicationAdministration(actual)
        let candidate = try XCTUnwrap(repository.daytimeSourceCandidates(kind: .medication, asOf: now).first)
        XCTAssertNil(candidate.link.start)
        XCTAssertEqual(candidate.link.timePrecision, .unknown)
        XCTAssertEqual(candidate.link.sourceEventIDs, [actual.id.uuidString])
        XCTAssertEqual(candidate.link.sourceRevisionID, preset.revisionID.uuidString)
        XCTAssertTrue(candidate.label.contains("2 mg"))
        try repository.saveDaytimeCheckIn(DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: [candidate.link]))
        XCTAssertEqual(try repository.medicationPresetExportSnapshot().administrations.count, 1)
    }
}

extension DaytimeCheckInStorageTests {
    func makeWake(_ storage: EventStorage, at: Date, recordedAt: Date) throws {
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('explicit-wake','2026-09-20','2026-09-21T00:00:00Z')", nil, nil, nil), SQLITE_OK)
        var diary = NightOutcomeDiary(); diary.finalWakeAt = at
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2026-09-20"), reason: "", recordedAt: recordedAt).isCommitted)
    }
    func testLinkedWakeContextIsFrozenAndClearDoesNotRetarget() throws {
        let storage = EventStorage.inMemory(), repository = repo(storage)
        try makeWake(storage, at: now.addingTimeInterval(-3600), recordedAt: now.addingTimeInterval(-100))
        let link = try XCTUnwrap(repository.daytimeSourceCandidates(kind: .mainWake, asOf: now).first?.link)
        let row = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, sourceLinks: [link])
        try repository.saveDaytimeCheckIn(row)
        let snapshot = try DaytimeTrendRecords(repository: repository, asOf: now)
        XCTAssertEqual(snapshot.wakeContexts[row.id]?.status, .current)
        let source = try XCTUnwrap(snapshot.wakeContexts[row.id]?.currentSource?.reference.at)
        XCTAssertEqual(snapshot.wakeContexts[row.id]?.elapsedSeconds, now.timeIntervalSince(source))
        XCTAssertTrue(storage.saveNightOutcome(NightOutcomeDiary(), review: try storage.nightOutcomeSnapshot(sessionDate: "2026-09-20"), reason: "Wake uncertain", recordedAt: now.addingTimeInterval(10)).isCommitted)
        XCTAssertEqual(try DaytimeTrendRecords(repository: repository, asOf: now).wakeContexts[row.id]?.status, .current)
        XCTAssertEqual(try DaytimeTrendRecords(repository: repository, asOf: now.addingTimeInterval(20)).wakeContexts[row.id]?.status, .unavailable)
        XCTAssertEqual(try repository.daytimeCheckIns().current.first?.sourceLinks, [link])
    }
    func testScheduledWakeUsesOriginalPromptAndScheduleIdentity() throws {
        let storage = EventStorage.inMemory(), repository = repo(storage)
        try makeWake(storage, at: now.addingTimeInterval(-3600), recordedAt: now.addingTimeInterval(-3500))
        let wake = try XCTUnwrap(repository.daytimeMainWakeSources(asOf: now).first)
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 12, minute: 0, timeZone: "UTC", enabled: true, at: now.addingTimeInterval(-7200), rule: DaytimePromptRule(anchor: .mainWake, selectedWeekdays: Set(1...7), wakeOffsetMinutes: 60))
        let anchor = try DaytimeAnchorSource(id: wake.id, revision: wake.revision, at: wake.at)
        let context = DaytimePromptAnchorContext(dayKey: DaytimePromptRule.dayKey(wake.at, timeZone: "UTC"), timeZone: "UTC", mainWake: anchor)
        let prompt = try XCTUnwrap(ledger.prepareHorizon(at: now.addingTimeInterval(-1800), contexts: [context]).first)
        try repository.saveDaytimePrompts(ledger)
        let row = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, origin: .scheduled, promptID: prompt.id, samplingProtocolID: prompt.scheduleID)
        let result = try repository.daytimeWakeContexts(observations: [row], asOf: now)
        XCTAssertEqual(result[row.id]?.status, .current)
        XCTAssertEqual(result[row.id]?.originalReferences.first?.sourceID, wake.id)
        XCTAssertEqual(result[row.id]?.originalReferences.first?.revision, wake.revision)
        let mismatched = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, origin: .scheduled, promptID: prompt.id, samplingProtocolID: UUID())
        XCTAssertEqual(try repository.daytimeWakeContexts(observations: [mismatched], asOf: now)[mismatched.id]?.status, .unavailable)
        let unlinked = try value()
        XCTAssertEqual(try repository.daytimeWakeContexts(observations: [unlinked], asOf: now)[unlinked.id]?.status, .notLinked)
    }
}


extension DaytimeCheckInStorageTests {
    func testWakeProjectionRejectsDuplicateRowsAndUnreadablePromptDoesNotGuess() throws {
        let repository = repo(EventStorage.inMemory()), row = try value()
        XCTAssertThrowsError(try repository.daytimeWakeContexts(observations: [row, row], asOf: now))
        let scheduled = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, origin: .scheduled, promptID: UUID())
        XCTAssertEqual(try repository.daytimeWakeContexts(observations: [scheduled], asOf: now)[scheduled.id]?.status, .unavailable)
        XCTAssertTrue(try repository.daytimeCheckIns().current.isEmpty)
    }
}

private final class DaytimeEvidenceWriter {
    let db: OpaquePointer
    let payload: String
    var result: Int32 = SQLITE_ERROR
    private var wrote = false
    init(db: OpaquePointer, payload: String) { self.db = db; self.payload = payload }
    func writeOnce() {
        guard !wrote else { return }; wrote = true
        var statement: OpaquePointer?
        result = sqlite3_prepare_v2(db, "UPDATE checkin_submissions SET responses_json=? WHERE checkin_type='night_outcome'", -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        result = sqlite3_bind_text(statement, 1, payload, -1, SQLITE_TRANSIENT)
        guard result == SQLITE_OK else { return }
        result = sqlite3_step(statement)
    }
}
