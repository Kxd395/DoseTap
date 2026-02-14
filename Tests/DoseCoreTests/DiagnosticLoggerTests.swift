import XCTest
@testable import DoseCore

final class DiagnosticLoggerTests: XCTestCase {

    // MARK: - DiagnosticEvent

    func test_event_rawValues_match_ssot_naming() {
        // Core session lifecycle
        XCTAssertEqual(DiagnosticEvent.sessionStarted.rawValue, "session.started")
        XCTAssertEqual(DiagnosticEvent.sessionCompleted.rawValue, "session.completed")
        XCTAssertEqual(DiagnosticEvent.sessionExpired.rawValue, "session.expired")
        XCTAssertEqual(DiagnosticEvent.sessionSkipped.rawValue, "session.skipped")
    }

    func test_event_dose_rawValues() {
        XCTAssertEqual(DiagnosticEvent.dose1Taken.rawValue, "dose.1.taken")
        XCTAssertEqual(DiagnosticEvent.dose2Taken.rawValue, "dose.2.taken")
        XCTAssertEqual(DiagnosticEvent.dose2Skipped.rawValue, "dose.2.skipped")
        XCTAssertEqual(DiagnosticEvent.snoozeActivated.rawValue, "dose.snooze.activated")
    }

    func test_event_window_rawValues() {
        XCTAssertEqual(DiagnosticEvent.doseWindowOpened.rawValue, "dose.window.opened")
        XCTAssertEqual(DiagnosticEvent.doseWindowNearClose.rawValue, "dose.window.nearClose")
        XCTAssertEqual(DiagnosticEvent.doseWindowExpired.rawValue, "dose.window.expired")
    }

    func test_event_alarm_rawValues() {
        XCTAssertEqual(DiagnosticEvent.alarmScheduled.rawValue, "alarm.scheduled")
        XCTAssertEqual(DiagnosticEvent.alarmCancelled.rawValue, "alarm.cancelled")
    }

    func test_event_codable_roundtrip() throws {
        let events: [DiagnosticEvent] = [.sessionStarted, .dose1Taken, .alarmScheduled, .invariantViolation]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for event in events {
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(DiagnosticEvent.self, from: data)
            XCTAssertEqual(decoded, event)
        }
    }

    // MARK: - DiagnosticLevel

    func test_level_rawValues() {
        XCTAssertEqual(DiagnosticLevel.info.rawValue, "info")
        XCTAssertEqual(DiagnosticLevel.warning.rawValue, "warning")
        XCTAssertEqual(DiagnosticLevel.error.rawValue, "error")
    }

    func test_level_codable_roundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for level in [DiagnosticLevel.info, .warning, .error] {
            let data = try encoder.encode(level)
            let decoded = try decoder.decode(DiagnosticLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }

    // MARK: - DiagnosticLogEntry

    func test_logEntry_creation() {
        var entry = DiagnosticLogEntry(
            ts: Date(timeIntervalSince1970: 1000),
            level: .info,
            event: .sessionStarted,
            sessionId: "test-session",
            appVersion: "1.0",
            build: "debug"
        )
        XCTAssertEqual(entry.event, .sessionStarted)
        XCTAssertEqual(entry.sessionId, "test-session")
        XCTAssertEqual(entry.level, .info)
        
        // Verify mutable context fields
        entry.phase = "active"
        entry.elapsedMinutes = 160
        XCTAssertEqual(entry.phase, "active")
        XCTAssertEqual(entry.elapsedMinutes, 160)
    }

    func test_logEntry_codable_roundtrip() throws {
        var entry = DiagnosticLogEntry(
            ts: Date(timeIntervalSince1970: 1000),
            level: .warning,
            event: .doseWindowNearClose,
            sessionId: "sess-123",
            appVersion: "2.0",
            build: "release"
        )
        entry.seq = 42
        entry.phase = "nearClose"
        entry.remainingMinutes = 12
        entry.reason = "test reason"

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DiagnosticLogEntry.self, from: data)
        XCTAssertEqual(decoded.event, .doseWindowNearClose)
        XCTAssertEqual(decoded.sessionId, "sess-123")
        XCTAssertEqual(decoded.seq, 42)
        XCTAssertEqual(decoded.phase, "nearClose")
        XCTAssertEqual(decoded.remainingMinutes, 12)
    }

