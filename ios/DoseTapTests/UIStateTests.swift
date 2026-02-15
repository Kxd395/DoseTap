//
//  UIStateTests.swift
//  DoseTapTests
//
//  UI smoke tests, phase transitions, snooze/skip state, and settings tests.
//  Extracted from DoseTapTests.swift for maintainability.
//

import XCTest
@testable import DoseTap
import DoseCore

// MARK: - UI Smoke Tests

@MainActor
final class UISmokeTests: XCTestCase {
    
    private var storage: EventStorage!
    private var repo: SessionRepository!
    
    /// Fixed clock well after the 18:00 UTC rollover so dose times at
    /// `Date() - 180 min` never cross a session boundary on CI (UTC).
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
    
    func test_tonightEmptyState_afterSessionDelete() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-180 * 60))
        repo.setDose2Time(Date().addingTimeInterval(-15 * 60))
        repo.incrementSnooze()
        
        let sessionDate = repo.currentSessionDateString()
        
        XCTAssertNotNil(repo.dose1Time, "Session should exist before delete")
        XCTAssertNotNil(repo.dose2Time, "Dose 2 should exist before delete")
        XCTAssertEqual(repo.snoozeCount, 1, "Snooze count should be 1")
        
        repo.deleteSession(sessionDate: sessionDate)
        
        let context = repo.currentContext
        XCTAssertEqual(context.phase, .noDose1, "Phase should be noDose1 (empty state)")
        XCTAssertNil(repo.dose1Time, "Dose 1 should be nil")
        XCTAssertNil(repo.dose2Time, "Dose 2 should be nil")
        XCTAssertEqual(repo.snoozeCount, 0, "Snooze count should be 0")
        XCTAssertNil(repo.activeSessionDate, "Active session should be nil")
        
        if case .disabled(let msg) = context.primary {
            XCTAssertTrue(msg.contains("Dose 1") || msg.contains("Log"), "Empty state should prompt for Dose 1")
        }
    }
    
    func test_exportProducesData_whenSessionExists() async throws {
        let now = Date()
        repo.setDose1Time(now.addingTimeInterval(-180 * 60))
        repo.setDose2Time(now.addingTimeInterval(-15 * 60))
        
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "bathroom",
            timestamp: now.addingTimeInterval(-60 * 60),
            colorHex: nil
        )
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "lights_out",
            timestamp: now.addingTimeInterval(-120 * 60),
            colorHex: nil
        )
        
        let sessionDate = repo.currentSessionDateString()
        let sleepEvents = storage.fetchSleepEvents(forSession: sessionDate)
        
        XCTAssertGreaterThan(sleepEvents.count, 0, "Should have sleep events to export")
        XCTAssertNotNil(repo.dose1Time, "Should have dose1 to export")
        XCTAssertNotNil(repo.dose2Time, "Should have dose2 to export")
        
        for event in sleepEvents {
            XCTAssertFalse(event.id.isEmpty, "Event should have ID")
            XCTAssertFalse(event.eventType.isEmpty, "Event should have type")
        }
    }
    
    func test_exportReturnsEmpty_whenNoSession() async throws {
        storage.clearAllData()
        repo.reload()
        
        let sessionDate = repo.currentSessionDateString()
        let sleepEvents = storage.fetchSleepEvents(forSession: sessionDate)
        
        XCTAssertTrue(sleepEvents.isEmpty, "Should have no events when no session")
        XCTAssertNil(repo.dose1Time, "Should have no dose1")
        XCTAssertNil(repo.dose2Time, "Should have no dose2")
    }
}

// MARK: - Full UI State Tests

@MainActor
final class UIStateTests: XCTestCase {
    
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
    
    // MARK: - Phase Transition Tests
    
    func test_phaseTransitions_fullCycle() async throws {
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Initial phase should be noDose1")
        
        let dose1Time = Date().addingTimeInterval(-100 * 60)
        repo.setDose1Time(dose1Time)
        XCTAssertEqual(repo.currentContext.phase, .beforeWindow, "Should be beforeWindow when window not open")
        
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        XCTAssertEqual(repo.currentContext.phase, .active, "Should be active when in window")
        
        repo.setDose1Time(Date().addingTimeInterval(-235 * 60))
        XCTAssertEqual(repo.currentContext.phase, .nearClose, "Should be nearClose near window end")
        
        repo.setDose1Time(Date().addingTimeInterval(-250 * 60))
        XCTAssertEqual(repo.currentContext.phase, .closed, "Should be closed past window")
    }
    
