import XCTest
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

}
