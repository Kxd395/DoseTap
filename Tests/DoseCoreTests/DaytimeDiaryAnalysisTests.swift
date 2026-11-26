import XCTest
@testable import DoseCore
final class DaytimeDiaryAnalysisTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func testGroupingKeepsOriginsAndSettingsSeparate() throws {
        let protocolID = UUID()
        func value(_ origin: DaytimeCheckIn.Origin, _ score: Int, _ setting: DaytimeCheckIn.Setting) throws -> DaytimeCheckIn {
            try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: score, origin: origin, setting: setting, promptID: origin == .scheduled ? UUID() : nil, samplingProtocolID: origin == .scheduled ? protocolID : nil)
        }
        let values = try [value(.scheduled, 2, .work), value(.scheduled, 4, .work), value(.symptomTriggered, 9, .work), value(.scheduled, 1, .offWork)]
        let report = try DaytimeDiaryAnalysis(observations: values, events: [], start: now.addingTimeInterval(-86400), end: now, now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(report.groups.count, 3)
        let scheduled = try XCTUnwrap(report.groups.first { $0.origin == .scheduled && $0.setting == .work })
        XCTAssertEqual(Set(scheduled.observationIDs), Set(values.prefix(2).map(\.id)))
        XCTAssertEqual(scheduled.median, 3); XCTAssertEqual(scheduled.ratedDays, 1); XCTAssertEqual(scheduled.distribution, [2: 1, 4: 1])
    }
    func testMissingScoreIsNotZeroAndEventsAreNotReviews() throws {
        let event = try DaytimeEvent(kind: .unplannedSleep, occurredAt: now, recordedAt: now, timeZoneIdentifier: "UTC")
        let review = try DaytimeEventReview(from: now.addingTimeInterval(-3600), to: now, status: .eventsReported, eventIDs: [event.id])
        let a = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: nil, status: .unsure, eventReview: review)
        let b = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 0, eventReview: review)
        let report = try DaytimeDiaryAnalysis(observations: [a,b], events: [event], start: now.addingTimeInterval(-86400), end: now, now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(report.eventCountsByKind[.unplannedSleep], 1)
        XCTAssertEqual(report.copingResponseCounts[.unanswered], 2)
        XCTAssertEqual(report.groups.first?.entryCount, 2)
        XCTAssertEqual(report.answeredCount, 1); XCTAssertEqual(report.unplannedSleepEvents, 1)
        XCTAssertEqual(report.reviewSubmissionDays, 1); XCTAssertEqual(report.groups.first?.median, 0)
        XCTAssertThrowsError(try DaytimeDiaryAnalysis(observations: [], events: [], start: now, end: now.addingTimeInterval(1), now: now, timeZone: .current))
    }
}

extension DaytimeDiaryAnalysisTests {
    func testUnknownScheduledProtocolsDoNotPoolAndRevisionsDoNotDoubleCount() throws {
        let values = try (0..<2).map { _ in try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 4, origin: .scheduled, promptID: UUID()) }
        let report = try DaytimeDiaryAnalysis(observations: values, events: [], start: now, end: now, now: now, timeZone: .current)
        XCTAssertEqual(report.groups.count, 2)
        XCTAssertThrowsError(try DaytimeDiaryAnalysis(observations: [values[0], values[0]], events: [], start: now, end: now, now: now, timeZone: .current))
    }
    func testFourEventsOnTwelveReviewedDatesInFourteenDaysIsNotExtrapolated() throws {
        let end = ISO8601DateFormatter().date(from: "2026-09-30T23:00:00Z")!
        let start = ISO8601DateFormatter().date(from: "2026-09-17T00:00:00Z")!
        let records = try (0..<12).map { day in
            let time = end.addingTimeInterval(Double(-day * 86400))
            return try DaytimeCheckIn(assessedAt: time, recordedAt: end, timeZoneIdentifier: "UTC", response: 1, eventReview: DaytimeEventReview(from: time.addingTimeInterval(-3600), to: time, status: .noneReported))
        }
        let events = try (0..<4).map { day in try DaytimeEvent(kind: .unplannedSleep, occurredAt: end.addingTimeInterval(Double(-day * 86400)), recordedAt: end, timeZoneIdentifier: "UTC") }
        let report = try DaytimeDiaryAnalysis(observations: records, events: events, start: start, end: end, now: end, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(report.unplannedSleepEvents, 4); XCTAssertEqual(report.reviewedCalendarDays, 12)
        XCTAssertEqual(report.fullyReviewedCalendarDays, 0); XCTAssertEqual(report.partiallyReviewedCalendarDays, 12)
        XCTAssertEqual(report.reviewSubmissionDays, 1)
        XCTAssertEqual(report.calendarDays, 14); XCTAssertEqual(report.daysWithoutReviewedInterval, 2)
    }
    func testTimezonesAndProtocolChangesKeepGroupsSeparate() throws {
        let a = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 1)
        let b = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "America/New_York", response: 1)
        let report = try DaytimeDiaryAnalysis(observations: [a,b], events: [], start: now, end: now, now: now, timeZone: .current)
        XCTAssertEqual(Set(report.groups.map(\.timeZoneIdentifier)), Set(["UTC", "America/New_York"]))
    }
}

