import XCTest
@testable import DoseCore

final class HistoryDoseChangeTests: XCTestCase {
    let first = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { first.addingTimeInterval(12 * 3600) }
    func row(_ type: String, _ minutes: Double, id: String? = nil) -> StoredDoseEvent {
        StoredDoseEvent(id: id ?? type, eventType: type, timestamp: first.addingTimeInterval(minutes * 60), sessionDate: "2027-01-15", sessionId: "night")
    }
    func change(_ type: String, _ minutes: Double, replacing: String? = nil, remove: Bool = false) -> HistoryDoseChange {
        HistoryDoseChange(eventType: type, timestamp: first.addingTimeInterval(minutes * 60), replacingEventID: replacing, remove: remove, reason: "Correcting my record")
    }
    func testMissingFirstDoseAndLateSecondCanBeRecordedWithoutInventingTimes() {
        XCTAssertNil(change("dose1", 0).validationError(existing: [], now: now))
        let late = change("dose2", 500)
        XCTAssertNil(late.validationError(existing: [row("dose1", 0)], now: now))
        XCTAssertTrue(late.needsTimingWarning(existing: [row("dose1", 0)]))
        XCTAssertNotNil(late.validationError(existing: [], now: now))
    }
    func testTimingWarningUsesExactBoundaries() {
        for (minutes, warning) in [(149.99, true), (150.0, false), (239.99, false), (240.0, true)] {
            XCTAssertEqual(change("dose2", minutes).needsTimingWarning(existing: [row("dose1", 0)]), warning)
        }
    }
    func testDuplicateAndContradictoryOutcomesAreRejected() {
        let existing = [row("dose1", 0), row("dose2", 180)]
        XCTAssertNotNil(change("dose1", 5).validationError(existing: existing, now: now))
        XCTAssertNotNil(change("dose2", 185).validationError(existing: existing, now: now))
        XCTAssertNotNil(change("dose2_skipped", 200).validationError(existing: existing, now: now))
        XCTAssertNil(change("dose2_skipped", 200, replacing: "dose2").validationError(existing: existing, now: now))
    }
    func testCorrectionsCannotReverseTheDoseSequence() {
        let existing = [row("dose1", 0), row("dose2", 180)]
        XCTAssertNotNil(change("dose1", 190, replacing: "dose1").validationError(existing: existing, now: now))
        XCTAssertNotNil(change("dose2", -1, replacing: "dose2").validationError(existing: existing, now: now))
        XCTAssertNil(change("dose2", 285, replacing: "dose2").validationError(existing: existing, now: now))
    }
    func testRemovalDoesNotCreateSkipAndCannotOrphanDependents() {
        let existing = [row("dose1", 0), row("dose2", 180)]
        XCTAssertNil(change("dose2", 180, replacing: "dose2", remove: true).validationError(existing: existing, now: now))
        XCTAssertNotNil(change("dose1", 0, replacing: "dose1", remove: true).validationError(existing: existing, now: now))
        XCTAssertNotNil(change("dose2", 180, replacing: "missing", remove: true).validationError(existing: existing, now: now))
    }
    func testExtraDoseRequiresBothPrimaryDosesAndChronology() {
        XCTAssertNotNil(change("extra_dose", 300).validationError(existing: [row("dose1", 0)], now: now))
        let existing = [row("dose1", 0), row("dose2", 180), row("extra_dose", 300)]
        XCTAssertNil(change("extra_dose", 400).validationError(existing: existing, now: now))
        XCTAssertNotNil(change("dose2", 180, replacing: "dose2", remove: true).validationError(existing: existing, now: now))
        XCTAssertNotNil(change("extra_dose", 170).validationError(existing: existing, now: now))
    }
    func testFutureInvalidUnknownAndUnexplainedWritesFailClosed() {
        XCTAssertNotNil(change("dose1", 721).validationError(existing: [], now: now))
        XCTAssertNotNil(change("snooze", 0).validationError(existing: [], now: now))
        XCTAssertNotNil(HistoryDoseChange(eventType: "dose1", timestamp: first, reason: " ").validationError(existing: [], now: now))
        XCTAssertNotNil(HistoryDoseChange(eventType: "dose1", timestamp: Date(timeIntervalSince1970: .nan), reason: "Correction").validationError(existing: [], now: now))
    }

    func testCanRemoveAnErroneousFutureRecordButCannotOrphanSnoozes() {
        XCTAssertNil(change("dose1", 900, replacing: "dose1", remove: true).validationError(existing: [row("dose1", 900)], now: now))
        XCTAssertNotNil(change("dose1", 0, replacing: "dose1", remove: true).validationError(existing: [row("dose1", 0), row("snooze", 180)], now: now))
    }
}
