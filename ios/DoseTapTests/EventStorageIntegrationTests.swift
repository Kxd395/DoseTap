import XCTest
@testable import DoseTap

@MainActor
final class EventStorageIntegrationTests: XCTestCase {
    private var storage: EventStorage!
    private var iso: ISO8601DateFormatter!

    override func setUp() async throws {
        storage = EventStorage.inMemory()
        iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    override func tearDown() async throws {
        storage = nil
        iso = nil
    }

    func test_fetchRecentSessionsLocal_handlesSleepOnlyDoseOnlyAndMixedSessions() {
        let sleepOnlyDate = "2026-02-10"
        let doseOnlyDate = "2026-02-11"
        let mixedDate = "2026-02-12"

        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "lights_out",
            timestamp: makeDate("2026-02-10T23:10:00.000Z"),
            sessionDate: sleepOnlyDate,
            sessionId: sleepOnlyDate,
            colorHex: nil,
            notes: nil
        )

        storage.insertDoseEvent(
            eventType: "dose1",
            timestamp: makeDate("2026-02-11T22:00:00.000Z"),
            sessionDate: doseOnlyDate,
            sessionId: doseOnlyDate,
            metadata: nil
        )

        storage.insertDoseEvent(
            eventType: "dose1",
            timestamp: makeDate("2026-02-12T22:05:00.000Z"),
            sessionDate: mixedDate,
            sessionId: mixedDate,
            metadata: nil
        )
        storage.insertDoseEvent(
            eventType: "snooze",
            timestamp: makeDate("2026-02-12T22:30:00.000Z"),
            sessionDate: mixedDate,
            sessionId: mixedDate,
            metadata: nil
        )
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "asleep",
            timestamp: makeDate("2026-02-12T23:00:00.000Z"),
            sessionDate: mixedDate,
            sessionId: mixedDate,
            colorHex: nil,
            notes: nil
        )

        let sessions = storage.fetchRecentSessionsLocal(days: 10)
        let keyed = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionDate, $0) })

        XCTAssertEqual(keyed.count, 3)

        let sleepOnly = tryUnwrap(keyed[sleepOnlyDate])
        XCTAssertNil(sleepOnly.dose1Time)
        XCTAssertEqual(sleepOnly.eventCount, 1)

        let doseOnly = tryUnwrap(keyed[doseOnlyDate])
        XCTAssertNotNil(doseOnly.dose1Time)
        XCTAssertEqual(doseOnly.eventCount, 0)

        let mixed = tryUnwrap(keyed[mixedDate])
        XCTAssertNotNil(mixed.dose1Time)
        XCTAssertEqual(mixed.snoozeCount, 1)
        XCTAssertEqual(mixed.eventCount, 1)
    }

    func test_fetchDoseLog_returnsCurrentAndHistoricalSessionData() {
        let historicalDate = "2026-02-11"
        let currentDate = "2026-02-12"

        let historicalDose1 = makeDate("2026-02-11T22:00:00.000Z")
        storage.insertDoseEvent(
            eventType: "dose1",
            timestamp: historicalDose1,
            sessionDate: historicalDate,
            sessionId: historicalDate,
            metadata: nil
        )
        storage.insertDoseEvent(
            eventType: "snooze",
            timestamp: makeDate("2026-02-11T22:20:00.000Z"),
            sessionDate: historicalDate,
            sessionId: historicalDate,
            metadata: nil
        )

        let currentDose1 = makeDate("2026-02-12T22:05:00.000Z")
        let currentDose2 = makeDate("2026-02-13T02:30:00.000Z")
        storage.saveDose1(timestamp: currentDose1, sessionId: currentDate, sessionDateOverride: currentDate)
        storage.saveDose2(timestamp: currentDose2, isEarly: false, isExtraDose: false, isLate: false, sessionId: currentDate, sessionDateOverride: currentDate)

        let historicalLog = tryUnwrap(storage.fetchDoseLog(forSession: historicalDate))
        XCTAssertEqual(historicalLog.sessionDate, historicalDate)
        XCTAssertEqual(historicalLog.snoozeCount, 1)
        XCTAssertEqual(historicalLog.dose1Time.timeIntervalSince1970, historicalDose1.timeIntervalSince1970, accuracy: 0.001)

        let currentLog = tryUnwrap(storage.fetchDoseLog(forSession: currentDate))
        XCTAssertEqual(currentLog.sessionDate, currentDate)
        XCTAssertNotNil(currentLog.dose1Time)
        XCTAssertNotNil(currentLog.dose2Time)
        XCTAssertEqual(currentLog.dose1Time.timeIntervalSince1970, currentDose1.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(tryUnwrap(currentLog.dose2Time).timeIntervalSince1970, currentDose2.timeIntervalSince1970, accuracy: 0.001)
    }

    private func makeDate(_ isoString: String) -> Date {
        guard let date = iso.date(from: isoString) else {
            XCTFail("Invalid ISO date: \(isoString)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func tryUnwrap<T>(_ value: T?) -> T {
        guard let value else {
            XCTFail("Expected value to be non-nil")
            fatalError("Unreachable")
        }
        return value
    }
}
