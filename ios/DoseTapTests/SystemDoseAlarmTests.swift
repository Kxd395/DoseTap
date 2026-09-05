import XCTest
import UserNotifications
@testable import DoseTap

@MainActor
final class SystemDoseAlarmTests: XCTestCase {
    final class Native: SystemDoseAlarmScheduling {
        var target: Date?
        var denied = false
        var drops = false
        var failNext = false
        var onSchedule: (() -> Void)?
        var authorizationDescription: String { "Test authorization" }
        func requestAuthorization() async throws { if denied { throw SystemDoseAlarmError.permission } }
        func deadline() throws -> Date? { target }
        func cancel() throws { target = nil }
        func schedule(at date: Date) async throws {
            if failNext { failNext = false; throw SystemDoseAlarmError.verification }
            onSchedule?()
            target = drops ? nil : date
        }
    }
    final class Notifications: AlarmNotificationCenterClient {
        var removed: [String] = []
        func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}
        func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { false }
        func authorizationStatus() async -> UNAuthorizationStatus { .denied }
        func pendingRequests() async -> [UNNotificationRequest] { [] }
        func add(_ request: UNNotificationRequest) async throws { XCTFail("Wake must use system alarms") }
        func removePendingRequests(withIdentifiers identifiers: [String]) { removed += identifiers }
        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) { removed += identifiers }
    }
    private var domains: [String] = []
    override func tearDown() async throws {
        for domain in domains { UserDefaults.standard.removePersistentDomain(forName: domain) }
    }
    private func service(_ native: Native, _ notifications: Notifications? = nil, now: Date) -> AlarmService {
        let domain = "SystemDoseAlarmTests.\(UUID())"; domains.append(domain)
        return AlarmService(notificationClient: notifications ?? Notifications(), defaults: UserDefaults(suiteName: domain)!,
            nowProvider: { now }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! },
            configurationProvider: { AlarmConfiguration(notificationsEnabled: true, windowOpenAlert: true,
                fifteenMinWarning: true, fiveMinWarning: true, soundEnabled: false, criticalAlertsEnabled: false,
                snoozeDurationMinutes: 10, maxSnoozes: 3) }, systemWakeAlarm: native)
    }
    func testSystemAlarmSchedulesDespiteSeparateNotificationDenialAndKeepsAbsoluteTarget() async {
        let native = Native(), notifications = Notifications(), now = Date()
        let alarm = service(native, notifications, now: now)
        let target = now.addingTimeInterval(165 * 60)
        let result = await alarm.scheduleDose2Alarm(at: target, dose1Time: now)
        XCTAssertNil(result.failure)
        XCTAssertTrue(alarm.alarmScheduled)
        XCTAssertEqual(native.target, target)
        XCTAssertFalse(notifications.removed.contains(SupplyReminderService.requestID))
        XCTAssertTrue(Set(notifications.removed).isSubset(of: Set(AlarmService.wakeNotificationIdentifiers)))
        alarm.cancelWakeAlarms()
        XCTAssertNil(native.target)
    }
    func testDeniedAndMissingSystemAlarmNeverClaimSuccess() async {
        let native = Native(), now = Date()
        let alarm = service(native, now: now)
        native.denied = true
        let denied = await alarm.scheduleDose2Alarm(at: now.addingTimeInterval(100), dose1Time: now)
        XCTAssertEqual(denied.failure?.code, .systemAlarm)
        XCTAssertFalse(alarm.alarmScheduled)
        native.denied = false; native.drops = true
        let dropped = await alarm.scheduleDose2Alarm(at: now.addingTimeInterval(100), dose1Time: now)
        XCTAssertNotNil(dropped.failure)
        XCTAssertFalse(alarm.alarmScheduled)
    }
    func testFailedReplacementRestoresPreviousTargetAndCancellationWinsRace() async {
        let native = Native(), now = Date()
        let alarm = service(native, now: now)
        let old = now.addingTimeInterval(100)
        _ = await alarm.scheduleDose2Alarm(at: old, dose1Time: now)
        native.failNext = true
        let failed = await alarm.scheduleDose2Alarm(at: now.addingTimeInterval(200), dose1Time: now)
        XCTAssertTrue(failed.failure?.previousScheduleRestored == true)
        XCTAssertEqual(alarm.targetWakeTime, old)
        XCTAssertEqual(native.target, old)
        native.onSchedule = { alarm.cancelWakeAlarms() }
        let cancelled = await alarm.scheduleDose2Alarm(at: now.addingTimeInterval(300), dose1Time: now)
        XCTAssertEqual(cancelled.failure?.code, .cancelled)
        XCTAssertNil(native.target)
        XCTAssertFalse(alarm.alarmScheduled)
    }
}
