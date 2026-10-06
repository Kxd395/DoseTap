import XCTest
import Combine
import DoseCore
import UserNotifications
import SQLite3
@testable import DoseTap

@MainActor
final class DaytimePromptServiceTests: XCTestCase {
    typealias Client = SupplyReminderServiceTests.Client
    let now = ISO8601DateFormatter().date(from: "2035-10-04T10:00:00Z")!.addingTimeInterval(0.123456)
    func enable(_ service: DaytimePromptService) async -> Bool {
        await service.change { try $0.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now) }
    }
    func testRandomizedWakeQueuesStableWindowsAndManualCheckInCancelsOnlyCurrentWindow() async throws {
        var clock = now
        let repo = SessionRepository(storage: .inMemory(), clock: { clock }), client = Client()
        let key = DaytimePromptRule.dayKey(now, timeZone: "UTC")
        let context = DaytimePromptAnchorContext(dayKey: key, timeZone: "UTC", working: true,
            mainWake: try DaytimeAnchorSource(id: "wake", revision: "r1", at: now))
        let service = DaytimePromptService(repository: repo, client: client, now: { clock }, contexts: { _, _, _ in [context] })
        let saved = await service.change {
            $0.quietStart = 0; $0.quietEnd = 0
            try $0.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: self.now,
                rule: DaytimePromptRule(anchor: .mainWake, randomizedWake: .init(workBedtimeMinute: 60)))
        }
        XCTAssertTrue(saved)
        XCTAssertEqual(client.requests.count, 3)
        let first = service.ledger.prompts
        await service.reconcile()
        XCTAssertEqual(service.ledger.prompts, first)
        clock = first[0].windowEnd!
        let queued = Set(client.requests.keys)
        await service.handle(promptID: first[0].id, action: "daytime_later")
        XCTAssertEqual(Set(client.requests.keys), queued, "An unavailable deferral must preserve other windows")
        clock = first[0].windowStart!
        let entry = try DaytimeCheckIn(assessedAt: clock, recordedAt: clock, timeZoneIdentifier: "UTC", response: 4, status: .answered)
        try repo.saveDaytimeCheckIn(entry)
        await service.reconcile()
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(service.ledger.prompts[0].assessmentID, entry.id)
        XCTAssertEqual(try repo.daytimeCheckIns().revisions.first?.origin, entry.origin)
        XCTAssertTrue(service.ledger.prompts.dropFirst().allSatisfy { $0.isOutstanding })
    }
    func testVerifiedQueueReportsNextFutureAttemptAndClearsOnPause() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        var clock = now
        let service = DaytimePromptService(repository: repo, client: client, now: { clock })
        XCTAssertNil(service.nextReminderAt)
        XCTAssertNil(service.lastCheckedAt)
        let enabled = await enable(service)
        XCTAssertTrue(enabled)
        let dates = service.ledger.prompts.map(\.nextAttemptAt).sorted()
        XCTAssertEqual(service.nextReminderAt, dates.first)
        XCTAssertEqual(service.scheduledThrough, dates.last)
        XCTAssertEqual(service.lastCheckedAt, clock)
        clock = try XCTUnwrap(dates.first)
        XCTAssertEqual(service.nextReminderAt, dates[1])
        let paused = await service.change { $0.enabled = false }
        XCTAssertTrue(paused)
        XCTAssertNil(service.nextReminderAt)
        XCTAssertNil(service.scheduledThrough)
        XCTAssertEqual(service.lastCheckedAt, clock)
    }
    func testUnreadableRoutineBlocksConfigurationUntilSuccessfulRetry() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        XCTAssertFalse(service.hasLoadedLedger)
        _ = await enable(service)
        XCTAssertTrue(service.hasLoadedLedger)
        let saved = try repo.daytimePrompts()
        XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE daytime_prompt_state SET payload = 'invalid' WHERE id = 1", nil, nil, nil), SQLITE_OK)
        await service.reconcile()
        XCTAssertFalse(service.hasLoadedLedger)
        XCTAssertNil(service.nextReminderAt)
        XCTAssertTrue(service.status.contains("failed"))
        try repo.saveDaytimePrompts(saved)
        await service.reconcile()
        XCTAssertTrue(service.hasLoadedLedger)
        XCTAssertEqual(service.ledger.current, saved.current)
        XCTAssertNotNil(service.nextReminderAt)
    }
    func testDeniedPermissionAndFailedRefreshClearVerifiedQueue() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        _ = await enable(service)
        XCTAssertNotNil(service.nextReminderAt)
        client.authorization = .denied
        await service.reconcile()
        XCTAssertEqual(service.notificationPermission, .denied)
        XCTAssertNil(service.nextReminderAt)
        XCTAssertNil(service.scheduledThrough)
        client.authorization = .authorized
        await service.reconcile()
        XCTAssertNotNil(service.nextReminderAt)
        client.dropsAdds = true
        await service.reconcile()
        XCTAssertNil(service.nextReminderAt)
        XCTAssertNil(service.scheduledThrough)
        XCTAssertTrue(service.status.contains("failed"))
    }
    func testSevenDayRetryPreservesDoseRequestsAndNoSensitiveContent() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        client.requests["dosetap_dose2_alarm"] = UNNotificationRequest(identifier: "dosetap_dose2_alarm", content: UNMutableNotificationContent(), trigger: nil)
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        let saved = await enable(service); XCTAssertTrue(saved)
        XCTAssertEqual(client.requests.count, 8)
        let first = Set(client.requests.keys)
        await service.reconcile()
        XCTAssertEqual(Set(client.requests.keys), first)
        XCTAssertFalse(client.removed.contains("dosetap_dose2_alarm"))
        XCTAssertEqual(try repo.daytimePrompts().prompts.count, 7)
        for request in client.requests.values where DaytimePromptService.owns(request.identifier) {
            XCTAssertNil(request.content.sound)
            XCTAssertEqual(request.content.interruptionLevel, .passive)
            XCTAssertEqual(request.content.userInfo.count, 1)
            XCTAssertNotNil(request.content.userInfo["prompt_id"])
        }
    }
    func testFullQueueClearsOldVerificationAndPreservesOtherOwners() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        _ = await enable(service)
        XCTAssertNotNil(service.nextReminderAt)
        for index in 0..<64 {
            let id = "other-owner-\(index)"
            client.requests[id] = UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
        }
        await service.reconcile()
        XCTAssertNil(service.nextReminderAt)
        XCTAssertNil(service.scheduledThrough)
        XCTAssertTrue(service.status.contains("queue is full"))
        XCTAssertEqual(client.requests.count, 64)
        XCTAssertFalse(client.requests.keys.contains(where: DaytimePromptService.owns))
    }
    func testPermissionDenialQuietHoursAndSleepSuppressWithoutAssessment() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        client.authorization = .denied
        _ = await enable(service)
        XCTAssertTrue(client.requests.isEmpty)
        client.authorization = .authorized
        _ = await service.change { value in
            value.quietStart = 13 * 60; value.quietEnd = 15 * 60
        }
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(try repo.daytimePrompts().prompts.allSatisfy { $0.status == .suppressed && $0.assessmentID == nil })
        repo.setDose1Time(now)
        _ = await service.change { value in
            value.quietStart = 0; value.quietEnd = 0
            try value.configure(hour: 15, minute: 0, timeZone: "UTC", enabled: true, at: now)
        }
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(service.status.contains("sleep"))
        XCTAssertNil(service.nextReminderAt)
        XCTAssertNil(service.scheduledThrough)
    }
    func testSilentDropAndWriteFailureDoNotClaimScheduledSuccess() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        client.dropsAdds = true
        let dropped = await enable(service)
        XCTAssertFalse(dropped)
        XCTAssertNil(service.scheduledThrough)
        let before = try repo.daytimePrompts()
        XCTAssertEqual(sqlite3_exec(storage.db, "PRAGMA query_only = ON", nil, nil, nil), SQLITE_OK)
        let failed = await service.change { $0.enabled = false }
        XCTAssertFalse(failed)
        XCTAssertEqual(try repo.daytimePrompts(), before)
    }
    func testReportedFinalWakeEndsHistoricalMainSleepSuppression() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now }), client = Client()
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('reported-wake','2035-10-03','2035-10-04T00:00:00.000Z'); INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('lights','lights_out','2035-10-04T01:00:00.000Z','2035-10-03')", nil, nil, nil), SQLITE_OK)
        var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-4 * 3600)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "", recordedAt: now).isCommitted)
        XCTAssertFalse(repo.daytimePromptSleepActive, "An explicitly reported final wake must end earlier main-sleep suppression after rollover")
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        let saved = await enable(service)
        XCTAssertTrue(saved); XCTAssertEqual(client.requests.count, 7)
        XCTAssertNotNil(service.nextReminderAt)
    }
    func testReconciliationQueryCountDoesNotGrowWithNightHistory() async throws {
        func measuredReads(nights: Int, wakeBased: Bool) async throws -> Int {
            let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now })
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            for offset in 1...nights {
                let day = calendar.date(byAdding: .day, value: -offset, to: now)!
                let key = DaytimePromptRule.dayKey(day, timeZone: "UTC")
                let id = "wake-\(offset)"
                XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('\(id)','\(key)','\(AppFormatters.iso8601Fractional.string(from: day))')", nil, nil, nil), SQLITE_OK)
                var diary = NightOutcomeDiary(); diary.finalWakeAt = day.addingTimeInterval(22 * 3600)
                XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: key), reason: "", recordedAt: now).isCommitted)
            }
            XCTAssertEqual(try repo.daytimeMainWakeSources(asOf: now).count, nights)
            let reads = UnsafeMutablePointer<Int>.allocate(capacity: 1); reads.initialize(to: 0)
            defer { sqlite3_trace_v2(storage.db, 0, nil, nil); reads.deinitialize(count: 1); reads.deallocate() }
            sqlite3_trace_v2(storage.db, UInt32(SQLITE_TRACE_STMT), { _, context, statement, _ in
                if let statement, let sql = sqlite3_sql(OpaquePointer(statement)),
                   String(cString: sql).trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("SELECT") {
                    context?.assumingMemoryBound(to: Int.self).pointee += 1
                }
                return SQLITE_OK
            }, reads)
            let client = Client(), service = DaytimePromptService(repository: repo, client: client, now: { self.now })
            let saved = await service.change {
                $0.quietStart = 0; $0.quietEnd = 0
                try $0.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: self.now,
                    rule: wakeBased ? DaytimePromptRule(anchor: .mainWake) : nil)
            }
            XCTAssertTrue(saved); XCTAssertNotNil(service.nextReminderAt)
            return reads.pointee
        }
        for wakeBased in [false, true] {
            let small = try await measuredReads(nights: 4, wakeBased: wakeBased)
            let large = try await measuredReads(nights: 40, wakeBased: wakeBased)
            NSLog("%@", "Daytime reminder query probe: wakeBased=\(wakeBased), nights=4/40, SELECT reads=\(small)/\(large)")
            XCTAssertEqual(large, small, "Reconciliation queries must stay bounded as retained history grows; wakeBased=\(wakeBased)")
        }
    }
    func testUnreadableRealWakeContextInvalidatesPreviouslyVerifiedQueue() async throws {
        for randomized in [false, true] {
            let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now }), client = Client()
            XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('real-wake','2035-10-03','2035-10-04T00:00:00.000Z')", nil, nil, nil), SQLITE_OK)
            var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-7200)
            XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "", recordedAt: now).isCommitted)
            var work = WorkContextDocument()
            work.occurrences = [WorkOccurrence(workDate: "2035-10-04", timeZoneIdentifier: "UTC", plannedWorking: true, recordedAt: now)]
            try storage.saveWorkContext(work, expectedRevision: nil)
            let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
            let saved = await service.change {
                $0.quietStart = 0; $0.quietEnd = 0
                try $0.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: self.now,
                    rule: DaytimePromptRule(anchor: .mainWake, randomizedWake: randomized ? .init(workBedtimeMinute: 60) : nil))
            }
            XCTAssertTrue(saved); XCTAssertNotNil(service.nextReminderAt)
            XCTAssertTrue(client.requests.keys.contains(where: DaytimePromptService.owns))
            client.requests["dose-owner"] = UNNotificationRequest(identifier: "dose-owner", content: UNMutableNotificationContent(), trigger: nil)
            let retained = try repo.daytimePrompts()
            XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE checkin_submissions SET responses_json='invalid JSON' WHERE checkin_type='night_outcome'", nil, nil, nil), SQLITE_OK)
            await service.reconcile()
            XCTAssertFalse(client.requests.keys.contains(where: DaytimePromptService.owns))
            XCTAssertNotNil(client.requests["dose-owner"])
            XCTAssertNil(service.nextReminderAt); XCTAssertNil(service.scheduledThrough)
            XCTAssertTrue(service.status.contains("failed"))
            XCTAssertEqual(try repo.daytimePrompts(), retained)
        }
    }
    func testUnreadableWakeRetriesOnlyCancellationAndBoundsPersistentFailure() async throws {
        for randomized in [false, true] {
            for persistent in [false, true] {
                let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now }), client = Client()
                XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('real-wake','2035-10-03','2035-10-04T00:00:00Z')", nil, nil, nil), SQLITE_OK)
                var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-7200)
                XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "", recordedAt: now).isCommitted)
                var work = WorkContextDocument()
                work.occurrences = [WorkOccurrence(workDate: "2035-10-04", timeZoneIdentifier: "UTC", plannedWorking: true, recordedAt: now)]
                try storage.saveWorkContext(work, expectedRevision: nil)
                let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
                let enabled = await service.change {
                    $0.quietStart = 0; $0.quietEnd = 0
                    try $0.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: self.now,
                        rule: DaytimePromptRule(anchor: .mainWake, randomizedWake: randomized ? .init(workBedtimeMinute: 60) : nil))
                }
                XCTAssertTrue(enabled); XCTAssertNotNil(service.nextReminderAt)
                let owned = client.requests.keys.filter(DaytimePromptService.owns).count
                XCTAssertGreaterThan(owned, 0)
                client.requests["dose-owner"] = UNNotificationRequest(identifier: "dose-owner", content: UNMutableNotificationContent(), trigger: nil)
                client.removed = []; client.ignoresRemovals = true
                client.onPending = { if !persistent && !client.removed.isEmpty { client.ignoresRemovals = false } }
                let retained = try repo.daytimePrompts()
                XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE checkin_submissions SET responses_json='invalid JSON' WHERE checkin_type='night_outcome'", nil, nil, nil), SQLITE_OK)
                let reads = UnsafeMutablePointer<Int>.allocate(capacity: 1); reads.initialize(to: 0)
                defer { sqlite3_trace_v2(storage.db, 0, nil, nil); reads.deinitialize(count: 1); reads.deallocate() }
                sqlite3_trace_v2(storage.db, UInt32(SQLITE_TRACE_STMT), { _, context, statement, _ in
                    if let statement, let sql = sqlite3_sql(OpaquePointer(statement)),
                       String(cString: sql).hasPrefix("SELECT session_date, source_record_id") {
                        context?.assumingMemoryBound(to: Int.self).pointee += 1
                    }
                    return SQLITE_OK
                }, reads)
                await service.reconcile()
                XCTAssertEqual(client.removed.filter(DaytimePromptService.owns).count, owned * 2, "Exactly one cancellation retry")
                XCTAssertEqual(client.requests.keys.contains(where: DaytimePromptService.owns), persistent)
                XCTAssertNotNil(client.requests["dose-owner"]); XCTAssertFalse(client.removed.contains("dose-owner"))
                XCTAssertNil(service.nextReminderAt); XCTAssertNil(service.scheduledThrough)
                XCTAssertEqual(try repo.daytimePrompts(), retained)
                XCTAssertEqual(reads.pointee, 1, "Cancellation retry must not reread or replan the unreadable wake source")
                XCTAssertTrue(service.status.contains("failed"))
                XCTAssertEqual(service.status.contains("Cancellation could not be verified"), persistent)
            }
        }
    }
    func testPersistentCleanupDropsCoalescedRefreshButDrainsExplicitActions() async throws {
        for randomized in [false, true] {
            for variant in [(false, false), (true, false), (false, true), (true, true)] {
                let persistent = variant.0, queueAction = variant.1
                let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now }), client = Client()
                XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('real-wake','2035-10-03','2035-10-04T00:00:00Z')", nil, nil, nil), SQLITE_OK)
                var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-7200)
                XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "", recordedAt: now).isCommitted)
                var work = WorkContextDocument()
                work.occurrences = [WorkOccurrence(workDate: "2035-10-04", timeZoneIdentifier: "UTC", plannedWorking: true, recordedAt: now)]
                try storage.saveWorkContext(work, expectedRevision: nil)
                let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
                let enabled = await service.change {
                    $0.quietStart = 0; $0.quietEnd = 0
                    try $0.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: self.now,
                        rule: DaytimePromptRule(anchor: .mainWake, randomizedWake: randomized ? .init(workBedtimeMinute: 60) : nil))
                }
                XCTAssertTrue(enabled)
                let owned = client.requests.keys.filter(DaytimePromptService.owns).count
                let retained = try repo.daytimePrompts()
                client.requests["dose-owner"] = UNNotificationRequest(identifier: "dose-owner", content: UNMutableNotificationContent(), trigger: nil)
                client.removed = []; client.ignoresRemovals = true
                client.onPending = { if !persistent && !client.removed.isEmpty { client.ignoresRemovals = false } }
                var adds = 0; client.onAdd = { adds += 1 }
                XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE checkin_submissions SET responses_json='invalid JSON' WHERE checkin_type='night_outcome'", nil, nil, nil), SQLITE_OK)
                let reads = UnsafeMutablePointer<Int>.allocate(capacity: 1); reads.initialize(to: 0)
                defer { sqlite3_trace_v2(storage.db, 0, nil, nil); reads.deinitialize(count: 1); reads.deallocate() }
                sqlite3_trace_v2(storage.db, UInt32(SQLITE_TRACE_STMT), { _, context, statement, _ in
                    if let statement, let sql = sqlite3_sql(OpaquePointer(statement)), String(cString: sql).hasPrefix("SELECT session_date, source_record_id") {
                        context?.assumingMemoryBound(to: Int.self).pointee += 1
                    }
                    return SQLITE_OK
                }, reads)
                let entered = expectation(description: "First cleanup read is suspended")
                let extraPass = expectation(description: "No coalesced automatic reconciliation"); extraPass.isInverted = true
                var release: CheckedContinuation<Void, Never>?, pendingCalls = 0, reportedExtraPass = false
                client.onPendingAsync = {
                    pendingCalls += 1
                    if pendingCalls == 1 { await withCheckedContinuation { release = $0; entered.fulfill() } }
                    if pendingCalls > 4 && !reportedExtraPass { reportedExtraPass = true; extraPass.fulfill() }
                }
                let first = Task { await service.reconcile() }
                await fulfillment(of: [entered], timeout: 3)
                XCTAssertTrue(service.isBusy)
                await service.reconcile() // An overlapping lifecycle refresh must be consumed after terminal cleanup.
                var explicit: Task<Void, Never>?
                if queueAction {
                    let queued = expectation(description: "Explicit action entered")
                    explicit = Task { queued.fulfill(); await service.handle(promptID: UUID(), action: "daytime_skip") }
                    await fulfillment(of: [queued], timeout: 3)
                    await Task.yield()
                }
                let blocked = try XCTUnwrap(release); release = nil; blocked.resume()
                await first.value
                if let explicit { await explicit.value }
                await fulfillment(of: [extraPass], timeout: 0.15)
                XCTAssertEqual(reads.pointee, 1)
                XCTAssertEqual(pendingCalls, 4)
                XCTAssertEqual(client.removed.filter(DaytimePromptService.owns).count, owned * 2)
                XCTAssertEqual(client.requests.keys.contains(where: DaytimePromptService.owns), persistent)
                XCTAssertNotNil(client.requests["dose-owner"]); XCTAssertFalse(client.removed.contains("dose-owner"))
                XCTAssertNil(service.nextReminderAt); XCTAssertNil(service.scheduledThrough)
                XCTAssertEqual(try repo.daytimePrompts(), retained); XCTAssertEqual(adds, 0)
                XCTAssertFalse(service.isBusy)
                XCTAssertTrue(service.status.contains(queueAction ? "no longer available" : (persistent ? "Cancellation could not be verified" : "failed")))
                client.onPendingAsync = nil; client.onPending = nil; client.onAdd = nil
            }
        }
    }
    func testHealthyReconciliationStillDrainsCoalescedRefresh() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        let enabled = await enable(service); XCTAssertTrue(enabled)
        let entered = expectation(description: "First cancellation read is suspended")
        let finished = expectation(description: "Both healthy refreshes completed")
        var release: CheckedContinuation<Void, Never>?, pendingCalls = 0, completions = 0, adds = 0
        client.onPendingAsync = {
            pendingCalls += 1
            if pendingCalls == 1 { await withCheckedContinuation { release = $0; entered.fulfill() } }
        }
        client.onAdd = { adds += 1 }
        let observation = service.$isBusy.dropFirst().filter { !$0 }.sink { _ in
            completions += 1
            if completions == 2 { finished.fulfill() }
        }
        defer { observation.cancel(); client.onPendingAsync = nil; client.onAdd = nil }
        let first = Task { await service.reconcile() }
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertTrue(service.isBusy)
        await service.reconcile()
        let blocked = try XCTUnwrap(release); release = nil; blocked.resume()
        await first.value
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(completions, 2); XCTAssertEqual(adds, 14)
        XCTAssertFalse(service.isBusy); XCTAssertNotNil(service.nextReminderAt)
        XCTAssertEqual(client.requests.count, 7)
    }
    func testCommittedLaterPreservesUnverifiedCancellationGuidance() async throws {
        var clock = now
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { clock })
        let enabled = await enable(service); XCTAssertTrue(enabled)
        let prompt = try XCTUnwrap(service.ledger.prompts.first)
        clock = prompt.intendedAt
        client.ignoresRemovals = true; client.removed = []
        await service.handle(promptID: prompt.id, action: "daytime_later")
        let saved = try XCTUnwrap(repo.daytimePrompts().prompts.first { $0.id == prompt.id })
        XCTAssertEqual(saved.status, .deferred)
        XCTAssertTrue(service.status.contains("postponed"))
        XCTAssertTrue(service.status.contains("Cancellation could not be verified"))
        XCTAssertNil(service.nextReminderAt); XCTAssertNil(service.scheduledThrough)
        XCTAssertEqual(client.removed.count, 21, "One normal cancellation and two bounded cleanup attempts; no replanning")
    }
    func testRealWakeCorrectionDuringOSAddInvalidatesBatchSnapshot() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now }), client = Client()
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('real-wake','2035-10-03','2035-10-04T00:00:00.000Z')", nil, nil, nil), SQLITE_OK)
        var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-7200)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "", recordedAt: now).isCommitted)
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        client.onAdd = {
            client.onAdd = nil
            diary.finalWakeAt = self.now.addingTimeInterval(-3600)
            do {
                XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "Wake corrected", recordedAt: self.now).isCommitted)
            } catch { XCTFail("Valid concurrent correction failed: \(error)") }
        }
        let saved = await service.change {
            $0.quietStart = 0; $0.quietEnd = 0
            try $0.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: self.now, rule: DaytimePromptRule(anchor: .mainWake))
        }
        XCTAssertFalse(saved); XCTAssertNil(service.nextReminderAt); XCTAssertNil(service.scheduledThrough)
        XCTAssertFalse(client.requests.keys.contains(where: DaytimePromptService.owns))
        XCTAssertEqual(try repo.daytimeMainWakeSources(asOf: now).first?.at, Date(timeIntervalSince1970: floor(try XCTUnwrap(diary.finalWakeAt).timeIntervalSince1970)))
    }
    func testFutureSleepEventDoesNotSuppressCurrentReminders() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now }), client = Client()
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('future-sleep','lights_out','2035-10-05T01:00:00.000Z','2035-10-04')", nil, nil, nil), SQLITE_OK)
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        _ = await enable(service)
        XCTAssertEqual(client.requests.count, 7)
        XCTAssertNotNil(service.nextReminderAt)
    }
    func testUnreadableSleepEvidenceNeverQueuesReminders() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now }), client = Client()
        XCTAssertEqual(sqlite3_exec(storage.db, "ALTER TABLE sleep_events RENAME TO unavailable_sleep_events", nil, nil, nil), SQLITE_OK)
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        _ = await enable(service)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertNil(service.nextReminderAt)
        XCTAssertTrue(service.status.contains("failed"))
    }
    func testReportedWakePreservesLaterSleepAndUnfinishedNap() throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now })
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('reported-wake','2035-10-03','2035-10-04T00:00:00Z'); INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('lights','LightsOut','2035-10-04T01:00:00Z','2035-10-03')", nil, nil, nil), SQLITE_OK)
        var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-4 * 3600)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "", recordedAt: now).isCommitted)
        XCTAssertFalse(try repo.daytimePromptSleepActive(asOf: now))
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('later-lights','Lights Out','2035-10-04T08:00:00.000Z','2035-10-03')", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(try repo.daytimePromptSleepActive(asOf: now))
        XCTAssertEqual(sqlite3_exec(storage.db, "DELETE FROM sleep_events WHERE id='later-lights'; INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('nap','nap_start','2035-10-04T08:00:00.000Z','2035-10-03')", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(try repo.daytimePromptSleepActive(asOf: now), "Main wake never supplies a missing nap end")
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('nap-end','nap_end','2035-10-04T09:00:00.000Z','2035-10-03')", nil, nil, nil), SQLITE_OK)
        XCTAssertFalse(try repo.daytimePromptSleepActive(asOf: now))
    }
    func testRelevantSleepEvidenceIsNotLimitedByUnrelatedDisplayRows() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now }), client = Client()
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('nap','nap_start','2035-10-04T01:00:00.000Z','2035-10-03'); WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<501) INSERT INTO sleep_events(id,event_type,timestamp,session_date) SELECT 'unrelated-'||x,'bathroom','2035-10-04T09:00:00.000Z','2035-10-03' FROM n", nil, nil, nil), SQLITE_OK)
        XCTAssertFalse(repo.fetchRecentEvents(limit: 500).contains { $0.eventType == "nap_start" })
        XCTAssertTrue(try repo.daytimePromptSleepActive(asOf: now))
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        _ = await enable(service)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(service.status.contains("sleep"))
    }
    func testMalformedSleepOrWakeEvidenceClearsQueueAndForegroundPermission() async throws {
        for malformedWake in [false, true] {
            let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now }), client = Client()
            let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
            _ = await enable(service)
            XCTAssertNotNil(service.nextReminderAt); XCTAssertTrue(service.permitsForegroundPresentation)
            if malformedWake {
                XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('bad','2035-10-03','2035-10-04T00:00:00.000Z')", nil, nil, nil), SQLITE_OK)
                XCTAssertTrue(storage.saveNightOutcome(NightOutcomeDiary(), review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "", recordedAt: now).isCommitted)
                XCTAssertEqual(sqlite3_exec(storage.db, "UPDATE checkin_submissions SET responses_json='invalid JSON' WHERE checkin_type='night_outcome'", nil, nil, nil), SQLITE_OK)
            } else {
                XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('bad','lights_out','invalid date','2035-10-03')", nil, nil, nil), SQLITE_OK)
            }
            XCTAssertThrowsError(try repo.daytimePromptSleepActive(asOf: now))
            XCTAssertFalse(service.permitsForegroundPresentation)
            await service.reconcile()
            XCTAssertTrue(client.requests.isEmpty); XCTAssertNil(service.nextReminderAt)
            XCTAssertTrue(service.status.contains("failed"))
        }
    }
    func testFutureWakeAndEqualTimeEndCannotClearCurrentSleep() throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now })
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('sleep','lights_out','2035-10-04T08:00:00.000Z','2035-10-03'),('future-wake','wake_final','2035-10-05T06:00:00.000Z','2035-10-04')", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(try repo.daytimePromptSleepActive(asOf: now))
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('tied-wake','wakefinal','2035-10-04T08:00:00.000Z','2035-10-03')", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(try repo.daytimePromptSleepActive(asOf: now))
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('wake','Wake Final','2035-10-04T09:00:00.000Z','2035-10-03')", nil, nil, nil), SQLITE_OK)
        XCTAssertFalse(try repo.daytimePromptSleepActive(asOf: now))
        XCTAssertThrowsError(try repo.daytimePromptSleepActive(asOf: Date(timeIntervalSince1970: .nan)))
    }
    func testSleepStateUsesWakeRevisionVisibleAtCapture() throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now })
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('reported-wake','2035-10-03','2035-10-04T00:00:00.000Z'); INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('lights','lights_out','2035-10-04T01:00:00.000Z','2035-10-03')", nil, nil, nil), SQLITE_OK)
        var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-4 * 3600)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "", recordedAt: now).isCommitted)
        diary.finalWakeAt = nil
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "Wake uncertain", recordedAt: now.addingTimeInterval(30)).isCommitted)
        XCTAssertFalse(try repo.daytimePromptSleepActive(asOf: now))
        XCTAssertTrue(try repo.daytimePromptSleepActive(asOf: now.addingTimeInterval(30)))
    }
    func testSleepStartedDuringOSAddCancelsOwnedQueueWithoutVerification() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage, clock: { self.now }), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        client.onAdd = {
            XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_events(id,event_type,timestamp,session_date) VALUES('new-nap','nap_start','2035-10-04T10:00:00.000Z','2035-10-03')", nil, nil, nil), SQLITE_OK)
            client.onAdd = nil
        }
        _ = await enable(service)
        XCTAssertTrue(client.requests.isEmpty); XCTAssertNil(service.nextReminderAt)
        XCTAssertTrue(service.status.contains("sleep"))
        XCTAssertTrue(service.ledger.prompts.allSatisfy { $0.status == .suppressed })
    }
    func testResetDuringSleepCancellationDoesNotRestoreDeletedHistory() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        client.onAdd = { repo.setDose1Time(self.now); client.onAdd = nil }
        var sleepReads = 0
        client.onPending = {
            if repo.daytimePromptSleepActive {
                sleepReads += 1
                if sleepReads == 2 { storage.clearAllData() }
            }
        }
        let saved = await enable(service)
        XCTAssertFalse(saved)
        XCTAssertTrue(try repo.daytimePrompts().prompts.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
    }
    func testFailedCancellationNeverClaimsPausedOrChangesOtherOwners() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        _ = await enable(service)
        client.ignoresRemovals = true
        let paused = await service.change { $0.enabled = false }
        XCTAssertFalse(paused); XCTAssertNil(service.scheduledThrough)
        XCTAssertNil(service.nextReminderAt)
        XCTAssertEqual(client.requests.count, 7)
        let before = try repo.daytimePrompts()
        await service.handle(promptID: UUID(), action: UNNotificationDismissActionIdentifier)
        XCTAssertEqual(try repo.daytimePrompts(), before)
    }
    func testResetDuringOSAddDoesNotRestoreDeletedHistory() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        client.onAdd = { storage.clearAllData() }
        let saved = await enable(service)
        XCTAssertFalse(saved)
        XCTAssertTrue(try repo.daytimePrompts().prompts.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
    }
    func testSubsecondDeferUsesExplicitWholeSecondSchedulingBoundary() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        var clock = now
        let service = DaytimePromptService(repository: repo, client: client, now: { clock })
        _ = await enable(service)
        let prompt = try XCTUnwrap(service.ledger.prompts.first)
        clock = prompt.intendedAt.addingTimeInterval(0.123456)
        await service.handle(promptID: prompt.id, action: "daytime_later")
        XCTAssertFalse(service.status.contains("failed"))
        XCTAssertEqual(service.ledger.prompts.first?.nextAttemptAt,
                       Date(timeIntervalSince1970: ceil(clock.timeIntervalSince1970 + 1800)))
        XCTAssertNotNil(client.requests[DaytimePromptService.requestID + "." + prompt.id.uuidString])
    }

    func testReportedWakeAnchorQueuesOnePreciseSlotAndPreservesRevisionHistory() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let key = DaytimePromptRule.dayKey(now, timeZone: "UTC")
        var source = try DaytimeAnchorSource(id: "main-night", revision: "r1", at: now.addingTimeInterval(-7200))
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now }, contexts: { _, _, _ in
            [DaytimePromptAnchorContext(dayKey: key, timeZone: "UTC", mainWake: source)]
        })
        let saved = await service.change { value in
            try value.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now,
                                rule: DaytimePromptRule(anchor: .mainWake))
        }
        XCTAssertTrue(saved); XCTAssertEqual(client.requests.count, 1)
        let first = try XCTUnwrap(service.ledger.prompts.first)
        XCTAssertEqual(first.anchor?.sourceRevision, "r1")
        XCTAssertTrue(service.protocolLabel(for: first).contains("After main wake + 240 min"))
        source = try DaytimeAnchorSource(id: "main-night", revision: "r2", at: now.addingTimeInterval(-3600))
        await service.reconcile()
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(service.ledger.prompts.first?.status, .suppressed)
        XCTAssertEqual(service.ledger.prompts.last?.anchor?.sourceRevision, "r2")
        XCTAssertEqual(service.protocolLabel(for: first), service.protocolLabel(for: try XCTUnwrap(service.ledger.prompts.last)))
    }
    func testSourceRevisionChangeDuringOSAddFailsClosed() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let key = DaytimePromptRule.dayKey(now, timeZone: "UTC")
        var source = try DaytimeAnchorSource(id: "main-night", revision: "r1", at: now.addingTimeInterval(-7200))
        let revised = try DaytimeAnchorSource(id: "main-night", revision: "r2", at: now.addingTimeInterval(-3600))
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now }, contexts: { _, _, _ in
            [DaytimePromptAnchorContext(dayKey: key, timeZone: "UTC", mainWake: source)]
        })
        client.onAdd = { source = revised }
        let saved = await service.change { value in
            try value.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now,
                                rule: DaytimePromptRule(anchor: .mainWake))
        }
        XCTAssertFalse(saved); XCTAssertNil(service.scheduledThrough)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertNil(service.ledger.prompts.first?.assessmentID)
    }
    func testMissingAnchorStaysUnscheduledWithVisibleReason() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now }, contexts: { _, _, _ in [] })
        let saved = await service.change { value in
            try value.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now,
                                rule: DaytimePromptRule(anchor: .mainWake))
        }
        XCTAssertTrue(saved); XCTAssertTrue(client.requests.isEmpty)
        XCTAssertNil(service.nextReminderAt)
        XCTAssertTrue(service.ledger.prompts.isEmpty)
        XCTAssertTrue(service.anchorAvailability.contains { $0.contains("main-wake observation unavailable") })
    }

    func testSecondFallBackOccurrenceKeepsExplicitAbsoluteAnchor() async throws {
        let clock = ISO8601DateFormatter().date(from: "2035-11-04T05:00:00Z")!
        let wake = ISO8601DateFormatter().date(from: "2035-11-04T04:30:00Z")!
        let intended = ISO8601DateFormatter().date(from: "2035-11-04T06:30:00Z")!
        let source = try DaytimeAnchorSource(id: "fall-back-main-wake", revision: "r1", at: wake)
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { clock }, contexts: { _, _, _ in
            [DaytimePromptAnchorContext(dayKey: "2035-11-04", timeZone: "America/New_York", mainWake: source)]
        })
        let saved = await service.change { value in
            value.quietStart = 0; value.quietEnd = 0
            try value.configure(hour: 14, minute: 0, timeZone: "America/New_York", enabled: true, at: clock,
                                rule: DaytimePromptRule(anchor: .mainWake, wakeOffsetMinutes: 120))
        }
        XCTAssertTrue(saved)
        let prompt = try XCTUnwrap(service.ledger.prompts.first)
        XCTAssertEqual(prompt.intendedAt, intended)
        XCTAssertEqual(prompt.anchorDayKey, "2035-11-04")
        XCTAssertEqual(service.ledger.current?.timeZone, "America/New_York")
        let request = try XCTUnwrap(client.requests[DaytimePromptService.requestID + "." + prompt.id.uuidString])
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.nextTriggerDate(), intended)
        XCTAssertEqual(trigger.dateComponents.timeZone?.secondsFromGMT(for: intended), 0)
    }

    func testRepositoryContextKeepsOriginalWakeIdentityWhenAnotherSourceAppears() throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage)
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO sleep_sessions(session_id,session_date,start_utc) VALUES('original-night','2035-10-03','2035-10-03T23:00:00Z'),('other-night','2035-10-04','2035-10-04T00:00:00Z')", nil, nil, nil), SQLITE_OK)
        var diary = NightOutcomeDiary(); diary.finalWakeAt = now.addingTimeInterval(-7200)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "", recordedAt: now).isCommitted)
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now, rule: DaytimePromptRule(anchor: .mainWake))
        let schedule = try XCTUnwrap(ledger.current)
        _ = ledger.prepareHorizon(at: now, contexts: try repo.daytimePromptContexts(for: schedule, ledger: ledger, asOf: now))
        XCTAssertEqual(ledger.prompts.first?.anchor?.sourceID, "original-night")
        diary.finalWakeAt = now.addingTimeInterval(-3600)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-04"), reason: "", recordedAt: now).isCommitted)
        let key = DaytimePromptRule.dayKey(now, timeZone: "UTC")
        XCTAssertEqual(try repo.daytimePromptContexts(for: schedule, ledger: ledger, asOf: now).first { $0.dayKey == key }?.mainWake?.id, "original-night")
        XCTAssertNil(try repo.daytimePromptContexts(for: schedule, ledger: DaytimePromptLedger(), asOf: now).first { $0.dayKey == key }?.mainWake)
        diary.finalWakeAt = nil
        XCTAssertTrue(storage.saveNightOutcome(diary, review: try storage.nightOutcomeSnapshot(sessionDate: "2035-10-03"), reason: "Wake uncertain", recordedAt: now.addingTimeInterval(1)).isCommitted)
        XCTAssertNil(try repo.daytimePromptContexts(for: schedule, ledger: ledger, asOf: now.addingTimeInterval(1)).first { $0.dayKey == key }?.mainWake)
    }
    func testRepositoryContextIncludesPriorDayReviewedOvernightShift() throws {
        let clock = ISO8601DateFormatter().date(from: "2035-10-04T00:15:00Z")!
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage)
        var work = WorkContextDocument()
        var occurrence = WorkOccurrence(workDate: "2035-10-03", timeZoneIdentifier: "UTC", plannedWorking: true, recordedAt: clock)
        occurrence.scheduledStart = ISO8601DateFormatter().date(from: "2035-10-03T20:00:00Z")!
        occurrence.scheduledEnd = ISO8601DateFormatter().date(from: "2035-10-04T09:00:00Z")!
        occurrence.scheduledTimesReviewed = true; work.occurrences = [occurrence]
        try storage.saveWorkContext(work, expectedRevision: nil)
        var ledger = DaytimePromptLedger()
        try ledger.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: clock, rule: DaytimePromptRule(anchor: .shiftMidpoint))
        let contexts = try repo.daytimePromptContexts(for: XCTUnwrap(ledger.current), ledger: ledger, asOf: clock)
        let source = try XCTUnwrap(contexts.first { $0.dayKey == "2035-10-03" }?.shift)
        XCTAssertEqual(source.id, occurrence.id.uuidString)
        XCTAssertEqual(source.endAt, occurrence.scheduledEnd)
        XCTAssertEqual(ledger.prepareHorizon(at: clock, contexts: contexts).first?.intendedAt,
                       ISO8601DateFormatter().date(from: "2035-10-04T02:30:00Z"))
    }

    func testRejectedMutationAndStaleSkipPreserveVerifiedQueue() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        _ = await enable(service)
        let before = try repo.daytimePrompts(), queued = Set(client.requests.keys), next = service.nextReminderAt
        let rejected = await service.change { _ in throw DaytimeDiaryError.invalid }
        XCTAssertFalse(rejected)
        XCTAssertEqual(Set(client.requests.keys), queued)
        XCTAssertEqual(service.nextReminderAt, next)
        await service.handle(promptID: UUID(), action: "daytime_skip")
        XCTAssertEqual(Set(client.requests.keys), queued)
        XCTAssertEqual(service.nextReminderAt, next)
        XCTAssertEqual(try repo.daytimePrompts(), before)
    }
    func testManualCompletionPrecedesPermissionAndSleepEarlyReturn() async throws {
        for mode in ["permission", "quiet", "sleep"] {
            var clock = now
            let repo = SessionRepository(storage: .inMemory(), clock: { clock }), client = Client()
            let context = DaytimePromptAnchorContext(dayKey: "2035-10-04", timeZone: "UTC", working: true,
                mainWake: try DaytimeAnchorSource(id: "wake", revision: "r1", at: now))
            let service = DaytimePromptService(repository: repo, client: client, now: { clock }, contexts: { _, _, _ in [context] })
            _ = await service.change {
                $0.quietStart = 0; $0.quietEnd = 0
                try $0.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now,
                    rule: DaytimePromptRule(anchor: .mainWake, randomizedWake: .init(workBedtimeMinute: 60)))
            }
            let slot = try XCTUnwrap(service.ledger.prompts.first)
            if mode == "permission" { client.authorization = .denied }
            if mode == "quiet" { _ = await service.change { $0.quietStart = 0; $0.quietEnd = 1439 } }
            if mode == "sleep" { repo.setDose1Time(now) }
            await service.reconcile()
            clock = slot.windowStart!
            let entry = try DaytimeCheckIn(assessedAt: clock, recordedAt: clock, timeZoneIdentifier: "UTC", response: 4, status: .answered)
            try repo.saveDaytimeCheckIn(entry)
            await service.reconcile()
            XCTAssertEqual(service.ledger.prompts.first?.assessmentID, entry.id, mode)
            XCTAssertEqual(service.ledger.prompts.first?.status, .responded, mode)
        }
    }
    func testPartialOSAddTransientFailureGetsOneBoundedRecovery() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        var adds = 0
        client.onAdd = {
            adds += 1
            if adds == 1 { client.failsAdds = true }
        }
        client.onPending = { if client.failsAdds { client.failsAdds = false; client.onAdd = nil } }
        _ = await enable(service)
        XCTAssertEqual(client.requests.count, 7)
        XCTAssertNotNil(service.nextReminderAt)
    }

    func testLaterAtWindowBoundaryUsesOneActionClockSample() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let context = DaytimePromptAnchorContext(dayKey: "2035-10-04", timeZone: "UTC", working: true,
            mainWake: try DaytimeAnchorSource(id: "wake", revision: "r1", at: now))
        var actionClock: Date?, reads = 0
        let service = DaytimePromptService(repository: repo, client: client, now: {
            guard let start = actionClock else { return self.now }
            defer { reads += 1 }
            return start.addingTimeInterval(Double(reads))
        }, contexts: { _, _, _ in [context] })
        _ = await service.change {
            $0.quietStart = 0; $0.quietEnd = 0
            try $0.configure(hour: 14, minute: 0, timeZone: "UTC", enabled: true, at: now,
                rule: DaytimePromptRule(anchor: .mainWake, randomizedWake: .init(workBedtimeMinute: 60)))
        }
        let slot = try XCTUnwrap(service.ledger.prompts.first)
        let fire = Date(timeIntervalSince1970: floor(slot.windowEnd!.timeIntervalSince1970))
        actionClock = fire.addingTimeInterval(-1800)
        await service.handle(promptID: slot.id, action: "daytime_later")
        XCTAssertEqual(service.ledger.prompts.first?.nextAttemptAt, fire)
        XCTAssertEqual(service.ledger.prompts.first?.status, .deferred)
        XCTAssertEqual(client.requests.count, 3)
    }
    func testPersistentOSFailureStopsAfterOneRecovery() async throws {
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        let service = DaytimePromptService(repository: repo, client: client, now: { self.now })
        var adds = 0
        client.dropsAdds = true; client.onAdd = { adds += 1 }
        let saved = await enable(service)
        XCTAssertFalse(saved)
        XCTAssertEqual(adds, 14, "Seven-request initial attempt plus exactly one recovery")
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertNil(service.nextReminderAt)
        XCTAssertTrue(service.status.contains("failed"))
    }

    func testCommittedLaterAndOpenRemainAcceptedWhenOSVerificationFails() async throws {
        for action in ["daytime_later", "open"] {
            var clock = now
            let repo = SessionRepository(storage: .inMemory()), client = Client()
            let service = DaytimePromptService(repository: repo, client: client, now: { clock })
            _ = await enable(service)
            let slot = try XCTUnwrap(service.ledger.prompts.first)
            clock = slot.intendedAt
            client.dropsAdds = true
            await service.handle(promptID: slot.id, action: action)
            let saved = try XCTUnwrap(repo.daytimePrompts().prompts.first { $0.id == slot.id })
            XCTAssertTrue(service.status.contains("retry") || service.status.contains("Retry"))
            XCTAssertFalse(service.status.contains("cannot be postponed"))
            XCTAssertNil(service.nextReminderAt)
            XCTAssertTrue(client.requests.isEmpty)
            if action == "daytime_later" {
                XCTAssertEqual(saved.status, .deferred)
                XCTAssertEqual(saved.nextAttemptAt, clock.addingTimeInterval(1800))
            } else {
                XCTAssertEqual(saved.openedAt, DaytimePromptLedger.canonicalDate(clock))
                XCTAssertEqual(service.promptToOpen?.id, slot.id)
            }
        }
    }
    func testRetainedCrossDayCollisionNeverQueuesBothRequests() async throws {
        let payload = #"{"enabled":true,"prompts":[{"anchor":{"intendedAt":"2035-10-05T02:17:00.000Z","kind":"mainWake","label":"Workday check-in 1 · after main wake","sourceAt":"2035-10-04T23:00:00.000Z","sourceID":"2035-10-04T23:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-04","id":"00000000-0000-0000-0000-295B83AB8D1B","intendedAt":"2035-10-05T02:17:00.000Z","nextAttemptAt":"2035-10-05T02:17:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T03:00:00.000Z","windowIndex":0,"windowStart":"2035-10-05T01:00:00.000Z"},{"anchor":{"intendedAt":"2035-10-05T07:17:00.000Z","kind":"mainWake","label":"Workday check-in 2 · after main wake","sourceAt":"2035-10-04T23:00:00.000Z","sourceID":"2035-10-04T23:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-04","id":"00000000-0000-0000-0000-285B83AB8B68","intendedAt":"2035-10-05T07:17:00.000Z","nextAttemptAt":"2035-10-05T07:17:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T08:00:00.000Z","windowIndex":1,"windowStart":"2035-10-05T05:00:00.000Z"},{"anchor":{"intendedAt":"2035-10-05T10:58:00.000Z","kind":"mainWake","label":"Workday check-in 3 · after main wake","sourceAt":"2035-10-04T23:00:00.000Z","sourceID":"2035-10-04T23:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-04","id":"00000000-0000-0000-0000-2B5B83AB9081","intendedAt":"2035-10-05T10:58:00.000Z","nextAttemptAt":"2035-10-05T10:58:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T12:00:00.000Z","windowIndex":2,"windowStart":"2035-10-05T10:00:00.000Z"},{"anchor":{"intendedAt":"2035-10-05T11:14:00.000Z","kind":"mainWake","label":"Workday check-in 1 · after main wake","sourceAt":"2035-10-05T09:00:00.000Z","sourceID":"2035-10-05T09:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-05","id":"00000000-0000-0000-0000-405B888238D0","intendedAt":"2035-10-05T11:14:00.000Z","nextAttemptAt":"2035-10-05T11:14:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T13:00:00.000Z","windowIndex":0,"windowStart":"2035-10-05T11:00:00.000Z"},{"anchor":{"intendedAt":"2035-10-05T16:43:00.000Z","kind":"mainWake","label":"Workday check-in 2 · after main wake","sourceAt":"2035-10-05T09:00:00.000Z","sourceID":"2035-10-05T09:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-05","id":"00000000-0000-0000-0000-415B88823A83","intendedAt":"2035-10-05T16:43:00.000Z","nextAttemptAt":"2035-10-05T16:43:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T18:00:00.000Z","windowIndex":1,"windowStart":"2035-10-05T15:00:00.000Z"},{"anchor":{"intendedAt":"2035-10-05T20:21:00.000Z","kind":"mainWake","label":"Workday check-in 3 · after main wake","sourceAt":"2035-10-05T09:00:00.000Z","sourceID":"2035-10-05T09:00:00Z","sourceRevision":"r1","workRevision":"w1","workSourceID":"work-A","working":true},"anchorDayKey":"2035-10-05","id":"00000000-0000-0000-0000-425B88823C36","intendedAt":"2035-10-05T20:21:00.000Z","nextAttemptAt":"2035-10-05T20:21:00.000Z","scheduleID":"00000000-0000-0000-0000-000000000001","status":"pending","windowEnd":"2035-10-05T21:00:00.000Z","windowIndex":2,"windowStart":"2035-10-05T20:00:00.000Z"}],"quietEnd":420,"quietStart":1320,"schedules":[{"createdAt":"2035-10-04T23:00:00.000Z","hour":14,"id":"00000000-0000-0000-0000-000000000001","minute":0,"rule":{"anchor":"mainWake","offDayAnchor":"clock","offDayHour":14,"offDayMinute":0,"randomizedWake":{"offBedtimeMinute":1320,"workBedtimeMinute":1380},"selectedWeekdays":[1,2,3,4,5,6,7],"wakeOffsetMinutes":240},"timeZone":"UTC"}]}"#
        let original = try DaytimePromptLedger.decodePayload(Data(payload.utf8))
        let clock = ISO8601DateFormatter().date(from: "2035-10-05T09:00:00Z")!
        let repo = SessionRepository(storage: .inMemory()), client = Client()
        try repo.saveDaytimePrompts(original)
        let contexts = try ["2035-10-04T23:00:00Z", "2035-10-05T09:00:00Z"].map { stamp in
            let wake = ISO8601DateFormatter().date(from: stamp)!
            return DaytimePromptAnchorContext(dayKey: DaytimePromptRule.dayKey(wake, timeZone: "UTC"), timeZone: "UTC", working: true,
                mainWake: try DaytimeAnchorSource(id: stamp, revision: "r1", at: wake), workSourceID: "work-A", workRevision: "w1")
        }
        let service = DaytimePromptService(repository: repo, client: client, now: { clock }, contexts: { _, _, _ in contexts })
        await service.reconcile()
        let queued = service.ledger.prompts.filter { client.requests[DaytimePromptService.requestID + "." + $0.id.uuidString] != nil }
            .map(\.nextAttemptAt).sorted()
        for pair in zip(queued, queued.dropFirst()) { XCTAssertGreaterThanOrEqual(pair.1.timeIntervalSince(pair.0), 7200) }
        XCTAssertTrue(service.ledger.prompts.contains { $0.reason == "Spacing conflict; review the routine" })
        XCTAssertEqual(service.ledger.prompts.map(\.intendedAt), original.prompts.map(\.intendedAt))
    }

}
