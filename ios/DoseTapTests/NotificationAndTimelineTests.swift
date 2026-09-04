//
//  NotificationAndTimelineTests.swift
//  DoseTapTests
//
//  Notification center integration and timeline filtering tests.
//  Extracted from DoseTapTests.swift for maintainability.
//

import XCTest
@testable import DoseTap
import DoseCore
@preconcurrency import UserNotifications

// MARK: - Notification Center Integration

@MainActor
final class NotificationCenterIntegrationTests: XCTestCase {
    
    private final class RecordingUNNotificationScheduler: NotificationScheduling, @unchecked Sendable {
        let center: UNUserNotificationCenter
        private(set) var cancelled: [String] = []
        
        init(center: UNUserNotificationCenter = .current()) {
            self.center = center
        }
        
        func cancelNotifications(withIdentifiers ids: [String]) {
            cancelled = ids
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
    
    override func setUp() async throws {
        EventStorage.shared.clearAllData()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    override func tearDown() async throws {
        EventStorage.shared.clearAllData()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func test_deleteSession_cancelsPendingUNNotifications() async throws {
        let center = UNUserNotificationCenter.current()
        
        for id in SessionRepository.sessionNotificationIdentifiers {
            let content = UNMutableNotificationContent()
            content.title = "Test"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try await center.add(request)
        }
        
        let recordingScheduler = RecordingUNNotificationScheduler(center: center)
        let repo = SessionRepository(storage: EventStorage.shared, notificationScheduler: recordingScheduler)
        repo.setDose1Time(Date())
        let sessionDate = repo.currentSessionDateString()
        repo.deleteSession(sessionDate: sessionDate)
        
        let pendingAfter = await pendingIdentifiers(center)
        let remaining = Set(pendingAfter)
        let expected = Set(SessionRepository.sessionNotificationIdentifiers)
        
        XCTAssertEqual(Set(recordingScheduler.cancelled), expected, "deleteSession should cancel canonical identifiers")
        XCTAssertTrue(remaining.isDisjoint(with: expected), "No session identifiers should remain pending")
    }
    
    func test_skipDose_cancelsWakeAlarms() async throws {
        let center = UNUserNotificationCenter.current()
        
        let wakeIds = [
            "dosetap_dose2_alarm",
            "dosetap_dose2_pre_alarm",
            "dosetap_followup_1",
            "dosetap_followup_2",
            "dosetap_followup_3",
        ]
        for id in wakeIds {
            let content = UNMutableNotificationContent()
            content.title = "Wake Alarm"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try await center.add(request)
        }
        
        let recordingScheduler = RecordingUNNotificationScheduler(center: center)
        let repo = SessionRepository(storage: EventStorage.shared, notificationScheduler: recordingScheduler)
        repo.setDose1Time(Date())
        repo.skipDose2()
        
        let pendingAfter = await pendingIdentifiers(center)
        let remaining = Set(pendingAfter)
        
        XCTAssertTrue(remaining.isDisjoint(with: Set(wakeIds)), "Wake alarms should be cancelled on skip")
        XCTAssertTrue(Set(recordingScheduler.cancelled).isSuperset(of: Set(wakeIds)), "Skip should request cancellation of wake alarms")
    }
    
    private func pendingIdentifiers(_ center: UNUserNotificationCenter) async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map { $0.identifier })
            }
        }
    }
}

// MARK: - Verified Alarm Scheduling

/// Exercises the medication-alarm boundary without relying on the simulator's
/// global notification center. The fake deliberately supports add failures,
/// silent drops, and re-entrant cancellation so success cannot be inferred from
/// a fire-and-forget API call.
@MainActor
final class AlarmSchedulingTests: XCTestCase {
    private final class InjectedNotificationError: LocalizedError {
        let identifier: String

        init(identifier: String) {
            self.identifier = identifier
        }

        var errorDescription: String? {
            "Injected notification failure for \(identifier)"
        }
    }

    @MainActor
    private final class FakeNotificationCenter: AlarmNotificationCenterClient {
        var authorization: UNAuthorizationStatus = .authorized
        var requestsByIdentifier: [String: UNNotificationRequest] = [:]
        var failingIdentifiers: Set<String> = []
        var remainingFailureCounts: [String: Int] = [:]
        var silentlyDroppedIdentifiers: Set<String> = []
        var onAdd: ((UNNotificationRequest) -> Void)?
        private(set) var removedIdentifiers: [String] = []
        private(set) var categories: Set<UNNotificationCategory> = []

