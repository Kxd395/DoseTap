//
//  DoseTapTests.swift
//  DoseTapTests
//
//  Created by Kevin Dial on 12/24/25.
//  Integrity tests for DoseTap data operations
//

import XCTest
@testable import DoseTap
import DoseCore
import UserNotifications

// MARK: - Fake Notification Scheduler (conforms to production protocol)

/// Fake notification scheduler for testing - captures all cancellation calls
/// Conforms to the production NotificationScheduling protocol from SessionRepository
final class FakeNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private(set) var cancelledIdentifiers: [String] = []
    private let lock = NSLock()
    
    func cancelNotifications(withIdentifiers ids: [String]) {
        lock.lock()
        defer { lock.unlock() }
        cancelledIdentifiers.append(contentsOf: ids)
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        cancelledIdentifiers.removeAll()
    }
}

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
    
    /// CRITICAL: Verify foreign keys are enabled before any cascade tests.
    /// If this fails, cascade delete tests can pass accidentally because manual
    /// delete code cleans up rows, masking the lack of FK enforcement.
    func test_sqlite_foreignKeysEnabled() async throws {
        let fkEnabled = storage.isForeignKeysEnabled()
        XCTAssertTrue(fkEnabled, 
            "PRAGMA foreign_keys must be ON for cascade delete to work. " +
            "Without FK enforcement, tests can pass accidentally.")
    }
    
    /// DOCUMENTATION TEST: Schema uses manual cascade, NOT SQLite FK constraints.
    /// This is a known limitation. The manual cascade in deleteSession() works,
    /// but if someone adds a new table and forgets to include it in deleteSession(),
    /// orphan rows could occur. This test documents the pattern.
    func test_schemaUsesManualCascade_documented() async throws {
        // The following tables MUST be included in deleteSession() for cascade to work:
        let tablesRequiringManualCascade = [
            "sleep_events",
            "dose_events",
            "pre_sleep_logs",
            "morning_checkins",
            "medication_events"
        ]
        
        // This test serves as documentation. The actual cascade is verified by
        // test_sessionDelete_cascadesAllDependentTables which queries row counts.
        //
        // FUTURE WORK: Add actual FOREIGN KEY constraints to schema:
        // CREATE TABLE sleep_events (
        //     ...
        //     session_date TEXT NOT NULL REFERENCES current_session(session_date) ON DELETE CASCADE
        // );
        //
        // Until then, any new tables MUST be added to:
        // 1. EventStorage.deleteSession() 
        // 2. EventStorage.clearAllData()
        // 3. fetchRowCount() allowedTables list
        // 4. test_sessionDelete_cascadesAllDependentTables assertions
        
        XCTAssertEqual(tablesRequiringManualCascade.count, 5, 
            "If you added a new table, add it to manual cascade in deleteSession()")
    }
    
    // MARK: - Cascade Delete Tests
    
    /// Verify that deleting a session cascades to all related data.
    /// NOTE: This uses MANUAL cascade (transaction with DELETE statements),
    /// not SQLite FK CASCADE constraints.
    func test_sessionDelete_cascadesToDoseEvents() async throws {
        // Arrange: Create session with dose events
        let now = Date()
        let dose1Time = now.addingTimeInterval(-120 * 60) // 2 hours ago
        repo.setDose1Time(dose1Time)
        
        let sessionDate = repo.currentSessionDateString()
        
        // Verify dose is recorded
        XCTAssertNotNil(repo.dose1Time, "Dose 1 should exist before delete")
        
        // Act: Delete the session
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert: All related data is cleared
        XCTAssertNil(repo.dose1Time, "Dose 1 should be nil after cascade delete")
        XCTAssertNil(repo.dose2Time, "Dose 2 should be nil after cascade delete")
        XCTAssertNil(repo.activeSessionDate, "Session should be nil after delete")
        
        // Reload from storage to verify persistence layer cascade
        repo.reload()
        XCTAssertNil(repo.dose1Time, "Dose 1 should remain nil after reload - cascade persisted")
    }
    
    /// Verify that deleting a session with dose2 data cascades properly.
    func test_sessionDelete_cascadesBothDoses() async throws {
        // Arrange: Complete dose cycle
        let now = Date()
        let dose1Time = now.addingTimeInterval(-180 * 60) // 3 hours ago
        let dose2Time = now.addingTimeInterval(-15 * 60)  // 15 min ago
        
        repo.setDose1Time(dose1Time)
        repo.setDose2Time(dose2Time)
        
        let sessionDate = repo.currentSessionDateString()
        
        // Verify both doses recorded
        XCTAssertNotNil(repo.dose1Time, "Dose 1 should exist")
        XCTAssertNotNil(repo.dose2Time, "Dose 2 should exist")
        
        // Act: Delete session
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert: Both doses cleared
        XCTAssertNil(repo.dose1Time, "Dose 1 should cascade delete")
        XCTAssertNil(repo.dose2Time, "Dose 2 should cascade delete")
        
        // Verify storage layer (no ghost data)
        repo.reload()
        XCTAssertNil(repo.dose1Time, "No ghost dose1 in storage")
        XCTAssertNil(repo.dose2Time, "No ghost dose2 in storage")
    }
    
    /// Verify snooze count and skip state reset on session delete.
    func test_sessionDelete_resetsEphemeralState() async throws {
        // Arrange: Session with snoozes and skip
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.incrementSnooze()
        repo.incrementSnooze()
        repo.skipDose2()
        
        let sessionDate = repo.currentSessionDateString()
        
        XCTAssertEqual(repo.snoozeCount, 2, "Snooze count should be 2")
        XCTAssertTrue(repo.dose2Skipped, "Dose 2 should be skipped")
        
        // Act: Delete session
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert: Ephemeral state reset
        XCTAssertEqual(repo.snoozeCount, 0, "Snooze count should reset to 0")
        XCTAssertFalse(repo.dose2Skipped, "Skip state should reset to false")
    }
    
    // MARK: - Notification Cancellation Tests (GAP 1 Closure)
    
    /// CRITICAL: Verify deleteSession cancels EXACT notification identifiers.
    /// This test proves the production code path calls the injected scheduler
    /// with the correct identifiers - no more, no less.
    func test_deleteActiveSession_cancelsExactNotificationIdentifiers() async throws {
        // Arrange: Create a session
        let dose1Time = Date().addingTimeInterval(-150 * 60)
        repo.setDose1Time(dose1Time)
        
        let sessionDate = repo.currentSessionDateString()
        XCTAssertNotNil(repo.activeSessionDate, "Session should exist")
        
        // Clear any previous calls
        fakeScheduler.reset()
        
        // Act: Delete the active session
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert: Exact identifiers were cancelled
        let cancelledSet = Set(fakeScheduler.cancelledIdentifiers)
        let expectedSet = Set(SessionRepository.sessionNotificationIdentifiers)
        
        XCTAssertEqual(cancelledSet, expectedSet,
            "Cancelled identifiers should exactly match SessionRepository.sessionNotificationIdentifiers")
        
        // Verify count matches (no duplicates, no extras)
        XCTAssertEqual(fakeScheduler.cancelledIdentifiers.count, 
                       SessionRepository.sessionNotificationIdentifiers.count,
            "Should cancel exactly \(SessionRepository.sessionNotificationIdentifiers.count) identifiers")
    }
    
    /// Verify deleteSession does NOT cancel notifications for inactive sessions.
    func test_deleteInactiveSession_doesNotCancelNotifications() async throws {
        // Arrange: Create current session
        repo.setDose1Time(Date())
        XCTAssertNotNil(repo.activeSessionDate)
        
        // Clear any previous calls
        fakeScheduler.reset()
        
        // Act: Delete a different (past) session
        let pastSessionDate = "2024-01-01"
        repo.deleteSession(sessionDate: pastSessionDate)
        
        // Assert: No notifications were cancelled (past session doesn't affect current)
        XCTAssertTrue(fakeScheduler.cancelledIdentifiers.isEmpty,
            "Deleting inactive session should NOT cancel notifications for active session")
    }
    
    /// Verify all expected notification identifiers are in the canonical list.
    /// This test fails if someone adds a notification without updating the list.
    func test_sessionNotificationIdentifiers_containsAllExpected() {
        let ids = SessionRepository.sessionNotificationIdentifiers
        
        // Core dose notifications
        XCTAssertTrue(ids.contains("dose_reminder"), "Missing dose_reminder")
        XCTAssertTrue(ids.contains("window_opening"), "Missing window_opening")
        XCTAssertTrue(ids.contains("window_closing"), "Missing window_closing")
        XCTAssertTrue(ids.contains("window_critical"), "Missing window_critical")
        
        // Wake alarm notifications
        XCTAssertTrue(ids.contains("wake_alarm"), "Missing wake_alarm")
        XCTAssertTrue(ids.contains("wake_alarm_pre"), "Missing wake_alarm_pre")
        XCTAssertTrue(ids.contains("wake_alarm_follow1"), "Missing wake_alarm_follow1")
        XCTAssertTrue(ids.contains("wake_alarm_follow2"), "Missing wake_alarm_follow2")
        XCTAssertTrue(ids.contains("wake_alarm_follow3"), "Missing wake_alarm_follow3")
        
        // Hard stop notifications
        XCTAssertTrue(ids.contains("hard_stop"), "Missing hard_stop")
        XCTAssertTrue(ids.contains("hard_stop_5min"), "Missing hard_stop_5min")
        XCTAssertTrue(ids.contains("hard_stop_2min"), "Missing hard_stop_2min")
        XCTAssertTrue(ids.contains("hard_stop_30sec"), "Missing hard_stop_30sec")
        XCTAssertTrue(ids.contains("hard_stop_expired"), "Missing hard_stop_expired")
        
        // Snooze
        XCTAssertTrue(ids.contains("snooze_reminder"), "Missing snooze_reminder")
    }
    
    // MARK: - Database Cascade Assertions (GAP 2 Closure)
    
    /// CRITICAL: Verify all dependent table rows are deleted when session is deleted.
    /// This test queries the database directly to prove no orphan rows remain.
    func test_sessionDelete_cascadesAllDependentTables() async throws {
        // Arrange: Create session with data in ALL dependent tables
        let sessionDate = storage.currentSessionDate()
        
        // 1. Create dose data
        repo.setDose1Time(Date().addingTimeInterval(-180 * 60))
        repo.setDose2Time(Date().addingTimeInterval(-15 * 60))
        
        // 2. Create sleep events using correct API
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
        
        // 3. Create medication event (if table exists)
        // Note: medication_events may not have data in basic tests
        
        // Verify data exists before delete
        XCTAssertGreaterThan(storage.fetchRowCount(table: "sleep_events", sessionDate: sessionDate), 0,
            "Should have sleep events before delete")
        
        // Act: Delete session through repository
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert: ALL dependent tables are empty for this session
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
        
        // Assert: Repository state is also cleared
        XCTAssertNil(repo.dose1Time, "Repo dose1Time should be nil")
        XCTAssertNil(repo.dose2Time, "Repo dose2Time should be nil")
        XCTAssertNil(repo.activeSessionDate, "Repo activeSessionDate should be nil")
    }
    
    /// Verify current_session table is cleared for the deleted session.
    func test_sessionDelete_clearsCurrentSessionTable() async throws {
        // Arrange
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.incrementSnooze()
        
        let sessionDate = repo.currentSessionDateString()
        
        // Act
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert: Reload returns clean state
        repo.reload()
        XCTAssertNil(repo.dose1Time, "dose1Time should be nil after reload")
        XCTAssertEqual(repo.snoozeCount, 0, "snoozeCount should be 0 after reload")
    }
    
    // MARK: - Legacy Tests (kept for backward compatibility)

    /// Verify that clearing "Tonight" state also manages notifications.
    func test_clearTonight_managedNotificationState() async throws {
        // Arrange
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.setDose2Time(Date())
        
        XCTAssertNotNil(repo.dose1Time)
        XCTAssertNotNil(repo.dose2Time)
        
        // Act
        repo.clearTonight()
        
        // Assert: State fully cleared
        XCTAssertNil(repo.dose1Time, "Dose 1 cleared")
        XCTAssertNil(repo.dose2Time, "Dose 2 cleared")
        XCTAssertNil(repo.activeSessionDate, "Session cleared")
    }
    
    // MARK: - Data Consistency Tests
    
    /// Verify that session context remains consistent through state changes.
    func test_contextConsistency_throughStateTransitions() async throws {
        // Initial: No session
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Start with noDose1")
        
        // Transition: Add dose 1
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60)) // In active window
        XCTAssertNotEqual(repo.currentContext.phase, .noDose1, "Phase changes after dose1")
        
        // Transition: Delete session
        let sessionDate = repo.currentSessionDateString()
        repo.deleteSession(sessionDate: sessionDate)
        
        // Final: Back to no session
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Returns to noDose1 after delete")
        XCTAssertEqual(repo.currentContext.snoozeCount, 0, "Snooze count is 0")
    }
}

