//
//  ExportTests.swift
//  DoseTapTests
//
//  Export integrity, import round-trip, and support bundle tests.
//  Extracted from DoseTapTests.swift for maintainability.
//

import XCTest
@testable import DoseTap
import DoseCore
import SQLite3

@MainActor
final class WHOOPExportStatusTests: XCTestCase {
    private var storage: EventStorage!
    private var repo: SessionRepository!
    private var folder: URL!
    private let sentinel = "synthetic-provider-error-must-not-export"
    override func setUp() async throws {
        storage = EventStorage.inMemory()
        repo = SessionRepository(storage: storage, timeZoneProvider: { TimeZone(identifier: "America/New_York")! })
        XCTAssertEqual(sqlite3_exec(storage.db, "INSERT INTO dose_events(id,session_id,event_type,timestamp,session_date) VALUES('whoop-d1','whoop-session','dose1','2026-09-11T23:00:00Z','2026-09-11');", nil, nil, nil), SQLITE_OK)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("WHOOPExport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: folder.appendingPathExtension("zip"))
        repo = nil; storage = nil
    }
    private func sleeps() throws -> [WHOOPSleep] {
        let data = Data(#"[{"id":"night","start":"2026-09-11T23:00:00Z","end":"2026-09-12T00:00:00Z","nap":false,"score_state":"SCORED","score":{"stage_summary":{"total_light_sleep_time_milli":3600000}}},{"id":"nap","start":"2026-09-12T10:00:00Z","end":"2026-09-12T11:00:00Z","nap":true,"score_state":"SCORED","score":{"stage_summary":{"total_light_sleep_time_milli":3600000}}}]"#.utf8)
        return try WHOOPService.makeAPIDecoder().decode([WHOOPSleep].self, from: data)
    }
    private func result(_ records: [WHOOPSleep] = [], failingRecovery: Bool = false) async throws -> WHOOPNightFetchResult {
        try await WHOOPService.loadNightSummaryResult(sleep: { records }, recovery: {
            if failingRecovery { throw NSError(domain: self.sentinel, code: 1) }; return []
        })
    }
    private func bundle() throws -> [String: Any] {
        let data = try Data(contentsOf: folder.appendingPathComponent("insights_bundle.json"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(sentinel))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func metadata(_ bundle: [String: Any]) throws -> [String: Any] {
        let status = try XCTUnwrap(bundle["whoopEnrichment"] as? [String: Any])
        XCTAssertEqual(status["version"] as? Int, 1)
        return status
    }
    func testPartialRecoveryPreservesSleepAndFetchEvidenceInProductionArchive() async throws {
        let response = try await result(sleeps(), failingRecovery: true)
        var queried: (Date, Date)?
        let writer = StudioBundleExporter()
        try await writer.writeWHOOPExportBundleForTesting(using: repo, to: folder, sessionDates: ["2026-09-11"]) {
            queried = ($0, $1); return response
        }
        let object = try bundle(), status = try metadata(object)
        XCTAssertEqual(status["sleepStatus"] as? String, "completed"); XCTAssertEqual(status["recoveryStatus"] as? String, "failed")
        XCTAssertEqual(status["sleepRecordCount"] as? Int, 2); XCTAssertEqual(status["eligibleNightCount"] as? Int, 1)
        XCTAssertNil(status["recoveryRecordCount"]); XCTAssertNil(status["notAttemptedReason"])
        XCTAssertEqual(ISO8601DateFormatter().date(from: try XCTUnwrap(status["queryStartUTC"] as? String)), queried?.0)
        XCTAssertEqual(ISO8601DateFormatter().date(from: try XCTUnwrap(status["queryEndUTC"] as? String)), queried?.1)
        let session = try XCTUnwrap((object["sessions"] as? [[String: Any]])?.first)
        let whoop = try XCTUnwrap(session["whoop"] as? [String: Any])
        XCTAssertEqual(whoop["sleepId"] as? String, "night"); XCTAssertEqual(whoop["totalSleepMinutes"] as? Int, 60)
        XCTAssertNil(whoop["recoveryScore"])
        XCTAssertTrue((object["exportWarnings"] as? [String])?.contains("WHOOP sleep was fetched, but recovery could not be fetched; available sleep data is retained.") == true)
        let rows = try ReportCSV.rows(String(contentsOf: folder.appendingPathComponent("sessions.csv"), encoding: .utf8))
        XCTAssertEqual(rows[1][try XCTUnwrap(rows[0].firstIndex(of: "whoop_recovery"))], "")
        let archive = try writer.archiveExportDirectory(folder)
        let attachment = XCTAttachment(data: try Data(contentsOf: archive), uniformTypeIdentifier: "public.zip-archive")
        attachment.name = "whoop-partial-recovery-roundtrip.zip"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCompletedEmptySleepFailureAndEmptyRecoveryRemainDistinct() async throws {
        for scenario in 0...2 {
            let response = try await result(scenario == 2 ? sleeps() : [])
            try await StudioBundleExporter().writeWHOOPExportBundleForTesting(using: repo, to: folder, sessionDates: ["2026-09-11"]) { _, _ in
                if scenario == 1 { throw NSError(domain: self.sentinel, code: 2) }; return response
            }
            let object = try bundle(), status = try metadata(object)
            XCTAssertEqual(status["sleepStatus"] as? String, scenario == 1 ? "failed" : "completed")
            XCTAssertEqual(status["recoveryStatus"] as? String, scenario == 1 ? "not_attempted" : "completed")
            if scenario == 1 {
                for key in ["sleepRecordCount", "eligibleNightCount", "recoveryRecordCount"] { XCTAssertNil(status[key]) }
            } else {
                XCTAssertEqual(status["sleepRecordCount"] as? Int, scenario == 2 ? 2 : 0)
                XCTAssertEqual(status["eligibleNightCount"] as? Int, scenario == 2 ? 1 : 0)
                XCTAssertEqual(status["recoveryRecordCount"] as? Int, 0)
            }
            XCTAssertNotNil(status["queryStartUTC"]); XCTAssertNotNil(status["queryEndUTC"])
            if scenario < 2 {
                let warning = scenario == 0 ? "WHOOP sleep query completed with no records." : "WHOOP sleep could not be fetched; WHOOP enrichment is unavailable."
                XCTAssertTrue((object["exportWarnings"] as? [String])?.contains(warning) == true)
                XCTAssertNil((object["sessions"] as? [[String: Any]])?.first?["whoop"])
            }
        }
    }
    func testReturnedNapOnlyRecordsRetainCountsWithoutInventingEligibleSleep() async throws {
        let response = try await result(sleeps().filter { $0.nap == true })
        try await StudioBundleExporter().writeWHOOPExportBundleForTesting(using: repo, to: folder, sessionDates: ["2026-09-11"]) { _, _ in response }
        let object = try bundle(), status = try metadata(object)
        XCTAssertEqual(status["sleepStatus"] as? String, "completed"); XCTAssertEqual(status["recoveryStatus"] as? String, "completed")
        XCTAssertEqual(status["sleepRecordCount"] as? Int, 1); XCTAssertEqual(status["eligibleNightCount"] as? Int, 0)
        XCTAssertEqual(status["recoveryRecordCount"] as? Int, 0)
        XCTAssertNotNil(status["queryStartUTC"]); XCTAssertNotNil(status["queryEndUTC"])
        XCTAssertTrue((object["exportWarnings"] as? [String])?.contains("WHOOP sleep records were fetched, but none met the existing sleep-summary criteria.") == true)
        XCTAssertNil((object["sessions"] as? [[String: Any]])?.first?["whoop"])
    }
    func testRecoveryFailureWithoutEligibleSleepDoesNotClaimRetention() async throws {
        for records in [[], try sleeps().filter { $0.nap == true }] {
            let response = try await result(records, failingRecovery: true)
            try await StudioBundleExporter().writeWHOOPExportBundleForTesting(using: repo, to: folder, sessionDates: ["2026-09-11"]) { _, _ in response }
            let object = try bundle(), status = try metadata(object)
            XCTAssertEqual(status["eligibleNightCount"] as? Int, 0)
            XCTAssertEqual(status["recoveryStatus"] as? String, "failed")
            let warnings = try XCTUnwrap(object["exportWarnings"] as? [String])
            XCTAssertTrue(warnings.contains("WHOOP recovery could not be fetched; no WHOOP sleep summary is included in this export."))
            XCTAssertFalse(warnings.contains { $0.contains("available sleep data is retained") })
            XCTAssertTrue(warnings.contains(records.isEmpty ? "WHOOP sleep query completed with no records." : "WHOOP sleep records were fetched, but none met the existing sleep-summary criteria."))
            XCTAssertNil((object["sessions"] as? [[String: Any]])?.first?["whoop"])
        }
    }
    func testRecoveryWarningDoesNotClaimRetentionForUnexportedInterveningNight() async throws {
        let response = try await result(sleeps(), failingRecovery: true)
        try await StudioBundleExporter().writeWHOOPExportBundleForTesting(using: repo, to: folder, sessionDates: ["2026-09-10", "2026-09-12"]) { _, _ in response }
        let object = try bundle(), status = try metadata(object)
        XCTAssertEqual(status["eligibleNightCount"] as? Int, 1)
        XCTAssertTrue(try XCTUnwrap(object["sessions"] as? [[String: Any]]).allSatisfy { $0["whoop"] == nil })
        let warnings = try XCTUnwrap(object["exportWarnings"] as? [String])
        XCTAssertTrue(warnings.contains("WHOOP recovery could not be fetched; no WHOOP sleep summary is included in this export."))
        XCTAssertFalse(warnings.contains { $0.contains("available sleep data is retained") })
    }
    func testDisabledDisconnectedAndUnqueryableExportsDoNotAttemptFetch() async throws {
        let response = try await result()
        for reason in ["invalid_range", "feature_disabled", "preference_disabled", "disconnected", "no_sessions"] {
            var calls = 0
            let dates = reason == "no_sessions" ? [] : [reason == "invalid_range" ? "invalid-date" : "2026-09-11"]
            // Invalid treatment dates cannot produce a valid archive; repository validation stays authoritative.
            do {
                try await StudioBundleExporter().writeWHOOPExportBundleForTesting(using: repo, to: folder, sessionDates: dates,
                    featureEnabled: reason != "feature_disabled", preferenceEnabled: reason != "preference_disabled", connected: reason != "disconnected") { _, _ in calls += 1; return response }
                XCTAssertNotEqual(reason, "invalid_range", "Invalid treatment night must reject export")
            } catch {
                XCTAssertEqual(error as? MedicationStorageInjectedFailure, .init(code: .precondition, detail: "Choose a valid treatment night."))
                XCTAssertEqual(reason, "invalid_range"); XCTAssertEqual(calls, 0); XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("insights_bundle.json").path))
                continue
            }
            let status = try metadata(bundle())
            XCTAssertEqual(calls, 0); XCTAssertEqual(status["notAttemptedReason"] as? String, reason)
            for key in ["sleepStatus", "recoveryStatus"] { XCTAssertEqual(status[key] as? String, "not_attempted") }
            for key in ["sleepRecordCount", "recoveryRecordCount", "eligibleNightCount", "queryStartUTC", "queryEndUTC"] { XCTAssertNil(status[key]) }
        }
    }
    func testCancellationSignalsAndCancelledTasksNeverWriteAnArchive() async throws {
        let response = try await result()
        for scenario in 0...3 {
            var calls = 0
            let task = Task { @MainActor in
                if scenario == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                try await StudioBundleExporter().writeWHOOPExportBundleForTesting(using: self.repo, to: self.folder, sessionDates: ["2026-09-11"]) { _, _ in
                    calls += 1
                    if scenario == 0 { throw CancellationError() }
                    if scenario == 1 { throw URLError(.cancelled) }
                    if scenario == 3 { withUnsafeCurrentTask { $0?.cancel() } }
                    return response
                }
            }
            do { try await task.value; XCTFail("Cancellation must abort export") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(calls, scenario == 2 ? 0 : 1)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
    }
    func testCancelledArchivePreservesSourceFolderAndCreatesNoZIP() async throws {
        let marker = folder.appendingPathComponent("preserved.txt"), data = Data("synthetic source".utf8)
        try data.write(to: marker)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try StudioBundleExporter().archiveExportDirectory(self.folder)
        }
        do { _ = try await task.value; XCTFail("Cancelled archive must reject") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathExtension("zip").path))
        XCTAssertEqual(try Data(contentsOf: marker), data)
    }
    func testLocalSnapshotDoesNotInventFetchStatus() throws {
        try StudioBundleExporter().writeLocalStudioExportBundle(using: repo, to: folder)
        let object = try bundle()
        XCTAssertNil(object["whoopEnrichment"])
        XCTAssertTrue((object["exportWarnings"] as? [String])?.contains("Local snapshot only; provider enrichment was not fetched.") == true)
    }
}

@MainActor
final class AppleHealthExportMissingnessTests: XCTestCase {
    private let nightStart = ISO8601DateFormatter().date(from: "2026-09-11T22:00:00Z")!
    private var biometrics: HealthKitService.NightBiometricsSummary {
        .init(averageHeartRate: 64, respiratoryRate: 14, hrvMs: 37, restingHeartRate: 56)
    }
    private var noBiometrics: HealthKitService.NightBiometricsSummary {
        .init(averageHeartRate: nil, respiratoryRate: nil, hrvMs: nil, restingHeartRate: nil)
    }
    private let sleepFields = ["totalSleepMinutes", "ttfwMinutes", "wakeCount", "awakeMinutes",
        "wakeAfterSleepOnsetMinutes", "inBedMinutes", "coreSleepMinutes", "deepSleepMinutes",
        "remSleepMinutes", "bedTimeUTC", "sleepOnsetUTC", "finalWakeUTC", "observationEndUTC",
        "finalWakeBasis", "derivationVersion"]

    private func json(_ summary: InsightsAppleHealthSummary) throws -> [String: Any] {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(summary)) as? [String: Any])
    }

    func testBiometricsWithoutSegmentsPreserveMeasurementsAndMissingSleep() throws {
        let summary = try XCTUnwrap(StudioBundleExporter.appleHealthSummaryForExport(
            segments: [], biometrics: biometrics, nightStart: nightStart))
        let object = try json(summary)
        for field in sleepFields { XCTAssertNil(object[field], "No sleep observations cannot establish \(field)") }
        XCTAssertEqual(summary.averageHeartRate, 64); XCTAssertEqual(summary.respiratoryRate, 14)
        XCTAssertEqual(summary.hrvMs, 37); XCTAssertEqual(summary.restingHeartRate, 56)
        XCTAssertEqual(summary.recordedIntervals, [])
        XCTAssertEqual(summary.sources, [])
    }

    func testNoProviderObservationsProduceNoSummary() {
        XCTAssertNil(StudioBundleExporter.appleHealthSummaryForExport(
            segments: [], biometrics: noBiometrics, nightStart: nightStart))
    }

    func testContinuousRecordedSleepRetainsExistingZeroAwakeValues() throws {
        let end = nightStart.addingTimeInterval(3600)
        let summary = try XCTUnwrap(StudioBundleExporter.appleHealthSummaryForExport(
            segments: [.init(start: nightStart, end: end, stage: .asleepCore, source: "Synthetic Watch")],
            biometrics: noBiometrics, nightStart: nightStart))
        XCTAssertEqual(summary.totalSleepMinutes, 60)
        XCTAssertEqual(summary.coreSleepMinutes, 60)
        XCTAssertEqual(summary.wakeCount, 0)
        XCTAssertEqual(summary.awakeMinutes, 0)
        XCTAssertEqual(summary.wakeAfterSleepOnsetMinutes, 0)
        XCTAssertEqual(summary.sleepOnsetUTC, nightStart); XCTAssertEqual(summary.finalWakeUTC, end)
        XCTAssertEqual(summary.recordedIntervals, [.init(start: nightStart, end: end, asleep: true)])
    }

    func testAwakeOnlyEvidenceDoesNotInventSleepOnsetOrWakeCount() throws {
        let end = nightStart.addingTimeInterval(600)
        let summary = try XCTUnwrap(StudioBundleExporter.appleHealthSummaryForExport(
            segments: [.init(start: nightStart, end: end, stage: .awake, source: "Synthetic Watch")],
            biometrics: noBiometrics, nightStart: nightStart))
        let object = try json(summary)
        for field in sleepFields { XCTAssertNil(object[field], "Awake-only samples do not supply a sleep summary") }
        XCTAssertEqual(summary.recordedIntervals, [.init(start: nightStart, end: end, asleep: false)])
        XCTAssertEqual(summary.sources, ["Synthetic Watch"])
    }

    func testBelowThresholdAndInBedEvidenceKeepMissingSummary() throws {
        // Exercises received-input preservation; the live query may filter these out earlier.
        for stage in [HealthKitService.SleepStage.asleepCore, .inBed] {
            let end = nightStart.addingTimeInterval(600)
            let summary = try XCTUnwrap(StudioBundleExporter.appleHealthSummaryForExport(
                segments: [.init(start: nightStart, end: end, stage: stage, source: "Synthetic Watch")],
                biometrics: noBiometrics, nightStart: nightStart))
            let object = try json(summary)
            for field in sleepFields where field != "bedTimeUTC" { XCTAssertNil(object[field]) }
            XCTAssertEqual(summary.bedTimeUTC, stage == .inBed ? nightStart : nil)
            XCTAssertEqual(summary.recordedIntervals, stage == .inBed ? [] : [.init(start: nightStart, end: end, asleep: true)])
        }
    }

    func testBiometricOnlyEvidenceReachesProductionArchiveWithoutSleepClaims() throws {
        let storage = EventStorage.inMemory()
        let repo = SessionRepository(storage: storage)
        XCTAssertEqual(sqlite3_exec(storage.db, """
        INSERT INTO dose_events(id,session_id,event_type,timestamp,session_date)
        VALUES('health-d1','health-session','dose1','2026-09-11T22:00:00.000Z','2026-09-11'),
        ('health-d2','health-session','dose2','2026-09-12T01:00:00.000Z','2026-09-11');
        INSERT INTO sleep_events(id,session_id,event_type,timestamp,session_date)
        VALUES('health-bathroom','health-session','bathroom','2026-09-11T23:00:00.000Z','2026-09-11');
        """, nil, nil, nil), SQLITE_OK)
        let summary = try XCTUnwrap(StudioBundleExporter.appleHealthSummaryForExport(
            segments: [], biometrics: biometrics, nightStart: nightStart))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HealthExport-\(UUID().uuidString)")
        let archive = folder.appendingPathExtension("zip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: archive) }
        let writer = StudioBundleExporter()
        try writer.writeStudioExportBundleForTesting(using: repo, to: folder, sessionDates: ["2026-09-11"],
            healthKitBySessionDate: ["2026-09-11": summary])
        let bundle = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("insights_bundle.json"))) as? [String: Any])
        let session = try XCTUnwrap((bundle["sessions"] as? [[String: Any]])?.first)
        let health = try XCTUnwrap(session["healthKit"] as? [String: Any])
        for field in sleepFields { XCTAssertNil(health[field], "Archive must preserve missing \(field)") }
        XCTAssertEqual(health["averageHeartRate"] as? Double, 64)
        XCTAssertEqual(health["respiratoryRate"] as? Double, 14)
        XCTAssertEqual(health["hrvMs"] as? Double, 37)
        XCTAssertEqual(health["restingHeartRate"] as? Double, 56)
        XCTAssertEqual((session["sourceAvailability"] as? [String: Any])?["healthKit"] as? Bool, true)
        let provenance = try XCTUnwrap(session["metricProvenance"] as? [String: String])
        for key in ["total_sleep_minutes", "ttfw_minutes", "wake_count", "awake_minutes", "wake_after_sleep_onset_minutes",
                    "in_bed_minutes", "core_sleep_minutes", "deep_sleep_minutes", "rem_sleep_minutes", "wake_disruption_count"] {
            XCTAssertNil(provenance[key], "No sleep observation supports provenance for \(key)")
        }
        for key in ["average_heart_rate", "respiratory_rate", "hrv_ms", "resting_heart_rate"] {
            XCTAssertEqual(provenance[key], "healthkit")
        }
        let rows = try ReportCSV.rows(String(contentsOf: folder.appendingPathComponent("sessions.csv"), encoding: .utf8))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][try XCTUnwrap(rows[0].firstIndex(of: "avg_hr"))], "64")
        XCTAssertEqual(rows[1][try XCTUnwrap(rows[0].firstIndex(of: "sleep_efficiency"))], "")
        let collected = try ReportCSV.rows(String(contentsOf: folder.appendingPathComponent("collected_nights.csv"), encoding: .utf8))
        for key in ["estimated_sleep_after_dose2_minutes", "sleep_after_dose2_source"] {
            XCTAssertEqual(collected[1][try XCTUnwrap(collected[0].firstIndex(of: key))], "")
        }
        XCTAssertEqual(try writer.archiveExportDirectory(folder), archive)
        let attachment = XCTAttachment(data: try Data(contentsOf: archive), uniformTypeIdentifier: "public.zip-archive")
        attachment.name = "apple-health-biometrics-only-roundtrip.zip"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

