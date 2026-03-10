//
//  E2EAndRegressionTests.swift
//  DoseTapTests
//
//  End-to-end integration tests and alarm/setup/snooze regression tests.
//  Extracted from DoseTapTests.swift for maintainability.
//

import XCTest
@testable import DoseTap
import DoseCore

// MARK: - E2E Integration Tests

/// End-to-end integration tests for session lifecycle.
///
/// Uses a deterministic clock (23:00 UTC) to avoid flaky failures when CI runs
/// near the 18:00 session rollover boundary.
@MainActor
final class E2EIntegrationTests: XCTestCase {
    
    private var storage: EventStorage!
    private var repo: SessionRepository!
    private var fakeScheduler: FakeNotificationScheduler!
    /// Fixed reference time: 23:00 UTC — 5 hours past rollover, so offsets up to -300 min stay in-session.
    private var fixedNow: Date!
    
    override func setUp() async throws {
        fixedNow = ISO8601DateFormatter().date(from: "2026-01-15T23:00:00Z")!
        let now = fixedNow!
        storage = EventStorage.shared
        fakeScheduler = FakeNotificationScheduler()
        repo = SessionRepository(
            storage: storage,
            notificationScheduler: fakeScheduler,
            clock: { now },
            timeZoneProvider: { TimeZone(identifier: "UTC")! }
        )
        storage.clearAllData()
        repo.reload()
    }
    
    override func tearDown() async throws {
        storage.clearAllData()
    }
    
    func test_e2e_completeDoseCycle() async throws {
        XCTAssertNil(repo.activeSessionDate)
        XCTAssertEqual(repo.currentContext.phase, .noDose1)
        
        let dose1Time = Date().addingTimeInterval(-10 * 60)
        repo.setDose1Time(dose1Time)
        
        XCTAssertNotNil(repo.activeSessionDate, "Session should be created")
        XCTAssertNotNil(repo.dose1Time, "Dose 1 should be recorded")
        XCTAssertEqual(repo.currentContext.phase, .beforeWindow, "Should be beforeWindow waiting for window")
        
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        XCTAssertEqual(repo.currentContext.phase, .active, "Should be in active window")
        
        repo.setDose2Time(Date())
        
        XCTAssertNotNil(repo.dose2Time, "Dose 2 should be recorded")
        XCTAssertEqual(repo.currentContext.phase, .completed, "Should be completed")
        
        repo.reload()
        XCTAssertNotNil(repo.dose1Time, "Dose 1 should persist")
        XCTAssertNotNil(repo.dose2Time, "Dose 2 should persist")
        XCTAssertEqual(repo.currentContext.phase, .completed, "Completion should persist")
    }
    
    func test_e2e_doseCycleWithSnooze() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        XCTAssertEqual(repo.currentContext.phase, .active)
        