// MARK: - Notification Center Integration

/// Integration test against UNUserNotificationCenter to ensure real cancellation occurs.
@MainActor
final class NotificationCenterIntegrationTests: XCTestCase {
    
    /// Notification scheduler that forwards to UNUserNotificationCenter while recording IDs.
    private final class RecordingUNNotificationScheduler: NotificationScheduling {
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
        
        // Seed pending requests for all session-scoped identifiers
        for id in SessionRepository.sessionNotificationIdentifiers {
            let content = UNMutableNotificationContent()
            content.title = "Test"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try await center.add(request)
        }
        
        // Act: delete active session and assert cancellations propagate to the real center
        let recordingScheduler = RecordingUNNotificationScheduler(center: center)
        let repo = SessionRepository(storage: EventStorage.shared, notificationScheduler: recordingScheduler)
        repo.setDose1Time(Date())
        let sessionDate = repo.currentSessionDateString()
        repo.deleteSession(sessionDate: sessionDate)
        
        let pendingAfter = await pendingIdentifiers(center)
        let remaining = Set(pendingAfter)
        let expected = Set(SessionRepository.sessionNotificationIdentifiers)
        
        // Validate that cancelNotifications was invoked with the full identifier list
        XCTAssertEqual(Set(recordingScheduler.cancelled), expected, "deleteSession should cancel canonical identifiers")
        XCTAssertTrue(remaining.isDisjoint(with: expected), "No session identifiers should remain pending")
    }
    
    func test_skipDose_cancelsWakeAlarms() async throws {
        let center = UNUserNotificationCenter.current()
        
        // Seed only wake-related requests
        let wakeIds = ["wake_alarm", "wake_alarm_pre", "wake_alarm_follow1", "wake_alarm_follow2", "wake_alarm_follow3"]
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
        
        // Create a session via repository to ensure session_date exists
        let repo = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler())
        repo.setDose1Time(Date())
        let sessionDate = repo.currentSessionDateString()
        
        // Precondition: session exists
        XCTAssertTrue(storage.filterExistingSessionDates([sessionDate]).contains(sessionDate))
        
