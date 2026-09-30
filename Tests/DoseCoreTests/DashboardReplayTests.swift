import XCTest
@testable import DoseCore

final class DashboardReplayTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    func marker(_ kind: DashboardReplayMarker.Kind, _ seconds: Double, id: String? = nil,
                session: String = "session") -> DashboardReplayMarker {
        .init(id: id ?? kind.rawValue, sessionID: session, kind: kind, occurredAt: base.addingTimeInterval(seconds),
              recordedAt: base.addingTimeInterval(50_000), source: "patient_report")
    }
    func snapshot(_ markers: [DashboardReplayMarker], omitted: Bool = false, resolved: Bool = true) -> DashboardReplaySnapshot {
        .init(sessionID: "session", treatmentDate: "2026-09-21", asOf: base.addingTimeInterval(60_000),
              timeZoneID: "America/New_York", sourcePolicy: "Apple Health main episode", filterDescription: "28 days",
              markers: markers, dose2NotTaken: omitted, identityResolved: resolved)
    }
    func testOccurrenceNotRecordedAtDrivesElapsedAndLineage() {
        let value = snapshot([marker(.dose1, 0), marker(.dose2, 10_800)]).interval(.dose1ToDose2)
        XCTAssertEqual(value.minutes, 180); XCTAssertEqual(value.state, .available)
        XCTAssertEqual(value.startID, "dose1"); XCTAssertEqual(value.endID, "dose2")
    }
    func testOmissionAndMissingAreDifferentAndNeverZero() {
        let one = [marker(.dose1, 0)]
        XCTAssertEqual(snapshot(one, omitted: true).interval(.dose1ToDose2).state, .notApplicable)
        XCTAssertEqual(snapshot(one).interval(.dose1ToDose2).state, .unavailable)
        XCTAssertNil(snapshot(one).interval(.dose1ToDose2).minutes)
    }
    func testConflictingIdentityDuplicateSlotAndNonpositiveRequireReview() {
        for markers in [[marker(.dose1, 0), marker(.dose2, 100, session: "other")],
                        [marker(.dose1, 0), marker(.dose2, 100), marker(.dose2, 200, id: "extra")],
                        [marker(.dose1, 100), marker(.dose2, 100)],
                        [marker(.dose1, 200), marker(.dose2, 100)]] {
            XCTAssertEqual(snapshot(markers).interval(.dose1ToDose2).state, .needsReview)
        }
        XCTAssertEqual(snapshot([marker(.dose1, 0)], resolved: false).interval(.dose1ToDose2).state, .needsReview)
    }
    func testExplicitOmissionContradictingAdministrationRequiresReview() {
        XCTAssertEqual(snapshot([marker(.dose1, 0), marker(.dose2, 100)], omitted: true)
            .interval(.dose1ToDose2).state, .needsReview)
    }
    func testSignedRequiredWakeAndReminderDeviation() {
        let snap = snapshot([marker(.dose2, 100), marker(.requiredWake, 0), marker(.reminder, 200)])
        XCTAssertEqual(snap.interval(.dose2ToRequiredWake).minutes!, -100 / 60, accuracy: 0.0001)
        XCTAssertEqual(snap.interval(.reminderDeviation).minutes!, -100 / 60, accuracy: 0.0001)
    }
    func testAllCuratedPresetsUseExplicitEndpoints() {
        for preset in DashboardIntervalPreset.allCases {
            let snap = snapshot([marker(preset.endpoints.0, 0), marker(preset.endpoints.1, 600)])
            if preset == .dose2ToSleep { XCTAssertNil(snap.interval(preset).minutes) }
            else { XCTAssertEqual(snap.interval(preset).minutes, 10, preset.rawValue) }
        }
    }
    func testReturnToSleepRequiresReviewedBoundaryEvidence() {
        let snap = snapshot([marker(.dose2, 100), marker(.returnSleep, 200)])
        XCTAssertEqual(snap.interval(.dose2ToSleep).state, .unavailable)
    }
    func testReviewedReturnBoundaryAndCSVAccounting() throws {
        let end = base.addingTimeInterval(900), checked = base.addingTimeInterval(1000)
        let window = ReviewedSleepWindow(sessionID: "session", start: base, end: end,
            entryTimeZone: TimeZone(secondsFromGMT: 0)!, reviewedAt: checked)
        func sample(_ id: String, _ a: Double, _ b: Double, _ stage: SleepEvidenceSample.Stage) -> SleepEvidenceSample {
            .init(sampleID: id, start: base.addingTimeInterval(a), end: base.addingTimeInterval(b),
                  rawCategory: 99, stage: stage, origin: .init(sourceName: "test", bundleIdentifier: nil))
        }
        let evidence = try XCTUnwrap(SleepEvidenceResolution.calculate(start: base, end: end,
            samples: [sample("a", 0, 200, .asleep), sample("b", 200, 400, .awake), sample("c", 400, 900, .asleep)]))
        let projection = try XCTUnwrap(ReviewedNightSleepProjection.calculate(window: window, evidence: evidence, generatedAt: checked))
        func snap(_ dose: Double) -> DashboardReplaySnapshot {
            .init(sessionID: "session", treatmentDate: "2026-09-21", asOf: checked, timeZoneID: "UTC",
                  sourcePolicy: "reviewed", filterDescription: "test", markers: [marker(.dose2, dose), marker(.returnSleep, 400)],
                  reviewedProjection: projection)
        }
        XCTAssertEqual(snap(300).interval(.dose2ToSleep).minutes!, 100 / 60, accuracy: 0.0001)
        XCTAssertEqual(snap(100).interval(.dose2ToSleep).state, .needsReview)
        XCTAssertTrue(snap(300).csv.contains("conflict_subset_minutes"))
        XCTAssertTrue(snap(300).csv.contains("band_start,band_end,state"))
    }
    func testFutureAndDuplicateIDsAreRejected() {
        XCTAssertEqual(snapshot([marker(.dose1, 0), marker(.dose2, 70_000)]).interval(.dose1ToDose2).state, .needsReview)
        XCTAssertEqual(snapshot([marker(.dose1, 0, id: "same"), marker(.dose2, 100, id: "same")])
            .interval(.dose1ToDose2).state, .needsReview)
    }
    func testAlignmentUsesElapsedUTCAndDoesNotUseCaptureTime() {
        let snap = snapshot([marker(.dose1, 0), marker(.dose2, 10_800)])
        XCTAssertEqual(snap.position(of: base.addingTimeInterval(14_400), alignment: .dose1), 240)
        XCTAssertEqual(snap.position(of: base.addingTimeInterval(14_400), alignment: .dose2), 60)
        XCTAssertNil(snapshot([]).position(of: base, alignment: .dose2))
    }
    func testSnapshotRoundTripAndCSVProtectFormulaLabels() throws {
        let snap = DashboardReplaySnapshot(sessionID: "=malicious", treatmentDate: "2026-09-21", asOf: base,
            timeZoneID: "UTC", sourcePolicy: "Apple Health", filterDescription: "custom, bounds", markers: [])
        let data = try snap.jsonData()
        XCTAssertEqual(try JSONDecoder().decode(DashboardReplaySnapshot.self, from: data), snap)
        XCTAssertTrue(snap.csv.contains("'\u{200B}=malicious"))
        XCTAssertEqual(try ReportCSV.rows(snap.csv)[1][1], "=malicious")
        XCTAssertTrue(snap.csv.contains("derivation_version"))
    }
}
