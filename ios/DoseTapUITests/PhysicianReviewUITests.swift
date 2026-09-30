import XCTest

final class PhysicianReviewUITests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "--physician-review-fixture", "-setup_completed_v2", "YES", "-healthkit_enabled", "NO", "-whoop_enabled", "NO"]
        if name.contains("LargeText") { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
    }
    private func reveal(_ element: XCUIElement, scrollingUp: Bool = true) {
        for _ in 0..<90 {
            if element.exists && element.isHittable { return }
            let up = !element.exists || element.frame.isEmpty ? scrollingUp : element.frame.midY > app.frame.midY
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.72 : 0.40)).press(forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.40 : 0.72)))
        }
        XCTFail("Report control could not be reached: \(element)")
    }
    private func enter(_ id: String, _ value: String, scrollingUp: Bool = true) {
        let field = app.descendants(matching: .any).matching(identifier: id).firstMatch
        reveal(field, scrollingUp: scrollingUp); field.tap(); field.typeText(value)
        let done = app.buttons["physician-keyboard-done"]; if done.exists { done.tap() }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testPrepareNotesImmutablePreviewAndExplicitShareCancel() { journey() }
    func testPrepareNotesLargeTextAndExplicitShareCancel() { journey() }
    private func journey() {
        let dashboard = app.buttons["Dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10)); dashboard.tap()
        let open = app.buttons["physician-review-open"]; reveal(open); open.tap()
        let period = app.buttons["physician-report-period"]; reveal(period); period.tap()
        app.buttons["28 Days"].firstMatch.tap()
        let prepare = app.buttons["physician-prepare-period"]; reveal(prepare); XCTAssertTrue(prepare.isEnabled); prepare.tap()
        let captureLabel = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Sources captured")).firstMatch
        XCTAssertTrue(captureLabel.waitForExistence(timeout: 15)); capture("Explicit 28-day source preparation")
        let visit = app.buttons["physician-save-visit"]; reveal(visit); visit.tap()
        enter("physician-note-activity", "Reading at home")
        enter("physician-note-comment", "Synthetic observation; uncertain duration")
        let add = app.buttons["physician-add-note"]; reveal(add); XCTAssertTrue(add.isEnabled); add.tap()
        enter("physician-note-activity", "Conversation after lunch", scrollingUp: false)
        enter("physician-note-comment", "Second reviewed example")
        reveal(add); add.tap()
        enter("physician-questions", "Which observations should I bring to my next visit?")
        capture("Multiple unscored visit notes and question")
        let save = app.buttons["physician-create-preview"]; reveal(save); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.navigationBars["Report preview"].waitForExistence(timeout: 10))
        capture("Immutable report overview and captured policy")
        let question = app.staticTexts["Which observations should I bring to my next visit?"].firstMatch
        reveal(question); XCTAssertTrue(question.exists); capture("Reviewed notes and question retained")
        let share = app.buttons["physician-share-report"]; share.tap()
        XCTAssertTrue(app.cells["Save to Files"].waitForExistence(timeout: 10)); capture("Explicit share sheet; no recipient selected")
        let closeShare = app.buttons["header.closeButton"]
        XCTAssertTrue(closeShare.waitForExistence(timeout: 5)); closeShare.tap()
        app.navigationBars["Report preview"].buttons["Close"].tap()
        enter("physician-questions", " Future unsaved draft question", scrollingUp: false)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "physician-saved-preview-")).firstMatch
        reveal(saved); saved.tap()
        XCTAssertTrue(app.navigationBars["Report preview"].waitForExistence(timeout: 5))
        reveal(question); XCTAssertTrue(question.exists)
        XCTAssertFalse(app.staticTexts["Which observations should I bring to my next visit? Future unsaved draft question"].exists)
        capture("Reopened immutable saved preview")
    }
}
