import XCTest
@testable import DoseCore

final class DoseWindowStateTests: XCTestCase {
    func makeDate(_ base: Date, addMinutes: Int) -> Date { base.addingTimeInterval(Double(addMinutes) * 60) }

    func test_noDose1() {
        let calc = DoseWindowCalculator(now: { Date() })
        let ctx = calc.context(dose1At: nil, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .noDose1)
        XCTAssertTrue(ctx.errors.contains(.dose1Required))
    }

    func test_beforeWindow() {
        let anchor = Date(); let now = makeDate(anchor, addMinutes: 120)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .beforeWindow)
        if case .waitingUntilEarliest(let rem) = ctx.primary { XCTAssert(rem > 0) } else { XCTFail() }
    }

    func test_activeWindowJustOpened() {
        let anchor = Date(); let now = makeDate(anchor, addMinutes: 151)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .active)
        XCTAssertEqual(ctx.primary, .takeNow)
    }

    func test_nearClose239Minutes() {
        let anchor = Date(); let now = makeDate(anchor, addMinutes: 239)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 1)
        XCTAssertEqual(ctx.phase, .nearClose)
        if case .takeBeforeWindowEnds(let rem) = ctx.primary { XCTAssert(rem <= 60 * 15) } else { XCTFail() }
        if case .snoozeDisabled = ctx.snooze { } else { XCTFail("Snooze should be disabled near close") }
    }

    func test_windowClosedAfter240() {
        let anchor = Date(); let now = makeDate(anchor, addMinutes: 241)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .closed)
        XCTAssertTrue(ctx.errors.contains(.windowExceeded))
    }

    func test_completedTaken() {
        let anchor = Date(); let d2 = makeDate(anchor, addMinutes: 170); let now = makeDate(anchor, addMinutes: 200)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: d2, dose2Skipped: false, snoozeCount: 2)
        XCTAssertEqual(ctx.phase, .completed)
        if case .disabled(let r) = ctx.primary { XCTAssertEqual(r, "Completed") } else { XCTFail() }
    }

    func test_snoozeLimitReached() {
        let anchor = Date(); let now = makeDate(anchor, addMinutes: 170); var config = DoseWindowConfig(); config.maxSnoozes = 2
        let calc = DoseWindowCalculator(config: config, now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 2)
        if case .snoozeDisabled(let reason) = ctx.snooze { XCTAssert(reason.lowercased().contains("limit")) } else { XCTFail() }
    }
}
