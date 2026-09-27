import XCTest
import DoseCore

final class DashboardUITests: XCTestCase {
    func testNativeOverviewMedicationAndConnection() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchEnvironment["DOSETAP_DASHBOARD_UI_FIXTURE"] = try fixture().base64EncodedString()
        app.launch()
        XCTAssertTrue(app.staticTexts["Your nights. Your days."].waitForExistence(timeout: 10))
        capture("Native iPad review home")
        app.buttons["Dose timing"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Median recorded spacing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3h 0m"].firstMatch.exists)
        capture("Native iPad overview")
        app.buttons["Medications"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["SYNTHETIC medication · 15 mg"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Stored creation (may be import time)")).firstMatch.exists)
        capture("Native iPad medication history")
        app.textFields["medication-filter"].tap(); app.textFields["medication-filter"].typeText("not-present")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "0 of 1 records")).firstMatch.exists)
        app.buttons["Sleep & check-ins"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Recorded sleep quality"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1 dates with a usable stored rating")).firstMatch.exists)
        capture("Native iPad sleep check-ins")
        app.buttons["Wake & sleepiness"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["4h 0m"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["0 / 10"].firstMatch.exists)
        capture("Native iPad explicit diary outcomes")
        reveal("Timing and reported sleepiness", app: app)
        app.buttons["diary-comparison-picker"].tap()
        app.buttons["Elapsed to final wake"].tap()
        reveal("Matched records", app: app, button: true)
        app.buttons["Matched records"].tap()
        let matched = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "diary-matched-")).firstMatch
        XCTAssertTrue(matched.waitForExistence(timeout: 5)); matched.tap()
        XCTAssertTrue(app.navigationBars["Matched diary evidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "4h 0m 0s")).firstMatch.exists)
        capture("Native matched timing and sleepiness evidence")
        app.buttons["Done"].tap()
        reveal("Timed sleepiness observations", app: app)
        capture("Native timed sleepiness observations")
        app.buttons["Night review"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "night-review-")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Night detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reported administration times"].exists)
        capture("Native iPad night detail")
        app.buttons["Done"].tap()
        app.buttons["Report contents"].tap()
        XCTAssertTrue(app.staticTexts["What arrived from your iPhone"].waitForExistence(timeout: 5))
        capture("Native iPad report contents")
        selectSidebar("Connection", app: app)
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
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "dashboard-sidebar").firstMatch.waitForExistence(timeout: 10))
        capture("Native iPad largest text overview")
        selectSidebar("Medications", app: app)
        XCTAssertTrue(app.staticTexts["SYNTHETIC medication · 15 mg"].waitForExistence(timeout: 5))
        capture("Native iPad largest text medication")
        selectSidebar("Wake & sleepiness", app: app)
        let content = app.scrollViews["dashboard-content"]
        for _ in 0..<8 where !app.staticTexts["Dose 2 → reported final wake"].isHittable { content.swipeUp() }
        XCTAssertTrue(app.staticTexts["Dose 2 → reported final wake"].isHittable)
        capture("Native iPad largest text explicit diary")
        selectSidebar("Connection", app: app)
        for _ in 0..<4 where !app.buttons["Forget downloaded report"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["Forget downloaded report"].isHittable)
    }
    func testProviderEvidenceNativeInspection() throws { try providerJourney(largeText: false) }
    func testProviderEvidenceLargestText() throws { try providerJourney(largeText: true) }
    private func providerJourney(largeText: Bool) throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        var report = try JSONDecoder().decode(CloudDashboardSnapshot.self, from: fixture())
        let end = report.capturedAt
        let origin = SleepEvidenceSample.Origin(sourceName: "Fixture Watch", bundleIdentifier: "example.fixture")
        let samples = [
            SleepEvidenceSample(sampleID: "core-sample", start: end.addingTimeInterval(-60), end: end.addingTimeInterval(-30), rawCategory: 3, stage: .core, origin: origin),
            SleepEvidenceSample(sampleID: "awake-sample", start: end.addingTimeInterval(-30), end: end, rawCategory: 2, stage: .awake, origin: origin)
        ]
        let packet = DashboardSleepEvidence(queryStart: end.addingTimeInterval(-86400), queryEnd: end,
                                             completedAt: end, timeZoneID: "America/New_York", samples: samples)
        report.sections[report.sections.firstIndex { $0.dataset == .appleHealth }!] = try packet.section()
        app.launchEnvironment["DOSETAP_DASHBOARD_UI_FIXTURE"] = try JSONEncoder().encode(report).base64EncodedString()
        app.launch()
        XCTAssertTrue(app.buttons["Apple Health evidence"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Apple Health evidence"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["provider-sample-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["provider-sample-count"].label.contains("2 original samples"))
        capture(largeText ? "Apple Health evidence largest text" : "Apple Health evidence native stages")
        reveal("Original intervals", app: app)
        let row = app.buttons["provider-interval-awake-sample"]
        for _ in 0..<8 where !row.isHittable { app.scrollViews["dashboard-content"].swipeUp() }
        XCTAssertTrue(row.isHittable); row.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sample: awake-sample")).firstMatch.waitForExistence(timeout: 5))
        capture(largeText ? "Apple Health original sample largest text" : "Apple Health original sample provenance")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func selectSidebar(_ title: String, app: XCUIApplication) {
        let sidebar = app.descendants(matching: .any).matching(identifier: "dashboard-sidebar").firstMatch
        let button = sidebar.buttons[title].firstMatch
        for _ in 0..<5 where !button.isHittable { sidebar.swipeUp() }
        XCTAssertTrue(button.isHittable); button.tap()
    }
    private func reveal(_ title: String, app: XCUIApplication, button: Bool = false) {
        let element = button ? app.buttons[title].firstMatch : app.staticTexts[title].firstMatch
        for _ in 0..<12 where !element.isHittable { app.scrollViews["dashboard-content"].swipeUp() }
        XCTAssertTrue(element.isHittable)
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
        let morning = try JSONSerialization.data(withJSONObject: [["sourceTable": "morning_checkins", "columns": ["id": text("morning-sample"), "session_id": text("sample"), "session_date": text(date), "sleep_quality": ["type": "real", "real": 3.5]]]])
        let diary = try JSONSerialization.data(withJSONObject: ["answers": ["wakeMethod": "alarm", "dayType": "workday", "finalWakeAt": iso.string(from: start.addingTimeInterval(7 * 3600)), "sleepiness": 0, "assessedAt": iso.string(from: start.addingTimeInterval(9 * 3600))], "recordedAt": iso.string(from: now), "revisions": []])
        let outcome = try JSONSerialization.data(withJSONObject: [["sourceTable": "checkin_submissions", "columns": ["id": text("night_outcome:sample"), "source_record_id": text("sample"), "session_id": text("sample"), "session_date": text(date), "checkin_type": text("night_outcome"), "questionnaire_version": text("night_outcome.v1"), "responses_json": text(String(decoding: diary, as: UTF8.self))]]])
        let sections = DashboardDataset.allCases.map { dataset in
            DashboardSnapshotSection(dataset: dataset, rows: dataset == .doseEvents ? doses : dataset == .medicationEntries ? medications : dataset == .morning ? morning : dataset == .normalizedAnswers ? outcome : Data("[]".utf8), rowCount: dataset == .doseEvents ? 2 : (dataset == .medicationEntries || dataset == .morning || dataset == .normalizedAnswers) ? 1 : 0)
        }
        return try JSONEncoder().encode(CloudDashboardSnapshot(sourceID: "synthetic-ui", sequence: 1, capturedAt: now, sections: sections))
    }
}
