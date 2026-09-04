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

        _ = try storage.savePreSleepLogOrThrow(
            sessionId: sessionDate,
            answers: DoseTap.PreSleepLogAnswers(
                intendedSleepTime: .thirtyMin,
                stressLevel: 3,
                notes: "preserve raw pre-sleep answers"
            ),
            completionState: "complete",
            now: preSleepTime,
            timeZone: TimeZone(identifier: "UTC")!
        )
        storage.insertDoseEvent(eventType: "dose1", timestamp: dose1Time, sessionDate: sessionDate)
        storage.insertDoseEvent(eventType: "dose2", timestamp: dose2Time, sessionDate: sessionDate)
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

        let settingsView = SettingsView()
        let bundleData = try settingsView.buildStudioInsightsBundleDataForTesting(
            using: repo,
            sessionDates: [sessionDate]
        )
        let bundle = try XCTUnwrap(JSONSerialization.jsonObject(with: bundleData) as? [String: Any])
        let sessions = try XCTUnwrap(bundle["sessions"] as? [[String: Any]])
        let exportedSession = try XCTUnwrap(sessions.first)
        let preSleep = try XCTUnwrap(exportedSession["preSleep"] as? [String: Any])
        let morning = try XCTUnwrap(exportedSession["morning"] as? [String: Any])
        let submissions = try XCTUnwrap(exportedSession["checkInSubmissions"] as? [[String: Any]])

        XCTAssertTrue((preSleep["rawAnswersJson"] as? String)?.contains("preserve raw pre-sleep answers") == true)
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
        XCTAssertTrue(responsePayloads.contains { $0.contains("sleep.quality") })
        XCTAssertTrue(responsePayloads.contains { $0.contains("overall.stress") })

        let inventoryCSV = settingsView.buildStudioInventoryCSVForTesting(using: repo)
        let inventoryRows = inventoryCSV.split(whereSeparator: \.isNewline)
        XCTAssertEqual(inventoryRows.count, 2, "Inventory CSV should include one header and one active snapshot row")
        XCTAssertTrue(inventoryCSV.contains("28"))
        XCTAssertTrue(inventoryCSV.contains("source=active_sqlite"))

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoseTapStudioExportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }

        try settingsView.writeStudioExportBundleForTesting(
            using: repo,
            to: exportDirectory,
            sessionDates: [sessionDate]
        )

        for fileName in ["events.csv", "sessions.csv", "inventory.csv", "insights_bundle.json"] {
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
        XCTAssertEqual((writtenSession["checkInSubmissions"] as? [[String: Any]])?.count, 2)

        let writtenSessionsCSV = try String(contentsOf: exportDirectory.appendingPathComponent("sessions.csv"), encoding: .utf8)
        XCTAssertTrue(writtenSessionsCSV.contains("2026-06-17T01:15:00.000Z"))
        XCTAssertTrue(writtenSessionsCSV.contains("210"), "Sessions CSV should include the 3h30 dose interval")

        let writtenInventoryCSV = try String(contentsOf: exportDirectory.appendingPathComponent("inventory.csv"), encoding: .utf8)
        XCTAssertTrue(writtenInventoryCSV.contains("source=active_sqlite"))
        XCTAssertEqual(writtenInventoryCSV.split(whereSeparator: \.isNewline).count, 2)
    }

    func test_studioWHOOPExportRangeUsesChronologicalBoundsForDescendingSessions() throws {
        let settingsView = SettingsView()
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
        let settingsView = SettingsView()
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

        try SettingsView().writeStudioExportBundleForTesting(
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
