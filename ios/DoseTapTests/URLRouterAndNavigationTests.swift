//
//  URLRouterAndNavigationTests.swift
//  DoseTapTests
//
//  URL routing, deep link, and navigation flow tests.
//  Extracted from DoseTapTests.swift for maintainability.
//

import XCTest
@testable import DoseTap
import DoseCore

// MARK: - Dose Action Presentation Tests

@MainActor
final class DoseActionResultPresentationTests: XCTestCase {

    func test_blockedResultCreatesVisibleFeedback() {
        let presentation = DoseActionResultPresentation(
            result: .blocked(reason: "Take Dose 1 first")
        )

        XCTAssertNil(presentation.confirmation)
        XCTAssertEqual(presentation.feedback?.kind, .blocked)
        XCTAssertEqual(presentation.feedback?.title, "Dose action blocked")
        XCTAssertEqual(presentation.feedback?.message, "Take Dose 1 first")
    }

    func test_successResultCreatesVisibleFeedback() {
        let presentation = DoseActionResultPresentation(
            result: .success(message: "Dose 2 logged")
        )

        XCTAssertNil(presentation.confirmation)
        XCTAssertEqual(presentation.feedback?.kind, .success)
        XCTAssertEqual(presentation.feedback?.title, "Dose action complete")
        XCTAssertEqual(presentation.feedback?.message, "Dose 2 logged")
    }

    func test_attentionRequiredCreatesVisibleAlarmWarning() {
        let presentation = DoseActionResultPresentation(
            result: .attentionRequired(
                message: "Dose 1 was logged. Retry the alarm."
            )
        )

        XCTAssertNil(presentation.confirmation)
        XCTAssertEqual(presentation.feedback?.kind, .warning)
        XCTAssertEqual(presentation.feedback?.title, "Dose logged; alarm needs attention")
        XCTAssertEqual(
            presentation.feedback?.message,
            "Dose 1 was logged. Retry the alarm."
        )
    }

    func test_confirmationResultRoutesWithoutFeedback() {
        let presentation = DoseActionResultPresentation(
            result: .needsConfirm(.outsideWindowOccurrence)
        )

        XCTAssertNil(presentation.feedback)
        XCTAssertEqual(presentation.confirmation, .outsideWindowOccurrence)
    }
}

// MARK: - URL Router / Deep Link Tests

@MainActor
final class URLRouterTests: XCTestCase {
    
    private var router: URLRouter!
    private var core: DoseTapCore!
    private var coordinator: DoseActionCoordinator!
    private var previousPrepTimeMinutes: Int?
    
    override func setUp() async throws {
        let settings = UserSettingsManager.shared
        previousPrepTimeMinutes = settings.prepTimeMinutes
        settings.prepTimeMinutes = Self.prepTimeOutsideActiveDoseWindow()

        router = URLRouter.shared
        core = DoseTapCore()
        core.setSessionRepository(SessionRepository.shared)
        coordinator = DoseActionCoordinator(
            core: core,
            alarmService: AlarmService.shared,
            eventLogger: EventLogger.shared,
            sessionRepo: SessionRepository.shared
        )
        router.configure(core: core, eventLogger: EventLogger.shared, coordinator: coordinator)
        router.applicationStateProvider = { .active }
        router.protectedDataProvider = { true }
        await router.waitForPendingActions()
        router.lastAction = nil
        router.feedbackMessage = ""
        SessionRepository.shared.clearTonight()
    }

    override func tearDown() async throws {
        await router.waitForPendingActions()
        router.resetTestOverrides()
        SessionRepository.shared.clearTonight()
        if let previousPrepTimeMinutes {
            UserSettingsManager.shared.prepTimeMinutes = previousPrepTimeMinutes
        }
    }

    private static func prepTimeOutsideActiveDoseWindow(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let currentMinute = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        return (currentMinute + 1) % (24 * 60)
    }
    
    // MARK: - URL Parsing Tests
    
    func test_validScheme_isHandled() {
        let dose1URL = URL(string: "dosetap://dose1")!
        _ = router.handle(dose1URL)
        XCTAssertNotNil(router.lastAction, "Should set lastAction for valid URL")
    }
    
