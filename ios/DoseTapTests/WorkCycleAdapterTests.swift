import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class WorkCycleAdapterTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func model() -> DashboardAnalyticsModel {
        let queries = DashboardProviderQueries(healthEnabled: { false }, whoopEnabled: { false },
            whoopConnected: { false }, prepareHealth: { .unavailable }, healthHistory: { _ in [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let now = start.addingTimeInterval(50_000)
        let result = DashboardAnalyticsModel(now: { now }, sessionRepo: SessionRepository(storage: .inMemory()),
            timeZone: { .gmt }, providerAccess: DashboardProviderAccess(), providerQueries: queries)
        result.selectedRange = .all
        result.nights = [night("a"), night("b")]
        result.contextReadReady = true; result.doseReviewReadReady = true
        result.publishWorkInspectionContext(nil, nights: result.nights, asOf: now)
        return result
    }
    private func night(_ id: String) -> DashboardNightAggregate {
        var row = DashboardNightAggregate(sessionDate: "2026-09-21", dose1Time: start,
            dose2Time: start.addingTimeInterval(10800), dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0,
            events: [], morningCheckIn: nil, preSleepLog: nil, healthSummary: nil, whoopSummary: nil,
            duplicateClusterCount: 0, napSummary: .init(count: 0, totalMinutes: 0))
        row.sessionID = id; row.stableID = "session:" + id
        row.doseEvents = [.init(id: id + "-d1", eventType: "dose1", timestamp: start, sessionDate: row.sessionDate, sessionId: id),
                          .init(id: id + "-d2", eventType: "dose2", timestamp: start.addingTimeInterval(10800), sessionDate: row.sessionDate, sessionId: id)]
        return row
    }
    func testReadinessFailureIsNotAnEmptySuccessfulComparison() {
        let value = model(); value.contextReadReady = false
        XCTAssertNil(value.workCycleComparison(metric: .doseInterval))
        XCTAssertNotNil(value.workCycleComparisonIssue(metric: .doseInterval))
        value.contextReadReady = true; value.invalidateWorkInspectionContext()
        XCTAssertNil(value.workCycleComparison(metric: .doseInterval))
    }
    func testValidEmptyFilterIsAnEmptyComparisonAndKeepsSelection() throws {
        let value = model(); value.inspection.workPhaseFilter = .entering
        value.inspection.selectedObservationID = "session:a"
        let comparison = try XCTUnwrap(value.workCycleComparison(metric: .doseInterval))
        XCTAssertTrue(comparison.observations.isEmpty)
        XCTAssertNil(value.workCycleComparisonIssue(metric: .doseInterval))
        XCTAssertEqual(value.inspection.selectedObservationID, "session:a")
    }
    func testAxisDomainRetainsSelectedRangeWhenSharedPhaseFilterHidesRows() throws {
        let value = model(); value.inspection.workPhaseFilter = .entering
        XCTAssertTrue(try XCTUnwrap(value.workCycleComparison(metric: .doseInterval)).observations.isEmpty)
        XCTAssertEqual(try XCTUnwrap(value.workCycleAxisObservations(metric: .doseInterval)).count, 2)
    }
    func testExactIdentitiesAndUnknownContextStaySeparate() throws {
        let value = model()
        let comparison = try XCTUnwrap(value.workCycleComparison(metric: .doseInterval))
        XCTAssertEqual(Set(comparison.observations.map(\.id)), ["session:a", "session:b"])
        XCTAssertEqual(comparison.selectedPeriod.count, 2)
        XCTAssertTrue(comparison.observations.allSatisfy { $0.value == 180 })
    }
    func testExactPeriodWithholdsBoundaryDoseIntervalButRetainsEvidence() throws {
        let value = model()
        let period = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: start.addingTimeInterval(10800)),
            ledger: .init(), asOf: value.reportingAsOf, timeZone: .gmt)
        let comparison = try XCTUnwrap(value.workCycleComparison(metric: .doseInterval, period: period))
        XCTAssertTrue(comparison.observations.allSatisfy { $0.value == nil && $0.metricEvidence?.metric.value == 180 })
        XCTAssertTrue(comparison.observations.allSatisfy { $0.contributionReason == "metric_bounds_outside_selected_period" })
    }
    func testExactApplePeriodRequiresConsistentRecordedAsleepBounds() throws {
        let value = model(); value.inspection.includePartialMetrics = true
        var health = HealthKitService.SleepNightSummary(date: start, bedTime: nil, sleepOnset: start,
            firstWake: nil, finalWake: start.addingTimeInterval(3600), ttfwMinutes: nil,
            totalSleepMinutes: 60, wakeCount: 0, source: "Synthetic")
        health.recordedIntervals = [.init(start: start.addingTimeInterval(60), end: start.addingTimeInterval(3600), asleep: true)]
        value.nights[0].healthSummary = health
        let period = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: start.addingTimeInterval(7200)),
            ledger: .init(), asOf: value.reportingAsOf, timeZone: .gmt)
        func contribution() throws -> Double? {
            try XCTUnwrap(value.workCycleComparison(metric: .mainSleep, period: period)).observations.first { $0.id == "session:a" }?.value
        }
        XCTAssertNil(try contribution(), "Named and recorded sleep bounds disagree")
        health.recordedIntervals = [.init(start: start, end: start.addingTimeInterval(3600), asleep: true)]
        value.nights[0].healthSummary = health
        XCTAssertEqual(try contribution(), 60)
        health.recordedIntervals = []; value.nights[0].healthSummary = health
        XCTAssertNil(try contribution(), "Missing recorded boundaries cannot produce an exact-period contribution")
    }
    func testAmbiguousDoseIdentityCannotSupplyInterval() throws {
        let value = model(); value.nights[0].identityNeedsReview = true
        let comparison = try XCTUnwrap(value.workCycleComparison(metric: .doseInterval))
        let row = try XCTUnwrap(comparison.observations.first { $0.id == "session:a" })
        XCTAssertNil(row.value); XCTAssertEqual(row.metricEvidence?.metric.state, .needsReview)
    }
    func testDisplayFixturePublishesOneFrozenReadableComparisonSnapshot() throws {
        let value = model()
        XCTAssertTrue(value.loadDashboardUITestFixtureIfRequested(arguments: ["--uitesting-dashboard"]))
        XCTAssertEqual(value.lastRefresh, value.reportingAsOf)
        XCTAssertEqual(value.workInspectionAsOf, value.reportingAsOf)
        XCTAssertTrue(value.contextReadReady); XCTAssertTrue(value.doseReviewReadReady)
        XCTAssertTrue(value.providerAssociationsReady); XCTAssertNotNil(value.contextTimeline)
        XCTAssertEqual(value.healthSnapshot?.window, value.currentReportWindow)
        XCTAssertEqual(value.healthSnapshot?.window.asOf, value.reportingAsOf)
        XCTAssertNil(value.workCycleComparisonIssue(metric: .doseInterval))
        XCTAssertEqual(try XCTUnwrap(value.workCycleComparison(metric: .doseInterval)).observations.count, 8)
        value.inspection.selectedObservationID = value.nights.first?.id
        value.inspection.workPhaseFilter = .entering
        XCTAssertTrue(try XCTUnwrap(value.workCycleComparison(metric: .doseInterval)).observations.isEmpty)
        XCTAssertNotNil(value.inspection.selectedObservationID)
    }

    func testFutureIntervalIsExcludedAtFrozenCaptureWithoutExactPeriod() throws {
        let value = model(); value.reportingAsOf = start.addingTimeInterval(15_000)
        value.nights[0].doseEvents[1] = .init(id: "a-d2", eventType: "dose2", timestamp: start.addingTimeInterval(18_000), sessionDate: "2026-09-21", sessionId: "a")
        value.publishWorkInspectionContext(nil, nights: value.nights, asOf: value.reportingAsOf)
        let row = try XCTUnwrap(value.workCycleComparison(metric: .doseInterval)?.observations.first)
        XCTAssertEqual(row.metricEvidence?.metric.value, 300)
        XCTAssertNil(row.value); XCTAssertEqual(row.contributionState, .needsReview)
        XCTAssertEqual(row.contributionReason, "metric_bounds_after_capture")
    }
    func testInvalidAppleBoundsCannotContributeChronologicalTotal() throws {
        let value = model(); value.inspection.includePartialMetrics = true
        var health = HealthKitService.SleepNightSummary(date: start, bedTime: nil, sleepOnset: start,
            firstWake: nil, finalWake: start.addingTimeInterval(3600), ttfwMinutes: nil,
            totalSleepMinutes: 60, wakeCount: 0, source: "Synthetic")
        health.recordedIntervals = [.init(start: start.addingTimeInterval(60), end: start.addingTimeInterval(3600), asleep: true)]
        value.nights[0].healthSummary = health
        let row = try XCTUnwrap(value.workCycleComparison(metric: .mainSleep)?.observations.first { $0.id == "session:a" })
        XCTAssertNil(row.value); XCTAssertEqual(row.metricEvidence?.metric.value, 60)
        XCTAssertEqual(row.contributionState, .needsReview)
        XCTAssertEqual(row.contributionReason, "inconsistent_recorded_sleep_bounds")
    }
    func testWHOOPOriginalEndpointsAndReviewReasonUseTheSharedFactory() throws {
        let value = model(); value.sleepSource = .whoop; value.inspection.includePartialMetrics = true
        func summary(end: Date) throws -> WHOOPNightSummary {
            let object: [String: Any] = ["id": "scored-episode", "start": ISO8601DateFormatter().string(from: start),
                "end": ISO8601DateFormatter().string(from: end), "score_state": "SCORED",
                "score": ["stage_summary": ["total_light_sleep_time_milli": 60_000,
                    "total_slow_wave_sleep_time_milli": 0, "total_rem_sleep_time_milli": 0]]]
            let raw = try WHOOPService.makeAPIDecoder().decode(WHOOPSleep.self, from: JSONSerialization.data(withJSONObject: object))
            return try XCTUnwrap(WHOOPService.makeNightSummaries(sleeps: [raw], recoveries: []).first)
        }
        let period = try PhysicianReportPeriod.resolve(.custom(start: start, endExclusive: start.addingTimeInterval(7200)),
            ledger: .init(), asOf: value.reportingAsOf, timeZone: .gmt)
        value.nights[0].whoopSummary = try summary(end: start.addingTimeInterval(3600))
        let valid = try XCTUnwrap(value.workCycleComparison(metric: .mainSleep, period: period)?.observations.first { $0.id == "session:a" })
        XCTAssertEqual(valid.value, 1); XCTAssertEqual(valid.metricEvidence?.end, start.addingTimeInterval(3600))
        value.nights[0].whoopSummary = try summary(end: start.addingTimeInterval(30))
        let invalid = try XCTUnwrap(value.workCycleComparison(metric: .mainSleep)?.observations.first { $0.id == "session:a" })
        XCTAssertNil(invalid.value); XCTAssertEqual(invalid.metricEvidence?.metric.state, .needsReview)
        XCTAssertEqual(invalid.contributionState, .needsReview)
    }

    func testNapComparisonRejectsUnpublishedReportingSelection() throws {
        let value = model()
        XCTAssertThrowsError(try value.workCycleNapDayReport())
        XCTAssertTrue(value.loadDashboardUITestFixtureIfRequested(arguments: ["--uitesting-dashboard"]))
        XCTAssertNil(try value.workCycleNapDayReport().documentRevision)
    }

    func testActualShiftComparisonUsesStoredExactLinksAndUnknownActualTimesStayMissing() throws {
        let value = model(), sleep = start.addingTimeInterval(3600)
        var before = WorkShiftEvent(timeZoneIdentifier: "GMT", recordedAt: value.reportingAsOf)
        before.status = .worked; before.attendanceConfirmed = true; before.actualTimePrecision = .reportedMinute
        before.actualStart = sleep.addingTimeInterval(-28800); before.actualEnd = sleep.addingTimeInterval(-3600)
        before.blockID = "reviewed-block"; before.firstShiftDate = "2026-09-19"; before.position = 1; before.blockShiftCount = 2
        var after = before; after.id = UUID(); after.shiftID = UUID(); after.position = 2
        after.actualStart = sleep.addingTimeInterval(32400); after.actualEnd = sleep.addingTimeInterval(40000)
        var association = WorkSleepAssociation(sleepID: "session:a", precedingDate: "2026-09-21", followingDate: "2026-09-22", timeZoneIdentifier: "GMT", plannedAt: value.reportingAsOf, recordedAt: value.reportingAsOf)
        association.eventContext = .init(mainSleepStart: sleep, mainSleepEnd: sleep.addingTimeInterval(25200), precedingStatus: .work, followingStatus: .work, precedingShiftID: before.shiftID, followingShiftID: after.shiftID, wakingPeriodsReviewed: true)
        var document = WorkContextDocument(); document.schemaVersion = 3; document.shiftEvents = [before, after]; document.associations = [association]
        try value.sessionRepo.saveWorkContext(document, expectedRevision: nil)
        let stored = try XCTUnwrap(value.sessionRepo.workContext())
        value.inspection.workContextBasis = .confirmed
        value.publishWorkInspectionContext(stored, nights: value.nights, asOf: value.reportingAsOf)
        let row = try XCTUnwrap(value.workCycleComparison(metric: .shiftEndToSleep)?.observations.first { $0.id == "session:a" })
        XCTAssertEqual(row.value, 60); XCTAssertEqual(row.phase, .between); XCTAssertEqual(row.classificationVersion, 2)
        XCTAssertEqual(row.firstShiftDate, "2026-09-19"); XCTAssertEqual(Set(row.metricSourceRecordIDs), Set([before.id.uuidString, after.id.uuidString]))
        XCTAssertEqual(value.workCycleComparison(metric: .timeBetweenShifts)?.observations.first?.value, 600)
        XCTAssertEqual(value.workCycleComparison(metric: .recordedWork24h)?.observations.first?.value, 420)
        before.actualEnd = nil; document.shiftEvents = [before, after]
        value.publishWorkInspectionContext(document, nights: value.nights, asOf: value.reportingAsOf)
        XCTAssertNil(value.workCycleComparison(metric: .shiftEndToSleep)?.observations.first?.value)
    }
    func testRequiredWakeComparisonUsesHistoricalWarningAndPreservesItsRevision() throws {
        let value = model(), revision = UUID(), wake = start.addingTimeInterval(21600)
        let payload: [String: Any] = ["sessionId": "a", "revision": revision.uuidString, "wakeDate": "2026-09-21", "timeZoneIdentifier": "GMT",
            "requiredWake": wake.timeIntervalSinceReferenceDate, "targetAt": start.timeIntervalSinceReferenceDate, "target": WorkWarningTarget.doseTarget.rawValue]
        let metadata = String(decoding: try JSONSerialization.data(withJSONObject: ["work_warning_acknowledgement": payload]), as: UTF8.self)
        value.nights[0].doseEvents[1] = .init(id: "a-d2", eventType: "dose2", timestamp: start.addingTimeInterval(10800), sessionDate: "2026-09-21", metadata: metadata, sessionId: "a")
        let row = try XCTUnwrap(value.workCycleComparison(metric: .dose2ToRequiredWake)?.observations.first)
        XCTAssertEqual(row.value, 180); XCTAssertEqual(row.metricEvidence?.end, wake)
        XCTAssertEqual(row.metricSourceRecordIDs, ["a-d2:" + revision.uuidString])
        XCTAssertNil(value.workCycleComparison(metric: .dose2ToRequiredWake)?.observations.last?.value)
    }

}
