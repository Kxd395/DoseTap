import XCTest
@testable import DoseCore

final class DoseRegistrationPolicyTests: XCTestCase {

    // MARK: - Helpers

    private func makeInput(
        dose1Time: Date? = nil,
        dose2Time: Date? = nil,
        dose2Skipped: Bool = false,
        snoozeCount: Int = 0,
        windowPhase: DoseWindowPhase = .noDose1,
        surface: RegistrationSurface = .tonightButton
    ) -> DoseRegistrationInput {
        DoseRegistrationInput(
            dose1Time: dose1Time,
            dose2Time: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount,
            windowPhase: windowPhase,
            surface: surface
        )
    }

    private let d1 = Date(timeIntervalSince1970: 0)

    // MARK: - Dose 1 Tests

    func testDose1_allowed_whenNoDose1() {
        let input = makeInput(windowPhase: .noDose1)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose1(input: input), .allowed)
    }

    func testDose1_blocked_whenAlreadyTaken() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose1(input: input), .blocked(reason: "Dose 1 already taken"))
    }

    // MARK: - Dose 2 - Happy Path

    func testDose2_allowed_whenActive() {
        let input = makeInput(dose1Time: d1, windowPhase: .active)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input), .allowed)
    }

    func testDose2_allowed_whenNearClose() {
        let input = makeInput(dose1Time: d1, windowPhase: .nearClose)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input), .allowed)
    }

    // MARK: - Dose 2 - Blocked

    func testDose2_blocked_whenNoDose1() {
        let input = makeInput(windowPhase: .noDose1)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input), .blocked(reason: "Take Dose 1 first"))
    }

    func testDose2_blocked_whenCompleted() {
        let input = makeInput(dose1Time: d1, dose2Skipped: false, windowPhase: .completed)
        // dose2Time nil, not skipped, but completed phase (e.g., session ended)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input), .blocked(reason: "Session already complete"))
    }

    func testDose2_blocked_whenFinalizing() {
        let input = makeInput(dose1Time: d1, windowPhase: .finalizing)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input), .blocked(reason: "Session already complete"))
    }

    // MARK: - Dose 2 - Confirmation Required

    func testDose2_requiresConfirm_whenBeforeWindow() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)
        let result = DoseRegistrationPolicy.evaluateDose2(input: input)
        if case .requiresConfirmation(.earlyDose) = result {
            // Pass — minutesRemaining is time-dependent
        } else {
            XCTFail("Expected .requiresConfirmation(.earlyDose), got \(result)")
        }
    }

    func testDose2_requiresConfirm_whenClosed() {
        let input = makeInput(dose1Time: d1, windowPhase: .closed)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input), .requiresConfirmation(.lateDose))
    }

    func testDose2_requiresConfirm_extraDose() {
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let input = makeInput(dose1Time: d1, dose2Time: d2, windowPhase: .completed)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input), .requiresConfirmation(.extraDose))
    }

    func testDose2_requiresConfirm_afterSkip() {
        let input = makeInput(dose1Time: d1, dose2Skipped: true, windowPhase: .completed)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input), .requiresConfirmation(.afterSkip))
    }

    // MARK: - Dose 2 - Override Confirmed

    func testDose2_allowed_earlyOverrideConfirmed() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input, overrideConfirmed: true), .allowed)
    }

    func testDose2_allowed_lateOverrideConfirmed() {
        let input = makeInput(dose1Time: d1, windowPhase: .closed)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input, overrideConfirmed: true), .allowed)
    }

    func testDose2_allowed_extraDoseOverrideConfirmed() {
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let input = makeInput(dose1Time: d1, dose2Time: d2, windowPhase: .completed)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input, overrideConfirmed: true), .allowed)
    }

    func testDose2_allowed_afterSkipOverrideConfirmed() {
        let input = makeInput(dose1Time: d1, dose2Skipped: true, windowPhase: .completed)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateDose2(input: input, overrideConfirmed: true), .allowed)
    }

    // MARK: - Dose 2 - Surface Parity

    func testDose2_allSurfaces_sameResult_active() {
        let surfaces: [RegistrationSurface] = [.tonightButton, .deepLink, .flic, .historyButton]
        for surface in surfaces {
            let input = makeInput(dose1Time: d1, windowPhase: .active, surface: surface)
            XCTAssertEqual(
                DoseRegistrationPolicy.evaluateDose2(input: input),
                .allowed,
                "Surface \(surface.rawValue) should return .allowed for .active phase"
            )
        }
    }

    func testDose2_allSurfaces_sameResult_closed() {
        let surfaces: [RegistrationSurface] = [.tonightButton, .deepLink, .flic, .historyButton]
        for surface in surfaces {
            let input = makeInput(dose1Time: d1, windowPhase: .closed, surface: surface)
            XCTAssertEqual(
                DoseRegistrationPolicy.evaluateDose2(input: input),
                .requiresConfirmation(.lateDose),
                "Surface \(surface.rawValue) should require confirmation for .closed phase"
            )
        }
    }

    func testDose2_allSurfaces_sameResult_extraDose() {
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let surfaces: [RegistrationSurface] = [.tonightButton, .deepLink, .flic, .historyButton]
        for surface in surfaces {
            let input = makeInput(dose1Time: d1, dose2Time: d2, windowPhase: .completed, surface: surface)
            XCTAssertEqual(
                DoseRegistrationPolicy.evaluateDose2(input: input),
                .requiresConfirmation(.extraDose),
                "Surface \(surface.rawValue) should require confirmation for extra dose"
            )
        }
    }

    // MARK: - Snooze Tests

    func testSnooze_allowed_whenActive() {
        let input = makeInput(dose1Time: d1, windowPhase: .active)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateSnooze(input: input), .allowed)
    }

    func testSnooze_blocked_noDose1() {
        let input = makeInput(windowPhase: .noDose1)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateSnooze(input: input), .blocked(reason: "Take Dose 1 first"))
    }

    func testSnooze_blocked_nearClose() {
        let input = makeInput(dose1Time: d1, windowPhase: .nearClose)
        let result = DoseRegistrationPolicy.evaluateSnooze(input: input)
        if case .blocked = result {
            // Pass
        } else {
            XCTFail("Expected .blocked for nearClose, got \(result)")
        }
    }

    func testSnooze_blocked_limitReached() {
        let input = makeInput(dose1Time: d1, snoozeCount: 3, windowPhase: .active)
        let config = DoseWindowConfig(maxSnoozes: 3)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateSnooze(input: input, config: config),
            .blocked(reason: "Snooze limit reached (3)")
        )
    }

    func testSnooze_blocked_dose2Taken() {
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let input = makeInput(dose1Time: d1, dose2Time: d2, windowPhase: .completed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateSnooze(input: input),
            .blocked(reason: "Dose 2 already taken or skipped")
        )
    }

    func testSnooze_blocked_beforeWindow() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)
        let result = DoseRegistrationPolicy.evaluateSnooze(input: input)
        if case .blocked = result {
            // Pass
        } else {
            XCTFail("Expected .blocked for beforeWindow, got \(result)")
        }
    }

    // MARK: - Skip Tests

    func testSkip_allowed_whenDose1Exists() {
        let input = makeInput(dose1Time: d1, windowPhase: .active)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateSkip(input: input), .allowed)
    }

    func testSkip_blocked_noDose1() {
        let input = makeInput(windowPhase: .noDose1)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateSkip(input: input), .blocked(reason: "Take Dose 1 first"))
    }

    func testSkip_blocked_dose2Taken() {
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let input = makeInput(dose1Time: d1, dose2Time: d2, windowPhase: .completed)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateSkip(input: input), .blocked(reason: "Dose 2 already taken"))
    }

    func testSkip_blocked_alreadySkipped() {
        let input = makeInput(dose1Time: d1, dose2Skipped: true, windowPhase: .completed)
        XCTAssertEqual(DoseRegistrationPolicy.evaluateSkip(input: input), .blocked(reason: "Dose 2 already skipped"))
    }
}