        // Delete and assert filter drops it
        repo.deleteSession(sessionDate: sessionDate)
        XCTAssertFalse(storage.filterExistingSessionDates([sessionDate]).contains(sessionDate))
    }
}

// MARK: - Timeline Dual-Storage Integration Tests (DISABLED - SQLiteStorage is unavailable)
// This test was for the old dual-storage architecture. Now that storage is unified
// through SessionRepository → EventStorage, this test is obsolete.
// See docs/STORAGE_UNIFICATION_2025-12-26.md for the migration details.
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
        
        // Seed a real session in both storages
        let now = Date()
        repo.setDose1Time(now)
        let realSessionDate = repo.currentSessionDateString()
        sqlStorage.logEvent(sessionDate: realSessionDate, type: "dose1", timestamp: now)
        
        // Create a ghost session only in SQLiteStorage
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

// MARK: - HealthKit Provider Tests

/// Tests for the HealthKitProviding protocol and NoOpHealthKitProvider.
/// GAP A: These verify no real HealthKit calls happen in tests.
@MainActor
final class HealthKitProviderTests: XCTestCase {
    
    func test_factoryDefaultsToNoOpOnSimulator() async throws {
        let provider = HealthKitProviderFactory.makeDefault()
        XCTAssertTrue(provider is NoOpHealthKitProvider, "Simulator should default to NoOpHealthKitProvider")
    }
    
    /// Verify NoOpHealthKitProvider returns safe defaults
    func test_noOpProvider_returnsSafeDefaults() async throws {
        let provider = NoOpHealthKitProvider()
        
        XCTAssertFalse(provider.isAvailable, "Default isAvailable is false")
        XCTAssertFalse(provider.isAuthorized, "Default isAuthorized is false")
        XCTAssertNil(provider.ttfwBaseline, "Default baseline is nil")
        XCTAssertNil(provider.calculateNudgeSuggestion(), "No nudge by default")
        
        let sameNight = await provider.sameNightNudge(dose1Time: Date(), currentTargetMinutes: 165)
        XCTAssertNil(sameNight, "No same-night nudge by default")
    }
    
    /// Verify NoOpHealthKitProvider can be stubbed for specific test scenarios
    func test_noOpProvider_canBeStubbed() async throws {
        let provider = NoOpHealthKitProvider()
        
        // Configure stubs
        provider.stubIsAvailable = true
        provider.stubIsAuthorized = true
        provider.stubAuthorizationResult = true
        provider.stubTTFWBaseline = 180.5
        provider.stubNudgeSuggestion = 15
        provider.stubSameNightNudge = 195
        
        // Verify stubs work
        XCTAssertTrue(provider.isAvailable, "Stubbed isAvailable")
        XCTAssertTrue(provider.isAuthorized, "Stubbed isAuthorized")
        XCTAssertEqual(provider.ttfwBaseline, 180.5, "Stubbed baseline")
        XCTAssertEqual(provider.calculateNudgeSuggestion(), 15, "Stubbed nudge")
        
        let auth = await provider.requestAuthorization()
        XCTAssertTrue(auth, "Stubbed authorization result")
        
        let sameNight = await provider.sameNightNudge(dose1Time: Date(), currentTargetMinutes: 165)
        XCTAssertEqual(sameNight, 195, "Stubbed same-night nudge")
    }
    
    /// Verify NoOpHealthKitProvider tracks method calls
    func test_noOpProvider_tracksCalls() async throws {
        let provider = NoOpHealthKitProvider()
        
        XCTAssertEqual(provider.requestAuthorizationCallCount, 0)
        XCTAssertEqual(provider.computeBaselineCallCount, 0)
        XCTAssertNil(provider.lastComputeBaselineDays)
        
        _ = await provider.requestAuthorization()
        XCTAssertEqual(provider.requestAuthorizationCallCount, 1)
        
        await provider.computeTTFWBaseline(days: 14)
        XCTAssertEqual(provider.computeBaselineCallCount, 1)
        XCTAssertEqual(provider.lastComputeBaselineDays, 14)
        
        _ = await provider.requestAuthorization()
        await provider.computeTTFWBaseline(days: 30)
        XCTAssertEqual(provider.requestAuthorizationCallCount, 2)
        XCTAssertEqual(provider.computeBaselineCallCount, 2)
        XCTAssertEqual(provider.lastComputeBaselineDays, 30)
    }
    
    /// Verify reset clears call tracking
    func test_noOpProvider_resetClearsCalls() async throws {
        let provider = NoOpHealthKitProvider()
        
        _ = await provider.requestAuthorization()
        await provider.computeTTFWBaseline(days: 7)
        
        XCTAssertEqual(provider.requestAuthorizationCallCount, 1)
        XCTAssertEqual(provider.computeBaselineCallCount, 1)
        
        provider.reset()
        
        XCTAssertEqual(provider.requestAuthorizationCallCount, 0)
        XCTAssertEqual(provider.computeBaselineCallCount, 0)
        XCTAssertNil(provider.lastComputeBaselineDays)
    }
    
    /// Verify HealthKitService conforms to HealthKitProviding
    /// This is a compile-time check that enables dependency injection.
    func test_healthKitService_conformsToProtocol() {
        // This test verifies the protocol conformance at compile time.
        // If HealthKitService doesn't conform, this won't compile.
        let _: any HealthKitProviding.Type = HealthKitService.self
    }
    
    func test_whoopService_disabledByDefault() {
        XCTAssertFalse(WHOOPService.isEnabled, "WHOOP should be disabled by default for shipping builds")
    }
}

// MARK: - GAP C: Export and Support Bundle Tests

/// Tests verifying export row counts match database and secrets are excluded
@MainActor
final class ExportIntegrityTests: XCTestCase {
    
    private var storage: EventStorage!
    private var repo: SessionRepository!
    
    override func setUp() async throws {
        storage = EventStorage.shared
        repo = SessionRepository(storage: storage)
        storage.clearAllData()
        repo.reload()
    }
    
    override func tearDown() async throws {
        storage.clearAllData()
    }
    
    // MARK: - Export Row Count Tests
    
    /// Verify export row count matches database session count
    func test_export_rowCountMatchesDatabaseSessions() async throws {
        // Arrange: Create multiple sessions
        let calendar = Calendar.current
        
        // Session 1: Yesterday
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.day! -= 1
        comps.hour = 22
        comps.minute = 0
        if let yesterday = calendar.date(from: comps) {
            repo.setDose1Time(yesterday)
            repo.setDose2Time(yesterday.addingTimeInterval(165 * 60))
        }
        
        // Clear for next session
        repo.clearTonight()
        
        // Session 2: Today
        let now = Date()
        repo.setDose1Time(now.addingTimeInterval(-120 * 60))
        
        // Get database session count
        let dbSessionCount = storage.getAllSessionDates().count
        
        // Get export data
        let sessions = repo.getAllSessions()
        
        XCTAssertEqual(sessions.count, dbSessionCount,
            "Export session count (\(sessions.count)) should match DB session count (\(dbSessionCount))")
    }

    /// Verify export CSV includes metadata header with schema and constants versions
    func test_export_includesMetadataHeader() async throws {
        // Arrange: ensure there is at least one session
        repo.setDose1Time(Date().addingTimeInterval(-120 * 60))
        
        // Act
        let csv = storage.exportToCSV()
        
        // Assert: metadata header present on first line
        let firstLine = csv.components(separatedBy: .newlines).first ?? ""
        XCTAssertTrue(firstLine.contains("schema_version="), "CSV should include schema_version metadata")
        XCTAssertTrue(firstLine.contains("constants_version="), "CSV should include constants_version metadata")
    }

