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
        XCTAssertEqual(spacing.state, .unavailable); XCTAssertNil(spacing.value)
        XCTAssertTrue(spacing.detail.contains("metric_bounds_outside_selected_period"))
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

extension PhysicianReportAdapterTests {
    func testExplicitPreparationFreezesExactPeriodSourceAndPartialPolicy() async throws {
        let model = await model(), period = try period()
        let row = try DaytimeCheckIn(assessedAt: now.addingTimeInterval(-60), recordedAt: now, timeZoneIdentifier: "UTC", response: 4)
        try model.sessionRepo.saveDaytimeCheckIn(row)
        var selection = DashboardInspectionState(); selection.includePartialMetrics = true
        selection.contextStratumID = "retained-empty-context"
        let source = PhysicianSourcePreparation(model: model)
        let prepared = try await source.prepare(period: period, inspection: selection, sleepSource: .whoop)
        XCTAssertEqual(prepared.period, period); XCTAssertTrue(prepared.includePartialMetrics)
        XCTAssertEqual(prepared.observations.map(\.id), ["daytime:" + row.id.uuidString])
        XCTAssertTrue(prepared.contexts.first?.lines.contains("Selected sleep source: WHOOP") == true)
        XCTAssertTrue(prepared.contexts.first?.lines.contains { $0.contains("retained-empty-context") } == true)
        selection.resetFilters(); model.inspection = selection
        XCTAssertTrue(prepared.includePartialMetrics)
        let report = try PhysicianReportSnapshot(period: prepared.period, observations: prepared.observations, notes: [], questions: [],
            appVersion: "test", generatedAt: now, contexts: prepared.contexts, includePartialMetrics: prepared.includePartialMetrics)
        XCTAssertEqual(report.includePartialMetrics, true)
    }
    func testCancelledPreparationCannotPublishPreviewSources() async throws {
        let model = await model(), period = try period(), source = PhysicianSourcePreparation(model: model)
        let task = Task { try await source.prepare(period: period, inspection: .init(), sleepSource: .appleHealth) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled preparation must not produce a capture") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try model.sessionRepo.physicianReports().isEmpty)
    }
}

extension PhysicianReportAdapterTests {
    func testReportUsesSharedRecordedSleepBoundaryGate() async throws {
        let first = now.addingTimeInterval(-7200), last = now.addingTimeInterval(-1800)
        let summary = HealthKitService.SleepNightSummary(date: first, bedTime: first, sleepOnset: first,
            firstWake: nil, finalWake: last, ttfwMinutes: nil, totalSleepMinutes: 90, wakeCount: 0, source: "Synthetic")
        let queries = DashboardProviderQueries(healthEnabled: { true }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .ready }, healthHistory: { _ in [summary] },
            whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
        let model = DashboardAnalyticsModel(now: { self.now }, sessionRepo: SessionRepository(storage: .inMemory(), clock: { self.now }),
            timeZone: { .gmt }, providerAccess: DashboardProviderAccess(), providerQueries: queries)
        model.selectedRange = .all; await model.performRefresh(days: 730)
        XCTAssertTrue(model.providerSnapshotIsCurrent(.health))
        let shared = try XCTUnwrap(model.workCycleComparison(metric: .mainSleep, period: period())?.observations.first)
        XCTAssertNil(shared.value); XCTAssertEqual(shared.contributionReason, "metric_bounds_unavailable")
        let rows = try model.physicianReportObservations(for: period())
        let primary = try XCTUnwrap(rows.first { $0.metricID.hasPrefix("Primary episode sleep") })
        XCTAssertNil(primary.value); XCTAssertTrue(primary.detail.contains(shared.contributionReason))
        XCTAssertTrue(primary.detail.contains("90"))
        var paired = night(); paired.healthSummary = summary; model.nights = [paired]
        for includePartial in [false, true] {
            model.inspection.includePartialMetrics = includePartial
            let interval = model.replaySnapshot(for: paired).interval(.dose2ToDeviceEnd)
            XCTAssertNotNil(interval.minutes)
            let reportRows = try model.physicianReportObservations(for: period())
            let row = try XCTUnwrap(reportRows.first { $0.id == paired.id + ":interval:" + DashboardIntervalPreset.dose2ToDeviceEnd.rawValue })
            XCTAssertEqual(row.value, interval.eligibleMinutes(includePartial: includePartial))
            XCTAssertTrue(row.detail.contains(interval.reason))
        }
    }
    func testUnknownDaytimeContextsCannotBecomeOnePooledReportGroup() async throws {
        let model = await model()
        for rating in [1, 9] {
            try model.sessionRepo.saveDaytimeCheckIn(.init(assessedAt: now.addingTimeInterval(-60), recordedAt: now,
                timeZoneIdentifier: "UTC", response: rating))
        }
        let rows = try model.physicianReportObservations(for: period())
        let report = try PhysicianReportSnapshot(period: period(), observations: rows, notes: [], questions: [], appVersion: "test", generatedAt: now)
        XCTAssertEqual(report.summaries.filter { $0.metricID == "Current sleepiness (custom 0–10)" }.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.comparisonLabel?.lowercased().contains("unknown") == true })
    }
    func testPromptHistoryPreservesIntentAndResponseWithoutInventingDelivery() async throws {
        let model = await model()
        var ledger = DaytimePromptLedger()
        let earlier = now.addingTimeInterval(-86400)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let clock = calendar.dateComponents([.hour, .minute], from: now.addingTimeInterval(-3600))
        try ledger.configure(hour: try XCTUnwrap(clock.hour), minute: try XCTUnwrap(clock.minute), timeZone: "UTC", enabled: true, at: earlier)
        let prompt = try XCTUnwrap(ledger.prepare(at: earlier))
        try ledger.open(id: prompt.id, at: now.addingTimeInterval(-2))
        try ledger.respond(id: prompt.id, assessmentID: UUID(), assessedAt: now.addingTimeInterval(-3), at: now.addingTimeInterval(-1))
        _ = ledger.prepareHorizon(at: now)
        try model.sessionRepo.saveDaytimePrompts(ledger)
        let rows = try model.physicianReportObservations(for: period()).filter { $0.id.hasPrefix("prompt:") }
        XCTAssertTrue(rows.contains { $0.id.hasSuffix(":responded") })
        XCTAssertTrue(rows.contains { $0.id.hasSuffix(":intended") })
        XCTAssertFalse(rows.contains { $0.observedAt.map { $0 >= now } == true })
        XCTAssertTrue(rows.allSatisfy { $0.detailOnly == true && $0.detail.contains("not observed delivery") })
    }
    func testWorkContextRetainsCanonicalCountsWithoutInventingRevision() async throws {
        let model = await model(); model.nights = [night()]
        let shared = try XCTUnwrap(model.workCycleComparison(metric: .doseInterval, period: period()))
        let group = try XCTUnwrap(shared.selectedPeriod.first)
        let contexts = try model.physicianReportContexts(for: period(), generatedAt: now)
        let work = try XCTUnwrap(contexts.first { $0.id.hasPrefix("work-comparison:") && $0.title.contains("D1–D2") && $0.title.contains("Full period") })
        XCTAssertTrue(work.lines.contains { $0.contains("\(group.summary.availableCount)/\(group.summary.eligibleCount) eligible") })
        XCTAssertFalse(work.recordIDs.contains("00000000-0000-0000-0000-000000000000"))
        XCTAssertTrue(work.lines.contains { $0.contains("Context revision: unavailable") })
    }
}

