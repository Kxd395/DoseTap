import SwiftUI
import DoseCore
import os.log

// MARK: - Compact Dose Button
struct CompactDoseButton: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var undoState: UndoStateManager
    @ObservedObject var sessionRepo: SessionRepository
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var showEarlyDoseAlert: Bool
    @Binding var earlyDoseMinutes: Int
    @Binding var showExtraDoseWarning: Bool  // For second dose 2 attempt
    /// Optional binding to open Morning Check-In sheet when user taps primary
    /// button in `.finalizing` state.
    var showMorningCheckIn: Binding<Bool>? = nil
    @State private var showWindowExpiredOverride = false  // For taking dose after window expired
    @State private var reasonCaptureMode: Dose2OutcomeReasonMode?
    @State private var actionFeedback: DoseActionFeedback?
    @State private var clearFeedbackTask: Task<Void, Never>?
    
    /// Centralized coordinator for all dose actions.
    var coordinator: DoseActionCoordinator
    
    private let windowOpenMinutes: Double = 150
    
    var body: some View {
        VStack(spacing: 8) {
            // Prepare nudge: 5-min pre-window warning
            if let prepareMinutes = prepareNudgeMinutes {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(prepareMinutes <= 1
                         ? "Dose 2 window opens in under a minute"
                         : "Dose 2 window opens in \(prepareMinutes) min")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.12))
                )
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(prepareMinutes <= 1
                                    ? "Dose 2 window opens in under a minute. Get ready."
                                    : "Dose 2 window opens in \(prepareMinutes) minutes. Get ready.")
                .accessibilityAddTraits(.updatesFrequently)
            }

            Button(action: handlePrimaryButtonTap) {
                Text(primaryButtonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)  // Minimum 44pt tap target per Apple HIG
                    .background(primaryButtonColor)
                    .cornerRadius(12)
            }
            // Accessibility
            .accessibilityLabel(primaryButtonAccessibilityLabel)
            .accessibilityHint(primaryButtonAccessibilityHint)
            // Allow tapping even when completed (for extra dose warning) or closed (for override)
            .padding(.horizontal)
            .alert("Window Expired", isPresented: $showWindowExpiredOverride) {
                Button("Cancel", role: .cancel) { }
                Button("Take Dose 2 Anyway", role: .destructive) {
                    reasonCaptureMode = core.currentStatus == .completed && core.isSkipped && core.dose2Time == nil
                        ? .afterSkipDose
                        : .lateDose
                }
            } message: {
                Text(overrideConfirmationMessage)
            }
            .sheet(item: $reasonCaptureMode) { mode in
                Dose2OutcomeReasonSheet(
                    mode: mode,
                    onConfirm: { reason, notes in
                        switch mode {
                        case .skipDose:
                            completeSkip(reason: reason, notes: notes)
                        case .lateDose, .afterSkipDose:
                            takeDose2WithOverride(reason: reason, notes: notes)
                        case .earlyDose:
                            break
                        }
                        reasonCaptureMode = nil
                    },
                    onCancel: { reasonCaptureMode = nil }
                )
            }

            if let actionFeedback {
                DoseActionFeedbackBanner(feedback: actionFeedback)
                    .padding(.horizontal)
            }
            
            // Secondary buttons row
            if core.currentStatus != .noDose1 && core.currentStatus != .completed {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            handleActionResult(await coordinator.snooze())
                        }
                    } label: {
                        Label("Snooze +10m", systemImage: "bell.badge")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!snoozeEnabled)
                    
                    Button {
                        reasonCaptureMode = .skipDose
                    } label: {
                        Label("Skip", systemImage: "forward.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!skipEnabled)
                }
            }
        }
        .onDisappear {
            clearFeedbackTask?.cancel()
        }
    }
    
    private func handlePrimaryButtonTap() {
        // Finalizing: primary button acts as morning check-in launcher.
        if core.currentStatus == .finalizing, let binding = showMorningCheckIn {
            binding.wrappedValue = true
            Haptics.light.play()
            return
        }

        Task {
            let result: DoseActionCoordinator.ActionResult
            if core.dose1Time == nil {
                result = await coordinator.takeDose1()
            } else {
                result = await coordinator.takeDose2()
            }
            handleActionResult(result)
        }
    }
    
    /// Take Dose 2 after window expired with explicit user override
    private func takeDose2WithOverride(reason: String?, notes: String?) {
        Task {
            let override: DoseActionCoordinator.DoseOverride = (core.currentStatus == .completed && core.isSkipped && core.dose2Time == nil)
                ? .afterSkipConfirmed
                : .lateConfirmed
            let result = await coordinator.takeDose2(override: override, reason: reason, reasonNotes: notes)
            handleActionResult(result)
        }
    }

    private func completeSkip(reason: String?, notes: String?) {
        Task {
            let result = await coordinator.skipDose(reason: reason, reasonNotes: notes)
            handleActionResult(result)
        }
    }

    private func handleActionResult(_ result: DoseActionCoordinator.ActionResult) {
        let presentation = DoseActionResultPresentation(result: result)
        if let feedback = presentation.feedback {
            showActionFeedback(feedback)
        }
        if let confirmation = presentation.confirmation {
            handleConfirmation(confirmation)
        }
    }

    private func handleConfirmation(_ confirmation: DoseActionCoordinator.ConfirmationType) {
        switch confirmation {
        case .earlyDose(let minutes):
            earlyDoseMinutes = minutes
            showEarlyDoseAlert = true
        case .lateDose, .afterSkip:
            showWindowExpiredOverride = true
        case .extraDose:
            showExtraDoseWarning = true
        }
    }

    private func showActionFeedback(_ feedback: DoseActionFeedback) {
        actionFeedback = feedback
        clearFeedbackTask?.cancel()
        clearFeedbackTask = Task {
            let delay: UInt64 = feedback.kind == .blocked ? 6_000_000_000 : 3_000_000_000
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if actionFeedback == feedback {
                    actionFeedback = nil
                }
            }
        }
    }

    private var overrideConfirmationMessage: String {
        if core.currentStatus == .completed && core.isSkipped && core.dose2Time == nil {
            return "Dose 2 was previously marked as skipped. This will record Dose 2 now and clear skipped status. Are you sure you want to proceed?"
        }
        return "The 240-minute window has passed. Taking Dose 2 late may affect efficacy. Are you sure you want to proceed?"
    }
    
    private var primaryButtonText: String {
        switch core.currentStatus {
        case .noDose1: return "Take Dose 1"
        case .beforeWindow: return "Waiting..."
        case .active, .nearClose: return "Take Dose 2"
        case .closed: return "Take Dose 2 (Late)"
        case .completed: return "Complete ✓"
        case .finalizing: return "Check-In"
        }
    }
    
    private var primaryButtonAccessibilityLabel: String {
        switch core.currentStatus {
        case .noDose1: return "Take Dose 1 button"
        case .beforeWindow: return "Waiting for dose window to open"
        case .active: return "Take Dose 2 button. Window is open."
        case .nearClose: return "Take Dose 2 button. Warning: window closing soon!"
        case .closed: return "Take Dose 2 late button. Window has closed."
        case .completed: return "Session complete. Both doses taken."
        case .finalizing: return "Complete morning check-in button"
        }
    }
    
    private var primaryButtonAccessibilityHint: String {
        switch core.currentStatus {
        case .noDose1: return "Double tap to take Dose 1"
        case .beforeWindow: return "Wait for the countdown to finish"
        case .active: return "Double tap to take Dose 2"
        case .nearClose: return "Double tap now to take your second dose before the window closes"
        case .closed: return "Double tap to take dose late. You will be asked to confirm."
        case .completed: return ""
        case .finalizing: return "Double tap to complete your session"
        }
    }
    
    private var primaryButtonColor: Color {
        let theme = themeManager.currentTheme
        switch core.currentStatus {
        case .noDose1: return theme == .night ? theme.buttonBackground : .blue
        case .beforeWindow: return .gray
        case .active: return theme == .night ? theme.successColor : .green
        case .nearClose: return theme == .night ? theme.warningColor : .orange
        case .closed: return theme == .night ? theme.errorColor : .red
        case .completed: return theme == .night ? Color(red: 0.6, green: 0.3, blue: 0.2) : .purple
        case .finalizing: return theme == .night ? theme.warningColor : .yellow
        }
    }
    
    /// Minutes until the Dose 2 window opens, when <= 5 min remain and we're in pre-window.
    /// Returns nil outside the 5-min prepare zone so the banner hides.
    private var prepareNudgeMinutes: Int? {
        guard core.currentStatus == .beforeWindow,
              let dose1Time = core.dose1Time else { return nil }
        let windowOpensAt = dose1Time.addingTimeInterval(windowOpenMinutes * 60)
        let remaining = windowOpensAt.timeIntervalSince(Date())
        guard remaining > 0, remaining <= 5 * 60 else { return nil }
        return max(1, Int(ceil(remaining / 60)))
    }

    private var snoozeEnabled: Bool {
        if case .snoozeEnabled = core.windowContext.snooze { return true }
        return false
    }
    
    private var skipEnabled: Bool {
        core.currentStatus == .active || core.currentStatus == .nearClose || core.currentStatus == .closed
    }
}