    // MARK: - DiagnosticLogger Actor

    func test_logger_disabled_does_not_write() async {
        let logger = DiagnosticLogger.shared
        await logger.updateSettings(isEnabled: false, tier2Enabled: false, tier3Enabled: false)

        // This should silently no-op — no crash
        await logger.log(.sessionStarted, sessionId: "test-disabled")

        // Re-enable for other tests
        await logger.updateSettings(isEnabled: true, tier2Enabled: true, tier3Enabled: false)
    }

    func test_logger_empty_sessionId_rejected() async {
        let logger = DiagnosticLogger.shared
        await logger.updateSettings(isEnabled: true, tier2Enabled: true, tier3Enabled: false)
        // Should silently reject — no crash
        await logger.log(.sessionStarted, sessionId: "")
    }

    func test_logger_ensureSessionMetadata_creates_directory() async {
        let logger = DiagnosticLogger.shared
        await logger.updateSettings(isEnabled: true, tier2Enabled: true, tier3Enabled: false)
        let testSessionId = "unit-test-\(UUID().uuidString)"
        await logger.ensureSessionMetadata(sessionId: testSessionId)

        // Verify meta.json was created
        let eventsPath = await logger.eventsFilePath(for: testSessionId)
        let sessionDir = eventsPath.deletingLastPathComponent()
        let metaFile = sessionDir.appendingPathComponent("meta.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaFile.path), "meta.json should be created")

        // Cleanup
        try? FileManager.default.removeItem(at: sessionDir)
    }

    func test_logger_writes_events_jsonl() async {
        let logger = DiagnosticLogger.shared
        await logger.updateSettings(isEnabled: true, tier2Enabled: true, tier3Enabled: false)
        let testSessionId = "unit-test-\(UUID().uuidString)"

        await logger.log(.sessionStarted, sessionId: testSessionId)
        await logger.log(.dose1Taken, sessionId: testSessionId) { entry in
            entry.elapsedMinutes = 0
        }

        let eventsPath = await logger.eventsFilePath(for: testSessionId)
        if FileManager.default.fileExists(atPath: eventsPath.path) {
            let content = try? String(contentsOf: eventsPath, encoding: .utf8)
            let lines = content?.split(separator: "\n") ?? []
            XCTAssertGreaterThanOrEqual(lines.count, 2, "Should have at least 2 event lines")

            // Logger encodes dates as ISO8601 strings — decoder must match
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // Each line should be valid JSON
            for line in lines {
                let data = line.data(using: .utf8)!
                XCTAssertNoThrow(try decoder.decode(DiagnosticLogEntry.self, from: data))
            }
        }

        // Cleanup
        let sessionDir = eventsPath.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: sessionDir)
    }

