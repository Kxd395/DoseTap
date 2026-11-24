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
    @State private var workWakeWarning: WorkWakeWarning?
    @State private var dose1Review: DoseActionCoordinator.Dose1Review?
    @State private var dose2Confirmation: DoseActionCoordinator.Dose2Confirmation?
    @State private var showExpiredDose2Resolution = false
    @State private var expiredResolutionReferenceTime = Date()
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
                VStack(spacing: 2) {
                    Text(copy.title)
                        .font(.headline)
                    if let subtitle = copy.subtitle {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                    }
                }
                .foregroundColor(primaryButtonTextColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                // Grows with Dynamic Type; never shorter than the 44pt HIG minimum.
                .frame(minHeight: 50)
                .padding(.vertical, 6)
                .background(primaryButtonColor)
                .cornerRadius(12)
            }
            // Accessibility: the spoken label always contains the visible text
            // so Voice Control commands such as "Tap Record Dose 2" work.
            .accessibilityIdentifier("dose-primary-action")
            .accessibilityLabel(copy.accessibilityLabel)
            .accessibilityValue(copy.accessibilityValue)
            .accessibilityHint(copy.accessibilityHint)
            // Closed timing phases remain actionable so the record can be resolved.
            .padding(.horizontal)
            .sheet(item: $dose1Review) { review in
                Dose1ReviewSheet(review: review, coordinator: coordinator, onCommitted: handleActionResult)
                    .nightModePresentation()
            }
            .sheet(item: $dose2Confirmation) { confirmation in
                Dose2RecordConfirmationSheet(confirmation: confirmation, coordinator: coordinator, onCommitted: handleActionResult)
                    .nightModePresentation()
            }
            .sheet(item: $workWakeWarning) { warning in
                Group {
                    if let repository = coordinator.sessionRepo {
                        WorkWakeWarningSheet(warning: warning, repository: repository, coordinator: coordinator, onResult: handleActionResult)
                    }
                }
                .nightModePresentation()
            }
            .sheet(isPresented: $showExpiredDose2Resolution) {
                Group {
                    if let repository = coordinator.sessionRepo, let dose1Time = core.dose1Time {
                        ExpiredDose2ResolutionSheet(
                            dose1Time: dose1Time,
                            referenceTime: expiredResolutionReferenceTime,
                            isAlreadyMarkedMissed: core.isSkipped,
                            repository: repository,
                            recordOccurrence: { occurrenceTime, reason, notes, workWarning, wakeMethod in
                                await coordinator.recordDose2Occurrence(
                                    at: occurrenceTime,
                                    warningConfirmed: true,
                                    acknowledgedWorkWarning: workWarning,
                                    reason: reason,
                                    reasonNotes: notes,
                                    surface: .tonightButton, wakeMethod: wakeMethod
                                )
                            },
                            markMissed: { reason, notes in
                                await coordinator.skipDose(
                                    reason: reason,
                                    reasonNotes: notes,
                                    surface: .tonightButton
                                )
                            },
                            onCommitted: handleActionResult
                        )
                    }
                }
                .nightModePresentation()
            }
            .sheet(item: $reasonCaptureMode) { mode in
                Group {
                    Dose2OutcomeReasonSheet(
                        mode: mode,
                        onConfirm: { reason, notes in
                            switch mode {
                            case .skipDose:
                                completeSkip(reason: reason, notes: notes)
                            case .earlyDose:
                                break
                            }
                            reasonCaptureMode = nil
                        },
                        onCancel: { reasonCaptureMode = nil }
                    )
                }
                .nightModePresentation()
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
                        Label(DoseControlCopy.snoozeLabel(minutes: coordinator.alarmService.snoozeDurationMinutes), systemImage: "bell.badge")
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
        .onReceive(URLRouter.shared.$dose2ReviewRequest.compactMap { $0 }) { _ in
            // The alarm screen asked for the normal Dose 2 review. Only phases
            // where Tonight's own button reviews Dose 2 respond (DOSETAP-90).
            // Take the request first so a redraw cannot replay it.
            guard URLRouter.shared.takeDose2ReviewRequest(),
                  Self.respondsToDose2ReviewRequest(core.currentStatus) else { return }
            handlePrimaryButtonTap()
        }
    }

    static func respondsToDose2ReviewRequest(_ status: DoseStatus) -> Bool {
        switch status {
        case .beforeWindow, .active, .nearClose, .closed: return true
        case .noDose1, .completed, .finalizing: return false
        }
    }
    
    private func handlePrimaryButtonTap() {
        // Finalizing: primary button acts as morning check-in launcher.
        if core.currentStatus == .finalizing, let binding = showMorningCheckIn {
            binding.wrappedValue = true
            Haptics.light.play()
            return
        }

        if core.currentStatus == .closed
            || (core.currentStatus == .completed && core.isSkipped && core.dose2Time == nil) {
            expiredResolutionReferenceTime = Date()
            showExpiredDose2Resolution = true
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
        case .dose1Record(let review):
            dose1Review = review
        case .dose2Record(let request):
            dose2Confirmation = request
        case .workWake(let warning):
            workWakeWarning = warning
        case .earlyDose(let minutes):
            earlyDoseMinutes = minutes
            showEarlyDoseAlert = true
        case .outsideWindowOccurrence, .afterSkip:
            expiredResolutionReferenceTime = Date()
            showExpiredDose2Resolution = true
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

    private var copy: DoseControlCopy.Primary {
        DoseControlCopy.primary(
            status: core.currentStatus,
            isSkipped: core.isSkipped,
            hasDose2: core.dose2Time != nil
        )
    }

    private var primaryButtonTextColor: Color {
        switch core.currentStatus {
        case .active, .nearClose, .finalizing:
            return .black
        case .beforeWindow:
            // White on system gray is below 3:1; use the primary label color.
            return .primary
        default:
            return .white
        }
    }

    private var primaryButtonColor: Color {
        let theme = themeManager.currentTheme
        switch core.currentStatus {
        case .noDose1: return theme == .night ? theme.buttonBackground : .blue
        case .beforeWindow: return Color(.systemGray4)
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
        if case .skipEnabled = core.windowContext.skip { return true }
        return false
    }
}

// MARK: - Dose Control Copy

/// Visible text and spoken text for dose controls. Kept as pure values so the
/// label rules can be unit tested without rendering a view.
enum DoseControlCopy {
    struct Primary: Equatable {
        let title: String
        let subtitle: String?
        let accessibilityLabel: String
        let accessibilityValue: String
        let accessibilityHint: String
    }

    /// The snooze button names the configured duration (1–30 minutes).
    static func snoozeLabel(minutes: Int) -> String {
        "Snooze +\(max(1, min(30, minutes)))m"
    }

    static func primary(status: DoseStatus, isSkipped: Bool, hasDose2: Bool) -> Primary {
        switch status {
        case .noDose1:
            return Primary(title: "Take Dose 1", subtitle: nil,
                           accessibilityLabel: "Take Dose 1", accessibilityValue: "",
                           accessibilityHint: "Opens the Dose 1 review before anything is recorded")
        case .beforeWindow:
            return Primary(title: "Waiting for Dose 2 window", subtitle: "Tap to review an early Dose 2",
                           accessibilityLabel: "Waiting for Dose 2 window. Tap to review an early Dose 2",
                           accessibilityValue: "Window not open",
                           accessibilityHint: "Opens an early-dose warning. Nothing is recorded unless you confirm")
        case .active:
            return Primary(title: "Record Dose 2", subtitle: nil,
                           accessibilityLabel: "Record Dose 2", accessibilityValue: "Window is open",
                           accessibilityHint: "Opens the Dose 2 confirmation")
        case .nearClose:
            return Primary(title: "Record Dose 2", subtitle: nil,
                           accessibilityLabel: "Record Dose 2", accessibilityValue: "Window closing soon",
                           accessibilityHint: "Opens the Dose 2 confirmation before the window closes")
        case .closed:
            return Primary(title: "Resolve Dose 2", subtitle: nil,
                           accessibilityLabel: "Resolve Dose 2", accessibilityValue: "The planned window has ended",
                           accessibilityHint: "Record a Dose 2 that already happened, or mark Dose 2 missed")
        case .completed:
            if isSkipped && !hasDose2 {
                return Primary(title: "Correct Dose 2 Record", subtitle: nil,
                               accessibilityLabel: "Correct Dose 2 Record", accessibilityValue: "Dose 2 is marked missed",
                               accessibilityHint: "Opens the Dose 2 correction")
            }
            return Primary(title: "Complete ✓", subtitle: nil,
                           accessibilityLabel: "Complete", accessibilityValue: "Dose 2 outcome recorded",
                           accessibilityHint: "")
        case .finalizing:
            return Primary(title: "Check-In", subtitle: nil,
                           accessibilityLabel: "Check-In", accessibilityValue: "Morning check-in needed",
                           accessibilityHint: "Opens the morning check-in")
        }
    }
}
