import XCTest
import DoseCore
import UserNotifications
@testable import DoseTap

@MainActor
final class SupplyReminderServiceTests: XCTestCase {
    final class Client: AlarmNotificationCenterClient {
        var authorization: UNAuthorizationStatus = .authorized
        var requests: [String: UNNotificationRequest] = [:]
        var removed: [String] = []
        var dropsAdds = false
        var failsAdds = false
        var onAdd: (() -> Void)?
        func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}
        func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { authorization == .authorized }
        func authorizationStatus() async -> UNAuthorizationStatus { authorization }
        func add(_ request: UNNotificationRequest) async throws {
            if failsAdds { throw SupplyStorageError.unavailable }
            onAdd?()
            if !dropsAdds { requests[request.identifier] = request }
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
        let repo = SessionRepository(storage: EventStorage.inMemory())
        let service = SupplyReminderService(repository: repo, client: client)
        let firstSave = await service.save(entry())
        XCTAssertTrue(firstSave)
        XCTAssertTrue(service.status.hasPrefix("Scheduled:"), service.status)
        var changed = entry(); changed.day = 5
        _ = await service.save(changed)
        await service.reconcile()
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(try repo.loadSupply().reminder?.history.count, 1)
        await service.setHandledOrDisabled(handled: true)
        XCTAssertTrue(service.status.hasPrefix("Handled"))
        XCTAssertTrue(client.requests.isEmpty)
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
}
