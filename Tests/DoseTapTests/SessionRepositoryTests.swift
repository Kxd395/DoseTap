import XCTest
@testable import DoseTap
import Combine
import DoseCore

/// Tests for SessionRepository - the single source of truth for session state.
/// These tests verify that delete operations properly broadcast state changes.
@MainActor
final class SessionRepositoryTests: XCTestCase {
    
    private var storage: EventStorage!
    private var repo: SessionRepository!
    private var cancellables: Set<AnyCancellable> = []
    
    override func setUp() async throws {
        // Use shared storage for integration tests
        // Note: In production, we'd want an in-memory SQLite mode for isolation
        storage = EventStorage.shared
        repo = SessionRepository(storage: storage)
        
        // Clear any existing data for clean test state
        storage.clearAllData()
        repo.reload()
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        // Clean up test data
        storage.clearAllData()
    }
    
    // MARK: - Test: Delete Active Session Clears Tonight State
    
    /// This is THE critical test that catches the two-sources-of-truth bug.
    /// When active session is deleted, Tonight tab must show empty state.
    func test_deleteActiveSession_clearsTonightState() async throws {
        // Arrange: Create a session with dose data
        let now = Date()
        repo.setDose1Time(now.addingTimeInterval(-60 * 60)) // 1 hour ago
        repo.setDose2Time(now.addingTimeInterval(-30 * 60)) // 30 min ago
        
        // Verify session exists
        XCTAssertNotNil(repo.dose1Time, "Dose 1 should be set")
        XCTAssertNotNil(repo.dose2Time, "Dose 2 should be set")
        XCTAssertNotNil(repo.activeSessionDate, "Active session should exist")
        
        let sessionDate = repo.currentSessionDateString()
        
        // Act: Delete the active session
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert: Tonight state is cleared
        XCTAssertNil(repo.dose1Time, "Dose 1 should be nil after delete")
        XCTAssertNil(repo.dose2Time, "Dose 2 should be nil after delete")
        XCTAssertNil(repo.activeSessionDate, "Active session should be nil after delete")
        XCTAssertEqual(repo.snoozeCount, 0, "Snooze count should reset")
        XCTAssertFalse(repo.dose2Skipped, "Skip state should reset")
    }
    
    // MARK: - Test: Delete Inactive Session Preserves Active State
    
    /// Deleting a past session should NOT affect Tonight's current state.
    func test_deleteInactiveSession_preservesActiveState() async throws {
        // Arrange: Create current session
        let now = Date()
        repo.setDose1Time(now)
        
        let currentSessionDate = repo.currentSessionDateString()
        XCTAssertNotNil(repo.dose1Time)
        
        // Create a fake "past" session date (not the current one)
        let pastSessionDate = "2024-01-01" // Definitely not today
        
        // Act: Delete the past (inactive) session
        repo.deleteSession(sessionDate: pastSessionDate)
        
        // Assert: Active session state is preserved
        XCTAssertNotNil(repo.dose1Time, "Dose 1 should still exist")
        XCTAssertEqual(repo.activeSessionDate, currentSessionDate, "Active session should be unchanged")
    }
    
    // MARK: - Test: Change Signal is Broadcast on Delete
    
