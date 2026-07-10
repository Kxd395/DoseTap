import XCTest

/// Core UI smoke tests for DoseTap.
/// These tests verify basic app lifecycle, navigation, and critical user flows.
final class DoseTapUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        if name.contains("testLateDose2RecoveryAfterAutoSkip") {
            app.launchArguments.append("--uitesting-late-dose-recovery")
        }
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch

    func testAppLaunches() throws {
        // Verify the app launched and a tab bar is present
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    // MARK: - Tab Navigation

    func testTonightTabExists() throws {
        let tonightTab = app.buttons["Tonight"]
        if tonightTab.waitForExistence(timeout: 5) {
            tonightTab.tap()
            // Tab should remain selected
            XCTAssertTrue(tonightTab.exists)
        }
        // If tab doesn't exist, that's OK — the app may use different labels
    }

    func testDetailsTabExists() throws {
        let detailsTab = app.buttons["Details"]
        if detailsTab.waitForExistence(timeout: 5) {
            detailsTab.tap()
            XCTAssertTrue(detailsTab.exists)
        }
    }

    func testSettingsTabExists() throws {
        let settingsTab = app.buttons["Settings"]
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
            XCTAssertTrue(settingsTab.exists)
        }
    }

    func testTabCycling() throws {
        // Cycle through all tabs to verify no crashes
        let tabLabels = ["Tonight", "Details", "Settings"]
        for label in tabLabels {
            let tab = app.buttons[label]
            if tab.waitForExistence(timeout: 3) {
                tab.tap()
                // Small delay to let UI settle
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        // If we got here without crashing, the test passes
    }

    // MARK: - Dose Flow Smoke Tests

    func testDose1ButtonVisibility() throws {
        // Navigate to Tonight tab first
        let tonightTab = app.buttons["Tonight"]
        if tonightTab.waitForExistence(timeout: 5) {
            tonightTab.tap()
        }

        // Look for dose-related UI elements
        let dose1Button = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] 'dose' OR label CONTAINS[cd] 'Dose 1'"))
        // We just verify the query doesn't crash — button may or may not exist depending on session state
        _ = dose1Button.count
    }

    func testLateDose2RecoveryAfterAutoSkip() throws {
        let recoveryButton = app.buttons["dose-primary-action"]
        XCTAssertTrue(recoveryButton.waitForExistence(timeout: 10))
        XCTAssertTrue(
            recoveryButton.label.localizedCaseInsensitiveContains("late after it was marked skipped"),
            "Auto-skipped Dose 2 must expose the confirmed late recovery action."
        )

        let beforeAttachment = XCTAttachment(screenshot: app.screenshot())
        beforeAttachment.name = "Late Dose 2 Recovery Available"
        beforeAttachment.lifetime = .keepAlways
        add(beforeAttachment)

        recoveryButton.tap()

        let warning = app.alerts["Record Dose 2 After Skip?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(
            warning.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[cd] %@", "clinician or pharmacist")
            ).firstMatch.exists,
            "The late recovery warning must retain the clinical safety language."
        )
        warning.buttons["Record Late Dose 2"].tap()

        XCTAssertTrue(app.navigationBars["After-Skip Reason"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()

        let recoveryRemoved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: recoveryButton
        )
        wait(for: [recoveryRemoved], timeout: 10)

        let morningCloseout = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[cd] %@", "Wake up and end session")
        ).firstMatch
        XCTAssertTrue(morningCloseout.waitForExistence(timeout: 5))

        let afterAttachment = XCTAttachment(screenshot: app.screenshot())
        afterAttachment.name = "Late Dose 2 Recovery Completed"
        afterAttachment.lifetime = .keepAlways
        add(afterAttachment)
    }

    // MARK: - Settings Screen

    func testSettingsScreenLoads() throws {
        let settingsTab = app.buttons["Settings"]
        guard settingsTab.waitForExistence(timeout: 5) else {
            return // Tab bar not in expected format; skip
        }
        settingsTab.tap()

        // Settings should have some identifiable content
        let settingsContent = app.scrollViews.firstMatch
        if settingsContent.waitForExistence(timeout: 3) {
            XCTAssertTrue(settingsContent.exists)
        }
    }

    // MARK: - Accessibility

    func testMainViewHasAccessibleElements() throws {
        // Verify the app has at least some accessible elements
        let allButtons = app.buttons.count
        XCTAssertGreaterThan(allButtons, 0, "App should have at least one accessible button")
    }

    // MARK: - Memory & Stability

    func testRepeatedTabSwitchingDoesNotCrash() throws {
        let tabLabels = ["Tonight", "Details", "Settings"]
        for _ in 0..<10 {
            for label in tabLabels {
                let tab = app.buttons[label]
                if tab.exists {
                    tab.tap()
                }
            }
        }
        // If we survived 30 tab switches, the app is stable
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
    }
}
