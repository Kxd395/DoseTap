import XCTest
@testable import DoseCore

final class DoseWindowEdgeTests: XCTestCase {
    private func makeDate(_ base: Date, addMinutes: Int) -> Date { base.addingTimeInterval(Double(addMinutes) * 60) }

    func test_exact_150_enters_active() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 150)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        // At EXACT 150 we consider window open
        XCTAssertEqual(ctx.phase, .active)
    }

    func test_exact_165_mid_window() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 165)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .active)
        XCTAssertEqual(ctx.primary, .takeNow)
    }

    func test_exact_225_is_near_close_threshold() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 225) // 15 minutes before 240 => nearClose threshold is 15 so 225 should be active
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        // At exactly remaining == threshold we classify as nearClose
        XCTAssertEqual(ctx.phase, .nearClose)
    }

    func test_239_near_close() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 239)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .nearClose)
    }

    func test_exact_240_closed() {
        let anchor = Date()
        let now = makeDate(anchor, addMinutes: 240)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        XCTAssertEqual(ctx.phase, .closed)
    }

    func test_dst_forward_skip() {
        // Simulate DST jump (e.g. 2 AM -> 3 AM) by adding 60m gap in timeline
        // We'll emulate Dose1 at 01:30, then 'now' 3.5h later in wall clock but with a 1h shift.
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2025; comps.month = 3; comps.day = 9; comps.hour = 1; comps.minute = 30
        let tz = TimeZone(abbreviation: "PST") ?? .current
        var cal = calendar
        cal.timeZone = tz
        guard let anchor = cal.date(from: comps) else { return XCTFail("Failed build anchor") }
        // Add 3.5h real time (210m). In a forward DST shift night, wall clock might show 4.5h difference.
        let now = anchor.addingTimeInterval(210 * 60)
        let calc = DoseWindowCalculator(now: { now })
        let ctx = calc.context(dose1At: anchor, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
        // Should still be active (since 210 < 225 threshold for nearClose)
        XCTAssertEqual(ctx.phase, .active)
    }
}