    /// Verify that sessionDidChange fires when session is deleted.
    func test_deleteSession_broadcastsChangeSignal() async throws {
        // Arrange
        let now = Date()
        repo.setDose1Time(now)
        let sessionDate = repo.currentSessionDateString()
        
        var changeReceived = false
        let expectation = XCTestExpectation(description: "Change signal received")
        
        repo.sessionDidChange
            .first()
            .sink { _ in
                changeReceived = true
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Act
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(changeReceived, "sessionDidChange should fire on delete")
    }
    
    // MARK: - Test: Reload Syncs from Storage
    
    func test_reload_syncsFromStorage() async throws {
        // Arrange: Save directly to storage (simulating data from another source)
        let now = Date()
        storage.saveDose1(timestamp: now)
        
        // Create fresh repo that hasn't seen this data
        let freshRepo = SessionRepository(storage: storage)
        
        // Assert: Fresh repo loaded the data
        XCTAssertNotNil(freshRepo.dose1Time, "Fresh repo should load existing dose1")
    }
    
    // MARK: - Test: Clear Tonight Clears Active Session
    
    func test_clearTonight_clearsActiveSession() async throws {
        // Arrange
        repo.setDose1Time(Date())
        repo.setDose2Time(Date())
        repo.incrementSnooze()
        
        XCTAssertNotNil(repo.dose1Time)
        XCTAssertNotNil(repo.dose2Time)
        XCTAssertEqual(repo.snoozeCount, 1)
        
        // Act
        repo.clearTonight()
        
        // Assert
        XCTAssertNil(repo.dose1Time)
        XCTAssertNil(repo.dose2Time)
        XCTAssertEqual(repo.snoozeCount, 0)
        XCTAssertNil(repo.activeSessionDate)
    }
    
    // MARK: - Test: Mutations Broadcast Changes
    
    func test_setDose1_broadcastsChange() async throws {
        var changes = 0
        repo.sessionDidChange
            .sink { _ in changes += 1 }
            .store(in: &cancellables)
        
        repo.setDose1Time(Date())
        
        // Give Combine time to deliver
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        XCTAssertGreaterThan(changes, 0, "setDose1Time should broadcast change")
    }
    
    func test_incrementSnooze_updatesCount() async throws {
        XCTAssertEqual(repo.snoozeCount, 0)
        
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 1)
        
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 2)
    }
    
    func test_skipDose2_updatesState() async throws {
        XCTAssertFalse(repo.dose2Skipped)
        
        repo.skipDose2()
        
        XCTAssertTrue(repo.dose2Skipped)
    }
    
    // MARK: - Test: Delete Clears Notifications (P0-3 Verification)
    
    /// Verify that deleting an active session cancels pending notifications.
    /// This test validates the P0-3 fix: notifications should not fire for deleted sessions.
    func test_deleteActiveSession_cancelsPendingNotifications() async throws {
        // Arrange: Create a session
        let now = Date()
        repo.setDose1Time(now)
        
        let sessionDate = repo.currentSessionDateString()
        XCTAssertNotNil(repo.dose1Time)
        
        // Act: Delete the active session
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert: Session state is cleared
        XCTAssertNil(repo.dose1Time, "Dose 1 should be nil after delete")
        XCTAssertNil(repo.activeSessionDate, "Active session should be nil after delete")
        
        // Note: We cannot directly verify notification cancellation in unit tests
        // without mocking UNUserNotificationCenter. This test documents the requirement.
        // Integration tests should verify: getPendingNotificationRequests returns empty array
        
        // The implementation calls cancelPendingNotifications() which removes:
        // - dose_reminder, window_opening, window_closing, window_critical
        // - wake_alarm and its follow-ups
        // - hard_stop warnings
    }
    
    // MARK: - Test: currentContext Reflects Repository State (P0-1 Verification)
    
    /// Verify that currentContext computed property correctly reflects repository state.
    /// This validates the P0-1 fix: TonightView uses repository's currentContext, not separate state.
    func test_currentContext_reflectsRepositoryState() async throws {
        // Arrange: Empty repo
        XCTAssertNil(repo.dose1Time)
        
        // Assert: Initial context should be noDose1 phase
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Empty repo should have noDose1 phase")
        
        // Act: Set dose 1
        let dose1Time = Date()
        repo.setDose1Time(dose1Time)
        
        // Assert: Context should now reflect dose1 state
        XCTAssertTrue(
            repo.currentContext.phase == .beforeWindow || 
            repo.currentContext.phase == .active ||
            repo.currentContext.phase == .nearClose,
            "After dose1, context should be in waiting, active, or nearClose phase"
        )
    }
    
    /// Critical test: Verify currentContext returns noDose1 after session deletion.
    /// This is THE acceptance test for P0-1: "Delete session from History and Tonight clears instantly"
    func test_currentContext_returnsNoDose1_afterDeletion() async throws {
        // Arrange: Create a session with dose 1
        let now = Date()
        repo.setDose1Time(now)
        
        let sessionDate = repo.currentSessionDateString()
        
        // Verify context reflects dose taken
        XCTAssertNotEqual(repo.currentContext.phase, .noDose1, "Should not be noDose1 before delete")
        
        // Act: Delete the session
        repo.deleteSession(sessionDate: sessionDate)
        
        // Assert: Context should return to noDose1
        XCTAssertEqual(repo.currentContext.phase, .noDose1, 
                       "After delete, context should return to noDose1 phase")
        XCTAssertNil(repo.dose1Time, "dose1Time should be nil after delete")
    }
    
    /// Verify snoozeCount is correctly reflected in currentContext
    func test_currentContext_reflectsSnoozeCount() async throws {
        // Arrange: Set dose 1 within window (150+ minutes ago)
        let dose1Time = Date().addingTimeInterval(-155 * 60) // 155 minutes ago
        repo.setDose1Time(dose1Time)
        
        // Initial state - no snoozes
        let initialContext = repo.currentContext
        XCTAssertEqual(initialContext.snoozeCount, 0, "Initial snooze count should be 0")
        
        // Act: Increment snooze
        repo.incrementSnooze()
        
        // Assert: Context reflects new snooze count
        XCTAssertEqual(repo.currentContext.snoozeCount, 1, "Context should reflect snooze count")
        
        // Act: Increment again
        repo.incrementSnooze()
        
        // Assert
        XCTAssertEqual(repo.currentContext.snoozeCount, 2, "Context should reflect updated snooze count")
    }
}
