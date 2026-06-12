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
#if canImport(WidgetKit)
import WidgetKit
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
///   .needsConfirm   → show confirmation dialog, then call again with override
///   .blocked        → show reason to user
///
@available(iOS 15.0, *)
@MainActor
final class DoseActionCoordinator: ObservableObject {

    // MARK: - Dependencies (injected by the app root)

    let core: DoseTapCore
    let alarmService: AlarmService
    var eventLogger: EventLogger?
    var undoState: UndoStateManager?
    var sessionRepo: SessionRepository?

    // MARK: - Result Types

    enum ActionResult: Equatable {
        case success(message: String)
        case needsConfirm(ConfirmationType)
        case blocked(reason: String)
    }

    enum ConfirmationType: Equatable {
        /// Window not open yet - tell user how many minutes remain
        case earlyDose(minutesRemaining: Int)
        /// 240-minute window has passed
        case lateDose
        /// Dose 2 was skipped; user wants to un-skip
        case afterSkip
        /// Dose 2 already recorded; this would be a 3rd+ dose
        case extraDose
    }

    enum DoseOverride: Equatable {
        case none
        case earlyConfirmed
        case lateConfirmed
        case afterSkipConfirmed
        case extraDoseConfirmed
    }

    // MARK: - Init

    init(
        core: DoseTapCore,
        alarmService: AlarmService,
        eventLogger: EventLogger? = nil,
        undoState: UndoStateManager? = nil,
        sessionRepo: SessionRepository? = nil
    ) {
        self.core = core
        self.alarmService = alarmService
        self.eventLogger = eventLogger
        self.undoState = undoState
        self.sessionRepo = sessionRepo
    }

    // MARK: - Take Dose 1

    func takeDose1() async -> ActionResult {
        let sig = DoseSignpost.begin(.takeDose1)
        defer { DoseSignpost.end(.takeDose1, sig) }

        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        switch DoseRegistrationPolicy.evaluateDose1(input: registrationInput(surface: .tonightButton)) {
        case .allowed:
            break
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }

        let now = Date()
        sessionRepo.setDose1Time(now)

        // Event log
        eventLogger?.logEvent(
            name: "Dose 1", color: .green,
            cooldownSeconds: 3600 * 8, persist: false
        )

        // Undo
        undoState?.register(.takeDose1(at: now))

        // Schedule alarms
        let targetMinutes = UserSettingsManager.shared.targetIntervalMinutes
        let target = targetMinutes > 0 ? targetMinutes : 165
        let wakeTime = now.addingTimeInterval(Double(target) * 60)
        await alarmService.scheduleDose2Alarm(at: wakeTime, dose1Time: now)
        await alarmService.scheduleDose2Reminders(dose1Time: now)

        playHaptic(.dose)
        playConfirmationSound()
        refreshWidgets()

        coordinatorLog.info("Dose 1 logged via coordinator")
        return .success(message: "✓ Dose 1 logged")
    }

    // MARK: - Take Dose 2

    func takeDose2(
        override: DoseOverride = .none,
        reason: String? = nil,
        reasonNotes: String? = nil
    ) async -> ActionResult {
        let sig = DoseSignpost.begin(.takeDose2, "override=\(override)")
        defer { DoseSignpost.end(.takeDose2, sig) }

        guard sessionRepo != nil else {
            return .blocked(reason: "Session store unavailable")
        }

        let input = registrationInput(surface: .tonightButton)
        let ctx = core.windowContext
        let overrideConfirmed = override != .none

        switch DoseRegistrationPolicy.evaluateDose2(input: input, overrideConfirmed: overrideConfirmed) {
        case .allowed:
            if input.dose2Time != nil {
                guard override == .extraDoseConfirmed else {
                    return .needsConfirm(.extraDose)
                }
                return await performExtraDose(reason: reason, reasonNotes: reasonNotes)
            }
            if input.dose2Skipped {
                guard override == .afterSkipConfirmed || override == .lateConfirmed else {
                    return .needsConfirm(.afterSkip)
                }
                return await performDose2(
                    eventName: "Dose 2 (After Skip)",
                    isLate: true,
                    reason: reason,
                    reasonNotes: reasonNotes
                )
            }
            if ctx.phase == .beforeWindow {
                guard override == .earlyConfirmed else {
                    return .needsConfirm(.earlyDose(minutesRemaining: remainingMinutesToWindowOpen()))
                }
                return await performDose2(
                    eventName: "Dose 2 (Early)",
                    isLate: false,
                    isEarly: true,
                    reason: reason,
                    reasonNotes: reasonNotes
                )
            }
            if ctx.phase == .closed {
                guard override == .lateConfirmed else {
                    return .needsConfirm(.lateDose)
                }
                return await performDose2(
                    eventName: "Dose 2 (Late)",
                    isLate: true,
                    reason: reason,
                    reasonNotes: reasonNotes
                )
            }
            return await performDose2(
                eventName: "Dose 2",
                isLate: false,
                reason: reason,
                reasonNotes: reasonNotes
            )
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }
    }

    // MARK: - Snooze

