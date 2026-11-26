import XCTest
@testable import DoseCore

final class DashboardInspectionStateTests: XCTestCase {
    func testDefaultHasNoImplicitSelectionOrExclusion() {
        let state = DashboardInspectionState()
        XCTAssertEqual(state.selectionStatus(visibleIDs: ["a"], knownIDs: ["a"]), .none)
        XCTAssertNil(state.dosePatternFilter)
        XCTAssertNil(state.workPhaseFilter)
        XCTAssertFalse(state.includePartialMetrics)
    }
    func testFilteringRetainsExactSelectedObservation() {
        var state = DashboardInspectionState()
        state.selectedObservationID = "session:first"
        XCTAssertEqual(state.selectionStatus(visibleIDs: ["session:second"], knownIDs: ["session:first", "session:second"]), .filtered)
        XCTAssertEqual(state.selectedObservationID, "session:first")
        XCTAssertEqual(state.selectionStatus(visibleIDs: ["session:first"], knownIDs: ["session:first"]), .visible)
    }
    func testUnavailableObservationNeverSelectsAnotherSession() {
        var state = DashboardInspectionState()
        state.selectedObservationID = "provider:removed"
        XCTAssertEqual(state.selectionStatus(visibleIDs: ["session:other"], knownIDs: ["session:other"]), .unavailable)
        XCTAssertEqual(state.selectedObservationID, "provider:removed")
    }
    func testResetFiltersPreservesSelectionAndHistoricalBasis() {
        var state = DashboardInspectionState()
        state.selectedObservationID = "session:a"
        state.dosePatternFilter = .singleOmitted
        state.workPhaseFilter = .after
        state.workContextBasis = .confirmed
        state.contextStratumID = "context:one"
        state.includePartialMetrics = true
        state.resetFilters()
        XCTAssertEqual(state.selectedObservationID, "session:a")
        XCTAssertEqual(state.workContextBasis, .confirmed)
        XCTAssertNil(state.dosePatternFilter)
        XCTAssertNil(state.workPhaseFilter)
        XCTAssertNil(state.contextStratumID)
        XCTAssertFalse(state.includePartialMetrics)
    }
}
