import Foundation
import DoseCore
import os.log
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
import AudioToolbox
#endif

private let coordinatorLog = Logger(subsystem: "com.dosetap.app", category: "DoseActionCoordinator")

// MARK: - Dose Action Coordinator
/// P0-4: Single entry point for all dose actions across every surface
/// (CompactDoseButton, DoseButtonsSection, FlicButtonService, URLRouter).
///
/// Centralises: validation → confirmation routing → persistence →
/// alarm scheduling → event logging → undo registration.
///
/// Surfaces call coordinator methods and handle the returned `ActionResult`:
///   .success        → update UI with feedback
///   .attentionRequired → dose committed, but a follow-up safety effect needs retry
///   .needsConfirm   → show confirmation dialog, then call again with override
///   .blocked        → show reason to user
///
@available(iOS 15.0, *)
@MainActor
final class DoseActionCoordinator: ObservableObject {

    // MARK: - Dependencies (injected by the app root)

    let core: DoseTapCore
    let alarmService: AlarmService
    let dateProvider: any DateProviding
    var eventLogger: EventLogger?
    var undoState: UndoStateManager?
    var sessionRepo: SessionRepository?
    var hapticObserver: ((FeedbackIntensity) -> Void)?

    // MARK: - Result Types

    enum ActionResult: Equatable {
        case success(message: String)
        case attentionRequired(message: String)
        case retryRequired(message: String)
        case needsConfirm(ConfirmationType)
        case blocked(reason: String)
    }

    enum ConfirmationType: Equatable {
        /// Window not open yet - tell user how many minutes remain
        case workWake(WorkWakeWarning)
        case earlyDose(minutesRemaining: Int)
        /// A reported occurrence is outside the configured timing window.
        case outsideWindowOccurrence
        /// Dose 2 was skipped; user wants to un-skip
        case afterSkip
        /// Dose 2 already recorded; this would be a 3rd+ dose
        case extraDose
    }

    enum DoseOverride: Equatable {
        case none
        case earlyConfirmed
        case extraDoseConfirmed
    }

    // MARK: - Init

    init(
        core: DoseTapCore,
        alarmService: AlarmService,
        dateProvider: any DateProviding = SystemDateProvider(),
        eventLogger: EventLogger? = nil,
        undoState: UndoStateManager? = nil,
        sessionRepo: SessionRepository? = nil
    ) {
        self.core = core
        self.alarmService = alarmService
        self.dateProvider = dateProvider
        self.eventLogger = eventLogger
        self.undoState = undoState
        self.sessionRepo = sessionRepo
    }

    // MARK: - Take Dose 1

    func takeDose1(surface: RegistrationSurface = .tonightButton) async -> ActionResult {
        let sig = DoseSignpost.begin(.takeDose1)
        defer { DoseSignpost.end(.takeDose1, sig) }

        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let decisionTime = dateProvider.now()
        switch DoseRegistrationPolicy.evaluateDose1(
            input: registrationInput(surface: surface, at: decisionTime),
            at: decisionTime
        ) {
        case .allowed:
            break
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }

        let diagnosticActionId = UUID().uuidString
        let diagnosticSessionId = sessionRepo.currentSessionIdString()
        await DiagnosticLogger.shared.logDoseAction(
            .doseActionAttempted,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "dose1",
            surface: surface.rawValue
        )
        let mutationResult = sessionRepo.setDose1Time(decisionTime)
        await logDoseMutationResult(
            mutationResult,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "dose1",
            surface: surface
        )
        guard mutationResult.isCommitted else {
            return retryResult(
                mutationResult,
                action: "Dose 1"
            )
        }

        // Event log
        eventLogger?.logEvent(
            name: "Dose 1", color: .green,
            cooldownSeconds: 3600 * 8, persist: false
        )

        // Undo
        undoState?.register(.takeDose1(at: decisionTime))

        // Schedule alarms
        let targetMinutes = UserSettingsManager.shared.targetIntervalMinutes
        let target = targetMinutes > 0 ? targetMinutes : 165
        let wakeTime = decisionTime.addingTimeInterval(Double(target) * 60)
        let wakeResult = await alarmService.scheduleDose2Alarm(
            at: wakeTime,
            dose1Time: decisionTime
        )
        let reminderResult = await alarmService.scheduleDose2Reminders(
            dose1Time: decisionTime
        )

        playHaptic(.dose)
        playConfirmationSound()
        coordinatorLog.info("Dose 1 logged via coordinator from \(surface.rawValue, privacy: .public)")
        let schedulingFailures = [wakeResult, reminderResult].compactMap(\.failure)
        if !schedulingFailures.isEmpty {
            let messages = Array(Set(schedulingFailures.map(\.userMessage))).sorted()
            coordinatorLog.error("Dose 1 committed, but notification scheduling needs retry")
            return .attentionRequired(
                message: "Dose 1 was logged. \(messages.joined(separator: " "))"
            )
        }
        return .success(message: "✓ Dose 1 logged")
    }