    func test_completedPhase_afterDose2() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.setDose2Time(Date())
        XCTAssertEqual(repo.currentContext.phase, .completed, "Should be completed after dose2")
    }
    
    func test_completedPhase_afterSkip() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-160 * 60))
        repo.skipDose2()
        XCTAssertEqual(repo.currentContext.phase, .completed, "Should be completed after skip")
    }
    
    // MARK: - Snooze State Tests
    
    func test_snoozeState_throughCycles() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        
        if case .snoozeEnabled = repo.currentContext.snooze {
        } else {
            XCTFail("Snooze should be enabled initially")
        }
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 1)
        
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 2)
        
        repo.incrementSnooze()
        XCTAssertEqual(repo.snoozeCount, 3)
        if case .snoozeDisabled = repo.currentContext.snooze {
        } else {
            XCTFail("Snooze should be disabled at max")
        }
    }
    
    func test_snoozeDisabled_nearWindowEnd() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-230 * 60))
        if case .snoozeDisabled = repo.currentContext.snooze {
        } else {
            XCTFail("Snooze should be disabled when <15 min remain")
        }
    }
    
    // MARK: - Skip State Tests
    
    func test_skipState_enabledInActiveWindow() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        if case .skipEnabled = repo.currentContext.skip {
        } else {
            XCTFail("Skip should be enabled in active window")
        }
    }
    
    func test_skipState_disabledAfterSkip() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        repo.skipDose2()
        if case .skipDisabled = repo.currentContext.skip {
        } else {
            XCTFail("Skip should be disabled after skip")
        }
    }
    
    // MARK: - Primary CTA Tests
    
    func test_primaryCTA_changesWithPhase() async throws {
        if case .disabled = repo.currentContext.primary {
        } else {
            XCTFail("Primary should be disabled without dose1")
        }
        
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        switch repo.currentContext.primary {
        case .takeNow, .takeBeforeWindowEnds:
            break
        default:
            XCTFail("Primary should be take action in active window")
        }
        
        repo.setDose2Time(Date())
        if case .disabled = repo.currentContext.primary {
        } else {
            XCTFail("Primary should be disabled after completion")
        }
    }

    func test_primaryCTA_closedPhase_requiresOverride() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-250 * 60))
        XCTAssertEqual(repo.currentContext.phase, .closed)

        switch repo.currentContext.primary {
        case .takeWithOverride(let reason):
            XCTAssertFalse(reason.isEmpty, "Override CTA should include rationale.")
        default:
            XCTFail("Closed phase should surface .takeWithOverride.")
        }
    }
    
    // MARK: - Settings State Tests
    
    func test_settings_persistenceRoundTrip() {
        let defaults = UserDefaults.standard
        let testKey = "test_reduced_motion"
        
        defaults.set(true, forKey: testKey)
        XCTAssertTrue(defaults.bool(forKey: testKey), "Should persist boolean setting")
        defaults.removeObject(forKey: testKey)
    }
    
    func test_settings_targetMinutesPersistence() {
        let defaults = UserDefaults.standard
        let key = "dose2_target_minutes"
        
        defaults.removeObject(forKey: key)
        let defaultValue = defaults.integer(forKey: key)
        XCTAssertEqual(defaultValue, 0, "Missing key returns 0")
        
        defaults.set(180, forKey: key)
        XCTAssertEqual(defaults.integer(forKey: key), 180, "Should persist custom target")
        defaults.removeObject(forKey: key)
    }
    
    // MARK: - Timer Display Tests
    
    func test_remainingTime_availableInWindow() async throws {
        repo.setDose1Time(Date().addingTimeInterval(-155 * 60))
        let remaining = repo.currentContext.remainingToMax
        XCTAssertNotNil(remaining, "Should have remainingToMax in window")
        if let secs = remaining {
            XCTAssertGreaterThan(secs, 0, "Remaining should be positive in window")
        }
    }
    
    func test_remainingTime_nilWithNoSession() async throws {
        let remaining = repo.currentContext.remainingToMax
        XCTAssertNil(remaining, "No remaining time without session")
    }
}

// MARK: - PreSleep Card State Tests

final class PreSleepCardStateTests: XCTestCase {
    func test_preSleepCardState_loggedHidesCTA() {
        let log = StoredPreSleepLog(
            id: "log-123",
            sessionId: "2025-12-26",
            createdAtUtc: "2025-12-26T03:22:00Z",
            localOffsetMinutes: -300,
            completionState: "complete",
            answers: nil
        )
        let loggedState = PreSleepCardState(log: log)
        XCTAssertTrue(loggedState.isLogged)
        XCTAssertEqual(loggedState.action, .edit(id: "log-123"))
        
        let emptyState = PreSleepCardState(log: nil)
        XCTAssertFalse(emptyState.isLogged)
        XCTAssertEqual(emptyState.action, .start)
    }
    
    func test_preSleepCardState_editActionUsesSameId() {
        let log = StoredPreSleepLog(
            id: "log-999",
            sessionId: "2025-12-26",
            createdAtUtc: "2025-12-26T05:00:00Z",
            localOffsetMinutes: 0,
            completionState: "complete",
            answers: nil
        )
        let state = PreSleepCardState(log: log)
        XCTAssertEqual(state.action, .edit(id: "log-999"))
    }
}
