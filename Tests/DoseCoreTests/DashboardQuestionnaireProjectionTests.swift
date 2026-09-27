import XCTest
@testable import DoseCore

final class DashboardQuestionnaireProjectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func text(_ value: String) -> [String: Any] { ["type": "text", "text": value] }
    private func row(_ table: String, _ values: [String: Any]) -> [String: Any] { ["sourceTable": table, "columns": values] }
    private func session(_ id: String = "night", _ date: String = "2026-09-01") -> [String: Any] {
        row("sleep_sessions", ["session_id": text(id), "session_date": text(date)])
    }
    private func morning(_ id: String = "m", quality: [String: Any]? = nil) -> [String: Any] {
        var values: [String: Any] = ["id": text(id), "session_id": text("night"), "session_date": text("2026-09-01")]
        if let quality { values["sleep_quality"] = quality }
        return row("morning_checkins", values)
    }
    private func pre(_ state: String, identity: String? = "night") -> [String: Any] {
        row("pre_sleep_logs", ["id": text("p"), "session_id": identity.map(text) ?? ["type": "null"], "completion_state": text(state)])
    }
    private func outcome(_ payload: String, version: String = "night_outcome.v1") -> [String: Any] {
        row("checkin_submissions", ["id": text("night_outcome:night"), "source_record_id": text("night"),
            "session_id": text("night"), "session_date": text("2026-09-01"), "checkin_type": text("night_outcome"),
            "questionnaire_version": text(version), "responses_json": text(payload)])
    }
    private func project(_ content: [DashboardDataset: [[String: Any]]], later: Date? = nil) throws -> DashboardQuestionnaireProjection {
        let snapshot = CloudDashboardSnapshot(sourceID: "phone", sequence: 1, capturedAt: now,
            sections: try DashboardDataset.allCases.map {
                let values = content[$0] ?? []
                return DashboardSnapshotSection(dataset: $0, rows: try JSONSerialization.data(withJSONObject: values), rowCount: values.count)
            })
        return try DashboardQuestionnaireProjection(snapshot: snapshot, now: later ?? now)
    }
    func testMissingRatingsStayMissingAndStoredDefaultIsNotConfirmedCompletion() throws {
        let missing = try project([.sessions: [session()], .morning: [morning()]])
        XCTAssertEqual(missing.days[0].morning, .recorded); XCTAssertNil(missing.days[0].recordedSleepQuality)
        let stored = try project([.morning: [morning(quality: ["type": "real", "real": 3])]])
        XCTAssertEqual(stored.days[0].recordedSleepQuality, 3)
        XCTAssertEqual(stored.days[0].sleepQualityProvenance, "Stored rating; freshness and confirmation unknown")
        XCTAssertEqual(stored.days[0].preSleep, .missing); XCTAssertNil(stored.days[0].dose2WakeMethod)
    }
    func testPreSleepCoverageKeepsCompletePartialSkippedAndUnassignedSeparate() throws {
        for (raw, state) in [("complete", DashboardQuestionnaireStatus.complete), ("partial", .partial), ("skipped", .skipped), ("future", .unavailable)] {
            let p = try project([.sessions: [session()], .preSleep: [pre(raw)]])
            XCTAssertEqual(p.days[0].preSleep, state)
        }
        let p = try project([.sessions: [session()], .preSleep: [pre("complete", identity: nil)]])
        XCTAssertEqual(p.unassignedPreSleepCount, 1); XCTAssertTrue(p.days.isEmpty)
    }
    func testDuplicatesAndIdentityAmbiguitySuppressAnswers() throws {
        let m = morning(quality: ["type": "integer", "integer": 4])
        for content: [DashboardDataset: [[String: Any]]] in [
            [.morning: [m, morning("other")]],
            [.morning: [m], .sessions: [session(), session("other")]],
            [.morning: [m], .sessions: [session("night", "2026-09-02")]]] {
            let day = try XCTUnwrap(project(content).days.first { $0.treatmentDate == "2026-09-01" })
            XCTAssertEqual(day.morning, .conflict); XCTAssertNil(day.recordedSleepQuality)
        }
    }
    func testExplicitOutcomeAnswersAndUnknownAreNotLegacyInference() throws {
        let valid = #"{"answers":{"wakeMethod":"alarm","dayType":"workday"},"recordedAt":"2026-09-01T12:00:00Z","revisions":[]}"#
        let day = try project([.normalizedAnswers: [outcome(valid)]]).days[0]
        XCTAssertEqual(day.nightOutcome, .recorded); XCTAssertEqual(day.dose2WakeMethod, .alarm)
        XCTAssertEqual(day.followingDay, .workday)
        let unknown = #"{"answers":{"wakeMethod":"unknown","dayType":"unknown"},"recordedAt":"2026-09-01T12:00:00Z","revisions":[]}"#
        let other = try project([.normalizedAnswers: [outcome(unknown)]]).days[0]
        XCTAssertNil(other.dose2WakeMethod); XCTAssertNil(other.followingDay)
    }
    func testUnsupportedMalformedAndPostCaptureOutcomeNeverBecomeAnswers() throws {
        let future = #"{"answers":{"wakeMethod":"alarm","dayType":"workday"},"recordedAt":"2099-09-01T12:00:00Z","revisions":[]}"#
        for r in [outcome("{}"), outcome("{}", version: "night_outcome.v2"), outcome(future)] {
            let day = try project([.normalizedAnswers: [r]], later: now.addingTimeInterval(86400)).days[0]
            XCTAssertEqual(day.nightOutcome, .unavailable); XCTAssertNil(day.dose2WakeMethod)
        }
    }
    func testNormalizedCopyDoesNotDuplicateMorningAndWrongTableFails() throws {
        let normalized = row("checkin_submissions", ["id": text("morning:m"), "source_record_id": text("m"),
            "session_id": text("night"), "session_date": text("2026-09-01"), "checkin_type": text("morning")])
        let p = try project([.morning: [morning(quality: ["type": "real", "real": 4])], .normalizedAnswers: [normalized]])
        XCTAssertEqual(p.days.count, 1); XCTAssertEqual(p.days[0].morning, .recorded)
        XCTAssertThrowsError(try project([.morning: [session()]]))
    }
    func testIndependentAndSessionOnlyRowsDoNotCreateQuestionnaireDates() throws {
        let orphan = row("medication_events", ["session_id": ["type": "null"], "session_date": ["type": "null"]])
        let p = try project([.sessions: [session()], .medicationEntries: [orphan]])
        XCTAssertTrue(p.days.isEmpty)
        let unassigned = row("morning_checkins", ["id": text("orphan"), "session_id": ["type": "null"]])
        XCTAssertEqual(try project([.morning: [unassigned]]).unassignedSourceRowCount, 1)
    }
    func testNormalizedPreSleepLinkPreservesNilContextWithoutDoubleCounting() throws {
        let normalized = row("checkin_submissions", ["id": text("pre_night:p"), "source_record_id": text("p"),
            "session_id": ["type": "null"], "session_date": text("2026-09-01"), "checkin_type": text("pre_night")])
        let p = try project([.preSleep: [pre("complete", identity: nil)], .normalizedAnswers: [normalized]])
        XCTAssertEqual(p.days.count, 1); XCTAssertEqual(p.days[0].preSleep, .complete)
        XCTAssertEqual(p.unassignedSourceRowCount, 0); XCTAssertEqual(p.selected(count: 0, timeZone: .gmt).count, 1)
    }
}