    // MARK: - Take Dose 2

    func takeDose2(
        override: DoseOverride = .none,
        acknowledgedWorkWarning: WorkWakeWarning? = nil,
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface = .tonightButton
    ) async -> ActionResult {
        let sig = DoseSignpost.begin(.takeDose2, "override=\(override),surface=\(surface.rawValue)")
        defer { DoseSignpost.end(.takeDose2, sig) }

        guard sessionRepo != nil else {
            return .blocked(reason: "Session store unavailable")
        }

        let decisionTime = dateProvider.now()
        let input = registrationInput(surface: surface, at: decisionTime)
        let phase = input.windowPhase
        let overrideConfirmed = override != .none

        switch DoseRegistrationPolicy.evaluateDose2(
            input: input,
            at: decisionTime,
            overrideConfirmed: overrideConfirmed
        ) {
        case .allowed:
            var workWarning: WorkWakeWarning?
            if input.dose2Time == nil, let first = input.dose1Time, let repo = sessionRepo,
               let identity = repo.activeSessionId, let sessionDate = repo.activeSessionDate {
                do {
                    workWarning = try repo.workWakeSchedule().warning(sessionId: identity, sessionDate: sessionDate, dose1: first, now: decisionTime, doseTargetMinutes: UserSettingsManager.shared.targetIntervalMinutes)
                } catch {
                    return .retryRequired(message: "Your work schedule could not be read. Review it in Weekly Schedule and retry.")
                }
                if let warning = workWarning, warning != acknowledgedWorkWarning { return .needsConfirm(.workWake(warning)) }
            }
            if input.dose2Time != nil {
                guard override == .extraDoseConfirmed else {
                    return .needsConfirm(.extraDose)
                }
                return await performExtraDose(
                    at: decisionTime,
                    reason: reason,
                    reasonNotes: reasonNotes,
                    surface: surface
                )
            }
            if phase == .beforeWindow {
                guard override == .earlyConfirmed else {
                    return .needsConfirm(
                        .earlyDose(minutesRemaining: remainingMinutesToWindowOpen(at: decisionTime))
                    )
                }
                return await performDose2(
                    at: decisionTime,
                    eventName: "Dose 2 (Early)",
                    isLate: false,
                    isEarly: true,
                    reason: reason,
                    reasonNotes: reasonNotes,
                    surface: surface
                )
            }
            return await performDose2(
                at: decisionTime,
                eventName: "Dose 2",
                isLate: false,
                workWarning: workWarning,
                reason: reason,
                reasonNotes: reasonNotes,
                surface: surface
            )
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }
    }