extension PhysicianReportAdapterTests {
    func testNapReportPreservesRevisionsAndUnknownEstimatesWithoutPrivateReason() async throws {
        let model = await model()
        let start = now.addingTimeInterval(-120), end = now.addingTimeInterval(-60)
        var original = NapEpisode(day: NapEpisode.day(start, "UTC"), timeZoneID: "UTC", start: start, end: end, recordedAt: end)
        original.intent = .unknown
        var correction = original; correction.revision = UUID(); correction.predecessor = original.revision
        correction.recordedAt = now; correction.reason = "Private correction reason"; correction.intent = .rest
        var document = NapDiaryDocument(); document.episodes = [original, correction]
        try model.sessionRepo.saveNapDiary(document, expectedRevision: nil)
        let rows = try model.physicianReportObservations(for: period()).filter { $0.id.hasPrefix("nap:") }
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.value == nil && $0.detailOnly == true && $0.detail.contains("Work context unknown") })
        XCTAssertFalse(rows.contains { $0.detail.contains("Private correction reason") })
        XCTAssertTrue(rows.contains { $0.recordIDs.contains(original.revision.uuidString) })
        XCTAssertTrue(rows.contains { $0.recordIDs.contains(correction.revision.uuidString) })
        let report = try PhysicianReportSnapshot(period: period(), observations: rows, notes: [], questions: [], appVersion: "test", generatedAt: now)
        XCTAssertTrue(report.summaries.isEmpty)
    }
    func testNapDayReviewRemainsOriginalDayEvidenceWithoutInventedOccurrence() async throws {
        let model = await model()
        var document = NapDiaryDocument()
        let review = NapDayReview(day: NapEpisode.day(now, "UTC"), timeZoneID: "UTC", status: .none, recordedAt: now)
        document.reviews = [review]
        try model.sessionRepo.saveNapDiary(document, expectedRevision: nil)
        let rows = try model.physicianReportObservations(for: period()).filter { $0.id.hasPrefix("nap-day-review:") }
        XCTAssertEqual(rows.count, 1); XCTAssertNil(rows.first?.observedAt); XCTAssertNil(rows.first?.value)
        XCTAssertEqual(rows.first?.detailOnly, true); XCTAssertEqual(rows.first?.recordIDs, [review.id.uuidString])
        XCTAssertTrue(rows.first?.detail.contains("fully assessed report day") == true)
    }
}