        if case .snoozeEnabled = repo.currentContext.snooze {
        } else {
            XCTFail("Snooze should be enabled")
        }
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 1)
        
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 2)
        
        repo.setDose2Time(Date())
        XCTAssertEqual(repo.currentContext.phase, .completed)
        
        repo.reload()
        XCTAssertEqual(repo.snoozeCount, 2, "Snooze count should persist")
    }
    
    func test_e2e_doseCycleWithSkip() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        XCTAssertEqual(repo.currentContext.phase, .active)
        
        if case .skipEnabled = repo.currentContext.skip {
        } else {
            XCTFail("Skip should be enabled")
        }
        repo.skipDose2()
        
        XCTAssertTrue(repo.dose2Skipped, "Dose 2 should be marked skipped")
        XCTAssertEqual(repo.currentContext.phase, .completed)
        
        repo.reload()
        XCTAssertTrue(repo.dose2Skipped, "Skip should persist")
    }
    
    func test_e2e_sessionDeletion() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-180 * 60))
        repo.setDose2Time(fixedNow.addingTimeInterval(-15 * 60))
        repo.incrementSnooze()
        
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "bathroom",
            timestamp: fixedNow.addingTimeInterval(-60 * 60),
            colorHex: nil
        )
        
        let sessionDate = repo.currentSessionDateString()
        
        XCTAssertNotNil(repo.dose1Time)
        XCTAssertNotNil(repo.dose2Time)
        XCTAssertEqual(repo.snoozeCount, 1)
        
        fakeScheduler.reset()
        repo.deleteSession(sessionDate: sessionDate)
        
        XCTAssertNil(repo.dose1Time, "Dose 1 should be nil")
        XCTAssertNil(repo.dose2Time, "Dose 2 should be nil")
        XCTAssertEqual(repo.snoozeCount, 0, "Snooze should reset")
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Should return to noDose1")
        
        XCTAssertFalse(fakeScheduler.cancelledIdentifiers.isEmpty, "Should cancel notifications")
        
        XCTAssertEqual(storage.fetchRowCount(table: "sleep_events", sessionDate: sessionDate), 0)
        XCTAssertEqual(storage.fetchRowCount(table: "dose_events", sessionDate: sessionDate), 0)
    }
    
    func test_e2e_eventLogging() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-160 * 60))
        let sessionDate = repo.currentSessionDateString()
        
        let events = ["bathroom", "lights_out", "bathroom", "wake_final"]
        for event in events {
            storage.insertSleepEvent(
                id: UUID().uuidString,
                eventType: event,
                timestamp: fixedNow,
                colorHex: nil
            )
        }
        
        let savedEvents = storage.fetchSleepEvents(forSession: sessionDate)
        XCTAssertEqual(savedEvents.count, events.count, "All events should be saved")
        
        let savedTypes = savedEvents.map { $0.eventType }
        XCTAssertTrue(savedTypes.contains("bathroom"), "Should have bathroom events")
        XCTAssertTrue(savedTypes.contains("lights_out"), "Should have lights_out event")
        XCTAssertTrue(savedTypes.contains("wake_final"), "Should have wake_final event")
    }
    
    func test_e2e_rapidStateChanges() async throws {
        for i in 0..<5 {
            repo.setDose1Time(fixedNow.addingTimeInterval(Double(-160 * 60 - i)))
            XCTAssertNotNil(repo.dose1Time)
            repo.clearTonight()
            XCTAssertNil(repo.dose1Time)
        }
        
        repo.reload()
        XCTAssertNil(repo.dose1Time)
        XCTAssertNil(repo.activeSessionDate)
    }
    
    func test_e2e_databaseIntegrity() async throws {
        for day in 0..<3 {
            let offset = TimeInterval(day * 24 * 60 * 60)
            let dose1 = fixedNow.addingTimeInterval(-offset - 180 * 60)
            repo.setDose1Time(dose1)
            repo.setDose2Time(dose1.addingTimeInterval(165 * 60))
            
            storage.insertSleepEvent(
                id: UUID().uuidString,
                eventType: "bathroom",
                timestamp: dose1.addingTimeInterval(60 * 60),
                colorHex: nil
            )
        }
        
        let allSessions = storage.getAllSessionDates()
        XCTAssertGreaterThan(allSessions.count, 0, "Should have session data")
        
        storage.clearAllData()
        repo.reload()
        XCTAssertNil(repo.dose1Time)
        XCTAssertTrue(storage.getAllSessionDates().isEmpty || 
                      storage.fetchSleepEvents(forSession: storage.currentSessionDate()).isEmpty)
    }
}

// MARK: - Alarm / Setup / Snooze Regression Tests

@MainActor
final class AlarmAndSetupRegressionTests: XCTestCase {
    private var previousNotificationsEnabled = true
    private var previousMaxSnoozes = 3
    private var previousSnoozeDuration = 10

    private let alarm = AlarmService.shared
    private let repo = SessionRepository.shared
    private let router = URLRouter.shared
    private var core: DoseTapCore!

    override func setUp() async throws {
        let settings = UserSettingsManager.shared
        previousNotificationsEnabled = settings.notificationsEnabled
        previousMaxSnoozes = settings.maxSnoozes
        previousSnoozeDuration = settings.snoozeDurationMinutes

        settings.notificationsEnabled = true
        settings.maxSnoozes = 3
        settings.snoozeDurationMinutes = 10

        repo.clearTonight()
        alarm.clearDose2AlarmState()
        alarm.cancelAllAlarms()

        core = DoseTapCore(isOnline: { true })
        core.setSessionRepository(repo)
        router.configure(core: core, eventLogger: EventLogger.shared)
        router.applicationStateProvider = { .active }
        router.protectedDataProvider = { true }
        await router.waitForPendingActions()
        router.lastAction = nil
        router.feedbackMessage = ""
    }

