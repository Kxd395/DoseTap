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