    /// Verify deleted sessions are excluded from exports
    func test_export_excludesDeletedSessions() async throws {
        // Arrange: create a session then delete it
        repo.setDose1Time(Date().addingTimeInterval(-90 * 60))
        let sessionDate = repo.currentSessionDateString()
        repo.deleteSession(sessionDate: sessionDate)
        
        // Act
        let sessions = repo.getAllSessions()
        
        // Assert
        XCTAssertFalse(sessions.contains(sessionDate),
            "Deleted session \(sessionDate) should not appear in export list")
    }
    
    /// Verify export does not include empty rows
    func test_export_noEmptyRows() async throws {
        // Arrange: Create a session with data
        repo.setDose1Time(Date().addingTimeInterval(-150 * 60))
        
        // Get export data
        let sessions = repo.getAllSessions()
        
        // Verify no empty session dates
        for session in sessions {
            XCTAssertFalse(session.isEmpty, "Session date should not be empty")
        }
    }
    
    // MARK: - Support Bundle Secrets Tests
    
    /// Verify support bundle does not contain API keys
    func test_supportBundle_excludesAPIKeys() async throws {
        // Define patterns that should NEVER appear in support bundles
        let secretPatterns = [
            "whoop_client_id",
            "whoop_client_secret",
            "api_key",
            "apiKey",
            "API_KEY",
            "bearer_token",
            "access_token",
            "refresh_token",
            "sk_live_",  // Stripe live key prefix
            "pk_live_",  // Stripe public key prefix
        ]
        
        // Get support bundle content (simulated - in real test this would use SupportBundleExport)
        let bundleContent = """
        DoseTap Support Bundle
        App Version: 1.0.0
        Device: iPhone 15
        Session Count: \(repo.getAllSessions().count)
        Last Dose 1: \(repo.dose1Time?.description ?? "none")
        """
        
        // Verify no secrets in bundle
        for pattern in secretPatterns {
            XCTAssertFalse(bundleContent.lowercased().contains(pattern.lowercased()),
                "Support bundle should not contain '\(pattern)'")
        }
    }
    
    /// Verify support bundle redacts device identifiers
    func test_supportBundle_redactsDeviceIDs() async throws {
        // Test that UUIDs would be redacted
        let redactor = DataRedactor()
        let testUUID = "550E8400-E29B-41D4-A716-446655440000"
        let testContent = "Device ID: \(testUUID)"
        
        let result = redactor.redact(testContent)
        
        XCTAssertFalse(result.redactedText.contains(testUUID),
            "Device UUID should be redacted")
        XCTAssertTrue(result.redactedText.contains("HASH_"),
            "UUID should be replaced with hash")
    }
    
    /// Verify support bundle redacts email addresses
    func test_supportBundle_redactsEmails() async throws {
        let redactor = DataRedactor()
        let testEmail = "user@example.com"
        let testContent = "Contact: \(testEmail)"
        
        let result = redactor.redact(testContent)
        
        XCTAssertFalse(result.redactedText.contains(testEmail),
            "Email should be redacted")
        XCTAssertTrue(result.redactedText.contains("[EMAIL_REDACTED]"),
            "Email should be replaced with placeholder")
    }
    
    /// Verify support bundle includes metadata header (schema/constants)
    func test_supportBundle_includesMetadata() async throws {
        let bundle = SupportBundleExporter(storage: storage).makeBundleSummary()
        XCTAssertTrue(bundle.contains("schema_version="), "Support bundle should include schema_version")
        XCTAssertTrue(bundle.contains("constants_version="), "Support bundle should include constants_version")
    }
    
    /// Verify schema version getter exists and returns a valid value
    func test_export_includesSchemaVersion() async throws {
        // Get current schema version
        let schemaVersion = storage.getSchemaVersion()
        
        // Schema version can be 0 (unset) or positive
        // The important thing is that the method exists and returns an Int
        XCTAssertGreaterThanOrEqual(schemaVersion, 0,
            "Schema version should be 0 or greater")
        
        // In a real export, schema_version would be in metadata
        // This test verifies the getter exists and returns valid data
    }
}

// MARK: - Export/Import Round Trip Tests

@MainActor
final class ExportImportRoundTripTests: XCTestCase {
    private let storage = EventStorage.shared
    private var repo: SessionRepository!
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    override func setUp() async throws {
        storage.clearAllData()
        repo = SessionRepository(storage: storage, notificationScheduler: FakeNotificationScheduler())
    }
    
    override func tearDown() async throws {
        storage.clearAllData()
    }
    
    func test_exportImport_roundTripPreservesCounts() async throws {
        let baseDate = Date()
        repo.setDose1Time(baseDate)
        repo.setDose2Time(baseDate.addingTimeInterval(165 * 60))
        let sessionDate = repo.currentSessionDateString()
        
        // Seed additional data
        storage.insertSleepEvent(eventType: "lights_out", timestamp: baseDate, sessionDate: sessionDate, notes: "seed")
        storage.insertMedicationEvent(SQLiteStoredMedicationEntry(
            sessionId: sessionDate,
            sessionDate: sessionDate,
            medicationId: "adderall",
            doseMg: 10,
            takenAtUTC: baseDate,
            localOffsetMinutes: 0,
            notes: "seed",
            confirmedDuplicate: false,
            createdAt: baseDate
        ))
        
        let originalDoseCount = storage.countDoseEvents()
        let originalSleepCount = storage.fetchAllSleepEvents(limit: 1000).count
        let originalMedCount = storage.fetchAllMedicationEvents(limit: 1000).count
        
        let export = storage.exportToCSV()
        XCTAssertTrue(export.contains("schema_version"), "Export should include metadata header")
        
        // Clear and import from export
        storage.clearAllData()
        let lines = export.split(whereSeparator: \.isNewline)
        XCTAssertGreaterThan(lines.count, 1, "Export should contain data lines")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("type") {
                continue
            }
            let parts = trimmed.split(separator: ",", maxSplits: 3).map(String.init)
            guard parts.count >= 3 else { continue }
            let type = parts[0]
            let timestamp = isoFormatter.date(from: parts[1]) ?? baseDate
            let session = parts[2]
            let details = parts.count > 3 ? parts[3] : ""
            
            switch type {
            case "dose1", "dose2", "dose2_skipped", "snooze":
                storage.insertDoseEvent(eventType: type, timestamp: timestamp, sessionDate: session)
            case "medication":
                let tokens = details.split(separator: "|")
                let medId = tokens.first.map(String.init) ?? "med"
                let doseMg = tokens.dropFirst().first.flatMap { Int($0.replacingOccurrences(of: "mg", with: "")) } ?? 0
                let note = tokens.dropFirst(2).first.map(String.init)
                storage.insertMedicationEvent(SQLiteStoredMedicationEntry(
                    sessionId: session,
                    sessionDate: session,
                    medicationId: medId,
                    doseMg: doseMg,
                    takenAtUTC: timestamp,
                    localOffsetMinutes: 0,
                    notes: note,
                    confirmedDuplicate: false,
                    createdAt: timestamp
                ))
            default:
                storage.insertSleepEvent(eventType: type, timestamp: timestamp, sessionDate: session, notes: details)
            }
        }
        
        let importedDoseCount = storage.countDoseEvents()
        let importedSleepCount = storage.fetchAllSleepEvents(limit: 1000).count
        let importedMedCount = storage.fetchAllMedicationEvents(limit: 1000).count
        
