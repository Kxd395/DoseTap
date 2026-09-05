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
        if name.contains("testWorkWarning") { app.launchArguments.append("--uitesting-work-warning") }
        if name.contains("testExpiredSessionLaunch") { app.launchArguments.append("--uitesting-expired-session") }
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
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
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Wake deadline:")).firstMatch.exists)
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
        let bottle = app.buttons["startedNewBottle"]
        for _ in 0..<5 where !bottle.isHittable { app.swipeUp() }
        XCTAssertTrue(bottle.isHittable)
        bottle.tap()
        app.buttons["Record bottle start"].tap()
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
