import XCTest

final class DaytimePromptUITests: XCTestCase {
    func testOptionalReminderControlsAtLargestText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-auto-night-reset", "-setup_completed_v2", "YES",
                               "-healthkit_enabled", "NO", "-whoop_enabled", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        let link = app.buttons["Daytime reminder"]
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
        let toggle = app.switches["Enable daytime reminder"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "0")
        let save = app.buttons["Save reminder"]
        for _ in 0..<16 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable); save.tap()
        for _ in 0..<6 where !app.staticTexts["Reminders paused"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Reminders paused"].waitForExistence(timeout: 10))
        app.swipeUp()
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Optional daytime reminder largest text paused"; proof.lifetime = .keepAlways; add(proof)
    }
}