    func snooze() async -> ActionResult {
        let sig = DoseSignpost.begin(.snooze)
        defer { DoseSignpost.end(.snooze, sig) }

        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        switch DoseRegistrationPolicy.evaluateSnooze(input: registrationInput(surface: .tonightButton)) {
        case .allowed:
            break
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }

        guard let dose1Time = sessionRepo.dose1Time ?? core.dose1Time else {
            return .blocked(reason: "Take Dose 1 first")
        }

        guard sessionRepo.incrementSnoozeIfActive() else {
            return .blocked(reason: "Snooze not available for the current session")
        }

        guard let newTime = await alarmService.snoozeAlarm(dose1Time: dose1Time) else {
            sessionRepo.decrementSnoozeCount()
            return .blocked(reason: "No alarm available to snooze")
        }

        undoState?.register(.snooze(minutes: alarmService.snoozeDurationMinutes))
        let formatted = newTime.formatted(date: .omitted, time: .shortened)
        coordinatorLog.info("Snoozed to \(formatted, privacy: .public)")
        playHaptic(.action)
        refreshWidgets()
        return .success(message: "✓ Snoozed to \(formatted)")
    }

    // MARK: - Skip Dose

    func skipDose(reason: String? = nil, reasonNotes: String? = nil) async -> ActionResult {
        let sig = DoseSignpost.begin(.skipDose)
        defer { DoseSignpost.end(.skipDose, sig) }

        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        switch DoseRegistrationPolicy.evaluateSkip(input: registrationInput(surface: .tonightButton)) {
        case .allowed:
            break
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }

        sessionRepo.skipDose2(reason: reason, reasonNotes: reasonNotes)
        alarmService.cancelAllAlarms()
        alarmService.clearDose2AlarmState()

        eventLogger?.logEvent(
            name: "Skip Dose 2", color: .orange,
            cooldownSeconds: 3600 * 8, persist: false
        )

        undoState?.register(.skipDose(sequence: 2, reason: reason))
        playHaptic(.action)

        coordinatorLog.info("Dose 2 skipped via coordinator")
        refreshWidgets()
        return .success(message: "✓ Dose 2 skipped")
    }

    // MARK: - Private Helpers

    private func performDose2(
        eventName: String,
        isLate: Bool,
        isEarly: Bool = false,
        reason: String? = nil,
        reasonNotes: String? = nil
    ) async -> ActionResult {
        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let now = Date()
        sessionRepo.setDose2Time(
            now,
            isEarly: isEarly,
            isExtraDose: false,
            reason: reason,
            reasonNotes: reasonNotes
        )

        alarmService.cancelAllAlarms()
        alarmService.clearDose2AlarmState()

        eventLogger?.logEvent(
            name: eventName,
            color: isLate ? .orange : .green,
            cooldownSeconds: 3600 * 8,
            persist: false
        )

        undoState?.register(.takeDose2(at: now))

        playHaptic(.dose)
        playConfirmationSound()

        coordinatorLog.info("\(eventName, privacy: .public) logged via coordinator")
        refreshWidgets()
        return .success(message: "✓ \(eventName) logged")
    }

    private func performExtraDose(reason: String? = nil, reasonNotes: String? = nil) async -> ActionResult {
        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let now = Date()
        sessionRepo.setDose2Time(
            now,
            isEarly: false,
            isExtraDose: true,
            reason: reason,
            reasonNotes: reasonNotes
        )

        eventLogger?.logEvent(
            name: "Extra Dose",
            color: .red,
            cooldownSeconds: 0,
            persist: false
        )

        playHaptic(.dose)
        playConfirmationSound()
        coordinatorLog.warning("Extra dose logged via coordinator after explicit confirmation")
        refreshWidgets()
        return .success(message: "Extra dose logged")
    }

    private func registrationInput(surface: RegistrationSurface) -> DoseRegistrationInput {
        let context = core.windowContext
        return DoseRegistrationInput(
            dose1Time: sessionRepo?.dose1Time ?? core.dose1Time,
            dose2Time: sessionRepo?.dose2Time ?? core.dose2Time,
            dose2Skipped: sessionRepo?.dose2Skipped ?? core.isSkipped,
            snoozeCount: sessionRepo?.snoozeCount ?? core.snoozeCount,
            windowPhase: context.phase,
            surface: surface
        )
    }

    private func mapConfirmation(_ type: DoseConfirmationType) -> ConfirmationType {
        switch type {
        case .earlyDose(let minutesRemaining):
            return .earlyDose(minutesRemaining: minutesRemaining)
        case .lateDose:
            return .lateDose
        case .afterSkip:
            return .afterSkip
        case .extraDose:
            return .extraDose
        }
    }

    private func remainingMinutesToWindowOpen() -> Int {
        guard let dose1Time = core.dose1Time else { return 0 }
        let windowOpen = dose1Time.addingTimeInterval(150 * 60)
        let remaining = windowOpen.timeIntervalSince(Date())
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

    /// P4-2: Ask WidgetKit to refresh complications/widgets after any state-changing
    /// dose action so watch complications, Lock Screen, and Home Screen widgets stay
    /// in sync with `DoseTapCore` without waiting for the next app-lifecycle refresh.
    private func refreshWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

// MARK: - Dose Action Result Presentation

@available(iOS 15.0, *)
struct DoseActionFeedback: Equatable {
    enum Kind: Equatable {
        case success
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
        case .blocked:
            return .orange
        }
    }
}
#endif
