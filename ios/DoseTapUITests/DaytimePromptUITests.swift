import XCTest

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
