import XCTest
@testable import DoseCore

/// Tests for session_id backfill migration and data integrity
final class SessionIdBackfillTests: XCTestCase {
    
    // MARK: - Session Key Computation Tests
    
    /// Test that sessionKey computes correctly for various timestamps
    func test_sessionKey_beforeRollover_belongsToPreviousDay() {
        // 3:00 PM on Dec 26 → belongs to Dec 25 session
        let dec26_3pm = makeDate(year: 2025, month: 12, day: 26, hour: 15, minute: 0)
        let key = sessionKey(for: dec26_3pm, timeZone: TimeZone(identifier: "America/New_York")!, rolloverHour: 18)
        XCTAssertEqual(key, "2025-12-25", "3 PM should belong to previous day's session")
    }
    
    func test_sessionKey_afterRollover_belongsToCurrentDay() {
        // 7:00 PM on Dec 26 → belongs to Dec 26 session
        let dec26_7pm = makeDate(year: 2025, month: 12, day: 26, hour: 19, minute: 0)
        let key = sessionKey(for: dec26_7pm, timeZone: TimeZone(identifier: "America/New_York")!, rolloverHour: 18)
        XCTAssertEqual(key, "2025-12-26", "7 PM should belong to current day's session")
    }
    
    func test_sessionKey_exactRollover_belongsToCurrentDay() {
        // 6:00 PM on Dec 26 → belongs to Dec 26 session (boundary)
        let dec26_6pm = makeDate(year: 2025, month: 12, day: 26, hour: 18, minute: 0)
        let key = sessionKey(for: dec26_6pm, timeZone: TimeZone(identifier: "America/New_York")!, rolloverHour: 18)
        XCTAssertEqual(key, "2025-12-26", "Exactly 6 PM should belong to current day's session")
    }
    
    func test_sessionKey_justBeforeRollover_belongsToPreviousDay() {
        // 5:59 PM on Dec 26 → belongs to Dec 25 session
        let dec26_559pm = makeDate(year: 2025, month: 12, day: 26, hour: 17, minute: 59)
        let key = sessionKey(for: dec26_559pm, timeZone: TimeZone(identifier: "America/New_York")!, rolloverHour: 18)
        XCTAssertEqual(key, "2025-12-25", "5:59 PM should belong to previous day's session")
    }
    
    func test_sessionKey_midnight_belongsToPreviousDay() {
        // 12:30 AM on Dec 26 → belongs to Dec 25 session
        let dec26_1230am = makeDate(year: 2025, month: 12, day: 26, hour: 0, minute: 30)
        let key = sessionKey(for: dec26_1230am, timeZone: TimeZone(identifier: "America/New_York")!, rolloverHour: 18)
        XCTAssertEqual(key, "2025-12-25", "12:30 AM should belong to previous day's session")
    }
    
    // MARK: - ISO8601 Parsing Tests (for migration)
    
    func test_iso8601_parsing_withFractionalSeconds() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let dateStr = "2025-12-26T03:00:00.123Z"
        let date = formatter.date(from: dateStr)
        XCTAssertNotNil(date, "Should parse ISO8601 with fractional seconds")
    }
    
    func test_iso8601_parsing_withoutFractionalSeconds() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        let dateStr = "2025-12-26T03:00:00Z"
        let date = formatter.date(from: dateStr)
        XCTAssertNotNil(date, "Should parse ISO8601 without fractional seconds")
    }
    
    // MARK: - Helpers
    
    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = TimeZone(identifier: "America/New_York")
        return Calendar.current.date(from: components)!
    }
}
