import XCTest
import Combine
import DoseCore
@testable import DoseTap

@MainActor
final class DashboardReplayAdapterTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    func night(metadata: String? = nil, events: [DoseTap.StoredSleepEvent] = []) -> DashboardNightAggregate {
        var row = DashboardNightAggregate(sessionDate: "2026-09-21", dose1Time: start,
            dose2Time: start.addingTimeInterval(10_800), dose2Skipped: false, snoozeCount: 0, extraDoseCount: 0,
            events: events, morningCheckIn: nil, preSleepLog: nil, healthSummary: nil, whoopSummary: nil,
            duplicateClusterCount: 0, napSummary: .init(count: 0, totalMinutes: 0))
        row.sessionID = "durable-session"
        row.stableID = "session:durable-session"
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
    func testSharedSelectionStoresCanonicalObservationAndMapsRawSessionOnlyForLookup() {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        model.nights = [night()]; model.selectReplayID("durable-session")
        XCTAssertEqual(model.inspection.selectedObservationID, "session:durable-session")
        XCTAssertEqual(model.selectedReplayID, "durable-session")
        model.nights = []
        XCTAssertNil(model.selectedReplayID)
        XCTAssertEqual(model.inspection.selectedObservationID, "session:durable-session")
        model.selectReplayID("unknown")
        XCTAssertEqual(model.inspection.selectedObservationID, "session:durable-session")
    }
    func testPreSleepCompletionAndSkipNeverBecomeConfirmedLightsOut() {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        for note in ["Pre-sleep check completed", "Pre-sleep check skipped"] {
            let snap = model.replaySnapshot(for: night(events: [.init(id: "check", eventType: "lightsOut", timestamp: start,
                sessionDate: "2026-09-21", notes: note)]))
            XCTAssertEqual(snap.markers.first { $0.id == "event:check" }?.source, note + "; not confirmed lights out")
            XCTAssertFalse(snap.markers.contains { $0.kind == .mainSleepStart })
        }
    }
    func testHistoricalWakeAndFilteredExportPreserveSourceIdentity() throws {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        let target = start.addingTimeInterval(20_000)
        let warning: [String: Any] = ["sessionId": "durable-session", "revision": UUID().uuidString,
            "wakeDate": "2026-09-21", "timeZoneIdentifier": "UTC", "requiredWake": target.timeIntervalSinceReferenceDate,
            "targetAt": start.timeIntervalSinceReferenceDate, "target": WorkWarningTarget.doseTarget.rawValue]
        let metadata = String(decoding: try JSONSerialization.data(withJSONObject: ["work_warning_acknowledgement": warning]), as: UTF8.self)
        let row = night(metadata: metadata), snap = model.replaySnapshot(for: night(metadata: metadata))
        XCTAssertEqual(snap.markers.first { $0.kind == .requiredWake }?.occurredAt, target)
        let frozen = ReplayInspectionExport(scope: "Filtered", selectedObservationID: row.id,
            rows: [.init(observationID: row.id, snapshot: snap, recordedWakeTarget: model.replayWakeTarget(for: row))])
        let decoded = try JSONDecoder().decode(ReplayInspectionExport.self, from: frozen.jsonData())
        XCTAssertEqual(decoded.rows.first?.recordedWakeTarget.sources.first?.eventID, "d1")
        XCTAssertEqual(decoded.rows.first?.observationID, row.id)
        XCTAssertTrue(frozen.csv.contains("required_wake_state,available"))
        XCTAssertTrue(frozen.csv.contains("postdose_endpoint,state,elapsed_minutes"))
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
    func presentationModel() -> DashboardAnalyticsModel {
        DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) },
            sessionRepo: SessionRepository(storage: .inMemory()), providerAccess: DashboardProviderAccess())
    }
    func testPresentationAndExplicitEndpointsSurviveViewReconstruction() async throws {
        let model = presentationModel()
        let endpoint = DashboardReplayMarker(id: "chosen", sessionID: "durable-session", kind: .napEnd,
            occurredAt: start, source: "Explicitly selected")
        model.replayPresentation.open(initialMode: .medication)
        model.replayPresentation.endpointSelections = ["durable-session": [endpoint]]
        model.replayPresentation.preset = .napToSleep
        model.replayPresentation.alignment = .dose2
        model.replayPresentation.intervalMode = "Distribution"
        await model.replayCoverageState.refresh(sessionDate: "2026-09-21") { _ in .init(status: .available, checkedAt: self.start) }
        _ = DashboardReplayView(model: model)
        _ = DashboardReplayView(model: model, initialMode: .replay)
        model.replayPresentation.open(initialMode: .replay)
        XCTAssertEqual(model.replayPresentation.mode, .medication)
        XCTAssertEqual(model.replayPresentation.endpointSelections["durable-session"], [endpoint])
        XCTAssertEqual(model.replayPresentation.preset, .napToSleep)
        XCTAssertEqual(model.replayPresentation.alignment, .dose2)
        XCTAssertEqual(model.replayPresentation.intervalMode, "Distribution")
        XCTAssertEqual(model.replayCoverageState.result?.checkedAt, start)
    }
    func testPresentationAndFiltersRetainCoverageButCanonicalSelectionInvalidatesIt() async {
        let model = presentationModel()
        model.inspection.selectedObservationID = "session:first"
        await model.replayCoverageState.refresh(sessionDate: "2026-09-21") { _ in .init(status: .available, checkedAt: self.start) }
        model.replayPresentation.mode = .medication
        model.replayPresentation.preset = .foodToDose1
        model.replayPresentation.alignment = .dose1
        model.inspection.includePartialMetrics = true
        model.inspection.selectedObservationID = "session:first"
        XCTAssertEqual(model.replayCoverageState.result?.checkedAt, start)
        model.inspection.selectedObservationID = "session:second"
        XCTAssertNil(model.replayCoverageState.result)
    }
    func testSourcePublicationAndCutoffChangesInvalidateCoverageOffscreen() async {
        let model = presentationModel()
        let changes: [() -> Void] = [
            { model.nights = [self.night()] },
            { model.reportingAsOf = model.reportingAsOf.addingTimeInterval(1) },
            { model.reportingTimeZone = TimeZone(secondsFromGMT: 0)! },
            { model.sleepSource = .whoop }
        ]
        model.reportingTimeZone = TimeZone(identifier: "America/New_York")!
        for change in changes {
            await model.replayCoverageState.refresh(sessionDate: "2026-09-21") { _ in .init(status: .available, checkedAt: self.start) }
            change()
            XCTAssertNil(model.replayCoverageState.result)
        }
    }
    func testInjectedRepositoryAndProviderInvalidationUseTheirExactOwners() async {
        let model = presentationModel(), other = SessionRepository(storage: .inMemory())
        let marker = DashboardReplayMarker(id: "chosen", sessionID: "durable-session", kind: .napEnd,
            occurredAt: start, source: "Explicitly selected")
        model.replayPresentation.endpointSelections = ["durable-session": [marker]]
        await model.replayCoverageState.refresh(sessionDate: "2026-09-21") { _ in .init(status: .available, checkedAt: self.start) }
        other.sessionDidChange.send()
        XCTAssertNotNil(model.replayCoverageState.result)
        model.providerAccess.invalidate(.health)
        XCTAssertNil(model.replayCoverageState.result)
        XCTAssertEqual(model.replayPresentation.endpointSelections["durable-session"], [marker])
        await model.replayCoverageState.refresh(sessionDate: "2026-09-21") { _ in .init(status: .available, checkedAt: self.start) }
        model.sessionRepo.sessionDidChange.send()
        XCTAssertNil(model.replayCoverageState.result)
        XCTAssertTrue(model.replayPresentation.endpointSelections.isEmpty)
        XCTAssertNotNil(model.replayPresentation.selectionNotice)
    }
    func testDateScopedCoverageCannotSelectBetweenTwoSessions() async {
        let model = DashboardAnalyticsModel(now: { self.start.addingTimeInterval(50_000) })
        var other = night(); other.sessionID = "second-session"
        model.nights = [night(), other]
        let result = await model.replayCoverage(sessionID: "durable-session")
        XCTAssertEqual(result.status, .needsReview)
    }
    func testProviderQualityRetainsRawIntervalButDefaultsToExcluded() throws {
        let model = presentationModel(); var row = night()
        row.healthSummary = .init(date: start, bedTime: start, sleepOnset: start, firstWake: nil,
            finalWake: start.addingTimeInterval(14_400), ttfwMinutes: nil, totalSleepMinutes: 0, wakeCount: 0, source: "Synthetic")
        model.nights = [row]
        let snapshot = model.replaySnapshot(for: row), interval = snapshot.interval(.dose2ToDeviceEnd)
        XCTAssertEqual(interval.state, .partial); XCTAssertEqual(interval.minutes, 60)
        XCTAssertNil(interval.eligibleMinutes()); XCTAssertEqual(interval.eligibleMinutes(includePartial: true), 60)
        XCTAssertEqual(snapshot.interval(.dose1ToDose2).eligibleMinutes(), 180)
        XCTAssertEqual(snapshot.markers.first { $0.kind == .deviceSleepEnd }?.evidenceQuality?.providerRecordID, row.healthSummary?.id)
        let first = try XCTUnwrap(model.replayComparison(for: snapshot, outcome: .mainSleep, preset: .dose1ToDose2))
        XCTAssertEqual(first.metric.value, 0); XCTAssertEqual(first.metric.state, .partial); XCTAssertFalse(first.paired)
        model.inspection.includePartialMetrics = true
        let included = try XCTUnwrap(model.replayComparison(for: snapshot, outcome: .mainSleep, preset: .dose1ToDose2))
        XCTAssertEqual(included.y, 0); XCTAssertTrue(included.paired)
    }
    func testTimedSleepinessZeroIsNotMissingAndUntimedIsReview() throws {
        let model = presentationModel(); var row = night(); var diary = NightOutcomeDiary()
        diary.sleepiness = 0; diary.assessedAt = start.addingTimeInterval(30_000); row.outcome = diary; model.nights = [row]
        let snap = model.replaySnapshot(for: row)
        let paired = try XCTUnwrap(model.replayComparison(for: snap, outcome: .sleepiness, preset: .dose1ToDose2))
        XCTAssertTrue(paired.paired); XCTAssertEqual(paired.y, 0); XCTAssertEqual(paired.sourceRecordID, row.sessionID)
        XCTAssertEqual(paired.observedAt, diary.assessedAt); XCTAssertTrue(paired.metric.reason.contains("not ESS"))
        row.outcome?.assessedAt = nil; model.nights = [row]
        XCTAssertEqual(model.replayComparison(for: snap, outcome: .sleepiness, preset: .dose1ToDose2)?.metric.state, .needsReview)
        row.outcome = diary; row.outcomeReadFailed = true; model.nights = [row]
        XCTAssertNil(model.replayComparison(for: snap, outcome: .sleepiness, preset: .dose1ToDose2)?.y)
    }
    func testComparisonExportFreezesExactPairedValuesAndSourceIdentity() throws {
        let model = presentationModel(); var row = night(); var diary = NightOutcomeDiary()
        diary.sleepiness = 2; diary.assessedAt = start.addingTimeInterval(30_000); row.outcome = diary; model.nights = [row]
        let snap = try model.replaySnapshot(for: row).selectingDosePair(dose1ID: "d1", dose2ID: "d2")
        let comparison = try XCTUnwrap(model.replayComparison(for: snap, outcome: .sleepiness, preset: .dose1ToDose2))
        let frozen = ReplayInspectionExport(scope: "Paired", selectedObservationID: row.id, rows: [.init(observationID: row.id,
            snapshot: snap, recordedWakeTarget: model.replayWakeTarget(for: row), comparison: comparison)])
        model.nights = []
        let decoded = try JSONDecoder().decode(ReplayInspectionExport.self, from: frozen.jsonData())
        XCTAssertEqual(decoded.rows.first?.comparison?.x, 180); XCTAssertEqual(decoded.rows.first?.comparison?.y, 2)
        XCTAssertEqual(decoded.rows.first?.snapshot.dosePairSelection?.dose1ID, "d1")
        XCTAssertEqual(comparison.binLower, 180); XCTAssertTrue(frozen.csv.contains(comparison.csv))
        XCTAssertTrue(frozen.csv.contains("night-outcome.sleepiness_0_10.v1"))
        XCTAssertEqual(decoded.rows.first?.comparison?.referenceVersion, comparison.referenceVersion)
    }
    func testDosePairAndComparedOutcomeSurvivePresentationButNotRecordChange() {
        let model = presentationModel()
        model.replayPresentation.dosePairs["durable-session"] = .init(dose1ID: "d1", dose2ID: "d2")
        model.replayPresentation.comparedOutcome = .sleepiness; model.replayPresentation.selectedBinLower = 180
        model.replayPresentation.open(initialMode: .intervals); model.replayPresentation.mode = .medication
        XCTAssertEqual(model.replayPresentation.dosePairs["durable-session"]?.dose2ID, "d2")
        XCTAssertEqual(model.replayPresentation.comparedOutcome, .sleepiness)
        model.sessionRepo.sessionDidChange.send()
        XCTAssertTrue(model.replayPresentation.dosePairs.isEmpty)
        XCTAssertEqual(model.replayPresentation.selectedBinLower, 180)
    }

    func testWHOOPOriginalEndpointsStaySeparateFromActualWakeAndRespectPeriod() throws {
        let model = presentationModel(); model.selectedRange = .all; model.sleepSource = .whoop
        let formatter = ISO8601DateFormatter(), end = start.addingTimeInterval(14_400)
        let json: [String: String] = ["id": "original-episode", "start": formatter.string(from: start), "end": formatter.string(from: end)]
        let raw = try WHOOPService.makeAPIDecoder().decode(WHOOPSleep.self, from: JSONSerialization.data(withJSONObject: json))
        var row = night(); row.whoopSummary = raw.toNightSummary(); model.nights = [row]
        let snapshot = model.replaySnapshot(for: row)
        XCTAssertEqual(snapshot.interval(.dose2ToWHOOPepisodeEnd).minutes, 60)
        XCTAssertEqual(snapshot.interval(.dose2ToWHOOPepisodeEnd).state, .partial)
        XCTAssertNil(snapshot.interval(.dose2ToDeviceEnd).minutes); XCTAssertNil(snapshot.interval(.dose2ToReportedWake).minutes)
        XCTAssertEqual(snapshot.markers.first { $0.kind == .whoopEpisodeEnd }?.evidenceQuality?.providerRecordID, "original-episode")
        row.whoopSummary?.endpointEvidence = .init(sleepID: "foreign", originalStart: start, originalEnd: end, providerTimeZoneOffset: nil, providerUpdatedAt: nil)
        XCTAssertFalse(model.replaySnapshot(for: row).markers.contains { $0.kind == .whoopEpisodeEnd })
    }

}
