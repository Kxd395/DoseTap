import XCTest
@testable import DoseCore

final class DashboardDiaryAnalysisTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_788_220_800)
    private func snapshot(identity: String? = "session-a", outcomeID: String = "session-a",
                          interval: Double = 180, wakeMinutes: Double? = 300,
                          assessedMinutes: Double? = 330, score: Int? = 0,
                          duplicate: Bool = false, skip: Bool = false, base: Date? = nil,
                          dateKey: String = "2026-09-01") throws -> CloudDashboardSnapshot {
        let start = base ?? self.start
        func text(_ value: String) -> [String: Any] { ["type": "text", "text": value] }
        func row(_ table: String, _ fields: [String: Any]) -> [String: Any] { ["sourceTable": table, "columns": fields] }
        let iso = ISO8601DateFormatter()
        func date(_ minutes: Double) -> String { iso.string(from: start.addingTimeInterval(minutes * 60)) }
        func dose(_ id: String, _ kind: String, _ minutes: Double) -> [String: Any] {
            row("dose_events", ["id": text(id), "event_type": text(kind), "timestamp": text(date(minutes)),
                "session_date": text(dateKey), "session_id": identity.map(text) ?? ["type": "null"]])
        }
        var doses = [dose("d1", "dose1", 0), dose("d2", "dose2", interval)]
        if duplicate { doses.append(dose("d3", "dose2", interval)) }
        if skip { doses.append(dose("skip", "dose2_skipped", interval)) }
        var answers: [String: Any] = ["wakeMethod": "alarm", "dayType": "workday"]
        if let wakeMinutes { answers["finalWakeAt"] = date(wakeMinutes) }
        if let assessedMinutes { answers["assessedAt"] = date(assessedMinutes) }
        if let score { answers["sleepiness"] = score }
        let payload: [String: Any] = ["answers": answers, "recordedAt": date(400), "revisions": []]
        let outcome = row("checkin_submissions", ["id": text("night_outcome:" + outcomeID),
            "source_record_id": text(outcomeID), "session_id": text(outcomeID), "session_date": text(dateKey),
            "checkin_type": text("night_outcome"), "questionnaire_version": text("night_outcome.v1"),
            "responses_json": text(String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self))])
        let content: [DashboardDataset: [[String: Any]]] = [.doseEvents: doses, .normalizedAnswers: [outcome]]
        return CloudDashboardSnapshot(sourceID: "phone", sequence: 7, capturedAt: start.addingTimeInterval(500 * 60),
            sections: try DashboardDataset.allCases.map {
                let rows = content[$0] ?? []
                return .init(dataset: $0, rows: try JSONSerialization.data(withJSONObject: rows), rowCount: rows.count)
            })
    }
    private func analysis(_ snapshot: CloudDashboardSnapshot) throws -> DashboardDiaryAnalysis {
        try .init(snapshot: snapshot, now: snapshot.capturedAt)
    }
    func testValidZeroRatingAndIndependentMetricCounts() throws {
        let value = try analysis(snapshot())
        XCTAssertEqual(value.sequence, 7); XCTAssertEqual(value.sourceID, "phone")
        let point = try XCTUnwrap(value.points.first)
        XCTAssertEqual(point.dose2ToReportedFinalWakeMinutes, 120)
        XCTAssertEqual(point.matchedSleepiness0To10, 0)
        let summary = DashboardDiaryAnalysis.summaries(for: value.points)
        XCTAssertEqual(summary.elapsedCount, 1); XCTAssertEqual(summary.medianSleepiness, 0)
        XCTAssertEqual(summary.sleepinessCount, 1)
    }
    func testNullAndDatePlaceholderIdentityNeverRepaired() throws {
        for id: String? in [nil, "2026-09-01"] {
            let point = try XCTUnwrap(analysis(snapshot(identity: id)).points.first)
            XCTAssertEqual(point.sleepiness0To10, 0)
            XCTAssertNil(point.matchedSleepiness0To10)
            XCTAssertEqual(point.elapsedExclusion, .identityUnavailable)
        }
    }
    func testDifferentIdentityAndConflictingDoseEvidenceExcluded() throws {
        for value in [try snapshot(outcomeID: "other"), try snapshot(duplicate: true),
                      try snapshot(skip: true), try snapshot(interval: 0), try snapshot(interval: -1)] {
            let points = try analysis(value).points
            XCTAssertNil(points.first?.dose2ToReportedFinalWakeMinutes)
            XCTAssertNil(points.first?.matchedSleepiness0To10)
        }
    }
    func testMissingFinalWakePreservesRawRating() throws {
        let point = try XCTUnwrap(analysis(snapshot(wakeMinutes: nil)).points.first)
        XCTAssertEqual(point.sleepiness0To10, 0); XCTAssertNotNil(point.sleepinessAssessedAt)
        XCTAssertEqual(point.elapsedExclusion, .missingFinalWake)
        XCTAssertEqual(point.sleepinessExclusion, .missingFinalWake)
    }
    func testFinalWakeEqualToDoseIsZeroElapsedNotMissing() throws {
        let point = try XCTUnwrap(analysis(snapshot(wakeMinutes: 180)).points.first)
        XCTAssertEqual(point.dose2ToReportedFinalWakeMinutes, 0)
        XCTAssertEqual(point.matchedSleepiness0To10, 0)
    }
    func testBadChronologyAndInvalidRatingNeverBecomeMatchedValues() throws {
        for value in [try snapshot(wakeMinutes: 100, assessedMinutes: 150),
                      try snapshot(assessedMinutes: 290), try snapshot(score: 11),
                      try snapshot(assessedMinutes: nil)] {
            XCTAssertNil(try analysis(value).points.first?.matchedSleepiness0To10)
        }
    }
    func testFractionalIntervalAndRatingMissingHaveSeparateDenominators() throws {
        let point = try XCTUnwrap(analysis(snapshot(interval: 0.5, assessedMinutes: nil, score: nil)).points.first)
        XCTAssertEqual(point.dose2ToReportedFinalWakeMinutes, 299.5)
        let summary = DashboardDiaryAnalysis.summaries(for: [point])
        XCTAssertEqual(summary.elapsedCount, 1); XCTAssertEqual(summary.sleepinessCount, 0)
        XCTAssertEqual(summary.sleepinessExclusions[.missingTimedRating], 1)
    }
    private func replacing(_ section: DashboardDataset, in snapshot: CloudDashboardSnapshot,
                           change: ([[String: Any]]) -> [[String: Any]]) throws -> CloudDashboardSnapshot {
        var result = snapshot
        let index = try XCTUnwrap(result.sections.firstIndex { $0.dataset == section })
        let rows = try JSONSerialization.jsonObject(with: XCTUnwrap(result.sections[index].rows)) as! [[String: Any]]
        let updated = change(rows)
        result.sections[index] = .init(dataset: section,
            rows: try JSONSerialization.data(withJSONObject: updated), rowCount: updated.count)
        return result
    }
    func testOnlyOneDoseCarriesIdentityCannotJoin() throws {
        for missing in 0...1 {
            let value = try replacing(.doseEvents, in: snapshot()) { rows in
                var rows = rows, columns = rows[missing]["columns"] as! [String: Any]
                columns["session_id"] = ["type": "null"]
                rows[missing]["columns"] = columns
                return rows
            }
            let point = try XCTUnwrap(analysis(value).points.first)
            XCTAssertNil(point.dose2ToReportedFinalWakeMinutes)
            XCTAssertNil(point.matchedSleepiness0To10)
        }
    }
    func testLifecycleCannotPromoteNullDosesAndCrossDateIdentityIsConflict() throws {
        for identity: String? in [nil, "session-a"] {
            let value = try replacing(.sessions, in: snapshot(identity: identity)) { _ in
                [["sourceTable": "sleep_sessions", "columns": [
                    "session_id": ["type": "text", "text": "session-a"],
                    "session_date": ["type": "text", "text": identity == nil ? "2026-09-01" : "2026-09-02"]]]]
            }
            let point = try XCTUnwrap(analysis(value).points.first)
            XCTAssertNil(point.matchedSleepiness0To10)
            XCTAssertNil(point.dose2ToReportedFinalWakeMinutes)
        }
    }
    func testPostCaptureDiaryRejectedAndOldGenerationRemainsIndependent() throws {
        var old = try snapshot()
        old.capturedAt = start.addingTimeInterval(350 * 60)
        let oldPoint = try XCTUnwrap(analysis(old).points.first)
        XCTAssertNil(oldPoint.sleepiness0To10)
        XCTAssertEqual(oldPoint.elapsedExclusion, .unavailableDiary)
        let current = try analysis(snapshot())
        XCTAssertEqual(current.points.first?.matchedSleepiness0To10, 0)
    }

    func testMidnightAndDSTUseAbsoluteElapsedTime() throws {
        let iso = ISO8601DateFormatter()
        for (instant, key) in [("2026-09-01T23:30:00Z", "2026-09-01"),
                               ("2026-11-01T04:30:00Z", "2026-10-31")] {
            let base = try XCTUnwrap(iso.date(from: instant))
            let point = try XCTUnwrap(analysis(snapshot(base: base, dateKey: key)).points.first)
            XCTAssertEqual(point.pairedIntervalMinutes, 180)
            XCTAssertEqual(point.dose2ToReportedFinalWakeMinutes, 120)
            XCTAssertEqual(point.sleepiness0To10, 0)
        }
    }

}
