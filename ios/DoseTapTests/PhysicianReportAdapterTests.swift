import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class PhysicianReportAdapterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_794_800)
    func period(end: Date? = nil) throws -> PhysicianReportPeriod {
        try .resolve(.custom(start: now.addingTimeInterval(-86400), endExclusive: end ?? now),
                     ledger: .init(), asOf: now, timeZone: .gmt)
    }
    func model() async -> DashboardAnalyticsModel {
        let queries = DashboardProviderQueries(healthEnabled: { false }, whoopEnabled: { false },
            whoopConnected: { false }, prepareHealth: { .unavailable }, healthHistory: { _ in [] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let model = DashboardAnalyticsModel(now: { self.now },
            sessionRepo: SessionRepository(storage: .inMemory(), clock: { self.now }, timeZoneProvider: { .gmt }),
            timeZone: { .gmt }, providerAccess: DashboardProviderAccess(), providerQueries: queries)
        model.selectedRange = .all
        await model.performRefresh(days: 730, includeProviders: false)
        return model
    }
    func night(morning: DoseTap.StoredMorningCheckIn? = nil) -> DashboardNightAggregate {
        let first = now.addingTimeInterval(-10800), second = now.addingTimeInterval(-3600)
        var row = DashboardNightAggregate(sessionDate: "2026-09-29", dose1Time: first, dose2Time: second,
            dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0, events: [], morningCheckIn: morning,
            preSleepLog: nil, healthSummary: nil, whoopSummary: nil, duplicateClusterCount: 0,
            napSummary: .init(count: 0, totalMinutes: 0))
        row.sessionID = "synthetic"; row.stableID = "session:synthetic"; row.sessionClosed = true
        row.doseEvents = [.init(id: "first", eventType: "dose1", timestamp: first, sessionDate: row.sessionDate,
            metadata: "{\"actual_amount_g\":2.25}", sessionId: row.sessionID),
            .init(id: "second", eventType: "dose2", timestamp: second, sessionDate: row.sessionDate, sessionId: row.sessionID)]
        return row
    }
    func testIndependentDaytimeAssessmentsUseExactHalfOpenPeriodWithoutNights() async throws {
        let model = await model()
        let included = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-1), recordedAt: now, timeZoneIdentifier: "UTC", response: 0)
        let excluded = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 10)
        try model.sessionRepo.saveDaytimeCheckIn(included); try model.sessionRepo.saveDaytimeCheckIn(excluded)
        let rows = try model.physicianReportObservations(for: period())
        XCTAssertTrue(model.nights.isEmpty)
        XCTAssertEqual(rows.map(\.id), ["daytime:" + included.id.uuidString])
        XCTAssertEqual(rows.first?.value, 0)
        XCTAssertNotNil(rows.first?.comparisonLabel)
        let contexts = try model.physicianReportContexts(for: period(), generatedAt: now)
        XCTAssertTrue(contexts.first?.lines.contains { $0.contains("1 answered") } == true)
    }
    func testExactEndpointCutoffWithholdsContributionButPreservesRawValueAndAmount() async throws {
        let model = await model(), night = night(); model.nights = [night]
        let cutoff = try XCTUnwrap(night.dose2Time)
        let rows = try model.physicianReportObservations(for: period(end: cutoff))
        let spacing = try XCTUnwrap(rows.first { $0.id == night.id + ":spacing" })
        XCTAssertEqual(spacing.state, .partial); XCTAssertNil(spacing.value)
        XCTAssertTrue(spacing.detail.contains("Raw source value: 120"))
        XCTAssertEqual(spacing.recordIDs, ["first", "second"])
        let raw = try XCTUnwrap(rows.first { $0.id == "administration:first" })
        XCTAssertEqual(raw.detailOnly, true); XCTAssertTrue(raw.detail.contains("2.25"))
        XCTAssertFalse(rows.contains { $0.id == "administration:second" })
    }
    func testSharedDoseProjectionAndRawRowsNeverDoubleCountSummary() async throws {
        let model = await model(), night = night(); model.nights = [night]
        let rows = try model.physicianReportObservations(for: period())
        let spacing = try XCTUnwrap(rows.first { $0.id == night.id + ":spacing" })
        XCTAssertEqual(spacing.value, night.dosePattern.interval.value)
        XCTAssertEqual(spacing.state.rawValue, night.dosePattern.interval.state.rawValue)
        let report = try PhysicianReportSnapshot(period: period(), observations: rows, notes: [], questions: [], appVersion: "test", generatedAt: now)
        XCTAssertFalse(report.summaries.contains { $0.metricID == "Reported dose event detail" })
        XCTAssertTrue(report.detailCSV.contains("2.25"))
    }
    func testRetainedEmptyFilterKeepsIndependentDaytimeAndDoesNotBecomeAll() async throws {
        let model = await model(); model.nights = [night()]
        let check = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-60), recordedAt: now, timeZoneIdentifier: "UTC", response: 3)
        try model.sessionRepo.saveDaytimeCheckIn(check)
        model.inspection.contextStratumID = "exact-context-with-no-matching-rows"
        XCTAssertNil(model.inspectionFilterIssue)
        let rows = try model.physicianReportObservations(for: period())
        XCTAssertEqual(rows.map(\.id), ["daytime:" + check.id.uuidString])
        XCTAssertEqual(model.inspection.contextStratumID, "exact-context-with-no-matching-rows")
    }
    func testUnreadLocalContextFailsClosedInsteadOfUnknownOrEmptySuccess() async throws {
        let model = await model(); model.workContextReadReady = false
        XCTAssertThrowsError(try model.physicianReportObservations(for: period()))
        model.workContextReadReady = true; model.contextReadReady = false
        XCTAssertThrowsError(try model.physicianReportObservations(for: period()))
    }
    func testSelectedMissingWHOOPDoesNotExportUnselectedHealthMetrics() async throws {
        let model = await model(); model.nights = [night()]; model.sleepSource = .whoop
        let rows = try model.physicianReportObservations(for: period())
        XCTAssertFalse(rows.contains { $0.id.hasSuffix(":apple-sleep") })
        let selected = try XCTUnwrap(rows.first { $0.id.hasSuffix(":whoop-sleep") })
        XCTAssertEqual(selected.state, .unavailable); XCTAssertNil(selected.value)
    }
    func testLegacyMorningDefaultsRemainUnconfirmedUnplacedDetailEvenWithPartialPolicy() async throws {
        let model = await model()
        model.nights = [night(morning: .init(id: "legacy-defaults", sessionId: "synthetic", timestamp: now.addingTimeInterval(-1), sessionDate: "2026-09-29"))]
        let rows = try model.physicianReportObservations(for: period())
        let morning = try XCTUnwrap(rows.first { $0.id == "morning:legacy-defaults" })
        XCTAssertEqual(morning.state, .needsReview); XCTAssertEqual(morning.detailOnly, true)
        XCTAssertNil(morning.observedAt); XCTAssertTrue(morning.requiresReview)
        let report = try PhysicianReportSnapshot(period: period(), observations: rows, notes: [], questions: [], appVersion: "test", generatedAt: now, includePartialMetrics: true)
        XCTAssertFalse(report.summaries.contains { $0.metricID == "Morning questionnaire detail" })
        XCTAssertTrue(report.reviewText.contains("assessment time was not collected"))
    }

}