    override func tearDown() async throws {
        let settings = UserSettingsManager.shared
        settings.notificationsEnabled = previousNotificationsEnabled
        settings.maxSnoozes = previousMaxSnoozes
        settings.snoozeDurationMinutes = previousSnoozeDuration

        await router.waitForPendingActions()
        router.resetTestOverrides()
        alarm.clearDose2AlarmState()
        alarm.cancelAllAlarms()
        repo.clearTonight()
    }

    func test_dueAlarm_doesNotRing_afterSessionCompleted() async {
        let now = Date()
        repo.setDose1Time(now.addingTimeInterval(-180 * 60))
        repo.setDose2Time(now.addingTimeInterval(-5 * 60))

        alarm.targetWakeTime = now.addingTimeInterval(-60)
        alarm.alarmScheduled = true
        alarm.checkForDueAlarm(now: now)

        XCTAssertFalse(alarm.isAlarmRinging, "Completed sessions must never re-trigger alarm ringing.")
        XCTAssertNil(alarm.targetWakeTime, "Completed sessions should clear stale wake target.")
        XCTAssertFalse(alarm.alarmScheduled, "Completed sessions should clear scheduled wake-alarm state.")
    }

    func test_setupWarnings_doNotBlockProceed() async {
        let service = SetupWizardService()
        service.currentStep = 2
        service.userConfig.medicationProfile.medicationName = "XYWAV"
        service.userConfig.medicationProfile.doseMgDose1 = 225
        service.userConfig.medicationProfile.doseMgDose2 = 300
        service.userConfig.medicationProfile.dosesPerBottle = 60

        service.validateCurrentStep()

        XCTAssertTrue(service.validationErrors.isEmpty, "Warning-only config should not produce blocking errors.")
        XCTAssertFalse(service.validationWarnings.isEmpty, "Warning should still be surfaced to the user.")
        XCTAssertTrue(service.canProceed, "Warnings should not block navigation.")

        service.nextStep()
        XCTAssertEqual(service.currentStep, 3, "Wizard should advance when only warnings are present.")
    }

    func test_setupErrors_stillBlockProceed() async {
        let service = SetupWizardService()
        service.currentStep = 2
        service.userConfig.medicationProfile.medicationName = ""
        service.userConfig.medicationProfile.doseMgDose1 = 0
        service.userConfig.medicationProfile.doseMgDose2 = 0
        service.userConfig.medicationProfile.dosesPerBottle = 0

        service.validateCurrentStep()

        XCTAssertFalse(service.validationErrors.isEmpty, "Hard validation errors must still be enforced.")
        XCTAssertFalse(service.canProceed, "Wizard must block continuation on blocking errors.")
    }

    func test_setupValidation_refreshesImmediately_whenUserEditsStepFields() async {
        let service = SetupWizardService()
        service.currentStep = 4
        service.validateCurrentStep()

        XCTAssertFalse(service.canProceed, "Notifications step should block until risk is acknowledged or permissions are granted.")

        service.userConfig.notifications.acknowledgedNotificationRisk = true

        XCTAssertTrue(service.validationErrors.isEmpty, "Editing the step should refresh validation without requiring manual revalidation.")
        XCTAssertTrue(service.canProceed, "Continue should re-enable immediately after resolving blocking setup errors.")
    }

    func test_morningCheckIn_useLast_appliesMostRecentWakeSurveyPayload() async {
        let viewModel = MorningCheckInViewModelV2()
        let now = Date()

        let older = DoseTap.StoredSleepEvent(
            id: UUID().uuidString,
            eventType: "wake_survey",
            timestamp: now.addingTimeInterval(-3600),
            sessionDate: "2026-01-08",
            notes: #"{"feeling":"Rough","sleep_quality":2,"sleepiness_now":4,"pain_level":6,"pain_woke_user":true,"awakenings":"3-4","long_awake":"1h+","notes":"older"}"#
        )

        let newest = DoseTap.StoredSleepEvent(
            id: UUID().uuidString,
            eventType: "wake_survey",
            timestamp: now.addingTimeInterval(-60),
            sessionDate: "2026-01-09",
            notes: #"{"feeling":"Great","sleep_quality":5,"sleepiness_now":1,"pain_level":1,"pain_woke_user":false,"awakenings":"1-2","long_awake":"<15m","notes":"latest"}"#
        )

        let applied = viewModel.applyLastWakeSurvey(
            from: [older, newest],
            excludingSessionDate: "2026-01-10"
        )

        XCTAssertTrue(applied, "Use Last should apply when a valid historical wake_survey exists.")
        XCTAssertEqual(viewModel.feelingNow, .great)
        XCTAssertEqual(viewModel.sleepQuality, 5)
        XCTAssertEqual(viewModel.sleepinessNow, 1)
        XCTAssertEqual(viewModel.wakePainLevel, 1)
        XCTAssertFalse(viewModel.painWokeUser)
        XCTAssertEqual(viewModel.awakeningsCount, .oneTwo)
        XCTAssertEqual(viewModel.longAwakePeriod, .lessThan15)
        XCTAssertEqual(viewModel.notes, "latest")
    }

