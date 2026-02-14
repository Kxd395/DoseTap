import XCTest
@testable import DoseTap
import Combine
import DoseCore

final class TestClock {
    var now: Date
    let timeZone: TimeZone
    
    init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }
    
    func advance(hours: Double) {
        now = now.addingTimeInterval(hours * 3600)
    }
}

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
        XCTAssertNil(repo.activeSessionId, "Active session id should be nil after delete")
        XCTAssertNil(repo.activeSessionStart, "Active session start should be nil after delete")
        XCTAssertNil(repo.activeSessionEnd, "Active session end should be nil after delete")
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

    /// Async deletion path should mirror sync deletion semantics for active sessions.
    func test_deleteSessionAsync_clearsActiveSessionState() async throws {
        let now = Date()
        repo.setDose1Time(now.addingTimeInterval(-60 * 60))
        repo.setDose2Time(now.addingTimeInterval(-30 * 60))
        let sessionDate = repo.currentSessionDateString()

        await repo.deleteSessionAsync(sessionDate: sessionDate)

        XCTAssertNil(repo.dose1Time, "Dose 1 should be nil after async delete")
        XCTAssertNil(repo.dose2Time, "Dose 2 should be nil after async delete")
        XCTAssertNil(repo.activeSessionDate, "Active session should be nil after async delete")
        XCTAssertNil(repo.activeSessionId, "Active session id should be nil after async delete")
        XCTAssertNil(repo.activeSessionStart, "Active session start should be nil after async delete")
        XCTAssertNil(repo.activeSessionEnd, "Active session end should be nil after async delete")
        XCTAssertEqual(repo.snoozeCount, 0, "Snooze count should reset after async delete")
    }

    /// Async timeline/history query path should stay functionally equivalent to sync facade.
    func test_fetchRecentSessionsAsync_matchesSyncResults() async throws {
        let dose1 = Date().addingTimeInterval(-160 * 60)
        repo.setDose1Time(dose1)
        repo.setDose2Time(dose1.addingTimeInterval(165 * 60))

        let sync = repo.fetchRecentSessions(days: 7)
        let async = await repo.fetchRecentSessionsAsync(days: 7)

        XCTAssertEqual(async.map(\.sessionDate), sync.map(\.sessionDate), "Async and sync recent sessions should match")
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
        XCTAssertNil(repo.activeSessionId)
        XCTAssertNil(repo.activeSessionStart)
        XCTAssertNil(repo.activeSessionEnd)
    }

    func test_clearAllData_clearsSessionIdentityState() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-120 * 60))
        repo.incrementSnooze()

        XCTAssertNotNil(repo.activeSessionDate)
        XCTAssertNotNil(repo.activeSessionId)
        XCTAssertNotNil(repo.activeSessionStart)

        repo.clearAllData()

        XCTAssertNil(repo.activeSessionDate, "clearAllData should clear active session date")
        XCTAssertNil(repo.activeSessionId, "clearAllData should clear active session id")
        XCTAssertNil(repo.activeSessionStart, "clearAllData should clear active session start")
        XCTAssertNil(repo.activeSessionEnd, "clearAllData should clear active session end")
        XCTAssertNil(repo.dose1Time, "clearAllData should clear dose1 time")
        XCTAssertNil(repo.dose2Time, "clearAllData should clear dose2 time")
        XCTAssertEqual(repo.snoozeCount, 0, "clearAllData should reset snooze count")
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "clearAllData should return to noDose1 phase")
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
    
    /// Verify timezone change detection fires when device timezone shifts mid-session
    func test_timezoneChange_detectedAfterDose1() async throws {
        let original = TimeZone.current
        defer { NSTimeZone.default = original }
        
        // Start session in UTC
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        repo.setDose1Time(Date())
        XCTAssertNotNil(repo.dose1TimezoneOffsetMinutes, "Dose 1 should record timezone offset")
        
        // Simulate traveling +3h east
        NSTimeZone.default = TimeZone(secondsFromGMT: 3 * 3600)!
        
        let description = repo.checkTimezoneChange()
        XCTAssertNotNil(description, "Timezone change should be detected after offset shift")
        XCTAssertTrue(description?.contains("east") == true, "Description should indicate eastward shift")
    }

    func test_sessionKey_rollover_rules_across_timezones() {
        let ny = TimeZone(identifier: "America/New_York")!
        let utc = TimeZone(secondsFromGMT: 0)!
        
        let beforeRolloverNY = makeDate(2025, 12, 25, 14, 22, tz: ny)
        let afterRolloverNY = makeDate(2025, 12, 25, 20, 47, tz: ny)
        XCTAssertEqual(sessionKey(for: beforeRolloverNY, timeZone: ny, rolloverHour: 18), "2025-12-24")
        XCTAssertEqual(sessionKey(for: afterRolloverNY, timeZone: ny, rolloverHour: 18), "2025-12-25")
        
        let beforeRolloverUTC = makeDate(2025, 12, 25, 14, 22, tz: utc)
        let afterRolloverUTC = makeDate(2025, 12, 25, 20, 47, tz: utc)
        XCTAssertEqual(sessionKey(for: beforeRolloverUTC, timeZone: utc, rolloverHour: 18), "2025-12-24")
        XCTAssertEqual(sessionKey(for: afterRolloverUTC, timeZone: utc, rolloverHour: 18), "2025-12-25")
    }

    func test_repository_rollover_changes_sessionKey_and_broadcasts() async throws {
        storage.clearAllData()
        cancellables.removeAll()
        let tz = TimeZone(identifier: "America/New_York")!
        let clock = TestClock(now: makeDate(2025, 12, 25, 17, 0, tz: tz), timeZone: tz)
        repo = SessionRepository(
            storage: storage,
            notificationScheduler: FakeNotificationScheduler(),
            clock: { clock.now },
            timeZoneProvider: { clock.timeZone },
            rolloverHour: 18
        )
        
        var changeCount = 0
        let changeExpectation = expectation(description: "rollover broadcast")
        repo.sessionDidChange
            .sink { _ in
                changeCount += 1
                if changeCount == 1 {
                    changeExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        XCTAssertEqual(repo.currentSessionDateString(), "2025-12-24")
        
        clock.advance(hours: 3) // Cross 6 PM boundary
        repo.refreshForTimeChange()
        await fulfillment(of: [changeExpectation], timeout: 2.0)
        XCTAssertEqual(repo.currentSessionDateString(), "2025-12-25")
        XCTAssertNil(repo.activeSessionDate)
        XCTAssertNil(repo.dose1Time)
    }

    func test_tonight_empty_after_rollover() async throws {
        storage.clearAllData()
        cancellables.removeAll()
        let tz = TimeZone(identifier: "America/New_York")!
        let clock = TestClock(now: makeDate(2025, 12, 25, 17, 30, tz: tz), timeZone: tz)
        repo = SessionRepository(
            storage: storage,
            notificationScheduler: FakeNotificationScheduler(),
            clock: { clock.now },
            timeZoneProvider: { clock.timeZone },
            rolloverHour: 18
        )
        
        repo.setDose1Time(clock.now.addingTimeInterval(-3600))
        repo.setDose2Time(clock.now)
        XCTAssertNotNil(repo.activeSessionDate, "Session should be active before rollover")
        
        clock.advance(hours: 2) // move past 6 PM
        repo.refreshForTimeChange()
        
        XCTAssertNil(repo.activeSessionDate, "Active session should clear after rollover")
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Context should reset after rollover")
    }

    func test_addPreSleepLog_persistsRowAndIsQueryableBySessionKey() async throws {
        storage.clearAllData()
        let answers = DoseTap.PreSleepLogAnswers()
        let log = try repo.savePreSleepLog(answers: answers, completionState: "complete")
        guard let sessionId = log.sessionId else {
            XCTFail("Expected pre-sleep log to include sessionId")
            return
        }
        
        let count = storage.fetchPreSleepLogCount(sessionId: sessionId)
        XCTAssertEqual(count, 1, "Expected one pre-sleep log row for session")
        let fetched = storage.fetchMostRecentPreSleepLog(sessionId: sessionId)
        XCTAssertNotNil(fetched, "Expected pre-sleep log to be queryable by sessionId")
    }

    func test_addPreSleepLog_persistsNormalizedQuestionnaireSubmission() async throws {
        storage.clearAllData()
        var answers = DoseTap.PreSleepLogAnswers()
        answers.stressLevel = 4
        answers.bodyPain = .moderate
        answers.painLocations = [.back]
        answers.painType = .aching

        _ = try repo.savePreSleepLog(answers: answers, completionState: "complete")
        let rows = storage.fetchCheckInSubmissions(checkInType: .preNight)

        XCTAssertEqual(rows.count, 1, "Expected one normalized pre-night submission")
        guard let row = rows.first else { return }
        XCTAssertEqual(row.checkInType, .preNight)
        XCTAssertFalse(row.questionnaireVersion.isEmpty)
        XCTAssertFalse(row.userId.isEmpty)

        let responses = decodeJSONDictionary(row.responsesJson)
        XCTAssertEqual(responses["overall.stress"] as? Int, 4)
        XCTAssertEqual(responses["pain.any"] as? Bool, true)
        XCTAssertEqual(responses["pain.overall_intensity"] as? Int, 6)
    }

    func test_addPreSleepLog_persistsGranularSubstanceDetails_andNormalizesTotals() async throws {
        storage.clearAllData()
        let caffeineTime = Date(timeIntervalSince1970: 1_770_000_000)
        let alcoholTime = caffeineTime.addingTimeInterval(-3600)

        var answers = DoseTap.PreSleepLogAnswers()
        answers.stimulants = .coffee
        answers.caffeineLastIntakeAt = caffeineTime
        answers.caffeineLastAmountMg = 190
        answers.caffeineDailyTotalMg = 120 // intentionally lower; should normalize up
        answers.alcohol = .twoThree
        answers.alcoholLastDrinkAt = alcoholTime
        answers.alcoholLastAmountDrinks = 2.5
        answers.alcoholDailyTotalDrinks = 1.5 // intentionally lower; should normalize up
        answers.exercise = .intense
        answers.exerciseType = .strength
        answers.exerciseLastAt = caffeineTime.addingTimeInterval(-5400)
        answers.exerciseDurationMinutes = 55
        answers.napToday = .medium
        answers.napCount = 2
        answers.napTotalMinutes = 70
        answers.napLastEndAt = alcoholTime.addingTimeInterval(-7200)

        let log = try repo.savePreSleepLog(answers: answers, completionState: "complete")
        let rows = storage.fetchCheckInSubmissions(checkInType: .preNight)

        XCTAssertEqual(rows.count, 1, "Expected one normalized pre-night submission")
        guard let row = rows.first else { return }

        let responses = decodeJSONDictionary(row.responsesJson)
        XCTAssertEqual(responses["pre.substances.caffeine.source"] as? String, PreSleepLogAnswers.Stimulants.coffee.rawValue)
        XCTAssertEqual(responses["pre.substances.caffeine.any"] as? Bool, true)
        XCTAssertEqual(responses["pre.substances.caffeine.last_amount_mg"] as? Int, 190)
        XCTAssertEqual(responses["pre.substances.caffeine.daily_total_mg"] as? Int, 190)
        XCTAssertNotNil(responses["pre.substances.caffeine.last_time_utc"] as? String)

        XCTAssertEqual(responses["pre.substances.alcohol"] as? String, PreSleepLogAnswers.AlcoholLevel.twoThree.rawValue)
        XCTAssertEqual(responses["pre.substances.alcohol.any"] as? Bool, true)
        let alcoholLast = doubleValue(responses["pre.substances.alcohol.last_amount_drinks"])
        let alcoholTotal = doubleValue(responses["pre.substances.alcohol.daily_total_drinks"])
        XCTAssertNotNil(alcoholLast)
        XCTAssertNotNil(alcoholTotal)
        XCTAssertEqual(alcoholLast ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(alcoholTotal ?? 0, 2.5, accuracy: 0.001)
        XCTAssertNotNil(responses["pre.substances.alcohol.last_time_utc"] as? String)
        XCTAssertEqual(responses["pre.day.exercise.any"] as? Bool, true)
        XCTAssertEqual(responses["pre.day.exercise_level"] as? String, PreSleepLogAnswers.ExerciseLevel.intense.rawValue)
        XCTAssertEqual(responses["pre.day.exercise.type"] as? String, PreSleepLogAnswers.ExerciseType.strength.rawValue)
        XCTAssertEqual(responses["pre.day.exercise.duration_minutes"] as? Int, 55)
        XCTAssertNotNil(responses["pre.day.exercise.last_time_utc"] as? String)
        XCTAssertEqual(responses["pre.day.nap.any"] as? Bool, true)
        XCTAssertEqual(responses["pre.day.nap_duration"] as? String, PreSleepLogAnswers.NapDuration.medium.rawValue)
        XCTAssertEqual(responses["pre.day.nap.count"] as? Int, 2)
        XCTAssertEqual(responses["pre.day.nap.total_minutes"] as? Int, 70)
        XCTAssertNotNil(responses["pre.day.nap.last_end_time_utc"] as? String)

        guard let sessionId = log.sessionId else {
            XCTFail("Expected pre-sleep log session id")
            return
        }
        let stored = storage.fetchMostRecentPreSleepLog(sessionId: sessionId)
        XCTAssertEqual(stored?.answers?.caffeineDailyTotalMg, 190)
        XCTAssertEqual(stored?.answers?.alcoholDailyTotalDrinks ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(stored?.answers?.exerciseType, .strength)
        XCTAssertEqual(stored?.answers?.exerciseDurationMinutes, 55)
        XCTAssertEqual(stored?.answers?.napCount, 2)
        XCTAssertEqual(stored?.answers?.napTotalMinutes, 70)
    }

    func test_corePreSleepBridge_mapsLegacyBooleans_toCanonicalSubstanceResponses() throws {
        storage.clearAllData()
        let sessionKey = "2026-02-09"
        let coreAnswers = DoseCore.PreSleepLogAnswers(
            caffeineLast6Hours: true,
            alcoholLast6Hours: true,
            stressLevel: 3
        )

        try storage.savePreSleepLogOrThrow(
            sessionKey: sessionKey,
            answers: coreAnswers,
            completionState: "complete"
        )

        let rows = storage.fetchCheckInSubmissions(sessionDate: sessionKey, checkInType: .preNight)
        XCTAssertEqual(rows.count, 1)
        guard let row = rows.first else { return }
        let responses = decodeJSONDictionary(row.responsesJson)

        XCTAssertEqual(responses["overall.stress"] as? Int, 3)
        XCTAssertEqual(responses["pre.substances.caffeine.any"] as? Bool, true)
        XCTAssertEqual(responses["pre.substances.alcohol.any"] as? Bool, true)
        XCTAssertNotNil(responses["pre.substances.caffeine.last_amount_mg"] as? Int)
        XCTAssertNotNil(doubleValue(responses["pre.substances.alcohol.last_amount_drinks"]))
    }
    
    func test_preSleepSubmit_broadcastsChangeSignal() async throws {
        cancellables.removeAll()
        let expectation = XCTestExpectation(description: "pre-sleep broadcast")
        
        repo.sessionDidChange
            .first()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        _ = try repo.savePreSleepLog(answers: PreSleepLogAnswers(), completionState: "complete")
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func test_preSleepSessionKey_matchesTonightKey_aroundRollover() {
        let tz = TimeZone(identifier: "America/New_York")!
        let before = makeDate(2025, 12, 25, 17, 30, tz: tz)
        let after = makeDate(2025, 12, 25, 20, 0, tz: tz)
        let localRepo = SessionRepository(
            storage: storage,
            notificationScheduler: FakeNotificationScheduler(),
            clock: { before },
            timeZoneProvider: { tz },
            rolloverHour: 18
        )
        
        let beforeKey = localRepo.preSleepDisplaySessionKey(for: before)
        let afterKey = localRepo.preSleepDisplaySessionKey(for: after)
        
        XCTAssertEqual(beforeKey, "2025-12-25")
        XCTAssertEqual(afterKey, "2025-12-25")
    }

    func test_plannerSessionKey_afterMorningCheckIn_targetsUpcomingNightByDefault() {
        let tz = TimeZone(identifier: "America/New_York")!
        let morning = makeDate(2025, 12, 29, 7, 30, tz: tz)
        let clock = TestClock(now: morning, timeZone: tz)
        let settings = UserSettingsManager.shared
        let previousToggle = settings.plannerUsesUpcomingNightAfterCheckIn
        settings.plannerUsesUpcomingNightAfterCheckIn = true
        defer { settings.plannerUsesUpcomingNightAfterCheckIn = previousToggle }

        let localRepo = SessionRepository(
            storage: storage,
            notificationScheduler: FakeNotificationScheduler(),
            clock: { clock.now },
            timeZoneProvider: { clock.timeZone },
            rolloverHour: 18
        )

        // Prior-night session (Sunday) closes after wake/check-in on Monday morning.
        localRepo.setDose1Time(makeDate(2025, 12, 28, 23, 0, tz: tz))
        localRepo.setWakeFinalTime(makeDate(2025, 12, 29, 7, 0, tz: tz))
        localRepo.completeCheckIn()

        XCTAssertNil(localRepo.activeSessionDate, "Session should be closed after check-in")
        XCTAssertEqual(localRepo.currentSessionKey, "2025-12-28", "Storage session key remains prior night until 6 PM")
        XCTAssertEqual(
            localRepo.plannerSessionKey(for: clock.now),
            "2025-12-29",
            "UI planning key should move to upcoming night after morning check-in"
        )
    }

    func test_plannerSessionKey_canFollowStorageBoundaryWhenToggleOff() {
        let tz = TimeZone(identifier: "America/New_York")!
        let morning = makeDate(2025, 12, 29, 7, 30, tz: tz)
        let clock = TestClock(now: morning, timeZone: tz)
        let settings = UserSettingsManager.shared
        let previousToggle = settings.plannerUsesUpcomingNightAfterCheckIn
        settings.plannerUsesUpcomingNightAfterCheckIn = false
        defer { settings.plannerUsesUpcomingNightAfterCheckIn = previousToggle }

        let localRepo = SessionRepository(
            storage: storage,
            notificationScheduler: FakeNotificationScheduler(),
            clock: { clock.now },
            timeZoneProvider: { clock.timeZone },
            rolloverHour: 18
        )

        XCTAssertNil(localRepo.activeSessionDate)
        XCTAssertEqual(localRepo.currentSessionKey, "2025-12-28")
        XCTAssertEqual(
            localRepo.plannerSessionKey(for: clock.now),
            "2025-12-28",
            "When toggle is off, planner should follow 6 PM storage boundary key"
        )
    }

    func test_preSleepLog_upsertSameSession() async throws {
        storage.clearAllData()
        var firstAnswers = DoseTap.PreSleepLogAnswers()
        firstAnswers.stressLevel = 1
        let first = try repo.savePreSleepLog(answers: firstAnswers, completionState: "complete")
        guard let sessionId = first.sessionId else {
            XCTFail("Expected sessionId on first pre-sleep log")
            return
        }
        
        var secondAnswers = DoseTap.PreSleepLogAnswers()
        secondAnswers.stressLevel = 5
        let second = try repo.savePreSleepLog(answers: secondAnswers, completionState: "complete")
        
        XCTAssertEqual(first.id, second.id, "Expected upsert to keep the same pre-sleep log id")
        XCTAssertEqual(storage.fetchPreSleepLogCount(sessionId: sessionId), 1, "Expected only one pre-sleep log row for session")
        let fetched = storage.fetchMostRecentPreSleepLog(sessionId: sessionId)
        XCTAssertEqual(fetched?.answers?.stressLevel, 5, "Expected latest save to update answers")
    }

    func test_preSleepLog_upsert_updatesNormalizedSubmissionWithoutDupes() async throws {
        storage.clearAllData()
        var firstAnswers = DoseTap.PreSleepLogAnswers()
        firstAnswers.stressLevel = 1
        _ = try repo.savePreSleepLog(answers: firstAnswers, completionState: "complete")

        var secondAnswers = DoseTap.PreSleepLogAnswers()
        secondAnswers.stressLevel = 5
        _ = try repo.savePreSleepLog(answers: secondAnswers, completionState: "complete")

        XCTAssertEqual(
            storage.fetchCheckInSubmissionCount(checkInType: .preNight),
            1,
            "Expected pre-night submission upsert instead of duplicate rows"
        )
        guard let submission = storage.fetchCheckInSubmissions(checkInType: .preNight).first else {
            XCTFail("Expected pre-night submission")
            return
        }
        let responses = decodeJSONDictionary(submission.responsesJson)
        XCTAssertEqual(responses["overall.stress"] as? Int, 5)
    }

    func test_saveMorningCheckIn_persistsNormalizedQuestionnaireSubmission() async throws {
        storage.clearAllData()
        let sessionDate = "2026-02-09"
        let checkIn = SQLiteStoredMorningCheckIn(
            id: UUID().uuidString,
            sessionId: "session_\(sessionDate)",
            timestamp: Date(),
            sessionDate: sessionDate,
            sleepQuality: 4,
            feelRested: "Well",
            grogginess: "Mild",
            sleepInertiaDuration: "5-15 minutes",
            dreamRecall: "Normal",
            hasPhysicalSymptoms: true,
            physicalSymptomsJson: #"{"painLocations":["Lower Back"],"painSeverity":7,"painType":"Sharp"}"#,
            hasRespiratorySymptoms: false,
            respiratorySymptomsJson: nil,
            mentalClarity: 6,
            mood: "Good",
            anxietyLevel: "Mild",
            readinessForDay: 4,
            hadSleepParalysis: false,
            hadHallucinations: false,
            hadAutomaticBehavior: false,
            fellOutOfBed: false,
            hadConfusionOnWaking: false,
            usedSleepTherapy: false,
            sleepTherapyJson: nil,
            hasSleepEnvironment: false,
            sleepEnvironmentJson: nil,
            notes: "Felt better than expected"
        )

        repo.saveMorningCheckIn(checkIn, sessionDateOverride: sessionDate)
        let rows = storage.fetchCheckInSubmissions(sessionDate: sessionDate, checkInType: .morning)

        XCTAssertEqual(rows.count, 1, "Expected one normalized morning submission")
        guard let row = rows.first else { return }
        XCTAssertEqual(row.checkInType, .morning)
        XCTAssertFalse(row.questionnaireVersion.isEmpty)

        let responses = decodeJSONDictionary(row.responsesJson)
        XCTAssertEqual(responses["sleep.quality"] as? Int, 4)
        XCTAssertEqual(responses["pain.any"] as? Bool, true)
        XCTAssertEqual(responses["pain.overall_intensity"] as? Int, 7)
    }

    func test_deleteMorningCheckIn_removesNormalizedSubmission() async throws {
        storage.clearAllData()
        let sessionDate = "2026-02-10"
        let checkInId = UUID().uuidString
        let checkIn = SQLiteStoredMorningCheckIn(
            id: checkInId,
            sessionId: "session_\(sessionDate)",
            timestamp: Date(),
            sessionDate: sessionDate,
            sleepQuality: 3,
            feelRested: "Moderately",
            grogginess: "Mild",
            sleepInertiaDuration: "5-15 minutes",
            dreamRecall: "None",
            hasPhysicalSymptoms: false,
            physicalSymptomsJson: nil,
            hasRespiratorySymptoms: false,
            respiratorySymptomsJson: nil,
            mentalClarity: 5,
            mood: "Neutral",
            anxietyLevel: "None",
            readinessForDay: 3,
            hadSleepParalysis: false,
            hadHallucinations: false,
            hadAutomaticBehavior: false,
            fellOutOfBed: false,
            hadConfusionOnWaking: false
        )

        repo.saveMorningCheckIn(checkIn, sessionDateOverride: sessionDate)
        XCTAssertEqual(storage.fetchCheckInSubmissionCount(sessionDate: sessionDate, checkInType: .morning), 1)

        storage.deleteMorningCheckIn(id: checkInId)
        XCTAssertEqual(storage.fetchCheckInSubmissionCount(sessionDate: sessionDate, checkInType: .morning), 0)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, tz: TimeZone) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        comps.timeZone = tz
        return Calendar(identifier: .gregorian).date(from: comps) ?? Date()
    }

    private func decodeJSONDictionary(_ json: String) -> [String: Any] {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double {
            return number
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }
}
