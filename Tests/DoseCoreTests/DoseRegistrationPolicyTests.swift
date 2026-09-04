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
    private let decisionTime = Date(timeIntervalSince1970: 120 * 60)
    private let closedReason = "The Dose 2 window has ended. Record a dose that already occurred, or mark it missed."

    // MARK: - Dose 1 Tests

    func testDose1_allowed_whenNoDose1() {
        let input = makeInput(windowPhase: .noDose1)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose1(input: input, at: decisionTime),
            .allowed
        )
    }

    func testDose1_blocked_whenAlreadyTaken() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose1(input: input, at: decisionTime),
            .blocked(reason: "Dose 1 already taken")
        )
    }

    // MARK: - Dose 2 - Happy Path

    func testDose2_allowed_whenActive() {
        let input = makeInput(dose1Time: d1, windowPhase: .active)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
            .allowed
        )
    }

    func testDose2_allowed_whenNearClose() {
        let input = makeInput(dose1Time: d1, windowPhase: .nearClose)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
            .allowed
        )
    }

    // MARK: - Dose 2 - Blocked

    func testDose2_blocked_whenNoDose1() {
        let input = makeInput(windowPhase: .noDose1)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
            .blocked(reason: "Take Dose 1 first")
        )
    }

    func testDose2_blocked_whenCompleted() {
        let input = makeInput(dose1Time: d1, dose2Skipped: false, windowPhase: .completed)
        // dose2Time nil, not skipped, but completed phase (e.g., session ended)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
            .blocked(reason: "Session already complete")
        )
    }

    func testDose2_blocked_whenFinalizing() {
        let input = makeInput(dose1Time: d1, windowPhase: .finalizing)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
            .blocked(reason: "Session already complete")
        )
    }

    // MARK: - Dose 2 - Confirmation Required

    func testDose2_requiresConfirm_whenBeforeWindow() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)
        let result = DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime)
        XCTAssertEqual(result, .requiresConfirmation(.earlyDose(minutesRemaining: 30)))
    }

    func testDose2_blocksProspectiveAction_whenClosed() {
        let input = makeInput(dose1Time: d1, windowPhase: .closed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
            .blocked(reason: closedReason)
        )
    }

    func testDose2_requiresConfirm_extraDose() {
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let input = makeInput(dose1Time: d1, dose2Time: d2, windowPhase: .completed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
            .requiresConfirmation(.extraDose)
        )
    }

    func testDose2_blocksProspectiveAction_afterSkip() {
        let input = makeInput(dose1Time: d1, dose2Skipped: true, windowPhase: .completed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
            .blocked(reason: "Dose 2 is marked missed. Use Correct Dose 2 Record to add an occurrence that already happened.")
        )
    }

    // MARK: - Dose 2 - Override Confirmed

    func testDose2_allowed_earlyOverrideConfirmed() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(
                input: input,
                at: decisionTime,
                overrideConfirmed: true
            ),
            .allowed
        )
    }

    func testDose2_closedCannotBeConvertedToProspectiveActionByOverride() {
        let input = makeInput(dose1Time: d1, windowPhase: .closed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(
                input: input,
                at: decisionTime,
                overrideConfirmed: true
            ),
            .blocked(reason: closedReason)
        )
    }

    func testDose2_allowed_extraDoseOverrideConfirmed() {
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let input = makeInput(dose1Time: d1, dose2Time: d2, windowPhase: .completed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(
                input: input,
                at: decisionTime,
                overrideConfirmed: true
            ),
            .allowed
        )
    }

    func testDose2_afterSkipCannotBeConvertedToProspectiveActionByOverride() {
        let input = makeInput(dose1Time: d1, dose2Skipped: true, windowPhase: .completed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(
                input: input,
                at: decisionTime,
                overrideConfirmed: true
            ),
            .blocked(reason: "Dose 2 is marked missed. Use Correct Dose 2 Record to add an occurrence that already happened.")
        )
    }

    // MARK: - Retrospective Dose 2 Occurrences

    func testRetrospectiveDose2_withinWindow_isRecordableAfterWindowClosed() {
        let input = makeInput(dose1Time: d1, windowPhase: .closed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateRetrospectiveDose2(
                input: input,
                occurrenceTime: d1.addingTimeInterval(165 * 60),
                decisionTime: d1.addingTimeInterval(300 * 60)
            ),
            .allowed
        )
    }

    func testRetrospectiveDose2_outsideWindow_requiresWarningConfirmation() {
        let input = makeInput(dose1Time: d1, windowPhase: .closed)
        let occurrence = d1.addingTimeInterval(270 * 60)
        let now = d1.addingTimeInterval(300 * 60)

        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateRetrospectiveDose2(
                input: input,
                occurrenceTime: occurrence,
                decisionTime: now
            ),
            .requiresConfirmation(.outsideWindowOccurrence)
        )
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateRetrospectiveDose2(
                input: input,
                occurrenceTime: occurrence,
                decisionTime: now,
                warningConfirmed: true
            ),
            .allowed
        )
    }

    func testRetrospectiveDose2_beforeWindow_requiresWarningConfirmation() {
        let input = makeInput(dose1Time: d1, windowPhase: .closed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateRetrospectiveDose2(
                input: input,
                occurrenceTime: d1.addingTimeInterval(120 * 60),
                decisionTime: d1.addingTimeInterval(300 * 60)
            ),
            .requiresConfirmation(.outsideWindowOccurrence)
        )
    }

    func testRetrospectiveDose2_canCorrectExplicitSkipWithConfirmation() {
        let input = makeInput(dose1Time: d1, dose2Skipped: true, windowPhase: .completed)
        let occurrence = d1.addingTimeInterval(165 * 60)
        let now = d1.addingTimeInterval(300 * 60)

        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateRetrospectiveDose2(
                input: input,
                occurrenceTime: occurrence,
                decisionTime: now
            ),
            .requiresConfirmation(.afterSkip)
        )
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateRetrospectiveDose2(
                input: input,
                occurrenceTime: occurrence,
                decisionTime: now,
                warningConfirmed: true
            ),
            .allowed
        )
    }

    func testRetrospectiveDose2_rejectsFutureOccurrence() {
        let input = makeInput(dose1Time: d1, windowPhase: .closed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateRetrospectiveDose2(
                input: input,
                occurrenceTime: d1.addingTimeInterval(301 * 60),
                decisionTime: d1.addingTimeInterval(300 * 60),
                warningConfirmed: true
            ),
            .blocked(reason: "Dose 2 time cannot be in the future")
        )
    }

    func testRetrospectiveDose2_rejectsOccurrenceBeforeDose1() {
        let input = makeInput(dose1Time: d1, windowPhase: .closed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateRetrospectiveDose2(
                input: input,
                occurrenceTime: d1.addingTimeInterval(-1),
                decisionTime: d1.addingTimeInterval(300 * 60),
                warningConfirmed: true
            ),
            .blocked(reason: "Dose 2 time cannot be before Dose 1")
        )
    }

    // MARK: - Dose 2 - Surface Parity

    func testDose2_allSurfaces_sameResult_active() {
        let surfaces = RegistrationSurface.allTestSurfaces
        for surface in surfaces {
            let input = makeInput(dose1Time: d1, windowPhase: .active, surface: surface)
            XCTAssertEqual(
                DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
                .allowed,
                "Surface \(surface.rawValue) should return .allowed for .active phase"
            )
        }
    }

    func testDose2_allSurfaces_sameResult_closed() {
        let surfaces = RegistrationSurface.allTestSurfaces
        for surface in surfaces {
            let input = makeInput(dose1Time: d1, windowPhase: .closed, surface: surface)
            XCTAssertEqual(
                DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
                .blocked(reason: closedReason),
                "Surface \(surface.rawValue) should block a prospective action for .closed phase"
            )
        }
    }

    func testDose2_allSurfaces_sameResult_extraDose() {
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let surfaces = RegistrationSurface.allTestSurfaces
        for surface in surfaces {
            let input = makeInput(dose1Time: d1, dose2Time: d2, windowPhase: .completed, surface: surface)
            XCTAssertEqual(
                DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime),
                .requiresConfirmation(.extraDose),
                "Surface \(surface.rawValue) should require confirmation for extra dose"
            )
        }
    }

    // MARK: - Snooze Tests

    func testSnooze_allowed_whenActive() {
        let input = makeInput(dose1Time: d1, windowPhase: .active)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateSnooze(input: input, at: decisionTime),
            .allowed
        )
    }

    func testSnooze_blocked_noDose1() {
        let input = makeInput(windowPhase: .noDose1)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateSnooze(input: input, at: decisionTime),
            .blocked(reason: "Take Dose 1 first")
        )
    }

    func testSnooze_blocked_nearClose() {
        let input = makeInput(dose1Time: d1, windowPhase: .nearClose)
        let result = DoseRegistrationPolicy.evaluateSnooze(input: input, at: decisionTime)
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
            DoseRegistrationPolicy.evaluateSnooze(
                input: input,
                at: decisionTime,
                config: config
            ),
            .blocked(reason: "Snooze limit reached (3)")
        )
    }

    func testSnooze_blocked_dose2Taken() {
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let input = makeInput(dose1Time: d1, dose2Time: d2, windowPhase: .completed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateSnooze(input: input, at: decisionTime),
            .blocked(reason: "Dose 2 already taken or skipped")
        )
    }

    func testSnooze_blocked_beforeWindow() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)
        let result = DoseRegistrationPolicy.evaluateSnooze(input: input, at: decisionTime)
        if case .blocked = result {
            // Pass
        } else {
            XCTFail("Expected .blocked for beforeWindow, got \(result)")
        }
    }

    // MARK: - Skip Tests

    func testSkip_allowed_whenDose1Exists() {
        let input = makeInput(dose1Time: d1, windowPhase: .active)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateSkip(input: input, at: decisionTime),
            .allowed
        )
    }

    func testSkip_blocked_beforeWindow() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateSkip(input: input, at: decisionTime),
            .blocked(reason: "Dose 2 window has not opened")
        )
    }

    func testSkip_blocked_noDose1() {
        let input = makeInput(windowPhase: .noDose1)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateSkip(input: input, at: decisionTime),
            .blocked(reason: "Take Dose 1 first")
        )
    }

    func testSkip_blocked_dose2Taken() {
        let d2 = Date(timeIntervalSince1970: 165 * 60)
        let input = makeInput(dose1Time: d1, dose2Time: d2, windowPhase: .completed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateSkip(input: input, at: decisionTime),
            .blocked(reason: "Dose 2 already taken")
        )
    }

    func testSkip_blocked_alreadySkipped() {
        let input = makeInput(dose1Time: d1, dose2Skipped: true, windowPhase: .completed)
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateSkip(input: input, at: decisionTime),
            .blocked(reason: "Dose 2 already skipped")
        )
    }

    func testSkip_allSurfaces_sameDecisionAndReason_forEveryPhase() {
        let surfaces = RegistrationSurface.allTestSurfaces
        let phaseCases: [(DoseWindowPhase, Date?, RegistrationDecision)] = [
            (.noDose1, nil, .blocked(reason: "Take Dose 1 first")),
            (.beforeWindow, d1, .blocked(reason: "Dose 2 window has not opened")),
            (.active, d1, .allowed),
            (.nearClose, d1, .allowed),
            (.closed, d1, .allowed),
            (.completed, d1, .blocked(reason: "Session already complete")),
            (.finalizing, d1, .blocked(reason: "Session already complete")),
        ]

        for (phase, dose1Time, expected) in phaseCases {
            for surface in surfaces {
                let input = makeInput(
                    dose1Time: dose1Time,
                    windowPhase: phase,
                    surface: surface
                )
                XCTAssertEqual(
                    DoseRegistrationPolicy.evaluateSkip(input: input, at: decisionTime),
                    expected,
                    "Surface \(surface.rawValue) diverged in phase \(phase)"
                )
            }
        }
    }

    // MARK: - Deterministic Clock Tests

    func testDose2_frozenDecisionTime_producesStableCountdown() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)

        let first = DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime)
        let second = DoseRegistrationPolicy.evaluateDose2(input: input, at: decisionTime)

        XCTAssertEqual(first, .requiresConfirmation(.earlyDose(minutesRemaining: 30)))
        XCTAssertEqual(second, first)
    }

    func testDose2_advancingDecisionTime_crossesExactWindowBoundaries() {
        func decision(at time: Date) -> RegistrationDecision {
            let context = DoseWindowCalculator(now: { time }).context(
                dose1At: d1,
                dose2TakenAt: nil,
                dose2Skipped: false,
                snoozeCount: 0
            )
            let input = makeInput(dose1Time: d1, windowPhase: context.phase)
            return DoseRegistrationPolicy.evaluateDose2(input: input, at: time)
        }

        XCTAssertEqual(
            decision(at: d1.addingTimeInterval(150 * 60 - 1)),
            .requiresConfirmation(.earlyDose(minutesRemaining: 1))
        )
        XCTAssertEqual(decision(at: d1.addingTimeInterval(150 * 60)), .allowed)
        XCTAssertEqual(decision(at: d1.addingTimeInterval(240 * 60 - 1)), .allowed)
        XCTAssertEqual(
            decision(at: d1.addingTimeInterval(240 * 60)),
            .blocked(reason: closedReason)
        )
    }

    func testDose2_earlyCountdown_roundsRemainingSecondsUpToWholeMinutes() {
        let input = makeInput(dose1Time: d1, windowPhase: .beforeWindow)

        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(
                input: input,
                at: d1.addingTimeInterval(148 * 60 + 59)
            ),
            .requiresConfirmation(.earlyDose(minutesRemaining: 2))
        )
        XCTAssertEqual(
            DoseRegistrationPolicy.evaluateDose2(
                input: input,
                at: d1.addingTimeInterval(149 * 60)
            ),
            .requiresConfirmation(.earlyDose(minutesRemaining: 1))
        )
    }

    func testMedicationSafetySources_forbidDirectSystemClockReads() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "ios/Core/DoseRegistrationPolicy.swift",
            "ios/DoseTap/DoseActionCoordinator.swift",
        ]
        let forbiddenTokens = [
            "Date()",
            "Date.now",
            "timeIntervalSinceNow",
            "timeIntervalSince(Date())",
        ]

        for relativePath in relativePaths {
            let sourceURL = repositoryRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    source.contains(token),
                    "\(relativePath) must obtain decision time from its injected clock; found \(token)"
                )
            }
        }
    }

    func testMedicationSafetySources_forbidElapsedTimeFromPersistingMissedOutcome() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "ios/DoseTap/DoseTapApp.swift",
            "ios/DoseTap/Storage/SessionRepository.swift",
        ]
        let forbiddenTokens = [
            "checkAndHandleExpiredSession",
            "markSessionSleptThrough",
            "reason: \"slept_through\"",
        ]

        for relativePath in relativePaths {
            let sourceURL = repositoryRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    source.contains(token),
                    "\(relativePath) must not persist a medication outcome from elapsed time; found \(token)"
                )
            }
        }
    }
}

private extension RegistrationSurface {
    static let allTestSurfaces: [RegistrationSurface] = [
        .tonightButton,
        .sessionDetail,
        .deepLink,
        .flic,
        .historyButton,
        .notificationAction,
    ]
}
