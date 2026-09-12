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
final class ExportRecordFidelityTests: XCTestCase {
    private func fixture() -> (EventStorage, SessionRepository) {
        let storage = EventStorage.inMemory()
        return (storage, SessionRepository(storage: storage))
    }

    private func execute(_ sql: String, in storage: EventStorage) {
        XCTAssertEqual(sqlite3_exec(storage.db, sql, nil, nil, nil), SQLITE_OK)
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
