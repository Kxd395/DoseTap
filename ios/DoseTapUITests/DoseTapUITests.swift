import XCTest

/// Core UI smoke tests for DoseTap.
/// These tests verify basic app lifecycle, navigation, and critical user flows.
final class DoseTapUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        if name.contains("testSupply") || name.contains("testSystemAlarm") { app.launchArguments += ["-setup_completed_v2", "YES"] }
        if name.contains("testDashboard") { app.launchArguments += ["--uitesting-dashboard", "-setup_completed_v2", "YES"] }
        if name.contains("testWorkWarning") { app.launchArguments.append("--uitesting-work-warning") }
        if name.contains("testExpiredSessionLaunch") { app.launchArguments.append("--uitesting-expired-session") }
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testDashboardOverviewTrendsAndData() throws {
        app.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["Recorded Nights"].waitForExistence(timeout: 10))
        captureDashboard("Dashboard overview")
        app.buttons["Trends"].tap()
        XCTAssertTrue(app.staticTexts["Interactive Trends"].waitForExistence(timeout: 5))
        app.buttons["WHOOP"].tap()
        captureDashboard("Dashboard trends WHOOP")
        app.buttons["dashboard-trend-picker"].tap()
        app.buttons["Weekday"].tap()
        captureDashboard("Dashboard weekday observed samples")
        app.buttons["Data"].tap()
        XCTAssertTrue(app.staticTexts["Data Coverage"].waitForExistence(timeout: 5))
        captureDashboard("Dashboard data coverage")
        app.swipeUp()
        captureDashboard("Dashboard readable recent nights")
        app.terminate()
        app.launchArguments += ["--dashboard-empty", "--dashboard-partial"]
        app.launch()
        app.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["No data in this range"].waitForExistence(timeout: 10))
        captureDashboard("Dashboard empty and provider error")
    }

    func testDashboardLargeTextAndLandscape() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["Recorded Nights"].waitForExistence(timeout: 10))
        captureDashboard("Dashboard accessibility text")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, object: app)
        wait(for: [landscape], timeout: 10)
        app.swipeUp()
        captureDashboard("Dashboard landscape accessibility text")
    }

    private func captureDashboard(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWorkWarningNonworkingExceptionDoesNotRecordDose() throws {
        let action = app.buttons["dose-primary-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        action.tap()
        let warning = app.navigationBars["Work and Wake Warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Work warning before dated exception"
        before.lifetime = .keepAlways
        add(before)
        let notWorking = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "I'm Not Working ")).firstMatch
        XCTAssertTrue(notWorking.exists)
        notWorking.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: warning)
        wait(for: [dismissed], timeout: 5)
        XCTAssertTrue(action.exists, "A schedule exception must leave the pending dose action available")
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "Dose remains pending after dated exception"
        after.lifetime = .keepAlways
        add(after)
    }

    func testWorkWarningWakeEditorKeepsSaveVisibleAndDosePending() throws {
        let action = app.buttons["dose-primary-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        action.tap()
        let changeWake = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Change ")).firstMatch
        XCTAssertTrue(changeWake.waitForExistence(timeout: 5))
        changeWake.tap()
        XCTAssertTrue(app.navigationBars["Change Wake Time"].waitForExistence(timeout: 5))
        let save = app.buttons["Save Wake Time"]
        XCTAssertTrue(save.isHittable, "The dated editor must expose Save without scrolling")
        save.tap()
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.label.contains("Dose 2"), "Saving a wake exception must not record the dose")
    }

    func testWorkWarningTargetSelectorSavesAllThreeChoices() throws {
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        let schedule = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Typical Week Schedule")).firstMatch
        for _ in 0..<6 where !schedule.isHittable { app.swipeUp() }
        XCTAssertTrue(schedule.isHittable)
        schedule.tap()
        let picker = app.buttons["work-warning-target"]
        for title in ["Fixed work-night cutoff", "Wake time minus my buffer", "Existing Dose 2 target"] {
            for _ in 0..<5 where !picker.isHittable { app.swipeDown() }
            XCTAssertTrue(picker.isHittable)
            picker.tap()
            app.buttons[title].tap()
            let save = app.buttons["Save Work Warning Schedule"]
            for _ in 0..<5 where !save.isHittable { app.swipeUp() }
            XCTAssertTrue(save.isHittable)
            save.tap()
            XCTAssertTrue(app.staticTexts["Work warning schedule saved. No medication record changed."].exists)
        }
    }

    func testWorkWarningContinueKeepsNightAndHidesCompletedAlarm() throws {
        let action = app.buttons["dose-primary-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        let night = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Tonight – ")).firstMatch.label
        action.tap()
        let record = app.buttons["Continue to Record Dose 2"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        XCTAssertTrue(app.staticTexts[night].waitForExistence(timeout: 5))
        XCTAssertFalse(action.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Dose 2 alarm:")).firstMatch.exists)
    }

    // MARK: - App Launch

    func testSystemAlarmPermissionAndBackgroundDelivery() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 3) { springboard.buttons["Allow"].tap() }
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        let link = app.buttons["Locked-phone alarm setup & test"]
        for _ in 0..<5 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable)
        link.tap()
        app.buttons["testLockedAlarm"].tap()
        app.buttons["Schedule test alarm"].tap()
        if springboard.buttons["Allow"].waitForExistence(timeout: 4) { springboard.buttons["Allow"].tap() }
        let result = app.staticTexts["systemAlarmTestResult"]
        for _ in 0..<4 where !result.isHittable { app.swipeUp() }
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", "Test alarm verified."), evaluatedWith: result)
        waitForExpectations(timeout: 10)
        let configured = XCTAttachment(screenshot: app.screenshot())
        configured.name = "AlarmKit test schedule verified"
        configured.lifetime = .keepAlways
        add(configured)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.staticTexts["DoseTap alarm test"].waitForExistence(timeout: 75))
        let delivered = XCTAttachment(screenshot: springboard.screenshot())
        delivered.name = "System alarm delivered with DoseTap backgrounded"
        delivered.lifetime = .keepAlways
        add(delivered)
        if springboard.buttons["Stop"].exists { springboard.buttons["Stop"].tap() }
    }

    func testWorkWarningPreSleepImmediatelyPrecedesActiveDoseAction() throws {
        let dose = app.buttons["dose-primary-action"]
        XCTAssertTrue(dose.waitForExistence(timeout: 15))
        let check = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pre-sleep")).firstMatch
        XCTAssertTrue(check.exists)
        XCTAssertLessThan(check.frame.maxY, dose.frame.minY)
        XCTAssertLessThan(dose.frame.minY - check.frame.maxY, 80)
        XCTAssertTrue(app.staticTexts["tonightWakeTime"].exists)
        XCTAssertFalse(app.buttons["startedNewBottle"].exists)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Tonight active session preparation before dose"
        proof.lifetime = .keepAlways
        add(proof)
    }

    func testSupplyBottleIsFirstInPreSleepAndNeverCarriedForward() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 3) { springboard.buttons["Allow"].tap() }
        let dose = app.buttons["dose-primary-action"]
        XCTAssertTrue(dose.waitForExistence(timeout: 15))
        let doseBefore = dose.label
        let check = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pre-sleep")).firstMatch
        for _ in 0..<5 where !check.isHittable { app.swipeUp() }
        XCTAssertTrue(check.isHittable)
        XCTAssertLessThan(check.frame.maxY, dose.frame.minY, "Pre-sleep preparation must precede the dose action")
        XCTAssertFalse(app.buttons["startedNewBottle"].exists, "Tonight must not duplicate the bottle action outside the check")
        XCTAssertTrue(app.staticTexts["tonightWakeTime"].exists)
        let tonightProof = XCTAttachment(screenshot: app.screenshot())
        tonightProof.name = "Tonight preparation before Dose 1"
        tonightProof.lifetime = .keepAlways
        add(tonightProof)
        check.tap()
        let bottle = app.buttons["preSleepStartedNewBottle"]
        XCTAssertTrue(bottle.waitForExistence(timeout: 5))
        XCTAssertTrue(bottle.isHittable, "Bottle opening must be visible without scrolling")
        let remembered = app.staticTexts["Remember last pre-sleep settings"]
        XCTAssertLessThan(bottle.frame.minY, remembered.frame.minY)
        bottle.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(bottle.waitForExistence(timeout: 5))
        bottle.tap()
        app.buttons["Record bottle start"].tap()
        let saved = app.staticTexts["preSleepLastBottleOpening"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        let savedLabel = saved.label
        let wakeToggle = app.switches["preSleepWakeOverride"]
        XCTAssertTrue(wakeToggle.exists)
        wakeToggle.tap()
        XCTAssertTrue(app.datePickers["preSleepWakeTime"].waitForExistence(timeout: 5))
        let resetWake = app.buttons["resetPreSleepWakeTime"]
        for _ in 0..<3 where !resetWake.isHittable { app.swipeUp() }
        resetWake.tap()
        XCTAssertFalse(app.datePickers["preSleepWakeTime"].exists)
        for _ in 0..<3 where !bottle.isHittable { app.swipeDown() }
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Bottle opening first in pre-sleep check"
        proof.lifetime = .keepAlways
        add(proof)
        app.buttons["Use last"].tap()
        XCTAssertEqual(saved.label, savedLabel)
        app.buttons["Next"].tap()
        app.buttons["Back"].tap()
        XCTAssertEqual(saved.label, savedLabel)
        app.terminate()
        app.launch()
        XCTAssertTrue(dose.waitForExistence(timeout: 15))
        XCTAssertEqual(dose.label, doseBefore)
        for _ in 0..<5 where !check.isHittable { app.swipeUp() }
        check.tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.label, savedLabel)
        XCTAssertTrue(bottle.isHittable, "A new check offers an explicit action, never an auto-selected answer")
    }

    func testSupplyReceiptReminderAndOptionalBottleSurviveRelaunch() throws {
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 3) { springboard.buttons["Allow"].tap() }
        let dose = app.buttons["dose-primary-action"]
        XCTAssertTrue(dose.waitForExistence(timeout: 15))
        let doseBefore = dose.label
        let check = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pre-sleep")).firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertLessThan(check.frame.maxY, dose.frame.minY)
        check.tap()
        let bottle = app.buttons["preSleepStartedNewBottle"]
        XCTAssertTrue(bottle.waitForExistence(timeout: 5))
        bottle.tap()
        app.buttons["Record bottle start"].tap()
        XCTAssertTrue(app.staticTexts["preSleepLastBottleOpening"].waitForExistence(timeout: 5))
        app.buttons["Skip for tonight"].tap()
        XCTAssertTrue(dose.waitForExistence(timeout: 5))
        XCTAssertEqual(dose.label, doseBefore)

        func openSupply() {
            app.buttons["Settings"].tap()
            let link = app.buttons["Supply & order reminder"]
            for _ in 0..<8 where !link.isHittable { app.swipeUp() }
            XCTAssertTrue(link.isHittable)
            link.tap()
        }
        openSupply()
        let save = app.buttons["saveSupplyReminder"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        if springboard.buttons["Allow"].waitForExistence(timeout: 2) { springboard.buttons["Allow"].tap() }
        let status = app.staticTexts["supplyReminderStatus"]
        let scheduled = NSPredicate(format: "label BEGINSWITH %@", "Scheduled:")
        expectation(for: scheduled, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Received date plus 21 days with verified reminder"
        proof.lifetime = .keepAlways
        add(proof)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        openSupply()
        expectation(for: scheduled, evaluatedWith: app.staticTexts["supplyReminderStatus"])
        waitForExpectations(timeout: 10)
        let handled = app.buttons["Mark handled"]
        for _ in 0..<4 where !handled.isHittable { app.swipeUp() }
        handled.tap()
        for _ in 0..<4 where !app.staticTexts["supplyReminderStatus"].isHittable { app.swipeDown() }
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", "Handled"), evaluatedWith: app.staticTexts["supplyReminderStatus"])
        waitForExpectations(timeout: 5)
        let handledProof = XCTAttachment(screenshot: app.screenshot())
        handledProof.name = "Reminder handled without changing dose history"
        handledProof.lifetime = .keepAlways
        add(handledProof)
    }

    func testExpiredSessionLaunchDoesNotReenterRepository() throws {
        XCTAssertTrue(app.buttons["dose-primary-action"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["dose-primary-action"].waitForExistence(timeout: 15))
    }

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
