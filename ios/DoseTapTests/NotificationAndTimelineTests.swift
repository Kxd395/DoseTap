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
            "dosetap_wake_alarm",
            "dosetap_pre_alarm",
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
