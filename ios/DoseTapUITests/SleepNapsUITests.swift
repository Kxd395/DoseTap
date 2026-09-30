import XCTest
final class SleepNapsUITests: XCTestCase {
    private let app = XCUIApplication()
    private func launch(largeText: Bool, reset: Bool, fixture: Bool = true, interval: Bool = false, navigation: Bool = false) {
        app.launchArguments = ["--uitesting", "-setup_completed_v2", "YES", "-healthkit_enabled", "NO", "-whoop_enabled", "NO"]
        if fixture { app.launchArguments.append("--uitesting-sleep-naps") }
        if reset { app.launchArguments.append("--uitesting-nap-reset") }
        if interval { app.launchArguments.append("--uitesting-nap-interval") }
        if navigation { app.launchArguments.append("--uitesting-nap-navigation") }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<24 {
            if element.exists && element.isHittable && element.frame.midY < app.frame.maxY - 40 && element.frame.midY > 120 { return }
            let down = !element.exists || element.frame.midY > app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.55 : 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.30 : 0.60))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Nap control visibility failure"; attachment.lifetime = .keepAlways; add(attachment)
        XCTFail("Control unavailable: \(element)")
    }
    private func revealSelectionAtTop(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.midY > 120 && element.frame.midY < app.frame.maxY - 40 { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).press(forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        }
        XCTFail("Selected nap identity unavailable after returning to top")
    }
    private func setOn(_ identifier: String) {
        let control = app.switches[identifier]; reveal(control)
        if control.value as? String != "1" { control.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        XCTAssertEqual(control.value as? String, "1")
    }
    func testExplicitDurationOnlyReviewPersistsAcrossRestart() { journey(largeText: false) }
    func testExplicitDurationOnlyReviewAtLargestText() { journey(largeText: true) }
    func testActualNapEndRequiresExplicitDoseOccurrence() {
        continueAfterFailure = false
        launch(largeText: false, reset: true, interval: true)
        let record = app.buttons["nap-record-synthetic-nap-ended"]; reveal(record); record.tap()
        let unselected = app.staticTexts["No explicit endpoint pair selected."]; reveal(unselected); XCTAssertTrue(unselected.exists)
        XCTAssertFalse(app.staticTexts["nap-dose-interval"].exists)
        let choice = app.buttons["nap-dose-choice"]; reveal(choice); choice.tap()
        let dose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Dose 1 ·")).firstMatch
        XCTAssertTrue(dose.waitForExistence(timeout: 5)); dose.tap()
        let interval = app.staticTexts["nap-dose-interval"]; reveal(interval); XCTAssertEqual(interval.label, "45.0 elapsed minutes")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Explicit actual nap end and dose occurrence"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testExactNapSelectionSurvivesRouteBackAndRefresh() {
        continueAfterFailure = false
        launch(largeText: false, reset: true, interval: true, navigation: true)
        let open = app.buttons["nap-fixture-open"]; XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        let record = app.buttons["nap-record-synthetic-nap-ended"]; reveal(record); record.tap()
        let selected = app.staticTexts["nap-selected-id"]; revealSelectionAtTop(selected)
        XCTAssertEqual(selected.label, "Selected nap: synthetic-nap-ended")
        app.navigationBars.buttons["Dashboard fixture"].tap()
        let refresh = app.buttons["nap-fixture-refresh"]; XCTAssertTrue(refresh.waitForExistence(timeout: 5)); refresh.tap()
        XCTAssertTrue(app.staticTexts["Nap refresh finished"].waitForExistence(timeout: 10))
        open.tap(); revealSelectionAtTop(selected); XCTAssertEqual(selected.label, "Selected nap: synthetic-nap-ended")
        XCTAssertFalse(app.staticTexts["nap-dose-interval"].exists, "A recreated route must not retain a stale interval/provider measurement")
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "Exact nap identity retained after route back and refresh"; proof.lifetime = .keepAlways; add(proof)
        let clear = app.buttons["nap-clear-selection"]; reveal(clear); clear.tap()
        XCTAssertFalse(selected.exists)
    }
    private func journey(largeText: Bool) {
        continueAfterFailure = false
        launch(largeText: largeText, reset: false, fixture: false)
        let dashboard = app.buttons["Dashboard"]; XCTAssertTrue(dashboard.waitForExistence(timeout: 10)); dashboard.tap()
        let route = app.buttons["dashboard-sleep-naps-open"]; reveal(route); route.tap()
        XCTAssertTrue(app.buttons["nap-add-report"].waitForExistence(timeout: 10)); app.terminate()
        launch(largeText: largeText, reset: true)
        let add = app.buttons["nap-add-report"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        let save = app.buttons["nap-save-review"]; XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertFalse(save.isEnabled)
        setOn("nap-estimate-known")
        let minutes = app.textFields["nap-estimated-minutes"]; reveal(minutes); minutes.tap(); minutes.typeText("30")
        setOn("nap-reviewed")
        XCTAssertTrue(save.isEnabled); save.tap()
        let summary = app.staticTexts["Reported asleep duration unavailable"]
        reveal(summary); XCTAssertTrue(summary.exists)
        let unknown = app.staticTexts["Clock start unknown"]; reveal(unknown); XCTAssertTrue(unknown.exists)
        XCTAssertTrue(app.staticTexts["Rest: unavailable; estimated asleep: 30.0 min"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Duration-only nap retains unknown clock position"; attachment.lifetime = .keepAlways; self.add(attachment)
        let export = app.buttons["Preview nap comparison CSV"]; reveal(export); export.tap()
        let csv = app.staticTexts["nap-export-csv"]; XCTAssertTrue(csv.waitForExistence(timeout: 5))
        let parsed = csv.label.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { $0.components(separatedBy: ",") }
        guard let header = parsed.first, let minutesColumn = header.firstIndex(of: "eligible_reported_asleep_minutes"),
              let rawColumn = header.firstIndex(of: "reported_asleep_minutes"), let startColumn = header.firstIndex(of: "start_utc"), let endColumn = header.firstIndex(of: "end_utc"),
              let summaryRow = parsed.first(where: { $0.first == "day_summary" }), let episodeRow = parsed.first(where: { $0.first == "episode" }),
              summaryRow.count > minutesColumn, episodeRow.count > max(minutesColumn, max(startColumn, endColumn)) else { XCTFail("CSV lacks exact summary/episode fields"); return }
        XCTAssertEqual(summaryRow[minutesColumn], ""); XCTAssertEqual(episodeRow[minutesColumn], "")
        XCTAssertEqual(episodeRow[rawColumn], "30.0"); for field in ["export_scope", "inspection_date", "period_start_utc", "period_end_exclusive_utc", "period_as_of_utc", "period_timezone", "night_filter_policy", "main_source_policy"] { guard let column = header.firstIndex(of: field), episodeRow.count > column else { XCTFail("Missing scope field: \(field)"); return }; XCTAssertFalse(episodeRow[column].isEmpty, field) }
        XCTAssertEqual(episodeRow[startColumn], ""); XCTAssertEqual(episodeRow[endColumn], "")
        app.terminate(); launch(largeText: largeText, reset: false)
        reveal(summary); XCTAssertTrue(summary.exists); reveal(unknown); XCTAssertTrue(unknown.exists)
    }
}