@MainActor
final class ExportRecordFidelityTests: XCTestCase {
    private func fixture() -> (EventStorage, SessionRepository) {
        let storage = EventStorage.inMemory()
        return (storage, SessionRepository(storage: storage))
    }

    private func execute(_ sql: String, in storage: EventStorage) {
        XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
    }

    func testEventIdentityAndProvenanceReachEveryArchiveRepresentation() throws {
        let (storage, repo) = fixture()
        execute("""
        INSERT INTO dose_events(id,session_id,event_type,timestamp,session_date,metadata,created_at)
        VALUES('shared-id','session-a','dose1','2026-09-11T23:00:00.123Z','2026-09-11','{"recorded_at_utc":"2026-09-12T07:50:00Z","source":"history","previous":"kept"}','2026-09-12 07:50:01'),
        ('second-session','session-a','history_correction','2026-09-12T01:00:00Z','2026-09-11','unparsed legacy metadata',NULL);
        INSERT INTO sleep_events(id,session_id,event_type,timestamp,session_date,color_hex,notes,created_at)
        VALUES('shared-id',NULL,'Future Sleep Event','2026-09-12T01:02:00Z','2026-09-11','#ABCDEF','comma, "quote"
        new line',NULL);
        """, in: storage)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = StudioBundleExporter()
        try writer.writeLocalStudioExportBundle(using: repo, to: folder)
        let data = try Data(contentsOf: folder.appendingPathComponent("insights_bundle.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try XCTUnwrap((json["sessions"] as? [[String: Any]])?.first)
        let raw = try XCTUnwrap(session["rawEvents"] as? [[String: Any]])
        let normalized = try XCTUnwrap(session["normalizedEvents"] as? [[String: Any]])
        XCTAssertEqual(raw.count, 3)
        XCTAssertEqual(normalized.count, 3)
        for rows in [raw, normalized] {
            let dose = try XCTUnwrap(rows.first { $0["sourceTable"] as? String == "dose_events" && $0["id"] as? String == "shared-id" })
            XCTAssertEqual(dose["sessionId"] as? String, "session-a")
            XCTAssertEqual(dose["timestampStoredUTC"] as? String, "2026-09-11T23:00:00.123Z")
            XCTAssertEqual(dose["createdAtStoredUTC"] as? String, "2026-09-12 07:50:01")
            XCTAssertTrue((dose["details"] as? String)?.contains("2026-09-12T07:50:00Z") == true)
            let other = try XCTUnwrap(rows.first { $0["id"] as? String == "second-session" })
            XCTAssertEqual(other["sessionId"] as? String, "session-a")
            XCTAssertEqual(other["details"] as? String, "unparsed legacy metadata")
            XCTAssertNil(other["source"])
            let sleep = try XCTUnwrap(rows.first { $0["sourceTable"] as? String == "sleep_events" })
            XCTAssertEqual(sleep["id"] as? String, "shared-id")
            XCTAssertEqual(sleep["colorHex"] as? String, "#ABCDEF")
            XCTAssertEqual(sleep["sessionDate"] as? String, "2026-09-11")
            XCTAssertNil(sleep["sessionId"]); XCTAssertNil(sleep["createdAtStoredUTC"]); XCTAssertNil(sleep["source"])
        }
        XCTAssertEqual(raw.first { $0["sourceTable"] as? String == "sleep_events" }?["eventType"] as? String, "Future Sleep Event")
        let csv = try ReportCSV.rows(String(contentsOf: folder.appendingPathComponent("events.csv"), encoding: .utf8))
        XCTAssertEqual(Array(try XCTUnwrap(csv.first).prefix(4)), ["event_type", "occurred_at_utc", "details", "device_time"])
        XCTAssertEqual(csv.count, 4)
        for event in raw {
            let headers = try XCTUnwrap(csv.first)
            let id = try XCTUnwrap(headers.firstIndex(of: "id")), table = try XCTUnwrap(headers.firstIndex(of: "source_table"))
            let row = try XCTUnwrap(csv.dropFirst().first { $0[id] == event["id"] as? String && $0[table] == event["sourceTable"] as? String })
            XCTAssertNotNil(AppFormatters.iso8601Fractional.date(from: row[1]), "Legacy CSV occurrence keeps fractional format")
            for (column, key) in [("session_id", "sessionId"), ("session_date", "sessionDate"), ("timestamp_stored_utc", "timestampStoredUTC"), ("created_at_stored_utc", "createdAtStoredUTC"), ("color_hex", "colorHex"), ("details", "details")] {
                XCTAssertEqual(row[try XCTUnwrap(headers.firstIndex(of: column))], event[key] as? String ?? "")
            }
        }
        let archive = try writer.writeScheduledArchive(using: repo, to: folder)
        let attachment = XCTAttachment(data: try Data(contentsOf: archive), uniformTypeIdentifier: "public.zip-archive")
        attachment.name = "stored-events-roundtrip.zip"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testEventReaderPreservesDifferentSessionsWithoutAssigningLegacyRows() throws {
        let (storage, repo) = fixture()
        execute("""
        INSERT INTO dose_events(id,session_id,event_type,timestamp,session_date)
        VALUES('one','session-a','dose1','2026-09-11T23:00:00Z','2026-09-11'),
        ('two','session-b','dose1','2026-09-11T23:00:00Z','2026-09-11'),
        ('legacy',NULL,'snooze','2026-09-11T23:00:00Z','2026-09-11');
        """, in: storage)
        let events = try repo.eventExportRecords(sessionDate: "2026-09-11")
        XCTAssertEqual(Set(events.map(\.id)), ["one", "two", "legacy"])
        XCTAssertEqual(Set(events.compactMap(\.sessionId)), ["session-a", "session-b"])
        XCTAssertNil(events.first { $0.id == "legacy" }?.sessionId)
    }

    func testLegacyWholeSecondDoseReadPreservesChronologyAndHistoryGuard() throws {
        let (storage, _) = fixture()
        execute("""
        INSERT INTO dose_events(id,session_id,event_type,timestamp,session_date)
        VALUES('fractional','same','snooze','2026-09-11T23:00:00.123Z','2026-09-11'),
        ('whole','same','dose1','2026-09-11T23:00:00Z','2026-09-11');
        """, in: storage)
        XCTAssertEqual(storage.fetchDoseEvents(sessionId: "same", sessionDate: "2026-09-11").map(\.id), ["whole", "fractional"])
        XCTAssertEqual(try storage.historySnapshot(sessionDate: "2026-09-11").events.count, 2)
        execute("UPDATE dose_events SET timestamp = 'invalid' WHERE id = 'whole';", in: storage)
        XCTAssertThrowsError(try storage.historySnapshot(sessionDate: "2026-09-11"))
    }

    func testMalformedEventReadDoesNotPublishPartialArchive() throws {
        for table in ["dose_events", "sleep_events"] {
            let (storage, repo) = fixture()
            execute("INSERT INTO \(table)(id,event_type,timestamp,session_date) VALUES('valid','brief_wake','2026-09-11T23:00:00Z','2026-09-11'),('invalid','brief_wake','zz-invalid','2026-09-11');", in: storage)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            XCTAssertThrowsError(try StudioBundleExporter().writeScheduledArchive(using: repo, to: folder))
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasSuffix(".zip") })
        }
    }

    func testInventoryExportsEveryStoredIdentityAndUnchangedNotes() throws {
        let (storage, repo) = fixture()
        execute("""
        WITH RECURSIVE seq(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM seq WHERE x<501)
        INSERT INTO inventory_snapshots(id,as_of_utc,medication_name,bottles_remaining,doses_remaining,notes)
        SELECT 'inventory-'||x,'2026-09-11T23:00:00.123Z','archived medication',1,x,'exact note' FROM seq;
        """, in: storage)
        let csv = try StudioBundleExporter().buildStudioInventoryCSVForTesting(using: repo)
        let rows = try ReportCSV.rows(csv)
        let header = try XCTUnwrap(rows.first)
        let idIndex = try XCTUnwrap(header.firstIndex(of: "id"))
        let nameIndex = try XCTUnwrap(header.firstIndex(of: "medication_name"))
        XCTAssertEqual(rows.count, 502)
        XCTAssertEqual(Set(rows.dropFirst().map { $0[idIndex] }), Set((1...501).map { "inventory-\($0)" }))
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0[nameIndex] == "archived medication" && $0[5] == "exact note" })
    }

    func testMedicationExportPreservesStoredFactsAndNullableProvenance() throws {
        let (storage, repo) = fixture()
        execute("""
        INSERT INTO medication_events(id,session_id,session_date,medication_id,dose_mg,dose_unit,formulation,taken_at_utc,local_offset_minutes,confirmed_duplicate,created_at,notes)
        VALUES('original','stable-session','2026-09-11','unknown-med',1,'mL','liquid','2026-09-11T23:00:00.123Z',-240,1,'2026-09-12 07:50:00','saved notes'),
        ('legacy',NULL,'2026-09-11','legacy-med',2,'custom-unit','unknown-form','2026-09-11T23:05:00Z',0,NULL,NULL,NULL);
        """, in: storage)
        let data = try StudioBundleExporter().buildStudioInsightsBundleDataForTesting(using: repo, sessionDates: ["2026-09-11"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try XCTUnwrap((json["sessions"] as? [[String: Any]])?.first)
        let rows = try XCTUnwrap(session["medications"] as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { $0["id"] as? String == "original" })
        XCTAssertEqual(row["doseUnit"] as? String, "mL")
        XCTAssertEqual(row["formulation"] as? String, "liquid")
        XCTAssertEqual(row["sessionId"] as? String, "stable-session")
        XCTAssertEqual(row["sessionDate"] as? String, "2026-09-11")
        XCTAssertEqual(row["localOffsetMinutes"] as? Int, -240)
        XCTAssertEqual(row["confirmedDuplicate"] as? Bool, true)
        XCTAssertEqual(row["createdAtStoredUTC"] as? String, "2026-09-12 07:50:00")
        XCTAssertEqual(row["takenAtStoredUTC"] as? String, "2026-09-11T23:00:00.123Z")
        let legacy = try XCTUnwrap(rows.first { $0["id"] as? String == "legacy" })
        XCTAssertEqual(legacy["doseUnit"] as? String, "custom-unit")
        XCTAssertNil(legacy["createdAtStoredUTC"])
        XCTAssertNil(legacy["confirmedDuplicate"])
        XCTAssertNil(legacy["sessionId"])
    }

    func testUnreadableInventoryOrMedicationAbortsExport() throws {
        let (storage, repo) = fixture()
        execute("INSERT INTO inventory_snapshots(id,as_of_utc,medication_name) VALUES('bad','invalid-date','med');", in: storage)
        XCTAssertThrowsError(try StudioBundleExporter().buildStudioInventoryCSVForTesting(using: repo))
        execute("DELETE FROM inventory_snapshots; DROP TABLE inventory_snapshots;", in: storage)
        XCTAssertThrowsError(try StudioBundleExporter().buildStudioInventoryCSVForTesting(using: repo))
        execute("INSERT INTO medication_events(id,session_date,medication_id,dose_mg,taken_at_utc) VALUES('bad','2026-09-11','med',1,'invalid-date');", in: storage)
        XCTAssertThrowsError(try StudioBundleExporter().buildStudioInsightsBundleDataForTesting(using: repo, sessionDates: ["2026-09-11"]))
    }

    func testScheduledWriterRejectsFailedDiscoveryAndPartialMedicationRead() throws {
        let (storage, repo) = fixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        execute("INSERT INTO medication_events(id,session_date,medication_id,dose_mg,taken_at_utc) VALUES('good','2026-09-11','med',1,'2026-09-11T23:00:00Z'),('bad','2026-09-11','med',1,'0000-invalid');", in: storage)
        XCTAssertThrowsError(try StudioBundleExporter().writeScheduledArchive(using: repo, to: folder))
        execute("DROP TABLE medication_events;", in: storage)
        XCTAssertThrowsError(try StudioBundleExporter().writeScheduledArchive(using: repo, to: folder))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasSuffix(".zip") })
    }

    func testMedicationOnlySessionReachesActualArchiveWithStoredFields() throws {
        let (storage, repo) = fixture()
        execute("INSERT INTO medication_events(id,session_date,medication_id,dose_mg,dose_unit,formulation,taken_at_utc,created_at) VALUES('med-only','2026-09-11','unknown-med',1,'mL','liquid','2026-09-11T23:00:00.123Z',NULL);", in: storage)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = StudioBundleExporter()
        try writer.writeLocalStudioExportBundle(using: repo, to: folder)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("insights_bundle.json"))) as? [String: Any])
        let session = try XCTUnwrap((json["sessions"] as? [[String: Any]])?.first)
        let row = try XCTUnwrap((session["medications"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["id"] as? String, "med-only")
        XCTAssertEqual(row["doseUnit"] as? String, "mL")
        XCTAssertEqual(row["formulation"] as? String, "liquid")
        XCTAssertEqual(row["takenAtStoredUTC"] as? String, "2026-09-11T23:00:00.123Z")
        XCTAssertNil(row["createdAtStoredUTC"])
        let archive = try writer.writeScheduledArchive(using: repo, to: folder)
        let attachment = XCTAttachment(data: try Data(contentsOf: archive), uniformTypeIdentifier: "public.zip-archive")
        attachment.name = "stored-medication-roundtrip.zip"; attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Export Integrity Tests

@MainActor
final class ExportIntegrityTests: XCTestCase {
    
    private var storage: EventStorage!
    private var repo: SessionRepository!
    
    /// Fixed clock well after the 18:00 UTC rollover so dose times at
    /// `Date() - N min` never cross a session boundary on CI (UTC).
    private let fixedNow: Date = {
        ISO8601DateFormatter().date(from: "2026-01-15T23:00:00Z")!
    }()
    
    override func setUp() async throws {
        storage = EventStorage.shared
        repo = SessionRepository(
            storage: storage,
            clock: { [fixedNow] in fixedNow },
            timeZoneProvider: { TimeZone(identifier: "UTC")! }
        )
        storage.clearAllData()
        repo.reload()
    }
    
    override func tearDown() async throws {
        storage.clearAllData()
    }
    
    func test_export_rowCountMatchesDatabaseSessions() async throws {
        let calendar = Calendar.current
        
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.day! -= 1
        comps.hour = 22
        comps.minute = 0
        if let yesterday = calendar.date(from: comps) {
            repo.setDose1Time(yesterday)
            repo.setDose2Time(yesterday.addingTimeInterval(165 * 60))
        }
        
        repo.clearTonight()
        
        let now = Date()
        repo.setDose1Time(now.addingTimeInterval(-120 * 60))
        
        let dbSessionCount = storage.getAllSessionDates().count
        let sessions = repo.getAllSessions()
        
        XCTAssertEqual(sessions.count, dbSessionCount,
            "Export session count (\(sessions.count)) should match DB session count (\(dbSessionCount))")
    }

    func test_export_includesMetadataHeader() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-120 * 60))
        
        let csv = storage.exportToCSV()
        
        let firstLine = csv.components(separatedBy: .newlines).first ?? ""
        XCTAssertTrue(firstLine.contains("schema_version="), "CSV should include schema_version metadata")
        XCTAssertTrue(firstLine.contains("constants_version="), "CSV should include constants_version metadata")
    }

    func test_export_excludesDeletedSessions() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-90 * 60))
        let sessionDate = repo.currentSessionDateString()
        repo.deleteSession(sessionDate: sessionDate)
        
        let sessions = repo.getAllSessions()
        
        XCTAssertFalse(sessions.contains(sessionDate),
            "Deleted session \(sessionDate) should not appear in export list")
    }
    
    func test_export_noEmptyRows() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-150 * 60))
        
        let sessions = repo.getAllSessions()
        
        for session in sessions {
            XCTAssertFalse(session.isEmpty, "Session date should not be empty")
        }
    }

    func test_fetchDoseEvents_fallsBackToSessionDate_whenSessionIdMismatches() async throws {
        let now = Date()
        repo.setDose1Time(now)
        let sessionDate = repo.currentSessionDateString()

        guard let canonicalSessionId = repo.fetchSessionId(forSessionDate: sessionDate) else {
            XCTFail("Expected canonical session ID for active session")
            return
        }
        XCTAssertNotEqual(canonicalSessionId, sessionDate, "Test requires session_id and session_date to differ")

        let canonicalRows = repo.fetchDoseEvents(forSessionDate: sessionDate)
        for row in canonicalRows {
            storage.deleteDoseEvent(id: row.id, recordCloudKitDeletion: false)
        }

        storage.insertDoseEvent(
            eventType: "dose1",
            timestamp: now,
            sessionDate: sessionDate,
            sessionId: nil
        )

        let fetched = repo.fetchDoseEvents(forSessionDate: sessionDate)
        XCTAssertEqual(fetched.count, 1, "Should fetch legacy session_date keyed dose row")
        XCTAssertEqual(fetched.first?.eventType, "dose1")
    }

    func test_primaryNightSleepBands_excludesLongAwakeBridgesAndSecondaryCluster() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 22, minute: 0)) ?? Date()

        let bands: [SleepStageBand] = [
            SleepStageBand(stage: .awake, startTime: start, endTime: start.addingTimeInterval(2 * 3600)),
            SleepStageBand(stage: .light, startTime: start.addingTimeInterval(2 * 3600 + 10 * 60), endTime: start.addingTimeInterval(2 * 3600 + 50 * 60)),
            SleepStageBand(stage: .deep, startTime: start.addingTimeInterval(3 * 3600 + 10 * 60), endTime: start.addingTimeInterval(3 * 3600 + 50 * 60)),
            SleepStageBand(stage: .awake, startTime: start.addingTimeInterval(4 * 3600), endTime: start.addingTimeInterval(8 * 3600)),
            SleepStageBand(stage: .light, startTime: start.addingTimeInterval(8 * 3600 + 10 * 60), endTime: start.addingTimeInterval(9 * 3600))
        ]

        let filtered = primaryNightSleepBands(from: bands)
        XCTAssertFalse(filtered.isEmpty, "Expected a retained primary sleep cluster")

        let filteredStart = filtered.map(\.startTime).min()
        let filteredEnd = filtered.map(\.endTime).max()

        XCTAssertEqual(filteredStart, start.addingTimeInterval(2 * 3600 + 10 * 60),
            "Filtered cluster should begin at first primary sleep segment")
        XCTAssertEqual(filteredEnd, start.addingTimeInterval(3 * 3600 + 50 * 60),
            "Filtered cluster should end at primary cluster")
    }
    
    // MARK: - Support Bundle Secrets Tests
    
    func test_supportBundle_excludesAPIKeys() async throws {
        let secretPatterns = [
            "whoop_client_id", "whoop_client_secret", "api_key", "apiKey",
            "API_KEY", "bearer_token", "access_token", "refresh_token",
            "sk_live_", "pk_live_",
        ]
        
        let bundleContent = """
        DoseTap Support Bundle
        App Version: 1.0.0
        Device: iPhone 15
        Session Count: \(repo.getAllSessions().count)
        Last Dose 1: \(repo.dose1Time?.description ?? "none")
        """
        
        for pattern in secretPatterns {
            XCTAssertFalse(bundleContent.lowercased().contains(pattern.lowercased()),
                "Support bundle should not contain '\(pattern)'")
        }
    }
    
    func test_supportBundle_redactsDeviceIDs() async throws {
        let redactor = DataRedactor()
        let testUUID = "550E8400-E29B-41D4-A716-446655440000"
        let testContent = "Device ID: \(testUUID)"
        
        let result = redactor.redact(testContent)
        
        XCTAssertFalse(result.redactedText.contains(testUUID), "Device UUID should be redacted")
        XCTAssertTrue(result.redactedText.contains("HASH_"), "UUID should be replaced with hash")
    }
    
    func test_supportBundle_redactsEmails() async throws {
        let redactor = DataRedactor()
        let testEmail = "user@example.com"
        let testContent = "Contact: \(testEmail)"
        
        let result = redactor.redact(testContent)
        
        XCTAssertFalse(result.redactedText.contains(testEmail), "Email should be redacted")
        XCTAssertTrue(result.redactedText.contains("[EMAIL_REDACTED]"), "Email should be replaced with placeholder")
    }
    
    func test_supportBundle_includesMetadata() async throws {
        let bundle = SupportBundleExporter(storage: storage).makeBundleSummary()
        XCTAssertTrue(bundle.contains("schema_version="), "Support bundle should include schema_version")
        XCTAssertTrue(bundle.contains("constants_version="), "Support bundle should include constants_version")
    }
    
    func test_export_includesSchemaVersion() async throws {
        let schemaVersion = storage.getSchemaVersion()
        XCTAssertGreaterThanOrEqual(schemaVersion, 0, "Schema version should be 0 or greater")
    }

    func test_studioExport_preservesCheckInPayloadsAndInventoryRows() throws {
        let sessionDate = "2026-06-16"
        let dose1Time = makeDate("2026-06-17T01:15:00.000Z")
        let dose2Time = makeDate("2026-06-17T04:45:00.000Z")
        let preSleepTime = makeDate("2026-06-17T00:40:00.000Z")
        let morningTime = makeDate("2026-06-17T11:00:00.000Z")
        let physicalJson = #"{"painEntries":[{"area":"neck","severity":5}],"headacheIntensity":2}"#
        let respiratoryJson = #"{"congestionBurden":"mild","coughBurden":"none"}"#
        let therapyJson = #"{"device":"cpap","compliance":4}"#
        let environmentJson = #"{"roomTemp":"cool","noiseLevel":"quiet"}"#
        let stressJson = #"{"stressProgression":"better","stressNotes":"less pressure"}"#
        let timingJson = #"{"nightType":"work_night","wakeType":"natural","nextDayDemand":"shift_13h"}"#

        var foodAnswers = DoseTap.PreSleepLogAnswers(intendedSleepTime: .thirtyMin,
            stressLevel: 3, notes: "preserve raw pre-sleep answers")
        foodAnswers.lastFood = .init(finishedAt: preSleepTime.addingTimeInterval(-7200), kind: .meal,
            highFat: true, notes: "Fried food")
        foodAnswers.stimulants = .coffee
        var caffeine = CaffeineAmounts()
        caffeine.lastVolumeUSFlOz = 12.5; caffeine.lastCaffeineMg = 0
        caffeine.source = .labelReported
        foodAnswers.caffeineAmounts = caffeine
        foodAnswers.caffeineLastAmountMg = 95 // Unverified legacy value, not a conversion.
        _ = try storage.savePreSleepLogOrThrow(
            sessionId: sessionDate,
            answers: foodAnswers,
            completionState: "complete",
            now: preSleepTime,
            timeZone: TimeZone(identifier: "UTC")!
        )
        storage.insertDoseEvent(eventType: "dose1", timestamp: dose1Time, sessionDate: sessionDate)
        storage.insertDoseEvent(eventType: "dose2", timestamp: dose2Time, sessionDate: sessionDate)
        let review = try repo.nightOutcomeSnapshot(sessionDate: sessionDate)
        var diary = NightOutcomeDiary()
        diary.wakeMethod = .natural; diary.backupAlarmSet = true; diary.dayType = .dayOff
        diary.finalWakeAt = morningTime; diary.sleepiness = 0; diary.assessedAt = morningTime.addingTimeInterval(21600)
        diary.reviewedSleepWindow = .init(sessionID: review.history.sessionId, start: preSleepTime, end: morningTime,
            entryTimeZone: TimeZone(identifier: "America/New_York")!, reviewedAt: diary.assessedAt!)
        XCTAssertTrue(storage.saveNightOutcome(diary, review: review, reason: "", recordedAt: diary.assessedAt!).isCommitted)
        storage.saveMorningCheckIn(
            DoseTap.StoredMorningCheckIn(
                id: "morning-\(sessionDate)",
                sessionId: sessionDate,
                timestamp: morningTime,
                sessionDate: sessionDate,
                sleepQuality: 4.25,
                hasPhysicalSymptoms: true,
                physicalSymptomsJson: physicalJson,
                hasRespiratorySymptoms: true,
                respiratorySymptomsJson: respiratoryJson,
                stressLevel: 2,
                stressContextJson: stressJson,
                usedSleepTherapy: true,
                sleepTherapyJson: therapyJson,
                hasSleepEnvironment: true,
                sleepEnvironmentJson: environmentJson,
                timingContextJson: timingJson
            ),
            forSession: sessionDate
        )
        storage.upsertInventorySnapshot(
            DoseTap.StoredInventorySnapshot(
                id: "inventory-\(sessionDate)",
                asOfUTC: morningTime,
                medicationName: "XYWAV",
                bottlesRemaining: 2,
                dosesRemaining: 28,
                estimatedDaysLeft: 14,
                nextRefillDate: makeDate("2026-06-30T12:00:00.000Z"),
                notes: "test supply"
            )
        )

        let settingsView = StudioBundleExporter()
        let bundleData = try settingsView.buildStudioInsightsBundleDataForTesting(
            using: repo,
            sessionDates: [sessionDate]
        )
        let bundle = try XCTUnwrap(JSONSerialization.jsonObject(with: bundleData) as? [String: Any])
        let sessions = try XCTUnwrap(bundle["sessions"] as? [[String: Any]])
        let exportedSession = try XCTUnwrap(sessions.first)
        let preSleep = try XCTUnwrap(exportedSession["preSleep"] as? [String: Any])
        let collected = try XCTUnwrap(exportedSession["collectedNight"] as? [String: Any])
        XCTAssertEqual(collected["dose2WakeMethod"] as? String, "natural")
        XCTAssertEqual(collected["backupAlarmSet"] as? Bool, true)
        XCTAssertEqual(collected["sleepiness0To10"] as? Int, 0)
        XCTAssertEqual(collected["lastFoodHighFat"] as? Bool, true)
        XCTAssertEqual(collected["lastFoodToDose1Minutes"] as? Double, 155)
        XCTAssertNil(collected["estimatedSleepAfterDose2Minutes"], "No segments is not zero sleep")
        let exportedWindow = try XCTUnwrap(collected["reviewedSleepWindow"] as? [String: Any])
        XCTAssertEqual(exportedWindow["sessionID"] as? String, review.history.sessionId)
        XCTAssertEqual(exportedWindow["entryTimeZoneID"] as? String, "America/New_York")
        XCTAssertEqual(exportedWindow["source"] as? String, "user_reviewed")
        let measured = try repo.collectedNightSummary(for: sessionDate, intervals: [
            .init(start: dose2Time, end: morningTime, asleep: true),
            .init(start: dose2Time, end: dose2Time.addingTimeInterval(600), asleep: false)
        ])
        XCTAssertEqual(measured.estimatedSleepAfterDose2Minutes, 365)
        XCTAssertEqual(measured.sleepAfterDose2CoveredMinutes, 375)
        let morning = try XCTUnwrap(exportedSession["morning"] as? [String: Any])
        let submissions = try XCTUnwrap(exportedSession["checkInSubmissions"] as? [[String: Any]])

        XCTAssertTrue((preSleep["rawAnswersJson"] as? String)?.contains("preserve raw pre-sleep answers") == true)
        XCTAssertEqual((preSleep["caffeineAmounts"] as? [String: Any])?["lastVolumeUSFlOz"] as? Double, 12.5)
        XCTAssertNil(preSleep["caffeineLastAmountMg"])
        let food = try XCTUnwrap(preSleep["lastFood"] as? [String: Any])
        XCTAssertEqual(food["kind"] as? String, "meal")
        XCTAssertEqual(food["highFat"] as? Bool, true)
        XCTAssertEqual(food["notes"] as? String, "Fried food")
        XCTAssertNotNil(ISO8601DateFormatter().date(from: try XCTUnwrap(food["finishedAt"] as? String)))
        let exportedSleepQuality = try XCTUnwrap(morning["sleepQuality"] as? Double)
        XCTAssertEqual(exportedSleepQuality, 4.25, accuracy: 0.001)
        XCTAssertEqual(morning["rawPhysicalSymptomsJson"] as? String, physicalJson)
        XCTAssertEqual(morning["rawRespiratorySymptomsJson"] as? String, respiratoryJson)
        XCTAssertEqual(morning["rawSleepTherapyJson"] as? String, therapyJson)
        XCTAssertEqual(morning["rawSleepEnvironmentJson"] as? String, environmentJson)
        XCTAssertEqual(morning["rawStressContextJson"] as? String, stressJson)
        XCTAssertEqual(morning["rawTimingContextJson"] as? String, timingJson)

        let submissionTypes = Set(submissions.compactMap { $0["checkInType"] as? String })
        XCTAssertTrue(submissionTypes.contains("pre_night"))
        XCTAssertTrue(submissionTypes.contains("morning"))
        let responsePayloads = submissions.compactMap { $0["responsesJson"] as? String }
        XCTAssertTrue(responsePayloads.contains { $0.contains("reviewedSleepWindow") })
        XCTAssertTrue(responsePayloads.contains { $0.contains("sleep.quality") })
        XCTAssertTrue(responsePayloads.contains { $0.contains("overall.stress") })

        let inventoryCSV = try settingsView.buildStudioInventoryCSVForTesting(using: repo)
        let inventoryRows = inventoryCSV.split(whereSeparator: \.isNewline)
        XCTAssertEqual(inventoryRows.count, 2, "Inventory CSV should include one header and one active snapshot row")
        XCTAssertTrue(inventoryCSV.contains("28"))
        XCTAssertTrue(inventoryCSV.contains("active_sqlite"))

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoseTapStudioExportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }

        try settingsView.writeStudioExportBundleForTesting(
            using: repo,
            to: exportDirectory,
            sessionDates: [sessionDate]
        )

        for fileName in ["events.csv", "sessions.csv", "inventory.csv", "insights_bundle.json", "collected_nights.csv"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: exportDirectory.appendingPathComponent(fileName).path),
                "Expected Studio export package to include \(fileName)"
            )
        }

        let writtenBundleData = try Data(contentsOf: exportDirectory.appendingPathComponent("insights_bundle.json"))
        let writtenBundle = try XCTUnwrap(JSONSerialization.jsonObject(with: writtenBundleData) as? [String: Any])
        let writtenSessions = try XCTUnwrap(writtenBundle["sessions"] as? [[String: Any]])
        let writtenSession = try XCTUnwrap(writtenSessions.first)
        XCTAssertEqual(writtenSession["sessionDate"] as? String, sessionDate)
        XCTAssertEqual((writtenSession["checkInSubmissions"] as? [[String: Any]])?.count, 3)

        let writtenSessionsCSV = try String(contentsOf: exportDirectory.appendingPathComponent("sessions.csv"), encoding: .utf8)
        let windowCSV = try String(contentsOf: exportDirectory.appendingPathComponent("collected_nights.csv"), encoding: .utf8)
        let windowRows = try ReportCSV.rows(windowCSV)
        let windowColumn = try XCTUnwrap(windowRows[0].firstIndex(of: "reviewed_window_entry_timezone"))
        XCTAssertEqual(windowRows[1][windowColumn], "America/New_York")
        XCTAssertTrue(writtenSessionsCSV.contains("2026-06-17T01:15:00.000Z"))
        XCTAssertTrue(writtenSessionsCSV.contains("210"), "Sessions CSV should include the 3h30 dose interval")

        let writtenInventoryCSV = try String(contentsOf: exportDirectory.appendingPathComponent("inventory.csv"), encoding: .utf8)
        XCTAssertTrue(writtenInventoryCSV.contains("active_sqlite"))
        XCTAssertEqual(writtenInventoryCSV.split(whereSeparator: \.isNewline).count, 2)

        // Scheduled and manual exports use the same local record writer.
        try settingsView.writeLocalStudioExportBundle(using: repo, to: exportDirectory)
        let localData = try Data(contentsOf: exportDirectory.appendingPathComponent("insights_bundle.json"))
        let local = try XCTUnwrap(JSONSerialization.jsonObject(with: localData) as? [String: Any])
        XCTAssertNil(local["consent"])
        XCTAssertTrue((local["exportWarnings"] as? [String])?.contains(where: { $0.contains("Local snapshot") }) == true)
        let flat = try ReportCSV.rows(String(contentsOf: exportDirectory.appendingPathComponent("collected_nights.csv"), encoding: .utf8))
        XCTAssertEqual(flat.count, 2)
        XCTAssertEqual(flat[0].count, flat[1].count)
        XCTAssertEqual(flat[1][try XCTUnwrap(flat[0].firstIndex(of: "sleepiness_0_to_10"))], "0")
        var cancellationChecks = 0
        XCTAssertThrowsError(try settingsView.writeScheduledArchive(using: repo, to: exportDirectory, cancelled: {
            cancellationChecks += 1; return cancellationChecks == 2
        }))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: exportDirectory.path).contains { $0.hasSuffix(".zip") })
        let archive = try settingsView.writeScheduledArchive(using: repo, to: exportDirectory)
        let archiveData = try Data(contentsOf: archive)
        XCTAssertEqual(Array(archiveData.prefix(2)), [0x50, 0x4b])
        let attachment = XCTAttachment(data: archiveData, uniformTypeIdentifier: "public.zip-archive")
        attachment.name = "collected-night-roundtrip.zip"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_studioWHOOPExportRangeUsesChronologicalBoundsForDescendingSessions() throws {
        let settingsView = StudioBundleExporter()
        let descendingDates = ["2026-06-17", "2026-06-16", "2026-02-09"]
        let ascendingDates = descendingDates.sorted()

        let descendingRange = try XCTUnwrap(
            settingsView.studioWHOOPExportQueryRangeForTesting(sessionDates: descendingDates)
        )
        let ascendingRange = try XCTUnwrap(
            settingsView.studioWHOOPExportQueryRangeForTesting(sessionDates: ascendingDates)
        )

        XCTAssertLessThan(descendingRange.start, descendingRange.end)
        XCTAssertEqual(descendingRange.start, ascendingRange.start)
        XCTAssertEqual(descendingRange.end, ascendingRange.end)
    }

    func test_studioWHOOPSummaryDateUsesSessionRolloverKey() throws {
        let settingsView = StudioBundleExporter()
        let afterMidnightSleepStart = makeDate("2026-06-17T02:30:00.000Z")

        XCTAssertEqual(
            settingsView.studioWHOOPSessionDateForTesting(using: repo, summaryDate: afterMidnightSleepStart),
            "2026-06-16"
        )
    }

    func test_studioSessionsCSV_marksMissingDose2OutcomeInsteadOfOk() throws {
        let sessionDate = "2026-08-29"
        storage.insertDoseEvent(
            eventType: "dose1",
            timestamp: makeDate("2026-08-30T02:00:00.000Z"),
            sessionDate: sessionDate
        )

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoseTapMissingOutcomeExportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }

        try StudioBundleExporter().writeStudioExportBundleForTesting(
            using: repo,
            to: exportDirectory,
            sessionDates: [sessionDate]
        )

        let csv = try String(
            contentsOf: exportDirectory.appendingPathComponent("sessions.csv"),
            encoding: .utf8
        )
        let rows = csv.split(whereSeparator: \.isNewline)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows[1].contains(",missing,"), "A missing Dose 2 outcome must never be exported as adherent")
        XCTAssertFalse(rows[1].contains(",ok,"))
    }

    private func makeDate(_ isoString: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: isoString) ?? Date(timeIntervalSince1970: 0)
    }
}

