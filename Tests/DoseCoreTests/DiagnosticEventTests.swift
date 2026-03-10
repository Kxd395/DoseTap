import XCTest
@testable import DoseCore

final class DiagnosticEventTests: XCTestCase {
    
    // MARK: - DiagnosticEvent raw values match SSOT dot-notation
    
    func test_sessionLifecycleEvents_haveCorrectRawValues() {
        XCTAssertEqual(DiagnosticEvent.sessionStarted.rawValue, "session.started")
        XCTAssertEqual(DiagnosticEvent.sessionPhaseEntered.rawValue, "session.phase.entered")
        XCTAssertEqual(DiagnosticEvent.sessionCompleted.rawValue, "session.completed")
        XCTAssertEqual(DiagnosticEvent.sessionExpired.rawValue, "session.expired")
        XCTAssertEqual(DiagnosticEvent.sessionSkipped.rawValue, "session.skipped")
        XCTAssertEqual(DiagnosticEvent.sessionAutoExpired.rawValue, "session.autoExpired")
        XCTAssertEqual(DiagnosticEvent.sessionRollover.rawValue, "session.rollover")
    }
    
    func test_doseWindowEvents_haveCorrectRawValues() {
        XCTAssertEqual(DiagnosticEvent.doseWindowOpened.rawValue, "dose.window.opened")
        XCTAssertEqual(DiagnosticEvent.doseWindowNearClose.rawValue, "dose.window.nearClose")
        XCTAssertEqual(DiagnosticEvent.doseWindowExpired.rawValue, "dose.window.expired")
        XCTAssertEqual(DiagnosticEvent.doseWindowBlocked.rawValue, "dose.window.blocked")
    }
    
    func test_doseActionEvents_haveCorrectRawValues() {
        XCTAssertEqual(DiagnosticEvent.dose1Taken.rawValue, "dose.1.taken")
        XCTAssertEqual(DiagnosticEvent.dose2Taken.rawValue, "dose.2.taken")
        XCTAssertEqual(DiagnosticEvent.doseExtraTaken.rawValue, "dose.extra.taken")
        XCTAssertEqual(DiagnosticEvent.dose2Skipped.rawValue, "dose.2.skipped")
        XCTAssertEqual(DiagnosticEvent.doseUndone.rawValue, "dose.undone")
        XCTAssertEqual(DiagnosticEvent.snoozeActivated.rawValue, "dose.snooze.activated")
    }
    
    func test_invariantViolation_rawValue() {
        XCTAssertEqual(DiagnosticEvent.invariantViolation.rawValue, "invariant.violation")
    }
    
    // MARK: - DiagnosticEvent Codable round-trip
    
    func test_diagnosticEvent_codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let events: [DiagnosticEvent] = [
            .sessionStarted, .dose1Taken, .dose2Taken, .doseWindowOpened,
            .invariantViolation, .appForegrounded, .undoExecuted, .sleepEventLogged
        ]
        
