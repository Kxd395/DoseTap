import XCTest

final class ContextMorningOutcomesUITests: XCTestCase {
    @MainActor func testContextRouteSelection() { journey(large: false) }
    @MainActor func testContextRouteLargeText() { journey(large: true) }
    @MainActor private func journey(large: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-dashboard", "-setup_completed_v2", "YES", "-healthkit_enabled", "NO", "-whoop_enabled", "NO"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let dashboard = app.buttons["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 15)); dashboard.tap()
        let route = app.buttons["dashboard-context-open"]
        for _ in 0..<8 where !route.isHittable { app.swipeUp() }
        XCTAssertTrue(route.waitForExistence(timeout: 5)); route.tap()
        let outcome = app.buttons["context-outcome"]
        for _ in 0..<5 where !outcome.isHittable { app.swipeUp() }
        XCTAssertTrue(outcome.exists); outcome.tap()
        app.buttons["D1–D2 spacing"].tap()
        let next = app.buttons["Next observation"]
        for _ in 0..<12 {
            if next.isHittable && next.frame.maxY < app.frame.maxY - 110 { break }
            app.swipeUp()
        }
        XCTAssertTrue(next.isHittable); next.tap()
        let detail = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Selected:")).firstMatch
        for _ in 0..<8 where !detail.isHittable { app.swipeUp() }
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }
}