        func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}

        func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
            self.categories = categories
        }

        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            authorization == .authorized
                || authorization == .provisional
                || authorization == .ephemeral
        }

        func authorizationStatus() async -> UNAuthorizationStatus {
            authorization
        }

        func add(_ request: UNNotificationRequest) async throws {
            let callback = onAdd
            callback?(request)
            if let remaining = remainingFailureCounts[request.identifier], remaining > 0 {
                remainingFailureCounts[request.identifier] = remaining - 1
                throw InjectedNotificationError(identifier: request.identifier)
            }
            if failingIdentifiers.contains(request.identifier) {
                throw InjectedNotificationError(identifier: request.identifier)
            }
            guard !silentlyDroppedIdentifiers.contains(request.identifier) else {
                return
            }
            requestsByIdentifier[request.identifier] = request
        }

        func pendingRequests() async -> [UNNotificationRequest] {
            Array(requestsByIdentifier.values)
        }

        func removePendingRequests(withIdentifiers identifiers: [String]) {
            removedIdentifiers.append(contentsOf: identifiers)
            for identifier in identifiers {
                requestsByIdentifier.removeValue(forKey: identifier)
            }
        }

        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}

        func removePending(identifier: String) {
            requestsByIdentifier.removeValue(forKey: identifier)
        }
    }

    @MainActor
    private final class TestEnvironment {
        var now: Date
        var timeZone: TimeZone

        init(now: Date, timeZone: TimeZone) {
            self.now = now
            self.timeZone = timeZone
        }
    }

    private struct FixedDateProvider: DateProviding, @unchecked Sendable {
        let date: Date

        func now() -> Date { date }
    }

    private var defaultsDomains: [String] = []

    override func tearDown() async throws {
        for domain in defaultsDomains {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        defaultsDomains.removeAll()
    }

    func test_alarmActionExplicitlyRequiresOpeningAppToLogDose2() throws {
        let client = FakeNotificationCenter()
        _ = makeService(client: client, environment: makeEnvironment())

        let category = try XCTUnwrap(client.categories.first {
            $0.identifier == "dosetap_alarm"
        })
        let openAction = try XCTUnwrap(category.actions.first {
            $0.identifier == "dosetap_alarm_stop"
        })

        XCTAssertEqual(openAction.title, "Open DoseTap to Log Dose 2")
    }

    func test_permissionDeniedFailsClosedAndRetainsRetryMetadata() async throws {
        let client = FakeNotificationCenter()
        client.authorization = .denied
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)
        let dose1 = environment.now
        let target = dose1.addingTimeInterval(165 * 60)

        let result = await service.scheduleDose2Alarm(at: target, dose1Time: dose1)

        XCTAssertEqual(result.failure?.code, .authorizationDenied)
        XCTAssertFalse(service.alarmScheduled)
        XCTAssertEqual(service.targetWakeTime, target, "The absolute intent must remain available for an explicit retry")
        XCTAssertNotNil(service.lastSchedulingError)
        XCTAssertTrue(client.requestsByIdentifier.isEmpty)
    }

    func test_doseOneCommitSurfacesAlarmFailureAsAttentionRequired() async throws {
        let client = FakeNotificationCenter()
        client.authorization = .denied
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)
        let storage = EventStorage.inMemory()
        let repository = SessionRepository(
            storage: storage,
            notificationScheduler: FakeNotificationScheduler(),
            clock: { environment.now },
            timeZoneProvider: { environment.timeZone }
        )
        let core = DoseTapCore()
        core.setSessionRepository(repository)
        let coordinator = DoseActionCoordinator(
            core: core,
            alarmService: service,
            dateProvider: FixedDateProvider(date: environment.now),
            sessionRepo: repository
        )

        let result = await coordinator.takeDose1(surface: .tonightButton)

        guard case .attentionRequired(let message) = result else {
            return XCTFail("Dose 1 should commit while the alarm failure remains visible")
        }
        XCTAssertEqual(repository.dose1Time, environment.now)
        XCTAssertTrue(message.contains("Dose 1 was logged"))
        XCTAssertTrue(message.contains("Notification permission is denied"))
        XCTAssertFalse(service.alarmScheduled)
        XCTAssertFalse(service.reminderScheduled)
    }

    func test_partialAddFailureRollsBackWholeWakeGroup() async throws {
        let client = FakeNotificationCenter()
        client.failingIdentifiers = [AlarmService.NotificationID.dose2PreAlarm]
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)
        let dose1 = environment.now

        let result = await service.scheduleDose2Alarm(
            at: environment.now.addingTimeInterval(165 * 60),
            dose1Time: dose1
        )

        XCTAssertEqual(result.failure?.code, .addFailed)
        XCTAssertEqual(result.failure?.failedIdentifier, AlarmService.NotificationID.dose2PreAlarm)
        XCTAssertFalse(service.alarmScheduled)
        XCTAssertTrue(client.requestsByIdentifier.isEmpty, "A partial wake group must never survive")
    }

    func test_firstAddErrorLeavesNoScheduledWakeState() async throws {
        let client = FakeNotificationCenter()
        client.failingIdentifiers = [AlarmService.NotificationID.dose2Alarm]
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)

        let result = await service.scheduleDose2Alarm(
            at: environment.now.addingTimeInterval(165 * 60),
            dose1Time: environment.now
        )

        XCTAssertEqual(result.failure?.code, .addFailed)
        XCTAssertEqual(result.failure?.failedIdentifier, AlarmService.NotificationID.dose2Alarm)
        XCTAssertFalse(service.alarmScheduled)
        XCTAssertTrue(client.requestsByIdentifier.isEmpty)
    }

    func test_rescheduleFailureRestoresPreviouslyVerifiedWakeGroup() async throws {
        let client = FakeNotificationCenter()
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)
        let dose1 = environment.now
        let originalTarget = environment.now.addingTimeInterval(165 * 60)
        let replacementTarget = originalTarget.addingTimeInterval(10 * 60)

        guard case .scheduled = await service.scheduleDose2Alarm(
            at: originalTarget,
            dose1Time: dose1
        ) else {
            return XCTFail("Expected original wake group to verify")
        }
        let originalDeadlines = wakeNotificationDeadlines(client)
        client.remainingFailureCounts[AlarmService.NotificationID.dose2PreAlarm] = 1

        let result = await service.scheduleDose2Alarm(
            at: replacementTarget,
            dose1Time: dose1
        )

        XCTAssertEqual(result.failure?.code, .addFailed)
        XCTAssertTrue(result.failure?.previousScheduleRestored == true)
        XCTAssertTrue(service.alarmScheduled)
        XCTAssertEqual(service.targetWakeTime, originalTarget)
        XCTAssertEqual(wakeNotificationDeadlines(client), originalDeadlines)
        XCTAssertNotNil(service.lastSchedulingError, "The restored fallback must not hide the failed replacement")
    }

    func test_failedRollbackRemovesEveryPartialWakeRequest() async throws {
        let client = FakeNotificationCenter()
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)
        let originalTarget = environment.now.addingTimeInterval(165 * 60)

        guard case .scheduled = await service.scheduleDose2Alarm(
            at: originalTarget,
            dose1Time: environment.now
        ) else {
            return XCTFail("Expected original wake group to verify")
        }
        client.failingIdentifiers = [AlarmService.NotificationID.dose2PreAlarm]

        let result = await service.scheduleDose2Alarm(
            at: originalTarget.addingTimeInterval(10 * 60),
            dose1Time: environment.now
        )

        XCTAssertEqual(result.failure?.code, .addFailed)
        XCTAssertFalse(result.failure?.previousScheduleRestored == true)
        XCTAssertFalse(service.alarmScheduled)
        XCTAssertTrue(client.requestsByIdentifier.isEmpty, "A failed rollback must itself fail closed")
    }

    func test_silentNotificationDropFailsVerificationAndRollsBack() async throws {
        let client = FakeNotificationCenter()
        client.silentlyDroppedIdentifiers = [AlarmService.NotificationID.dose2PreAlarm]
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)

        let result = await service.scheduleDose2Alarm(
            at: environment.now.addingTimeInterval(165 * 60),
            dose1Time: environment.now
        )

        XCTAssertEqual(result.failure?.code, .verificationFailed)
        XCTAssertEqual(result.failure?.failedIdentifier, AlarmService.NotificationID.dose2PreAlarm)
        XCTAssertFalse(service.alarmScheduled)
        XCTAssertTrue(client.requestsByIdentifier.isEmpty)
    }

    func test_cancelDuringAddInvalidatesSchedulingGeneration() async throws {
        let client = FakeNotificationCenter()
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)
        client.onAdd = { _ in
            client.onAdd = nil
            service.cancelWakeAlarms()
        }

        let result = await service.scheduleDose2Alarm(
            at: environment.now.addingTimeInterval(165 * 60),
            dose1Time: environment.now
        )

        XCTAssertEqual(result.failure?.code, .cancelled)
        XCTAssertFalse(service.alarmScheduled)
        XCTAssertTrue(client.requestsByIdentifier.isEmpty, "Cancellation must win even when an add is in flight")
    }

    func test_restartRequiresAndThenCompletesPendingRequestReconciliation() async throws {
        let client = FakeNotificationCenter()
        let environment = makeEnvironment()
        let defaults = makeDefaults()
        let first = makeService(client: client, environment: environment, defaults: defaults)
        let dose1 = environment.now
        let target = dose1.addingTimeInterval(165 * 60)

        guard case .scheduled = await first.scheduleDose2Alarm(at: target, dose1Time: dose1) else {
            return XCTFail("Expected the initial wake schedule to verify")
        }
        guard case .scheduled = await first.scheduleDose2Reminders(dose1Time: dose1) else {
            return XCTFail("Expected the initial reminder schedule to verify")
        }

        let restarted = makeService(client: client, environment: environment, defaults: defaults)
        XCTAssertFalse(restarted.alarmScheduled, "Persisted flags are not runtime proof")
        XCTAssertFalse(restarted.reminderScheduled, "Persisted flags are not runtime proof")
        XCTAssertEqual(
            try XCTUnwrap(restarted.targetWakeTime).timeIntervalSince1970,
            target.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertNotNil(restarted.lastSchedulingError)

        let report = await restarted.reconcilePendingRequests(reason: .appActive)

        guard case .scheduled = report.wakeResult else {
            return XCTFail("Restart reconciliation should verify the wake group")
        }
        guard case .scheduled = report.reminderResult else {
            return XCTFail("Restart reconciliation should verify the reminder group")
        }
        XCTAssertTrue(restarted.alarmScheduled)
        XCTAssertTrue(restarted.reminderScheduled)
        XCTAssertNil(restarted.lastSchedulingError)
        XCTAssertEqual(restarted.reconciledTimeZoneIdentifier, environment.timeZone.identifier)
    }

    func test_reconciliationRepairsAnOmittedPendingRequest() async throws {
        let client = FakeNotificationCenter()
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)
        let target = environment.now.addingTimeInterval(165 * 60)

        guard case .scheduled = await service.scheduleDose2Alarm(
            at: target,
            dose1Time: environment.now
        ) else {
            return XCTFail("Expected initial scheduling to verify")
        }
        client.removePending(identifier: AlarmService.NotificationID.dose2PreAlarm)

        let report = await service.reconcilePendingRequests(reason: .appActive)

        XCTAssertTrue(report.detectedMissingIdentifiers.contains(AlarmService.NotificationID.dose2PreAlarm))
        XCTAssertTrue(report.repairedIdentifiers.contains(AlarmService.NotificationID.dose2PreAlarm))
        XCTAssertTrue(service.alarmScheduled)
        XCTAssertEqual(
            Set(client.requestsByIdentifier.keys).intersection(AlarmService.wakeNotificationIdentifiers),
            Set(AlarmService.wakeNotificationIdentifiers)
        )
    }

    func test_timezoneChangePreservesAbsoluteDeadlinesAndRebuildsCalendarZone() async throws {
        let client = FakeNotificationCenter()
        let environment = makeEnvironment(timeZoneID: "America/New_York")
        let service = makeService(client: client, environment: environment)
        let target = environment.now.addingTimeInterval(165 * 60)

        guard case .scheduled = await service.scheduleDose2Alarm(
            at: target,
            dose1Time: environment.now
        ) else {
            return XCTFail("Expected initial scheduling to verify")
        }
        let originalDeadlines = wakeNotificationDeadlines(client)
        environment.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        let report = await service.reconcilePendingRequests(reason: .timeZoneChange)

        guard case .scheduled = report.wakeResult else {
            return XCTFail("Timezone reconciliation should reschedule the wake group")
        }
        XCTAssertEqual(service.targetWakeTime, target)
        XCTAssertEqual(wakeNotificationDeadlines(client), originalDeadlines)
        for identifier in AlarmService.wakeNotificationIdentifiers {
            guard let request = client.requestsByIdentifier[identifier],
                  let trigger = request.trigger as? UNCalendarNotificationTrigger else {
                return XCTFail("Missing rebuilt request \(identifier)")
            }
            XCTAssertEqual(
                request.content.userInfo["dosetap_schedule_timezone"] as? String,
                "America/Los_Angeles"
            )
            let absoluteDeadline = try XCTUnwrap(originalDeadlines[identifier])
            let nextDate = try XCTUnwrap(trigger.nextTriggerDate())
            XCTAssertEqual(nextDate.timeIntervalSince1970, absoluteDeadline, accuracy: 1)
            XCTAssertEqual(
                trigger.dateComponents.timeZone?.secondsFromGMT(for: nextDate),
                environment.timeZone.secondsFromGMT(for: nextDate)
            )
        }
    }

    func test_absoluteComponentsRoundTripAcrossDstZones() throws {
        let formatter = ISO8601DateFormatter()
        let instants = try [
            "2026-03-08T06:59:30Z",
            "2026-03-08T07:01:30Z",
            "2026-10-25T00:59:30Z",
            "2026-10-25T01:01:30Z",
        ].map { try XCTUnwrap(formatter.date(from: $0)) }
        let zones = try [
            "America/New_York",
            "Europe/Berlin",
            "Pacific/Auckland",
        ].map { try XCTUnwrap(TimeZone(identifier: $0)) }

        for zone in zones {
            for instant in instants {
                let components = AlarmService.absoluteDateComponents(for: instant, in: zone)
                let rebuilt = try XCTUnwrap(components.date)
                XCTAssertEqual(rebuilt.timeIntervalSince1970, instant.timeIntervalSince1970, accuracy: 1)
                XCTAssertEqual(
                    components.timeZone?.secondsFromGMT(for: instant),
                    zone.secondsFromGMT(for: instant)
                )
            }
        }
    }

    func test_repeatedSnoozeReplacesWakeOnlyAndPreservesSafetyReminders() async throws {
        let client = FakeNotificationCenter()
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)
        let dose1 = environment.now.addingTimeInterval(-160 * 60)
        let initialTarget = environment.now.addingTimeInterval(10 * 60)

        guard case .scheduled = await service.scheduleDose2Alarm(
            at: initialTarget,
            dose1Time: dose1
        ) else {
            return XCTFail("Expected initial wake scheduling to verify")
        }
        guard case .scheduled = await service.scheduleDose2Reminders(dose1Time: dose1) else {
            return XCTFail("Expected reminder scheduling to verify")
        }

        let expectedReminderIDs: Set<String> = [
            AlarmService.NotificationID.windowWarning15,
            AlarmService.NotificationID.windowWarning5,
        ]
        XCTAssertEqual(pendingReminderIDs(client), expectedReminderIDs)

        let firstTarget = await service.snoozeAlarm(dose1Time: dose1)
        XCTAssertEqual(firstTarget, initialTarget.addingTimeInterval(10 * 60))
        XCTAssertEqual(service.snoozeCount, 1)
        XCTAssertEqual(pendingReminderIDs(client), expectedReminderIDs)

        let secondTarget = await service.snoozeAlarm(dose1Time: dose1)
        XCTAssertEqual(secondTarget, initialTarget.addingTimeInterval(20 * 60))
        XCTAssertEqual(service.snoozeCount, 2)
        XCTAssertEqual(pendingReminderIDs(client), expectedReminderIDs)
        XCTAssertEqual(
            Set(client.requestsByIdentifier.keys).intersection(AlarmService.wakeNotificationIdentifiers),
            Set(AlarmService.wakeNotificationIdentifiers)
        )
    }

    func test_snoozePrunesOnlyTheNowExpiredWindowOpenReminder() async throws {
        let client = FakeNotificationCenter()
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)
        let dose1 = environment.now.addingTimeInterval(-140 * 60)
        let initialTarget = environment.now.addingTimeInterval(25 * 60)

        guard case .scheduled = await service.scheduleDose2Alarm(
            at: initialTarget,
            dose1Time: dose1
        ) else {
            return XCTFail("Expected initial wake scheduling to verify")
        }
        guard case .scheduled = await service.scheduleDose2Reminders(dose1Time: dose1) else {
            return XCTFail("Expected reminder scheduling to verify")
        }
        XCTAssertEqual(
            pendingReminderIDs(client),
            Set(AlarmService.reminderNotificationIdentifiers)
        )

        // Move just into the active window. Window-open is now stale, while the
        // late safety warnings must survive a wake-target snooze.
        environment.now = environment.now.addingTimeInterval(11 * 60)
        let snoozedTarget = await service.snoozeAlarm(dose1Time: dose1)

        XCTAssertEqual(snoozedTarget, initialTarget.addingTimeInterval(10 * 60))
        XCTAssertEqual(
            pendingReminderIDs(client),
            [
                AlarmService.NotificationID.windowWarning15,
                AlarmService.NotificationID.windowWarning5,
            ]
        )
    }

    func test_snoozePolicyBlocksNoDose1BeforeWindowNearCloseAndClosed() async throws {
        let noDoseClient = FakeNotificationCenter()
        let noDoseEnvironment = makeEnvironment()
        let noDoseService = makeService(client: noDoseClient, environment: noDoseEnvironment)
        let noDoseResult = await noDoseService.snoozeAlarm(dose1Time: nil)
        XCTAssertNil(noDoseResult)
        XCTAssertTrue(noDoseClient.requestsByIdentifier.isEmpty)

        await assertSnoozeBlocked(
            elapsedMinutes: 140,
            expectedPhase: .beforeWindow,
            expectedReminderIDs: Set(AlarmService.reminderNotificationIdentifiers)
        )
        await assertSnoozeBlocked(
            elapsedMinutes: 230,
            expectedPhase: .nearClose,
            expectedReminderIDs: [AlarmService.NotificationID.windowWarning5]
        )
        await assertSnoozeBlocked(
            elapsedMinutes: 245,
            expectedPhase: .closed,
            expectedReminderIDs: []
        )
    }

    func test_reconcileWithNoPersistedIntentIsCleanNoOp() async throws {
        let client = FakeNotificationCenter()
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)

        let report = await service.reconcilePendingRequests(reason: .appActive)

        guard case .notNeeded(let wakeReason) = report.wakeResult,
              case .notNeeded(let reminderReason) = report.reminderResult else {
            return XCTFail("No active session should reconcile as a no-op")
        }
        XCTAssertEqual(wakeReason, "No persisted alarm schedule")
        XCTAssertEqual(reminderReason, "No persisted alarm schedule")
        XCTAssertNil(service.lastSchedulingError)
    }

    private func assertSnoozeBlocked(
        elapsedMinutes: Int,
        expectedPhase: DoseWindowPhase,
        expectedReminderIDs: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let client = FakeNotificationCenter()
        let environment = makeEnvironment()
        let service = makeService(client: client, environment: environment)
        let dose1 = environment.now.addingTimeInterval(-Double(elapsedMinutes) * 60)
        let initialTarget = environment.now.addingTimeInterval(10 * 60)
        let phase = DoseWindowCalculator(now: { environment.now }).context(
            dose1At: dose1,
            dose2TakenAt: nil,
            dose2Skipped: false,
            snoozeCount: 0
        ).phase
        XCTAssertEqual(phase, expectedPhase, file: file, line: line)

        guard case .scheduled = await service.scheduleDose2Alarm(
            at: initialTarget,
            dose1Time: dose1
        ) else {
            return XCTFail("Expected test precondition schedule to verify", file: file, line: line)
        }
        _ = await service.scheduleDose2Reminders(dose1Time: dose1)
        XCTAssertEqual(
            pendingReminderIDs(client),
            expectedReminderIDs,
            file: file,
            line: line
        )
        let before = notificationDeadlines(client.requestsByIdentifier)

        let result = await service.snoozeAlarm(dose1Time: dose1)

        XCTAssertNil(result, file: file, line: line)
        XCTAssertEqual(service.targetWakeTime, initialTarget, file: file, line: line)
        XCTAssertEqual(service.snoozeCount, 0, file: file, line: line)
        XCTAssertEqual(notificationDeadlines(client.requestsByIdentifier), before, file: file, line: line)
        XCTAssertEqual(
            pendingReminderIDs(client),
            expectedReminderIDs,
            file: file,
            line: line
        )
    }

    private func makeEnvironment(
        timeZoneID: String = "America/New_York"
    ) -> TestEnvironment {
        TestEnvironment(
            now: Date().addingTimeInterval(5),
            timeZone: TimeZone(identifier: timeZoneID)!
        )
    }

    private func makeDefaults() -> UserDefaults {
        let domain = "AlarmSchedulingTests.\(UUID().uuidString)"
        defaultsDomains.append(domain)
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        return defaults
    }

    private func makeService(
        client: FakeNotificationCenter,
        environment: TestEnvironment,
        defaults: UserDefaults? = nil
    ) -> AlarmService {
        let configuration = AlarmConfiguration(
            notificationsEnabled: true,
            windowOpenAlert: true,
            fifteenMinWarning: true,
            fiveMinWarning: true,
            soundEnabled: false,
            criticalAlertsEnabled: false,
            snoozeDurationMinutes: 10,
            maxSnoozes: 3
        )
        return AlarmService(
            notificationClient: client,
            defaults: defaults ?? makeDefaults(),
            nowProvider: { environment.now },
            timeZoneProvider: { environment.timeZone },
            configurationProvider: { configuration }
        )
    }

    private func pendingReminderIDs(_ client: FakeNotificationCenter) -> Set<String> {
        Set(client.requestsByIdentifier.keys).intersection(AlarmService.reminderNotificationIdentifiers)
    }

    private func wakeNotificationDeadlines(
        _ client: FakeNotificationCenter
    ) -> [String: TimeInterval] {
        notificationDeadlines(
            client.requestsByIdentifier.filter {
                AlarmService.wakeNotificationIdentifiers.contains($0.key)
            }
        )
    }

    private func notificationDeadlines(
        _ requests: [String: UNNotificationRequest]
    ) -> [String: TimeInterval] {
        Dictionary(uniqueKeysWithValues: requests.compactMap { identifier, request in
            guard let number = request.content.userInfo["dosetap_absolute_deadline"] as? NSNumber else {
                return nil
            }
            return (identifier, number.doubleValue)
        })
    }
}