    /// Record a Dose 2 occurrence that the user confirms already happened.
    /// This is deliberately separate from `takeDose2`: an outside-window record
    /// preserves history without presenting the app as permission to take a dose now.
    func recordDose2Occurrence(
        at occurrenceTime: Date,
        warningConfirmed: Bool = false,
        acknowledgedWorkWarning: WorkWakeWarning? = nil,
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface = .tonightButton
    ) async -> ActionResult {
        guard sessionRepo != nil else {
            return .blocked(reason: "Session store unavailable")
        }

        let decisionTime = dateProvider.now()
        let input = registrationInput(surface: surface, at: decisionTime)

        switch DoseRegistrationPolicy.evaluateRetrospectiveDose2(
            input: input,
            occurrenceTime: occurrenceTime,
            decisionTime: decisionTime,
            warningConfirmed: warningConfirmed
        ) {
        case .allowed:
            guard let dose1Time = input.dose1Time else {
                return .blocked(reason: "Add the missing Dose 1 record first")
            }
            var workWarning: WorkWakeWarning?
            if let repo = sessionRepo, let identity = repo.activeSessionId, let sessionDate = repo.activeSessionDate {
                do {
                    workWarning = try repo.workWakeSchedule().warning(sessionId: identity, sessionDate: sessionDate, dose1: dose1Time, now: occurrenceTime, doseTargetMinutes: UserSettingsManager.shared.targetIntervalMinutes, retrospective: true)
                } catch {
                    return .retryRequired(message: "Your work schedule could not be read. Review it in Weekly Schedule and retry.")
                }
                if let warning = workWarning, warning != acknowledgedWorkWarning { return .needsConfirm(.workWake(warning)) }
            }
            let interval = occurrenceTime.timeIntervalSince(dose1Time)
            let config = DoseCore.DoseWindowConfig()
            let isEarly = interval < Double(config.minIntervalMin) * 60
            let isLate = interval >= Double(config.maxIntervalMin) * 60
            let eventName: String
            if isEarly {
                eventName = "Dose 2 (Early, Recorded Later)"
            } else if isLate {
                eventName = "Dose 2 (Late, Recorded Later)"
            } else {
                eventName = "Dose 2 (Recorded Later)"
            }
            return await performDose2(
                at: occurrenceTime,
                eventName: eventName,
                isLate: isLate,
                workWarning: workWarning,
                isEarly: isEarly,
                entryMode: .retrospective,
                recordedAt: decisionTime,
                reason: reason,
                reasonNotes: reasonNotes,
                surface: surface
            )
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }
    }

    // MARK: - Snooze

    func snooze(surface: RegistrationSurface = .tonightButton) async -> ActionResult {
        let sig = DoseSignpost.begin(.snooze)
        defer { DoseSignpost.end(.snooze, sig) }

        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let decisionTime = dateProvider.now()
        switch DoseRegistrationPolicy.evaluateSnooze(
            input: registrationInput(surface: surface, at: decisionTime),
            at: decisionTime
        ) {
        case .allowed:
            break
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }

        guard let dose1Time = sessionRepo.dose1Time else {
            return .blocked(reason: "Take Dose 1 first")
        }

        let snoozeMutation = sessionRepo.incrementSnoozeMutationIfActive()
        guard snoozeMutation.isCommitted else {
            return retryResult(snoozeMutation, action: "Snooze")
        }

        guard let newTime = await alarmService.snoozeAlarm(dose1Time: dose1Time) else {
            let rollbackResult = sessionRepo.decrementSnoozeCount()
            if !rollbackResult.isCommitted {
                return retryResult(
                    rollbackResult,
                    action: "Snooze rollback"
                )
            }
            return .blocked(reason: "No alarm available to snooze")
        }

        undoState?.register(.snooze(minutes: alarmService.snoozeDurationMinutes))
        let formatted = newTime.formatted(date: .omitted, time: .shortened)
        coordinatorLog.info("Snoozed to \(formatted, privacy: .public) from \(surface.rawValue, privacy: .public)")
        playHaptic(.action)
        return .success(message: "✓ Snoozed to \(formatted)")
    }

    // MARK: - Skip Dose

    func skipDose(
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface = .tonightButton
    ) async -> ActionResult {
        let sig = DoseSignpost.begin(.skipDose)
        defer { DoseSignpost.end(.skipDose, sig) }

        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let decisionTime = dateProvider.now()
        switch DoseRegistrationPolicy.evaluateSkip(
            input: registrationInput(surface: surface, at: decisionTime),
            at: decisionTime
        ) {
        case .allowed:
            break
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }

        let diagnosticActionId = UUID().uuidString
        let diagnosticSessionId = sessionRepo.currentSessionIdString()
        await DiagnosticLogger.shared.logDoseAction(
            .doseActionAttempted,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "dose2_skip",
            surface: surface.rawValue
        )
        let mutationResult = sessionRepo.skipDose2(
            reason: reason,
            reasonNotes: reasonNotes,
            surface: surface
        )
        await logDoseMutationResult(
            mutationResult,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "dose2_skip",
            surface: surface
        )
        guard mutationResult.isCommitted else {
            return retryResult(mutationResult, action: "Dose 2 skip")
        }
        alarmService.cancelAllAlarms()
        alarmService.clearDose2AlarmState()

        eventLogger?.logEvent(
            name: "Skip Dose 2", color: .orange,
            cooldownSeconds: 3600 * 8, persist: false
        )

        undoState?.register(.skipDose(sequence: 2, reason: reason))
        playHaptic(.action)

        coordinatorLog.info("Dose 2 skipped via coordinator from \(surface.rawValue, privacy: .public)")
        return .success(message: "✓ Dose 2 skipped")
    }

