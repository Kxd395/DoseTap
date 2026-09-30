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
        let picker = app.buttons["dashboard-view-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); XCTAssertTrue(picker.isHittable); picker.tap()
        let route = app.buttons["dashboard-context-open"]
        app.revealDashboardMenuItem(route)
        XCTAssertTrue(route.waitForExistence(timeout: 5)); XCTAssertTrue(route.isHittable); route.tap()
        XCTAssertTrue(picker.label.contains("Context & Morning Outcomes"))
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
        reveal(app, element: detail, captureSteps: large)
        capture(app, name: "Selected date and value")
        if large {
            let occurrence = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Occurrence:")).firstMatch
            reveal(app, element: occurrence, captureSteps: true)
            capture(app, name: "Occurrence and source qualification")
        }
        if !large {
            let retainedSelection = detail.label
            let identifiers = app.buttons["Source record identifiers"]
            for _ in 0..<8 where !identifiers.isHittable { app.swipeUp() }
            identifiers.tap()
            let identity = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Observation:")).firstMatch
            XCTAssertTrue(identity.waitForExistence(timeout: 5))
            let retainedIdentity = identity.label
            XCTAssertTrue(picker.isHittable); picker.tap()
            let inventory = app.buttons["dashboard-data-open"]
        app.revealDashboardMenuItem(inventory)
            XCTAssertTrue(inventory.waitForExistence(timeout: 5)); inventory.tap()
            XCTAssertTrue(picker.label.contains("Review Data"))
            picker.tap(); app.revealDashboardMenuItem(route); XCTAssertTrue(route.waitForExistence(timeout: 5)); XCTAssertTrue(route.isHittable); route.tap()
            XCTAssertTrue(picker.label.contains("Context & Morning Outcomes"))
            for _ in 0..<8 where !outcome.isHittable { app.swipeUp() }
            XCTAssertTrue(outcome.label.contains("D1–D2 spacing"))
            for _ in 0..<10 where !detail.isHittable { app.swipeUp() }
            XCTAssertEqual(detail.label, retainedSelection)
            for _ in 0..<8 where !identifiers.isHittable { app.swipeUp() }
            identifiers.tap()
            XCTAssertTrue(identity.waitForExistence(timeout: 5))
            XCTAssertEqual(identity.label, retainedIdentity)
            let table = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Exact observation table")).firstMatch
            for _ in 0..<10 where !table.isHittable { app.swipeUp() }
            XCTAssertTrue(table.isHittable); table.tap()
            let marker = app.staticTexts["Selected observation"]
            XCTAssertTrue(marker.waitForExistence(timeout: 5))
            reveal(app, element: marker, captureSteps: false)
            capture(app, name: "Selected exact table row")
            let chartTitle = app.staticTexts["D1–D2 spacing by reported following day"]
            reveal(app, element: chartTitle, captureSteps: false)
            capture(app, name: "Selected individual chart observation")
        }
    }
    @MainActor private func reveal(_ app: XCUIApplication, element: XCUIElement, captureSteps: Bool) {
        let top = app.frame.minY + 170, bottom = app.frame.maxY - 110
        for _ in 0..<16 {
            if element.exists && element.frame.minY >= top && element.frame.maxY <= bottom { break }
            let distance = min(200, max(60, abs(element.frame.minY - top)))
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let direction: CGFloat = element.exists && element.frame.minY < top ? 1.0 : -1.0
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * distance)))
            if captureSteps { capture(app, name: "Selected detail continuation") }
        }
        XCTAssertTrue(element.exists)
        XCTAssertGreaterThanOrEqual(element.frame.minY, top)
        XCTAssertLessThanOrEqual(element.frame.maxY, bottom)
    }
    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
