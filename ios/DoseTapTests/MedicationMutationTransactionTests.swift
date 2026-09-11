import Foundation
import SQLite3
import XCTest
@testable import DoseTap
import DoseCore
@preconcurrency import UserNotifications

@MainActor
private final class MedicationMutationNotificationCenter: AlarmNotificationCenterClient {
    private(set) var requestsByIdentifier: [String: UNNotificationRequest] = [:]

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }

    func add(_ request: UNNotificationRequest) async throws {
        requestsByIdentifier[request.identifier] = request
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        Array(requestsByIdentifier.values)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers {
            requestsByIdentifier.removeValue(forKey: identifier)
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
}

@MainActor
final class MedicationMutationTransactionTests: XCTestCase {
    func testTimelineSleepCheckDiscardsLateNightResponseAndClearsOldResult() async {
        let model = TimelineDoseSleepModel()
        await model.refresh(sessionDate: "first") { _ in .init(status: .available) }
        XCTAssertNotNil(model.result)
        let cancelled = Task { await model.refresh(sessionDate: "cancelled") { _ in .init(status: .failed) } }
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(model.result?.status, .available, "An already cancelled view task must not clear a newer result")
        var continuation: CheckedContinuation<ReviewedNightSleepResult, Never>?
        let old = Task { await model.refresh(sessionDate: "first") { _ in
            await withCheckedContinuation { continuation = $0 }
        } }
        while continuation == nil { await Task.yield() }
        XCTAssertNil(model.result, "A refresh must remove prior success immediately")
        XCTAssertTrue(model.isLoading)
        model.invalidate()
        await model.refresh(sessionDate: "second") { _ in .init(status: .missingWindow) }
        continuation?.resume(returning: .init(status: .available))
        await old.value
        XCTAssertEqual(model.result?.status, .missingWindow)
        model.invalidate()
        XCTAssertNil(model.result)
        XCTAssertFalse(model.isLoading)
    }

    func testTimelineDose2EpisodeKeepsBoundarySourcesAndUnknownReturn() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func result(returnObserved: Bool) throws -> ReviewedNightSleepResult {
            let window = ReviewedSleepWindow(sessionID: "episode", start: base, end: base.addingTimeInterval(2400),
                entryTimeZone: TimeZone(secondsFromGMT: 0)!, reviewedAt: base.addingTimeInterval(3000))
            var samples = [SleepEvidenceSample(sampleID: "before", start: base, end: base.addingTimeInterval(600),
                rawCategory: 1, stage: .asleep, origin: .init(sourceName: "Watch", bundleIdentifier: nil)),
                SleepEvidenceSample(sampleID: "awake", start: base.addingTimeInterval(600), end: base.addingTimeInterval(1920),
                    rawCategory: 2, stage: .awake, origin: .init(sourceName: "Watch", bundleIdentifier: nil))]
            if returnObserved { samples.append(.init(sampleID: "return", start: base.addingTimeInterval(1920), end: window.end,
                rawCategory: 1, stage: .asleep, origin: .init(sourceName: "Watch", bundleIdentifier: nil))) }
            let evidence = try XCTUnwrap(SleepEvidenceResolution.calculate(start: window.start, end: window.end, samples: samples))
            let projection = try XCTUnwrap(ReviewedNightSleepProjection.calculate(window: window, evidence: evidence, generatedAt: window.reviewedAt))
            let doses = [("dose1", 0.0), ("dose2", 1080.0)].map { kind, offset in
                DoseCore.StoredDoseEvent(id: kind, eventType: kind, timestamp: base.addingTimeInterval(offset), sessionDate: "synthetic", sessionId: "episode")
            }
            return .init(status: .partial, window: window, evidence: evidence, projection: projection,
                doseSleepMetrics: .calculate(projection: projection, doses: doses))
        }
        let complete = try result(returnObserved: true)
        let episode = try XCTUnwrap(TimelineDose2Episode(result: complete))
        XCTAssertEqual(episode.dose.timeIntervalSince(episode.start), 480)
        XCTAssertEqual(try XCTUnwrap(episode.returned).timeIntervalSince(episode.dose), 840)
        XCTAssertEqual(episode.samples.map(\.sampleID), ["before", "awake", "return"])
        let partial = try XCTUnwrap(TimelineDose2Episode(result: result(returnObserved: false)))
        XCTAssertNil(partial.returned)
        XCTAssertEqual(partial.observedEnd, base.addingTimeInterval(1920))
        let logs = [("bathroom", 1200.0), ("noise", 2100.0)].map { kind, seconds in
            DoseTap.StoredSleepEvent(id: kind, eventType: kind, timestamp: base.addingTimeInterval(seconds), sessionDate: "synthetic")
        }
        XCTAssertEqual(partial.matchingEvents(logs).map(\.id), ["bathroom"])

        XCTAssertEqual(partial.dose, episode.dose)
        XCTAssertNil(TimelineDose2Episode(result: .init(status: .unavailable)))
    }

    func testDoseSleepDisplayPreservesPositiveSubsecondDelay() {
        XCTAssertEqual(ReviewedDoseSleepMetricsView.durationText(0), "0 min 0 sec")
        XCTAssertEqual(ReviewedDoseSleepMetricsView.durationText(0.25), "<1 sec")
        XCTAssertEqual(ReviewedDoseSleepMetricsView.durationText(840), "14 min 0 sec")
    }

    func testDoseSleepMetricsUseCheckedSnapshotAndDoNotWrite() async throws {
        let storage = EventStorage.inMemory(); try seedDose1(in: storage)
        let now = oldDose1.addingTimeInterval(8 * 3600)
        var diary = NightOutcomeDiary()
        diary.reviewedSleepWindow = .init(sessionID: sessionId, start: oldDose1,
            end: oldDose1.addingTimeInterval(4 * 3600), entryTimeZone: .current, reviewedAt: now)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: sessionDate),
            reason: "", recordedAt: now).isCommitted)
        let before = storage.reviewedNightSleepInput(sessionDate: sessionDate, now: now)
        let result = await ReviewedNightSleepLoader.load(
            read: { storage.reviewedNightSleepInput(sessionDate: self.sessionDate, now: now) },
            clock: { now }, isEnabled: { true }) { start, end in
                let onset = start.addingTimeInterval(600)
                let origin = SleepEvidenceSample.Origin(sourceName: "Synthetic", bundleIdentifier: nil)
                return SleepEvidenceResolution.calculate(start: start, end: end, samples: [
                    .init(sampleID: "awake", start: start, end: onset, rawCategory: 2, stage: .awake, origin: origin),
                    .init(sampleID: "sleep", start: onset, end: end, rawCategory: 1, stage: .asleep, origin: origin)])
            }
        XCTAssertEqual(result.doseSleepMetrics?.dose1ToSleep.seconds, 600)
        XCTAssertEqual(result.doseSleepMetrics?.dose2ToSleep.reason, .missingDose)
        XCTAssertEqual(result.doseSleepMetrics?.generatedAt, now)
        XCTAssertEqual(before, storage.reviewedNightSleepInput(sessionDate: sessionDate, now: now))
    }

    func testReviewedProviderCheckDiscardsLateCallbackAfterTaskCancellation() async throws {
        let storage = EventStorage.inMemory(); try seedDose1(in: storage)
        let now = oldDose1.addingTimeInterval(8 * 3600)
        var diary = NightOutcomeDiary()
        diary.reviewedSleepWindow = .init(sessionID: sessionId, start: oldDose1,
            end: oldDose1.addingTimeInterval(3600), entryTimeZone: .current, reviewedAt: now)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: sessionDate),
            reason: "", recordedAt: now).isCommitted)
        let requested = expectation(description: "Provider suspended")
        var callback: CheckedContinuation<SleepEvidenceResolution?, Never>?
        let task = Task { @MainActor in
            await ReviewedNightSleepLoader.load(
                read: { storage.reviewedNightSleepInput(sessionDate: self.sessionDate, now: now) },
                clock: { now }, isEnabled: { true }) { _, _ in
                    await withCheckedContinuation { callback = $0; requested.fulfill() }
                }
        }
        await fulfillment(of: [requested], timeout: 5)
        task.cancel()
        callback?.resume(returning: SleepEvidenceResolution.calculate(start: oldDose1,
            end: oldDose1.addingTimeInterval(3600), samples: []))
        let result = await task.value
        XCTAssertEqual(result.status, .cancelled); XCTAssertNil(result.evidence)
        XCTAssertNil(result.projection); XCTAssertNil(result.doseSleepMetrics)
    }

    func testReviewedProviderCheckMissingDisabledEmptyAwakeConflictAndFailures() async throws {
        let storage = EventStorage.inMemory(); try seedDose1(in: storage)
        let now = oldDose1.addingTimeInterval(8 * 3600)
        let read = { storage.reviewedNightSleepInput(sessionDate: self.sessionDate, now: now) }
        var calls = 0
        let missing = await ReviewedNightSleepLoader.load(read: read, clock: { now }, isEnabled: { true }) { _, _ in
            calls += 1; return nil
        }
        XCTAssertEqual(missing.status, .missingWindow); XCTAssertEqual(calls, 0)
        var diary = NightOutcomeDiary()
        diary.reviewedSleepWindow = .init(sessionID: sessionId, start: oldDose1,
            end: oldDose1.addingTimeInterval(3600), entryTimeZone: .current, reviewedAt: now)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: sessionDate),
            reason: "", recordedAt: now).isCommitted)
        let disabled = await ReviewedNightSleepLoader.load(read: read, clock: { now }, isEnabled: { false }) { _, _ in
            calls += 1; return nil
        }
        XCTAssertEqual(disabled.status, .disabled); XCTAssertEqual(calls, 0)
        for scenario in ["empty", "awake", "conflict", "wrongBounds", "error", "disableDuringQuery", "cancel"] {
            var enabled = true
            let result = await ReviewedNightSleepLoader.load(read: read, clock: { now }, isEnabled: { enabled }) { start, end in
                if scenario == "error" { throw NSError(domain: "Synthetic provider", code: 1) }
                if scenario == "cancel" { throw CancellationError() }
                if scenario == "disableDuringQuery" { enabled = false }
                let awake = SleepEvidenceSample(sampleID: "awake", start: start, end: end, rawCategory: 2, stage: .awake,
                    origin: .init(sourceName: "Synthetic", bundleIdentifier: nil))
                let sleep = SleepEvidenceSample(sampleID: "sleep", start: start, end: end, rawCategory: 3, stage: .core,
                    origin: awake.origin)
                return SleepEvidenceResolution.calculate(start: scenario == "wrongBounds" ? start.addingTimeInterval(1) : start,
                    end: end, samples: scenario == "awake" ? [awake] : (scenario == "conflict" ? [awake, sleep] : []))
            }
            switch scenario {
            case "empty": XCTAssertEqual(result.status, .unavailable); XCTAssertNil(result.evidence?.coverage.asleepMinutes)
            case "awake": XCTAssertEqual(result.status, .available); XCTAssertEqual(result.evidence?.coverage.asleepMinutes, 0)
            case "conflict": XCTAssertEqual(result.status, .conflict); XCTAssertEqual(result.evidence?.conflictMinutes, 60)
            case "disableDuringQuery": XCTAssertEqual(result.status, .disabled); XCTAssertNil(result.evidence)
            case "cancel": XCTAssertEqual(result.status, .cancelled); XCTAssertNil(result.evidence)
            default: XCTAssertEqual(result.status, .failed); XCTAssertNil(result.evidence)
            }
            if let evidence = result.evidence {
                XCTAssertNotNil(result.doseSleepMetrics)
                XCTAssertEqual(result.projection?.coverage, evidence.coverage)
                XCTAssertEqual(result.projection?.conflictMinutes, evidence.conflictMinutes)
            } else { XCTAssertNil(result.projection); XCTAssertNil(result.doseSleepMetrics) }
        }
    }

    func testReviewedProviderCheckJoinsBoundsAndEvidenceWithoutWrites() async throws {
        let storage = EventStorage.inMemory(); try seedDose1(in: storage)
        let now = oldDose1.addingTimeInterval(8 * 3600)
        var diary = NightOutcomeDiary()
        diary.reviewedSleepWindow = .init(sessionID: sessionId, start: oldDose1,
            end: oldDose1.addingTimeInterval(405 * 60), entryTimeZone: .current, reviewedAt: now)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: sessionDate),
            reason: "", recordedAt: now).isCommitted)
        let before = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        let result = await ReviewedNightSleepLoader.load(
            read: { storage.reviewedNightSleepInput(sessionDate: self.sessionDate, now: now) },
            clock: { now }, isEnabled: { true }) { start, end in
                XCTAssertEqual(start, self.oldDose1)
                XCTAssertEqual(end, diary.reviewedSleepWindow?.end)
                let samples = [(0.0, 180.0), (285.0, 405.0)].map { lower, upper in
                    SleepEvidenceSample(sampleID: "sample-\(lower)", start: start.addingTimeInterval(lower * 60),
                        end: start.addingTimeInterval(upper * 60), rawCategory: 3, stage: .core,
                        origin: .init(sourceName: "Synthetic", bundleIdentifier: nil))
                }
                return SleepEvidenceResolution.calculate(start: start, end: end, samples: samples)
            }
        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.evidence?.coverage.asleepMinutes, 300)
        XCTAssertEqual(result.evidence?.coverage.unmeasuredMinutes, 105)
        XCTAssertEqual(result.window, diary.reviewedSleepWindow)
        XCTAssertEqual(result.checkedAt, now)
        XCTAssertEqual(result.projection?.coverage.asleepMinutes, 300)
        XCTAssertEqual(result.projection?.bands.map(\.state), [.asleep, .unmeasured, .asleep])
        XCTAssertEqual(result.projection?.generatedAt, now)
        let after = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertEqual(after.rawJSON, before.rawJSON); XCTAssertEqual(after.history.events, before.history.events)
    }

    func testReviewedProviderCheckDiscardsChangedEvidenceAcrossAwait() async throws {
        for change in ["dose", "window", "nap", "otherWindow", "unreadable"] {
            let storage = EventStorage.inMemory(); try seedDose1(in: storage)
            let now = oldDose1.addingTimeInterval(8 * 3600)
            var diary = NightOutcomeDiary()
            diary.reviewedSleepWindow = .init(sessionID: sessionId, start: oldDose1,
                end: oldDose1.addingTimeInterval(6 * 3600), entryTimeZone: .current, reviewedAt: now)
            XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: sessionDate),
                reason: "", recordedAt: now).isCommitted)
            let result = await ReviewedNightSleepLoader.load(
                read: { storage.reviewedNightSleepInput(sessionDate: self.sessionDate, now: now) },
                clock: { now }, isEnabled: { true }) { start, end in
                    await Task.yield()
                    if change == "window" {
                        diary.reviewedSleepWindow = .init(sessionID: self.sessionId, start: start,
                            end: end.addingTimeInterval(60), entryTimeZone: .current, reviewedAt: now)
                        XCTAssertTrue(storage.saveNightOutcome(diary,
                            review: try storage.nightOutcomeSnapshot(sessionDate: self.sessionDate),
                            reason: "Correct bounds", recordedAt: now).isCommitted)
                    } else if change == "otherWindow" {
                        XCTAssertEqual(sqlite3_exec(storage.db,
                            "INSERT INTO sleep_sessions (session_id,session_date,start_utc) VALUES ('another-night','2026-08-30','\(storage.isoFormatter.string(from: start.addingTimeInterval(-86400)))')",
                            nil, nil, nil), SQLITE_OK)
                        var other = NightOutcomeDiary()
                        other.reviewedSleepWindow = .init(sessionID: "another-night", start: start.addingTimeInterval(-86400),
                            end: end.addingTimeInterval(-86400), entryTimeZone: .current, reviewedAt: now)
                        XCTAssertTrue(storage.saveNightOutcome(other,
                            review: try storage.nightOutcomeSnapshot(sessionDate: "2026-08-30"), reason: "", recordedAt: now).isCommitted)
                    } else {
                        let time = storage.isoFormatter.string(from: start.addingTimeInterval(60))
                        let sql = change == "dose" ? "UPDATE dose_events SET timestamp = '\(time)' WHERE event_type = 'dose1'" :
                            (change == "nap" ? "INSERT INTO sleep_events (id,event_type,timestamp,session_date,session_id) VALUES ('new-nap','nap_start','\(time)','\(self.sessionDate)','\(self.sessionId)')" : "DROP TABLE sleep_events")
                        XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
                    }
                    return SleepEvidenceResolution.calculate(start: start, end: end, samples: [])
                }
            XCTAssertEqual(result.status, change == "unreadable" ? .unreadable : .stale, change)
            XCTAssertNil(result.evidence, change)
            XCTAssertNil(result.projection, change); XCTAssertNil(result.doseSleepMetrics, change)
        }
    }

    func testWindowAssessmentBatchReadsSharedEvidenceOnceAndRechecksNextBatch() throws {
        let storage = EventStorage.inMemory(), now = oldDose1.addingTimeInterval(8 * 3600)
        let keys = ["2026-09-01", "2026-09-02", "2026-09-03"]
        for (index, key) in keys.enumerated() {
            let id = "batch-\(index)", start = oldDose1.addingTimeInterval(Double(index - 3) * 86400)
            XCTAssertEqual(sqlite3_exec(storage.db,
                "INSERT INTO sleep_sessions (session_id, session_date, start_utc) VALUES ('\(id)', '\(key)', '\(storage.isoFormatter.string(from: start))')",
                nil, nil, nil), SQLITE_OK)
            var diary = NightOutcomeDiary()
            diary.reviewedSleepWindow = .init(sessionID: id, start: start, end: start.addingTimeInterval(3600),
                entryTimeZone: .current, reviewedAt: now)
            XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: key),
                reason: "", recordedAt: now).isCommitted)
        }
        let expected = Dictionary(uniqueKeysWithValues: keys.map { ($0, storage.reviewedWindowAssessment(sessionDate: $0, now: now)) })
        let reads = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        reads.initialize(to: 0)
        defer { sqlite3_trace_v2(storage.db, 0, nil, nil); reads.deinitialize(count: 1); reads.deallocate() }
        sqlite3_trace_v2(storage.db, UInt32(SQLITE_TRACE_STMT), { _, context, statement, _ in
            if let statement, let sql = sqlite3_sql(OpaquePointer(statement)),
               String(cString: sql) == "SELECT id, event_type, timestamp, session_id, session_date FROM sleep_events" {
                context?.assumingMemoryBound(to: Int.self).pointee += 1
            }
            return SQLITE_OK
        }, reads)
        let result = storage.reviewedWindowAssessments(sessionDates: keys, now: now)
        XCTAssertEqual(result, expected)
        XCTAssertTrue(result.values.allSatisfy { $0.status == .checked })
        XCTAssertEqual(reads.pointee, 1, "Shared nap evidence must be prepared once per batch")
        reads.pointee = 0
        let repo = SessionRepository(storage: storage, clock: { now })
        let data = try StudioBundleExporter().buildStudioInsightsBundleDataForTesting(using: repo, sessionDates: keys)
        let bundle = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((bundle["sessions"] as? [[String: Any]])?.count, keys.count)
        XCTAssertEqual(reads.pointee, 1, "The actual bundle path must reuse the batch assessment")
        XCTAssertEqual(sqlite3_exec(storage.db,
            "INSERT INTO dose_events (id, event_type, timestamp, session_date, session_id) VALUES ('bad-batch-dose', 'dose1', 'not-a-date', '2026-09-01', 'batch-0')",
            nil, nil, nil), SQLITE_OK)
        let isolated = storage.reviewedWindowAssessments(sessionDates: keys + ["2026-09-04"], now: now)
        XCTAssertEqual(isolated[keys[0]]?.reasons, [.unreadableEvidence])
        XCTAssertEqual(isolated[keys[1]], expected[keys[1]])
        XCTAssertEqual(isolated[keys[2]], expected[keys[2]])
        XCTAssertEqual(isolated["2026-09-04"]?.status, .missing)
        XCTAssertEqual(sqlite3_exec(storage.db, "DELETE FROM dose_events WHERE id = 'bad-batch-dose'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(storage.db, "ALTER TABLE sleep_events RENAME TO unavailable_batch_naps", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(storage.reviewedWindowAssessments(sessionDates: keys, now: now).values.allSatisfy {
            $0.reasons == [.unreadableEvidence]
        }, "A new batch must not reuse stale success after source failure")
        XCTAssertEqual(storage.reviewedWindowAssessments(sessionDates: keys + ["2026-09-04"], now: now)["2026-09-04"]?.status, .missing)
    }

    func testWindowAssessmentUsesExistingLegacyDoseAliases() throws {
        let storage = EventStorage.inMemory(); try seedDose1(in: storage)
        let now = oldDose1.addingTimeInterval(8 * 3600)
        var diary = NightOutcomeDiary()
        diary.reviewedSleepWindow = .init(sessionID: sessionId, start: oldDose1,
            end: oldDose1.addingTimeInterval(6 * 3600), entryTimeZone: .current, reviewedAt: now)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: sessionDate),
            reason: "", recordedAt: now).isCommitted)
        for alias in ["dose_1_taken", "dose2_late", "dose_2_(late)", "dose_3_taken", "skipped", "snooze", "dose2_snoozed"] {
            XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET event_type = '\(alias)'", nil, nil, nil), SQLITE_OK)
            let before = try storage.historySnapshot(sessionDate: sessionDate).events
            let result = storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now)
            XCTAssertEqual(result.status, alias == "dose_1_taken" ? .checked : .needsReview, alias)
            if alias != "dose_1_taken" { XCTAssertTrue(result.reasons.contains(.invalidDoseRecords), alias) }
            XCTAssertEqual(try storage.historySnapshot(sessionDate: sessionDate).events, before)
        }
        let early = storage.isoFormatter.string(from: oldDose1.addingTimeInterval(-60))
        XCTAssertEqual(sqlite3_exec(storage.db,
            "UPDATE dose_events SET event_type = 'dose_1_taken', timestamp = '\(early)'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now).reasons, [.doseOutsideWindow])
    }

    func testWindowAssessmentRechecksDoseAndStrictNapEvidenceWithoutWrites() throws {
        let storage = EventStorage.inMemory(); try seedDose1(in: storage)
        let now = oldDose1.addingTimeInterval(8 * 3600)
        var diary = NightOutcomeDiary()
        diary.reviewedSleepWindow = .init(sessionID: sessionId, start: oldDose1, end: oldDose1.addingTimeInterval(6 * 3600),
            entryTimeZone: .current, reviewedAt: now)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: sessionDate),
            reason: "", recordedAt: now).isCommitted)
        let original = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertEqual(storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now).status, .checked)
        let formatter = storage.isoFormatter
        let early = formatter.string(from: oldDose1.addingTimeInterval(-60))
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp = '\(early)' WHERE event_type = 'dose1'", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now).reasons.contains(.doseOutsideWindow))
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE dose_events SET timestamp = '\(formatter.string(from: oldDose1))' WHERE event_type = 'dose1'", nil, nil, nil), SQLITE_OK)
        let nap = formatter.string(from: oldDose1.addingTimeInterval(600))
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events (id,event_type,timestamp,session_date,session_id) VALUES ('test-nap','nap_start','\(nap)','\(sessionDate)','\(sessionId)')", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now).reasons, [.incompleteNap])
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE sleep_events SET timestamp = 'unreadable' WHERE id = 'test-nap'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now).reasons, [.unreadableEvidence])
        XCTAssertEqual(sqlite3_exec(storage.db, "DELETE FROM sleep_events WHERE id = 'test-nap'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now).status, .checked)
        XCTAssertEqual(try storage.nightOutcomeSnapshot(sessionDate: sessionDate).rawJSON, original.rawJSON)
        XCTAssertEqual(try storage.nightOutcomeSnapshot(sessionDate: sessionDate).history.events, original.history.events)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
    }

    func testWindowAssessmentFailsClosedForUnavailableAndUnreadableEvidence() throws {
        let storage = EventStorage.inMemory(); try seedDose1(in: storage)
        let now = oldDose1.addingTimeInterval(8 * 3600)
        var diary = NightOutcomeDiary()
        diary.reviewedSleepWindow = .init(sessionID: sessionId, start: oldDose1, end: oldDose1.addingTimeInterval(6 * 3600),
            entryTimeZone: .current, reviewedAt: now)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: sessionDate),
            reason: "", recordedAt: now).isCommitted)
        XCTAssertEqual(sqlite3_exec(storage.db, "ALTER TABLE sleep_events RENAME TO unavailable_sleep_events", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now).reasons, [.unreadableEvidence])
        XCTAssertEqual(sqlite3_exec(storage.db, "ALTER TABLE unavailable_sleep_events RENAME TO sleep_events", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now).status, .checked)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO checkin_submissions (id,source_record_id,session_id,session_date,checkin_type,questionnaire_version,user_id,submitted_at_utc,local_offset_minutes,responses_json) SELECT 'broken-other','other','other','2026-09-01',checkin_type,questionnaire_version,user_id,submitted_at_utc,local_offset_minutes,'broken JSON' FROM checkin_submissions LIMIT 1", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now).reasons, [.unreadableEvidence])
        XCTAssertEqual(sqlite3_exec(storage.db, "DELETE FROM checkin_submissions WHERE id = 'broken-other'", nil, nil, nil), SQLITE_OK)
        var otherDiary = NightOutcomeDiary()
        otherDiary.reviewedSleepWindow = .init(sessionID: "other", start: oldDose1.addingTimeInterval(3600),
            end: oldDose1.addingTimeInterval(7 * 3600), entryTimeZone: .current, reviewedAt: now)
        let other = NightOutcomeRecord(answers: otherDiary, recordedAt: now, revisions: [])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let responses = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(other)) as? [String: Any])
        try storage.upsertCheckInSubmissionOrThrow(sourceRecordId: "other", sessionId: "other", sessionDate: "2026-09-01",
            checkInType: .nightOutcome, questionnaireVersion: "night_outcome.v1", submittedAt: now, responsesByQuestionID: responses)
        XCTAssertEqual(storage.reviewedWindowAssessment(sessionDate: sessionDate, now: now).reasons, [.overlappingWindow])
    }

    func testReviewedWindowPersistsCorrectionsAndRejectsStaleOrWrongSessionWithoutDoseWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("window.sqlite").path
        let reviewedAt = oldDose1.addingTimeInterval(8 * 3600)
        let window = ReviewedSleepWindow(sessionID: sessionId, start: oldDose1, end: oldDose1.addingTimeInterval(6 * 3600),
            entryTimeZone: TimeZone(identifier: "America/New_York")!, reviewedAt: reviewedAt)
        do {
            let storage = EventStorage(dbPath: path)
            try seedDose1(in: storage)
            let original = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
            var answers = NightOutcomeDiary(); answers.reviewedSleepWindow = window
            storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Injected") : nil }
            XCTAssertFalse(storage.saveNightOutcome(answers, review: original, reason: "", recordedAt: reviewedAt).isCommitted)
            XCTAssertNil(try storage.nightOutcomeSnapshot(sessionDate: sessionDate).record)
            storage.medicationFaultInjector = nil
            XCTAssertTrue(storage.saveNightOutcome(answers, review: original, reason: "", recordedAt: reviewedAt).isCommitted)
            XCTAssertFalse(storage.saveNightOutcome(answers, review: original, reason: "", recordedAt: reviewedAt).isCommitted)
            let saved = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
            XCTAssertEqual(saved.history.events, original.history.events)
            XCTAssertNil(saved.record?.answers.finalWakeAt)
            answers.reviewedSleepWindow = ReviewedSleepWindow(sessionID: "another-night", start: window.start, end: window.end,
                entryTimeZone: .current, reviewedAt: reviewedAt)
            XCTAssertFalse(storage.saveNightOutcome(answers, review: saved, reason: "Wrong identity", recordedAt: reviewedAt).isCommitted)
            XCTAssertEqual(try storage.nightOutcomeSnapshot(sessionDate: sessionDate).record?.answers.reviewedSleepWindow, window)
        }
        let storage = EventStorage(dbPath: path)
        let reopened = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertEqual(reopened.record?.answers.reviewedSleepWindow, window)
        var answers = try XCTUnwrap(reopened.record?.answers)
        answers.dayType = .dayOff
        XCTAssertTrue(storage.saveNightOutcome(answers, review: reopened, reason: "", recordedAt: reviewedAt).isCommitted)
        let changedDay = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertEqual(changedDay.record?.answers.reviewedSleepWindow, window)
        answers.reviewedSleepWindow = nil
        XCTAssertFalse(storage.saveNightOutcome(answers, review: changedDay, reason: "", recordedAt: reviewedAt).isCommitted)
        XCTAssertTrue(storage.saveNightOutcome(answers, review: changedDay, reason: "Remove incorrect window", recordedAt: reviewedAt).isCommitted)
        let cleared = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertNil(cleared.record?.answers.reviewedSleepWindow)
        XCTAssertEqual(cleared.record?.revisions.last?.answers.reviewedSleepWindow, window)
        XCTAssertEqual(cleared.history.events, reopened.history.events)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time)
        let exported = storage.fetchCheckInSubmissions(sessionDate: sessionDate, checkInType: .nightOutcome)
        XCTAssertEqual(exported.count, 1)
        XCTAssertTrue(cleared.rawJSON?.contains("Remove incorrect window") == true)
    }

    func testRetrospectiveDoseWakeAnswerPreservesReviewedWindow() throws {
        let storage = EventStorage.inMemory(); try seedDose1(in: storage)
        let entered = oldDose1.addingTimeInterval(8 * 3600)
        var diary = NightOutcomeDiary()
        diary.reviewedSleepWindow = .init(sessionID: sessionId, start: oldDose1, end: oldDose1.addingTimeInterval(6 * 3600),
            entryTimeZone: .current, reviewedAt: entered)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: sessionDate),
            reason: "", recordedAt: entered).isCommitted)
        XCTAssertFalse(storage.reconcileDoseEvent(eventType: .dose2, timestamp: oldDose1.addingTimeInterval(3 * 3600),
            sessionDate: sessionDate, sessionId: sessionId, metadata: nil, expectedDose1Time: oldDose1,
            onlyIfDose2Missing: true, wakeMethod: .natural).isCommitted,
            "A backdated occurrence without a valid later entry time must not corrupt an already reviewed diary")
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time)
        XCTAssertEqual(try storage.nightOutcomeSnapshot(sessionDate: sessionDate).record?.answers.reviewedSleepWindow, diary.reviewedSleepWindow)
        XCTAssertTrue(storage.reconcileDoseEvent(eventType: .dose2, timestamp: oldDose1.addingTimeInterval(3 * 3600),
            sessionDate: sessionDate, sessionId: sessionId, metadata: nil, expectedDose1Time: oldDose1,
            onlyIfDose2Missing: true, wakeMethod: .natural, recordedAt: entered).isCommitted)
        let saved = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertEqual(saved.record?.answers.reviewedSleepWindow, diary.reviewedSleepWindow)
        XCTAssertEqual(saved.record?.answers.wakeMethod, .natural)
        XCTAssertEqual(saved.record?.revisions.last?.answers.reviewedSleepWindow, diary.reviewedSleepWindow)
    }

    func testConfirmedDoseTwoAndWakeAnswerCommitOrRollBackTogether() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let dose2 = oldDose1.addingTimeInterval(180 * 60)
        let original = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        var diary = NightOutcomeDiary(); diary.backupAlarmSet = true; diary.dayType = .dayOff
        XCTAssertTrue(storage.saveNightOutcome(diary, review: original, reason: "", recordedAt: oldDose1).isCommitted)
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Injected") : nil }
        XCTAssertFalse(storage.saveDose2(timestamp: dose2, sessionId: sessionId,
            sessionDateOverride: sessionDate, wakeMethod: .natural).isCommitted)
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time)
        XCTAssertFalse(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).contains { $0.eventType == "dose2" })
        XCTAssertEqual(try storage.nightOutcomeSnapshot(sessionDate: sessionDate).record?.answers.wakeMethod, .unknown)
        storage.medicationFaultInjector = nil
        let result = storage.saveDose2(timestamp: dose2, sessionId: sessionId,
            sessionDateOverride: sessionDate, wakeMethod: .natural)
        XCTAssertTrue(result.isCommitted, result.failure?.detail ?? "Expected atomic commit")
        let saved = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertEqual(saved.record?.answers.wakeMethod, .natural)
        XCTAssertEqual(saved.record?.answers.backupAlarmSet, true, "A backup alarm does not change natural waking")
        XCTAssertEqual(saved.record?.answers.dayType, .dayOff)
        XCTAssertEqual(storage.loadCurrentSessionState().dose2Time, dose2)
    }

    func testRetrospectiveDoseTwoWakeUsesSameDiaryAndActualOccurrence() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let occurred = oldDose1.addingTimeInterval(300 * 60)
        let entered = occurred.addingTimeInterval(3600)
        XCTAssertTrue(storage.reconcileDoseEvent(eventType: .dose2, timestamp: occurred,
            sessionDate: sessionDate, sessionId: sessionId, metadata: nil,
            expectedDose1Time: oldDose1, onlyIfDose2Missing: true, wakeMethod: .alarm, recordedAt: entered).isCommitted)
        let saved = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertEqual(saved.record?.answers.wakeMethod, .alarm)
        XCTAssertEqual(saved.record?.recordedAt, entered)
        XCTAssertEqual(saved.history.events.first { $0.eventType == "dose2" }?.timestamp, occurred)
        XCTAssertEqual(storage.fetchCheckInSubmissions(sessionDate: sessionDate, checkInType: .nightOutcome).count, 1)
    }

    func testNightOutcomeCommitFailureStaleCorrectionAndMedicationIsolation() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let dose2 = oldDose1.addingTimeInterval(180 * 60)
        XCTAssertTrue(storage.saveDose2(timestamp: dose2, sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        let original = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        var diary = NightOutcomeDiary(); diary.wakeMethod = .natural; diary.backupAlarmSet = true
        func save(_ snapshot: NightOutcomeSnapshot, reason: String = "") -> MedicationMutationResult {
            storage.saveNightOutcome(diary, review: snapshot, reason: reason, recordedAt: dose2)
        }
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Injected") : nil }
        XCTAssertFalse(save(original).isCommitted)
        XCTAssertNil(try storage.nightOutcomeSnapshot(sessionDate: sessionDate).record)
        storage.medicationFaultInjector = nil
        XCTAssertTrue(save(original).isCommitted)
        XCTAssertFalse(save(original).isCommitted, "Stale form cannot overwrite a saved observation")
        let saved = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertEqual(saved.record?.answers.wakeMethod, .natural)
        XCTAssertEqual(saved.record?.answers.backupAlarmSet, true)
        diary.wakeMethod = .alarm
        XCTAssertFalse(save(saved).isCommitted, "Changing an answered field needs a reason")
        XCTAssertTrue(save(saved, reason: "Remembered the alarm").isCommitted)
        let corrected = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertEqual(corrected.record?.revisions.first?.answers.wakeMethod, .natural)
        XCTAssertEqual(corrected.history.events, original.history.events, "No medication rows may change")
        XCTAssertEqual(storage.loadCurrentSessionState().dose2Time, dose2)
        XCTAssertEqual(storage.fetchCheckInSubmissions(sessionDate: sessionDate, checkInType: .nightOutcome).count, 1)
        diary.finalWakeAt = dose2.addingTimeInterval(2 * 3600)
        diary.sleepiness = 0; diary.assessedAt = dose2.addingTimeInterval(8 * 3600)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: corrected, reason: "", recordedAt: diary.assessedAt!).isCommitted,
                      "A later, previously unanswered rating is not a correction")
        let later = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        XCTAssertEqual(later.record?.answers.sleepiness, 0, "Fully alert is a valid observed zero")
        XCTAssertEqual(later.record?.answers.assessedAt, diary.assessedAt)
        XCTAssertEqual(later.history.events, original.history.events)
    }

    func testWakeAnswerCannotCreateDoseTwoAndCorruptOutcomeFailsClosed() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let snapshot = try storage.nightOutcomeSnapshot(sessionDate: sessionDate)
        var diary = NightOutcomeDiary(); diary.wakeMethod = .alarm
        XCTAssertFalse(storage.saveNightOutcome(diary, review: snapshot, reason: "", recordedAt: oldDose1).isCommitted)
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time)
        diary.wakeMethod = .unknown; diary.dayType = .workday
        XCTAssertTrue(storage.saveNightOutcome(diary, review: snapshot, reason: "", recordedAt: oldDose1).isCommitted)
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE checkin_submissions SET responses_json = '{}' WHERE checkin_type = 'night_outcome'", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try storage.nightOutcomeSnapshot(sessionDate: sessionDate))
    }

    func testHistoryQuestionnairesCreateAnEmptyPastNightWithoutMedicationAndRejectStaleEdits() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let night = "2026-01-14"
        let time = ISO8601DateFormatter().date(from: "2026-01-15T03:00:00Z")!
        let review = try storage.historyQuestionnaireSnapshot(sessionDate: night, kind: .preSleep)
        var answers = DoseTap.PreSleepLogAnswers(); answers.notes = "Remembered evening"
        func save(_ review: HistoryQuestionnaireSnapshot, confirmed: Bool = true) -> MedicationMutationResult {
            storage.saveHistoryPreSleep(answers: answers, review: review, occurredAt: time, recordedAt: oldDose1,
                reason: "Forgot questionnaire", confirmed: confirmed)
        }
        XCTAssertFalse(save(review, confirmed: false).isCommitted)
        XCTAssertNil(storage.fetchSessionId(forSessionDate: night))
        answers.lastFood = .init(finishedAt: time.addingTimeInterval(1), highFat: true, notes: "Original food")
        XCTAssertFalse(save(review).isCommitted, "Food cannot occur after the historical questionnaire")
        XCTAssertNil(storage.fetchSessionId(forSessionDate: night), "Invalid food must roll back session creation")
        answers.lastFood?.finishedAt = time.addingTimeInterval(-10800)
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Injected") : nil }
        XCTAssertFalse(save(review).isCommitted)
        XCTAssertNil(storage.fetchSessionId(forSessionDate: night))
        XCTAssertNil(storage.fetchMostRecentPreSleepLog())
        storage.medicationFaultInjector = nil
        XCTAssertTrue(save(review).isCommitted)
        XCTAssertFalse(save(review).isCommitted, "A second submission with a stale snapshot must fail")
        XCTAssertEqual(storage.loadCurrentSessionState().sessionId, sessionId)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: review.history.sessionId, sessionDate: night).isEmpty)
        let updated = try storage.historyQuestionnaireSnapshot(sessionDate: night, kind: .preSleep)
        answers.notes = "Corrected evening"
        answers.lastFood?.highFat = false
        answers.lastFood?.notes = "Corrected food"
        XCTAssertTrue(save(updated).isCommitted)
        let submission = try XCTUnwrap(storage.fetchCheckInSubmissions(sessionDate: night).first)
        XCTAssertTrue(submission.responsesJson.contains("Remembered evening"))
        XCTAssertTrue(submission.responsesJson.contains("Original food"), "Correction must retain old food in provenance")
        XCTAssertEqual(storage.fetchMostRecentPreSleepLog(sessionId: updated.history.sessionId)?.answers?.lastFood?.highFat, false)
        XCTAssertTrue(submission.responsesJson.contains("history.provenance"))
        XCTAssertEqual(storage.fetchMostRecentPreSleepLog(sessionId: updated.history.sessionId)?.answers?.notes, "Corrected evening")
        let morning = try storage.historyQuestionnaireSnapshot(sessionDate: night, kind: .morning)
        let checkIn = DoseTap.StoredMorningCheckIn(id: UUID().uuidString, sessionId: morning.history.sessionId,
            timestamp: time, sessionDate: night, notes: "Remembered morning")
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Injected") : nil }
        XCTAssertFalse(storage.saveHistoryMorning(checkIn, review: morning, occurredAt: time, recordedAt: oldDose1,
            reason: "Late questionnaire", confirmed: true).isCommitted)
        XCTAssertEqual(storage.fetchCheckInSubmissions(sessionDate: night).count, 1)
        storage.medicationFaultInjector = nil
        XCTAssertTrue(storage.saveHistoryMorning(checkIn, review: morning, occurredAt: time, recordedAt: oldDose1,
            reason: "Late questionnaire", confirmed: true).isCommitted)
        XCTAssertEqual(storage.fetchCheckInSubmissions(sessionDate: night).count, 2)
        XCTAssertEqual(storage.loadCurrentSessionState().sessionId, sessionId)
        XCTAssertEqual(makeRepository(storage: storage, now: oldDose1).fetchMorningCheckIn(for: night)?.id, checkIn.id,
                       "Date-based presentation must resolve the saved stable session ID")
    }
    func testHistoryQuestionnaireRejectsFutureAndAmbiguousRecords() throws {
        let storage = EventStorage.inMemory()
        let night = "2026-01-14"
        let time = ISO8601DateFormatter().date(from: "2026-01-15T03:00:00Z")!
        let review = try storage.historyQuestionnaireSnapshot(sessionDate: night, kind: .preSleep)
        XCTAssertFalse(storage.saveHistoryPreSleep(answers: DoseTap.PreSleepLogAnswers(), review: review,
            occurredAt: time, recordedAt: time.addingTimeInterval(-1), reason: "Test", confirmed: true).isCommitted)
        XCTAssertFalse(storage.saveHistoryPreSleep(answers: DoseTap.PreSleepLogAnswers(), review: review,
            occurredAt: time.addingTimeInterval(86400), recordedAt: oldDose1, reason: "Wrong night", confirmed: true).isCommitted)
        let first = DoseTap.StoredMorningCheckIn(id: "first", sessionId: night, timestamp: time, sessionDate: night)
        let second = DoseTap.StoredMorningCheckIn(id: "second", sessionId: night, timestamp: time, sessionDate: night)
        storage.saveMorningCheckIn(first, forSession: night)
        storage.saveMorningCheckIn(second, forSession: night)
        XCTAssertThrowsError(try storage.historyQuestionnaireSnapshot(sessionDate: night, kind: .morning))
    }
    func testHistoryMorningCannotOverwriteAnotherNightsRecordID() throws {
        let storage = EventStorage.inMemory()
        let time = ISO8601DateFormatter().date(from: "2026-01-15T03:00:00Z")!
        storage.saveMorningCheckIn(DoseTap.StoredMorningCheckIn(id: "protected", sessionId: "2026-01-12",
            timestamp: time, sessionDate: "2026-01-12", notes: "Original"), forSession: "2026-01-12")
        let review = try storage.historyQuestionnaireSnapshot(sessionDate: "2026-01-14", kind: .morning)
        let candidate = DoseTap.StoredMorningCheckIn(id: "protected", sessionId: review.history.sessionId,
            timestamp: time, sessionDate: review.history.sessionDate, notes: "Wrong overwrite")
        XCTAssertFalse(storage.saveHistoryMorning(candidate, review: review, occurredAt: time,
            recordedAt: oldDose1, reason: "Late entry", confirmed: true).isCommitted)
        XCTAssertEqual(storage.fetchCheckInSubmissions(sessionDate: "2026-01-12").count, 1)
        XCTAssertTrue(storage.fetchCheckInSubmissions(sessionDate: "2026-01-14").isEmpty)
    }
    func testHistoricalSleepEntrySupportsOldNightsAndRejectsReplayFutureAndDoseNames() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let review = try storage.historySnapshot(sessionDate: "2026-01-14")
        let time = ISO8601DateFormatter().date(from: "2026-01-15T03:00:00Z")!
        func save(_ id: String, type: String = "bathroom", at: Date? = nil, original: DoseTap.StoredSleepEvent? = nil) -> MedicationMutationResult {
            storage.saveHistorySleepEvent(id: id, eventType: type, timestamp: at ?? time, notes: "Entered after the fact", review: review,
                original: original, remove: false, confirmed: true, recordedAt: oldDose1)
        }
        XCTAssertFalse(save("future", at: oldDose1.addingTimeInterval(1)).isCommitted)
        XCTAssertFalse(save("dose", type: "dose2").isCommitted)
        XCTAssertTrue(save("manual-event").isCommitted)
        XCTAssertFalse(save("manual-event").isCommitted)
        let event = try XCTUnwrap(storage.fetchSleepEvents(forSession: review.sessionDate).first)
        XCTAssertEqual(event.colorHex, "#007AFF")
        XCTAssertEqual(event.timestamp, time)
        XCTAssertTrue(save(event.id, at: time.addingTimeInterval(60), original: event).isCommitted)
        XCTAssertFalse(save(event.id, at: time.addingTimeInterval(120), original: event).isCommitted)
        XCTAssertEqual(storage.loadCurrentSessionState().sessionId, sessionId)
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Injected") : nil }
        XCTAssertFalse(save("rollback").isCommitted)
        XCTAssertEqual(storage.fetchSleepEvents(forSession: review.sessionDate).count, 1)
    }
    func testHistoryMissingNightDoesNotReplaceActiveSessionAndRejectsReplay() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let review = try storage.historySnapshot(sessionDate: "2026-01-14")
        let time = ISO8601DateFormatter().date(from: "2026-01-15T03:00:00Z")!
        let change = HistoryDoseChange(eventType: "dose1", timestamp: time, reason: "Forgot to log")
        XCTAssertTrue(storage.saveHistoryDoseChange(change, review: review, confirmed: true, warningConfirmed: true, recordedAt: oldDose1).isCommitted)
        XCTAssertEqual(storage.loadCurrentSessionState().sessionId, sessionId)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertFalse(storage.saveHistoryDoseChange(change, review: review, confirmed: true, warningConfirmed: true, recordedAt: oldDose1).isCommitted)
        XCTAssertEqual(try storage.historySnapshot(sessionDate: review.sessionDate).events.count, 1)
    }

    func testHistoryCorrectionRemovalAndRollbackPreserveOriginalEvidence() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        XCTAssertTrue(storage.saveDose2(timestamp: oldDose1.addingTimeInterval(180 * 60), sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        var review = try storage.historySnapshot(sessionDate: sessionDate)
        let original = try XCTUnwrap(review.events.first { $0.eventType == "dose2" })
        let correction = HistoryDoseChange(eventType: "dose2", timestamp: oldDose1.addingTimeInterval(285 * 60), replacingEventID: original.id, reason: "Wrong recorded time")
        XCTAssertFalse(storage.saveHistoryDoseChange(correction, review: review, confirmed: true, warningConfirmed: false, recordedAt: oldDose1.addingTimeInterval(600 * 60)).isCommitted)
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .diskFull, detail: "Injected") : nil }
        XCTAssertFalse(storage.saveHistoryDoseChange(correction, review: review, confirmed: true, warningConfirmed: true, recordedAt: oldDose1.addingTimeInterval(600 * 60)).isCommitted)
        XCTAssertEqual(try storage.historySnapshot(sessionDate: sessionDate).events, review.events)
        storage.medicationFaultInjector = nil
        XCTAssertTrue(storage.saveHistoryDoseChange(correction, review: review, confirmed: true, warningConfirmed: true, recordedAt: oldDose1.addingTimeInterval(600 * 60)).isCommitted)
        review = try storage.historySnapshot(sessionDate: sessionDate)
        let revised = try XCTUnwrap(review.events.first { $0.eventType == "dose2" })
        XCTAssertTrue(revised.metadata?.contains(original.id) == true)
        XCTAssertTrue(revised.metadata?.contains("retrospective") == true)
        XCTAssertEqual(storage.loadCurrentSessionState().dose2Time, correction.timestamp)
        let removal = HistoryDoseChange(eventType: "dose2", timestamp: revised.timestamp, replacingEventID: revised.id, remove: true, reason: "Not actually taken")
        XCTAssertTrue(storage.saveHistoryDoseChange(removal, review: review, confirmed: true, warningConfirmed: true, recordedAt: oldDose1.addingTimeInterval(600 * 60)).isCommitted)
        let rows = try storage.historySnapshot(sessionDate: sessionDate).events
        XCTAssertFalse(rows.contains { $0.eventType == "dose2" || $0.eventType == "dose2_skipped" })
        XCTAssertTrue(rows.first { $0.eventType == "history_correction" }?.metadata?.contains(original.id) == true)
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time)
        XCTAssertFalse(storage.loadCurrentSessionState().dose2Skipped)
        XCTAssertTrue(storage.exportToCSV().contains("history_correction"))
    }

    func testHistoryRequiresConsentAndUnambiguousUnchangedSession() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let review = try storage.historySnapshot(sessionDate: sessionDate)
        let change = HistoryDoseChange(eventType: "dose2", timestamp: oldDose1.addingTimeInterval(180 * 60), reason: "Forgot to log")
        XCTAssertFalse(storage.saveHistoryDoseChange(change, review: review, confirmed: false, warningConfirmed: true, recordedAt: oldDose1.addingTimeInterval(500 * 60)).isCommitted)
        storage.insertDoseEvent(eventType: "dose1", timestamp: oldDose1, sessionDate: sessionDate, sessionId: "another-night")
        XCTAssertThrowsError(try storage.historySnapshot(sessionDate: sessionDate))
        XCTAssertFalse(storage.saveHistoryDoseChange(change, review: review, confirmed: true, warningConfirmed: true, recordedAt: oldDose1.addingTimeInterval(500 * 60)).isCommitted)
    }

    func testHistoryMissedOutcomeDoesNotInheritTakenAmountOrTimingFlags() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        storage.insertDoseEvent(eventType: "dose2", timestamp: oldDose1.addingTimeInterval(180 * 60), sessionDate: sessionDate, sessionId: sessionId,
                                metadata: "{\"amount_mg\":4500,\"is_late\":true}")
        let review = try storage.historySnapshot(sessionDate: sessionDate)
        let original = try XCTUnwrap(review.events.first { $0.eventType == "dose2" })
        let change = HistoryDoseChange(eventType: "dose2_skipped", timestamp: original.timestamp, replacingEventID: original.id, reason: "Not taken")
        XCTAssertTrue(storage.saveHistoryDoseChange(change, review: review, confirmed: true, warningConfirmed: true, recordedAt: oldDose1.addingTimeInterval(600 * 60)).isCommitted)
        let skip = try XCTUnwrap(try storage.historySnapshot(sessionDate: sessionDate).events.first { $0.eventType == "dose2_skipped" })
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(skip.metadata!.utf8)) as? [String: Any])
        XCTAssertNil(object["amount_mg"])
        XCTAssertNil(object["is_late"])
        XCTAssertTrue(skip.metadata!.contains("4500"), "The original belongs in correction history only")
    }

    private let sessionId = "transaction-session"
    private let sessionDate = "2026-08-31"
    private let oldDose1 = Date(timeIntervalSince1970: 1_788_200_000)

    func test_databaseOpenFailure_returnsTypedFailureWithoutPublishingState() throws {
        let storage = EventStorage(
            dbPath: ":memory:",
            medicationFaultInjector: { point in
                guard point == .open else { return nil }
                return MedicationStorageInjectedFailure(
                    code: .databaseUnavailable,
                    sqliteCode: SQLITE_CANTOPEN,
                    detail: "Injected database-open failure"
                )
            }
        )

        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        let failure = try requireFailure(result, code: .databaseUnavailable, stage: .open)
        XCTAssertEqual(failure.sqliteCode, SQLITE_CANTOPEN)
        XCTAssertNil(storage.db)
        XCTAssertNil(storage.loadCurrentSessionState().dose1Time)
    }

    func test_diskFullDuringReplacement_rollsBackDeleteAndPreservesAcknowledgedDose() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let replacement = oldDose1.addingTimeInterval(600)
        storage.medicationFaultInjector = { point in
            guard point == .insert else { return nil }
            return MedicationStorageInjectedFailure(
                code: .diskFull,
                sqliteCode: SQLITE_FULL,
                detail: "Injected full disk"
            )
        }

        let result = storage.saveDose1(
            timestamp: replacement,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .diskFull, stage: .insert)
        assertOnlyAcknowledgedDose1(in: storage)
    }

    func test_corruptionAtTransactionBegin_preservesAcknowledgedDose() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        storage.medicationFaultInjector = { point in
            guard point == .begin else { return nil }
            return MedicationStorageInjectedFailure(
                code: .corrupted,
                sqliteCode: SQLITE_CORRUPT,
                detail: "Injected corruption"
            )
        }

        let result = storage.saveDose1(
            timestamp: oldDose1.addingTimeInterval(600),
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .corrupted, stage: .begin)
        assertOnlyAcknowledgedDose1(in: storage)
    }

    func test_insertFailure_leavesNoPartialEventOrSnapshot() throws {
        let storage = EventStorage.inMemory()
        storage.medicationFaultInjector = { point in
            guard point == .insert else { return nil }
            return MedicationStorageInjectedFailure(
                code: .statement,
                detail: "Injected insert failure"
            )
        }

        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .statement, stage: .insert)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).isEmpty)
        XCTAssertNil(storage.loadCurrentSessionState().dose1Time)
    }

    func test_snapshotUpdateFailure_rollsBackInsertedEvent() throws {
        let storage = EventStorage.inMemory()
        storage.medicationFaultInjector = { point in
            guard point == .update else { return nil }
            return MedicationStorageInjectedFailure(
                code: .io,
                sqliteCode: SQLITE_IOERR,
                detail: "Injected snapshot update failure"
            )
        }

        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .io, stage: .update)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).isEmpty)
        XCTAssertNil(storage.loadCurrentSessionState().dose1Time)
    }

    func test_commitFailure_rollsBackReplacementAndPreservesAcknowledgedDose() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        storage.medicationFaultInjector = { point in
            guard point == .commit else { return nil }
            return MedicationStorageInjectedFailure(
                code: .transaction,
                detail: "Injected commit failure"
            )
        }

        let result = storage.saveDose1(
            timestamp: oldDose1.addingTimeInterval(900),
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .transaction, stage: .commit)
        assertOnlyAcknowledgedDose1(in: storage)
    }

    func test_dose1ReplacementCannotDeleteCommittedDose2Outcome() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let dose2 = oldDose1.addingTimeInterval(165 * 60)
        XCTAssertTrue(storage.saveDose2(
            timestamp: dose2,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        ).isCommitted)

        let replacement = storage.saveDose1(
            timestamp: oldDose1.addingTimeInterval(300),
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(replacement, code: .precondition, stage: .preflight)
        let events = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        XCTAssertEqual(events.map(\.eventType), ["dose1", "dose2"])
        XCTAssertEqual(events.first?.timestamp, oldDose1)
        XCTAssertEqual(events.last?.timestamp, dose2)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertEqual(storage.loadCurrentSessionState().dose2Time, dose2)
    }

    func test_repeatedOrdinaryDose2WriteFailsWithoutCreatingExtraDose() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let firstDose2 = oldDose1.addingTimeInterval(165 * 60)
        let repeatedDose2 = firstDose2.addingTimeInterval(1)

        XCTAssertTrue(storage.saveDose2(
            timestamp: firstDose2,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        ).isCommitted)

        let repeatedResult = storage.saveDose2(
            timestamp: repeatedDose2,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        let failure = try requireFailure(repeatedResult, code: .precondition, stage: .preflight)
        XCTAssertEqual(
            failure.detail,
            "Dose 2 is already recorded. Use the explicit extra-dose confirmation or Edit to correct it."
        )
        let events = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        XCTAssertEqual(events.filter { $0.eventType == "dose2" }.count, 1)
        XCTAssertFalse(events.contains { $0.eventType == "extra_dose" })
        XCTAssertEqual(storage.loadCurrentSessionState().dose2Time, firstDose2)
    }

    func test_rollbackFailure_isReportedAndLeavesNoAcknowledgedMutation() throws {
        let storage = EventStorage.inMemory()
        storage.medicationFaultInjector = { point in
            switch point {
            case .insert:
                return MedicationStorageInjectedFailure(
                    code: .statement,
                    detail: "Injected insert failure"
                )
            case .rollback:
                return MedicationStorageInjectedFailure(
                    code: .transaction,
                    detail: "Injected rollback verification failure"
                )
            default:
                return nil
            }
        }

        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .transaction, stage: .rollback)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).isEmpty)
        XCTAssertNil(storage.loadCurrentSessionState().dose1Time)
    }

    func test_preflightFailure_doesNotBeginMedicationWrite() throws {
        let storage = EventStorage.inMemory()
        storage.medicationFaultInjector = { point in
            guard point == .preflight else { return nil }
            return MedicationStorageInjectedFailure(
                code: .precondition,
                detail: "Injected stale-state preflight"
            )
        }

        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .precondition, stage: .preflight)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).isEmpty)
    }

    func test_repositoryPublishesOnlyAfterCommit_forDose1Dose2SnoozeAndSkip() throws {
        let storage = EventStorage.inMemory()
        let now = oldDose1.addingTimeInterval(160 * 60)
        let repository = makeRepository(storage: storage, now: now)
        let initialResult = repository.setDose1Time(oldDose1)
        XCTAssertTrue(initialResult.isCommitted)
        let acknowledgedSessionId = try XCTUnwrap(repository.activeSessionId)
        let acknowledgedSessionDate = try XCTUnwrap(repository.activeSessionDate)

        storage.medicationFaultInjector = { point in
            guard point == .insert else { return nil }
            return MedicationStorageInjectedFailure(
                code: .statement,
                detail: "Injected live-action insert failure"
            )
        }

        let replacement = repository.setDose1Time(oldDose1.addingTimeInterval(60))
        _ = try requireFailure(replacement, code: .statement, stage: .insert)
        XCTAssertEqual(repository.dose1Time, oldDose1)
        XCTAssertEqual(repository.activeSessionId, acknowledgedSessionId)
        XCTAssertEqual(repository.activeSessionDate, acknowledgedSessionDate)

        let dose2 = repository.setDose2Time(now)
        _ = try requireFailure(dose2, code: .statement, stage: .insert)
        XCTAssertNil(repository.dose2Time)

        let snooze = repository.incrementSnoozeMutationIfActive()
        _ = try requireFailure(snooze, code: .statement, stage: .insert)
        XCTAssertEqual(repository.snoozeCount, 0)

        let skip = repository.skipDose2()
        _ = try requireFailure(skip, code: .statement, stage: .insert)
        XCTAssertFalse(repository.dose2Skipped)
        XCTAssertEqual(repository.lastMedicationMutationError?.stage, .insert)

        let events = storage.fetchDoseEvents(
            sessionId: acknowledgedSessionId,
            sessionDate: acknowledgedSessionDate
        )
        XCTAssertEqual(events.map(\.eventType), ["dose1"])
        XCTAssertEqual(events.first?.timestamp, oldDose1)
    }

    func test_failedReplacement_survivesRestartAsLastAcknowledgedState() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dosetap-medication-transaction-\(UUID().uuidString).sqlite")
        let paths = [baseURL.path, baseURL.path + "-wal", baseURL.path + "-shm"]
        defer {
            for path in paths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        do {
            let storage = EventStorage(dbPath: baseURL.path)
            try seedDose1(in: storage)
            storage.medicationFaultInjector = { point in
                guard point == .commit else { return nil }
                return MedicationStorageInjectedFailure(
                    code: .transaction,
                    detail: "Injected restart-boundary commit failure"
                )
            }
            let failed = storage.saveDose1(
                timestamp: oldDose1.addingTimeInterval(1_200),
                sessionId: sessionId,
                sessionDateOverride: sessionDate
            )
            _ = try requireFailure(failed, code: .transaction, stage: .commit)
        }

        let restartedStorage = EventStorage(dbPath: baseURL.path)
        assertOnlyAcknowledgedDose1(in: restartedStorage)
        let restartedRepository = makeRepository(
            storage: restartedStorage,
            now: oldDose1.addingTimeInterval(160 * 60)
        )
        XCTAssertEqual(restartedRepository.dose1Time, oldDose1)
        XCTAssertNil(restartedRepository.dose2Time)
    }

    func test_coordinatorPersistenceFailure_returnsRetryAndTriggersNoSuccessEffects() async throws {
        let storage = EventStorage.inMemory()
        let now = oldDose1
        let repository = makeRepository(storage: storage, now: now)
        storage.medicationFaultInjector = { point in
            guard point == .insert else { return nil }
            return MedicationStorageInjectedFailure(
                code: .diskFull,
                sqliteCode: SQLITE_FULL,
                detail: "Injected full disk"
            )
        }

        let notificationCenter = MedicationMutationNotificationCenter()
        let defaultsName = "MedicationMutationTransactionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let alarm = AlarmService(
            notificationClient: notificationCenter,
            defaults: defaults,
            nowProvider: { now },
            timeZoneProvider: { TimeZone(secondsFromGMT: 0)! },
            configurationProvider: {
                AlarmConfiguration(
                    notificationsEnabled: true,
                    windowOpenAlert: true,
                    fifteenMinWarning: true,
                    fiveMinWarning: true,
                    soundEnabled: false,
                    criticalAlertsEnabled: false,
                    snoozeDurationMinutes: 10,
                    maxSnoozes: 3
                )
            }
        )
        let core = DoseTapCore()
        core.setSessionRepository(repository)
        let undo = UndoStateManager()
        let coordinator = DoseActionCoordinator(
            core: core,
            alarmService: alarm,
            dateProvider: FixedDateProvider(date: now),
            undoState: undo,
            sessionRepo: repository
        )
        let diagnosticSessionId = repository.currentSessionIdString()
        let diagnosticEventsPath = await DiagnosticLogger.shared.eventsFilePath(
            for: diagnosticSessionId
        )
        try? FileManager.default.removeItem(at: diagnosticEventsPath.deletingLastPathComponent())
        defer {
            try? FileManager.default.removeItem(
                at: diagnosticEventsPath.deletingLastPathComponent()
            )
        }
        var hapticCount = 0
        coordinator.hapticObserver = { _ in hapticCount += 1 }

        let result = await coordinator.takeDose1()

        XCTAssertEqual(
            result,
            .retryRequired(message: "The dose was not saved because device storage is full. Free space, then retry.")
        )
        XCTAssertNil(repository.dose1Time)
        XCTAssertNil(undo.currentAction)
        XCTAssertEqual(hapticCount, 0)
        XCTAssertTrue(notificationCenter.requestsByIdentifier.isEmpty)
        XCTAssertFalse(alarm.alarmScheduled)
        XCTAssertFalse(alarm.reminderScheduled)

        var actionEntries = try diagnosticActionEntries(at: diagnosticEventsPath)
        XCTAssertEqual(actionEntries.map(\.event), [.doseActionAttempted, .doseActionFailed])
        XCTAssertEqual(Set(actionEntries.compactMap(\.actionId)).count, 1)
        XCTAssertEqual(actionEntries.last?.mutationFailureCode, "disk_full")

        storage.medicationFaultInjector = nil
        let retryResult = await coordinator.takeDose1()
        XCTAssertEqual(
            retryResult,
            .attentionRequired(
                message: "Dose 1 was logged. DoseTap could not verify every required notification. Retry the alarm."
            )
        )

        actionEntries = try diagnosticActionEntries(at: diagnosticEventsPath)
        XCTAssertEqual(actionEntries.count, 4)
        XCTAssertEqual(
            actionEntries.map(\.event),
            [.doseActionAttempted, .doseActionFailed, .doseActionAttempted, .doseActionCommitted]
        )
        let actionIds = Set(actionEntries.compactMap(\.actionId))
        XCTAssertEqual(actionIds.count, 2)
        for actionId in actionIds {
            XCTAssertEqual(actionEntries.filter { $0.actionId == actionId }.count, 2)
        }
        XCTAssertEqual(hapticCount, 1)
        XCTAssertNotNil(repository.dose1Time)
        XCTAssertNotNil(undo.currentAction)
        XCTAssertTrue(notificationCenter.requestsByIdentifier.isEmpty)
    }

    func test_timeEditFailure_preservesEventSnapshotAndPublishedTime() throws {
        let storage = EventStorage.inMemory()
        let repository = makeRepository(
            storage: storage,
            now: oldDose1.addingTimeInterval(160 * 60)
        )
        XCTAssertTrue(repository.setDose1Time(oldDose1).isCommitted)
        let activeDate = try XCTUnwrap(repository.activeSessionDate)
        storage.medicationFaultInjector = { point in
            guard point == .update else { return nil }
            return MedicationStorageInjectedFailure(
                code: .io,
                sqliteCode: SQLITE_IOERR,
                detail: "Injected edit failure"
            )
        }

        let result = repository.updateDose1Time(
            newTime: oldDose1.addingTimeInterval(300),
            sessionDate: activeDate
        )

        _ = try requireFailure(result, code: .io, stage: .update)
        XCTAssertEqual(repository.dose1Time, oldDose1)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertEqual(
            storage.fetchDoseEvents(sessionId: repository.activeSessionId, sessionDate: activeDate).first?.timestamp,
            oldDose1
        )
    }

    func test_morningReconciliationUpdateFailure_rollsBackEventAndPublishedState() throws {
        let storage = EventStorage.inMemory()
        let repository = makeRepository(
            storage: storage,
            now: oldDose1.addingTimeInterval(160 * 60)
        )
        XCTAssertTrue(repository.setDose1Time(oldDose1).isCommitted)
        let activeDate = try XCTUnwrap(repository.activeSessionDate)
        storage.medicationFaultInjector = { point in
            guard point == .update else { return nil }
            return MedicationStorageInjectedFailure(
                code: .io,
                sqliteCode: SQLITE_IOERR,
                detail: "Injected reconciliation snapshot failure"
            )
        }

        let result = repository.reconcileDose2(
            sessionDate: activeDate,
            takenAt: oldDose1.addingTimeInterval(160 * 60),
            amountMg: 4_500,
            reason: "missed_tap"
        )

        _ = try requireFailure(result, code: .io, stage: .update)
        XCTAssertNil(repository.dose2Time)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time)
        XCTAssertEqual(
            storage.fetchDoseEvents(sessionId: repository.activeSessionId, sessionDate: activeDate).map(\.eventType),
            ["dose1"]
        )
    }

    func test_historicalMorningReconciliation_commitsLedgerWithoutReplacingActiveSnapshot() throws {
        let storage = EventStorage.inMemory()
        let activeRepository = makeRepository(
            storage: storage,
            now: oldDose1.addingTimeInterval(160 * 60)
        )
        XCTAssertTrue(activeRepository.setDose1Time(oldDose1).isCommitted)
        let activeSessionDate = try XCTUnwrap(activeRepository.activeSessionDate)
        let activeSessionId = try XCTUnwrap(activeRepository.activeSessionId)
        let historicalDate = "2026-08-29"
        let historicalDose1 = oldDose1.addingTimeInterval(-48 * 60 * 60)
        let historicalDose2 = historicalDose1.addingTimeInterval(165 * 60)

        let dose1Result = storage.reconcileDoseEvent(
            eventType: .dose1,
            timestamp: historicalDose1,
            sessionDate: historicalDate,
            metadata: #"{"source":"morning_reconciliation"}"#
        )
        let dose2Result = storage.reconcileDoseEvent(
            eventType: .dose2,
            timestamp: historicalDose2,
            sessionDate: historicalDate,
            metadata: #"{"amount_mg":4500}"#
        )

        XCTAssertTrue(dose1Result.isCommitted)
        XCTAssertTrue(dose2Result.isCommitted)
        XCTAssertEqual(
            storage.fetchDoseEvents(sessionId: nil, sessionDate: historicalDate).map(\.eventType),
            ["dose1", "dose2"]
        )
        let activeSnapshot = storage.loadCurrentSessionState()
        XCTAssertEqual(activeSnapshot.sessionId, activeSessionId)
        XCTAssertEqual(activeSnapshot.sessionDate, activeSessionDate)
        XCTAssertEqual(activeSnapshot.dose1Time, oldDose1)
        XCTAssertNil(activeSnapshot.dose2Time)
    }

    func test_annotationFailure_preservesPreviouslyAcknowledgedMetadata() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let dose2 = oldDose1.addingTimeInterval(165 * 60)
        XCTAssertTrue(storage.reconcileDoseEvent(
            eventType: .dose2,
            timestamp: dose2,
            sessionDate: sessionDate,
            sessionId: sessionId,
            metadata: #"{"reason":"original"}"#
        ).isCommitted)
        let originalMetadata = storage.fetchDoseEvents(
            sessionId: sessionId,
            sessionDate: sessionDate
        ).first { $0.eventType == "dose2" }?.metadata
        storage.medicationFaultInjector = { point in
            guard point == .update else { return nil }
            return MedicationStorageInjectedFailure(
                code: .statement,
                detail: "Injected annotation failure"
            )
        }

        let result = storage.updateDose2OutcomeAnnotations(
            sessionDate: sessionDate,
            dose2Metadata: #"{"reason":"replacement"}"#,
            skippedMetadata: nil
        )

        _ = try requireFailure(result, code: .statement, stage: .update)
        let persistedMetadata = storage.fetchDoseEvents(
            sessionId: sessionId,
            sessionDate: sessionDate
        ).first { $0.eventType == "dose2" }?.metadata
        XCTAssertEqual(persistedMetadata, originalMetadata)
    }

    func test_skipCorrectionPreservesOriginalRowAndMetadata() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        XCTAssertTrue(storage.saveDoseSkipped(reason: "original reason", sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        let original = try XCTUnwrap(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).first { $0.eventType == "dose2_skipped" })
        XCTAssertTrue(storage.saveDose2(timestamp: oldDose1.addingTimeInterval(160 * 60), entryMode: .retrospective, recordedAt: oldDose1.addingTimeInterval(300 * 60), sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        let replacement = try XCTUnwrap(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).first { $0.eventType == "dose2" })
        let metadata = try XCTUnwrap(replacement.metadata?.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: metadata) as? [String: Any])
        let correction = try XCTUnwrap(json["correction"] as? [String: Any])
        let previous = try XCTUnwrap(correction["previous_events"] as? [[String: Any]])
        XCTAssertEqual(previous.count, 1)
        XCTAssertEqual(previous.first?["id"] as? String, original.id)
        XCTAssertEqual(previous.first?["metadata"] as? String, original.metadata)
        XCTAssertNotNil(correction["corrected_at_utc"])
    }

    func test_uuidScopedReadsDoNotCombineTwoSessionsOnSameDate() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        XCTAssertTrue(storage.reconcileDoseEvent(eventType: .dose1, timestamp: oldDose1.addingTimeInterval(600), sessionDate: sessionDate, sessionId: "other-session", metadata: nil).isCommitted)
        let original = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        XCTAssertEqual(original.count, 1)
        XCTAssertEqual(original.first?.timestamp, oldDose1)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
    }

    func test_historicalCorrectionDoesNotReopenSessionOrReplaceActiveState() throws {
        let storage = EventStorage.inMemory()
        let repository = makeRepository(storage: storage, now: oldDose1.addingTimeInterval(180 * 60))
        XCTAssertTrue(repository.setDose1Time(oldDose1).isCommitted)
        let activeID = repository.activeSessionId
        let previousDate = "2026-08-29"
        let historicalFirst = oldDose1.addingTimeInterval(-48 * 3600)
        XCTAssertTrue(storage.reconcileDoseEvent(eventType: .dose1, timestamp: historicalFirst, sessionDate: previousDate, sessionId: "historical", metadata: nil).isCommitted)
        let occurrence = historicalFirst.addingTimeInterval(14430)
        let result = repository.recordHistoricalDose2Occurrence(sessionId: "historical", sessionDate: previousDate, occurrenceTime: occurrence, confirmed: true, reason: "owner_review", notes: nil)
        XCTAssertTrue(result.isCommitted)
        XCTAssertEqual(repository.activeSessionId, activeID)
        XCTAssertEqual(storage.loadCurrentSessionState().sessionId, activeID)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertNil(repository.dose2Time)
        let recorded = try XCTUnwrap(storage.fetchDoseEvents(sessionId: "historical", sessionDate: previousDate).first { $0.eventType == "dose2" })
        XCTAssertEqual(recorded.timestamp, occurrence)
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(recorded.metadata).utf8)) as? [String: Any])
        XCTAssertEqual(metadata["is_late"] as? Bool, true)
        XCTAssertFalse(repository.recordHistoricalDose2Occurrence(sessionId: "historical", sessionDate: previousDate, occurrenceTime: occurrence, confirmed: true, reason: nil, notes: nil).isCommitted)
    }

    func test_correctionCommitFailureKeepsOriginalSkipAndItsMetadata() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        XCTAssertTrue(storage.saveDoseSkipped(reason: "keep me", sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        let before = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .io, detail: "commit failed") : nil }
        XCTAssertFalse(storage.saveDose2(timestamp: oldDose1.addingTimeInterval(160 * 60), entryMode: .retrospective, sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        XCTAssertEqual(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate), before)
        XCTAssertTrue(storage.loadCurrentSessionState().dose2Skipped)
    }

    func testSkipReplacementDoesNotEraseAnotherUUIDOnSameDate() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        storage.insertDoseEvent(eventType: "dose1", timestamp: oldDose1, sessionDate: sessionDate, sessionId: "other-session")
        storage.insertDoseEvent(eventType: "dose2_skipped", timestamp: oldDose1.addingTimeInterval(200), sessionDate: sessionDate, sessionId: "other-session", metadata: "{\"reason\":\"keep\"}")
        let before = storage.fetchDoseEvents(sessionId: "other-session", sessionDate: sessionDate)
        XCTAssertTrue(storage.saveDoseSkipped(sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        let after = storage.fetchDoseEvents(sessionId: "other-session", sessionDate: sessionDate)
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(after.map(\.metadata), before.map(\.metadata))
    }

    func testSecondaryMedicationWritesPreserveOtherUUIDAndRejectAmbiguousDate() throws {
        let operations: [(String, (EventStorage) -> MedicationMutationResult)] = [
            ("clear dose1", { $0.clearDose1(sessionDateOverride: self.sessionDate, sessionId: self.sessionId) }),
            ("clear dose2", { $0.clearDose2(sessionDateOverride: self.sessionDate, sessionId: self.sessionId) }),
            ("clear skip", { $0.clearSkip(sessionDateOverride: self.sessionDate, sessionId: self.sessionId) }),
            ("clear sequence", { $0.clearDoseSequence(sessionDateOverride: self.sessionDate, sessionId: self.sessionId) }),
            ("undo snooze", { $0.rollbackLatestSnooze(toCount: 0, sessionDateOverride: self.sessionDate, sessionId: self.sessionId) }),
            ("edit dose1", { $0.updateDose1Time(newTime: self.oldDose1.addingTimeInterval(30), sessionDate: self.sessionDate, sessionId: self.sessionId) }),
            ("edit dose2", { $0.updateDose2Time(newTime: self.oldDose1.addingTimeInterval(10000), sessionDate: self.sessionDate, sessionId: self.sessionId) }),
            ("annotations", { $0.updateDose2OutcomeAnnotations(sessionDate: self.sessionDate, dose2Metadata: "{}", skippedMetadata: "{}", sessionId: self.sessionId) })
        ]
        for (name, operation) in operations {
            let storage = EventStorage.inMemory()
            try seedDose1(in: storage)
            for identity in [sessionId, "other-session"] {
                if identity != sessionId { storage.insertDoseEvent(eventType: "dose1", timestamp: oldDose1, sessionDate: sessionDate, sessionId: identity) }
                for (index, type) in ["dose2", "dose2_skipped", "snooze"].enumerated() {
                    storage.insertDoseEvent(eventType: type, timestamp: oldDose1.addingTimeInterval(Double(index + 1) * 10000), sessionDate: sessionDate, sessionId: identity, metadata: "{\"reason\":\"original\"}")
                }
            }
            let before = storage.fetchDoseEvents(sessionId: "other-session", sessionDate: sessionDate)
            XCTAssertFalse(storage.updateDose2Time(newTime: oldDose1, sessionDate: sessionDate).isCommitted, "Ambiguous date must not choose an arbitrary UUID")
            XCTAssertTrue(operation(storage).isCommitted, name)
            let after = storage.fetchDoseEvents(sessionId: "other-session", sessionDate: sessionDate)
            XCTAssertEqual(after.map(\.id), before.map(\.id), name)
            XCTAssertEqual(after.map(\.timestamp), before.map(\.timestamp), name)
            XCTAssertEqual(after.map(\.metadata), before.map(\.metadata), name)
        }
    }

    func testHistoricalTimeEditDoesNotChangeActiveSnapshotOnSameDate() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        storage.insertDoseEvent(eventType: "dose1", timestamp: oldDose1, sessionDate: sessionDate, sessionId: "historical")
        XCTAssertTrue(storage.updateDose1Time(newTime: oldDose1.addingTimeInterval(60), sessionDate: sessionDate, sessionId: "historical").isCommitted)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertEqual(storage.fetchDoseEvents(sessionId: "historical", sessionDate: sessionDate).first?.timestamp, oldDose1.addingTimeInterval(60))
    }

    func testRestoredDatabaseRunsMigrationsDespitePreferencesFromAnotherDatabase() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let flags = ["event_types_normalized_v1", "brief_wake_alias_migration_v1", "session_id_uuid_migration_v1", "event_deduplication_v1"]
        let previous = flags.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(flags, previous) { UserDefaults.standard.set(value, forKey: key) } }
        do {
            let storage = EventStorage(dbPath: path)
            XCTAssertEqual(sqlite3_exec(storage.db, "DELETE FROM schema_migrations", nil, nil, nil), SQLITE_OK)
            storage.insertSleepEvent(id: "legacy-wake", eventType: "brief_wake", timestamp: oldDose1, sessionDate: sessionDate, sessionId: sessionDate)
            storage.insertSleepEvent(id: "unmatched-medication", eventType: "Dose 2", timestamp: oldDose1.addingTimeInterval(9000), sessionDate: sessionDate, sessionId: sessionDate)
            storage.insertSleepEvent(id: "duplicate-dose1", eventType: "Dose 1", timestamp: oldDose1, sessionDate: sessionDate, sessionId: sessionDate)
            storage.insertDoseEvent(eventType: "dose1", timestamp: oldDose1, sessionDate: sessionDate, sessionId: sessionDate)
        }
        for flag in flags { UserDefaults.standard.set(true, forKey: flag) }
        let restored = EventStorage(dbPath: path)
        let doses = restored.fetchDoseEvents(sessionId: nil, sessionDate: sessionDate)
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(doses.first?.sessionId)))
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(restored.db, "SELECT event_type FROM sleep_events WHERE id = 'legacy-wake'", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)), "wake_temp")
        var medicationStatement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(restored.db, "SELECT id FROM sleep_events WHERE id IN ('unmatched-medication','duplicate-dose1')", -1, &medicationStatement, nil), SQLITE_OK)
        defer { sqlite3_finalize(medicationStatement) }
        XCTAssertEqual(sqlite3_step(medicationStatement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(medicationStatement, 0)), "unmatched-medication", "An unmatched legacy medication row must remain available for owner review")
        XCTAssertEqual(sqlite3_step(medicationStatement), SQLITE_DONE)
    }

    func testFailedMigrationDoesNotAdvanceLedgerAndRetriesAfterReopen() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        do {
            let storage = EventStorage(dbPath: path)
            storage.insertSleepEvent(id: "retry-wake", eventType: "brief_wake", timestamp: oldDose1, sessionDate: sessionDate, sessionId: sessionId)
            XCTAssertEqual(sqlite3_exec(storage.db, "DELETE FROM schema_migrations; CREATE TRIGGER reject_migration BEFORE UPDATE ON sleep_events BEGIN SELECT RAISE(ABORT, 'injected migration failure'); END", nil, nil, nil), SQLITE_OK)
        }
        do {
            let failed = EventStorage(dbPath: path)
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(failed.db, "SELECT COUNT(*) FROM schema_migrations WHERE id IN ('event_types_normalized_v1','brief_wake_alias_migration_v1')", -1, &statement, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
            XCTAssertEqual(sqlite3_column_int(statement, 0), 0)
            sqlite3_finalize(statement)
            XCTAssertEqual(sqlite3_exec(failed.db, "DROP TRIGGER reject_migration", nil, nil, nil), SQLITE_OK)
        }
        let retried = EventStorage(dbPath: path)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(retried.db, "SELECT COUNT(*) FROM schema_migrations WHERE id IN ('event_types_normalized_v1','brief_wake_alias_migration_v1')", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 2)
    }

    func testWorkScheduleSaveFailurePreservesPreviousPlan() throws {
        let storage = EventStorage.inMemory()
        let first = WorkWakeSchedule(timeZoneIdentifier: "America/New_York", workingWeekdays: [2, 4, 6], wakeMinutes: 420)
        XCTAssertTrue(storage.saveWorkWakeSchedule(first).isCommitted)
        var changed = first
        changed.exceptions["2026-09-04"] = WorkWakeException(isWorking: false, wakeMinutes: nil)
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .io, detail: "work schedule commit failed") : nil }
        XCTAssertFalse(storage.saveWorkWakeSchedule(changed).isCommitted)
        XCTAssertEqual(try storage.loadWorkWakeSchedule(), first)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: nil, sessionDate: sessionDate).isEmpty)
    }

    func testStaleWorkPlanEditorCannotEraseNewDatedException() throws {
        let storage = EventStorage.inMemory()
        let repository = makeRepository(storage: storage, now: oldDose1)
        XCTAssertTrue(repository.saveWorkWakeSchedule(WorkWakeSchedule(workingWeekdays: [6])).isCommitted)
        var stale = try repository.workWakeSchedule()
        var current = stale
        current.exceptions["2026-09-04"] = WorkWakeException(isWorking: false, wakeMinutes: nil)
        XCTAssertTrue(repository.saveWorkWakeSchedule(current).isCommitted)
        stale.wakeMinutes = 480
        XCTAssertFalse(repository.saveWorkWakeSchedule(stale).isCommitted)
        XCTAssertEqual(try repository.workWakeSchedule().exceptions["2026-09-04"]?.isWorking, false)
    }

    func testWorkScheduleDatedExceptionSurvivesStorageReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("schedule.sqlite").path
        var plan = WorkWakeSchedule(timeZoneIdentifier: "America/New_York", workingWeekdays: [6], target: .wakeBuffer, bufferMinutes: 120)
        plan.exceptions["2026-09-04"] = WorkWakeException(isWorking: false, wakeMinutes: 480)
        do {
            let storage = EventStorage(dbPath: path)
            XCTAssertTrue(storage.saveWorkWakeSchedule(plan).isCommitted)
        }
        let reopened = EventStorage(dbPath: path)
        XCTAssertEqual(try reopened.loadWorkWakeSchedule(), plan)
    }

    private func makeRepository(storage: EventStorage, now: Date) -> SessionRepository {
        SessionRepository(
            storage: storage,
            notificationScheduler: FakeNotificationScheduler(),
            clock: { now },
            timeZoneProvider: { TimeZone(secondsFromGMT: 0)! },
            rolloverHour: 18
        )
    }

    private func seedDose1(in storage: EventStorage) throws {
        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate,
            sessionStart: oldDose1
        )
        XCTAssertTrue(result.isCommitted)
        _ = try XCTUnwrap(result.receipt)
    }

    private func assertOnlyAcknowledgedDose1(
        in storage: EventStorage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let events = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        XCTAssertEqual(events.count, 1, file: file, line: line)
        XCTAssertEqual(events.first?.eventType, "dose1", file: file, line: line)
        XCTAssertEqual(events.first?.timestamp, oldDose1, file: file, line: line)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1, file: file, line: line)
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time, file: file, line: line)
    }

    private func diagnosticActionEntries(at path: URL) throws -> [DiagnosticLogEntry] {
        let content = try String(contentsOf: path, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try content
            .split(separator: "\n")
            .map { try decoder.decode(DiagnosticLogEntry.self, from: Data($0.utf8)) }
            .filter {
                $0.event == .doseActionAttempted
                    || $0.event == .doseActionCommitted
                    || $0.event == .doseActionFailed
            }
    }

    @discardableResult
    private func requireFailure(
        _ result: MedicationMutationResult,
        code: MedicationMutationFailure.Code,
        stage: MedicationMutationFailure.Stage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> MedicationMutationFailure {
        let failure = try XCTUnwrap(result.failure, file: file, line: line)
        XCTAssertEqual(failure.code, code, file: file, line: line)
        XCTAssertEqual(failure.stage, stage, file: file, line: line)
        return failure
    }
}
