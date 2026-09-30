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