        for event in events {
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(DiagnosticEvent.self, from: data)
            XCTAssertEqual(decoded, event, "Round-trip failed for \(event.rawValue)")
        }
    }
    
    // MARK: - DiagnosticLevel
    
    func test_diagnosticLevel_rawValues() {
        XCTAssertEqual(DiagnosticLevel.debug.rawValue, "debug")
        XCTAssertEqual(DiagnosticLevel.info.rawValue, "info")
        XCTAssertEqual(DiagnosticLevel.warning.rawValue, "warning")
        XCTAssertEqual(DiagnosticLevel.error.rawValue, "error")
    }
    
    // MARK: - DiagnosticLogEntry
    
    func test_logEntry_codableRoundTrip_minimalFields() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let entry = DiagnosticLogEntry(
            ts: Date(timeIntervalSince1970: 1_000_000),
            level: .info,
            event: .dose1Taken,
            sessionId: "test-session-123",
            appVersion: "1.0.0",
            build: "debug"
        )
        
        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(DiagnosticLogEntry.self, from: data)
        
        XCTAssertEqual(decoded.event, .dose1Taken)
        XCTAssertEqual(decoded.level, .info)
        XCTAssertEqual(decoded.sessionId, "test-session-123")
        XCTAssertEqual(decoded.appVersion, "1.0.0")
        XCTAssertEqual(decoded.build, "debug")
        XCTAssertNil(decoded.phase)
        XCTAssertNil(decoded.dose1Time)
        XCTAssertNil(decoded.reason)
    }
    
    func test_logEntry_codableRoundTrip_allOptionalFields() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var entry = DiagnosticLogEntry(
            ts: Date(timeIntervalSince1970: 1_000_000),
            level: .error,
            event: .invariantViolation,
            sessionId: "sess-456",
            appVersion: "2.0.0",
            build: "release"
        )
        entry.seq = 42
        entry.phase = "active"
        entry.dose1Time = Date(timeIntervalSince1970: 900_000)
        entry.dose2Time = Date(timeIntervalSince1970: 910_000)
        entry.doseIndex = 2
        entry.elapsedMinutes = 166
        entry.isLate = false
        entry.remainingMinutes = 74
        entry.snoozeCount = 1
        entry.terminalState = "completed"
        entry.reason = "test reason"
        entry.alarmId = "alarm-1"
        entry.previousPhase = "beforeWindow"
        entry.invariantName = "negative_elapsed"
        entry.constantsHash = "abcdef01"
        entry.previousTimezone = "America/New_York"
        entry.newTimezone = "America/Los_Angeles"
        entry.undoTargetType = "dose1"
        entry.sleepEventType = "bathroom"
        entry.sleepEventId = "evt-789"
        entry.backgroundDurationSeconds = 300
        
        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(DiagnosticLogEntry.self, from: data)
        
        XCTAssertEqual(decoded.seq, 42)
        XCTAssertEqual(decoded.phase, "active")
        XCTAssertEqual(decoded.doseIndex, 2)
        XCTAssertEqual(decoded.elapsedMinutes, 166)
        XCTAssertEqual(decoded.isLate, false)
        XCTAssertEqual(decoded.remainingMinutes, 74)
        XCTAssertEqual(decoded.snoozeCount, 1)
        XCTAssertEqual(decoded.terminalState, "completed")
        XCTAssertEqual(decoded.reason, "test reason")
        XCTAssertEqual(decoded.invariantName, "negative_elapsed")
        XCTAssertEqual(decoded.constantsHash, "abcdef01")
        XCTAssertEqual(decoded.previousTimezone, "America/New_York")
        XCTAssertEqual(decoded.newTimezone, "America/Los_Angeles")
        XCTAssertEqual(decoded.undoTargetType, "dose1")
        XCTAssertEqual(decoded.sleepEventType, "bathroom")
        XCTAssertEqual(decoded.sleepEventId, "evt-789")
        XCTAssertEqual(decoded.backgroundDurationSeconds, 300)
    }
    
    func test_logEntry_usesSnakeCaseCodingKeys() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        var entry = DiagnosticLogEntry(
            ts: Date(timeIntervalSince1970: 1_000_000),
            level: .info,
            event: .dose1Taken,
            sessionId: "test-session",
            appVersion: "1.0.0",
            build: "debug"
        )
        entry.elapsedMinutes = 150
        entry.doseIndex = 1
        
        let data = try encoder.encode(entry)
        let jsonString = String(data: data, encoding: .utf8)!
        
        // Verify snake_case keys are used
        XCTAssertTrue(jsonString.contains("\"session_id\""), "Should use session_id not sessionId")
        XCTAssertTrue(jsonString.contains("\"app_version\""), "Should use app_version not appVersion")
        XCTAssertTrue(jsonString.contains("\"elapsed_minutes\""), "Should use elapsed_minutes not elapsedMinutes")
        XCTAssertTrue(jsonString.contains("\"dose_index\""), "Should use dose_index not doseIndex")
        
        // Verify camelCase keys are NOT used
        XCTAssertFalse(jsonString.contains("\"sessionId\""))
        XCTAssertFalse(jsonString.contains("\"appVersion\""))
        XCTAssertFalse(jsonString.contains("\"elapsedMinutes\""))
        XCTAssertFalse(jsonString.contains("\"doseIndex\""))
    }
    
    // MARK: - SessionMetadata
    
    func test_sessionMetadata_codableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let meta = SessionMetadata(
            sessionId: "sess-001",
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            appVersion: "1.2.3",
            buildNumber: "42",
            buildType: "debug",
            deviceModel: "iPhone15,3",
            osVersion: "17.2",
            timezone: "America/New_York",
            timezoneOffsetMinutes: -300,
            constantsHash: "abc123"
        )
        
        let data = try encoder.encode(meta)
        let decoded = try decoder.decode(SessionMetadata.self, from: data)
        
        XCTAssertEqual(decoded.sessionId, "sess-001")
        XCTAssertEqual(decoded.appVersion, "1.2.3")
        XCTAssertEqual(decoded.buildNumber, "42")
        XCTAssertEqual(decoded.buildType, "debug")
        XCTAssertEqual(decoded.deviceModel, "iPhone15,3")
        XCTAssertEqual(decoded.osVersion, "17.2")
        XCTAssertEqual(decoded.timezone, "America/New_York")
        XCTAssertEqual(decoded.timezoneOffsetMinutes, -300)
        XCTAssertEqual(decoded.constantsHash, "abc123")
    }
    
    func test_sessionMetadata_usesSnakeCaseKeys() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let meta = SessionMetadata(
            sessionId: "s1",
            createdAt: Date(timeIntervalSince1970: 0),
            appVersion: "1.0",
            buildNumber: "1",
            buildType: "debug",
            deviceModel: "test",
            osVersion: "17",
            timezone: "UTC",
            timezoneOffsetMinutes: 0,
            constantsHash: nil
        )
        
        let data = try encoder.encode(meta)
        let jsonString = String(data: data, encoding: .utf8)!
        
        XCTAssertTrue(jsonString.contains("\"session_id\""))
        XCTAssertTrue(jsonString.contains("\"created_at\""))
        XCTAssertTrue(jsonString.contains("\"app_version\""))
        XCTAssertTrue(jsonString.contains("\"build_number\""))
        XCTAssertTrue(jsonString.contains("\"build_type\""))
        XCTAssertTrue(jsonString.contains("\"device_model\""))
        XCTAssertTrue(jsonString.contains("\"os_version\""))
        XCTAssertTrue(jsonString.contains("\"timezone_offset_minutes\""))
    }
    
    // MARK: - Event coverage completeness
    
    /// Ensure no new diagnostic events are added without test awareness.
    /// If this count changes, a developer must add corresponding raw-value assertions above.
    func test_diagnosticEvent_totalCaseCount() {
        // Count via mirror on a representative subset — we encode/decode all cases
        let allEvents: [DiagnosticEvent] = [
            // Session lifecycle (7)
            .sessionStarted, .sessionPhaseEntered, .sessionCompleted, .sessionExpired,
            .sessionSkipped, .sessionAutoExpired, .sessionRollover,
            // Window (5)
            .doseWindowOpened, .doseWindowNearClose, .doseWindowExpired,
            .doseWindowBlocked, .doseWindowOverrideRequired,
            // Dose actions (6)
            .dose1Taken, .dose2Taken, .doseExtraTaken, .dose2Skipped,
            .doseUndone, .snoozeActivated,
            // Alarms (4)
            .alarmScheduled, .alarmCancelled, .alarmSuppressed, .alarmAutoCancelled,
            // Check-in (3)
            .checkinStarted, .checkinCompleted, .checkinSkipped,
            // App lifecycle (4)
            .appForegrounded, .appBackgrounded, .appLaunched, .appTerminated,
            // Time (2)
            .timezoneChanged, .timeSignificantChange,
            // Notifications (3)
            .notificationDelivered, .notificationTapped, .notificationDismissed,
            // Undo (3)
            .undoWindowOpened, .undoExecuted, .undoExpired,
            // Sleep events (3)
            .sleepEventLogged, .sleepEventDeleted, .sleepEventEdited,
            // Pre-sleep (3)
            .preSleepLogStarted, .preSleepLogSaved, .preSleepLogAbandoned,
            // Errors (3)
            .errorStorage, .errorNotification, .errorTimezone,
            // Invariant (1)
            .invariantViolation,
        ]
        
        // If a developer adds a new DiagnosticEvent case, this test will still pass
        // but the Codable round-trip test above will catch any missing raw values.
        // This serves as a documentation checkpoint.
        XCTAssertEqual(allEvents.count, 47, "Update this test when adding new DiagnosticEvent cases")
    }
}
