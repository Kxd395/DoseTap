import XCTest

final class DaytimePromptUITests: XCTestCase {
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
