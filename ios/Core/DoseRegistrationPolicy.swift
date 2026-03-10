// DoseRegistrationPolicy.swift
// DoseCore
//
// Pure-function policy for dose registration decisions.
// All entry surfaces (TonightView, Flic, URLRouter, History) MUST call
// this before recording any dose.
//
// Rule A: Every surface calls the same policy function.
// Rule B: If .requiresConfirmation, surface MUST show UI before proceeding.
// Rule C: Late dose override requires explicit confirmation on ALL surfaces.
// Rule D: Extra dose requires double-confirmation on ALL surfaces.
// Rule E: Undo is available for all dose actions regardless of surface.

import Foundation

// MARK: - Registration Surface

/// Identifies which UI surface is requesting the dose action.
/// Used for logging/audit; policy rules are identical across surfaces.
public enum RegistrationSurface: String, Sendable, Equatable {
    case tonightButton = "tonight_button"
    case deepLink = "deep_link"
    case flic = "flic"
    case historyButton = "history_button"
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

    /// Dose 2 attempted after window closes (> 240m).
    case lateDose

    /// Dose 2 was skipped; user wants to un-skip and take it.
    case afterSkip

    /// Dose 2 already recorded; this would be a 3rd+ dose.
    case extraDose
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
    public static func evaluateDose1(input: DoseRegistrationInput) -> RegistrationDecision {
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

        // Rule: After skip, allow un-skip with confirmation
        if input.dose2Skipped {
            if overrideConfirmed {
                return .allowed
            }
            return .requiresConfirmation(.afterSkip)
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
            let remaining = minutesUntilWindowOpen(dose1Time: input.dose1Time!, minIntervalMin: 150)
            return .requiresConfirmation(.earlyDose(minutesRemaining: remaining))

        case .active, .nearClose:
            // Happy path — window is open
            return .allowed

        case .closed:
            // Rule C: Late dose requires confirmation
            if overrideConfirmed {
                return .allowed
            }
            return .requiresConfirmation(.lateDose)

        case .completed, .finalizing:
            return .blocked(reason: "Session already complete")
        }
    }

    // MARK: - Snooze

    /// Evaluate whether a snooze is permitted.
    public static func evaluateSnooze(input: DoseRegistrationInput, config: DoseWindowConfig = DoseWindowConfig()) -> RegistrationDecision {
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
    public static func evaluateSkip(input: DoseRegistrationInput) -> RegistrationDecision {
        guard input.dose1Time != nil else {
            return .blocked(reason: "Take Dose 1 first")
        }
        if input.dose2Time != nil {
            return .blocked(reason: "Dose 2 already taken")
        }
        if input.dose2Skipped {
            return .blocked(reason: "Dose 2 already skipped")
        }
        return .allowed
    }

    // MARK: - Helpers

    private static func minutesUntilWindowOpen(dose1Time: Date, minIntervalMin: Int) -> Int {
        let windowOpen = dose1Time.addingTimeInterval(Double(minIntervalMin) * 60)
        let remaining = windowOpen.timeIntervalSinceNow
        return max(1, Int(ceil(remaining / 60)))
    }
}