    // MARK: - Private Helpers

    private func performDose2(
        at decisionTime: Date,
        eventName: String,
        isLate: Bool,
        workWarning: WorkWakeWarning? = nil,
        isEarly: Bool = false,
        entryMode: DoseEntryMode = .prospective,
        recordedAt: Date? = nil,
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface
    ) async -> ActionResult {
        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let diagnosticActionId = UUID().uuidString
        let diagnosticSessionId = sessionRepo.currentSessionIdString()
        let diagnosticAction = isEarly ? "dose2_early" : (isLate ? "dose2_late" : "dose2")
        await DiagnosticLogger.shared.logDoseAction(
            .doseActionAttempted,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: diagnosticAction,
            surface: surface.rawValue
        )
        let mutationResult = sessionRepo.setDose2Time(
            decisionTime,
            isEarly: isEarly,
            isExtraDose: false,
            entryMode: entryMode,
            workWarning: workWarning,
            recordedAt: recordedAt ?? decisionTime,
            surface: surface,
            reason: reason,
            reasonNotes: reasonNotes
        )
        await logDoseMutationResult(
            mutationResult,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: diagnosticAction,
            surface: surface
        )
        guard mutationResult.isCommitted else {
            return retryResult(mutationResult, action: eventName)
        }

        alarmService.cancelAllAlarms()
        alarmService.clearDose2AlarmState()

        eventLogger?.logEvent(
            name: eventName,
            color: isLate ? .orange : .green,
            cooldownSeconds: 3600 * 8,
            persist: false
        )

        undoState?.register(.takeDose2(at: decisionTime))

        playHaptic(.dose)
        playConfirmationSound()

        coordinatorLog.info("\(eventName, privacy: .public) logged via coordinator")
        return .success(message: "✓ \(eventName) logged")
    }

    private func performExtraDose(
        at decisionTime: Date,
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface
    ) async -> ActionResult {
        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let diagnosticActionId = UUID().uuidString
        let diagnosticSessionId = sessionRepo.currentSessionIdString()
        await DiagnosticLogger.shared.logDoseAction(
            .doseActionAttempted,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "extra_dose",
            surface: surface.rawValue
        )
        let mutationResult = sessionRepo.setDose2Time(
            decisionTime,
            isEarly: false,
            isExtraDose: true,
            reason: reason,
            reasonNotes: reasonNotes
        )
        await logDoseMutationResult(
            mutationResult,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "extra_dose",
            surface: surface
        )
        guard mutationResult.isCommitted else {
            return retryResult(mutationResult, action: "Extra dose")
        }

        eventLogger?.logEvent(
            name: "Extra Dose",
            color: .red,
            cooldownSeconds: 0,
            persist: false
        )

        playHaptic(.dose)
        playConfirmationSound()
        coordinatorLog.warning("Extra dose logged via coordinator after explicit confirmation")
        return .success(message: "Extra dose logged")
    }

    private func registrationInput(
        surface: RegistrationSurface,
        at decisionTime: Date
    ) -> DoseRegistrationInput {
        let dose1Time = sessionRepo?.dose1Time
        let dose2Time = sessionRepo?.dose2Time
        let dose2Skipped = sessionRepo?.dose2Skipped ?? false
        let snoozeCount = sessionRepo?.snoozeCount ?? 0
        let context = DoseWindowCalculator(now: { decisionTime }).context(
            dose1At: dose1Time,
            dose2TakenAt: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount,
            wakeFinalAt: sessionRepo?.wakeFinalTime,
            checkInCompleted: sessionRepo?.checkInCompleted ?? false
        )
        return DoseRegistrationInput(
            dose1Time: dose1Time,
            dose2Time: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount,
            windowPhase: context.phase,
            surface: surface
        )
    }

    private func logDoseMutationResult(
        _ result: MedicationMutationResult,
        sessionId: String,
        actionId: String,
        action: String,
        surface: RegistrationSurface
    ) async {
        await DiagnosticLogger.shared.logDoseAction(
            result.isCommitted ? .doseActionCommitted : .doseActionFailed,
            sessionId: sessionId,
            actionId: actionId,
            action: action,
            surface: surface.rawValue,
            failureCode: result.failure?.code.rawValue
        )
    }

