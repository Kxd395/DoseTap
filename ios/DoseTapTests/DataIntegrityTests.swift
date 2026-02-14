//
//  DataIntegrityTests.swift
//  DoseTapTests
//
//  SleepPlanStore template tests and data integrity / cascade tests.
//  Extracted from DoseTapTests.swift for maintainability.
//

import XCTest
@testable import DoseTap
import DoseCore

// MARK: - Sleep Plan Store Template Tests

@MainActor
final class SleepPlanStoreTemplateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: SleepPlanStore!

    override func setUp() async throws {
        suiteName = "SleepPlanStoreTemplateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = SleepPlanStore(userDefaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_applyWorkWeekTemplate_assignsWorkdaysAndOffdays() async {
        let workWake = makeTime(hour: 5, minute: 45)
        let offWake = makeTime(hour: 8, minute: 30)
        let workdays: Set<Int> = [2, 4, 6] // Mon/Wed/Fri

        store.applyWorkWeekTemplate(
            workdays: workdays,
            workdayWake: workWake,
            offdayWake: offWake,
            offdaysEnabled: true
        )

        for weekday in 1...7 {
            let entry = store.schedule.entry(for: weekday)
            if workdays.contains(weekday) {
                XCTAssertEqual(entry.wakeByHour, 5)
                XCTAssertEqual(entry.wakeByMinute, 45)
                XCTAssertTrue(entry.enabled)
            } else {
                XCTAssertEqual(entry.wakeByHour, 8)
                XCTAssertEqual(entry.wakeByMinute, 30)
                XCTAssertTrue(entry.enabled)
            }
        }
    }

    func test_applyWorkWeekTemplate_respectsOffdayEnabledFlag() async {
        let workWake = makeTime(hour: 6, minute: 0)
        let offWake = makeTime(hour: 9, minute: 0)

        store.applyWorkWeekTemplate(
            workdays: [2, 3, 4],
            workdayWake: workWake,
            offdayWake: offWake,
            offdaysEnabled: false
        )

        XCTAssertTrue(store.schedule.entry(for: 2).enabled)
        XCTAssertTrue(store.schedule.entry(for: 3).enabled)
        XCTAssertTrue(store.schedule.entry(for: 4).enabled)
        XCTAssertFalse(store.schedule.entry(for: 1).enabled)
        XCTAssertFalse(store.schedule.entry(for: 5).enabled)
        XCTAssertFalse(store.schedule.entry(for: 6).enabled)
        XCTAssertFalse(store.schedule.entry(for: 7).enabled)
    }

    private func makeTime(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Data Integrity Tests

/// Data integrity tests that verify cascade behaviors and notification lifecycle.
/// These tests protect against P0 bugs: ghost doses, orphan notifications, data corruption.
@MainActor
final class DataIntegrityTests: XCTestCase {
    
    private var storage: EventStorage!
    private var repo: SessionRepository!
    private var fakeScheduler: FakeNotificationScheduler!
    
    override func setUp() async throws {
        storage = EventStorage.shared
        fakeScheduler = FakeNotificationScheduler()
        repo = SessionRepository(storage: storage, notificationScheduler: fakeScheduler)
        storage.clearAllData()
        repo.reload()
    }
    
    override func tearDown() async throws {
        storage.clearAllData()
    }
    
    // MARK: - SQLite Configuration Tests
    
    func test_sqlite_foreignKeysEnabled() async throws {
        let fkEnabled = storage.isForeignKeysEnabled()
        XCTAssertTrue(fkEnabled, 
            "PRAGMA foreign_keys must be ON for cascade delete to work. " +
            "Without FK enforcement, tests can pass accidentally.")
    }
    
    func test_schemaUsesManualCascade_documented() async throws {
        let tablesRequiringManualCascade = [
            "sleep_events",
            "dose_events",
            "pre_sleep_logs",
            "morning_checkins",
            "checkin_submissions",
            "medication_events"
        ]
        
        XCTAssertEqual(tablesRequiringManualCascade.count, 6, 
            "If you added a new table, add it to manual cascade in deleteSession()")
    }
    
    // MARK: - Cascade Delete Tests
    
    func test_sessionDelete_cascadesToDoseEvents() async throws {
        let now = Date()
        let dose1Time = now.addingTimeInterval(-120 * 60)
        repo.setDose1Time(dose1Time)
        
        let sessionDate = repo.currentSessionDateString()
        XCTAssertNotNil(repo.dose1Time, "Dose 1 should exist before delete")
        
        repo.deleteSession(sessionDate: sessionDate)
        
        XCTAssertNil(repo.dose1Time, "Dose 1 should be nil after cascade delete")
        XCTAssertNil(repo.dose2Time, "Dose 2 should be nil after cascade delete")
        XCTAssertNil(repo.activeSessionDate, "Session should be nil after delete")
        
        repo.reload()
        XCTAssertNil(repo.dose1Time, "Dose 1 should remain nil after reload - cascade persisted")
    }
    
    func test_sessionDelete_cascadesBothDoses() async throws {
        let now = Date()
        let dose1Time = now.addingTimeInterval(-180 * 60)
        let dose2Time = now.addingTimeInterval(-15 * 60)
        
        repo.setDose1Time(dose1Time)
        repo.setDose2Time(dose2Time)
        
        let sessionDate = repo.currentSessionDateString()
        
        XCTAssertNotNil(repo.dose1Time, "Dose 1 should exist")
        XCTAssertNotNil(repo.dose2Time, "Dose 2 should exist")
        
        repo.deleteSession(sessionDate: sessionDate)
        
        XCTAssertNil(repo.dose1Time, "Dose 1 should cascade delete")
        XCTAssertNil(repo.dose2Time, "Dose 2 should cascade delete")
        
        repo.reload()
        XCTAssertNil(repo.dose1Time, "No ghost dose1 in storage")
        XCTAssertNil(repo.dose2Time, "No ghost dose2 in storage")
    }
    
    func test_sessionDelete_resetsEphemeralState() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.incrementSnooze()
        repo.incrementSnooze()
        repo.skipDose2()
        
        let sessionDate = repo.currentSessionDateString()
        
        XCTAssertEqual(repo.snoozeCount, 2, "Snooze count should be 2")
        XCTAssertTrue(repo.dose2Skipped, "Dose 2 should be skipped")
        
        repo.deleteSession(sessionDate: sessionDate)
        
        XCTAssertEqual(repo.snoozeCount, 0, "Snooze count should reset to 0")
        XCTAssertFalse(repo.dose2Skipped, "Skip state should reset to false")
    }
    
    // MARK: - Notification Cancellation Tests
    
    func test_deleteActiveSession_cancelsExactNotificationIdentifiers() async throws {
        let dose1Time = Date().addingTimeInterval(-150 * 60)
        repo.setDose1Time(dose1Time)
        
        let sessionDate = repo.currentSessionDateString()
        XCTAssertNotNil(repo.activeSessionDate, "Session should exist")
        
        fakeScheduler.reset()
        repo.deleteSession(sessionDate: sessionDate)
        
        let cancelledSet = Set(fakeScheduler.cancelledIdentifiers)
        let expectedSet = Set(SessionRepository.sessionNotificationIdentifiers)
        
        XCTAssertEqual(cancelledSet, expectedSet,
            "Cancelled identifiers should exactly match SessionRepository.sessionNotificationIdentifiers")
        XCTAssertEqual(fakeScheduler.cancelledIdentifiers.count, 
                       SessionRepository.sessionNotificationIdentifiers.count,
            "Should cancel exactly \(SessionRepository.sessionNotificationIdentifiers.count) identifiers")
    }
    
    func test_deleteInactiveSession_doesNotCancelNotifications() async throws {
        repo.setDose1Time(Date())
        XCTAssertNotNil(repo.activeSessionDate)
        
        fakeScheduler.reset()
        
        let pastSessionDate = "2024-01-01"
        repo.deleteSession(sessionDate: pastSessionDate)
        
        XCTAssertTrue(fakeScheduler.cancelledIdentifiers.isEmpty,
            "Deleting inactive session should NOT cancel notifications for active session")
    }
    
    func test_sessionNotificationIdentifiers_containsAllExpected() {
        let ids = SessionRepository.sessionNotificationIdentifiers
        
        XCTAssertTrue(ids.contains("dose_reminder"), "Missing dose_reminder")
        XCTAssertTrue(ids.contains("window_opening"), "Missing window_opening")
        XCTAssertTrue(ids.contains("window_closing"), "Missing window_closing")
        XCTAssertTrue(ids.contains("window_critical"), "Missing window_critical")
        XCTAssertTrue(ids.contains("wake_alarm"), "Missing wake_alarm")
        XCTAssertTrue(ids.contains("wake_alarm_pre"), "Missing wake_alarm_pre")
        XCTAssertTrue(ids.contains("wake_alarm_follow1"), "Missing wake_alarm_follow1")
        XCTAssertTrue(ids.contains("wake_alarm_follow2"), "Missing wake_alarm_follow2")
        XCTAssertTrue(ids.contains("wake_alarm_follow3"), "Missing wake_alarm_follow3")
        XCTAssertTrue(ids.contains("hard_stop"), "Missing hard_stop")
        XCTAssertTrue(ids.contains("hard_stop_5min"), "Missing hard_stop_5min")
        XCTAssertTrue(ids.contains("hard_stop_2min"), "Missing hard_stop_2min")
        XCTAssertTrue(ids.contains("hard_stop_30sec"), "Missing hard_stop_30sec")
        XCTAssertTrue(ids.contains("hard_stop_expired"), "Missing hard_stop_expired")
        XCTAssertTrue(ids.contains("snooze_reminder"), "Missing snooze_reminder")
    }
    
    // MARK: - Database Cascade Assertions
    
    func test_sessionDelete_cascadesAllDependentTables() async throws {
        let sessionDate = storage.currentSessionDate()
        
        repo.setDose1Time(Date().addingTimeInterval(-180 * 60))
        repo.setDose2Time(Date().addingTimeInterval(-15 * 60))
        
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "bathroom",
            timestamp: Date(),
            colorHex: nil
        )
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "lights_out",
            timestamp: Date(),
            colorHex: nil
        )
        
        XCTAssertGreaterThan(storage.fetchRowCount(table: "sleep_events", sessionDate: sessionDate), 0,
            "Should have sleep events before delete")
        
        repo.deleteSession(sessionDate: sessionDate)
        
        XCTAssertEqual(storage.fetchRowCount(table: "sleep_events", sessionDate: sessionDate), 0,
            "sleep_events should have 0 rows after cascade delete")
        XCTAssertEqual(storage.fetchRowCount(table: "dose_events", sessionDate: sessionDate), 0,
            "dose_events should have 0 rows after cascade delete")
        XCTAssertEqual(storage.fetchRowCount(table: "medication_events", sessionDate: sessionDate), 0,
            "medication_events should have 0 rows after cascade delete")
        XCTAssertEqual(storage.fetchRowCount(table: "morning_checkins", sessionDate: sessionDate), 0,
            "morning_checkins should have 0 rows after cascade delete")
        XCTAssertEqual(storage.fetchRowCount(table: "pre_sleep_logs", sessionDate: sessionDate), 0,
            "pre_sleep_logs should have 0 rows after cascade delete")
        
        XCTAssertNil(repo.dose1Time, "Repo dose1Time should be nil")
        XCTAssertNil(repo.dose2Time, "Repo dose2Time should be nil")
        XCTAssertNil(repo.activeSessionDate, "Repo activeSessionDate should be nil")
    }
    
    func test_sessionDelete_clearsCurrentSessionTable() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.incrementSnooze()
        
        let sessionDate = repo.currentSessionDateString()
        
        repo.deleteSession(sessionDate: sessionDate)
        
        repo.reload()
        XCTAssertNil(repo.dose1Time, "dose1Time should be nil after reload")
        XCTAssertEqual(repo.snoozeCount, 0, "snoozeCount should be 0 after reload")
    }
    
    // MARK: - Legacy Tests (kept for backward compatibility)

    func test_clearTonight_managedNotificationState() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.setDose2Time(Date())
        let sessionDate = repo.currentSessionDateString()
        
        XCTAssertNotNil(repo.dose1Time)
        XCTAssertNotNil(repo.dose2Time)
        XCTAssertNotNil(repo.activeSessionId)
        XCTAssertNotNil(repo.activeSessionStart)
        
        fakeScheduler.reset()
        repo.clearTonight()
        
        XCTAssertNil(repo.dose1Time, "Dose 1 cleared")
        XCTAssertNil(repo.dose2Time, "Dose 2 cleared")
        XCTAssertNil(repo.activeSessionDate, "Session cleared")
        XCTAssertNil(repo.activeSessionId, "Session id cleared")
        XCTAssertNil(repo.activeSessionStart, "Session start cleared")
        XCTAssertNil(repo.activeSessionEnd, "Session end cleared")
        XCTAssertEqual(repo.currentSessionKey, sessionDate, "Current session key should remain on today's bucket after clear")

        let cancelledSet = Set(fakeScheduler.cancelledIdentifiers)
        let expectedSet = Set(SessionRepository.sessionNotificationIdentifiers)
        XCTAssertEqual(cancelledSet, expectedSet, "clearTonight should cancel canonical session notifications")
    }

    func test_clearAllData_clearsIdentityAndCancelsNotifications() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-150 * 60))
        repo.incrementSnooze()
        XCTAssertNotNil(repo.activeSessionId, "Session id should exist before clearAllData")
        XCTAssertNotNil(repo.activeSessionStart, "Session start should exist before clearAllData")

        fakeScheduler.reset()
        repo.clearAllData()

        XCTAssertNil(repo.activeSessionDate, "Session date should clear on clearAllData")
        XCTAssertNil(repo.activeSessionId, "Session id should clear on clearAllData")
        XCTAssertNil(repo.activeSessionStart, "Session start should clear on clearAllData")
        XCTAssertNil(repo.activeSessionEnd, "Session end should clear on clearAllData")
        XCTAssertNil(repo.dose1Time, "Dose1 should clear on clearAllData")
        XCTAssertNil(repo.dose2Time, "Dose2 should clear on clearAllData")
        XCTAssertEqual(repo.snoozeCount, 0, "Snooze should reset on clearAllData")
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Context should return to noDose1 after clearAllData")

        let cancelledSet = Set(fakeScheduler.cancelledIdentifiers)
        let expectedSet = Set(SessionRepository.sessionNotificationIdentifiers)
        XCTAssertEqual(cancelledSet, expectedSet, "clearAllData should cancel canonical session notifications")
    }
    
    // MARK: - Data Consistency Tests
    
    func test_contextConsistency_throughStateTransitions() async throws {
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Start with noDose1")
        
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        XCTAssertNotEqual(repo.currentContext.phase, .noDose1, "Phase changes after dose1")
        
        let sessionDate = repo.currentSessionDateString()
        repo.deleteSession(sessionDate: sessionDate)
        
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Returns to noDose1 after delete")
        XCTAssertEqual(repo.currentContext.snoozeCount, 0, "Snooze count is 0")
    }
}