// MARK: - Timeline Filtering Tests

@MainActor
final class TimelineFilteringTests: XCTestCase {
    func test_eventStorageFiltersDeletedSessionDates() async throws {
        let storage = EventStorage.shared
        storage.clearAllData()
        
        let repo = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler())
        repo.setDose1Time(Date())
        let sessionDate = repo.currentSessionDateString()
        
        XCTAssertTrue(storage.filterExistingSessionDates([sessionDate]).contains(sessionDate))
        
        repo.deleteSession(sessionDate: sessionDate)
        XCTAssertFalse(storage.filterExistingSessionDates([sessionDate]).contains(sessionDate))
    }
}

// MARK: - Timeline Dual-Storage Integration Tests (DISABLED - SQLiteStorage is unavailable)

#if false
@MainActor
final class TimelineDualStorageIntegrationTests: XCTestCase {
    private let eventStorage = EventStorage.shared
    private let sqlStorage = SQLiteStorage.shared
    
    override func setUp() async throws {
        eventStorage.clearAllData()
        sqlStorage.clearAllData()
    }
    
    override func tearDown() async throws {
        eventStorage.clearAllData()
        sqlStorage.clearAllData()
    }
    
    func test_timelineDropsSessionsMissingFromEventStorage() async throws {
        let repo = SessionRepository(storage: eventStorage, notificationScheduler: FakeNotificationScheduler())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let now = Date()
        repo.setDose1Time(now)
        let realSessionDate = repo.currentSessionDateString()
        sqlStorage.logEvent(sessionDate: realSessionDate, type: "dose1", timestamp: now)
        
        let ghostDate = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let ghostSessionDate = formatter.string(from: ghostDate)
        sqlStorage.logEvent(sessionDate: ghostSessionDate, type: "dose1", timestamp: ghostDate)
        
        let viewModel = TimelineViewModel()
        await viewModel.load()
        
        let visibleDates = Set(viewModel.groupedSessions.keys.map { formatter.string(from: $0) })
        XCTAssertTrue(visibleDates.contains(realSessionDate), "Timeline should include sessions present in EventStorage + SQLiteStorage")
        XCTAssertFalse(visibleDates.contains(ghostSessionDate), "Timeline should drop sessions missing from EventStorage (soft-deleted)")
    }
}
#endif
