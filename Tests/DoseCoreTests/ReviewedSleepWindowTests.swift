import XCTest
@testable import DoseCore

final class ReviewedSleepWindowTests: XCTestCase {
    func testCollectedWindowRoundTripAndFlatFieldsPreserveMissingness() throws {
        var summary = CollectedNightSummary()
        XCTAssertNil(try JSONDecoder().decode(CollectedNightSummary.self, from: Data(#"{"version":1}"#.utf8)).reviewedSleepWindow)
        XCTAssertTrue(summary.fields.filter { $0.0.hasPrefix("reviewed_window_") }.allSatisfy { $0.1 == nil })
        summary.reviewedSleepWindow = window()
        let decoded = try JSONDecoder().decode(CollectedNightSummary.self, from: JSONEncoder().encode(summary))
        XCTAssertEqual(decoded.reviewedSleepWindow, summary.reviewedSleepWindow)
        let fields = Dictionary(uniqueKeysWithValues: decoded.fields)
        XCTAssertEqual(fields["reviewed_window_source"] ?? nil, "user_reviewed")
        XCTAssertEqual(fields["reviewed_window_entry_timezone"] ?? nil, "America/New_York")
        XCTAssertNotNil(fields["reviewed_window_start_at_utc"] ?? nil)
        XCTAssertNil(decoded.estimatedSleepAfterDose2Minutes)
    }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func window(start: Date? = nil, end: Date? = nil, sessionID: String = "session-A") -> ReviewedSleepWindow {
        .init(sessionID: sessionID, start: start ?? self.start,
              end: end ?? self.start.addingTimeInterval(3600),
              entryTimeZone: TimeZone(identifier: "America/New_York")!,
              reviewedAt: self.start.addingTimeInterval(7200))
    }
    func testWindowIsIndependentFromFinalWakeAndLegacyAnswersDecode() throws {
        let data = Data(#"{"wakeMethod":"unknown","dayType":"unknown"}"#.utf8)
        var diary = try JSONDecoder().decode(NightOutcomeDiary.self, from: data)
        XCTAssertNil(diary.reviewedSleepWindow)
        diary.reviewedSleepWindow = window()
        XCTAssertNil(diary.finalWakeAt)
        XCTAssertNil(diary.validationError(now: start.addingTimeInterval(7200)))
        XCTAssertEqual(try JSONDecoder().decode(NightOutcomeDiary.self, from: JSONEncoder().encode(diary)), diary)
        XCTAssertEqual(diary.reviewedSleepWindow?.source, "user_reviewed")
    }
    func testInvalidBoundsReviewTimeAndIdentityAreRejected() {
        let now = start.addingTimeInterval(7200)
        for value in [window(end: start), window(end: start.addingTimeInterval(-1)),
                      window(end: start.addingTimeInterval(7201)), window(start: .init(timeIntervalSince1970: .nan)),
                      window(end: .init(timeIntervalSince1970: .infinity)), window(sessionID: " ")] {
            XCTAssertNotNil(value.validationError(now: now))
        }
        XCTAssertNotNil(window().validationError(now: start))
        XCTAssertNotNil(window().validationError(now: .init(timeIntervalSince1970: .nan)))
    }
    func testCorrectionAndRemovalNeedReasonButInitialEntryDoesNot() {
        var old = NightOutcomeDiary(), edited = old
        edited.reviewedSleepWindow = window()
        XCTAssertFalse(edited.changesAnsweredFields(of: old))
        old = edited
        XCTAssertFalse(edited.changesAnsweredFields(of: old))
        edited.reviewedSleepWindow = window(end: start.addingTimeInterval(4000))
        XCTAssertTrue(edited.changesAnsweredFields(of: old))
        edited.reviewedSleepWindow = nil
        XCTAssertTrue(edited.changesAnsweredFields(of: old))
    }
    func testRepeatedHourRetainsEntryZoneOffsetsAndAbsoluteElapsedTime() throws {
        let formatter = ISO8601DateFormatter()
        let lower = try XCTUnwrap(formatter.date(from: "2026-11-01T01:30:00-04:00"))
        let upper = try XCTUnwrap(formatter.date(from: "2026-11-01T01:30:00-05:00"))
        let value = ReviewedSleepWindow(sessionID: "session-A", start: lower, end: upper,
            entryTimeZone: TimeZone(identifier: "America/New_York")!, reviewedAt: upper)
        XCTAssertNil(value.validationError(now: upper))
        XCTAssertEqual(value.end.timeIntervalSince(value.start), 3600)
        XCTAssertEqual(value.startUTCOffsetSeconds, -14400)
        XCTAssertEqual(value.endUTCOffsetSeconds, -18000)
        XCTAssertEqual(value.entryTimeZoneID, "America/New_York")
    }
    func testUnsupportedVersionSourceAndZoneFailValidation() throws {
        let data = try JSONEncoder().encode(window())
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in [("version", 2 as Any), ("source", "automatic"), ("entryTimeZoneID", "Not/AZone")] {
            var object = original; object[key] = value
            let decoded = try JSONDecoder().decode(ReviewedSleepWindow.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNotNil(decoded.validationError(now: start.addingTimeInterval(7200)))
        }
    }
}