extension DaytimeDiaryAnalysisTests {
    func testReviewUnionClipsRangeAndHonorsDSTCalendarDays() throws {
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "2026-03-08T05:00:00Z")!
        let end = formatter.date(from: "2026-03-09T04:00:00Z")!
        let middle = start.addingTimeInterval(12 * 3600)
        let a = try DaytimeCheckIn(assessedAt: end, recordedAt: end, timeZoneIdentifier: "America/New_York", response: nil, status: .incomplete, eventReview: DaytimeEventReview(from: start.addingTimeInterval(-3600), to: middle, status: .noneReported))
        let b = try DaytimeCheckIn(assessedAt: end, recordedAt: end, timeZoneIdentifier: "America/New_York", response: nil, status: .incomplete, eventReview: DaytimeEventReview(from: middle, to: end, status: .noneReported))
        let report = try DaytimeDiaryAnalysis(observations: [a,b], events: [], start: start, end: end, now: end, timeZone: TimeZone(identifier: "America/New_York")!)
        XCTAssertEqual(report.reviewedCalendarDays, 1); XCTAssertEqual(report.fullyReviewedCalendarDays, 1)
    }
}

extension DaytimeDiaryAnalysisTests {
    func testHalfOpenBoundaryExcludesMidnightSamplesAndPreservesFullReviewDay() throws {
        let start = ISO8601DateFormatter().date(from: "2026-09-30T00:00:00Z")!
        let end = start.addingTimeInterval(86400)
        let observation = try DaytimeCheckIn(assessedAt: end, recordedAt: end, timeZoneIdentifier: "UTC", response: 4, eventReview: DaytimeEventReview(from: start, to: end, status: .noneReported))
        let event = try DaytimeEvent(kind: .unplannedSleep, occurredAt: end, recordedAt: end, timeZoneIdentifier: "UTC")
        let report = try DaytimeDiaryAnalysis(observations: [observation], events: [event], start: start, end: end, now: end, timeZone: TimeZone(secondsFromGMT: 0)!, includesEnd: false)
        XCTAssertEqual(report.calendarDays, 1); XCTAssertEqual(report.fullyReviewedCalendarDays, 1)
        XCTAssertTrue(report.observations.isEmpty); XCTAssertEqual(report.unplannedSleepEvents, 0)
        XCTAssertEqual(report.reviewSubmissionDays, 0)
        XCTAssertThrowsError(try DaytimeDiaryAnalysis(observations: [], events: [], start: end, end: end, now: end, timeZone: .current, includesEnd: false))
    }
}

extension DaytimeDiaryAnalysisTests {
    func testSamplingProtocolSurvivesCorrectionAndLegacyDecoding() throws {
        let value = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 3, origin: .scheduled, promptID: UUID(), samplingProtocolID: UUID(), samplingProtocolLabel: "4 hours after main wake")
        let correction = try value.corrected(response: 4, status: .answered, reason: "Mistap", recordedAt: now)
        XCTAssertEqual(try DaytimeCheckInLedger(revisions: [value, correction]).current.first?.samplingProtocolID, value.samplingProtocolID)
        XCTAssertEqual(try DaytimeCheckIn.decode(correction.encoded()).samplingProtocolLabel, value.samplingProtocolLabel)
        let legacy = try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 2)
        XCTAssertNil(try DaytimeCheckIn.decode(legacy.encoded()).samplingProtocolID)
        XCTAssertThrowsError(try DaytimeCheckIn(assessedAt: now, recordedAt: now, timeZoneIdentifier: "UTC", response: 3, samplingProtocolID: UUID()))
    }
}
