import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardInspectionFilterTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_790_794_800)
    private func makeModel() -> DashboardAnalyticsModel {
        let queries = DashboardProviderQueries(healthEnabled: { false }, whoopEnabled: { false },
            whoopConnected: { false }, prepareHealth: { .unavailable }, healthHistory: { _ in [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let model = DashboardAnalyticsModel(now: { self.instant },
            sessionRepo: SessionRepository(storage: .inMemory(), clock: { self.instant }),
            timeZone: { .gmt }, providerAccess: DashboardProviderAccess(), providerQueries: queries)
        model.selectedRange = .all
        model.nights = [night("one"), night("two")]
        return model
    }
    private func night(_ id: String) -> DashboardNightAggregate {
        var row = DashboardNightAggregate(sessionDate: "2026-09-28", dose1Time: nil, dose2Time: nil,
            dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0, events: [], morningCheckIn: nil,
            preSleepLog: nil, healthSummary: nil, whoopSummary: nil, duplicateClusterCount: 0,
            napSummary: .init(count: 0, totalMinutes: 0))
        row.sessionID = id; row.stableID = "session:" + id
        return row
    }
    func testNoFilterRetainsSameDateIdentitiesAndSelection() {
        let model = makeModel(); model.inspection.selectedObservationID = "session:two"
        XCTAssertEqual(Set(model.visibleInspectionNights.map(\.id)), ["session:one", "session:two"])
        XCTAssertNil(model.inspectionFilterIssue)
        XCTAssertEqual(model.inspection.selectedObservationID, "session:two")
    }
    func testSameDateObservationOrderingIsStableAcrossRefreshInputOrder() {
        let model = makeModel()
        let before = model.visibleInspectionNights.map(\.id)
        model.nights.reverse()
        XCTAssertEqual(model.visibleInspectionNights.map(\.id), before)
    }
    func testRequestedWorkFilterFailsClosedUntilReadReady() {
        let model = makeModel(); model.inspection.workPhaseFilter = .unknown
        XCTAssertTrue(model.visibleInspectionNights.isEmpty)
        XCTAssertNotNil(model.inspectionFilterIssue)
        model.publishWorkInspectionContext(nil, nights: model.nights, asOf: instant)
        XCTAssertEqual(model.visibleInspectionNights.count, 2)
        XCTAssertNil(model.inspectionFilterIssue)
        model.inspection.workPhaseFilter = .entering
        XCTAssertTrue(model.visibleInspectionNights.isEmpty)
    }
    func testStaleWorkCutoffCannotMasqueradeAsUnknown() {
        let model = makeModel()
        model.publishWorkInspectionContext(nil, nights: model.nights, asOf: instant.addingTimeInterval(-1))
        model.inspection.workPhaseFilter = .unknown
        XCTAssertNotNil(model.inspectionFilterIssue)
        XCTAssertTrue(model.visibleInspectionNights.isEmpty)
    }
    func testWorkCacheUsesExactIdentityAndSelectedEvidenceBasis() {
        let model = makeModel(); let early = instant.addingTimeInterval(-7 * 86400)
        var document = WorkContextDocument()
        document.rosters = [WorkRoster(effectiveFrom: "2026-09-01", effectiveTo: "2026-12-31",
            timeZoneIdentifier: "UTC", weekdays: [3, 4, 5], recordedAt: early)]
        document.associations = [WorkSleepAssociation(sleepID: "session:one", precedingDate: "2026-09-28",
            followingDate: "2026-09-29", timeZoneIdentifier: "UTC", plannedAt: early, recordedAt: early)]
        XCTAssertTrue(document.isValid)
        model.publishWorkInspectionContext(document, nights: model.nights, asOf: instant)
        model.inspection.workContextBasis = .planned; model.inspection.workPhaseFilter = .entering
        XCTAssertEqual(model.visibleInspectionNights.map(\.id), ["session:one"])
        XCTAssertNil(model.workClassification(for: "session:two"))
        model.inspection.workContextBasis = .confirmed
        XCTAssertTrue(model.visibleInspectionNights.isEmpty)
        XCTAssertEqual(model.workClassification(for: "session:one")?.phase, .unknown)
    }
    func testInvalidatedWorkCacheDoesNotClassifyRetainedRows() {
        let model = makeModel(); model.publishWorkInspectionContext(nil, nights: model.nights, asOf: instant)
        model.inspection.workPhaseFilter = .unknown
        model.inspection.selectedObservationID = "session:one"
        model.invalidateWorkInspectionContext()
        XCTAssertTrue(model.visibleInspectionNights.isEmpty)
        XCTAssertFalse(model.workContextReadReady)
        XCTAssertEqual(model.inspection.selectedObservationID, "session:one")
    }
    func testDoseFilterDoesNotReplaceHiddenSelection() {
        let model = makeModel(); model.inspection.selectedObservationID = "session:one"
        model.inspection.dosePatternFilter = .twoReported
        XCTAssertTrue(model.visibleInspectionNights.isEmpty)
        XCTAssertEqual(model.inspection.selectedObservationID, "session:one")
        model.inspection.resetFilters()
        XCTAssertEqual(model.visibleInspectionNights.count, 2)
    }
    func testContextFilterRequiresCurrentPublicationAndExactIdentity() {
        let model = makeModel(); model.inspection.contextStratumID = "nonexistent-context"
        XCTAssertTrue(model.visibleInspectionNights.isEmpty)
        XCTAssertNotNil(model.inspectionFilterIssue)
        model.contextReadReady = true
        XCTAssertTrue(model.visibleInspectionNights.isEmpty)
        XCTAssertNil(model.inspectionFilterIssue)
    }
    func testContextCaptureUsesPublishedCutoffAfterAwaitedProviderRead() async {
        var clock = instant
        let queries = DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { false },
            whoopConnected: { false }, prepareHealth: { .ready },
            healthHistory: { _ in clock = clock.addingTimeInterval(60); return [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let model = DashboardAnalyticsModel(now: { clock },
            sessionRepo: SessionRepository(storage: .inMemory(), clock: { clock }),
            timeZone: { .gmt }, providerAccess: DashboardProviderAccess(), providerQueries: queries)
        await model.performRefresh(days: 30)
        XCTAssertTrue(model.contextReadReady)
        XCTAssertEqual(model.contextTimeline?.capturedAt, model.reportingAsOf)
        XCTAssertEqual(model.reportingAsOf, instant)
    }
}
