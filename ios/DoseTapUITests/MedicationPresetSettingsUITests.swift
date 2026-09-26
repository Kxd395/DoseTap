import XCTest

final class MedicationPresetSettingsUITests: XCTestCase {
    private var app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "-setup_completed_v2", "YES", "-healthkit_enabled", "NO", "-whoop_enabled", "NO"]
        if name.contains("LargeText") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<60 {
            if element.exists && element.isHittable { return }
            var upward = true
            if element.exists && !element.frame.isEmpty {
                upward = element.frame.midY > app.frame.midY
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.70 : 0.40))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.40 : 0.70))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTFail("Missing control: \(element)")
    }
    private func enter(_ id: String, _ text: String) {
        let field = app.descendants(matching: .any).matching(identifier: id).firstMatch
        reveal(field); field.tap(); field.typeText(text)
        let done = app.buttons["preset-keyboard-done"]; if done.exists { done.tap() }
    }
    private func choose(_ id: String, _ label: String) {
        let picker = app.buttons[id]; reveal(picker); picker.tap()
        let choice = app.buttons[label].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 3)); choice.tap()
    }
    private func screenshot(_ title: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = title; a.lifetime = .keepAlways; add(a)
    }
    private func openPresets() {
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let presets = app.buttons["settings-medication-presets"]; reveal(presets); presets.tap()
    }
    func testPresetSetupCreateReviseRestart() { journey() }
    func testPresetSetupLargeText() { journey(captureOnly: true) }
    private func captureAndReopen(_ label: String) {
        let log = app.buttons["preset-log-\(label)"]; reveal(log); log.tap()
        choose("administration-time", "Time unknown")
        let review = app.buttons["administration-reviewed"]
        let priorReview = app.buttons["administration-duplicate-reviewed"]
        // SwiftUI virtualizes off-screen rows. Review candidates while scrolling past them.
        for _ in 0..<80 {
            if priorReview.exists && priorReview.isHittable && priorReview.value as? String != "Reviewed" {
                priorReview.tap(); XCTAssertEqual(priorReview.value as? String, "Reviewed")
            }
            if review.exists && review.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70)).press(forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40)))
        }
        XCTAssertTrue(review.isHittable)
        XCTAssertEqual(review.value as? String, "Not reviewed")
        review.tap()
        let save = app.buttons["administration-save"]; reveal(save)
        XCTAssertTrue(save.isEnabled)
        screenshot("Actual amount and explicit time confirmation")
        save.tap()
        let receipt = app.staticTexts["administration-receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        screenshot("Confirmed administration receipt")
        let done = app.buttons["administration-done"]; reveal(done); done.tap()
        app.terminate(); app.launch(); openPresets()
        let history = app.buttons["preset-taken-history-\(label)"]; reveal(history); history.tap()
        let details = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Actual total: 2.25 mg", "Taken · Time unknown")).firstMatch
        reveal(details); XCTAssertTrue(details.exists)
        screenshot("Administration retained after restart")
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
    private func journey(captureOnly: Bool = false) {
        let label = "UI Test " + String(Int64.max - Int64(Date().timeIntervalSince1970 * 1000))
        openPresets()
        let add = app.buttons["preset-add"]; reveal(add); add.tap()
        enter("preset-label", label); enter("preset-ingredient", "Synthetic ingredient")
        choose("preset-release", "Extended release (XR)")
        choose("preset-form", "Capsule")
        enter("preset-strength", "1.125"); enter("preset-count", "2")
        enter("preset-instructions", "Synthetic label directions")
        choose("preset-schedule", "As needed, as prescribed")
        let review = app.buttons["preset-reviewed"]
        reveal(review)
        screenshot("Preset explicit review before save")
        review.tap(); XCTAssertEqual(review.value as? String, "Reviewed")
        let save = app.buttons["preset-save"]; reveal(save)
        XCTAssertTrue(save.isEnabled); save.tap()
        let receipt = app.staticTexts["Preset saved. No medication was logged as taken."]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        screenshot("Saved preset only")
        app.buttons["preset-receipt-dismiss"].tap()
        app.terminate(); app.launch(); openPresets()
        captureAndReopen(label)
        if captureOnly { return } // This slice's large-text coverage ends after persisted capture/history.
        let revise = app.buttons["preset-revise-\(label)"]; reveal(revise); revise.tap()
        let field = app.textFields["preset-label"]
        XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap(); field.typeText(" revised")
        // At large text the long field scrolls horizontally and the tap can place the caret mid-label.
        let editedLabel = field.value as? String ?? ""
        XCTAssertNotEqual(editedLabel, label)
        XCTAssertEqual(editedLabel.replacingOccurrences(of: " revised", with: ""), label)
        let done = app.buttons["preset-keyboard-done"]; if done.exists { done.tap() }
        reveal(review); review.tap(); XCTAssertEqual(review.value as? String, "Reviewed"); reveal(save); save.tap()
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        app.buttons["preset-receipt-dismiss"].tap()
        app.terminate(); app.launch(); openPresets()
        let newName = app.staticTexts[editedLabel].firstMatch; reveal(newName)
        screenshot("Revised preset preserves prior history")
        XCTAssertTrue(newName.exists)
        let history = app.buttons["preset-history-\(editedLabel)"]; reveal(history); history.tap()
        let original = app.staticTexts[label].firstMatch; reveal(original)
        XCTAssertTrue(original.exists)
        screenshot("Original label remains in revision history")
    }
}
