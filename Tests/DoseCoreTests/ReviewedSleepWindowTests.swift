import XCTest
@testable import DoseCore

final class ReviewedSleepWindowTests: XCTestCase {
    func testAssessmentRechecksDosesAndRetainsMissingWindow() {
        let value = window(), now = start.addingTimeInterval(7200)
        func assess(_ doses: [StoredDoseEvent]) -> ReviewedWindowAssessment {
            .calculate(window: value, sessionID: "session-A", doses: doses, otherWindows: [], naps: [], now: now)
        }
        let first = StoredDoseEvent(id: "d1", eventType: "dose1", timestamp: start, sessionDate: "")
        XCTAssertEqual(assess([first]).status, .checked)
        let outside = StoredDoseEvent(id: "d2", eventType: "dose2", timestamp: value.end, sessionDate: "")
        XCTAssertTrue(assess([first, outside]).reasons.contains(.doseOutsideWindow))
        XCTAssertTrue(assess([outside]).reasons.contains(.invalidDoseRecords))
        XCTAssertEqual(ReviewedWindowAssessment.calculate(window: nil, sessionID: "session-A", doses: [],
            otherWindows: [], naps: [], now: now).status, .missing)
        XCTAssertEqual(assess([first]).status, .checked) // Recalculation after correction, not cached failure.
    }
    func testAssessmentOverlapsAreHalfOpenAndSessionBound() {
        let value = window(), now = start.addingTimeInterval(7200)
        let overlap = window(start: start.addingTimeInterval(1800), end: start.addingTimeInterval(5400), sessionID: "session-B")
        let touching = window(start: value.end, end: start.addingTimeInterval(5400), sessionID: "session-C")
        let result = ReviewedWindowAssessment.calculate(window: value, sessionID: "session-A", doses: [],
            otherWindows: [overlap, touching], naps: [], now: now)
        XCTAssertEqual(result.reasons, [.overlappingWindow])
        XCTAssertEqual(ReviewedWindowAssessment.calculate(window: value, sessionID: "wrong", doses: [],
            otherWindows: [], naps: [], now: now).reasons, [.invalidWindow])
    }
    func testAssessmentNapsKeepIncompleteAndAmbiguousEvidence() {
        typealias Marker = ReviewedWindowAssessment.NapMarker
        let value = window(), now = start.addingTimeInterval(7200)
        func marker(_ id: String, _ seconds: Double, _ isStart: Bool, _ group: String = "a") -> Marker {
            .init(id: id, group: group, timestamp: start.addingTimeInterval(seconds), isStart: isStart)
        }
        func assess(_ naps: [Marker]) -> ReviewedWindowAssessment {
            .calculate(window: value, sessionID: "session-A", doses: [], otherWindows: [], naps: naps, now: now)
        }
        XCTAssertEqual(assess([marker("s", -600, true), marker("e", 0, false)]).status, .checked)
        XCTAssertEqual(assess([marker("s", 600, true), marker("e", 900, false)]).reasons, [.overlappingNap])
        XCTAssertEqual(assess([marker("s", -600, true)]).reasons, [.incompleteNap])
        XCTAssertEqual(assess([marker("e", 900, false)]).reasons, [.incompleteNap])
        let ambiguous = [marker("s", 600, true), marker("s2", 700, true), marker("e", 900, false)]
        XCTAssertEqual(assess(ambiguous).reasons, [.ambiguousNap])
        XCTAssertEqual(assess(ambiguous).reasons, assess(ambiguous.reversed()).reasons)
        XCTAssertEqual(assess([marker("s", 600, true), marker("e", 900, false, "other")]).reasons, [.incompleteNap])
    }
    func testCollectedWindowRoundTripAndFlatFieldsPreserveMissingness() throws {
        var summary = CollectedNightSummary()
        XCTAssertNil(try JSONDecoder().decode(CollectedNightSummary.self, from: Data(#"{"version":1}"#.utf8)).reviewedSleepWindow)
        XCTAssertTrue(summary.fields.filter { $0.0.hasPrefix("reviewed_window_") }.allSatisfy { $0.1 == nil })
        summary.reviewedSleepWindow = window()
        summary.reviewedWindowAssessment = .calculate(window: summary.reviewedSleepWindow, sessionID: "session-A",
            doses: [], otherWindows: [], naps: [], now: start.addingTimeInterval(7200))
        let decoded = try JSONDecoder().decode(CollectedNightSummary.self, from: JSONEncoder().encode(summary))
        XCTAssertEqual(decoded.reviewedSleepWindow, summary.reviewedSleepWindow)
        XCTAssertEqual(decoded.reviewedWindowAssessment, summary.reviewedWindowAssessment)
        let fields = Dictionary(uniqueKeysWithValues: decoded.fields)
        XCTAssertEqual(fields["reviewed_window_source"] ?? nil, "user_reviewed")
        XCTAssertEqual(fields["reviewed_window_assessment_status"] ?? nil, "checked")
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