    func test_invalidScheme_isRejected() {
        let invalidURL = URL(string: "https://example.com")!
        let result = router.handle(invalidURL)
        XCTAssertFalse(result, "Non-dosetap schemes should be rejected")
    }
    
    func test_unknownHost_isRejected() {
        let unknownURL = URL(string: "dosetap://unknown")!
        let result = router.handle(unknownURL)
        XCTAssertFalse(result, "Unknown hosts should be rejected")
    }

    func test_deepLinkRoute_stateChangingContract_isTyped() {
        XCTAssertEqual(URLDeepLinkRoute(host: "dose1"), .takeDose1)
        XCTAssertEqual(URLDeepLinkRoute(host: "dose2"), .takeDose2)
        XCTAssertEqual(URLDeepLinkRoute(host: "snooze"), .snooze)
        XCTAssertEqual(URLDeepLinkRoute(host: "skip"), .skip)
        XCTAssertEqual(URLDeepLinkRoute(host: "log"), .log)
        XCTAssertEqual(URLDeepLinkRoute(host: "oauth"), .oauth)
        XCTAssertEqual(URLDeepLinkRoute(host: "settings"), .navigate(tab: .settings))
        XCTAssertNil(URLDeepLinkRoute(host: "unknown"))

        XCTAssertTrue(URLDeepLinkRoute(host: "dose1")!.isStateChanging)
        XCTAssertTrue(URLDeepLinkRoute(host: "log")!.isStateChanging)
        XCTAssertFalse(URLDeepLinkRoute(host: "oauth")!.isStateChanging)
        XCTAssertFalse(URLDeepLinkRoute(host: "settings")!.isStateChanging)
    }
    
    // MARK: - Navigation Tests

    func test_navigationDeepLinkContract_isStable() {
        let expected: [(host: String, tab: AppTab)] = [
            ("tonight", .tonight),
            ("timeline", .timeline),
            ("details", .timeline),
            ("history", .history),
            ("dashboard", .dashboard),
            ("settings", .settings),
        ]
        XCTAssertEqual(AppTab.navigationDeepLinks.map { $0.host }, expected.map { $0.host })
        XCTAssertEqual(AppTab.navigationDeepLinks.map { $0.tab }, expected.map { $0.tab })
    }
    
    func test_navigate_tonight_setsTab0() {
        _ = router.handle(URL(string: "dosetap://tonight")!)
        XCTAssertEqual(router.selectedTab, .tonight, "tonight should navigate to tab 0")
    }
    
    func test_navigate_timeline_setsTab1() {
        _ = router.handle(URL(string: "dosetap://timeline")!)
        XCTAssertEqual(router.selectedTab, .timeline, "timeline should navigate to tab 1")
    }
    
    func test_navigate_details_setsTab1() {
        _ = router.handle(URL(string: "dosetap://details")!)
        XCTAssertEqual(router.selectedTab, .timeline, "details should navigate to tab 1")
    }
    
    func test_navigate_history_setsTab2() {
        _ = router.handle(URL(string: "dosetap://history")!)
        XCTAssertEqual(router.selectedTab, .history, "history should navigate to tab 2")
    }
    
    func test_navigate_dashboard_setsTab3() {
        _ = router.handle(URL(string: "dosetap://dashboard")!)
        XCTAssertEqual(router.selectedTab, .dashboard, "dashboard should navigate to tab 3")
    }

    func test_navigate_settings_setsTab4() {
        _ = router.handle(URL(string: "dosetap://settings")!)
        XCTAssertEqual(router.selectedTab, .settings, "settings should navigate to tab 4")
    }
    
    // MARK: - Log Event URL Tests
    
    func test_logEvent_parsesEventName() {
        let url = URL(string: "dosetap://log?event=bathroom")!
        _ = router.handle(url)
        
        if case .logEvent(let name, _) = router.lastAction {
            XCTAssertEqual(name, "bathroom", "Should parse event name from query")
        } else {
            XCTFail("lastAction should be .logEvent")
        }
    }
    
    func test_logEvent_parsesNotes() {
        let url = URL(string: "dosetap://log?event=bathroom&notes=urgent")!
        _ = router.handle(url)
        
        if case .logEvent(_, let notes) = router.lastAction {
            XCTAssertEqual(notes, "urgent", "Should parse notes from query")
        } else {
            XCTFail("lastAction should be .logEvent")
        }
    }

