import XCTest

extension DaytimePromptUITests {
    func testHistoricalDaytimeCorrectionAtNormalText() throws {
        try verifyHistoricalCorrection(size: "UICTContentSizeCategoryL")
    }
    func testHistoricalDaytimeCorrectionAtLargestText() throws {
        try verifyHistoricalCorrection(size: "UICTContentSizeCategoryAccessibilityXXXL")
    }
    private func verifyHistoricalCorrection(size: String) throws {
        let app = XCUIApplication(), id = "00000000-0000-4000-8000-000000000107"
        app.launchEnvironment["DOSETAP_DAYTIME_TEST_ID"] = UUID().uuidString
        app.launchArguments = ["--uitesting", "--uitesting-daytime-correction", "-setup_completed_v2", "YES",
                               "-healthkit_enabled", "NO", "-whoop_enabled", "NO", "-AppleLocale", "en_US",
                               "-AppleLanguages", "(en)", "-UIPreferredContentSizeCategoryName", size]
        app.launch()
        func reveal(_ element: XCUIElement, towardTopIfAbsent: Bool = false) throws {
            for _ in 0..<30 {
                if element.exists && element.isHittable { return }
                let towardTop = element.exists && !element.frame.isEmpty ? element.frame.midY < app.frame.midY : towardTopIfAbsent
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.35 : 0.7))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.7 : 0.35))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            _ = try XCTUnwrap(element.exists && element.isHittable ? element : nil,
                              "Could not reveal \(element.identifier) within 30 scrolls")
        }
        func openDiary() throws {
            let history = app.buttons["History"].firstMatch
            XCTAssertTrue(history.waitForExistence(timeout: 15)); history.tap()
            let diary = app.buttons["history-daytime"]
            XCTAssertTrue(diary.waitForExistence(timeout: 10)); try reveal(diary); diary.tap()
        }
        func capture(_ name: String) {
            let proof = XCTAttachment(screenshot: app.screenshot())
            proof.name = "\(name) \(size)"; proof.lifetime = .keepAlways; add(proof)
        }
        let question = app.staticTexts["daytime-rating-question"]
        let context = app.staticTexts["daytime-correction-context"]
        let record = app.buttons["tonight-daytime-record"]
        XCTAssertTrue(record.waitForExistence(timeout: 15)); try reveal(record); record.tap()
        XCTAssertTrue(question.waitForExistence(timeout: 10)); try reveal(question)
        XCTAssertEqual(question.label.lowercased(), "how sleepy do you feel now?")
        XCTAssertFalse(context.exists)
        XCTAssertEqual(app.staticTexts["daytime-rating-summary"].label, "Choose a rating")
        capture("New daytime observation")
        app.buttons["Cancel"].tap()
        try openDiary()
        let row = app.staticTexts["daytime-saved-observation-\(id)"]
        try reveal(row) // List virtualizes historical rows at accessibility text sizes.
        let originalTime = row.label
        XCTAssertTrue(originalTime.contains("2023"))
        let correct = app.buttons["daytime-correct-\(id)"]
        try reveal(correct); correct.tap()
        XCTAssertTrue(question.waitForExistence(timeout: 10)); try reveal(question)
        XCTAssertEqual(question.label.lowercased(), "how sleepy did you feel then?")
        try reveal(context)
        let originalContext = context.label
        for evidence in ["2023", "5:13", "America/New_York"] { XCTAssertTrue(originalContext.contains(evidence), originalContext) }
        capture("Historical correction context")
        let summary = app.staticTexts["daytime-rating-summary"]
        try reveal(summary); XCTAssertEqual(summary.label, "Your rating: 3/10")
        let rating = app.buttons["daytime-rating-7"]
        try reveal(rating); rating.tap()
        let guidance = app.staticTexts["Update this response and add a reason before saving."]
        try reveal(guidance)
        try reveal(app.buttons["Save correction"])
        let reason = app.textFields["daytime-correction-reason"]
        try reveal(reason); reason.tap(); reason.typeText("Corrected my earlier rating")
        let save = app.buttons["daytime-save-top"]
        XCTAssertTrue(save.isHittable); save.tap()
        try reveal(row, towardTopIfAbsent: true) // Return above the correction button in the virtualized list.
        XCTAssertEqual(row.label, originalTime)
        let correctedScore = app.staticTexts["Custom sleepiness: 7/10"]
        try reveal(correctedScore); capture("Saved historical correction")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-daytime-correction" }
        app.launch()
        try openDiary()
        try reveal(row) // List virtualizes historical rows at accessibility text sizes.
        XCTAssertEqual(row.label, originalTime, "Correction must retain the original observation time after relaunch")
        try reveal(correctedScore)
        try reveal(correct); correct.tap()
        XCTAssertTrue(question.waitForExistence(timeout: 10)); try reveal(question)
        XCTAssertEqual(question.label.lowercased(), "how sleepy did you feel then?")
        try reveal(context); XCTAssertEqual(context.label, originalContext)
        capture("Historical correction after relaunch")
        try reveal(summary); XCTAssertEqual(summary.label, "Your rating: 7/10")
        app.buttons["Cancel"].tap()
    }
}

