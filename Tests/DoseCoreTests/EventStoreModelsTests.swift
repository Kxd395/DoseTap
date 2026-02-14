import XCTest
@testable import DoseCore

final class EventStoreModelsTests: XCTestCase {

    // MARK: - StoredSleepEvent

    func test_storedSleepEvent_init() {
        let e = StoredSleepEvent(
            id: "e1", eventType: "bathroom",
            timestamp: Date(timeIntervalSince1970: 1000),
            sessionDate: "2026-01-19"
        )
        XCTAssertEqual(e.id, "e1")
        XCTAssertEqual(e.eventType, "bathroom")
        XCTAssertEqual(e.sessionDate, "2026-01-19")
        XCTAssertNil(e.colorHex)
        XCTAssertNil(e.notes)
    }

    func test_storedSleepEvent_with_optional_fields() {
        let e = StoredSleepEvent(
            id: "e2", eventType: "lights_out",
            timestamp: Date(), sessionDate: "2026-01-19",
            colorHex: "#FF0000", notes: "test note"
        )
        XCTAssertEqual(e.colorHex, "#FF0000")
        XCTAssertEqual(e.notes, "test note")
    }

    func test_storedSleepEvent_equatable() {
        let t = Date(timeIntervalSince1970: 1000)
        let a = StoredSleepEvent(id: "e1", eventType: "bathroom", timestamp: t, sessionDate: "2026-01-19")
        let b = StoredSleepEvent(id: "e1", eventType: "bathroom", timestamp: t, sessionDate: "2026-01-19")
        XCTAssertEqual(a, b)
    }

    // MARK: - StoredDoseEvent

    func test_storedDoseEvent_init() {
        let e = StoredDoseEvent(
            id: "d1", eventType: "dose1",
            timestamp: Date(timeIntervalSince1970: 2000),
            sessionDate: "2026-01-19"
        )
        XCTAssertEqual(e.id, "d1")
        XCTAssertEqual(e.eventType, "dose1")
        XCTAssertNil(e.metadata)
    }

    func test_storedDoseEvent_with_metadata() {
        let e = StoredDoseEvent(
            id: "d2", eventType: "dose2",
            timestamp: Date(), sessionDate: "2026-01-19",
            metadata: "{\"amount_mg\": 2250}"
        )
        XCTAssertEqual(e.metadata, "{\"amount_mg\": 2250}")
    }

    func test_storedDoseEvent_equatable() {
        let t = Date(timeIntervalSince1970: 2000)
        let a = StoredDoseEvent(id: "d1", eventType: "dose1", timestamp: t, sessionDate: "2026-01-19")
        let b = StoredDoseEvent(id: "d1", eventType: "dose1", timestamp: t, sessionDate: "2026-01-19")
        XCTAssertEqual(a, b)
    }

    // MARK: - PreSleepLogAnswers

    func test_preSleepLogAnswers_defaults_nil() {
        let a = PreSleepLogAnswers()
        XCTAssertNil(a.sleepGoalHours)
        XCTAssertNil(a.caffeineLast6Hours)
        XCTAssertNil(a.stressLevel)
    }

    func test_preSleepLogAnswers_codable() throws {
        let original = PreSleepLogAnswers(
            sleepGoalHours: 8, sleepGoalMinutes: 0,
            caffeineLast6Hours: true, alcoholLast6Hours: false,
            stressLevel: 7, notes: "Felt good"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PreSleepLogAnswers.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_preSleepLogAnswers_equatable() {
        let a = PreSleepLogAnswers(sleepGoalHours: 8)
        let b = PreSleepLogAnswers(sleepGoalHours: 8)
        XCTAssertEqual(a, b)
    }

    // MARK: - StoredPreSleepLog

    func test_storedPreSleepLog_init() {
        let log = StoredPreSleepLog(
            id: "psl1", sessionId: "s1",
            createdAtUTC: Date(timeIntervalSince1970: 3000),
            localOffsetMinutes: -300,
            completionState: "completed",
            answersJson: "{}"
        )
        XCTAssertEqual(log.id, "psl1")
        XCTAssertEqual(log.completionState, "completed")
    }

    // MARK: - StoredMorningCheckIn

    func test_storedMorningCheckIn_defaults() {
        let ci = StoredMorningCheckIn(
            id: "ci1", sessionId: "s1",
            timestamp: Date(), sessionDate: "2026-01-19"
        )
        XCTAssertEqual(ci.sleepQuality, 3)
        XCTAssertEqual(ci.feelRested, "moderate")
        XCTAssertFalse(ci.hadSleepParalysis)
        XCTAssertFalse(ci.hadHallucinations)
        XCTAssertFalse(ci.hadAutomaticBehavior)
    }

    func test_storedMorningCheckIn_equatable() {
        let t = Date(timeIntervalSince1970: 4000)
        let a = StoredMorningCheckIn(id: "ci1", sessionId: "s1", timestamp: t, sessionDate: "2026-01-19")
        let b = StoredMorningCheckIn(id: "ci1", sessionId: "s1", timestamp: t, sessionDate: "2026-01-19")
        XCTAssertEqual(a, b)
    }

    // MARK: - SessionSummary

    func test_sessionSummary_interval_calculated() {
        let d1 = Date(timeIntervalSince1970: 0)
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let s = SessionSummary(sessionDate: "2026-01-19", dose1Time: d1, dose2Time: d2)
        XCTAssertEqual(s.intervalMinutes, 165)
    }

    func test_sessionSummary_interval_nil_without_both_doses() {
        let s = SessionSummary(sessionDate: "2026-01-19", dose1Time: Date())
        XCTAssertNil(s.intervalMinutes)
    }

    func test_sessionSummary_skipped_alias() {
        let s = SessionSummary(sessionDate: "2026-01-19", dose2Skipped: true)
        XCTAssertTrue(s.skipped)
    }

    func test_sessionSummary_id_is_sessionDate() {
        let s = SessionSummary(sessionDate: "2026-01-19")
        XCTAssertEqual(s.id, "2026-01-19")
    }

    func test_sessionSummary_eventCount_defaults_to_sleepEvents_count() {
        let events = [
            StoredSleepEvent(id: "e1", eventType: "bathroom", timestamp: Date(), sessionDate: "2026-01-19"),
            StoredSleepEvent(id: "e2", eventType: "lights_out", timestamp: Date(), sessionDate: "2026-01-19"),
        ]
        let s = SessionSummary(sessionDate: "2026-01-19", sleepEvents: events)
        XCTAssertEqual(s.eventCount, 2)
    }

    func test_sessionSummary_explicit_eventCount_overrides() {
        let s = SessionSummary(sessionDate: "2026-01-19", sleepEvents: [], eventCount: 10)
        XCTAssertEqual(s.eventCount, 10)
    }
}