    func test_logEvent_persistsNotes_andCanonicalEventType() {
        let url = URL(string: "dosetap://log?event=lightsOut&notes=urgent%20bathroom%20trip")!
        let result = router.handle(url)
        XCTAssertTrue(result, "Valid log event URL should be handled")

        let events = SessionRepository.shared.fetchTonightSleepEvents()
        guard let saved = events.first(where: { $0.notes == "urgent bathroom trip" }) else {
            XCTFail("Expected log event notes to persist to storage")
            return
        }
        XCTAssertEqual(saved.eventType, "lights_out", "Event type should be canonicalized before persistence")
    }
    
    func test_logEvent_missingEvent_isRejected() {
        let url = URL(string: "dosetap://log")!
        let result = router.handle(url)
        
        XCTAssertFalse(result, "Missing event should fail validation")
        XCTAssertTrue(router.feedbackMessage.contains("Invalid"), "Should show invalid event feedback")
    }

    func test_logEvent_rejectsDoseEventNames() {
        for eventName in ["dose1", "dose2", "dose2_skipped", "snooze", "extra_dose"] {
            SessionRepository.shared.clearTonight()
            router.lastAction = nil
            router.feedbackMessage = ""

            let url = URL(string: "dosetap://log?event=\(eventName)")!
            let handled = router.handle(url)

            XCTAssertFalse(handled, "Log route must reject dose event \(eventName)")
            XCTAssertNil(router.lastAction, "Rejected dose log should not update lastAction")
            XCTAssertTrue(SessionRepository.shared.fetchTonightSleepEvents().isEmpty)
            XCTAssertTrue(router.feedbackMessage.contains("dose action"), "Should direct caller to dose action route")
        }
    }
    
    // MARK: - Action Recording Tests
    
    func test_dose1_setsLastAction() {
        let url = URL(string: "dosetap://dose1")!
        _ = router.handle(url)
        XCTAssertEqual(router.lastAction, .takeDose1, "Should set lastAction to .takeDose1")
    }

    func test_dose1_deepLink_doesNotPersistSleepEventDose() async {
        let url = URL(string: "dosetap://dose1")!
        let handled = router.handle(url)
        XCTAssertTrue(handled, "Dose 1 deep link should be handled")

        await Task.yield()
        try? await Task.sleep(nanoseconds: 120_000_000)

        let sleepEvents = SessionRepository.shared.fetchTonightSleepEvents()
        let hasDoseSleepEvent = sleepEvents.contains { event in
            let normalized = event.eventType.lowercased()
            return normalized == "dose1" || normalized == "dose2" || normalized == "extra_dose"
        }
        XCTAssertFalse(hasDoseSleepEvent, "Dose deep links must only persist dose_events, not sleep_events")
    }
    
    func test_dose2_setsLastAction_whenDose1Missing() async {
        let url = URL(string: "dosetap://dose2")!
        let result = router.handle(url)
        XCTAssertTrue(result, "Recognized Dose 2 deep link should be handled even when blocked by policy")
        await router.waitForPendingActions()
        XCTAssertTrue(router.feedbackMessage.contains("Dose 1"), "Should show Dose 1 required message")
    }

    func test_dose2_deepLink_requiresConfirmation_whenWindowClosed() async {
        let repo = SessionRepository.shared
        repo.setDose1Time(Date().addingTimeInterval(-250 * 60))
        XCTAssertEqual(repo.currentContext.phase, .closed, "Precondition: phase should be closed.")
        XCTAssertNil(repo.dose2Time, "Precondition: Dose 2 should not be logged yet.")

        let url = URL(string: "dosetap://dose2")!
        let handled = router.handle(url)
        XCTAssertTrue(handled, "Dose 2 deep link should be handled and routed to confirmation feedback.")

        await router.waitForPendingActions()

        XCTAssertNil(repo.dose2Time, "Late deep link must not log Dose 2 without in-app confirmation.")
        XCTAssertEqual(repo.currentContext.phase, .closed, "Session should remain closed until user confirms in app.")
        XCTAssertTrue(router.feedbackMessage.contains("Record a dose that already occurred"), "Should tell user to open app to confirm.")
    }