final class DaytimePromptUITests: XCTestCase {
    func testSleepEvidenceSectionAtNormalText() throws {
        try verifySleepEvidenceSection(size: "UICTContentSizeCategoryL")
    }
    func testSleepEvidenceSectionAtLargestText() throws {
        try verifySleepEvidenceSection(size: "UICTContentSizeCategoryAccessibilityXXXL")
    }
    private func verifySleepEvidenceSection(size: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-daytime-sleep-reasons", "-setup_completed_v2", "YES",
                               "-healthkit_enabled", "NO", "-whoop_enabled", "NO", "-AppleLocale", "en_US", "-AppleLanguages", "(en)",
                               "-UIPreferredContentSizeCategoryName", size]
        app.launch()
        // This fixture renders the production section; it does not exercise scheduling or storage.
        let rows = [
            ("activeDoseSession", "Night session remains open", "Dose 1:", "This session has no recorded Wake Up action or completed morning check-in."),
            ("nap", "Nap start without a later nap end", "Nap start:", "No later nap end is recorded."),
            ("mainSleep", "Lights out without a later final wake", "Lights out:", "No later final wake is recorded.")
        ]
        func reveal(_ element: XCUIElement) {
            for _ in 0..<20 {
                if element.exists && element.isHittable { return }
                let towardTop = element.exists && element.frame.midY < app.frame.midY
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.35 : 0.7))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.7 : 0.35))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTAssertTrue(element.exists); XCTAssertTrue(element.isHittable)
        }
        func assertTimestamp(_ element: XCUIElement) {
            XCTAssertTrue(element.label.contains("2023"), element.label)
            XCTAssertNotNil(element.label.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression), element.label)
            let proof = XCTAttachment(screenshot: app.screenshot())
            proof.name = "Sleep evidence \(element.identifier) \(size)"; proof.lifetime = .keepAlways; add(proof)
        }
        XCTAssertTrue(app.staticTexts["daytime-sleep-reason-activeDoseSession"].waitForExistence(timeout: 15))
        for (kind, title, prefix, detail) in rows {
            let row = app.staticTexts["daytime-sleep-reason-\(kind)"]
            reveal(row)
            XCTAssertTrue(row.label.contains(title)); XCTAssertTrue(row.label.contains(prefix))
            XCTAssertTrue(row.label.contains(detail))
            assertTimestamp(row)
        }
        let checked = app.staticTexts["daytime-sleep-evidence-checked"]
        reveal(checked); assertTimestamp(checked)
        XCTAssertTrue(checked.label.contains("Sleep records checked:"))
    }
    func testOptionalReminderControlsAtLargestText() throws {
        try verifyReminderStatus(size: "UICTContentSizeCategoryAccessibilityXXXL")
    }
    func testOptionalReminderStatusAtNormalText() throws {
        try verifyReminderStatus(size: "UICTContentSizeCategoryL")
    }
    private func verifyReminderStatus(size: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-auto-night-reset", "-setup_completed_v2", "YES",
                               "-healthkit_enabled", "NO", "-whoop_enabled", "NO",
                               "-UIPreferredContentSizeCategoryName", size]
        app.launch()
        func reveal(_ element: XCUIElement, towardTop: Bool = false) {
            for _ in 0..<20 {
                if element.exists && element.isHittable { return }
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.35 : 0.7))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.7 : 0.35))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTAssertTrue(element.exists); XCTAssertTrue(element.isHittable)
        }
        let link = app.buttons["tonight-daytime-reminder"]
        XCTAssertTrue(link.waitForExistence(timeout: 15)); reveal(link)
        XCTAssertTrue(link.isHittable); link.tap()
        let status = app.staticTexts["daytime-reminder-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Reminders paused")
        XCTAssertFalse(app.staticTexts["daytime-next-reminder"].exists)
        let checked = app.staticTexts["daytime-reminder-last-checked"]
        reveal(checked)
        XCTAssertTrue(checked.label.contains("Last checked:"))
        let toggle = app.switches["Enable daytime reminder"]
        reveal(toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        let save = app.buttons["daytime-reminder-save-top"]
        if size == "UICTContentSizeCategoryL" {
            let control = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
            control.tap()
            XCTAssertEqual(toggle.value as? String, "1")
            let refresh = app.buttons["Retry / refresh status"]
            reveal(refresh, towardTop: true); refresh.tap()
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            XCTAssertEqual(status.label, "Reminders paused")
            reveal(toggle)
            XCTAssertEqual(toggle.value as? String, "1", "Refresh must preserve the unsaved draft")
            control.tap()
        }
        let varied = app.switches["daytime-randomized"]
        reveal(varied)
        let variedControl = varied.switches.firstMatch.exists ? varied.switches.firstMatch : varied
        if varied.value as? String == "0" { variedControl.tap() }
        reveal(app.staticTexts["Workdays: 3 check-ins, 2–4, 6–9 and 11–13 hours after waking."])
        reveal(app.staticTexts["Off days: 2 check-ins, 3–5 and 8–10 hours after waking."])
        XCTAssertTrue(save.isHittable); save.tap()
        reveal(status, towardTop: true)
        XCTAssertEqual(status.label, "Reminders paused")
        XCTAssertFalse(app.staticTexts["daytime-next-reminder"].exists)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Optional daytime reminder status \(size)"; proof.lifetime = .keepAlways; add(proof)
    }
}