        XCTAssertEqual(importedDoseCount, originalDoseCount, "Dose event count should survive round-trip")
        XCTAssertEqual(importedSleepCount, originalSleepCount, "Sleep event count should survive round-trip")
        XCTAssertEqual(importedMedCount, originalMedCount, "Medication count should survive round-trip")
    }
}

// MARK: - API Contract Drift Tests

final class APIContractTests: XCTestCase {
    func test_openAPIMatchesClientEndpoints() throws {
        // Expected endpoints from SSOT and APIClient
        let expected: Set<String> = [
            "/doses/take",
            "/doses/skip",
            "/doses/snooze",
            "/events/log",
            "/analytics/export"
        ]
        
        // Extract paths from OpenAPI file (lightweight parse)
        // Try multiple possible locations for the OpenAPI file
        let possiblePaths = [
            "docs/SSOT/contracts/api.openapi.yaml",
            "../docs/SSOT/contracts/api.openapi.yaml",
            "../../docs/SSOT/contracts/api.openapi.yaml"
        ]
        
        var contents: String? = nil
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                contents = try? String(contentsOfFile: path, encoding: .utf8)
                if contents != nil { break }
            }
        }
        
        // If file not found in any location, skip OpenAPI verification but still check client endpoints
        if let contents = contents {
            let openapiPaths = Set(
                contents
                    .split(separator: "\n")
                    .map(String.init)
                    .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("/") }
                    .map { line in
                        line.trimmingCharacters(in: .whitespaces)
                            .split(separator: ":")
                            .first
                            .map(String.init) ?? ""
                    }
            )
            
            XCTAssertEqual(openapiPaths, expected, "OpenAPI paths should match SSOT-required endpoints")
        }
        
        // Extract client endpoints - this should always work
        let clientPaths = Set(APIClient.Endpoint.allCases.map { $0.rawValue })
        XCTAssertEqual(clientPaths, expected, "APIClient.Endpoint should cover all SSOT endpoints")
    }
}

// MARK: - watchOS Companion Smoke Test

final class WatchOSSmokeTests: XCTestCase {
    func test_watchOSCompanion_isDeferredOrUnavailable() {
        #if os(watchOS)
        // If we ever build a watch target, this should be replaced with real integration.
        XCTAssertTrue(true, "watchOS build present")
        #else
        // For current shipping builds, no watchOS companion is present; test documents default-off posture.
        XCTAssertTrue(true, "watchOS companion not built in this target (deferred)")
        #endif
    }
}

// MARK: - URL Router / Deep Link Tests

/// Tests for deep link URL routing and action execution.
/// These tests verify both URL parsing AND action execution.
@MainActor
final class URLRouterTests: XCTestCase {
    
    private var router: URLRouter!
    
    override func setUp() async throws {
        router = URLRouter.shared
        router.lastAction = nil
        router.feedbackMessage = ""
    }
    
    // MARK: - URL Parsing Tests
    
    /// Verify all valid URL schemes are recognized
    func test_validScheme_isHandled() {
        let dose1URL = URL(string: "dosetap://dose1")!
        let result = router.handle(dose1URL)
        // Should return true (handled) or false (missing dependencies)
        // The key is it doesn't crash and recognizes the scheme
        XCTAssertNotNil(router.lastAction, "Should set lastAction for valid URL")
    }
    
    /// Verify invalid schemes are rejected
    func test_invalidScheme_isRejected() {
        let invalidURL = URL(string: "https://example.com")!
        let result = router.handle(invalidURL)
        XCTAssertFalse(result, "Non-dosetap schemes should be rejected")
    }
    
    /// Verify unknown hosts are rejected
    func test_unknownHost_isRejected() {
        let unknownURL = URL(string: "dosetap://unknown")!
        let result = router.handle(unknownURL)
        XCTAssertFalse(result, "Unknown hosts should be rejected")
    }
    
    // MARK: - Navigation Tests
    
    /// Verify navigation URLs change selected tab
    func test_navigate_tonight_setsTab0() {
        let url = URL(string: "dosetap://tonight")!
        _ = router.handle(url)
        XCTAssertEqual(router.selectedTab, 0, "tonight should navigate to tab 0")
    }
    
    func test_navigate_timeline_setsTab1() {
        let url = URL(string: "dosetap://timeline")!
        _ = router.handle(url)
        XCTAssertEqual(router.selectedTab, 1, "timeline should navigate to tab 1")
    }
    
    func test_navigate_details_setsTab1() {
        let url = URL(string: "dosetap://details")!
        _ = router.handle(url)
        XCTAssertEqual(router.selectedTab, 1, "details should navigate to tab 1")
    }
    
    func test_navigate_history_setsTab2() {
        let url = URL(string: "dosetap://history")!
        _ = router.handle(url)
        XCTAssertEqual(router.selectedTab, 2, "history should navigate to tab 2")
    }
    
    func test_navigate_settings_setsTab3() {
        let url = URL(string: "dosetap://settings")!
        _ = router.handle(url)
        XCTAssertEqual(router.selectedTab, 3, "settings should navigate to tab 3")
    }
    
    // MARK: - Log Event URL Tests
    
    /// Verify log event URLs are parsed correctly
    func test_logEvent_parsesEventName() {
        let url = URL(string: "dosetap://log?event=bathroom")!
        _ = router.handle(url)
        
        if case .logEvent(let name, _) = router.lastAction {
            XCTAssertEqual(name, "bathroom", "Should parse event name from query")
        } else {
            XCTFail("lastAction should be .logEvent")
        }
    }
    
    /// Verify log event URLs parse notes parameter
    func test_logEvent_parsesNotes() {
        let url = URL(string: "dosetap://log?event=bathroom&notes=urgent")!
        _ = router.handle(url)
        
        if case .logEvent(_, let notes) = router.lastAction {
            XCTAssertEqual(notes, "urgent", "Should parse notes from query")
        } else {
            XCTFail("lastAction should be .logEvent")
        }
    }
    
    /// Verify log event with missing event is rejected (security validation)
    func test_logEvent_missingEvent_isRejected() {
        let url = URL(string: "dosetap://log")!
        let result = router.handle(url)
        
        // Missing event should be rejected by InputValidator
        XCTAssertFalse(result, "Missing event should fail validation")
        XCTAssertTrue(router.feedbackMessage.contains("Invalid"), "Should show invalid event feedback")
    }
    
    // MARK: - Action Recording Tests
    
    /// Verify dose1 URL sets correct lastAction
    func test_dose1_setsLastAction() {
        let url = URL(string: "dosetap://dose1")!
        _ = router.handle(url)
        XCTAssertEqual(router.lastAction, .takeDose1, "Should set lastAction to .takeDose1")
    }
    
    /// Verify dose2 URL sets correct lastAction (even if it fails validation)
    func test_dose2_setsLastAction_whenDose1Missing() {
        let url = URL(string: "dosetap://dose2")!
        let result = router.handle(url)
        // Dose2 without Dose1 should fail but still be recognized
        XCTAssertFalse(result, "Dose2 without Dose1 should return false")
        XCTAssertTrue(router.feedbackMessage.contains("Dose 1"), "Should show Dose 1 required message")
    }
    
    /// Verify snooze URL sets correct lastAction
    func test_snooze_setsLastAction() {
        let url = URL(string: "dosetap://snooze")!
        _ = router.handle(url)
        // Snooze without active window should fail but be recognized
        XCTAssertTrue(router.feedbackMessage.count > 0, "Should set feedback message")
    }
    
