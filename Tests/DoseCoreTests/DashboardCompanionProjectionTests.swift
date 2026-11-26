import XCTest
@testable import DoseCore

final class DashboardCompanionProjectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot(_ datasets: [DashboardDataset: [[String: Any]]] = [:]) throws -> CloudDashboardSnapshot {
        try .init(sourceID: "synthetic", sequence: 4, capturedAt: now,
            sections: DashboardDataset.allCases.map { dataset in
                let rows = datasets[dataset] ?? []
                return .init(dataset: dataset, rows: try JSONSerialization.data(withJSONObject: rows), rowCount: rows.count)
            })
    }
    private func row(_ table: String, _ fields: [String: String]) -> [String: Any] {
        ["sourceTable": table, "columns": fields.mapValues { ["type": "text", "text": $0] }]
    }
    func testDistinctSessionsOnOneDateNeverBecomeOneDosePair() throws {
        let source = try snapshot([.doseEvents: [
            row("dose_events", ["id":"one", "session_id":"a", "session_date":"2027-01-15", "event_type":"dose1", "timestamp":"2027-01-15T01:00:00Z"]),
            row("dose_events", ["id":"two", "session_id":"b", "session_date":"2027-01-15", "event_type":"dose2", "timestamp":"2027-01-15T04:00:00Z"])
        ]])
        let projection = try DashboardCompanionProjection(snapshot: source, now: now)
        XCTAssertEqual(Set(projection.nights.map(\.id)), ["session:a", "session:b"])
        XCTAssertTrue(projection.nights.allSatisfy { $0.pattern.interval.value == nil })
        XCTAssertEqual(projection.sequence, 4)
        XCTAssertEqual(projection.capturedAt, source.capturedAt)
    }
    func testCorrectedIdentityDatesNeedReviewAndMissingDose2StaysIncomplete() throws {
        let doses = [row("dose_events", ["id":"one", "session_id":"a", "session_date":"2027-01-15", "event_type":"dose1", "timestamp":"2027-01-15T01:00:00Z"])]
        let normal = try DashboardCompanionProjection(snapshot: snapshot([.doseEvents: doses]), now: now)
        XCTAssertEqual(normal.nights.first?.pattern.pattern, .incomplete)
        let conflicting = try snapshot([.doseEvents: doses, .morning: [row("morning_checkins", ["session_id":"a", "session_date":"2027-01-16"])]])
        let result = try DashboardCompanionProjection(snapshot: conflicting, now: now)
        XCTAssertTrue(result.nights.allSatisfy { !$0.identityResolved && $0.pattern.pattern == .needsReview })
    }
    func testMalformedDaytimeRetainsOtherDomainsAndExplainsMissingness() throws {
        let source = try snapshot([.daytimeDiary: [row("daytime_checkins", ["revision_id":"bad", "observation_id":"bad", "payload":"original malformed source"])]])
        let result = try DashboardCompanionProjection(snapshot: source, now: now)
        XCTAssertNil(result.checkIns); XCTAssertNil(result.daytimeEvents)
        XCTAssertNotNil(result.daytimeIssue)
        XCTAssertEqual(result.sourceID, "synthetic")
        XCTAssertEqual(source.sections.first { $0.dataset == .daytimeDiary }?.rowCount, 1)
    }
    func testEmptyLegacyReportDoesNotInventVisitOrWorkHistory() throws {
        let result = try DashboardCompanionProjection(snapshot: snapshot(), now: now)
        XCTAssertNil(result.completedVisits); XCTAssertNil(result.workContext)
        XCTAssertEqual(result.checkIns?.current.count, 0)
        XCTAssertNil(result.daytimeIssue)
    }
    func testCanonicalAliasesAndExplicitSkipRetainDifferentMeaning() throws {
        let rows = [row("dose_events", ["id":"one", "session_id":"a", "session_date":"2027-01-15", "event_type":"Dose 1 Taken", "timestamp":"2027-01-15T01:00:00Z"]),
                    row("dose_events", ["id":"skip", "session_id":"a", "session_date":"2027-01-15", "event_type":"dose_2_skipped", "timestamp":"2027-01-15T04:00:00Z"])]
        let result = try DashboardCompanionProjection(snapshot: snapshot([.doseEvents: rows]), now: now)
        XCTAssertEqual(result.nights.first?.pattern.pattern, .singleOmitted)
        XCTAssertEqual(result.nights.first?.pattern.interval.state, .notApplicable)
        XCTAssertNil(result.nights.first?.pattern.interval.value)
    }
    func testUnassignedMorningEvidenceStaysInRawReportWithoutInventedNight() throws {
        let source = try snapshot([.morning: [row("morning_checkins", ["id":"orphan"])]])
        let result = try DashboardCompanionProjection(snapshot: source, now: now)
        XCTAssertTrue(result.nights.isEmpty)
        XCTAssertEqual(result.unassignedIdentityRowCount, 1)
        XCTAssertEqual(source.sections.first { $0.dataset == .morning }?.rowCount, 1)
    }

    func testProviderOnlyEpisodeKeepsIdentityAndSleepIndependentOfDoseCount() throws {
        let start = now.addingTimeInterval(-7200), end = now.addingTimeInterval(-3600)
        let packet = DashboardSleepEvidence(queryStart: now.addingTimeInterval(-10000), queryEnd: now,
            completedAt: now, timeZoneID: "UTC", samples: [.init(sampleID: "sample", start: start, end: end,
                rawCategory: 1, stage: .asleep, origin: .init(sourceName: "Watch", bundleIdentifier: nil))])
        var source = try snapshot()
        source.sections[source.sections.firstIndex { $0.dataset == .appleHealth }!] = try packet.section()
        source.sleepEpisodes = [.init(episodeID: "apple-health:episode", treatmentDate: "2027-01-15", source: "Watch",
            sessionID: nil, associationRevision: nil, intervals: [.init(start: start, end: end, asleep: true)],
            bedTime: nil, sleepOnset: start, finalWake: end, observationEnd: end, finalWakeBasis: "last_observed_sleep_end",
            derivationVersion: "primary_episode_boundary_v2", totalSleepMinutes: 60,
            queryStart: packet.queryStart, queryEnd: now, completedAt: now, timeZoneID: "UTC")]
        let report = try DashboardCompanionProjection(snapshot: source, now: now)
        let night = try XCTUnwrap(report.nights.first)
        XCTAssertEqual(night.id, "apple-health:episode")
        XCTAssertFalse(night.pattern.countComplete)
        XCTAssertEqual(report.sleepMetric(for: night, definition: .mainProviderEpisode).metric.value, 60)
        XCTAssertNil(report.sleepMetric(for: night, definition: .observedAfterDose2).metric.value)
        XCTAssertEqual(report.replay(for: night, timeZone: .gmt, filterDescription: "test").markers.count, 2)
        source.sections[source.sections.firstIndex { $0.dataset == .appleHealth }!] = .init(dataset: .appleHealth, rows: Data("[]".utf8), rowCount: 0)
        XCTAssertThrowsError(try DashboardCompanionProjection(snapshot: source, now: now))
    }
    func testSharedFiltersRetainUnknownWorkAndStableSelection() throws {
        let source = try snapshot([.doseEvents: [row("dose_events", ["id":"d", "session_id":"a", "session_date":"2027-01-14", "event_type":"dose1", "timestamp":"2027-01-15T01:00:00Z"])]])
        let report = try DashboardCompanionProjection(snapshot: source, now: now)
        var inspection = DashboardInspectionState(); inspection.selectedObservationID = "session:a"
        inspection.workPhaseFilter = .unknown
        XCTAssertEqual(report.visible(range: .all, period: nil, timeZone: .gmt, inspection: inspection).count, 1)
        inspection.dosePatternFilter = .twoReported
        let visible = report.visible(range: .all, period: nil, timeZone: .gmt, inspection: inspection)
        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(inspection.selectionStatus(visibleIDs: visible.map(\.id), knownIDs: report.nights.map(\.id)), .filtered)
        let replay = report.replay(for: report.nights[0], timeZone: .gmt, filterDescription: "test")
        XCTAssertEqual(replay.interval(.dose1ToDose2).state, .unavailable)
        XCTAssertEqual(replay.markers.first?.sourceRecordID, "d")
    }

    func testCapturedReportingZoneMustBeValidAndRoundTrips() throws {
        var source = try snapshot(); source.reportingTimeZoneID = "America/New_York"
        let copy = try JSONDecoder().decode(CloudDashboardSnapshot.self, from: JSONEncoder().encode(source))
        XCTAssertEqual(copy.reportingTimeZoneID, "America/New_York")
        XCTAssertNoThrow(try DashboardCompanionProjection(snapshot: copy, now: now))
        source.reportingTimeZoneID = "Unknown/Not-A-Zone"
        XCTAssertThrowsError(try DashboardCompanionProjection(snapshot: source, now: now))
    }

}
