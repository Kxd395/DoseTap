import XCTest

/// Synthetic repository and provider evidence only; never authorizes a physical-device gate.
final class DosePatternDashboardUITests: XCTestCase {
    func testModesExactSelectionAndIndependentCountReview() throws {
        try runJourney(largeText: false)
    }
    func testLargestTextModesExactSelectionAndIndependentCountReview() throws {
        try runJourney(largeText: true)
    }
    private func runJourney(largeText: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-dashboard-provider-match-uitest", "-setup_completed_v2", "YES"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let dashboard = app.buttons["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 15)); dashboard.tap()
        let open = app.buttons["dashboard-dose-pattern-open"]
        reveal(open, in: app); XCTAssertTrue(open.isHittable); open.tap()
        let modes = app.descendants(matching: .any)["dose-pattern-mode"].firstMatch
        XCTAssertTrue(modes.waitForExistence(timeout: 10))
        for title in ["Compare", "Paired intervals", "By date"] {
            if largeText { modes.tap(); app.buttons[title].tap() }
            else { modes.buttons[title].tap(); XCTAssertTrue(modes.buttons[title].isSelected) }
        }
        let table = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "All observations and exact values")).firstMatch
        reveal(table, in: app); XCTAssertTrue(table.isHittable); table.tap()
        let row = app.buttons["dose-pattern-row-session:association-ui-session"]
        reveal(row, in: app); XCTAssertTrue(row.isHittable); row.tap()
        XCTAssertTrue(app.navigationBars["Observation detail"].waitForExistence(timeout: 5))
        let review = app.buttons["dose-pattern-review"]
        reveal(review, in: app); XCTAssertTrue(review.isHittable); review.tap()
        let count = app.descendants(matching: .any)["dose-review-count"].firstMatch
        capture(app, "Dose history review before revealing count")
        reveal(count, in: app)
        XCTAssertTrue(count.waitForExistence(timeout: 5)); count.tap()
        let one = app.buttons["One — complete report"]
        XCTAssertTrue(one.waitForExistence(timeout: 5)); one.tap()
        let save = app.buttons["dose-review-save"]
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.navigationBars["Observation detail"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["dose-review-error"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "One dose confirmed, plan unknown")).firstMatch.waitForExistence(timeout: 10))
        capture(app, "Exact session review reports count without creating a second administration")
        let done = app.buttons["Done"]; XCTAssertTrue(done.isHittable); done.tap()
        let partial = app.switches["dose-pattern-include-partial"]
        for _ in 0..<8 where !partial.isHittable { app.swipeDown() }
        XCTAssertTrue(partial.isHittable); partial.tap()
        XCTAssertEqual(partial.value as? String, "1")
        capture(app, "Dose-pattern modes and explicit partial-summary inclusion")
        app.terminate()
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
