// DoseRegistrationPolicy.swift
// DoseCore
//
// Pure-function policy for dose registration decisions.
// All entry surfaces (TonightView, Flic, URLRouter, History) MUST call
// this before recording any dose.
//
// Rule A: Every surface calls the same policy function.
// Rule B: If .requiresConfirmation, surface MUST show UI before proceeding.
// Rule C: A prospective Dose 2 action is unavailable after the configured window.
//         An occurrence that already happened remains recordable through the
//         separate retrospective policy with explicit outside-window confirmation.
// Rule D: Extra dose requires double-confirmation on ALL surfaces.
// Rule E: Undo is available for all dose actions regardless of surface.

import Foundation

// MARK: - Registration Surface

/// Identifies which UI surface is requesting the dose action.
/// Used for logging/audit; policy rules are identical across surfaces.
public enum RegistrationSurface: String, Sendable, Equatable {
    case tonightButton = "tonight_button"
    case sessionDetail = "session_detail"
    case deepLink = "deep_link"
    case flic = "flic"
    case historyButton = "history_button"
    case notificationAction = "notification_action"
}

// MARK: - Registration Decision

/// The result of evaluating whether a dose action is permitted.
public enum RegistrationDecision: Equatable, Sendable {
    /// Action is allowed — proceed immediately.
    case allowed

    /// Action requires user confirmation before proceeding.
    case requiresConfirmation(DoseConfirmationType)

    /// Action is blocked — cannot proceed.
    case blocked(reason: String)
}

/// Types of confirmation required before a dose can be registered.
public enum DoseConfirmationType: Equatable, Sendable {
    /// Dose 2 attempted before window opens (< 150m).
    /// `minutesRemaining` = time until window opens.
    case earlyDose(minutesRemaining: Int)

    /// A reported Dose 2 occurrence was outside the configured window.
    /// This confirms record accuracy; it is never permission to take a dose now.
    case outsideWindowOccurrence

    /// Dose 2 was marked skipped; user is correcting the record with an
    /// occurrence that already happened.
    case afterSkip

    /// Dose 2 already recorded; this would be a 3rd+ dose.
    case extraDose
}

/// Whether a dose command represents an action happening now or an occurrence
/// that the user reports already happened. Persist this distinction for audit.
public enum DoseEntryMode: String, Equatable, Sendable {
    case prospective
    case retrospective
}

// MARK: - Policy Input

/// All state needed to evaluate a dose registration decision.
/// Collect from SessionRepository / DoseWindowCalculator before calling.
public struct DoseRegistrationInput: Equatable, Sendable {
    public let dose1Time: Date?
    public let dose2Time: Date?
    public let dose2Skipped: Bool
    public let snoozeCount: Int
    public let windowPhase: DoseWindowPhase
    public let surface: RegistrationSurface

    public init(
        dose1Time: Date?,
        dose2Time: Date?,
        dose2Skipped: Bool,
        snoozeCount: Int,
        windowPhase: DoseWindowPhase,
        surface: RegistrationSurface
    ) {
        self.dose1Time = dose1Time
        self.dose2Time = dose2Time
        self.dose2Skipped = dose2Skipped
        self.snoozeCount = snoozeCount
        self.windowPhase = windowPhase
        self.surface = surface
    }
}

// MARK: - Policy

/// Platform-free, deterministic policy for dose registration.
/// No side effects — returns a decision, caller acts on it.
public enum DoseRegistrationPolicy {

    // MARK: - Dose 1

    /// Evaluate whether Dose 1 can be taken.
    public static func evaluateDose1(
        input: DoseRegistrationInput,
        at _: Date
    ) -> RegistrationDecision {
        if input.dose1Time != nil {
            return .blocked(reason: "Dose 1 already taken")
        }
        return .allowed
    }

    // MARK: - Dose 2

    /// Evaluate whether Dose 2 can be taken.
    /// If an override has been confirmed, set `overrideConfirmed = true`.
    public static func evaluateDose2(
        input: DoseRegistrationInput,
        at decisionTime: Date,
        overrideConfirmed: Bool = false
    ) -> RegistrationDecision {

        // Rule: Dose 1 must exist
        guard input.dose1Time != nil else {
            return .blocked(reason: "Take Dose 1 first")
        }

        // Rule D: If Dose 2 already taken, this is an extra dose (3rd+)
        if input.dose2Time != nil {
            if overrideConfirmed {
                return .allowed
            }
            return .requiresConfirmation(.extraDose)
        }

        // A skipped outcome can be corrected only through the retrospective
        // occurrence path. It must never turn back into a prospective command.
        if input.dose2Skipped {
            return .blocked(
                reason: "Dose 2 is marked missed. Use Correct Dose 2 Record to add an occurrence that already happened."
            )
        }

        // Phase-based routing
        switch input.windowPhase {
        case .noDose1:
            return .blocked(reason: "Take Dose 1 first")

        case .beforeWindow:
            // Rule C: Early dose requires confirmation
            if overrideConfirmed {
                return .allowed
            }
            let remaining = minutesUntilWindowOpen(
                dose1Time: input.dose1Time!,
                minIntervalMin: 150,
                at: decisionTime
            )
            return .requiresConfirmation(.earlyDose(minutesRemaining: remaining))

        case .active, .nearClose:
            // Happy path — window is open
            return .allowed

        case .closed:
            // A closed timing window is not a missing record, but it is no longer
            // a prospective "take now" state. Use evaluateRetrospectiveDose2 to
            // record an occurrence that the user confirms already happened.
            return .blocked(
                reason: "The Dose 2 window has ended. Record a dose that already occurred, or mark it missed."
            )

        case .completed, .finalizing:
            return .blocked(reason: "Session already complete")
        }
    }