// MARK: - Export/Import Round Trip Tests

@MainActor
final class ExportImportRoundTripTests: XCTestCase {
    private let storage = EventStorage.shared
    private var repo: SessionRepository!
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    /// Fixed clock well after the 18:00 UTC rollover so dose times at
    /// `Date() - N min` never cross a session boundary on CI (UTC).
    private let fixedNow: Date = {
        ISO8601DateFormatter().date(from: "2026-01-15T23:00:00Z")!
    }()
    
    override func setUp() async throws {
        storage.clearAllData()
        repo = SessionRepository(
            storage: storage,
            notificationScheduler: FakeNotificationScheduler(),
            clock: { [fixedNow] in fixedNow },
            timeZoneProvider: { TimeZone(identifier: "UTC")! }
        )
    }
    
    override func tearDown() async throws {
        storage.clearAllData()
    }
    
    func test_exportImport_roundTripPreservesCounts() async throws {
        let baseDate = Date()
        repo.setDose1Time(baseDate)
        repo.setDose2Time(baseDate.addingTimeInterval(165 * 60))
        let sessionDate = repo.currentSessionDateString()
        
        storage.insertSleepEvent(eventType: "lights_out", timestamp: baseDate, sessionDate: sessionDate, notes: "seed")
        storage.insertMedicationEvent(SQLiteStoredMedicationEntry(
            sessionId: sessionDate,
            sessionDate: sessionDate,
            medicationId: "adderall",
            doseMg: 10,
            takenAtUTC: baseDate,
            localOffsetMinutes: 0,
            notes: "seed",
            confirmedDuplicate: false,
            createdAt: baseDate
        ))
        
        let originalDoseCount = storage.countDoseEvents()
        let originalSleepCount = storage.fetchAllSleepEvents(limit: 1000).count
        let originalMedCount = storage.fetchAllMedicationEvents(limit: 1000).count
        
        let export = storage.exportToCSV()
        XCTAssertTrue(export.contains("schema_version"), "Export should include metadata header")
        
        storage.clearAllData()
        let lines = export.split(whereSeparator: \.isNewline)
        XCTAssertGreaterThan(lines.count, 1, "Export should contain data lines")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("type") {
                continue
            }
            let parts = trimmed.split(separator: ",", maxSplits: 3).map(String.init)
            guard parts.count >= 3 else { continue }
            let type = parts[0]
            let timestamp = isoFormatter.date(from: parts[1]) ?? baseDate
            let session = parts[2]
            let details = parts.count > 3 ? parts[3] : ""
            
            switch type {
            case "dose1", "dose2", "dose2_skipped", "snooze":
                storage.insertDoseEvent(eventType: type, timestamp: timestamp, sessionDate: session)
            case "medication":
                let tokens = details.split(separator: "|")
                let medId = tokens.first.map(String.init) ?? "med"
                let doseMg = tokens.dropFirst().first.flatMap { Int($0.replacingOccurrences(of: "mg", with: "")) } ?? 0
                let note = tokens.dropFirst(2).first.map(String.init)
                storage.insertMedicationEvent(SQLiteStoredMedicationEntry(
                    sessionId: session,
                    sessionDate: session,
                    medicationId: medId,
                    doseMg: doseMg,
                    takenAtUTC: timestamp,
                    localOffsetMinutes: 0,
                    notes: note,
                    confirmedDuplicate: false,
                    createdAt: timestamp
                ))
            default:
                storage.insertSleepEvent(eventType: type, timestamp: timestamp, sessionDate: session, notes: details)
            }
        }
        
        let importedDoseCount = storage.countDoseEvents()
        let importedSleepCount = storage.fetchAllSleepEvents(limit: 1000).count
        let importedMedCount = storage.fetchAllMedicationEvents(limit: 1000).count
        
        XCTAssertEqual(importedDoseCount, originalDoseCount, "Dose event count should survive round-trip")
        XCTAssertEqual(importedSleepCount, originalSleepCount, "Sleep event count should survive round-trip")
        XCTAssertEqual(importedMedCount, originalMedCount, "Medication count should survive round-trip")
    }
}
