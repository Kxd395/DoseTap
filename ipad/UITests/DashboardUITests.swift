import XCTest
import DoseCore

final class DashboardUITests: XCTestCase {
    func testNativeOverviewMedicationAndConnection() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["DOSETAP_DASHBOARD_UI_FIXTURE"] = try fixture().base64EncodedString()
        app.launch()
        XCTAssertTrue(app.staticTexts["Median recorded spacing"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["3h 0m"].firstMatch.exists)
        capture("Native iPad overview")
        app.buttons["Medications"].tap()
        XCTAssertTrue(app.staticTexts["SYNTHETIC medication · 15 mg"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Stored creation (may be import time)")).firstMatch.exists)
        capture("Native iPad medication history")
        app.textFields["medication-filter"].tap(); app.textFields["medication-filter"].typeText("not-present")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "0 of 1 records")).firstMatch.exists)
        app.buttons["Night review"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "night-review-")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Night detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reported administration times"].exists)
        capture("Native iPad night detail")
        app.buttons["Done"].tap()
        app.buttons["Report contents"].tap()
        XCTAssertTrue(app.staticTexts["What arrived from your iPhone"].waitForExistence(timeout: 5))
        capture("Native iPad report contents")
        app.buttons["Connection"].tap()
        XCTAssertTrue(app.buttons["Find my iPhone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Forget downloaded report"].exists)
        capture("Native iPad connection")
    }
    func testLargestTextKeepsReportAndConnectionReachable() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["DOSETAP_DASHBOARD_UI_FIXTURE"] = try fixture().base64EncodedString()
        app.launch()
        XCTAssertTrue(app.buttons["Medications"].waitForExistence(timeout: 10))
        capture("Native iPad largest text overview")
        app.buttons["Medications"].tap()
        XCTAssertTrue(app.staticTexts["SYNTHETIC medication · 15 mg"].waitForExistence(timeout: 5))
        capture("Native iPad largest text medication")
        app.buttons["Connection"].tap()
        for _ in 0..<4 where !app.buttons["Forget downloaded report"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["Forget downloaded report"].isHittable)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func fixture() throws -> Data {
        let now = Date(), start = now.addingTimeInterval(-86400)
        let iso = ISO8601DateFormatter()
        let date = String(iso.string(from: start).prefix(10))
        func text(_ value: String) -> [String: Any] { ["type": "text", "text": value] }
        func row(_ id: String, _ type: String, _ time: Date) -> [String: Any] {
            ["sourceTable": "dose_events", "columns": ["id": text(id), "event_type": text(type), "timestamp": text(iso.string(from: time)), "session_id": text("sample"), "session_date": text(date)]]
        }
        let doses = try JSONSerialization.data(withJSONObject: [row("a", "dose1", start), row("b", "dose2", start.addingTimeInterval(10800))])
        let medications = try JSONSerialization.data(withJSONObject: [["sourceTable": "medication_events", "columns": ["id": text("sample"), "medication_id": text("SYNTHETIC medication"), "dose_mg": ["type": "integer", "integer": 15], "dose_unit": text("mg"), "taken_at_utc": text(iso.string(from: start)), "created_at": text(iso.string(from: now)), "local_offset_minutes": ["type": "integer", "integer": -240]]]])
        let sections = DashboardDataset.allCases.map { dataset in
            DashboardSnapshotSection(dataset: dataset, rows: dataset == .doseEvents ? doses : dataset == .medicationEntries ? medications : Data("[]".utf8), rowCount: dataset == .doseEvents ? 2 : dataset == .medicationEntries ? 1 : 0)
        }
        return try JSONEncoder().encode(CloudDashboardSnapshot(sourceID: "synthetic-ui", sequence: 1, capturedAt: now, sections: sections))
    }
}