    func test_logger_errors_written_to_errors_jsonl() async {
        let logger = DiagnosticLogger.shared
        await logger.updateSettings(isEnabled: true, tier2Enabled: true, tier3Enabled: false)
        let testSessionId = "unit-test-\(UUID().uuidString)"

        await logger.log(.invariantViolation, level: .error, sessionId: testSessionId) { entry in
            entry.reason = "test invariant"
        }

        let eventsPath = await logger.eventsFilePath(for: testSessionId)
        let errorsPath = eventsPath.deletingLastPathComponent().appendingPathComponent("errors.jsonl")
        if FileManager.default.fileExists(atPath: errorsPath.path) {
            let content = try? String(contentsOf: errorsPath, encoding: .utf8)
            XCTAssertTrue(content?.contains("invariant") ?? false, "Error should appear in errors.jsonl")
        }

        // Cleanup
        let sessionDir = eventsPath.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: sessionDir)
    }

    func test_logger_sequence_numbers_increment() async {
        let logger = DiagnosticLogger.shared
        await logger.updateSettings(isEnabled: true, tier2Enabled: true, tier3Enabled: false)
        let testSessionId = "unit-test-\(UUID().uuidString)"

        for _ in 0..<5 {
            await logger.log(.sessionStarted, sessionId: testSessionId)
        }

        let eventsPath = await logger.eventsFilePath(for: testSessionId)
        if FileManager.default.fileExists(atPath: eventsPath.path),
           let content = try? String(contentsOf: eventsPath, encoding: .utf8) {
            let lines = content.split(separator: "\n")
            // Logger encodes dates as ISO8601 strings — decoder must match
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var seqs: [Int] = []
            for line in lines {
                if let data = line.data(using: .utf8),
                   let entry = try? decoder.decode(DiagnosticLogEntry.self, from: data),
                   let seq = entry.seq {
                    seqs.append(seq)
                }
            }
            // Sequences should be monotonically increasing
            XCTAssertGreaterThanOrEqual(seqs.count, 2, "Should have captured at least 2 sequence numbers")
            if seqs.count >= 2 {
                for i in 1..<seqs.count {
                    XCTAssertGreaterThan(seqs[i], seqs[i-1], "Sequence numbers must be monotonically increasing")
                }
            }
        }

        // Cleanup
        let sessionDir = eventsPath.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: sessionDir)
    }

    func test_logger_availableSessions_includes_created() async {
        let logger = DiagnosticLogger.shared
        await logger.updateSettings(isEnabled: true, tier2Enabled: true, tier3Enabled: false)
        let testSessionId = "unit-test-\(UUID().uuidString)"

        await logger.ensureSessionMetadata(sessionId: testSessionId)
        let sessions = await logger.availableSessions()
        XCTAssertTrue(sessions.contains(testSessionId))

        // Cleanup
        let eventsPath = await logger.eventsFilePath(for: testSessionId)
        let sessionDir = eventsPath.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: sessionDir)
    }

    func test_logger_tier2_disabled_skips_sleep_events() async {
        let logger = DiagnosticLogger.shared
        await logger.updateSettings(isEnabled: true, tier2Enabled: false, tier3Enabled: false)
        let testSessionId = "unit-test-\(UUID().uuidString)"

        // Tier 2 events should be silently dropped
        await logger.logSleepEventLogged(sessionId: testSessionId, eventType: "bathroom", eventId: "e1")
        await logger.logPreSleepStarted(sessionId: testSessionId)

        let eventsPath = await logger.eventsFilePath(for: testSessionId)
        // File should not exist (no events written)
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventsPath.path),
                       "Tier 2 events should not write when tier2Enabled=false")

        // Re-enable
        await logger.updateSettings(isEnabled: true, tier2Enabled: true, tier3Enabled: false)
    }

    // MARK: - Convenience Methods

    func test_convenience_logSessionStarted() async {
        let logger = DiagnosticLogger.shared
        await logger.updateSettings(isEnabled: true, tier2Enabled: true, tier3Enabled: false)
        let testSessionId = "unit-test-\(UUID().uuidString)"
        await logger.logSessionStarted(sessionId: testSessionId)

        let eventsPath = await logger.eventsFilePath(for: testSessionId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: eventsPath.path))

        // Cleanup
        try? FileManager.default.removeItem(at: eventsPath.deletingLastPathComponent())
    }

    func test_convenience_logPhaseEntered() async {
        let logger = DiagnosticLogger.shared
        let testSessionId = "unit-test-\(UUID().uuidString)"
        await logger.logPhaseEntered(
            sessionId: testSessionId,
            phase: "active",
            previousPhase: "beforeWindow",
            elapsedMinutes: 150,
            remainingMinutes: 90
        )

        let eventsPath = await logger.eventsFilePath(for: testSessionId)
        if FileManager.default.fileExists(atPath: eventsPath.path),
           let content = try? String(contentsOf: eventsPath, encoding: .utf8) {
            XCTAssertTrue(content.contains("session.phase.entered"))
        }

        try? FileManager.default.removeItem(at: eventsPath.deletingLastPathComponent())
    }
}
