import XCTest
@testable import DoseCore

final class TimeEngineTests: XCTestCase {

    // MARK: - Config Defaults

    func test_config_defaults() {
        let cfg = TimeEngineConfig()
        XCTAssertEqual(cfg.minIntervalMin, 150)
        XCTAssertEqual(cfg.maxIntervalMin, 240)
        XCTAssertEqual(cfg.targetIntervalMin, 165)
    }

    // MARK: - No Dose 1

    func test_noDose1_returns_noDose1() {
        let engine = TimeEngine(now: { Date() })
        let state = engine.state(dose1At: nil)
        XCTAssertEqual(state, .noDose1)
    }

    // MARK: - Waiting For Target

    func test_before_target_returns_waitingForTarget() {
        let d1 = Date(timeIntervalSince1970: 0)
        let engine = TimeEngine(now: { Date(timeIntervalSince1970: 100 * 60) })  // 100m elapsed
        let state = engine.state(dose1At: d1)
        if case .waitingForTarget(let remaining) = state {
            XCTAssertEqual(remaining, 65 * 60, accuracy: 1, "165 - 100 = 65 min remaining")
        } else {
            XCTFail("Expected waitingForTarget, got \(state)")
        }
    }

    func test_just_before_target_one_minute() {
        let d1 = Date(timeIntervalSince1970: 0)
        let engine = TimeEngine(now: { Date(timeIntervalSince1970: 164 * 60) })
        let state = engine.state(dose1At: d1)
        if case .waitingForTarget(let remaining) = state {
            XCTAssertEqual(remaining, 60, accuracy: 1, "1 minute remaining")
        } else {
            XCTFail("Expected waitingForTarget")
        }
    }

    // MARK: - Target Window Open

    func test_exact_target_returns_windowOpen() {
        let d1 = Date(timeIntervalSince1970: 0)
        let engine = TimeEngine(now: { Date(timeIntervalSince1970: 165 * 60) })
        let state = engine.state(dose1At: d1)
        if case .targetWindowOpen(let elapsed, let remaining) = state {
            XCTAssertEqual(elapsed, 165 * 60, accuracy: 1)
            XCTAssertEqual(remaining, 75 * 60, accuracy: 1, "240 - 165 = 75 min remaining")
        } else {
            XCTFail("Expected targetWindowOpen, got \(state)")
        }
    }

    func test_midWindow_180_minutes() {
        let d1 = Date(timeIntervalSince1970: 0)
        let engine = TimeEngine(now: { Date(timeIntervalSince1970: 180 * 60) })
        let state = engine.state(dose1At: d1)
        if case .targetWindowOpen(let elapsed, let remaining) = state {
            XCTAssertEqual(elapsed, 180 * 60, accuracy: 1)
            XCTAssertEqual(remaining, 60 * 60, accuracy: 1)
        } else {
            XCTFail("Expected targetWindowOpen")
        }
    }

    func test_exact_max_returns_windowOpen() {
        let d1 = Date(timeIntervalSince1970: 0)
        let engine = TimeEngine(now: { Date(timeIntervalSince1970: 240 * 60) })
        let state = engine.state(dose1At: d1)
        if case .targetWindowOpen(_, let remaining) = state {
            XCTAssertEqual(remaining, 0, accuracy: 1)
        } else {
            XCTFail("Expected targetWindowOpen at exact max boundary")
        }
    }

    // MARK: - Window Exceeded

    func test_past_max_returns_windowExceeded() {
        let d1 = Date(timeIntervalSince1970: 0)
        let engine = TimeEngine(now: { Date(timeIntervalSince1970: 241 * 60) })
        let state = engine.state(dose1At: d1)
        XCTAssertEqual(state, .windowExceeded)
    }

    func test_way_past_max_returns_windowExceeded() {
        let d1 = Date(timeIntervalSince1970: 0)
        let engine = TimeEngine(now: { Date(timeIntervalSince1970: 500 * 60) })
        let state = engine.state(dose1At: d1)
        XCTAssertEqual(state, .windowExceeded)
    }

    // MARK: - Custom Config

    func test_custom_config_wider_window() {
        var cfg = TimeEngineConfig()
        cfg.targetIntervalMin = 120
        cfg.maxIntervalMin = 300
        let d1 = Date(timeIntervalSince1970: 0)
        let engine = TimeEngine(config: cfg, now: { Date(timeIntervalSince1970: 250 * 60) })
        let state = engine.state(dose1At: d1)
        if case .targetWindowOpen = state {
            // 250m is within [120, 300]
        } else {
            XCTFail("Expected targetWindowOpen with custom config, got \(state)")
        }
    }

    func test_custom_config_narrow_window() {
        var cfg = TimeEngineConfig()
        cfg.targetIntervalMin = 160
        cfg.maxIntervalMin = 170
        let d1 = Date(timeIntervalSince1970: 0)
        let engine = TimeEngine(config: cfg, now: { Date(timeIntervalSince1970: 171 * 60) })
        let state = engine.state(dose1At: d1)
        XCTAssertEqual(state, .windowExceeded)
    }

    // MARK: - Time Injection (determinism)

    func test_time_injection_deterministic() {
        let d1 = Date(timeIntervalSince1970: 1_000_000)
        let engine = TimeEngine(now: { Date(timeIntervalSince1970: 1_000_000 + 165 * 60) })
        let state = engine.state(dose1At: d1)
        if case .targetWindowOpen = state {} else {
            XCTFail("Time injection should make tests deterministic")
        }
    }

    // MARK: - Zero Elapsed

    func test_just_taken_dose1_waiting() {
        let now = Date()
        let engine = TimeEngine(now: { now })
        let state = engine.state(dose1At: now)
        if case .waitingForTarget(let remaining) = state {
            XCTAssertEqual(remaining, 165 * 60, accuracy: 1)
        } else {
            XCTFail("Expected waitingForTarget right after dose 1")
        }
    }

    // MARK: - Equatable

    func test_states_equatable() {
        XCTAssertEqual(SimpleDoseWindowState.noDose1, .noDose1)
        XCTAssertEqual(SimpleDoseWindowState.windowExceeded, .windowExceeded)
        XCTAssertEqual(
            SimpleDoseWindowState.waitingForTarget(remaining: 100),
            .waitingForTarget(remaining: 100)
        )
        XCTAssertNotEqual(
            SimpleDoseWindowState.waitingForTarget(remaining: 100),
            .waitingForTarget(remaining: 200)
        )
    }
}
