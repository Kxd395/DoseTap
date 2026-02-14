import XCTest
@testable import DoseCore

final class RecommendationEngineTests: XCTestCase {

    // MARK: - No History (baseline)

    func test_noHistory_noSignals_returns_165() {
        let result = RecommendationEngine.recommendOffsetMinutes(history: [], liveSignals: nil)
        XCTAssertEqual(result, 165, "Default with no data should be 165m")
    }

    // MARK: - History-based Median

    func test_singleSample_returns_clamped_median() {
        let history = [NightSummary(minutesToFirstWake: 180, disturbancesScore: nil)]
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: nil)
        XCTAssertEqual(result, 180)
    }

    func test_median_of_odd_samples() {
        let history = [
            NightSummary(minutesToFirstWake: 170, disturbancesScore: nil),
            NightSummary(minutesToFirstWake: 190, disturbancesScore: nil),
            NightSummary(minutesToFirstWake: 180, disturbancesScore: nil),
        ]
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: nil)
        XCTAssertEqual(result, 180, "Median of [170,180,190] = 180")
    }

    func test_median_of_even_samples() {
        let history = [
            NightSummary(minutesToFirstWake: 170, disturbancesScore: nil),
            NightSummary(minutesToFirstWake: 190, disturbancesScore: nil),
        ]
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: nil)
        XCTAssertEqual(result, 180, "Median of [170,190] = 180")
    }

    func test_baseline_clamped_to_165_minimum() {
        // All samples below 165 — but within [150,240] so they count
        let history = [
            NightSummary(minutesToFirstWake: 150, disturbancesScore: nil),
            NightSummary(minutesToFirstWake: 155, disturbancesScore: nil),
            NightSummary(minutesToFirstWake: 152, disturbancesScore: nil),
        ]
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: nil)
        XCTAssertEqual(result, 165, "Baseline is clamped to min 165")
    }

    func test_baseline_clamped_to_210_maximum() {
        let history = [
            NightSummary(minutesToFirstWake: 230, disturbancesScore: nil),
            NightSummary(minutesToFirstWake: 235, disturbancesScore: nil),
            NightSummary(minutesToFirstWake: 240, disturbancesScore: nil),
        ]
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: nil)
        XCTAssertEqual(result, 210, "Baseline is clamped to max 210")
    }

    // MARK: - Out-of-range samples filtered

    func test_samples_outside_150_240_ignored() {
        let history = [
            NightSummary(minutesToFirstWake: 100, disturbancesScore: nil),  // too low
            NightSummary(minutesToFirstWake: 300, disturbancesScore: nil),  // too high
            NightSummary(minutesToFirstWake: nil, disturbancesScore: nil),   // nil
        ]
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: nil)
        XCTAssertEqual(result, 165, "No valid samples → fallback 165")
    }

    // MARK: - Live Signals

    func test_lightOrAwake_in_window_snaps_to_now() {
        let history = [NightSummary(minutesToFirstWake: 180, disturbancesScore: nil)]
        let signals = (isLightOrAwakeNow: true, minutesSinceDose1: 170)
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: signals)
        XCTAssertEqual(result, 170, "Should snap to current minutes when awake in window")
    }

    func test_lightOrAwake_outside_window_no_snap() {
        let history = [NightSummary(minutesToFirstWake: 180, disturbancesScore: nil)]
        let signals = (isLightOrAwakeNow: true, minutesSinceDose1: 100)  // below 150
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: signals)
        // Should bump by +10 since minutesSinceDose1 < 180
        XCTAssertEqual(result, 190, "Under 180 without in-window → baseline + 10")
    }

    func test_notAwake_under180_bumps_by_10() {
        let history = [NightSummary(minutesToFirstWake: 180, disturbancesScore: nil)]
        let signals = (isLightOrAwakeNow: false, minutesSinceDose1: 170)
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: signals)
        XCTAssertEqual(result, 190, "Not awake, <180 → baseline + 10")
    }

    func test_notAwake_over180_no_bump() {
        let history = [NightSummary(minutesToFirstWake: 180, disturbancesScore: nil)]
        let signals = (isLightOrAwakeNow: false, minutesSinceDose1: 200)
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: signals)
        XCTAssertEqual(result, 180, "Not awake, ≥180 → keep baseline")
    }

    // MARK: - Boundary Clamping

    func test_result_never_below_150() {
        // Even with extreme inputs, result should be ≥ 150
        let result = RecommendationEngine.recommendOffsetMinutes(history: [], liveSignals: nil)
        XCTAssertGreaterThanOrEqual(result, 150)
    }

    func test_result_never_above_240() {
        let history = [NightSummary(minutesToFirstWake: 210, disturbancesScore: nil)]
        let signals = (isLightOrAwakeNow: false, minutesSinceDose1: 10)
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: signals)
        XCTAssertLessThanOrEqual(result, 240)
    }

    func test_bump_capped_at_240() {
        // Baseline at 210 (max clamp) + 10 = 220, which is ≤ 240
        let history = [NightSummary(minutesToFirstWake: 210, disturbancesScore: nil)]
        let signals = (isLightOrAwakeNow: false, minutesSinceDose1: 100)
        let result = RecommendationEngine.recommendOffsetMinutes(history: history, liveSignals: signals)
        XCTAssertLessThanOrEqual(result, 240)
        XCTAssertEqual(result, 220)
    }

    // MARK: - NightSummary

    func test_nightSummary_init() {
        let s = NightSummary(minutesToFirstWake: 180, disturbancesScore: 2.5)
        XCTAssertEqual(s.minutesToFirstWake, 180)
        XCTAssertEqual(s.disturbancesScore, 2.5)
    }

    func test_nightSummary_nil_fields() {
        let s = NightSummary(minutesToFirstWake: nil, disturbancesScore: nil)
        XCTAssertNil(s.minutesToFirstWake)
        XCTAssertNil(s.disturbancesScore)
    }
}