    func test_dose2_deepLink_blocksBeforeWindow_withoutOverride() async {
        let repo = SessionRepository.shared
        repo.setDose1Time(Date().addingTimeInterval(-100 * 60))
        XCTAssertEqual(repo.currentContext.phase, .beforeWindow, "Precondition: phase should be beforeWindow.")
        XCTAssertNil(repo.dose2Time, "Precondition: Dose 2 should not be logged yet.")

        let url = URL(string: "dosetap://dose2")!
        let handled = router.handle(url)
        XCTAssertTrue(handled, "Recognized Dose 2 deep link should be handled and blocked by policy.")
        await router.waitForPendingActions()
        XCTAssertNil(repo.dose2Time, "Dose 2 should remain unset when request is rejected.")
        XCTAssertTrue(router.feedbackMessage.contains("Window not open"), "Should show before-window feedback.")
    }

    func test_dose2_deepLink_requiresConfirmation_afterSkip() async {
        let repo = SessionRepository.shared
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.skipDose2()
        XCTAssertNotNil(repo.dose1Time, "Precondition: Dose 1 should still be present after skip.")
        XCTAssertTrue(repo.dose2Skipped, "Precondition: Dose 2 should be skipped.")
        XCTAssertNil(repo.dose2Time, "Precondition: Dose 2 should not be logged yet.")

        let url = URL(string: "dosetap://dose2")!
        let handled = router.handle(url)
        XCTAssertTrue(handled, "Dose 2 deep link should be handled and routed to confirmation feedback.")

        await router.waitForPendingActions()

        XCTAssertNil(repo.dose2Time, "After-skip deep link must not log Dose 2 without in-app confirmation.")
        XCTAssertTrue(repo.dose2Skipped, "Skip state should remain until the user confirms in app.")
        XCTAssertTrue(
            router.feedbackMessage.contains("occurrence that already happened"),
            "Should tell user to open app to confirm after-skip correction. Actual: \(router.feedbackMessage)"
        )
    }

    func test_logEvent_wakeFinal_setsSessionFinalizingState() {
        let repo = SessionRepository.shared
        repo.setDose1Time(Date().addingTimeInterval(-180 * 60))
        XCTAssertNil(repo.wakeFinalTime, "Precondition: wakeFinalTime should be nil")

        let handled = router.handle(URL(string: "dosetap://log?event=wake_final")!)
        XCTAssertTrue(handled, "Wake final deep-link should be handled")
        XCTAssertNotNil(repo.wakeFinalTime, "Wake final deep-link should persist wake final time")
        XCTAssertEqual(repo.currentContext.phase, .finalizing, "Session should enter finalizing phase after wake_final")
    }

    func test_logEvent_isRejected_whenAppInactive() {
        router.applicationStateProvider = { .background }

        let handled = router.handle(URL(string: "dosetap://log?event=bathroom")!)

        XCTAssertFalse(handled, "State-changing log deep links should require the foreground app.")
        XCTAssertNil(router.lastAction)
        XCTAssertTrue(SessionRepository.shared.fetchTonightSleepEvents().isEmpty)
    }

    func test_logEvent_isRejected_whenProtectedDataUnavailable() {
        router.protectedDataProvider = { false }

        let handled = router.handle(URL(string: "dosetap://log?event=wake_final")!)

        XCTAssertFalse(handled, "State-changing log deep links should require protected data availability.")
        XCTAssertNil(SessionRepository.shared.wakeFinalTime)
        XCTAssertNil(router.lastAction)
    }
    
    func test_snooze_setsLastAction() async {
        let url = URL(string: "dosetap://snooze")!
        _ = router.handle(url)
        await router.waitForPendingActions()
        XCTAssertTrue(router.feedbackMessage.count > 0, "Should set feedback message")
    }
    
    func test_skip_setsLastAction() {
        let url = URL(string: "dosetap://skip")!
        _ = router.handle(url)
        XCTAssertTrue(router.feedbackMessage.count > 0, "Should set feedback message")
    }

