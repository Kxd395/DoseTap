import XCTest

final class QuestionnaireAccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["DOSETAP_DAYTIME_TEST_ID"] = UUID().uuidString
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testMorningAtNormalText() throws { try morning(largeText: false) }
    func testMorningAtLargestText() throws { try morning(largeText: true) }
    func testMorningFailureAtLargestText() throws { try morning(largeText: true, failSave: true) }
    func testBedtimeAtNormalText() throws { try bedtime(largeText: false) }
    func testBedtimeAtLargestTextWithReducedMotion() throws { try bedtime(largeText: true) }

    private func launch(largeText: Bool, morning: Bool, failSave: Bool = false) {
        app.launchArguments = ["--uitesting", morning ? "--uitesting-expired-session" : "--uitesting-auto-night-reset",
            "-setup_completed_v2", "YES", "-healthkit_enabled", "NO", "-whoop_enabled", "NO",
            "-notifications_enabled", "NO", "-morningCheckIn.rememberSettings", "NO",
            "-preSleepLog.rememberLastSettings", "NO", "-reduced_motion", largeText ? "YES" : "NO",
            "-AppleLocale", "en_US", "-AppleLanguages", "(en)", "-UIPreferredContentSizeCategoryName",
            largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        if failSave { app.launchArguments.append("--uitesting-morning-save-failure") }
        app.launch()
    }

    private func morning(largeText: Bool, failSave: Bool = false) throws {
        launch(largeText: largeText, morning: true, failSave: failSave)
        let finish = app.buttons["Finish"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 15)); finish.tap()
        let submit = app.buttons["morning-check-in-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertTrue(submit.isHittable, "Completion must be reachable before scrolling")
        capture("Morning initial completion control")
        let mild = app.buttons["morning-grogginess-Mild"]
        let severe = app.buttons["morning-grogginess-Severe"]
        try reveal(mild); mild.tap(); assertSelected(mild, true)
        try reveal(severe); severe.tap(); assertSelected(severe, true)
        try reveal(mild, upward: true); assertSelected(mild, false)
        for (identifier, label, initial) in [("morning-mental-clarity", "Mental clarity", 5),
            ("morning-readiness-for-day", "Readiness for the day", 3),
            ("morning-driving-confidence", "Driving confidence", 3),
            ("morning-daytime-sleepiness", "Daytime sleepiness", 3)] {
            if identifier == "morning-driving-confidence" {
                let work = app.switches["Add work / safety context"].firstMatch
                try reveal(work)
                if work.value as? String != "1" { work.tap() }
            }
            let slider = app.sliders[identifier]
            try reveal(slider)
            XCTAssertEqual(slider.label, label)
            XCTAssertEqual(slider.value as? String, "\(initial) out of 5")
            slider.adjust(toNormalizedSliderPosition: 0)
            assertValue(slider, "1 out of 5")
            slider.adjust(toNormalizedSliderPosition: 1)
            assertValue(slider, "5 out of 5")
        }
        capture("Distinct accessible morning sliders")
        let notes = app.descendants(matching: .any).matching(identifier: "morning-check-in-notes").firstMatch
        try reveal(notes); notes.tap(); notes.typeText("Questionnaire accessibility check")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(submit.isHittable, "Completion must remain reachable above the keyboard")
        XCTAssertLessThanOrEqual(submit.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        capture("Morning completion with notes keyboard")
        submit.tap()
        if failSave {
            let error = app.descendants(matching: .any).matching(identifier: "morning-check-in-storage-error").firstMatch
            XCTAssertTrue(error.waitForExistence(timeout: 10))
            XCTAssertTrue(submit.isHittable)
            XCTAssertLessThanOrEqual(submit.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
            capture("Failed save keeps completion reachable")
            let status = app.scrollViews["morning-check-in-status"]
            XCTAssertTrue(status.isHittable)
            status.swipeUp()
            capture("Full failure message scrolls above completion")
            XCTAssertTrue(submit.isEnabled)
            try reveal(notes)
            XCTAssertEqual(notes.value as? String, "Questionnaire accessibility check")
            return
        }
        XCTAssertTrue(app.buttons["dose-primary-action"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Morning Check-In"].exists)
    }

    private func bedtime(largeText: Bool) throws {
        launch(largeText: largeText, morning: false)
        try openBedtime()
        let now = app.buttons["questionnaire-option-IntendedSleepTime-now"]
        let soon = app.buttons["questionnaire-option-IntendedSleepTime-15min"]
        try reveal(now); now.tap(); assertSelected(now, true)
        try reveal(soon); soon.tap(); assertSelected(soon, true)
        try reveal(now, upward: true); assertSelected(now, false)
        let low = app.buttons["questionnaire-stress-1"]
        let high = app.buttons["questionnaire-stress-5"]
        try reveal(low); low.tap(); assertSelected(low, true)
        try reveal(high); high.tap(); assertSelected(high, true)
        try reveal(low, upward: true); assertSelected(low, false)
        let work = app.buttons["questionnaire-multi-CommonStressDriver-work"]
        let family = app.buttons["questionnaire-multi-CommonStressDriver-family"]
        try reveal(work); work.tap(); assertSelected(work, true)
        try reveal(family); family.tap(); assertSelected(family, true)
        try reveal(work, upward: true); work.tap(); assertSelected(work, false)
        try reveal(family); assertSelected(family, true)
        capture("Bedtime selected and deselected choices")
        app.buttons["pre-sleep-next"].tap()
        XCTAssertTrue(app.staticTexts["Card 2 of 3"].waitForExistence(timeout: 5))
        app.buttons["pre-sleep-back"].tap()
        XCTAssertTrue(app.staticTexts["Card 1 of 3"].waitForExistence(timeout: 5))
        try reveal(soon, upward: true); assertSelected(soon, true)
        try reveal(high); assertSelected(high, true)
        try reveal(family); assertSelected(family, true)
        try reveal(work, upward: true); assertSelected(work, false)
        app.buttons["Use room setup"].tap()
        XCTAssertTrue(app.staticTexts["Card 3 of 3"].waitForExistence(timeout: 5))
        capture("Bedtime setup navigation retains draft")
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.isHittable); done.tap()
        try openBedtime()
        XCTAssertTrue(app.navigationBars["Edit Pre-Sleep"].waitForExistence(timeout: 5))
        try reveal(soon); assertSelected(soon, true)
        try reveal(now, upward: true); assertSelected(now, false)
        try reveal(high); assertSelected(high, true)
        try reveal(work); assertSelected(work, false)
        try reveal(family); assertSelected(family, true)
        capture("Saved bedtime choices reopened")
        app.buttons["Cancel"].tap()
        // Retention and navigation assertions do not establish absence of visible motion.
    }

    private func openBedtime() throws {
        let check = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pre-sleep")).firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 15))
        try reveal(check); check.tap()
        XCTAssertTrue(app.staticTexts["Card 1 of 3"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, upward: Bool = false) throws {
        for _ in 0..<35 {
            let morningScroll = app.scrollViews["morning-check-in-scroll"]
            let bedtimeScroll = app.scrollViews["pre-sleep-timing-scroll"]
            let scroll = morningScroll.exists ? morningScroll : (bedtimeScroll.exists ? bedtimeScroll : app.scrollViews.firstMatch)
            let viewport = (scroll.exists ? scroll.frame : app.frame).intersection(app.frame)
            let footer = app.buttons["morning-check-in-submit"]
            let bottom = footer.exists ? min(viewport.maxY, footer.frame.minY) : viewport.maxY
            let top = max(viewport.minY, app.frame.minY + 100)
            let height = bottom - top
            // A partially clipped slider can be hittable while its thumb cannot be dragged.
            if element.exists && element.isHittable && (element.elementType != .slider ||
                (element.frame.minY >= top + 8 && element.frame.maxY <= bottom - 8)) { return }
            guard height > 60 else { break }
            let towardTop = element.exists && !element.frame.isEmpty ? element.frame.midY < top + height / 2 : upward
            let x = viewport.midX - app.frame.minX
            let startY = top + height * (towardTop ? 0.25 : 0.8) - app.frame.minY
            let endY = top + height * (towardTop ? 0.8 : 0.25) - app.frame.minY
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x, dy: startY)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY)))
        }
        _ = try XCTUnwrap(element.exists && element.isHittable ? element : nil,
                          "Could not reveal \(element.identifier) within 35 scrolls")
    }

    private func assertSelected(_ element: XCUIElement, _ selected: Bool) {
        let predicate = NSPredicate { _, _ in element.isSelected == selected }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, "\(element.identifier): \(element.value ?? "nil")")
    }

    private func assertValue(_ element: XCUIElement, _ value: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, "\(element.identifier): \(element.value ?? "nil")")
    }

    private func capture(_ name: String) {
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "\(self.name): \(name)"
        proof.lifetime = .keepAlways
        add(proof)
    }
}
