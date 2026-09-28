import XCTest
import DoseCore
import UserNotifications
import SQLite3
@testable import DoseTap

@MainActor
final class SupplyReminderServiceTests: XCTestCase {
    final class Client: AlarmNotificationCenterClient {
        var authorization: UNAuthorizationStatus = .authorized
        var requests: [String: UNNotificationRequest] = [:]
        var removed: [String] = []
        var dropsAdds = false
        var failsAdds = false
        var mismatchesTrigger = false
        var onAdd: (() -> Void)?
        func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}
        func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { authorization == .authorized }
        func authorizationStatus() async -> UNAuthorizationStatus { authorization }
        func add(_ request: UNNotificationRequest) async throws {
            if failsAdds { throw SupplyStorageError.unavailable }
            onAdd?()
            if !dropsAdds {
                requests[request.identifier] = mismatchesTrigger
                    ? UNNotificationRequest(identifier: request.identifier, content: request.content,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)) : request
            }
        }
        func pendingRequests() async -> [UNNotificationRequest] { Array(requests.values) }
        func removePendingRequests(withIdentifiers identifiers: [String]) {
            removed += identifiers
            for id in identifiers { requests[id] = nil }
        }
        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) { removed += identifiers }
    }
    private func entry() -> SupplyReminderEntry {
        SupplyReminderEntry(year: 2035, month: 10, day: 4, hour: 9, minute: 0)
    }

    func testReplaceRetryHandledAndDisableOnlyTouchSupplyRole() async throws {
        let client = Client()
        client.requests["dosetap_dose2_alarm"] = UNNotificationRequest(identifier: "dosetap_dose2_alarm",
            content: UNMutableNotificationContent(), trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false))
        let repo = SessionRepository(storage: EventStorage.inMemory())
        let service = SupplyReminderService(repository: repo, client: client)
        let firstSave = await service.save(entry())
        XCTAssertTrue(firstSave)
        XCTAssertTrue(service.status.hasPrefix("Scheduled:"), service.status)
        var changed = entry(); changed.day = 5
        _ = await service.save(changed)
        await service.reconcile()
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(try repo.loadSupply().reminder?.history.count, 1)
        await service.setHandledOrDisabled(handled: true)
        XCTAssertTrue(service.status.hasPrefix("Handled"))
        XCTAssertEqual(Set(client.requests.keys), ["dosetap_dose2_alarm"])
        XCTAssertEqual(Set(client.removed), [SupplyReminderService.requestID])
    }

    func testPermissionFailureSilentDropAndRetryRetainSourceWithoutFalseSuccess() async throws {
        let client = Client()
        let repo = SessionRepository(storage: EventStorage.inMemory())
        let service = SupplyReminderService(repository: repo, client: client)
        client.authorization = .denied
        _ = await service.save(entry())
        XCTAssertTrue(service.needsSettings)
        XCTAssertNotNil(try repo.loadSupply().reminder)
        client.authorization = .authorized
        client.dropsAdds = true
        await service.reconcile()
        XCTAssertTrue(service.status.hasPrefix("Failed:"))
        client.dropsAdds = false
        client.failsAdds = true
        await service.reconcile()
        XCTAssertTrue(service.status.hasPrefix("Failed:"))
        client.failsAdds = false
        client.mismatchesTrigger = true
        await service.reconcile()
        XCTAssertTrue(service.status.hasPrefix("Failed:"))
        client.mismatchesTrigger = false
        await service.reconcile()
        XCTAssertTrue(service.status.hasPrefix("Scheduled:"))
    }

    func testResetDuringAddCannotResurrectRequestAndBottleStartDoesNotMoveDate() async throws {
        let client = Client()
        let repo = SessionRepository(storage: EventStorage.inMemory())
        let service = SupplyReminderService(repository: repo, client: client)
        _ = await service.save(entry())
        let original = try repo.loadSupply().reminder
        _ = await service.recordBottleStart(at: Date().addingTimeInterval(-60))
        XCTAssertEqual(try repo.loadSupply().reminder, original)
        XCTAssertEqual(try repo.loadSupply().bottleStarts.count, 1)
        client.requests.removeAll()
        client.onAdd = { repo.clearAllData() }
        await service.reconcile()
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertNil(try repo.loadSupply().reminder)
    }

    func testFailedSupplyWriteDoesNotPreventDoseRecordAndPastReminderNeedsAttention() async throws {
        let storage = EventStorage.inMemory()
        let repo = SessionRepository(storage: storage)
        let service = SupplyReminderService(repository: repo, client: Client())
        var past = entry(); past.year = 2001
        _ = await service.save(past)
        let savedSource = try repo.loadSupply().reminder?.current
        XCTAssertTrue(service.status.hasPrefix("Needs attention:"))
        var invalid = entry(); invalid.day = 99
        let saved = await service.save(invalid)
        XCTAssertFalse(saved)
        let doseAt = Date()
        repo.setDose1Time(doseAt)
        XCTAssertEqual(repo.dose1Time, doseAt)
        XCTAssertEqual(try repo.loadSupply().reminder?.current, savedSource)
    }
    func testTrackedOpeningWriteFailureAndStableRetryPreserveDosesAndReminder() async throws {
        let storage = EventStorage.inMemory(), repo = SessionRepository(storage: storage)
        let client = Client(), now = Date(), receipt = UUID(), opening = UUID()
        let doseTime = now.addingTimeInterval(-60)
        repo.setDose1Time(doseTime)
        let doseAlarm = "dosetap_dose2_alarm"
        client.requests[doseAlarm] = UNNotificationRequest(identifier: doseAlarm,
            content: UNMutableNotificationContent(), trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false))
        let service = SupplyReminderService(repository: repo, client: client, now: { now })
        let reminderSaved = await service.save(entry())
        XCTAssertTrue(reminderSaved)
        let received = await service.change {
            try $0.receiveBottles(id: receipt, count: 3, receivedAt: doseTime, recordedAt: now, now: now)
        }
        XCTAssertTrue(received)
        let before = try repo.loadSupply()
        XCTAssertEqual(sqlite3_exec(storage.db, "PRAGMA query_only = ON", nil, nil, nil), SQLITE_OK)
        let failed = await service.change {
            try $0.startFullXYWAVBottle(id: opening, receiptID: receipt, openedAt: now, recordedAt: now, now: now)
        }
        XCTAssertFalse(failed)
        XCTAssertEqual(try repo.loadSupply(), before)
        XCTAssertEqual(service.backup, before)
        XCTAssertEqual(sqlite3_exec(storage.db, "PRAGMA query_only = OFF", nil, nil, nil), SQLITE_OK)
        for _ in 0..<2 {
            let saved = await service.change {
                try $0.startFullXYWAVBottle(id: opening, receiptID: receipt, openedAt: now, recordedAt: now, now: now)
            }
            XCTAssertTrue(saved)
        }
        let after = try repo.loadSupply()
        XCTAssertEqual(after.bottleStarts.count, 1)
        XCTAssertEqual(after.trackedUnopenedBottleCount, 2)
        XCTAssertEqual(after.remainingBottleMg(opening), 90_000)
        XCTAssertEqual(after.quantityEntries?.count, 1)
        XCTAssertEqual(after.reminder, before.reminder)
        XCTAssertEqual(repo.dose1Time, doseTime)
        XCTAssertNotNil(client.requests[doseAlarm])
        XCTAssertFalse(client.removed.contains(doseAlarm))
    }

    func testLegacyOpeningCommandCannotBypassTrackedReceiptSelection() async throws {
        let repo = SessionRepository(storage: EventStorage.inMemory()), now = Date()
        let service = SupplyReminderService(repository: repo, client: Client(), now: { now })
        let received = await service.change {
            try $0.receiveBottles(id: UUID(), count: 3, receivedAt: now, recordedAt: now, now: now)
        }
        XCTAssertTrue(received)
        let before = try repo.loadSupply()
        let saved = await service.recordBottleStart(at: now)
        XCTAssertFalse(saved)
        XCTAssertEqual(try repo.loadSupply(), before)
        XCTAssertEqual(service.backup, before)
        XCTAssertNil(repo.dose1Time)
        XCTAssertNil(repo.dose2Time)
    }

}