    func test_skipDeepLink_blocksBeforeWindow_withoutMutation() async {
        let repo = SessionRepository.shared
        repo.setDose1Time(Date().addingTimeInterval(-30 * 60))
        XCTAssertEqual(repo.currentContext.phase, .beforeWindow)

        let handled = router.handle(URL(string: "dosetap://skip")!)
        XCTAssertTrue(handled)
        await router.waitForPendingActions()

        XCTAssertFalse(repo.dose2Skipped, "Before-window deep link must not mutate skip state.")
        XCTAssertEqual(router.feedbackMessage, "Dose 2 window has not opened")
    }

    func test_skipFlicEquivalent_blocksBeforeWindow_withSameReason() async {
        let repo = SessionRepository.shared
        repo.setDose1Time(Date().addingTimeInterval(-30 * 60))
        XCTAssertEqual(repo.currentContext.phase, .beforeWindow)

        let flic = FlicButtonService.shared
        flic.resetToDefaults()
        flic.singlePressAction = .skip
        flic.configure(coordinator: coordinator, undoState: nil)

        let result = await flic.simulateGesture(.singlePress)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "Dose 2 window has not opened")
        XCTAssertFalse(repo.dose2Skipped, "Before-window Flic route must not mutate skip state.")

        flic.resetCommandHandlersForTests()
        flic.resetToDefaults()
    }

    func test_skipDeepLink_persistsInitiatingSurface() async throws {
        let repo = SessionRepository.shared
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        XCTAssertEqual(repo.currentContext.phase, .active)

        XCTAssertTrue(router.handle(URL(string: "dosetap://skip")!))
        await router.waitForPendingActions()
        XCTAssertTrue(repo.dose2Skipped)

        let sessionDate = try XCTUnwrap(repo.activeSessionDate)
        let event = try XCTUnwrap(
            EventStorage.shared.fetchDoseEvents(sessionId: nil, sessionDate: sessionDate)
                .first { $0.eventType == "dose2_skipped" }
        )
        let metadata = try XCTUnwrap(event.metadata?.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: metadata) as? [String: String]
        )
        XCTAssertEqual(object["surface"], RegistrationSurface.deepLink.rawValue)
    }
    
    // MARK: - OAuth Callback Test
    
    func test_oauthCallback_notHandledByRouter() {
        let url = URL(string: "dosetap://oauth?code=abc123")!
        let result = router.handle(url)
        XCTAssertFalse(result, "OAuth should be handled by WHOOP integration, not URLRouter")
    }
}

// MARK: - Navigation Flow Tests

@MainActor
final class NavigationFlowTests: XCTestCase {
    
    private var router: URLRouter!
    
    override func setUp() async throws {
        router = URLRouter.shared
        router.applicationStateProvider = { .active }
        router.protectedDataProvider = { true }
        await router.waitForPendingActions()
        router.lastAction = nil
        router.feedbackMessage = ""
        router.selectedTab = .tonight
    }

    override func tearDown() async throws {
        await router.waitForPendingActions()
        router.resetTestOverrides()
        router.lastAction = nil
        router.feedbackMessage = ""
        router.selectedTab = .tonight
    }
    
    func test_allTabs_selectableViaURL() {
        let tabURLs: [(String, AppTab)] = AppTab.navigationDeepLinks.map {
            ("dosetap://\($0.host)", $0.tab)
        }
        
        for (urlString, expectedTab) in tabURLs {
            let url = URL(string: urlString)!
            _ = router.handle(url)
            XCTAssertEqual(router.selectedTab, expectedTab, 
                "\(urlString) should select tab \(expectedTab.rawValue)")
        }
    }
    
    func test_tabSelection_persistsAfterAction() {
        _ = router.handle(URL(string: "dosetap://settings")!)
        XCTAssertEqual(router.selectedTab, .settings)
        
        _ = router.handle(URL(string: "dosetap://dose1")!)
        
        XCTAssertEqual(router.selectedTab, .settings)
    }
    
    func test_quickEventFlow() {
        let url = URL(string: "dosetap://log?event=bathroom")!
        _ = router.handle(url)
        
        if case .logEvent(let name, _) = router.lastAction {
            XCTAssertEqual(name, "bathroom")
        } else {
            XCTFail("Should parse log event action")
        }
    }
    
    func test_doseFlowFromWidget() {
        let url = URL(string: "dosetap://dose1")!
        _ = router.handle(url)
        
        XCTAssertEqual(router.lastAction, .takeDose1, "Should set takeDose1 action")
    }
}