extension DaytimePromptUITests {
    func testClearAllFailureRetainsDaytimeRowsAtNormalText() throws {
        try verifyClearAllFailure(size: "UICTContentSizeCategoryL")
    }
    func testClearAllFailureRetainsDaytimeRowsAtLargestText() throws {
        try verifyClearAllFailure(size: "UICTContentSizeCategoryAccessibilityXXXL")
    }
    private func verifyClearAllFailure(size: String) throws {
        let app = XCUIApplication()
        app.launchEnvironment["DOSETAP_DAYTIME_TEST_ID"] = UUID().uuidString
        app.launchArguments = ["--uitesting", "--uitesting-daytime-overlap", "--uitesting-reset-delete-failure",
                               "-setup_completed_v2", "YES", "-healthkit_enabled", "NO", "-whoop_enabled", "NO",
                               "-AppleLocale", "en_US", "-AppleLanguages", "(en)", "-UIPreferredContentSizeCategoryName", size]
        app.launch()
        func reveal(_ element: XCUIElement) throws {
            for _ in 0..<40 {
                if element.exists && element.isHittable { return }
                let towardTop = element.exists && !element.frame.isEmpty && element.frame.midY < app.frame.midY
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.35 : 0.7))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.7 : 0.35))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            _ = try XCTUnwrap(element.exists && element.isHittable ? element : nil,
                              "Could not reveal \(element.identifier) within 40 scrolls")
        }
        func originalRows() throws -> [String] {
            let history = app.buttons["History"].firstMatch
            XCTAssertTrue(history.waitForExistence(timeout: 15)); history.tap()
            let diary = app.buttons["history-daytime"]
            XCTAssertTrue(diary.waitForExistence(timeout: 10)); try reveal(diary); diary.tap()
            return try ["00000000-0000-4000-8000-000000000002", "00000000-0000-4000-8000-000000000001"].map { id in
                let row = app.staticTexts["daytime-saved-observation-\(id)"]
                try reveal(row); return row.label
            }
        }
        let before = try originalRows()
        XCTAssertEqual(before.count, 2)
        app.buttons["Settings"].firstMatch.tap()
        let clear = app.buttons["Clear All Data"]
        try reveal(clear); clear.tap()
        let confirmation = app.alerts["Clear All Data"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let disclosure = confirmation.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        for retained in ["exported files", "credentials", "Apple Health/WHOOP records", "retained"] {
            XCTAssertTrue(disclosure.contains(retained), disclosure)
        }
        let confirm = confirmation.buttons["Clear All"]
        try reveal(confirm); confirm.tap()
        let failure = app.alerts["Reset Status"]
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        XCTAssertTrue(failure.staticTexts["Your local records could not be cleared. Your session and settings were not reset. Please try again."].exists)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Clear All rollback retains daytime records \(size)"; proof.lifetime = .keepAlways; add(proof)
        let dismiss = failure.buttons["OK"]
        try reveal(dismiss); dismiss.tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-daytime-overlap" }
        app.launch()
        XCTAssertEqual(try originalRows(), before, "Both original observations must survive without reseeding")
    }
}
