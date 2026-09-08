import XCTest
import DoseCore
@testable import DoseTapStudio

final class StudioWakeProvenanceTests: XCTestCase {
    func testRecordedWakeWinsOverOppositeLegacyHint() {
        let natural = session(wake: "natural", legacy: "alarm_assisted")
        XCTAssertEqual(natural.wakeSignalLabel, "Natural")
        XCTAssertTrue(natural.classification.tags.contains(.naturalWakeNight))
        XCTAssertFalse(natural.classification.tags.contains(.alarmDependentNight))
        let alarm = session(wake: "alarm", legacy: "likely_natural")
        XCTAssertEqual(alarm.wakeSignalLabel, "Alarm")
        XCTAssertEqual(alarm.nightWakeFilter, .alarm)
        XCTAssertTrue(alarm.classification.tags.contains(.alarmDependentNight))
        XCTAssertFalse(alarm.classification.tags.contains(.naturalWakeNight))
    }

    func testUnknownOtherUnsupportedAndMissingDoseNeverInferNatural() {
        for night in [session(wake: nil), session(wake: "unknown"), session(wake: "invalid"),
                      session(wake: "natural", version: 2), session(wake: "natural", hasDose2: false)] {
            XCTAssertEqual(night.wakeSignalLabel, "Unknown")
            XCTAssertEqual(night.nightWakeFilter, .unknown)
            XCTAssertFalse(night.classification.tags.contains(.naturalWakeNight))
            XCTAssertFalse(night.classification.tags.contains(.alarmDependentNight))
        }
        XCTAssertEqual(session(wake: "other").wakeSignalLabel, "Other")
        XCTAssertFalse(session(wake: "other").classification.tags.contains(.alarmDependentNight))
    }

    func testReportsUseRecordedWakeAndKeepLegacyScoreSeparate() {
        let night = session(wake: "alarm")
        let report = InsightReportBuilder().buildProviderSummary(sessions: [night])
        XCTAssertTrue(report.contains("Recorded natural Dose 2 wake nights: 0"))
        XCTAssertTrue(report.contains("Recorded alarm Dose 2 wake nights: 1"))
        XCTAssertFalse(report.contains("Likely natural wake nights:"))
        for mode in InsightRecommendationMode.allCases {
            XCTAssertTrue(mode.transparencySummary.contains("0–10"))
            XCTAssertTrue(mode.transparencySummary.contains("not included"))
        }
    }

    func testRecordedFollowingDayOverridesLegacyWorkContext() {
        let off = session(wake: "natural", followingDay: "dayOff")
        XCTAssertTrue(off.classification.tags.contains(.offNight))
        XCTAssertFalse(off.classification.tags.contains(.workNight))
        XCTAssertTrue(off.comparableCohortKey.hasPrefix("off__natural__"))
        let unknown = session(wake: "alarm", followingDay: "unknown")
        XCTAssertFalse(unknown.classification.tags.contains(.workNight))
        XCTAssertTrue(unknown.comparableCohortKey.hasPrefix("unknown__alarm__"))
    }

    private func session(wake: String?, legacy: String = "likely_natural", version: Int = 1, hasDose2: Bool = true, followingDay: String? = nil) -> InsightSession {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        var diary = CollectedNightSummary()
        diary.version = version
        diary.dose2WakeMethod = wake
        diary.backupAlarmSet = true
        diary.followingDayType = followingDay
        let context = InsightSessionContext(
            nextMorningWeekdayIndex: 2, nextMorningIsWeekend: false,
            scheduledWakeByUTC: nil, scheduledWakeMinutesAfterMidnight: nil,
            scheduleDayType: "worklike", previousScheduleDayType: nil, nextScheduleDayType: nil,
            explicitWakeType: "natural", wakeSignal: legacy, wakeFinalLoggedAtUTC: nil,
            snoozeCount: 0, scheduleMarkers: [], lateMealEndedAtUTC: nil,
            lateMealMinutesBeforeDose1: nil, lateMealMinutesBeforeDose2: nil,
            caffeineLastIntakeAtUTC: nil, caffeineMinutesBeforeDose1: nil,
            alcoholLastDrinkAtUTC: nil, alcoholMinutesBeforeDose1: nil,
            exerciseLastAtUTC: nil, exerciseMinutesBeforeDose1: nil,
            napLastEndAtUTC: nil, napMinutesBeforeDose1: nil,
            screensLastUsedAtUTC: nil, screenMinutesBeforeDose1: nil)
        return InsightSession(id: "test", sessionDate: "2026-09-07", startedAt: first, endedAt: nil,
            dose1Time: first, dose2Time: hasDose2 ? first.addingTimeInterval(9900) : nil,
            dose2Skipped: false, snoozeCount: 0, adherenceFlag: "ok", sleepEfficiency: nil,
            whoopRecovery: nil, averageHeartRate: nil, notes: nil, events: [], preSleep: nil,
            morning: nil, medications: [], context: context, collectedNight: wake == nil ? nil : diary)
    }
}
