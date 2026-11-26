import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardNapInspectionTests: XCTestCase {
    private let captured = Date(timeIntervalSince1970: 1_790_794_800)
    private func model() -> DashboardAnalyticsModel {
        let queries = DashboardProviderQueries(healthEnabled: { false }, whoopEnabled: { false },
            whoopConnected: { false }, prepareHealth: { .unavailable }, healthHistory: { _ in [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        return DashboardAnalyticsModel(now: { self.captured },
            sessionRepo: SessionRepository(storage: .inMemory(), clock: { self.captured }),
            timeZone: { .gmt }, providerAccess: DashboardProviderAccess(), providerQueries: queries)
    }
    func testRouteInitializationDoesNotReplaceSavedDatePageOrExactID() {
        let model = model(), original = captured.addingTimeInterval(-4 * 86400)
        model.napInspection.initializeDayIfNeeded(original)
        model.napInspection.selectEpisode("nap:second-on-same-date")
        model.napInspection.setCalendarPage(3)
        _ = SleepNapsDashboardView(model: model)
        model.napInspection.initializeDayIfNeeded(captured)
        _ = SleepNapsDashboardView(model: model)
        XCTAssertEqual(model.napInspection.selectedDay, original)
        XCTAssertEqual(model.napInspection.selectedEpisodeID, "nap:second-on-same-date")
        XCTAssertEqual(model.napInspection.calendarPage, 3)
    }
    func testRefreshRangeAndProviderInvalidationRetainInspectionOnly() async {
        let model = model(), original = captured.addingTimeInterval(-9 * 86400)
        model.napInspection.initializeDayIfNeeded(original)
        model.napInspection.selectEpisode("nap:durable")
        model.napInspection.setCalendarPage(2)
        let saved = model.napInspection
        model.selectedRange = .week
        await model.refreshAndWait()
        model.providerAccess.invalidate(.health)
        XCTAssertEqual(model.napInspection, saved)
        XCTAssertNil(model.healthSnapshot)
        XCTAssertNil(model.healthQueryWindow)
    }
    func testHiddenAndUnavailableIDsRemainUntilExplicitClear() {
        var state = DashboardNapInspection()
        state.selectEpisode("nap:two")
        XCTAssertEqual(state.selectionStatus(visibleIDs: ["nap:one"], knownIDs: ["nap:one", "nap:two"]), .filtered)
        XCTAssertEqual(state.selectedEpisodeID, "nap:two")
        XCTAssertEqual(state.selectionStatus(visibleIDs: [], knownIDs: []), .unavailable)
        XCTAssertEqual(state.selectionStatus(visibleIDs: ["nap:two"], knownIDs: ["nap:two"]), .visible)
        state.clearSelection()
        XCTAssertNil(state.selectedEpisodeID)
        XCTAssertEqual(state.selectionStatus(visibleIDs: [], knownIDs: []), .none)
    }
    func testExplicitDateChangeDoesNotSubstituteSameDateEpisode() {
        var state = DashboardNapInspection()
        state.selectEpisode("nap:chosen")
        state.selectDay(captured)
        state.selectDay(captured.addingTimeInterval(-86400))
        XCTAssertEqual(state.selectedEpisodeID, "nap:chosen")
        XCTAssertEqual(state.selectionStatus(visibleIDs: ["nap:other"], knownIDs: ["nap:chosen", "nap:other"]), .filtered)
    }
    func testInvalidDatesAndUnboundedPagesCannotBreakPresentation() {
        var state = DashboardNapInspection()
        state.initializeDayIfNeeded(Date(timeIntervalSince1970: .nan))
        XCTAssertNil(state.selectedDay)
        state.initializeDayIfNeeded(captured)
        state.selectDay(Date(timeIntervalSince1970: .infinity))
        XCTAssertEqual(state.selectedDay, captured)
        state.setCalendarPage(Int.max)
        XCTAssertEqual(state.visiblePage(dayCount: 14), 0)
        XCTAssertEqual(state.visiblePage(dayCount: 15), 1)
        XCTAssertEqual(state.visiblePage(dayCount: -1), 0)
        XCTAssertEqual(state.calendarPage, Int.max)
        state.setCalendarPage(-1)
        XCTAssertEqual(state.calendarPage, 0)
    }
}
