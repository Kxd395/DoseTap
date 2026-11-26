import XCTest
@testable import DoseCore

final class NapDiaryTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    func episode(_ id: String = "a", offset: Double = 0) -> NapEpisode {
        NapEpisode(id: id, day: "2026-09-21", timeZoneID: "UTC", start: start.addingTimeInterval(offset), end: start.addingTimeInterval(offset + 3600), estimatedSleepMinutes: 30, recordedAt: start.addingTimeInterval(7200))
    }
    func testReportedSleepIsNotRestWindowAndDurationOnlyHasNoClockPosition() throws {
        var value = episode(); XCTAssertEqual(value.restMinutes, 60)
        XCTAssertEqual(value.estimatedSleepMinutes, 30)
        value.start = nil; value.end = nil
        XCTAssertTrue(value.isValid); XCTAssertNil(value.restMinutes)
        XCTAssertEqual(NapDayProjection(timeZoneID: "UTC", day: value.day, episodes: [value], review: .partial).estimatedMinutes, 30)
    }
    func testOverlapNeedsReviewUntilExplicitSameEpisodeLink() {
        let a = episode(), b = episode("b", offset: 1800)
        let conflict = NapDayProjection(timeZoneID: "UTC", day: a.day, episodes: [a,b], review: .complete)
        XCTAssertEqual(conflict.overlapIDs, Set(["a", "b"]))
        XCTAssertNil(conflict.estimatedMinutes); XCTAssertEqual(conflict.unavailableCount, 2)
        var linked = b; linked.duplicateOf = a.id; linked.reason = "Same nap recorded twice"
        let resolved = NapDayProjection(timeZoneID: "UTC", day: a.day, episodes: [a,linked], review: .complete)
        XCTAssertEqual(resolved.episodeCount, 1); XCTAssertEqual(resolved.estimatedMinutes, 30)
        XCTAssertEqual(resolved.estimatedMinutesByIntent[.unknown], 30)
        XCTAssertNil(conflict.estimatedMinutesByIntent[.unknown])
    }
    func testNoNapReviewCannotSuppressEpisodeEvidence() {
        let value = episode()
        XCTAssertTrue(NapDayProjection(timeZoneID: "UTC", day: value.day, episodes: [value], review: .none).reviewConflict)
        XCTAssertEqual(NapDayProjection(timeZoneID: "UTC", day: value.day, episodes: [], review: .none).estimatedMinutes, 0)
        XCTAssertNil(NapDayProjection(timeZoneID: "UTC", day: value.day, episodes: [], review: .unreviewed).estimatedMinutes)
    }
    func testIncompleteTimerAndUnknownEstimateStayUnavailable() {
        var value = episode(); value.end = nil; value.estimatedSleepMinutes = nil
        XCTAssertTrue(value.isValid); XCTAssertNil(value.restMinutes)
        XCTAssertNil(NapDayProjection(timeZoneID: "UTC", day: value.day, episodes: [value], review: .partial).estimatedMinutes)
    }
    func testFutureNegativeAndOversizedEstimatesRejected() {
        var value = episode(); value.estimatedSleepMinutes = 61; XCTAssertFalse(value.isValid)
        value.estimatedSleepMinutes = -1; XCTAssertFalse(value.isValid)
        value.estimatedSleepMinutes = 30; value.end = value.recordedAt.addingTimeInterval(1); XCTAssertFalse(value.isValid)
    }
    func testHistoryCannotReplacePriorRevisionOrCreateDuplicateCycle() {
        var doc = NapDiaryDocument(); let first = episode(); doc.episodes = [first]
        var next = first; next.revision = UUID(); next.predecessor = first.revision; next.reason = "Corrected estimate"; next.estimatedSleepMinutes = 20
        doc.episodes.append(next); XCTAssertTrue(doc.isValid); XCTAssertEqual(doc.current.first?.estimatedSleepMinutes, 20)
        doc.episodes.append(next); XCTAssertFalse(doc.isValid)
        var a = first, b = episode("b"); a.duplicateOf = "b"; b.duplicateOf = "a"; a.reason = "same"; b.reason = "same"
        doc.episodes = [a,b]; XCTAssertFalse(doc.isValid)
    }
    func testMidnightCountDoesNotDuplicateEpisode() {
        let value = episode()
        XCTAssertEqual(NapDayProjection(timeZoneID: "UTC", day: value.day, episodes: [value], review: .partial).episodeCount, 1)
        XCTAssertEqual(NapDayProjection(timeZoneID: "UTC", day: "2026-09-22", episodes: [value], review: .unreviewed).episodeCount, 0)
    }
    func testTimersNeverPairAcrossIdentityOrConsecutiveStarts() {
        let markers = [NapTimerMarker(id: "a", sessionID: "one", date: start, isStart: true),
                       NapTimerMarker(id: "b", sessionID: "two", date: start.addingTimeInterval(3600), isStart: false)]
        let output = NapEpisode.timers(markers, zone: "UTC", asOf: start.addingTimeInterval(7200))
        XCTAssertEqual(output.count, 2); XCTAssertTrue(output.allSatisfy { $0.restMinutes == nil })
        let ambiguous = [markers[0], NapTimerMarker(id: "c", sessionID: "one", date: start.addingTimeInterval(60), isStart: true),
                         NapTimerMarker(id: "d", sessionID: "one", date: start.addingTimeInterval(3600), isStart: false)]
        XCTAssertTrue(NapEpisode.timers(ambiguous, zone: "UTC", asOf: start.addingTimeInterval(7200)).allSatisfy { $0.restMinutes == nil })
    }
    func testMidnightTimerHasOneIdentityAndNoAsleepEstimate() {
        let midnightStart = ISO8601DateFormatter().date(from: "2026-09-21T23:30:00Z")!
        let output = NapEpisode.timers([.init(id: "a", sessionID: "one", date: midnightStart, isStart: true),
            .init(id: "b", sessionID: "one", date: midnightStart.addingTimeInterval(3600), isStart: false)], zone: "UTC", asOf: midnightStart.addingTimeInterval(7200))
        XCTAssertEqual(output.first?.day, "2026-09-21")
        XCTAssertEqual(NapDayProjection(timeZoneID: "UTC", day: "2026-09-22", episodes: output, review: .unreviewed).episodeCount, 0)
        XCTAssertEqual(output.count, 1); XCTAssertEqual(output.first?.restMinutes, 60)
        XCTAssertNil(output.first?.estimatedSleepMinutes)
    }
    func testCompletenessIsBoundToReviewedEvidence() {
        var doc = NapDiaryDocument(); let original = episode()
        doc.reviews = [.init(day: original.day, timeZoneID: "UTC", status: .complete, recordedAt: original.recordedAt, episodes: [original])]
        XCTAssertEqual(doc.status(day: original.day, zone: "UTC", episodes: [original]), .complete)
        var revised = original; revised.estimatedSleepMinutes = 20
        XCTAssertEqual(doc.status(day: original.day, zone: "UTC", episodes: [revised]), .partial)
        XCTAssertEqual(doc.status(day: original.day, zone: "UTC", episodes: [original, episode("new", offset: 4000)]), .partial)
    }
    func testRepeatedSourceIDDeduplicatesButConflictingCopiesStayUnresolved() {
        let original = episode()
        XCTAssertEqual(NapDayProjection(timeZoneID: "UTC", day: original.day, episodes: [original,original], review: .partial).episodeCount, 1)
        var other = original; other.estimatedSleepMinutes = 20
        XCTAssertNil(NapDayProjection(timeZoneID: "UTC", day: original.day, episodes: [original,other], review: .partial).estimatedMinutes)
    }
    func testUnrelatedDuplicateLinkDoesNotHideAnotherDay() {
        let original = episode(); var other = episode("b", offset: 100000)
        other.day = NapEpisode.day(other.start!, "UTC"); other.recordedAt = other.end!
        other.duplicateOf = original.id; other.reason = "Same nap"
        let projection = NapDayProjection(timeZoneID: "UTC", day: other.day, episodes: [original, other], review: .complete)
        XCTAssertEqual(projection.episodeCount, 1); XCTAssertTrue(projection.unresolvedDuplicateIDs.contains(other.id))
    }
    func testDurationOnlyFutureDayAndFutureReviewAreRejected() {
        var future = episode(); future.start = nil; future.end = nil; future.day = "2026-09-30"
        XCTAssertFalse(future.isValid)
        var document = NapDiaryDocument()
        document.reviews = [.init(day: future.day, timeZoneID: "UTC", status: .none, recordedAt: start)]
        XCTAssertFalse(document.isValid)
    }
    func testConflictingDuplicateCannotBeHiddenByItsLink() {
        let root = episode("root"); var a = episode("child")
        a.duplicateOf = root.id; a.reason = "Reviewed same nap"
        var conflict = a; conflict.estimatedSleepMinutes = 10
        let value = NapDayProjection(timeZoneID: "UTC", day: a.day, episodes: [root, a, conflict], review: .partial)
        XCTAssertTrue(value.episodes.contains { $0.id == a.id })
        XCTAssertTrue(value.unresolvedDuplicateIDs.contains(a.id))
        XCTAssertNil(value.estimatedMinutes)
    }

    func testNapDoseIntervalRequiresSelectedActualEndpointsAndIdentity() throws {
        let nap = episode()
        let dose = StoredDoseEvent(id: "dose-record", eventType: "dose1", timestamp: nap.recordedAt, sessionDate: nap.day, sessionId: "session")
        let result = try XCTUnwrap(NapDoseInterval(episode: nap, dose: dose, sessionID: "session", asOf: nap.recordedAt))
        XCTAssertEqual(result.minutes, 60); XCTAssertEqual(result.napID, nap.id); XCTAssertEqual(result.doseID, dose.id)
        XCTAssertNil(NapDoseInterval(episode: nap, dose: dose, sessionID: "different", asOf: nap.recordedAt))
        var unknown = nap; unknown.end = nil
        XCTAssertNil(NapDoseInterval(episode: unknown, dose: dose, sessionID: "session", asOf: nap.recordedAt))
        let prompt = StoredDoseEvent(id: "prompt", eventType: "snooze", timestamp: dose.timestamp, sessionDate: nap.day, sessionId: "session")
        XCTAssertNil(NapDoseInterval(episode: nap, dose: prompt, sessionID: "session", asOf: nap.recordedAt))
        XCTAssertNil(NapDoseInterval(episode: nap, dose: dose, sessionID: "session", asOf: nap.start!))
    }

    func testEveryDuplicateChainEdgeMustDescribeCompatibleWindows() {
        var broad = episode("broad"); broad.end = start.addingTimeInterval(14000); broad.recordedAt = broad.end!
        var first = episode("first"); var last = episode("last", offset: 10000); last.recordedAt = last.end!
        broad.duplicateOf = first.id; first.duplicateOf = last.id
        broad.reason = "Same episode"; first.reason = "Same episode"
        for input in [[broad, first, last], [last, first, broad], [first, broad, last]] {
            let result = NapDayProjection(timeZoneID: "UTC", day: broad.day, episodes: input, review: .partial)
            XCTAssertTrue(result.unresolvedDuplicateIDs.isSuperset(of: [broad.id, first.id]))
            XCTAssertEqual(result.episodeCount, 3)
        }
    }

    func testOptionalCustomBenefitIsNeverDefaultedAndMustBeInRange() {
        var value = episode(); XCTAssertNil(value.benefitRating)
        value.benefitRating = -1; XCTAssertFalse(value.isValid)
        value.benefitRating = 11; XCTAssertFalse(value.isValid)
        value.benefitRating = 0; XCTAssertTrue(value.isValid)
    }

    func testSemanticEvidenceDigestIsStableAndDoesNotTransportReasonText() {
        var a = episode(); a.reason = "Private correction explanation"
        var b = a; b.revision = UUID(); b.recordedAt = a.recordedAt.addingTimeInterval(30)
        XCTAssertEqual(a.evidenceKey, b.evidenceKey)
        XCTAssertEqual(a.evidenceKey.count, 64)
        XCTAssertFalse(a.evidenceKey.contains(a.reason))
        b.estimatedSleepMinutes = 5; XCTAssertNotEqual(a.evidenceKey, b.evidenceKey)
    }

    func testTravelZoneAndLongForgottenTimersRemainExplicit() {
        let original = episode(); var travel = episode("travel"); travel.timeZoneID = "America/New_York"
        let report = NapDayProjection(timeZoneID: "UTC", day: original.day, episodes: [original, travel], review: .complete)
        XCTAssertEqual(report.episodeCount, 1)
        let markers = [NapTimerMarker(id: "start", sessionID: "one", date: start, isStart: true),
            NapTimerMarker(id: "end", sessionID: "one", date: start.addingTimeInterval(172800), isStart: false)]
        let projected = NapEpisode.timers(markers, zone: "UTC", asOf: start.addingTimeInterval(172801))
        XCTAssertEqual(projected.count, 2); XCTAssertTrue(projected.allSatisfy(\.isValid))
        XCTAssertTrue(projected.allSatisfy { $0.restMinutes == nil })
    }

    func testCalendarDateLabelsUseRecordedZoneAndRejectInvalidInputs() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T03:30:00Z"))
        XCTAssertEqual(NapEpisode.day(instant, "America/New_York"), "2026-10-31")
        XCTAssertEqual(NapEpisode.day(instant, "UTC"), "2026-11-01")
        XCTAssertEqual(NapEpisode.day(instant, "invalid-zone"), "")
        XCTAssertEqual(NapEpisode.day(Date(timeIntervalSince1970: .nan), "UTC"), "")
    }

    func testReviewedTimerDoesNotHideLaterSourceChanges() {
        var raw = episode(); raw.sourceEventIDs = ["timer-start", "timer-end"]
        var reviewed = raw; reviewed.sourceEvidenceKey = raw.evidenceKey
        var doc = NapDiaryDocument(); doc.episodes = [reviewed]
        doc.reviews = [.init(day: raw.day, timeZoneID: "UTC", status: .complete, recordedAt: raw.recordedAt, episodes: doc.merging([raw]))]
        XCTAssertFalse(doc.merging([raw])[0].sourceNeedsReview)
        raw.end = raw.end!.addingTimeInterval(10)
        let current = doc.merging([raw])
        XCTAssertTrue(current[0].sourceNeedsReview)
        XCTAssertEqual(doc.status(day: raw.day, zone: "UTC", episodes: current), .partial)
        XCTAssertNil(NapDayProjection(timeZoneID: "UTC", day: raw.day, episodes: current, review: .partial).estimatedMinutes)
        XCTAssertTrue(doc.merging([])[0].sourceNeedsReview)
    }

}
