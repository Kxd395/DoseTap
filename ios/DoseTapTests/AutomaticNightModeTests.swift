import XCTest
@testable import DoseTap

@MainActor
final class AutomaticNightModeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        suite = "AutomaticNightModeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    private func reconcile(_ manager: ThemeManager, id: String? = "night-a", dose: Bool = true,
                           elapsed: TimeInterval = 1, woke: Bool = false) {
        manager.refreshAutomaticNight(sessionID: id, dose1: dose ? start : nil,
            wakeBy: start.addingTimeInterval(8 * 3600), wokeUp: woke,
            now: start.addingTimeInterval(elapsed))
    }

    func testCommittedDoseStartsNightAndExactWakeRestoresPreference() {
        let manager = ThemeManager(defaults: defaults)
        manager.applyTheme(.light)
        reconcile(manager, dose: false)
        XCTAssertEqual(manager.currentTheme, .light)
        reconcile(manager)
        XCTAssertEqual(manager.currentTheme, .night)
        XCTAssertTrue(manager.isAutomaticNightActive)
        XCTAssertEqual(defaults.string(forKey: "selectedTheme"), AppTheme.light.rawValue)
        reconcile(manager, elapsed: 8 * 3600 - 0.001)
        XCTAssertEqual(manager.currentTheme, .night)
        reconcile(manager, elapsed: 8 * 3600)
        XCTAssertEqual(manager.currentTheme, .light)
    }

    func testUndoClosureFinalWakeAndFutureDoseDoNotLeaveAutomaticNightOn() {
        let manager = ThemeManager(defaults: defaults)
        reconcile(manager)
        reconcile(manager, dose: false)
        XCTAssertEqual(manager.currentTheme, .dark)
        reconcile(manager)
        reconcile(manager, id: nil)
        XCTAssertEqual(manager.currentTheme, .dark)
        reconcile(manager)
        reconcile(manager, woke: true)
        XCTAssertEqual(manager.currentTheme, .dark)
        reconcile(manager, elapsed: -1)
        XCTAssertEqual(manager.currentTheme, .dark)
    }

    func testRestartReconstructsNightAndRestoresAfterWake() {
        let first = ThemeManager(defaults: defaults)
        first.applyTheme(.light)
        reconcile(first)
        let restarted = ThemeManager(defaults: defaults)
        reconcile(restarted)
        XCTAssertEqual(restarted.currentTheme, .night)
        let afterWake = ThemeManager(defaults: defaults)
        reconcile(afterWake, elapsed: 9 * 3600)
        XCTAssertEqual(afterWake.currentTheme, .light)
    }

    func testFinalWakeStaysOutOfAutomaticNightAfterRestart() {
        let manager = ThemeManager(defaults: defaults)
        reconcile(manager)
        reconcile(manager, woke: true)
        let restarted = ThemeManager(defaults: defaults)
        reconcile(restarted)
        XCTAssertEqual(restarted.currentTheme, .dark)
        reconcile(restarted, id: "night-b")
        XCTAssertEqual(restarted.currentTheme, .night)
    }

    func testManualOverrideSurvivesRestartButNotNextSession() {
        let manager = ThemeManager(defaults: defaults)
        reconcile(manager)
        manager.applyTheme(.dark)
        reconcile(manager)
        XCTAssertEqual(manager.currentTheme, .dark)
        let restarted = ThemeManager(defaults: defaults)
        reconcile(restarted)
        XCTAssertEqual(restarted.currentTheme, .dark)
        reconcile(restarted, id: "night-b")
        XCTAssertEqual(restarted.currentTheme, .night)
    }

    func testOptOutPersistsAndReenableResumesCurrentNight() {
        let manager = ThemeManager(defaults: defaults)
        reconcile(manager)
        manager.automaticNightModeEnabled = false
        XCTAssertEqual(manager.currentTheme, .dark)
        let restarted = ThemeManager(defaults: defaults)
        reconcile(restarted)
        XCTAssertEqual(restarted.currentTheme, .dark)
        restarted.automaticNightModeEnabled = true
        XCTAssertEqual(restarted.currentTheme, .night)
    }

    func testChangedWakeDeadlineAndManualNightPreference() {
        let manager = ThemeManager(defaults: defaults)
        reconcile(manager)
        manager.refreshAutomaticNight(sessionID: "night-a", dose1: start,
            wakeBy: start, wokeUp: false, now: start.addingTimeInterval(1))
        XCTAssertEqual(manager.currentTheme, .dark)
        manager.applyTheme(.night)
        reconcile(manager, elapsed: 9 * 3600)
        XCTAssertEqual(manager.currentTheme, .night, "Manual Night Mode remains a valid saved preference")
        XCTAssertFalse(manager.isAutomaticNightActive)
    }
}