    func test_napSummary_pairsStartsAndEnds_andTracksInProgressNap() async {
        let now = Date()

        repo.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "nap_start",
            timestamp: now.addingTimeInterval(-3600),
            colorHex: nil
        )
        repo.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "nap_end",
            timestamp: now.addingTimeInterval(-3300),
            colorHex: nil
        )
        repo.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "nap_start",
            timestamp: now.addingTimeInterval(-900),
            colorHex: nil
        )

        let summary = repo.napSummary(for: repo.currentSessionDateString())
        XCTAssertEqual(summary.count, 2, "One completed nap plus one in-progress nap should both count.")
        XCTAssertEqual(summary.totalMinutes, 5, "Only completed nap pairs should contribute to duration.")
    }

    func test_napSummary_countsUnmatchedNapEnd_asLoggedNap() async {
        repo.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "nap_end",
            timestamp: Date().addingTimeInterval(-600),
            colorHex: nil
        )

        let summary = repo.napSummary(for: repo.currentSessionDateString())
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.totalMinutes, 0)
    }

    func test_snoozeDeepLink_doesNotIncrement_whenRescheduleFails() async {
        let now = Date()
        repo.setDose1Time(now.addingTimeInterval(-160 * 60))
        XCTAssertEqual(repo.snoozeCount, 0)

        alarm.clearDose2AlarmState()

        let handled = router.handle(URL(string: "dosetap://snooze")!)
        XCTAssertTrue(handled, "Snooze deep link should be recognized while in active window.")

        await Task.yield()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(repo.snoozeCount, 0, "Failed alarm reschedule must not consume snooze count.")
    }

    func test_flicSnooze_reschedulesAlarm_andPersistsSnoozeCount() async {
        let now = Date()
        let originalTarget = now.addingTimeInterval(5 * 60)
        repo.setDose1Time(now.addingTimeInterval(-160 * 60))
        alarm.targetWakeTime = originalTarget
        alarm.alarmScheduled = true
        alarm.snoozeCount = 0

        let result = await FlicButtonService.shared.handleGesture(.doublePress)

        XCTAssertTrue(result.success, "Flic snooze should succeed when an alarm is scheduled.")
        XCTAssertEqual(repo.snoozeCount, 1, "Successful Flic snooze should update session state.")
        XCTAssertEqual(alarm.snoozeCount, 1, "Successful Flic snooze should update alarm state.")
        XCTAssertNotNil(alarm.targetWakeTime, "Successful Flic snooze should keep an active wake target.")
        XCTAssertEqual(
            alarm.targetWakeTime!.timeIntervalSinceReferenceDate,
            originalTarget.addingTimeInterval(10 * 60).timeIntervalSinceReferenceDate,
            accuracy: 1.0,
            "Flic snooze should move the target wake time by the configured snooze interval."
        )
    }

    func test_flicSnooze_doesNotIncrement_whenRescheduleFails() async {
        let now = Date()
        repo.setDose1Time(now.addingTimeInterval(-160 * 60))
        alarm.clearDose2AlarmState()
        alarm.snoozeCount = 0

        let result = await FlicButtonService.shared.handleGesture(.doublePress)

        XCTAssertFalse(result.success, "Flic snooze should fail when no alarm is scheduled.")
        XCTAssertEqual(repo.snoozeCount, 0, "Failed Flic snooze must not consume session snooze count.")
        XCTAssertEqual(alarm.snoozeCount, 0, "Failed Flic snooze must not consume alarm snooze count.")
    }
}