    // MARK: - Retrospective Dose 2

    /// Evaluate a Dose 2 occurrence that the user reports already happened.
    ///
    /// This path intentionally uses the occurrence time for timing classification
    /// and the decision time only to prevent future-dated records. It does not
    /// authorize a prospective dose outside the configured window.
    public static func evaluateRetrospectiveDose2(
        input: DoseRegistrationInput,
        occurrenceTime: Date,
        decisionTime: Date,
        warningConfirmed: Bool = false,
        config: DoseWindowConfig = DoseWindowConfig()
    ) -> RegistrationDecision {
        guard occurrenceTime <= decisionTime else {
            return .blocked(reason: "Dose 2 time cannot be in the future")
        }

        guard let dose1Time = input.dose1Time else {
            return .blocked(reason: "Add the missing Dose 1 record first")
        }

        guard occurrenceTime >= dose1Time else {
            return .blocked(reason: "Dose 2 time cannot be before Dose 1")
        }

        if input.dose2Time != nil {
            return .blocked(reason: "Dose 2 is already recorded. Use Edit to correct it.")
        }

        if input.dose2Skipped, !warningConfirmed {
            return .requiresConfirmation(.afterSkip)
        }

        let elapsed = occurrenceTime.timeIntervalSince(dose1Time)
        let isOutsideWindow = MedicationTiming.classify(elapsedSeconds: elapsed, config: config) != .inWindow

        if isOutsideWindow, !warningConfirmed {
            return .requiresConfirmation(.outsideWindowOccurrence)
        }

        return .allowed
    }

    // MARK: - Snooze

    /// Evaluate whether a snooze is permitted.
    public static func evaluateSnooze(
        input: DoseRegistrationInput,
        at _: Date,
        config: DoseWindowConfig = DoseWindowConfig()
    ) -> RegistrationDecision {
        guard input.dose1Time != nil else {
            return .blocked(reason: "Take Dose 1 first")
        }
        guard input.dose2Time == nil, !input.dose2Skipped else {
            return .blocked(reason: "Dose 2 already taken or skipped")
        }

        switch input.windowPhase {
        case .active:
            if config.maxSnoozes > 0, input.snoozeCount >= config.maxSnoozes {
                return .blocked(reason: "Snooze limit reached (\(config.maxSnoozes))")
            }
            return .allowed
        case .nearClose:
            return .blocked(reason: "Less than \(config.nearWindowThresholdMin) minutes remaining")
        default:
            return .blocked(reason: "Snooze not available in current phase")
        }
    }

    // MARK: - Skip

    /// Evaluate whether Dose 2 can be skipped.
    public static func evaluateSkip(
        input: DoseRegistrationInput,
        at _: Date
    ) -> RegistrationDecision {
        evaluateSkipState(
            dose1Time: input.dose1Time,
            dose2Time: input.dose2Time,
            dose2Skipped: input.dose2Skipped,
            windowPhase: input.windowPhase
        )
    }

    /// Canonical skip eligibility shared by the action policy and window-state UI.
    /// The initiating surface is intentionally absent: every surface must receive
    /// the same decision and denial reason for the same medication state.
    static func evaluateSkipState(
        dose1Time: Date?,
        dose2Time: Date?,
        dose2Skipped: Bool,
        windowPhase: DoseWindowPhase
    ) -> RegistrationDecision {
        guard dose1Time != nil else {
            return .blocked(reason: "Take Dose 1 first")
        }
        if dose2Time != nil {
            return .blocked(reason: "Dose 2 already taken")
        }
        if dose2Skipped {
            return .blocked(reason: "Dose 2 already skipped")
        }

        switch windowPhase {
        case .active, .nearClose, .closed:
            return .allowed
        case .beforeWindow:
            return .blocked(reason: "Dose 2 window has not opened")
        case .noDose1:
            return .blocked(reason: "Take Dose 1 first")
        case .completed, .finalizing:
            return .blocked(reason: "Session already complete")
        }
    }

    // MARK: - Helpers

    private static func minutesUntilWindowOpen(
        dose1Time: Date,
        minIntervalMin: Int,
        at decisionTime: Date
    ) -> Int {
        let windowOpen = dose1Time.addingTimeInterval(Double(minIntervalMin) * 60)
        let remaining = windowOpen.timeIntervalSince(decisionTime)
        return max(1, Int(ceil(remaining / 60)))
    }
}
