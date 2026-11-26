import XCTest
@testable import DoseCore

final class DashboardCompanionWorkContextTests: XCTestCase {
    private let captured = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!
    private func report(work: WorkContextDocument? = nil, badPreset: Bool = false, questionnaires: Bool = false, reference: Bool = false, binding: String = "wrong-source") throws -> DashboardCompanionProjection {
        func row(_ table: String, _ fields: [String: String]) -> [String: Any] {
            ["sourceTable": table, "columns": fields.mapValues { ["type": "text", "text": $0] }]
        }
        var data: [DashboardDataset: [[String: Any]]] = [.doseEvents: ["a", "b"].flatMap { id in
            [row("dose_events", ["id": id + "1", "session_id": id, "session_date": "2026-09-28", "event_type": "dose1", "timestamp": "2026-09-29T01:00:00Z"]),
             row("dose_events", ["id": id + "2", "session_id": id, "session_date": "2026-09-28", "event_type": "dose2", "timestamp": "2026-09-29T04:00:00Z"])]
        }]
        if questionnaires {
            data[.morning] = [row("morning_checkins", ["id": "morning-a", "session_id": "a", "session_date": "2026-09-28", "timestamp": "2026-09-29T09:00:00Z"])]
            data[.normalizedAnswers] = [row("checkin_submissions", ["id": "wrong", "checkin_type": binding == "wrong-kind" ? "pre_night" : "morning", "source_record_id": binding == "wrong-source" ? "morning-b" : "morning-a", "session_id": binding == "wrong-session" ? "b" : "a", "session_date": "2026-09-28", "submitted_at_utc": "2026-09-29T09:00:00Z", "questionnaire_version": "v2"])]
        }
        if let work { data[.workSchedule] = [row("work_block_context", ["payload": String(decoding: try JSONEncoder().encode(work), as: UTF8.self)])] }
        if reference {
            let preset = try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(), supersedesRevisionID: nil, labelName: "Synthetic reference", ingredient: "Synthetic", releaseProfile: .immediateRelease,
                components: [.init(id: UUID(), form: .tablet, strengthMilligrams: 5, unitCount: 1)], instructions: "PRIVATE INSTRUCTIONS", schedule: .scheduled,
                effectiveFrom: captured.addingTimeInterval(-86400 * 10), effectiveUntil: nil, recordedAt: captured.addingTimeInterval(-86400 * 11))
            data[.presetVersions] = [row("medication_preset_revisions", ["payload": try MedicationPresetExportSnapshot.encode(preset)])]
        }
        if badPreset { data[.presetVersions] = [row("medication_preset_revisions", ["payload": "invalid"])] }
        let snapshot = try CloudDashboardSnapshot(sourceID: "synthetic", sequence: 3, capturedAt: captured,
            sections: DashboardDataset.allCases.map { dataset in
                let rows = data[dataset] ?? []
                return .init(dataset: dataset, rows: try JSONSerialization.data(withJSONObject: rows), rowCount: rows.count)
            })
        return try .init(snapshot: snapshot, now: captured)
    }
    private func document() -> WorkContextDocument {
        var work = WorkContextDocument()
        let at = captured.addingTimeInterval(-86400 * 5)
        work.rosters = [.init(effectiveFrom: "2026-09-01", effectiveTo: "2026-09-30", timeZoneIdentifier: "UTC", weekdays: [3, 4, 5], recordedAt: at)]
        work.associations = [.init(sleepID: "session:a", precedingDate: "2026-09-28", followingDate: "2026-09-29", timeZoneIdentifier: "UTC", plannedAt: at.addingTimeInterval(1), recordedAt: at.addingTimeInterval(2))]
        work.associations[0].overrideReason = "PRIVATE PERSON NAME"
        return work
    }
    func testExactVisibleIDsNeverCollapseSameDateAndAbsentWorkStaysUnknown() throws {
        let source = try report()
        let result = try DashboardCompanionWorkContext(report: source, nights: source.nights, basis: .confirmed, metric: .doseInterval)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(Set(result.rows.map(\.id)), ["session:a", "session:b"])
        XCTAssertTrue(result.rows.allSatisfy { $0.phase == .unknown && $0.value == 180 })
        XCTAssertEqual(result.unknownContextCount, 2)
        XCTAssertTrue(result.summaries.isEmpty)
        let filtered = try DashboardCompanionWorkContext(report: source, nights: [source.nights[1]], basis: .planned, metric: .doseInterval)
        XCTAssertEqual(filtered.rows.count, 1)
        XCTAssertThrowsError(try DashboardCompanionWorkContext(report: source, nights: [source.nights[0], source.nights[0]], basis: .planned, metric: .doseInterval))
    }
    func testPlannedIsNotConfirmedAndSourceProvenanceSurvivesWithoutPrivateText() throws {
        let source = try report(work: document())
        let result = try DashboardCompanionWorkContext(report: source, nights: source.nights, basis: .planned, metric: .doseInterval)
        let row = try XCTUnwrap(result.rows.first { $0.id == "session:a" })
        XCTAssertEqual(row.plannedPhase, .entering)
        XCTAssertEqual(row.confirmedPhase, .unknown)
        XCTAssertEqual(row.position, "Before shift 1")
        XCTAssertNotNil(row.associationID)
        XCTAssertNotNil(row.rosterID)
        let csv = result.csv(timeZone: .gmt, filterDescription: "all")
        XCTAssertTrue(csv.contains("180.0"))
        XCTAssertTrue(csv.contains("planned"))
        XCTAssertFalse(csv.contains("PRIVATE PERSON NAME"))
        XCTAssertTrue(csv.contains("unknown"))
    }
    func testUnavailableSleepNeverUsesDoseIntervalAndBrokenContextFailsClosed() throws {
        let source = try report(badPreset: true)
        let result = try DashboardCompanionWorkContext(report: source, nights: source.nights, basis: .planned, metric: .mainSleep)
        XCTAssertNotNil(result.contextIssue)
        XCTAssertTrue(result.rows.allSatisfy { $0.value == nil })
        XCTAssertEqual(result.missingCount, 2)
        XCTAssertTrue(result.summaries.isEmpty)
        XCTAssertEqual(result.capturedAt, source.capturedAt)
    }
    func testMismatchedNormalizedSourceRetainsLegacyVersionUnknown() throws {
        for binding in ["wrong-source", "wrong-kind", "wrong-session"] {
            let source = try report(questionnaires: true, reference: true, binding: binding)
            let evidence = try source.workContextEvidence()
            let content = try XCTUnwrap(evidence.contentByObservationID["session:a"]?.first)
            XCTAssertEqual(content.sourceRecordID, "morning_checkins:morning-a")
            XCTAssertEqual(content.instrumentID, "dosetap.morning")
            XCTAssertNil(content.contentVersion)
            XCTAssertTrue(evidence.timeline.annotations.contains { $0.sourceRecordIDs == ["checkin_submissions:wrong"] })
            let night = try XCTUnwrap(source.nights.first { $0.id == "session:a" })
            XCTAssertEqual(evidence.stratum(for: night, report: source).status, .unknown)
        }
    }
    func testExactQuestionnaireVersionAndNamespacedProvenanceArePreserved() throws {
        let source = try report(questionnaires: true, reference: true, binding: "exact")
        let evidence = try source.workContextEvidence()
        let content = try XCTUnwrap(evidence.contentByObservationID["session:a"]?.first)
        XCTAssertEqual(content.sourceRecordID, "checkin_submissions:wrong")
        XCTAssertEqual(content.contentVersion, "v2")
        XCTAssertNil(content.language)
        let result = try DashboardCompanionWorkContext(report: source, nights: source.nights, basis: .confirmed, metric: .doseInterval)
        XCTAssertEqual(result.summaries.count, 2, "Different known questionnaire context must not pool")
    }
    func testKnownCompatibleMonthlyGroupUsesExactRowsAndDenominators() throws {
        let source = try report(reference: true)
        let result = try DashboardCompanionWorkContext(report: source, nights: source.nights, basis: .confirmed, metric: .doseInterval)
        let group = try XCTUnwrap(result.summaries.first)
        XCTAssertEqual(result.summaries.count, 1)
        XCTAssertEqual(group.month, "2026-09")
        XCTAssertEqual(group.summary.availableCount, 2)
        XCTAssertEqual(group.summary.median, 180)
        XCTAssertEqual(Set(group.observationIDs), ["session:a", "session:b"])
        XCTAssertFalse(result.csv(timeZone: .gmt, filterDescription: "all").contains("PRIVATE INSTRUCTIONS"))
    }
    func testEmptyViewExportsMetadataWithoutInventingObservations() throws {
        let source = try report()
        let result = try DashboardCompanionWorkContext(report: source, nights: [], basis: .confirmed, metric: .doseInterval)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(result.csv(timeZone: .gmt, filterDescription: "filtered").contains("metadata"))
    }
}
