import XCTest
@testable import DoseCore

final class DashboardReportProjectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func text(_ value: String) -> [String: Any] { ["type": "text", "text": value] }
    private func row(_ table: String, _ columns: [String: Any]) -> [String: Any] {
        ["sourceTable": table, "columns": columns]
    }
    private func snapshot(_ values: [DashboardDataset: [[String: Any]]]) throws -> CloudDashboardSnapshot {
        try CloudDashboardSnapshot(sourceID: "exact-phone-id", sequence: 1, capturedAt: now,
            sections: DashboardDataset.allCases.map {
                let rows = values[$0] ?? []
                return DashboardSnapshotSection(dataset: $0, rows: try JSONSerialization.data(withJSONObject: rows), rowCount: rows.count)
            })
    }
    private func dose(_ id: String, _ type: String, _ time: String, session: String? = "night") -> [String: Any] {
        row("dose_events", ["id": text(id), "event_type": text(type), "timestamp": text(time),
            "session_date": text("2026-03-07"), "session_id": session.map { text($0) } ?? ["type": "null"]])
    }
    func testMidnightDSTPairUsesActualElapsedTimeAndExactSource() throws {
        let s = try snapshot([.doseEvents: [dose("a", "dose1", "2026-03-08T01:30:00-05:00"),
            dose("b", "dose2", "2026-03-08T05:30:00-04:00")]])
        let p = try DashboardReportProjection(snapshot: s, now: now)
        XCTAssertEqual(p.sourceID, "exact-phone-id"); XCTAssertEqual(p.doseDays.first?.intervalMinutes, 180)
        XCTAssertEqual(p.doseDays.first?.treatmentDate, "2026-03-07"); XCTAssertEqual(p.validDosePairCount, 1)
    }
    func testDuplicateSkipIdentityAndNonpositiveIntervalsNeverBecomeZero() throws {
        let first = dose("a", "dose1", "2026-03-08T01:00:00Z")
        let second = dose("b", "dose2", "2026-03-08T04:00:00Z")
        for rows in [[first], [first, dose("skip", "dose2_skipped", "2026-03-08T04:00:00Z")],
                     [first, second, second], [first, second, dose("skip", "skip", "2026-03-08T04:00:00Z")],
                     [first, dose("b", "dose2", "2026-03-08T04:00:00Z", session: "other")],
                     [first, dose("b", "dose2", "2026-03-08T01:00:00Z")]] {
            let p = try DashboardReportProjection(snapshot: snapshot([.doseEvents: rows]), now: now)
            XCTAssertNil(p.doseDays.first?.intervalMinutes); XCTAssertEqual(p.validDosePairCount, 0)
        }
    }
    func testLegacyMedicationUsesOccurrenceOffsetNotTreatmentDateOrRecordedTime() throws {
        let r = row("medication_events", ["id": text("med"), "medication_id": text("custom"),
            "dose_mg": ["type": "integer", "integer": 10], "dose_unit": text("mg"),
            "taken_at_utc": text("2026-09-02T02:00:00Z"), "local_offset_minutes": ["type": "integer", "integer": -240],
            "session_date": text("1900-01-01"), "created_at": text("2026-09-03 12:00:00")])
        let p = try DashboardReportProjection(snapshot: snapshot([.medicationEntries: [r]]), now: now)
        XCTAssertEqual(p.medications.first?.calendarDate, "2026-09-01")
        XCTAssertNotEqual(p.medications.first?.occurredAt, p.medications.first?.recordedAt)
        XCTAssertEqual(p.medications.first?.amount, "10 mg")
    }
    func testCanonicalDecimalAndUnknownOccurrenceArePreserved() throws {
        let amount = Decimal(string: "1.12345678901234567890123456789")!
        let component = try MedicationPresetComponent(id: UUID(), form: .tablet, strengthMilligrams: amount, unitCount: 1)
        let preset = try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(), supersedesRevisionID: nil,
            labelName: "Synthetic", ingredient: "Synthetic", releaseProfile: .unknown, components: [component],
            instructions: "Synthetic", schedule: .asNeeded, effectiveFrom: now, effectiveUntil: nil, recordedAt: now)
        let actual = try ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: [component],
            occurredAt: nil, precision: .unknown, timeZoneIdentifier: nil, utcOffsetSeconds: nil, confirmedAt: now, recordedAt: now)
        let r = row("confirmed_medication_administrations", ["id": text(actual.id.uuidString),
            "payload": text(try MedicationPresetExportSnapshot.encode(actual))])
        let p = try DashboardReportProjection(snapshot: snapshot([.administrations: [r]]), now: now)
        XCTAssertEqual(p.medications.first?.amount, "\(amount) mg")
        XCTAssertNil(p.medications.first?.occurredAt); XCTAssertNil(p.medications.first?.calendarDate)
        XCTAssertEqual(p.medications.first?.recordedAt, now); XCTAssertEqual(p.unknownMedicationTimeCount, 1)
        let occurred = ISO8601DateFormatter().date(from: "2026-09-02T02:00:00Z")!
        let known = try ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: [component],
            occurredAt: occurred, precision: .approximate, timeZoneIdentifier: "America/New_York",
            utcOffsetSeconds: -14400, confirmedAt: now, recordedAt: now)
        let knownRow = row("confirmed_medication_administrations", ["id": text(known.id.uuidString),
            "payload": text(try MedicationPresetExportSnapshot.encode(known))])
        let knownProjection = try DashboardReportProjection(snapshot: snapshot([.administrations: [knownRow]]), now: now)
        XCTAssertEqual(knownProjection.medications.first?.calendarDate, "2026-09-01")
        XCTAssertEqual(knownProjection.medications.first?.timePrecision, "approximate")
    }
    func testWrongTableAndCorruptEnvelopeFailInsteadOfEmptySuccess() throws {
        var s = try snapshot([.medicationEntries: [row("dose_events", [:])]])
        XCTAssertThrowsError(try DashboardReportProjection(snapshot: s, now: now))
        s = try snapshot([:]); s.sections[0].rowCount = 9
        XCTAssertThrowsError(try DashboardReportProjection(snapshot: s, now: now))
    }
    func testSessionEvidencePreventsAmbiguousDateOnlyDosePairs() throws {
        func session(_ table: String, _ id: String, date: String = "2026-03-07") -> [String: Any] {
            row(table, ["session_id": text(id), "session_date": text(date)])
        }
        let first = dose("a", "dose1", "2026-03-08T01:00:00Z", session: nil)
        let second = dose("b", "dose2", "2026-03-08T04:00:00Z", session: nil)
        for evidence in [[session("sleep_sessions", "one"), session("sleep_sessions", "two")],
                         [session("sleep_sessions", "one"), session("current_session", "two")],
                         [session("sleep_sessions", "one"), session("current_session", "one", date: "2026-03-08")]] {
            let p = try DashboardReportProjection(snapshot: snapshot([.doseEvents: [first, second], .sessions: evidence]), now: now)
            XCTAssertNil(p.doseDays.first?.intervalMinutes); XCTAssertEqual(p.doseDays.first?.status, "Conflicting records")
        }
        let unique = [session("sleep_sessions", "one"), session("current_session", "one"),
                      session("sleep_sessions", "2026-03-07")]
        let p = try DashboardReportProjection(snapshot: snapshot([.doseEvents: [first, second], .sessions: unique]), now: now)
        XCTAssertEqual(p.doseDays.first?.intervalMinutes, 180)
    }
    func testSessionEvidenceCanConflictWithExplicitDoseIdentity() throws {
        let pair = [dose("a", "dose1", "2026-03-08T01:00:00Z"), dose("b", "dose2", "2026-03-08T04:00:00Z")]
        for (identity, date) in [("other", "2026-03-07"), ("night", "2026-03-08")] {
            let evidence = row("sleep_sessions", ["session_id": text(identity), "session_date": text(date)])
            let p = try DashboardReportProjection(snapshot: snapshot([.doseEvents: pair, .sessions: [evidence]]), now: now)
            XCTAssertNil(p.doseDays.first?.intervalMinutes)
        }
    }
}
