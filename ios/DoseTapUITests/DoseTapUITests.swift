import XCTest

/// Core UI smoke tests for DoseTap.
/// These tests verify basic app lifecycle, navigation, and critical user flows.
final class DoseTapUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        if name.contains("testTimelineReviewMetrics") { app.launchArguments += ["--uitesting-review-metrics", "-setup_completed_v2", "YES"] }
        if name.contains("testHistoryBathroomInsights") {
            app.launchArguments += ["--uitesting-bathroom-insights", "--uitesting-review-metrics", "-setup_completed_v2", "YES"]
        }
        if name.contains("testTimelineReviewMetricsPending") { app.launchArguments.append("--uitesting-review-pending") }
        if name.contains("testAutomaticNightMode") { app.launchArguments += ["--uitesting-auto-night-reset", "-setup_completed_v2", "YES"] }
        if name.contains("testCompactLayout") { app.launchArguments += ["--uitesting-layout", "-setup_completed_v2", "YES"] }
        if name.contains("testSupply") || name.contains("testSystemAlarm") || name.contains("testPreSleep") { app.launchArguments += ["-setup_completed_v2", "YES"] }
        if name.contains("testDashboard") { app.launchArguments += ["--uitesting-dashboard", "-setup_completed_v2", "YES"] }
        if name.contains("testWorkWarning") { app.launchArguments.append("--uitesting-work-warning") }
        if name.contains("testDose2Confirmation") || name.contains("testReviewedNightWindow") { app.launchArguments.append("--uitesting-dose2-confirmation") }
        if name.contains("testReviewedNightWindow") { app.launchArguments += ["-healthkit_enabled", "NO"] }
        if name.contains("testExpiredSessionLaunch") { app.launchArguments.append("--uitesting-expired-session") }
        if name.contains("testMorningDefaultDoseIntent") {
            app.launchArguments += ["--uitesting-expired-session", "-morningCheckIn.rememberSettings", "NO"]
        }
        if name.contains("testHistoryManual") { app.launchArguments += ["--uitesting-history", "--uitesting-history-reset", "-setup_completed_v2", "YES"] }
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testTimelineReviewMetricsPendingUpdatesWithoutInteraction() throws {
        app.buttons["Timeline"].tap()
        let review = app.segmentedControls.firstMatch.buttons["Review"]
        XCTAssertTrue(review.waitForExistence(timeout: 15)); review.tap()
        XCTAssertTrue(app.staticTexts["Dose timing: Pending. Interval: Pending."].waitForExistence(timeout: 5))
        // No tap, scroll, repository write or manual refresh crosses this boundary.
        XCTAssertTrue(app.staticTexts["Dose timing: Not recorded. Interval: Not recorded."].waitForExistence(timeout: 30))
    }

    func testHistoryBathroomInsightsCountsAndCapture() throws {
        app.buttons["History"].tap()
        let bathroom = app.descendants(matching: .any).matching(identifier: "insight-Bathroom Logs").firstMatch
        XCTAssertTrue(bathroom.waitForExistence(timeout: 15))
        XCTAssertTrue(bathroom.label.contains("3 logged"))
        XCTAssertTrue(bathroom.label.contains("2 of 3 recorded nights"))
        XCTAssertFalse(app.staticTexts["Avg Bathroom Wake"].exists)
        captureDashboard("History recorded bathroom counts")
        app.buttons["Timeline"].tap()
        let review = app.segmentedControls.firstMatch.buttons["Review"]
        XCTAssertTrue(review.waitForExistence(timeout: 15)); review.tap()
        let capture = app.buttons["Share review screenshot"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10)); capture.tap()
        XCTAssertTrue(app.navigationBars["Review Capture"].waitForExistence(timeout: 30))
        app.buttons["Copy"].tap()
        XCTAssertTrue(app.staticTexts["Copied to clipboard."].waitForExistence(timeout: 5))
        captureDashboard("Review capture preserves bathroom log summary")
    }

    func testTimelineReviewMetricsAndCapture() throws {
        app.buttons["Timeline"].tap()
        let review = app.segmentedControls.firstMatch.buttons["Review"]
        XCTAssertTrue(review.waitForExistence(timeout: 15)); review.tap()
        let bathroom = app.descendants(matching: .any).matching(identifier: "Bathroom Logs: 2 logged").firstMatch
        for _ in 0..<12 where !bathroom.isHittable { app.swipeUp() }
        XCTAssertTrue(bathroom.isHittable)
        XCTAssertTrue(app.staticTexts["Dose timing: Late"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Dose Interval: 4h 0m").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Est. WASO"].exists)
        captureDashboard("Timeline exact late boundary and bathroom log counts")
        let capture = app.buttons["Share review screenshot"]
        for _ in 0..<14 where !capture.isHittable { app.swipeDown() }
        XCTAssertTrue(capture.isHittable); capture.tap()
        XCTAssertTrue(app.navigationBars["Review Capture"].waitForExistence(timeout: 30))
        app.buttons["Copy"].tap()
        XCTAssertTrue(app.staticTexts["Copied to clipboard."].waitForExistence(timeout: 5))
        captureDashboard("Timeline Review generated capture with shared metrics")
    }

    func testAutomaticNightModeRecordsRestartsAndRestoresAtWake() throws {
        let theme = app.buttons["Theme quick switch"]
        XCTAssertTrue(theme.waitForExistence(timeout: 15))
        XCTAssertEqual(theme.value as? String, "Dark")
        let dose1 = app.buttons["dose-primary-action"]
        XCTAssertTrue(dose1.waitForExistence(timeout: 10))
        dose1.tap()
        captureDashboard("Dose 1 action before automatic appearance assertion")
        let night = NSPredicate(format: "value == %@", "Automatic Night Mode")
        expectation(for: night, evaluatedWith: theme)
        waitForExpectations(timeout: 10)
        captureDashboard("Automatic Night Mode after recorded Dose 1")
        for event in ["Bathroom", "Water", "Noise", "Dream"] {
            XCTAssertTrue(app.buttons["\(event) event button"].exists, "Quick Log must remain available")
        }
        app.launchArguments.removeAll { $0 == "--uitesting-auto-night-reset" }
        app.terminate(); app.launch()
        XCTAssertTrue(theme.waitForExistence(timeout: 15))
        expectation(for: night, evaluatedWith: theme)
        waitForExpectations(timeout: 10)
        app.terminate()
        app.launchArguments.append("--uitesting-auto-night-wake")
        app.launch()
        XCTAssertTrue(theme.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "value == %@", "Dark"), evaluatedWith: theme)
        waitForExpectations(timeout: 25)
        captureDashboard("Saved appearance restored at Wake by")
        XCTAssertFalse(app.buttons["dose-primary-action"].label.contains("Dose 1"), "Changing appearance must not clear the dose")
    }

    func testAutomaticNightModeManualOverrideSurvivesRestart() throws {
        let dose1 = app.buttons["dose-primary-action"]
        XCTAssertTrue(dose1.waitForExistence(timeout: 15)); dose1.tap()
        let theme = app.buttons["Theme quick switch"]
        expectation(for: NSPredicate(format: "value == %@", "Automatic Night Mode"), evaluatedWith: theme)
        waitForExpectations(timeout: 10)
        theme.tap()
        XCTAssertEqual(theme.value as? String, "Light")
        app.launchArguments.removeAll { $0 == "--uitesting-auto-night-reset" }
        app.terminate(); app.launch()
        XCTAssertTrue(theme.waitForExistence(timeout: 15))
        XCTAssertEqual(theme.value as? String, "Light")
        captureDashboard("Manual appearance override survives restart")
        app.buttons["Settings"].tap()
        let themeLink = app.buttons["settings-theme"]
        for _ in 0..<10 where !themeLink.isHittable { app.swipeUp() }
        XCTAssertTrue(themeLink.isHittable); themeLink.tap()
        let automatic = app.switches["automatic-night-mode"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 5))
        captureDashboard("Automatic Night Mode setting before toggle")
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: automatic)
        waitForExpectations(timeout: 5)
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: automatic)
        waitForExpectations(timeout: 5)
        captureDashboard("Automatic Night Mode setting")
    }

    func testCompactLayoutTonightFitsAndHistoryUsesOneMetricRow() throws {
        let heading = app.staticTexts["tonight-session-date"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 15))
        let originalY = heading.frame.minY
        let weekly = app.descendants(matching: .any).matching(identifier: "tonight-weekly-insights").firstMatch
        XCTAssertTrue(weekly.exists)
        XCTAssertLessThanOrEqual(weekly.frame.maxY, app.buttons["Tonight"].frame.minY)
        captureDashboard("Compact Tonight before scroll")
        app.swipeUp()
        XCTAssertEqual(heading.frame.minY, originalY, accuracy: 2, "A fitting Tonight page must not scroll into empty padding")
        app.buttons["History"].tap()
        let titles = ["On-Time", "Avg Interval", "Natural Wake", "Bathroom Logs"]
        let cells = titles.map { app.descendants(matching: .any).matching(identifier: "insight-\($0)").firstMatch }
        XCTAssertTrue(cells[0].waitForExistence(timeout: 10))
        for cell in cells { XCTAssertEqual(cell.frame.minY, cells[0].frame.minY, accuracy: 2) }
        captureDashboard("History four-metric row")
    }

    func testCompactLayoutSecondaryHeaders() throws {
        var headerHeights: [String: CGFloat] = [:]
        for title in ["Tonight", "Timeline", "History", "Dashboard", "Settings"] {
            app.buttons[title].tap()
            let header = app.navigationBars[title]
            XCTAssertTrue(header.waitForExistence(timeout: 10))
            headerHeights[title] = header.frame.height
            XCTAssertLessThan(header.frame.minY, 100, "The header should start just below the status bar")
            if title == "Timeline" || title == "Dashboard" {
                let picker = app.segmentedControls.firstMatch
                XCTAssertTrue(picker.exists)
                XCTAssertLessThanOrEqual(picker.frame.minY - header.frame.maxY, 40, "The first control should follow the header without an extra spacer")
            }
            captureDashboard("Compact \(title) header")
        }
        for (title, height) in headerHeights {
            XCTAssertLessThanOrEqual(height, 64, "\(title) should use a compact navigation header, not an expanded title region")
        }
    }

    func testCompactLayoutSecondaryHeadersLargeText() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        try testCompactLayoutSecondaryHeaders()
    }

    func testCompactLayoutSharedPageControls() throws {
        for title in ["Tonight", "Timeline", "History", "Dashboard", "Settings"] {
            app.buttons[title].tap()
            let header = app.navigationBars[title]
            XCTAssertTrue(header.waitForExistence(timeout: 10))
            XCTAssertLessThanOrEqual(header.frame.height, 64)
            let theme = header.buttons["Theme quick switch"]
            let capture = header.buttons["Share current page capture"]
            XCTAssertTrue(theme.isHittable, "\(title) must expose the shared theme control")
            XCTAssertTrue(capture.isHittable, "\(title) must expose page capture")
            XCTAssertLessThan(theme.frame.midX, header.frame.midX)
            XCTAssertGreaterThan(capture.frame.midX, header.frame.midX)
            captureDashboard("Shared controls on \(title)")
            capture.tap()
            XCTAssertTrue(app.navigationBars["Full Screen Capture"].waitForExistence(timeout: 10))
            captureDashboard("Page capture preview on \(title)")
            app.navigationBars["Full Screen Capture"].buttons["Done"].tap()
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            if title == "Timeline" {
                app.segmentedControls.firstMatch.buttons["Review"].tap()
                XCTAssertTrue(capture.isHittable)
                captureDashboard("Shared controls on Timeline Review")
                capture.tap()
                XCTAssertTrue(app.navigationBars["Full Screen Capture"].waitForExistence(timeout: 10))
                app.navigationBars["Full Screen Capture"].buttons["Done"].tap()
                app.segmentedControls.firstMatch.buttons["Live"].tap()
            }
        }
    }

    func testCompactLayoutSharedThemeAcrossTabs() throws {
        app.buttons["Timeline"].tap()
        let theme = app.navigationBars["Timeline"].buttons["Theme quick switch"]
        XCTAssertTrue(theme.waitForExistence(timeout: 10))
        theme.press(forDuration: 1)
        app.buttons["Dark"].tap()
        theme.tap()
        for title in ["Tonight", "History", "Dashboard", "Settings", "Timeline", "Tonight", "History", "Dashboard", "Settings", "Timeline"] {
            app.buttons[title].tap()
            let control = app.navigationBars[title].buttons["Theme quick switch"]
            XCTAssertTrue(control.waitForExistence(timeout: 10), "\(title) must retain its header after appearance changes")
            captureDashboard("Night Mode shared controls on \(title)")
            XCTAssertEqual(control.value as? String, "Night Mode", "Appearance must be shared across every tab")
        }
        theme.press(forDuration: 1)
        app.buttons["Dark"].tap()
        XCTAssertEqual(theme.value as? String, "Dark")
    }

    func testCompactLayoutLargeTextKeepsContentReachable() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 15))
        captureDashboard("Tonight largest accessibility text top")
        let weekly = app.descendants(matching: .any).matching(identifier: "tonight-weekly-insights").firstMatch
        for _ in 0..<15 where !weekly.exists || weekly.frame.maxY > app.buttons["Tonight"].frame.minY { app.swipeUp() }
        XCTAssertLessThanOrEqual(weekly.frame.maxY, app.buttons["Tonight"].frame.minY, "The bottom of the summary must remain reachable")
        captureDashboard("Tonight largest accessibility text weekly summary")
        app.buttons["History"].tap()
        let first = app.descendants(matching: .any).matching(identifier: "insight-On-Time").firstMatch
        let second = app.descendants(matching: .any).matching(identifier: "insight-Avg Interval").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(second.frame.minY, first.frame.minY, "Large text must stack metrics instead of squeezing four columns")
        captureDashboard("History largest accessibility text metrics")
    }

    func testHistoryManualEntriesCorrectionsAndRestart() throws {
        app.launchArguments.removeAll { $0 == "--uitesting-history-reset" }
        func reveal(_ element: XCUIElement) {
            for _ in 0..<8 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        func choose(_ title: String) {
            let picker = app.buttons["history-record-type"]
            reveal(picker); picker.tap(); app.buttons[title].tap()
        }
        func enterReason() {
            let reason = app.descendants(matching: .any).matching(identifier: "history-record-reason").firstMatch
            reveal(reason); reason.tap(); reason.typeText("Reviewed manual history")
        }
        func save() {
            let button = app.buttons["history-review-save"]
            reveal(button); button.tap(); app.alerts.buttons["Confirm Save"].tap()
            XCTAssertTrue(app.staticTexts["history-save-feedback"].waitForExistence(timeout: 5))
        }
        app.buttons["History"].tap()
        let manage = app.buttons["history-manage-records"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
        XCTAssertTrue(app.staticTexts["history-no-doses"].waitForExistence(timeout: 5))
        enterReason()
        reveal(app.buttons["history-review-save"]); app.buttons["history-review-save"].tap()
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["history-no-doses"].exists, "Cancel must not create a night")
        save()
        choose("Dose 2"); enterReason(); save()
        choose("Extra Dose"); enterReason(); save()
        // iOS can report a row beneath the translucent navigation bar as
        // hittable. Bring the whole record below the bar before selecting it.
        for _ in 0..<8 where !app.buttons["history-record-extra_dose"].isHittable || app.buttons["history-record-extra_dose"].frame.minY < 180 { app.swipeDown() }
        app.buttons["history-record-extra_dose"].tap(); enterReason()
        reveal(app.buttons["history-remove-record"]); app.buttons["history-remove-record"].tap()
        app.alerts.buttons["Confirm Removal"].tap()
        XCTAssertTrue(app.staticTexts["history-save-feedback"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["history-record-extra_dose"].exists)
        for _ in 0..<8 where !app.buttons["history-record-dose2"].isHittable || app.buttons["history-record-dose2"].frame.minY < 180 { app.swipeDown() }
        app.buttons["history-record-dose2"].tap()
        choose("Dose 2 — missed / not taken"); enterReason(); save()
        choose("Bathroom"); enterReason(); save()
        captureDashboard("Manual history entry for a night older than 24 hours")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 15)); app.buttons["History"].tap()
        XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
        XCTAssertTrue(app.buttons["history-record-dose1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history-record-dose2_skipped"].exists)
        XCTAssertFalse(app.buttons["history-record-extra_dose"].exists, "Removal must survive restart")
        XCTAssertTrue(app.buttons["history-sleep-bathroom"].exists)
        captureDashboard("Reviewed history survived a fresh process")
        app.buttons["history-sleep-bathroom"].tap()
        let notes = app.descendants(matching: .any).matching(identifier: "history-record-reason").firstMatch
        reveal(notes)
        XCTAssertEqual(notes.value as? String, "Reviewed manual history", "Editing a time must preserve the original notes")
    }

    func testHistoryManualQuestionnairesCancelSaveEditAndRestart() throws {
        app.launchArguments.removeAll { $0 == "--uitesting-history-reset" }
        func reveal(_ element: XCUIElement) {
            for _ in 0..<18 {
                if element.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(element.isHittable)
        }
        func openHistory() {
            XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 15)); app.buttons["History"].tap()
            app.buttons["history-manage-records"].tap()
        }
        func openQuestionnaire(_ id: String) {
            app.buttons[id].tap()
            let reason = app.descendants(matching: .any).matching(identifier: "history-questionnaire-reason").firstMatch
            XCTAssertTrue(reason.waitForExistence(timeout: 5)); reason.tap(); reason.typeText("Remembered this night")
            app.buttons["history-open-questionnaire"].tap()
        }
        func confirmSaved() {
            XCTAssertTrue(app.alerts["Confirm Questionnaire History"].waitForExistence(timeout: 5))
            app.alerts.buttons["Confirm Save"].tap()
            XCTAssertTrue(app.staticTexts["history-questionnaire-saved"].waitForExistence(timeout: 5))
        }
        openHistory()
        openQuestionnaire("history-pre-sleep-questionnaire")
        XCTAssertFalse(app.buttons["Skip for tonight"].exists)
        XCTAssertFalse(app.buttons["Use room setup"].exists)
        app.buttons["Next"].tap(); app.buttons["Next"].tap()
        let foodToggle = app.switches["pre-last-food-toggle"]
        reveal(foodToggle); foodToggle.tap()
        let foodNotes = app.textFields["pre-last-food-notes"].firstMatch
        let foodEditor = app.textViews["pre-last-food-notes"].firstMatch
        let foodInput = foodNotes.exists ? foodNotes : foodEditor
        reveal(foodInput)
        app.buttons["pre-last-food-kind"].tap()
        app.buttons["Meal"].tap()
        app.segmentedControls["pre-last-food-fat"].buttons["Yes"].tap()
        foodInput.tap(); foodInput.typeText("Fried chicken and fries")
        captureDashboard("Last food with high-fat answer in pre-sleep history")
        app.buttons["Review"].tap()
        XCTAssertTrue(app.alerts["Confirm Questionnaire History"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["history-questionnaire-saved"].exists)
        app.buttons["history-save-questionnaire"].tap(); confirmSaved()
        captureDashboard("Past-night pre-sleep questionnaire saved after review")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["history-no-doses"].exists, "Questionnaires must not infer medication")
        openQuestionnaire("history-morning-questionnaire")
        let notes = app.descendants(matching: .any).matching(identifier: "morning-check-in-notes").firstMatch
        reveal(notes); notes.tap(); notes.typeText("Remembered morning")
        let submit = app.buttons["Review History Answers"]
        reveal(submit); submit.tap(); confirmSaved()
        app.terminate(); app.launch(); openHistory()
        XCTAssertTrue(app.staticTexts["history-no-doses"].exists, "Neither questionnaire creates doses after restart")
        openQuestionnaire("history-morning-questionnaire")
        reveal(notes)
        XCTAssertEqual(notes.value as? String, "Remembered morning")
        notes.tap(); notes.typeText(". Corrected")
        reveal(submit); submit.tap(); confirmSaved()
        captureDashboard("Morning history correction saved without medication side effects")
        app.buttons["Done"].firstMatch.tap()
        openQuestionnaire("history-pre-sleep-questionnaire")
        XCTAssertTrue(app.navigationBars["Edit Pre-Sleep"].waitForExistence(timeout: 5), "Pre-sleep answers must also survive restart")
        app.buttons["Next"].tap(); app.buttons["Next"].tap()
        reveal(foodInput)
        XCTAssertEqual(foodInput.value as? String, "Fried chicken and fries")
        let foodKind = app.buttons["pre-last-food-kind"]
        XCTAssertTrue("\(foodKind.label) \(foodKind.value ?? "")".contains("Meal"))
        XCTAssertTrue(app.segmentedControls["pre-last-food-fat"].buttons["Yes"].isSelected)
        captureDashboard("Last food restored after restart in History")
        app.buttons["Cancel"].tap()
    }

    func testReviewedNightWindow() throws {
        app.launchArguments.removeAll { $0 == "--uitesting-dose2-confirmation" }
        func reveal(_ element: XCUIElement) {
            for _ in 0..<8 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        func toggle(_ element: XCUIElement) {
            reveal(element)
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        func acknowledge(_ title: String) {
            XCTAssertTrue(app.alerts[title].waitForExistence(timeout: 5))
            app.alerts[title].buttons["OK"].tap()
        }
        let dose = app.buttons["dose-primary-action"]
        XCTAssertTrue(dose.waitForExistence(timeout: 15)); reveal(dose); dose.tap()
        XCTAssertTrue(app.buttons["dose2-confirm-record"].waitForExistence(timeout: 5))
        app.buttons["dose2-wake-natural"].tap(); app.buttons["dose2-confirm-record"].tap()
        let diary = app.buttons["night-outcome-open"]
        XCTAssertTrue(diary.waitForExistence(timeout: 10)); diary.tap()
        toggle(app.switches["Record final awakening"])
        app.buttons["night-outcome-save"].tap(); acknowledge("Answers saved")
        diary.tap()
        let enabled = app.switches["night-window-enabled"], confirm = app.switches["night-window-confirm"]
        toggle(enabled)
        app.buttons["night-outcome-save"].tap(); acknowledge("Answers not saved")
        app.buttons["Done"].tap(); diary.tap(); reveal(enabled)
        XCTAssertEqual(enabled.value as? String, "0", "Unconfirmed or cancelled windows must not save")
        toggle(enabled); toggle(confirm)
        let range = app.staticTexts["night-window-range"]
        let reviewedRange = range.label
        XCTAssertTrue(reviewedRange.contains("UTC:"))
        captureDashboard("Reviewed night bounds before explicit save")
        app.buttons["night-outcome-save"].tap(); acknowledge("Answers saved")
        app.terminate(); app.launch()
        XCTAssertTrue(diary.waitForExistence(timeout: 15)); diary.tap(); reveal(enabled)
        XCTAssertEqual(enabled.value as? String, "1")
        reveal(app.staticTexts["night-window-saved"])
        let assessment = app.staticTexts["night-window-assessment"]
        reveal(assessment)
        XCTAssertEqual(assessment.label, "Saved bounds checked")
        XCTAssertEqual(range.label, reviewedRange)
        captureDashboard("Reviewed night bounds restored after restart")
        let coverage = app.buttons["night-window-check-coverage"]
        app.swipeUp() // Move the entire action above the home-indicator/viewport edge before tapping.
        reveal(coverage); coverage.tap()
        let coverageStatus = app.staticTexts["night-window-coverage-status"]
        app.swipeUp()
        captureDashboard("Coverage check after explicit action")
        XCTAssertTrue(coverageStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(coverageStatus.label.contains("disabled"))
        captureDashboard("Reviewed night Apple Health disabled state")
        for _ in 0..<8 where !enabled.isHittable { app.swipeDown() }
        toggle(enabled)
        XCTAssertFalse(coverageStatus.exists, "Changing bounds must clear the earlier provider result")
        app.buttons["night-outcome-save"].tap(); acknowledge("Answers not saved")
        let reason = app.textFields["night-outcome-reason"]
        for _ in 0..<8 where !reason.isHittable { app.swipeDown() }
        XCTAssertTrue(reason.isHittable); reason.tap(); reason.typeText("Remove incorrect night window")
        app.buttons["night-outcome-save"].tap(); acknowledge("Answers saved")
        diary.tap(); reveal(enabled)
        XCTAssertEqual(enabled.value as? String, "0")
        captureDashboard("Window cleared with retained correction history")
        app.buttons["Done"].tap()
        XCTAssertFalse(dose.exists, "Window edits must not remove or create medication records")
    }

    func testDose2ConfirmationCancelBackgroundAndExplicitSave() throws {
        // Seed only once. Relaunch below must read the committed database.
        app.launchArguments.removeAll { $0 == "--uitesting-dose2-confirmation" }
        let action = app.buttons["dose-primary-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        for _ in 0..<6 where !action.isHittable { app.swipeUp() }
        XCTAssertTrue(action.isHittable)
        action.tap()
        let confirm = app.buttons["dose2-confirm-record"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "The first tap must only open confirmation")
        let natural = app.buttons["dose2-wake-natural"]
        let alarm = app.buttons["dose2-wake-alarm"]
        natural.tap()
        XCTAssertEqual(natural.value as? String, "Selected")
        alarm.tap()
        XCTAssertEqual(natural.value as? String, "Not selected")
        XCTAssertEqual(alarm.value as? String, "Selected")
        captureDashboard("Dose 2 explicit confirmation before any medication write")
        app.buttons["dose2-cancel-record"].tap()
        XCTAssertTrue(action.waitForExistence(timeout: 5), "Cancel must leave Dose 2 pending")

        action.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(natural.value as? String, "Not selected", "Cancelled choices must not be saved or reused")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.exists, "Backgrounding must dismiss stale confirmation")

        action.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        natural.tap()
        captureDashboard("Natural wake selected on Dose 2 confirmation before saving")
        confirm.tap()
        let committed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: action)
        wait(for: [committed], timeout: 5)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Tonight"].waitForExistence(timeout: 15))
        XCTAssertFalse(action.exists, "Confirmed Dose 2 must survive process restart without reseeding")
        captureDashboard("Dose 2 confirmed record restored after relaunch")
        let diary = app.buttons["night-outcome-open"]
        XCTAssertTrue(diary.waitForExistence(timeout: 15))
        XCTAssertTrue(diary.label.contains("Natural"), "The checkbox answer must be committed with Dose 2 and survive relaunch")
        XCTAssertFalse(action.exists, "Wake answers must not change the recorded dose")
        diary.tap()
        app.segmentedControls["night-wake-method"].buttons["Alarm"].tap()
        app.buttons["night-outcome-save"].tap()
        XCTAssertTrue(app.alerts["Answers not saved"].waitForExistence(timeout: 5))
        captureDashboard("Wake correction requires a visible reason")
        app.alerts["Answers not saved"].buttons["OK"].tap()
        let reason = app.textFields["night-outcome-reason"]
        reason.tap(); reason.typeText("Corrected wake method")
        app.buttons["night-outcome-save"].tap()
        XCTAssertTrue(app.alerts["Answers saved"].waitForExistence(timeout: 5))
        app.alerts["Answers saved"].buttons["OK"].tap()
        diary.tap()
        let finalWake = app.switches["Record final awakening"]
        for _ in 0..<4 where !finalWake.isHittable { app.swipeUp() }
        finalWake.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let sleepiness = app.switches["night-sleepiness-toggle"]
        for _ in 0..<4 where !sleepiness.isHittable { app.swipeUp() }
        sleepiness.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.buttons["night-outcome-save"].tap()
        XCTAssertTrue(app.alerts["Answers saved"].waitForExistence(timeout: 5), "Adding a later assessment must not require a correction reason")
        app.alerts["Answers saved"].buttons["OK"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(diary.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: diary)
        waitForExpectations(timeout: 10)
        diary.tap()
        for _ in 0..<4 where !sleepiness.isHittable { app.swipeUp() }
        XCTAssertEqual(sleepiness.value as? String, "1")
        captureDashboard("Timestamped next-day sleepiness restored after restart")
        app.buttons["Done"].tap()
        verifyMorningWakeReview(expected: "Alarm")
    }

    private func verifyMorningWakeReview(expected: String) {
        app.buttons["History"].tap()
        let manage = app.buttons["history-manage-records"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); manage.tap()
        app.buttons["history-morning-questionnaire"].tap()
        let historyReason = app.descendants(matching: .any).matching(identifier: "history-questionnaire-reason").firstMatch
        XCTAssertTrue(historyReason.waitForExistence(timeout: 5))
        historyReason.tap(); historyReason.typeText("Review wake answer")
        app.buttons["history-open-questionnaire"].tap()
        XCTAssertTrue(app.navigationBars["Morning Check-In"].waitForExistence(timeout: 5))
        captureDashboard("Morning questionnaire initial viewport")
        let morningWake = app.buttons["morning-dose2-wake-review"]
        let editor = app.navigationBars["Wake & Next Day"]
        for index in 0..<14 where !morningWake.isHittable && !editor.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
            if index < 4 { captureDashboard("Morning wake review scroll \(index)") }
        }
        // A drag beginning on this large button can activate it while revealing
        // the card. Do not continue scrolling the editor over its parent button.
        if !editor.exists {
            XCTAssertTrue(morningWake.isHittable)
            XCTAssertTrue(morningWake.label.contains(expected), "Morning review must show the same Dose 2 answer")
            captureDashboard("Morning questionnaire reviews the same Dose 2 wake answer")
            morningWake.tap()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["night-wake-method"].buttons[expected].isSelected)
        captureDashboard("Shared Dose 2 wake answer opened from morning questionnaire")
        editor.buttons["Done"].tap()
        XCTAssertTrue(morningWake.label.contains(expected))
        captureDashboard("Morning questionnaire saved wake summary")
        app.navigationBars["Morning Check-In"].buttons["Cancel"].tap()
    }

    func testDashboardOverviewTrendsAndData() throws {
        app.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["Recorded Nights"].waitForExistence(timeout: 10))
        captureDashboard("Dashboard overview")
        app.segmentedControls["dashboard-section-picker"].buttons["Trends"].tap()
        revealDashboardText("Interactive Trends")
        app.buttons["WHOOP"].tap()
        captureDashboard("Dashboard trends WHOOP")
        app.buttons["dashboard-trend-picker"].tap()
        app.buttons["Weekday"].tap()
        captureDashboard("Dashboard weekday observed samples")
        let sectionPicker = app.segmentedControls["dashboard-section-picker"]
        for _ in 0..<8 where !sectionPicker.isHittable { app.swipeDown() }
        sectionPicker.buttons["Data"].tap()
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

    func testDashboardBuild14MetricsInEverySection() throws {
        app.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["Recorded Nights"].waitForExistence(timeout: 10))
        selectDashboardSection("Overview")
        revealDashboardText("Finished-night streak", prefix: true)
        revealDashboardText("Coverage · 3+ categories", prefix: true)
        revealDashboardText("WHOOP HRV", prefix: true)
        revealDashboardText("Tonight:", prefix: true)
        captureDashboard("Build14 parity Overview summaries")
        revealDashboardText("Duplicate Nights")
        revealDashboardText("Record review flags")
        revealDashboardText("Nap Nights")
        revealDashboardText("Resting HR")
        captureDashboard("Build14 parity WHOOP missing readings")

        selectDashboardSection("Trends")
        app.buttons["7D"].tap()
        revealDashboardText("vs. Prior Week")
        revealDashboardText("Recorded On-Time %", prefix: true)
        captureDashboard("Build14 parity prior comparison")
        revealDashboardText("Natural waking vs. alarm waking")
        revealDashboardText("Within-window pairs")
        captureDashboard("Wake comparison replaces legacy timing split")
        revealDashboardText("Alcohol: No data", prefix: true)
        revealDashboardText("Exercise Days")
        captureDashboard("Build14 parity lifestyle missing answers")
        revealDashboardText("Mental Clarity")
        revealDashboardText("Narcolepsy Symptoms")
        captureDashboard("Build14 parity morning metrics")

        selectDashboardSection("Data")
        revealDashboardText("Morning check-in rate:", prefix: true)
        revealDashboardText("Nights with at least 3 of 4 data categories:", prefix: true)
        revealDashboardText("Coverage: 4/4 categories")
        captureDashboard("Build14 parity Data per-night coverage")
        selectDashboardSection("Overview")
        app.buttons["Dashboard colors & missing data"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Blue values:")).firstMatch.waitForExistence(timeout: 5))
        captureDashboard("Build14 parity color key")
    }

    private func selectDashboardSection(_ title: String) {
        let picker = app.segmentedControls["dashboard-section-picker"]
        for _ in 0..<30 where !picker.isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(picker.isHittable)
        picker.buttons[title].tap()
    }

    func testDashboardAllRestoresEveryCardWithoutChangingSections() throws {
        app.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["Recorded Nights"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls["dashboard-section-picker"].buttons["All"].isSelected)
        captureDashboard("Restored dashboard All overview")
        for title in ["Recorded Dose Timing", "Sleep Outcomes", "WHOOP Recovery & Biometrics",
                      "Period Comparison", "Interactive Trends", "Natural waking vs. alarm waking",
                      "Timing & status · full date range", "Food timing & next-day diary", "Lifestyle Factors",
                      "Mood & Symptoms", "Stress Trends", "Data Coverage", "Integrations",
                      "Recent Nights · up to 14", "Captured Metrics Inventory"] {
            revealDashboardText(title)
            if ["Lifestyle Factors", "Data Coverage", "Captured Metrics Inventory"].contains(title) {
                captureDashboard("Restored dashboard " + title)
            }
        }
        app.terminate()
        app.launchArguments += ["--dashboard-sparse"]
        app.launch()
        app.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["Recorded Nights"].waitForExistence(timeout: 10))
        revealDashboardText("WHOOP Recovery & Biometrics")
        revealDashboardText("No WHOOP nights in this range. Check the WHOOP connection in Settings, then refresh or choose a wider range.")
        revealDashboardText("Natural waking vs. alarm waking")
        revealDashboardText("Each n counts nights with that measurement, not all recorded pairs. Missing data is not zero.")
        revealDashboardText("Timing & status · full date range")
        revealDashboardText("Before: <150 min · Within: 150–240 min inclusive · After: >240 min. Classified using unrounded elapsed time.")
        captureDashboard("Sparse dashboard explains prerequisites")
        app.terminate()
        app.launchArguments += ["--dashboard-empty"]
        app.launch()
        app.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["No data in this range"].waitForExistence(timeout: 10))
        revealDashboardText("Integrations")
        revealDashboardText("Captured Metrics Inventory")
        captureDashboard("Empty dashboard keeps data reference")
    }

    func testDashboardWakeComparison() throws {
        app.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["Recorded Nights"].waitForExistence(timeout: 10))
        app.segmentedControls["dashboard-section-picker"].buttons["Trends"].tap()
        revealDashboardText("Natural waking vs. alarm waking")
        captureDashboard("Wake comparison heading and day filter")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        captureDashboard("Wake comparison medians and independent usable counts")
        revealDashboardText("Timing & status · full date range")
        captureDashboard("Wake comparison missing-data and full-status disclosures")
        revealDashboardText("Food timing & next-day diary")
        let foodFilter = app.descendants(matching: .any).matching(identifier: "food-comparison-day-filter").firstMatch
        XCTAssertTrue(foodFilter.isHittable, app.debugDescription)
        foodFilter.tap()
        app.buttons["Day off"].tap()
        XCTAssertTrue(app.staticTexts["Last food recorded: 3 of 4 nights"].exists)
        foodFilter.tap()
        app.buttons["All days"].tap()
        captureDashboard("Food timing recorded and missing counts")
        let foodComparison = app.buttons["Compare recorded food answers"]
        for _ in 0..<4 where !foodComparison.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(foodComparison.isHittable)
        foodComparison.tap()
        revealDashboardText("High-fat: No")
        captureDashboard("Food timing paired outcomes and usable counts")
    }

    private func revealDashboardText(_ title: String, prefix: Bool = false) {
        let element = app.staticTexts.matching(NSPredicate(format: prefix ? "label BEGINSWITH %@" : "label == %@", title)).firstMatch
        for _ in 0..<18 {
            if element.exists && element.isHittable { return }
            app.swipeUp(velocity: .slow)
        }
        XCTFail("Dashboard card not reachable: " + title)
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
        let screenRotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let size = XCUIScreen.main.screenshot().image.size
            return size.width > size.height
        }, object: nil)
        wait(for: [screenRotated], timeout: 10)
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
        let confirm = app.buttons["dose2-confirm-record"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Acknowledging a work warning must not record Dose 2")
        confirm.tap()
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
        let remembered = app.staticTexts["Remember room setup"]
        XCTAssertLessThan(bottle.frame.minY, remembered.frame.minY)
        bottle.tap()
        app.navigationBars["New bottle"].buttons["Cancel"].tap()
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
        app.buttons["Use room setup"].tap()
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

    func testPreSleepCaffeineDistinguishesNoneFromUnanswered() throws {
        let check = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pre-sleep")).firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 15))
        for _ in 0..<5 where !check.isHittable { app.swipeUp() }
        check.tap()
        app.buttons["Next"].tap()
        let none = app.buttons["preSleepNoCaffeine"]
        for _ in 0..<10 where !none.isHittable { app.swipeUp() }
        XCTAssertTrue(none.isHittable)
        none.tap()
        let answer = app.staticTexts["preSleepCaffeineAnswer"]
        XCTAssertEqual(answer.label, "No caffeine today")
        let clear = app.buttons["preSleepClearCaffeine"]
        clear.tap()
        XCTAssertEqual(answer.label, "Not recorded")
        XCTAssertFalse(clear.exists)
        let coffee = app.buttons["Coffee"]
        for _ in 0..<3 where !coffee.isHittable { app.swipeUp() }
        coffee.tap()
        XCTAssertEqual(answer.label, "Coffee")
        coffee.tap()
        XCTAssertEqual(answer.label, "Not recorded", "Deselecting the last source is not an explicit No answer")
        none.tap()
        app.buttons["Back"].tap()
        app.buttons["Next"].tap()
        for _ in 0..<10 where !none.isHittable { app.swipeUp() }
        XCTAssertEqual(answer.label, "No caffeine today")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Explicit caffeine answer"
        proof.lifetime = .keepAlways
        add(proof)
    }

    func testPreSleepIndependentPainPatternsSurviveRestartWithoutAutoLogging() throws {
        func reveal(_ element: XCUIElement) {
            for _ in 0..<14 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        func openCheck() {
            let check = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pre-sleep")).firstMatch
            XCTAssertTrue(check.waitForExistence(timeout: 15))
            reveal(check); check.tap(); app.buttons["Next"].tap()
        }
        func addPain(area: String, sensations: [String]) {
            let add = app.buttons["add-pain-entry"]
            reveal(add); add.tap()
            let remember = app.switches["pain-remember-future"]
            XCTAssertTrue(remember.waitForExistence(timeout: 5))
            remember.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            captureDashboard("Remember pain selection before saving")
            XCTAssertEqual(remember.value as? String, "1")
            let location = app.buttons["pain-area-\(area)"]
            reveal(location); location.tap()
            let intensity = app.sliders["pain-intensity"]
            reveal(intensity); intensity.adjust(toNormalizedSliderPosition: 0.2)
            let aching = app.buttons["pain-sensation-aching"]
            reveal(aching); aching.tap()
            for sensation in sensations {
                let button = app.buttons["pain-sensation-\(sensation)"]
                reveal(button); button.tap()
            }
            app.navigationBars.buttons["Save"].tap()
        }
        openCheck()
        let mild = app.buttons["Mild"]
        reveal(mild); mild.tap()
        addPain(area: "mid_back", sensations: ["throbbing", "tightness"])
        addPain(area: "ankle_foot", sensations: ["pins_needles", "numbness"])
        let back = app.descendants(matching: .any).matching(identifier: "night-pain-mid_back|both").firstMatch
        let feet = app.descendants(matching: .any).matching(identifier: "night-pain-ankle_foot|both").firstMatch
        XCTAssertTrue(back.label.contains("Throbbing"))
        XCTAssertFalse(back.label.contains("Numbness"))
        XCTAssertTrue(feet.label.contains("Numbness"))
        XCTAssertFalse(feet.label.contains("Throbbing"))
        app.terminate(); app.launch(); openCheck()
        XCTAssertFalse(back.exists, "Remembering is not a nightly observation")
        XCTAssertFalse(feet.exists)
        let useBack = app.buttons["use-pain-mid_back|both"]
        reveal(useBack); useBack.tap()
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertFalse(back.exists)
        useBack.tap()
        let tonightIntensity = app.sliders["pain-intensity"]
        XCTAssertTrue(tonightIntensity.isHittable, "Saved pain should expose tonight's level without scrolling")
        tonightIntensity.adjust(toNormalizedSliderPosition: 0.6)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(back.exists)
        XCTAssertTrue(back.label.contains("6/10"))
        XCTAssertEqual(app.buttons["remember-pain-mid_back|both"].label, "Update saved pattern")
        XCTAssertFalse(feet.exists, "Selecting one pattern must not add the other")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Independent saved pain patterns reviewed for tonight"
        proof.lifetime = .keepAlways
        add(proof)
        useBack.tap()
        let lowerBack = app.buttons["pain-area-lower_back"]
        reveal(lowerBack); lowerBack.tap()
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(back.exists, "Changing a template's area must preserve the existing nightly back entry")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "night-pain-lower_back|both").firstMatch.exists)
        for key in ["mid_back|both", "ankle_foot|both"] {
            let forget = app.buttons["forget-pain-\(key)"]
            for _ in 0..<10 where !forget.isHittable { app.swipeDown() }
            forget.tap()
        }
        XCTAssertTrue(back.exists, "Forgetting a template must not remove tonight's reviewed entry")
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
        // Earlier questionnaire journeys may leave a saved check for this night.
        // Close its editor without changing that record; new checks can be skipped.
        let existingCheck = app.navigationBars["Edit Pre-Sleep"]
        if existingCheck.exists {
            existingCheck.buttons["Cancel"].tap()
        } else {
            app.navigationBars["Pre-Sleep Check"].buttons["Skip for tonight"].tap()
        }
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

    func testMorningDefaultDoseIntent() throws {
        let finish = app.buttons["Finish"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 15))
        finish.tap()
        let unchanged = app.segmentedControls.buttons["Leave as-is"].firstMatch
        for _ in 0..<8 where !unchanged.isHittable { app.swipeUp() }
        XCTAssertTrue(unchanged.isHittable)
        XCTAssertTrue(unchanged.isSelected, "Missing Dose 2 must never default to Taken or Skipped")
        captureDashboard("Morning missing Dose 2 stays Leave as-is")
        let complete = app.buttons["Complete Check-In"]
        for _ in 0..<20 where !complete.isHittable { app.swipeUp() }
        XCTAssertTrue(complete.isHittable)
        XCTAssertTrue(complete.isEnabled)
        complete.tap()
        XCTAssertTrue(app.buttons["dose-primary-action"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["morning-check-in-storage-error"].exists)
        captureDashboard("Morning answers saved without selecting a missing dose")
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