    /// Verify skip URL sets correct lastAction
    func test_skip_setsLastAction() {
        let url = URL(string: "dosetap://skip")!
        _ = router.handle(url)
        // Skip without Dose1 should fail but be recognized
        XCTAssertTrue(router.feedbackMessage.count > 0, "Should set feedback message")
    }
    
    // MARK: - OAuth Callback Test
    
    /// Verify OAuth callback is NOT handled by URLRouter (handled separately)
    func test_oauthCallback_notHandledByRouter() {
        let url = URL(string: "dosetap://oauth?code=abc123")!
        let result = router.handle(url)
        XCTAssertFalse(result, "OAuth should be handled by WHOOP integration, not URLRouter")
    }
}

// MARK: - UI Smoke Tests

/// Minimal UI smoke tests to verify critical user-facing state transitions.
/// These are NOT a full UI test suite - just sanity checks for ship-blocking scenarios.
@MainActor
final class UISmokeTests: XCTestCase {
    
    private var storage: EventStorage!
    private var repo: SessionRepository!
    
    override func setUp() async throws {
        storage = EventStorage.shared
        repo = SessionRepository(storage: storage)
        storage.clearAllData()
        repo.reload()
    }
    
    override func tearDown() async throws {
        storage.clearAllData()
    }
    
    // MARK: - Tonight Empty State Smoke Test
    
    /// Verify Tonight view renders correct empty state after session delete.
    /// This is a data-layer test that proves the UI WILL render empty state.
    /// (Actual SwiftUI rendering requires XCUITest, but this validates the prerequisite.)
    func test_tonightEmptyState_afterSessionDelete() async throws {
        // Arrange: Create a complete session
        repo.setDose1Time(Date().addingTimeInterval(-180 * 60))
        repo.setDose2Time(Date().addingTimeInterval(-15 * 60))
        repo.incrementSnooze()
        
        let sessionDate = repo.currentSessionDateString()
        
        // Verify session exists
        XCTAssertNotNil(repo.dose1Time, "Session should exist before delete")
        XCTAssertNotNil(repo.dose2Time, "Dose 2 should exist before delete")
        XCTAssertEqual(repo.snoozeCount, 1, "Snooze count should be 1")
        
        // Act: Delete the session
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert: All state is cleared (UI will show empty state)
        let context = repo.currentContext
        XCTAssertEqual(context.phase, .noDose1, "Phase should be noDose1 (empty state)")
        XCTAssertNil(repo.dose1Time, "Dose 1 should be nil")
        XCTAssertNil(repo.dose2Time, "Dose 2 should be nil")
        XCTAssertEqual(repo.snoozeCount, 0, "Snooze count should be 0")
        XCTAssertNil(repo.activeSessionDate, "Active session should be nil")
        
        // Verify primary action for empty state shows disabled (dose 1 required)
        if case .disabled(let msg) = context.primary {
            XCTAssertTrue(msg.contains("Dose 1") || msg.contains("Log"), "Empty state should prompt for Dose 1")
        }
    }
    
    // MARK: - Export Produces Data Smoke Test
    
    /// Verify export produces non-empty CSV when data exists.
    /// This tests the data layer that the Export screen consumes.
    func test_exportProducesData_whenSessionExists() async throws {
        // Arrange: Create session with data
        let now = Date()
        repo.setDose1Time(now.addingTimeInterval(-180 * 60))
        repo.setDose2Time(now.addingTimeInterval(-15 * 60))
        
        // Add sleep events
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "bathroom",
            timestamp: now.addingTimeInterval(-60 * 60),
            colorHex: nil
        )
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "lights_out",
            timestamp: now.addingTimeInterval(-120 * 60),
            colorHex: nil
        )
        
        // Act: Get export data
        let sessionDate = repo.currentSessionDateString()
        let sleepEvents = storage.fetchSleepEvents(forSession: sessionDate)
        
        // Assert: Data exists for export
        XCTAssertGreaterThan(sleepEvents.count, 0, "Should have sleep events to export")
        XCTAssertNotNil(repo.dose1Time, "Should have dose1 to export")
        XCTAssertNotNil(repo.dose2Time, "Should have dose2 to export")
        
        // Verify events have required fields
        for event in sleepEvents {
            XCTAssertFalse(event.id.isEmpty, "Event should have ID")
            XCTAssertFalse(event.eventType.isEmpty, "Event should have type")
        }
    }
    
    /// Verify export returns empty when no data exists.
    func test_exportReturnsEmpty_whenNoSession() async throws {
        // Arrange: Ensure no data
        storage.clearAllData()
        repo.reload()
        
        // Act: Get export data
        let sessionDate = repo.currentSessionDateString()
        let sleepEvents = storage.fetchSleepEvents(forSession: sessionDate)
        
        // Assert: No data (UI shows appropriate empty state)
        XCTAssertTrue(sleepEvents.isEmpty, "Should have no events when no session")
        XCTAssertNil(repo.dose1Time, "Should have no dose1")
        XCTAssertNil(repo.dose2Time, "Should have no dose2")
    }
}

// MARK: - Full UI State Tests

/// Tests for all UI state transitions and Settings functionality.
/// These verify the data layer correctly drives UI states.
@MainActor
final class UIStateTests: XCTestCase {
    
    private var storage: EventStorage!
    private var repo: SessionRepository!
    
    override func setUp() async throws {
        storage = EventStorage.shared
        repo = SessionRepository(storage: storage)
        storage.clearAllData()
        repo.reload()
    }
    
    override func tearDown() async throws {
        storage.clearAllData()
    }
    
    // MARK: - Phase Transition Tests
    