    private func retryResult(
        _ mutationResult: MedicationMutationResult,
        action: String
    ) -> ActionResult {
        guard let failure = mutationResult.failure else {
            return .retryRequired(
                message: "\(action) was not saved. Retry and confirm it appears before relying on it."
            )
        }
        coordinatorLog.error(
            "\(action, privacy: .public) persistence failed at \(failure.stage.rawValue, privacy: .public) with \(failure.code.rawValue, privacy: .public)"
        )
        return .retryRequired(message: failure.userMessage)
    }

    private func mapConfirmation(_ type: DoseConfirmationType) -> ConfirmationType {
        switch type {
        case .earlyDose(let minutesRemaining):
            return .earlyDose(minutesRemaining: minutesRemaining)
        case .outsideWindowOccurrence:
            return .outsideWindowOccurrence
        case .afterSkip:
            return .afterSkip
        case .extraDose:
            return .extraDose
        }
    }

    private func remainingMinutesToWindowOpen(at decisionTime: Date) -> Int {
        guard let dose1Time = sessionRepo?.dose1Time else { return 0 }
        let windowOpen = dose1Time.addingTimeInterval(150 * 60)
        let remaining = windowOpen.timeIntervalSince(decisionTime)
        return max(1, Int(ceil(remaining / 60)))
    }

    // MARK: - Sensory Feedback (P3-1, P3-2)

    /// Standard system sound for dose confirmation (subtle "tick").
    private static let confirmationSoundID: SystemSoundID = 1057

    enum FeedbackIntensity {
        case dose      // Dose taken - strongest
        case action    // Snooze / skip - medium
    }

    /// Haptic feedback respecting user preference. P3-1.
    private func playHaptic(_ intensity: FeedbackIntensity) {
        hapticObserver?(intensity)
        switch intensity {
        case .dose:   Haptics.doseTaken.play()
        case .action: Haptics.action.play()
        }
    }

    /// Audible confirmation respecting user preference. P3-2.
    private func playConfirmationSound() {
        #if canImport(AudioToolbox)
        guard UserSettingsManager.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(Self.confirmationSoundID)
        #endif
    }

}

// MARK: - Dose Action Result Presentation

@available(iOS 15.0, *)
struct DoseActionFeedback: Equatable {
    enum Kind: Equatable {
        case success
        case warning
        case blocked
    }

    let kind: Kind
    let title: String
    let message: String
    let systemImageName: String
}

@available(iOS 15.0, *)
struct DoseActionResultPresentation: Equatable {
    let feedback: DoseActionFeedback?
    let confirmation: DoseActionCoordinator.ConfirmationType?

    init(result: DoseActionCoordinator.ActionResult) {
        switch result {
        case .success(let message):
            feedback = DoseActionFeedback(
                kind: .success,
                title: "Dose action complete",
                message: message,
                systemImageName: "checkmark.circle.fill"
            )
            confirmation = nil
        case .attentionRequired(let message):
            feedback = DoseActionFeedback(
                kind: .warning,
                title: "Dose logged; alarm needs attention",
                message: message,
                systemImageName: "exclamationmark.triangle.fill"
            )
            confirmation = nil
        case .retryRequired(let message):
            feedback = DoseActionFeedback(
                kind: .blocked,
                title: "Dose not saved — retry",
                message: message,
                systemImageName: "externaldrive.badge.exclamationmark"
            )
            confirmation = nil
        case .blocked(let reason):
            feedback = DoseActionFeedback(
                kind: .blocked,
                title: "Dose action blocked",
                message: reason,
                systemImageName: "exclamationmark.triangle.fill"
            )
            confirmation = nil
        case .needsConfirm(let type):
            feedback = nil
            confirmation = type
        }
    }
}

#if canImport(SwiftUI)
@available(iOS 15.0, *)
struct DoseActionFeedbackBanner: View {
    let feedback: DoseActionFeedback

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feedback.systemImageName)
                .foregroundStyle(tint)
                .font(.headline)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                Text(feedback.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feedback.title). \(feedback.message)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var tint: Color {
        switch feedback.kind {
        case .success:
            return .green
        case .warning, .blocked:
            return .orange
        }
    }
}
#endif
