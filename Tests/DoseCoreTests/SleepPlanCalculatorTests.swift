import XCTest
@testable import DoseCore

final class SleepPlanCalculatorTests: XCTestCase {
    
    func test_wakeBy_uses_next_day_schedule_newYork() {
        let tz = TimeZone(identifier: "America/New_York")!
        // 2025-12-25 is Thursday -> expect to use Friday entry (index 6)
        var entries = TypicalWeekSchedule.defaultEntries
        if let idx = entries.firstIndex(where: { $0.weekdayIndex == 6 }) {
            entries[idx].wakeByHour = 7
            entries[idx].wakeByMinute = 45
        }
        let schedule = TypicalWeekSchedule(entries: entries)
        let wake = SleepPlanCalculator.wakeByDateTime(forActiveSessionKey: "2025-12-25", schedule: schedule, tz: tz)
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: wake)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 12)
        XCTAssertEqual(comps.day, 26)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 45)
    }
    
    func test_recommendedInBedTime_accounts_for_latency() {
        let tz = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = 2025
        comps.month = 12
        comps.day = 26
        comps.hour = 7
        comps.minute = 0
        comps.timeZone = tz
        let wake = Calendar(identifier: .gregorian).date(from: comps)!
        let settings = SleepPlanSettings(targetSleepMinutes: 480, sleepLatencyMinutes: 20, windDownMinutes: 30)
        let inBed = SleepPlanCalculator.recommendedInBedTime(wakeBy: wake, settings: settings)
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let inBedComps = cal.dateComponents([.hour, .minute, .day], from: inBed)
        // 8h + 20m back -> 22:40 previous day
        XCTAssertEqual(inBedComps.day, 25)
        XCTAssertEqual(inBedComps.hour, 22)
        XCTAssertEqual(inBedComps.minute, 40)
    }
    
    func test_expectedSleep_decreases_as_now_advances() {
        let tz = TimeZone(identifier: "America/New_York")!
        var wakeComps = DateComponents()
        wakeComps.year = 2025
        wakeComps.month = 12
        wakeComps.day = 26
        wakeComps.hour = 7
        wakeComps.minute = 30
        wakeComps.timeZone = tz
        let wake = Calendar(identifier: .gregorian).date(from: wakeComps)!
        let settings = SleepPlanSettings(targetSleepMinutes: 450, sleepLatencyMinutes: 15, windDownMinutes: 20)
        
        var nowComps = wakeComps
        nowComps.day = 25
        nowComps.hour = 23
        nowComps.minute = 0
        let now = Calendar(identifier: .gregorian).date(from: nowComps)!
        let later = now.addingTimeInterval(3600) // +1h
        
        let expectedNow = SleepPlanCalculator.expectedSleepIfInBedNow(now: now, wakeBy: wake, settings: settings)
        let expectedLater = SleepPlanCalculator.expectedSleepIfInBedNow(now: later, wakeBy: wake, settings: settings)
        
        XCTAssertGreaterThan(expectedNow, expectedLater)
        XCTAssertEqual(expectedNow - expectedLater, 60, accuracy: 0.5)
    }
}
