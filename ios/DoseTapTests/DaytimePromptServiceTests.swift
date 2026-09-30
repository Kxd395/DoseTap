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

}
