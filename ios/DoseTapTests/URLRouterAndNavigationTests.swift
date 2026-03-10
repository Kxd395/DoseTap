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

// MARK: - URL Router / Deep Link Tests

@MainActor
final class URLRouterTests: XCTestCase {
    
    private var router: URLRouter!
    private var core: DoseTapCore!
    
    override func setUp() async throws {
        router = URLRouter.shared
        core = DoseTapCore(isOnline: { true })
        core.setSessionRepository(SessionRepository.shared)
        router.configure(core: core, eventLogger: EventLogger.shared)
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
    
    func test_dose2_setsLastAction_whenDose1Missing() {
        let url = URL(string: "dosetap://dose2")!
        let result = router.handle(url)
        XCTAssertFalse(result, "Dose2 without Dose1 should return false")
        XCTAssertTrue(router.feedbackMessage.contains("Dose 1"), "Should show Dose 1 required message")
    }

    func test_dose2_deepLink_allowsLateOverride_whenWindowClosed() async {
        let repo = SessionRepository.shared
        repo.setDose1Time(Date().addingTimeInterval(-250 * 60))
        XCTAssertEqual(repo.currentContext.phase, .closed, "Precondition: phase should be closed.")
        XCTAssertNil(repo.dose2Time, "Precondition: Dose 2 should not be logged yet.")

        let url = URL(string: "dosetap://dose2")!
        let handled = router.handle(url)
        XCTAssertTrue(handled, "Dose 2 deep link should be handled in closed window via override.")

        await Task.yield()
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertNotNil(repo.dose2Time, "Late override should log Dose 2.")
        XCTAssertEqual(repo.currentContext.phase, .completed, "Session should complete after late Dose 2.")
    }

    func test_dose2_deepLink_rejectsBeforeWindow_withoutOverride() {
        let repo = SessionRepository.shared
        repo.setDose1Time(Date().addingTimeInterval(-100 * 60))
        XCTAssertEqual(repo.currentContext.phase, .beforeWindow, "Precondition: phase should be beforeWindow.")
        XCTAssertNil(repo.dose2Time, "Precondition: Dose 2 should not be logged yet.")

        let url = URL(string: "dosetap://dose2")!
        let handled = router.handle(url)
        XCTAssertFalse(handled, "Dose 2 deep link should be rejected before the window opens.")
        XCTAssertNil(repo.dose2Time, "Dose 2 should remain unset when request is rejected.")
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
    
    func test_snooze_setsLastAction() {
        let url = URL(string: "dosetap://snooze")!
        _ = router.handle(url)
        XCTAssertTrue(router.feedbackMessage.count > 0, "Should set feedback message")
    }
    
    func test_skip_setsLastAction() {
        let url = URL(string: "dosetap://skip")!
        _ = router.handle(url)
        XCTAssertTrue(router.feedbackMessage.count > 0, "Should set feedback message")
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
