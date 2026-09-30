import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardReplayAdapterTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    func night(metadata: String? = nil) -> DashboardNightAggregate {
        var row = DashboardNightAggregate(sessionDate: "2026-09-21", dose1Time: start,
            dose2Time: start.addingTimeInterval(10_800), dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0,
            events: [], morningCheckIn: nil, preSleepLog: nil, healthSummary: nil, whoopSummary: nil,
            duplicateClusterCount: 0, napSummary: .init(count: 0, totalMinutes: 0))
        row.sessionID = "durable-session"
        row.doseEvents = [.init(id: "d1", eventType: "dose1", timestamp: start, sessionDate: row.sessionDate,
                               metadata: metadata, sessionId: row.sessionID),
                          .init(id: "d2", eventType: "dose2", timestamp: start.addingTimeInterval(10_800),
                                sessionDate: row.sessionDate, sessionId: row.sessionID)]
        return row
    }
    func testReplayUsesDurableIdentityAndNeverCurrentReminderPreference() {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        let snapshot = model.replaySnapshot(for: night())
        XCTAssertEqual(snapshot.sessionID, "durable-session")
        XCTAssertEqual(snapshot.interval(.dose1ToDose2).minutes, 180)
        XCTAssertEqual(snapshot.interval(.reminderDeviation).state, .unavailable)
    }
    func testSavedReminderAndExplicitNoAlarmRemainSeparateFromDelivery() {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        let saved = model.replaySnapshot(for: night(metadata: "{\"reminder_interval_minutes\":165}"))
        XCTAssertEqual(saved.interval(.reminderDeviation).minutes, 15)
        XCTAssertNil(saved.interval(.deliveredAlarmToDose).minutes)
        let disabled = model.replaySnapshot(for: night(metadata: "{\"reminder_interval_minutes\":165,\"dose2_reminder_enabled\":false}"))
        XCTAssertNil(disabled.interval(.reminderDeviation).minutes)
    }
    func testAmbiguousRowsNeverSupplyUsableIntervals() {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        var row = night(); row.identityNeedsReview = true
        XCTAssertEqual(model.replaySnapshot(for: row).interval(.dose1ToDose2).state, .needsReview)
    }
    func testForeignDoseIdentityCannotBeRelabeledIntoTheSelectedSession() {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        var row = night()
        row.doseEvents[1] = .init(id: "foreign-d2", eventType: "dose2", timestamp: start.addingTimeInterval(10_800),
            sessionDate: row.sessionDate, sessionId: "other-session")
        let snapshot = model.replaySnapshot(for: row)
        XCTAssertEqual(snapshot.interval(.dose1ToDose2).state, .needsReview)
        XCTAssertNil(snapshot.interval(.dose1ToDose2).minutes)
        XCTAssertEqual(snapshot.markers.first { $0.id == "foreign-d2" }?.sessionID, "other-session")
    }
    func testMedicationSelectionUsesActualFormulationAndAmount() throws {
        let row = StoredMedicationEntry(id: "actual", sessionId: nil, sessionDate: "2026-09-21",
            medicationId: "unknown-name", doseMg: 15, takenAtUTC: start, doseUnit: "mg",
            formulation: "extended_release", localOffsetMinutes: 0, notes: nil, confirmedDuplicate: false, createdAt: start)
        let medication = try ReplayMedication(.quick(row))
        let marker = try XCTUnwrap(medication.marker(role: .medicationXR, sessionID: "selected-night"))
        XCTAssertEqual(marker.amountDescription, "15 mg")
        XCTAssertEqual(marker.sourceRecordID, "quick:actual")
        XCTAssertEqual(marker.sessionID, "selected-night")
        XCTAssertNil(medication.marker(role: .medicationIR, sessionID: "selected-night"))
    }
    func testUnknownMedicationTimeNeverBecomesRecordingTimeEndpoint() throws {
        let components = [try MedicationPresetComponent(id: UUID(), form: .tablet, strengthMilligrams: 5, unitCount: 1)]
        let preset = try MedicationPresetRevision(presetID: UUID(), revisionID: UUID(), supersedesRevisionID: nil,
            labelName: "Synthetic XR", ingredient: "Synthetic", releaseProfile: .extendedRelease,
            components: components, instructions: "Synthetic label", schedule: .scheduled,
            effectiveFrom: start, effectiveUntil: nil, recordedAt: start)
        let actual = try ConfirmedMedicationAdministration(id: UUID(), preset: preset, actualComponents: components,
            occurredAt: nil, precision: .unknown, timeZoneIdentifier: nil, utcOffsetSeconds: nil,
            confirmedAt: start, recordedAt: start)
        let medication = try ReplayMedication(.preset(actual))
        XCTAssertEqual(medication.amount, "5 mg")
        XCTAssertNil(medication.marker(role: .medicationXR, sessionID: "selected-night"))
        XCTAssertNil(medication.occurredAt)
    }
    func testDateScopedCoverageCannotSelectBetweenTwoSessions() async {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        var other = night(); other.sessionID = "second-session"
        model.nights = [night(), other]
        let result = await model.replayCoverage(sessionID: "durable-session")
        XCTAssertEqual(result.status, .needsReview)
    }
}
