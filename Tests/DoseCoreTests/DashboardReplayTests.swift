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
    func providerMarker(_ kind: DashboardReplayMarker.Kind, _ seconds: Double,
                        state: DashboardMetricState = .available, captured: Double = 40_000) -> DashboardReplayMarker {
        .init(id: kind.rawValue, sessionID: "session", kind: kind, occurredAt: base.addingTimeInterval(seconds),
            source: "Original provider endpoint", evidenceQuality: .init(state: state, reason: "Provider capture policy",
                capturedAt: base.addingTimeInterval(captured), providerRecordID: "original-provider-record"))
    }
    func testStaleProviderIntervalRetainsRawEvidenceButRequiresPartialOptIn() throws {
        let source = snapshot([marker(.dose1, 0), marker(.dose2, 600), providerMarker(.deviceSleepEnd, 1200, state: .partial)])
        let value = source.interval(.dose2ToDeviceEnd)
        XCTAssertEqual(value.state, .partial); XCTAssertEqual(value.minutes, 10)
        XCTAssertNil(value.eligibleMinutes())
        XCTAssertEqual(value.eligibleMinutes(includePartial: true), 10)
        XCTAssertEqual(source.interval(.dose1ToDose2).eligibleMinutes(), 10)
        let decoded = try JSONDecoder().decode(DashboardReplaySnapshot.self, from: source.jsonData())
        XCTAssertEqual(decoded.markers.last?.evidenceQuality?.providerRecordID, "original-provider-record")
        XCTAssertEqual(decoded.markers.last?.occurredAt, base.addingTimeInterval(1200))
        XCTAssertTrue(source.csv.contains("evidence_state"))
        XCTAssertTrue(source.csv.contains("original-provider-record"))
    }
    func testMissingProviderQualityIsPartialAndInvalidQualityCannotBecomeAvailable() {
        let legacy = snapshot([marker(.dose2, 0), marker(.deviceSleepEnd, 600)]).interval(.dose2ToDeviceEnd)
        XCTAssertEqual(legacy.state, .partial); XCTAssertEqual(legacy.minutes, 10)
        for state in [DashboardMetricState.unavailable, .notApplicable, .needsReview] {
            let value = snapshot([marker(.dose2, 0), providerMarker(.deviceSleepEnd, 600, state: state)]).interval(.dose2ToDeviceEnd)
            XCTAssertEqual(value.state, state); XCTAssertNil(value.minutes)
        }
        for date in [Double.nan, Double.infinity, 70_000] {
            XCTAssertEqual(snapshot([marker(.dose2, 0), providerMarker(.deviceSleepEnd, 600, captured: date)])
                .interval(.dose2ToDeviceEnd).state, .needsReview)
        }
        XCTAssertEqual(snapshot([marker(.dose2, 700), providerMarker(.deviceSleepEnd, 600, state: .partial)])
            .interval(.dose2ToDeviceEnd).state, .needsReview)
        XCTAssertEqual(snapshot([providerMarker(.deviceSleepEnd, 600, state: .partial)], omitted: true)
            .interval(.dose2ToDeviceEnd).state, .notApplicable)
    }
    func testWHOOPOriginalEpisodeEndNeverBecomesLastObservedSleepOrFinalWake() {
        let source = snapshot([marker(.dose2, 0), providerMarker(.whoopEpisodeStart, -600), providerMarker(.whoopEpisodeEnd, 1200)])
        XCTAssertEqual(source.interval(.dose2ToWHOOPepisodeEnd).eligibleMinutes(), 20)
        XCTAssertEqual(source.interval(.dose2ToDeviceEnd).state, .unavailable)
        XCTAssertEqual(source.interval(.dose2ToReportedWake).state, .unavailable)
        XCTAssertTrue(source.csv.contains("WHOOP original episode end"))
    }
    func testExplicitDosePairResolvesOnlyChosenCanonicalOccurrencesAndRetainsRawMarkers() throws {
        let source = snapshot([marker(.dose1, 0), marker(.dose2, 600, id: "first-d2"),
            marker(.dose2, 1200, id: "second-d2"), marker(.extraDose, 1800)])
        XCTAssertEqual(source.interval(.dose1ToDose2).state, .needsReview)
        let selected = try source.selectingDosePair(dose1ID: "dose1", dose2ID: "second-d2")
        XCTAssertEqual(selected.interval(.dose1ToDose2).eligibleMinutes(), 20)
        XCTAssertEqual(selected.interval(.dose1ToDose2).endID, "second-d2")
        XCTAssertEqual(selected.markers, source.markers)
        XCTAssertEqual(selected.position(of: base.addingTimeInterval(1800), alignment: .dose2), 10)
        XCTAssertEqual(try selected.addingSelectedEndpoints([]).withViewContext("retained").dosePairSelection, selected.dosePairSelection)
        let decoded = try JSONDecoder().decode(DashboardReplaySnapshot.self, from: selected.jsonData())
        XCTAssertEqual(decoded.dosePairSelection, selected.dosePairSelection)
        XCTAssertTrue(selected.csv.contains("selected_dose2_id,second-d2"))
        XCTAssertEqual(try selected.selectingDosePair(dose1ID: nil, dose2ID: nil).interval(.dose1ToDose2).state, .needsReview)
    }
    func testDosePairCannotRelabelForeignExtraFutureOrReversedOccurrences() throws {
        let candidates = [marker(.dose1, 0), marker(.dose2, 600), marker(.extraDose, 900),
            marker(.dose2, 1200, id: "foreign", session: "other"), marker(.dose2, 70_000, id: "future"),
            marker(.dose2, -1, id: "reversed")]
        let source = snapshot(candidates)
        for id in ["extraDose", "foreign", "future", "reversed", "missing", "dose1"] {
            XCTAssertThrowsError(try source.selectingDosePair(dose1ID: "dose1", dose2ID: id))
        }
        XCTAssertThrowsError(try source.selectingDosePair(dose1ID: "dose1", dose2ID: nil))
        let omitted = try snapshot(candidates, omitted: true).selectingDosePair(dose1ID: "dose1", dose2ID: "dose2")
        XCTAssertEqual(omitted.interval(.dose1ToDose2).state, .needsReview)
        XCTAssertEqual(snapshot([marker(.dose1, 0), marker(.dose2, 600)]).interval(.dose1ToDose2).referenceVersion,
                       "dose_spacing_reference_v1_150_240_minutes")
    }
    func testInvalidOrFutureDoseCannotAnchorAChart() {
        for offset in [Double.nan, Double.infinity, 70_000] {
            XCTAssertNil(snapshot([marker(.dose1, offset)]).position(of: base, alignment: .dose1))
        }
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
    func testExplicitSelectionRetainsSourceIdentityAndRejectsDoseReplacement() throws {
        let source = DashboardReplayMarker(id: "xr:selected", sessionID: "session", kind: .medicationXR,
            occurredAt: base, source: "Explicitly selected administration", sourceRecordID: "original-xr",
            medicationID: "medicine", formulation: "extendedRelease", amountDescription: "15 mg")
        let selected = try snapshot([marker(.mainSleepStart, 900)]).addingSelectedEndpoints([source])
        XCTAssertEqual(selected.markers.first?.sourceRecordID, "original-xr")
        XCTAssertEqual(selected.markers.first?.amountDescription, "15 mg")
        XCTAssertTrue(selected.csv.contains("original-xr"))
        XCTAssertThrowsError(try selected.addingSelectedEndpoints([marker(.dose1, 0)]))
        XCTAssertThrowsError(try selected.addingSelectedEndpoints([marker(.napEnd, 0, session: "other")]))
    }
    func testExtraAdministrationRequiresPairReview() {
        let snap = snapshot([marker(.dose1, 0), marker(.dose2, 600), marker(.extraDose, 900)])
        XCTAssertEqual(snap.interval(.dose1ToDose2).state, .needsReview)
        XCTAssertNil(snap.interval(.dose1ToDose2).minutes)
    }
    func testMainEpisodeBandsPreserveUnknownAndConflictInsteadOfInventingStages() throws {
        let intervals = [RecordedSleepInterval(start: base, end: base.addingTimeInterval(300), asleep: true),
                         .init(start: base.addingTimeInterval(200), end: base.addingTimeInterval(400), asleep: false),
                         .init(start: base.addingTimeInterval(500), end: base.addingTimeInterval(600), asleep: true)]
        let snap = DashboardReplaySnapshot(sessionID: "session", treatmentDate: "2026-09-21", asOf: base.addingTimeInterval(700),
            timeZoneID: "UTC", sourcePolicy: "Apple Health", filterDescription: "test", markers: [], mainEpisodeIntervals: intervals)
        let evidence = try XCTUnwrap(snap.mainEpisodeEvidence)
        XCTAssertEqual(evidence.slices.map(\.state), [.asleep, .conflict, .awake, .unmeasured, .asleep])
        XCTAssertEqual(evidence.conflictMinutes, 100 / 60, accuracy: 0.0001)
        XCTAssertEqual(evidence.coverage.unmeasuredMinutes, 200 / 60, accuracy: 0.0001)
        XCTAssertTrue(snap.csv.contains("main_episode_interval_start"))
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
