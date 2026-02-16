import XCTest
@testable import DoseCore

final class NightScoreCalculatorTests: XCTestCase {

    // MARK: - Full Score (perfect night)

    func test_perfectNight_scoresExcellent() {
        let input = NightScoreInput(
            intervalMinutes: 165,
            dose2Skipped: false,
            dose1Taken: true,
            dose2Taken: true,
            checkInCompleted: true,
            lightsOutLogged: true,
            wakeFinalLogged: true,
            totalSleepMinutes: 420,
            deepSleepMinutes: 90
        )
        let result = NightScoreCalculator.calculate(input)
        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.label, "Excellent")
        XCTAssertEqual(result.components.intervalAccuracy, 1.0)
        XCTAssertEqual(result.components.doseCompleteness, 1.0)
        XCTAssertEqual(result.components.sessionCompleteness, 1.0)
        XCTAssertEqual(result.components.sleepQuality, 1.0)
    }

    // MARK: - Empty Input

    func test_emptyInput_scoresZero() {
        let input = NightScoreInput()
        let result = NightScoreCalculator.calculate(input)
        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.label, "Needs Work")
    }

    // MARK: - Interval Accuracy

    func test_interval_atTarget_scores1() {
        let score = NightScoreCalculator.intervalScore(
            NightScoreInput(intervalMinutes: 165, dose1Taken: true, dose2Taken: true)
        )
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func test_interval_atMinEdge_scores0_9() {
        // 150m is only 15m from target (165m); maxDeviation=75 → 1.0-(15/75)*0.5 = 0.9
        let score = NightScoreCalculator.intervalScore(
            NightScoreInput(intervalMinutes: 150, dose1Taken: true, dose2Taken: true)
        )
        XCTAssertEqual(score, 0.9, accuracy: 0.05)
    }

    func test_interval_atMaxEdge_scores0_5() {
        let score = NightScoreCalculator.intervalScore(
            NightScoreInput(intervalMinutes: 240, dose1Taken: true, dose2Taken: true)
        )
        XCTAssertEqual(score, 0.5, accuracy: 0.001)
    }

    func test_interval_outsideWindow_scores0_1() {
        let score = NightScoreCalculator.intervalScore(
            NightScoreInput(intervalMinutes: 260, dose1Taken: true, dose2Taken: true)
        )
        XCTAssertEqual(score, 0.1, accuracy: 0.001)
    }

    func test_interval_nil_skipped_scores0_3() {
        let score = NightScoreCalculator.intervalScore(
            NightScoreInput(dose2Skipped: true, dose1Taken: true)
        )
        XCTAssertEqual(score, 0.3, accuracy: 0.001)
    }

    func test_interval_nil_missed_scores0() {
        let score = NightScoreCalculator.intervalScore(
            NightScoreInput(dose1Taken: true)
        )
        XCTAssertEqual(score, 0.0, accuracy: 0.001)
    }

    // MARK: - Dose Completeness

    func test_dose_bothTaken_scores1() {
        XCTAssertEqual(
            NightScoreCalculator.doseScore(
                NightScoreInput(dose1Taken: true, dose2Taken: true)
            ), 1.0
        )
    }

    func test_dose_skipped_scores0_5() {
        XCTAssertEqual(
            NightScoreCalculator.doseScore(
                NightScoreInput(dose2Skipped: true, dose1Taken: true)
            ), 0.5
        )
    }

    func test_dose_missed_scores0_3() {
        XCTAssertEqual(
            NightScoreCalculator.doseScore(
                NightScoreInput(dose1Taken: true)
            ), 0.3
        )
    }

    func test_dose_noDose1_scores0() {
        XCTAssertEqual(
            NightScoreCalculator.doseScore(NightScoreInput()), 0.0
        )
    }

    // MARK: - Session Completeness

    func test_session_allLogged_scores1() {
        let score = NightScoreCalculator.sessionScore(
            NightScoreInput(checkInCompleted: true, lightsOutLogged: true, wakeFinalLogged: true)
        )
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func test_session_onlyCheckIn_scores0_4() {
        let score = NightScoreCalculator.sessionScore(
            NightScoreInput(checkInCompleted: true)
        )
        XCTAssertEqual(score, 0.4, accuracy: 0.001)
    }

    func test_session_nothing_scores0() {
        let score = NightScoreCalculator.sessionScore(NightScoreInput())
        XCTAssertEqual(score, 0.0, accuracy: 0.001)
    }

    // MARK: - Sleep Quality

    func test_sleep_noData_returnsNil() {
        XCTAssertNil(NightScoreCalculator.sleepScore(NightScoreInput()))
    }

    func test_sleep_perfectTotal_noDeep_scores1() {
        let score = NightScoreCalculator.sleepScore(
            NightScoreInput(totalSleepMinutes: 420)
        )
        XCTAssertEqual(score!, 1.0, accuracy: 0.001)
    }

    func test_sleep_halfTotal_scores0_5() {
        let score = NightScoreCalculator.sleepScore(
            NightScoreInput(totalSleepMinutes: 210)
        )
        XCTAssertEqual(score!, 0.5, accuracy: 0.001)
    }

    func test_sleep_fullTotalAndDeep_scores1() {
        let score = NightScoreCalculator.sleepScore(
            NightScoreInput(totalSleepMinutes: 420, deepSleepMinutes: 90)
        )
        XCTAssertEqual(score!, 1.0, accuracy: 0.001)
    }

    func test_sleep_excessCapsAt1() {
        let score = NightScoreCalculator.sleepScore(
            NightScoreInput(totalSleepMinutes: 600, deepSleepMinutes: 200)
        )
        XCTAssertEqual(score!, 1.0, accuracy: 0.001)
    }

    // MARK: - Weight Redistribution

    func test_noSleepData_redistributesWeights() {
        // With no sleep data, interval/dose/session weights should be re-normalized.
        // A perfect night without sleep data should still score 100.
        let input = NightScoreInput(
            intervalMinutes: 165,
            dose1Taken: true,
            dose2Taken: true,
            checkInCompleted: true,
            lightsOutLogged: true,
            wakeFinalLogged: true
        )
        let result = NightScoreCalculator.calculate(input)
        XCTAssertEqual(result.score, 100)
        XCTAssertNil(result.components.sleepQuality)
    }

    // MARK: - Label Thresholds

    func test_label_excellent() {
        let input = NightScoreInput(
            intervalMinutes: 165,
            dose1Taken: true, dose2Taken: true,
            checkInCompleted: true, lightsOutLogged: true, wakeFinalLogged: true,
            totalSleepMinutes: 420, deepSleepMinutes: 90
        )
        XCTAssertEqual(NightScoreCalculator.calculate(input).label, "Excellent")
    }

    func test_label_needsWork() {
        let input = NightScoreInput()
        XCTAssertEqual(NightScoreCalculator.calculate(input).label, "Needs Work")
    }

    // MARK: - Mid-range Score

    func test_midRangeNight_scoresFair() {
        // Dose 1 taken, dose 2 taken at 200m (ok but not great), no events, no sleep
        let input = NightScoreInput(
            intervalMinutes: 200,
            dose1Taken: true,
            dose2Taken: true
        )
        let result = NightScoreCalculator.calculate(input)
        // interval: ~0.77 (200 is 35m from 165, max deviation 75, so 1 - 35/75*0.5 ≈ 0.767)
        // dose: 1.0
        // session: 0.0
        // No sleep data → redistribute
        // raw ≈ 0.767*(0.40/0.85) + 1.0*(0.25/0.85) + 0.0*(0.20/0.85)
        //     ≈ 0.767*0.471 + 1.0*0.294 + 0
        //     ≈ 0.361 + 0.294 = 0.655  → 66
        XCTAssertTrue(result.score >= 50 && result.score <= 80,
                       "Expected Fair range, got \(result.score)")
    }
}