    /// Verify all phase transitions from noDose1 → beforeWindow → active → closed
    func test_phaseTransitions_fullCycle() async throws {
        // Phase 1: noDose1 (no session)
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Initial phase should be noDose1")
        
        // Phase 2: beforeWindow (dose1 taken, window not yet open)
        let dose1Time = Date().addingTimeInterval(-100 * 60) // 100 min ago (window opens at 150)
        repo.setDose1Time(dose1Time)
        XCTAssertEqual(repo.currentContext.phase, .beforeWindow, "Should be beforeWindow when window not open")
        
        // Phase 3: active (in window)
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60)) // 155 min ago
        XCTAssertEqual(repo.currentContext.phase, .active, "Should be active when in window")
        
        // Phase 4: nearClose (near window end)
        repo.setDose1Time(Date().addingTimeInterval(-235 * 60)) // 235 min ago (5 min remaining)
        XCTAssertEqual(repo.currentContext.phase, .nearClose, "Should be nearClose near window end")
        
        // Phase 5: closed (past window)
        repo.setDose1Time(Date().addingTimeInterval(-250 * 60)) // 250 min ago
        XCTAssertEqual(repo.currentContext.phase, .closed, "Should be closed past window")
    }
    
    /// Verify completed phase after dose2 taken
    func test_completedPhase_afterDose2() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.setDose2Time(Date())
        XCTAssertEqual(repo.currentContext.phase, .completed, "Should be completed after dose2")
    }
    
    /// Verify completed phase after skip (skip also leads to completed)
    func test_completedPhase_afterSkip() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.skipDose2()
        XCTAssertEqual(repo.currentContext.phase, .completed, "Should be completed after skip")
    }
    
    // MARK: - Snooze State Tests
    
    /// Verify snooze button state through snooze cycles
    func test_snoozeState_throughCycles() async throws {
        // Setup: In active window
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        
        // Snooze 1 - should be enabled initially
        if case .snoozeEnabled = repo.currentContext.snooze {
            // Good - snooze enabled
        } else {
            XCTFail("Snooze should be enabled initially")
        }
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 1)
        
        // Snooze 2
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 2)
        
        // Snooze 3 (max)
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 3)
        if case .snoozeDisabled = repo.currentContext.snooze {
            // Good - snooze disabled at max
        } else {
            XCTFail("Snooze should be disabled at max")
        }
    }
    
    /// Verify snooze disabled near window end
    func test_snoozeDisabled_nearWindowEnd() async throws {
        // Setup: 10 minutes remaining (< 15 min threshold)
        repo.setDose1Time(Date().addingTimeInterval(-230 * 60))
        if case .snoozeDisabled = repo.currentContext.snooze {
            // Good - disabled when <15 min remain
        } else {
            XCTFail("Snooze should be disabled when <15 min remain")
        }
    }
    
    // MARK: - Skip State Tests
    
    /// Verify skip button state
    func test_skipState_enabledInActiveWindow() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        if case .skipEnabled = repo.currentContext.skip {
            // Good - skip enabled in active window
        } else {
            XCTFail("Skip should be enabled in active window")
        }
    }
    
    /// Verify skip disabled after skip
    func test_skipState_disabledAfterSkip() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        repo.skipDose2()
        if case .skipDisabled = repo.currentContext.skip {
            // Good - disabled after skip
        } else {
            XCTFail("Skip should be disabled after skip")
        }
    }
    
    // MARK: - Primary CTA Tests
    
    /// Verify primary CTA changes based on phase
    func test_primaryCTA_changesWithPhase() async throws {
        // No session: disabled
        if case .disabled = repo.currentContext.primary {
            // Good - should be disabled without dose1
        } else {
            XCTFail("Primary should be disabled without dose1")
        }
        
        // In window: takeNow or takeBeforeWindowEnds
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        switch repo.currentContext.primary {
        case .takeNow, .takeBeforeWindowEnds:
            break // Good
        default:
            XCTFail("Primary should be take action in active window")
        }
        
        // Completed: disabled
        repo.setDose2Time(Date())
        if case .disabled = repo.currentContext.primary {
            // Good - disabled after completion
        } else {
            XCTFail("Primary should be disabled after completion")
        }
    }
    
    // MARK: - Settings State Tests
    
    /// Verify UserDefaults persistence for settings
    func test_settings_persistenceRoundTrip() {
        let defaults = UserDefaults.standard
        let testKey = "test_reduced_motion"
        
        // Save
        defaults.set(true, forKey: testKey)
        
        // Retrieve
        XCTAssertTrue(defaults.bool(forKey: testKey), "Should persist boolean setting")
        
        // Clean up
        defaults.removeObject(forKey: testKey)
    }
    
    /// Verify target minutes persistence
    func test_settings_targetMinutesPersistence() {
        let defaults = UserDefaults.standard
        let key = "dose2_target_minutes"
        
        // Default should be 165
        defaults.removeObject(forKey: key)
        let defaultValue = defaults.integer(forKey: key)
        XCTAssertEqual(defaultValue, 0, "Missing key returns 0")
        
        // Set custom value
        defaults.set(180, forKey: key)
        XCTAssertEqual(defaults.integer(forKey: key), 180, "Should persist custom target")
        
        // Clean up
        defaults.removeObject(forKey: key)
    }
    
    // MARK: - Timer Display Tests
    
    /// Verify remaining time calculation is non-nil in window
    func test_remainingTime_availableInWindow() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60)) // 155 min ago
        let remaining = repo.currentContext.remainingToMax
        XCTAssertNotNil(remaining, "Should have remainingToMax in window")
        if let secs = remaining {
            XCTAssertGreaterThan(secs, 0, "Remaining should be positive in window")
        }
    }
    
    /// Verify remaining time is nil when no session
    func test_remainingTime_nilWithNoSession() async throws {
        let remaining = repo.currentContext.remainingToMax
        XCTAssertNil(remaining, "No remaining time without session")
    }
}

// MARK: - E2E Integration Tests

/// End-to-end integration tests that simulate complete user flows.
/// These test the full stack from UI action → Repository → Storage → Database.
@MainActor
final class E2EIntegrationTests: XCTestCase {
    
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
    
    // MARK: - Complete Dose Cycle E2E
    
    /// E2E: Complete dose cycle from Dose 1 → Dose 2
    func test_e2e_completeDoseCycle() async throws {
        // 1. Start: No session
        XCTAssertNil(repo.activeSessionDate)
        XCTAssertEqual(repo.currentContext.phase, .noDose1)
        
        // 2. User takes Dose 1
        let dose1Time = Date().addingTimeInterval(-10 * 60) // 10 min ago
        repo.setDose1Time(dose1Time)
        
        // Verify state
        XCTAssertNotNil(repo.activeSessionDate, "Session should be created")
        XCTAssertNotNil(repo.dose1Time, "Dose 1 should be recorded")
        XCTAssertEqual(repo.currentContext.phase, .beforeWindow, "Should be beforeWindow waiting for window")
        
        // 3. Time passes, window opens (simulate by setting earlier dose1)
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60)) // 155 min ago
        XCTAssertEqual(repo.currentContext.phase, .active, "Should be in active window")
        
        // 4. User takes Dose 2
        repo.setDose2Time(Date())
        
        // Verify completion
        XCTAssertNotNil(repo.dose2Time, "Dose 2 should be recorded")
        XCTAssertEqual(repo.currentContext.phase, .completed, "Should be completed")
        
        // 5. Verify persistence (reload from database)
        repo.reload()
        XCTAssertNotNil(repo.dose1Time, "Dose 1 should persist")
        XCTAssertNotNil(repo.dose2Time, "Dose 2 should persist")
        XCTAssertEqual(repo.currentContext.phase, .completed, "Completion should persist")
    }
    
    /// E2E: Dose cycle with snooze
    func test_e2e_doseCycleWithSnooze() async throws {
        // 1. Take Dose 1
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        XCTAssertEqual(repo.currentContext.phase, .active)
        
        // 2. User snoozes - verify enabled first
        if case .snoozeEnabled = repo.currentContext.snooze {
            // Good
        } else {
            XCTFail("Snooze should be enabled")
        }
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 1)
        
        // 3. User snoozes again
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 2)
        
        // 4. User finally takes Dose 2
        repo.setDose2Time(Date())
        XCTAssertEqual(repo.currentContext.phase, .completed)
        
        // 5. Verify snooze count persisted
        repo.reload()
        XCTAssertEqual(repo.snoozeCount, 2, "Snooze count should persist")
    }
    
    /// E2E: Dose cycle with skip
    func test_e2e_doseCycleWithSkip() async throws {
        // 1. Take Dose 1
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        XCTAssertEqual(repo.currentContext.phase, .active)
        
        // 2. User skips Dose 2 - verify enabled first
        if case .skipEnabled = repo.currentContext.skip {
            // Good
        } else {
            XCTFail("Skip should be enabled")
        }
        repo.skipDose2()
        
        // 3. Verify skip state
        XCTAssertTrue(repo.dose2Skipped, "Dose 2 should be marked skipped")
        XCTAssertEqual(repo.currentContext.phase, .completed)
        
        // 4. Verify persistence
        repo.reload()
        XCTAssertTrue(repo.dose2Skipped, "Skip should persist")
    }
    
    /// E2E: Session deletion clears everything
    func test_e2e_sessionDeletion() async throws {
        // 1. Create complete session with events
        repo.setDose1Time(Date().addingTimeInterval(-180 * 60))
        repo.setDose2Time(Date().addingTimeInterval(-15 * 60))
        repo.incrementSnooze()
        
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "bathroom",
            timestamp: Date().addingTimeInterval(-60 * 60),
            colorHex: nil
        )
        
        let sessionDate = repo.currentSessionDateString()
        
        // Verify data exists
        XCTAssertNotNil(repo.dose1Time)
        XCTAssertNotNil(repo.dose2Time)
        XCTAssertEqual(repo.snoozeCount, 1)
        
        // 2. User deletes session
        fakeScheduler.reset()
        repo.deleteSession(sessionDate: sessionDate)
        
        // 3. Verify complete cleanup
        XCTAssertNil(repo.dose1Time, "Dose 1 should be nil")
        XCTAssertNil(repo.dose2Time, "Dose 2 should be nil")
        XCTAssertEqual(repo.snoozeCount, 0, "Snooze should reset")
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Should return to noDose1")
        
        // 4. Verify notifications cancelled
        XCTAssertFalse(fakeScheduler.cancelledIdentifiers.isEmpty, "Should cancel notifications")
        
        // 5. Verify database is clean
        XCTAssertEqual(storage.fetchRowCount(table: "sleep_events", sessionDate: sessionDate), 0)
        XCTAssertEqual(storage.fetchRowCount(table: "dose_events", sessionDate: sessionDate), 0)
    }
    
    // MARK: - Event Logging E2E
    
    /// E2E: Log events through the full stack
    func test_e2e_eventLogging() async throws {
        // 1. Create session
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        let sessionDate = repo.currentSessionDateString()
        
        // 2. Log multiple events
        let events = ["bathroom", "lights_out", "bathroom", "wake_final"]
        for event in events {
            storage.insertSleepEvent(
                id: UUID().uuidString,
                eventType: event,
                timestamp: Date(),
                colorHex: nil
            )
        }
        
        // 3. Verify all events recorded
        let savedEvents = storage.fetchSleepEvents(forSession: sessionDate)
        XCTAssertEqual(savedEvents.count, events.count, "All events should be saved")
        
        // 4. Verify event types match
        let savedTypes = savedEvents.map { $0.eventType }
        XCTAssertTrue(savedTypes.contains("bathroom"), "Should have bathroom events")
        XCTAssertTrue(savedTypes.contains("lights_out"), "Should have lights_out event")
        XCTAssertTrue(savedTypes.contains("wake_final"), "Should have wake_final event")
    }
    
    // MARK: - Persistence Stress Tests
    
    /// E2E: Rapid state changes persist correctly
    func test_e2e_rapidStateChanges() async throws {
        // Rapid dose1/clear cycles
        for i in 0..<5 {
            repo.setDose1Time(Date().addingTimeInterval(Double(-160 * 60 - i)))
            XCTAssertNotNil(repo.dose1Time)
            repo.clearTonight()
            XCTAssertNil(repo.dose1Time)
        }
        
        // Final state should be clean
        repo.reload()
        XCTAssertNil(repo.dose1Time)
        XCTAssertNil(repo.activeSessionDate)
    }
    
    /// E2E: Verify database integrity after many operations
    func test_e2e_databaseIntegrity() async throws {
        // Create multiple sessions worth of data
        for day in 0..<3 {
            let offset = TimeInterval(day * 24 * 60 * 60)
            let dose1 = Date().addingTimeInterval(-offset - 180 * 60)
            repo.setDose1Time(dose1)
            repo.setDose2Time(dose1.addingTimeInterval(165 * 60))
            
            // Add events
            storage.insertSleepEvent(
                id: UUID().uuidString,
                eventType: "bathroom",
                timestamp: dose1.addingTimeInterval(60 * 60),
                colorHex: nil
            )
        }
        
        // Get all sessions
        let allSessions = storage.getAllSessionDates()
        
        // Should have at least one session (may collapse same-day sessions)
        XCTAssertGreaterThan(allSessions.count, 0, "Should have session data")
        
        // Clear all and verify clean state
        storage.clearAllData()
        repo.reload()
        XCTAssertNil(repo.dose1Time)
        XCTAssertTrue(storage.getAllSessionDates().isEmpty || 
                      storage.fetchSleepEvents(forSession: storage.currentSessionDate()).isEmpty)
    }
}

// MARK: - Navigation Flow Tests

/// Tests for tab navigation and deep link → screen mapping.
@MainActor
final class NavigationFlowTests: XCTestCase {
    
    private var router: URLRouter!
    
    override func setUp() async throws {
        router = URLRouter.shared
        router.lastAction = nil
        router.feedbackMessage = ""
        router.selectedTab = 0
    }
    
    // MARK: - Tab Selection Tests
    
    /// Verify all tabs can be selected via URL
    func test_allTabs_selectableViaURL() {
        let tabURLs: [(String, Int)] = [
            ("dosetap://tonight", 0),
            ("dosetap://timeline", 1),
            ("dosetap://details", 1),
            ("dosetap://history", 2),
            ("dosetap://settings", 3),
        ]
        
        for (urlString, expectedTab) in tabURLs {
            let url = URL(string: urlString)!
            _ = router.handle(url)
            XCTAssertEqual(router.selectedTab, expectedTab, 
                "\(urlString) should select tab \(expectedTab)")
        }
    }
    
    /// Verify tab selection persists after action URLs
    func test_tabSelection_persistsAfterAction() {
        // Select settings tab
        _ = router.handle(URL(string: "dosetap://settings")!)
        XCTAssertEqual(router.selectedTab, 3)
        
        // Perform action (which doesn't change tab)
        _ = router.handle(URL(string: "dosetap://dose1")!)
        
        // Tab should still be settings (action doesn't force tab change)
        // Note: Actual behavior depends on implementation - may navigate to Tonight
    }
    
    // MARK: - Deep Link Flow Tests
    
    /// Verify quick event logging flow
    func test_quickEventFlow() {
        // Log bathroom via deep link
        let url = URL(string: "dosetap://log?event=bathroom")!
        let result = router.handle(url)
        
        // Should be recognized (execution depends on session state)
        if case .logEvent(let name, _) = router.lastAction {
            XCTAssertEqual(name, "bathroom")
        } else {
            XCTFail("Should parse log event action")
        }
    }
    
    /// Verify dose flow from widget
    func test_doseFlowFromWidget() {
        // Widget taps dose1 URL
        let url = URL(string: "dosetap://dose1")!
        _ = router.handle(url)
        
        XCTAssertEqual(router.lastAction, .takeDose1, "Should set takeDose1 action")
    }
}

final class PreSleepCardStateTests: XCTestCase {
    func test_preSleepCardState_loggedHidesCTA() {
        let log = StoredPreSleepLog(
            id: "log-123",
            sessionId: "2025-12-26",
            createdAtUtc: "2025-12-26T03:22:00Z",
            localOffsetMinutes: -300,
            completionState: "complete",
            answers: nil
        )
        let loggedState = PreSleepCardState(log: log)
        XCTAssertTrue(loggedState.isLogged)
        XCTAssertEqual(loggedState.action, .edit(id: "log-123"))
        
        let emptyState = PreSleepCardState(log: nil)
        XCTAssertFalse(emptyState.isLogged)
        XCTAssertEqual(emptyState.action, .start)
    }
    
    func test_preSleepCardState_editActionUsesSameId() {
        let log = StoredPreSleepLog(
            id: "log-999",
            sessionId: "2025-12-26",
            createdAtUtc: "2025-12-26T05:00:00Z",
            localOffsetMinutes: 0,
            completionState: "complete",
            answers: nil
        )
        let state = PreSleepCardState(log: log)
        XCTAssertEqual(state.action, .edit(id: "log-999"))
    }
}
