import SwiftUI
import DoseCore
#if canImport(UIKit)
import UIKit
#endif

struct FullSessionDetails: View {
    @ObservedObject var core: DoseTapCore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Details")
                .font(.headline)

            VStack(spacing: 12) {
                DetailRow(
                    icon: "1.circle.fill",
                    title: "Dose 1",
                    value: core.dose1Time?.formatted(date: .abbreviated, time: .shortened) ?? "Not taken",
                    color: .blue
                )

                DetailRow(
                    icon: "2.circle.fill",
                    title: "Dose 2",
                    value: dose2String,
                    color: .green
                )

                if let dose1 = core.dose1Time {
                    DetailRow(
                        icon: "clock.fill",
                        title: "Window Opens",
                        value: dose1.addingTimeInterval(150 * 60).formatted(date: .omitted, time: .shortened),
                        color: .orange
                    )

                    DetailRow(
                        icon: "clock.badge.exclamationmark.fill",
                        title: "Window Closes",
                        value: dose1.addingTimeInterval(240 * 60).formatted(date: .omitted, time: .shortened),
                        color: .red
                    )

                    if let dose2 = core.dose2Time {
                        let interval = TimeIntervalMath.minutesBetween(start: dose1, end: dose2)
                        DetailRow(
                            icon: "timer",
                            title: "Interval",
                            value: TimeIntervalMath.formatMinutes(interval),
                            color: .purple
                        )
                    }
                }

                DetailRow(
                    icon: "bell.badge.fill",
                    title: "Snoozes Used",
                    value: "\(core.snoozeCount) of 3",
                    color: .orange
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private var dose2String: String {
        if let time = core.dose2Time {
            return time.formatted(date: .abbreviated, time: .shortened)
        }
        if core.isSkipped { return "Skipped" }
        return "Pending"
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct FullEventLogGrid: View {
    let eventTypes: [(name: String, icon: String, color: Color)]
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var settings: UserSettingsManager

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Log Sleep Event")
                    .font(.headline)
                Spacer()
                Text("Tap to log")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(eventTypes, id: \.name) { event in
                    let cooldown = settings.cooldown(for: event.name)
                    EventGridButton(
                        name: event.name,
                        icon: event.icon,
                        color: event.color,
                        cooldownEnd: eventLogger.cooldownEnd(for: event.name),
                        cooldownDuration: cooldown,
                        lastLogTime: eventLogger.lastEventTime(for: event.name),
                        onTap: {
                            eventLogger.logEvent(name: event.name, color: event.color, cooldownSeconds: cooldown)
                        }
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct EventGridButton: View {
    let name: String
    let icon: String
    let color: Color
    let cooldownEnd: Date?
    let cooldownDuration: TimeInterval
    let lastLogTime: Date?
    let onTap: () -> Void

    @State private var progress: CGFloat = 1.0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var isOnCooldown: Bool {
        guard let end = cooldownEnd else { return false }
        return Date() < end
    }

    private var timeSinceBadge: String? {
        guard !isOnCooldown else { return nil }
        return EventLogger.relativeBadge(since: lastLogTime)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(isOnCooldown ? 0.1 : 0.15))
                        .frame(height: 60)

                    if isOnCooldown {
                        RoundedRectangle(cornerRadius: 12)
                            .trim(from: 0, to: progress)
                            .stroke(color.opacity(0.3), lineWidth: 2)
                            .frame(height: 60)
                    }

                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(isOnCooldown ? color.opacity(0.4) : color)
                }

                Text(name)
                    .font(.caption2)
                    .foregroundColor(isOnCooldown ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let badge = timeSinceBadge {
                    Text(badge)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(color.opacity(0.7))
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .font(.system(size: 9))
                }
            }
        }
        .disabled(isOnCooldown)
        .onReceive(timer) { _ in
            guard let end = cooldownEnd else { progress = 1.0; return }
            let remaining = end.timeIntervalSince(Date())
            progress = remaining <= 0 ? 1.0 : 1.0 - CGFloat(remaining / cooldownDuration)
        }
    }
}

struct EventHistorySection: View {
    let events: [LoggedEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Event History")
                    .font(.headline)
                Spacer()
                Text("\(events.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if events.isEmpty {
                Text("No events logged tonight")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(events) { event in
                    HStack {
                        Circle()
                            .fill(event.color)
                            .frame(width: 10, height: 10)
                        Text(event.name)
                            .font(.subheadline)
                        Spacer()
                        Text(event.time, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct StatusCard: View {
    let status: DoseStatus

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: statusIcon)
                    .font(.title2)
                Text(statusTitle)
                    .font(.headline)
            }
            .foregroundColor(statusColor)

            Text(statusDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(statusColor.opacity(0.1))
        )
    }

    private var statusIcon: String {
        switch status {
        case .noDose1: return "1.circle"
        case .beforeWindow: return "clock"
        case .active: return "checkmark.circle"
        case .nearClose: return "exclamationmark.triangle"
        case .closed: return "questionmark.circle"
        case .completed: return "checkmark.seal.fill"
        case .finalizing: return "sunrise.fill"
        }
    }

    private var statusTitle: String {
        switch status {
        case .noDose1: return "Ready for Dose 1"
        case .beforeWindow: return "Waiting for Window"
        case .active: return "Window Open"
        case .nearClose: return "Window Closing Soon"
        case .closed: return "Dose 2 Record Needed"
        case .completed: return "Dose 2 Outcome Recorded"
        case .finalizing: return "Finalizing Session"
        }
    }

    private var statusDescription: String {
        switch status {
        case .noDose1: return "Take Dose 1 to start your session"
        case .beforeWindow: return "Dose 2 window opens in \(TimeIntervalMath.formatMinutes(150))"
        case .active: return "Take Dose 2 now"
        case .nearClose: return "Less than \(TimeIntervalMath.formatMinutes(15)) remaining!"
        case .closed: return "Window ended — record what actually happened"
        case .completed: return "Dose 2 outcome recorded"
        case .finalizing: return "Complete morning check-in"
        }
    }

    private var statusColor: Color {
        switch status {
        case .noDose1: return .blue
        case .beforeWindow: return .orange
        case .active: return .green
        case .nearClose: return .red
        case .closed: return .orange
        case .completed: return .purple
        case .finalizing: return .yellow
        }
    }
}

struct TimeUntilWindowCard: View {
    let dose1Time: Date
    @State private var timeRemaining: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let windowOpenMinutes: TimeInterval = 150

    var body: some View {
        VStack(spacing: 8) {
            Text("Window Opens In")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(formatTimeRemaining)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
                .monospacedDigit()

            Text("Take Dose 2 after \(formatWindowOpenTime)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
        )
        .onAppear { updateTimeRemaining() }
        .onReceive(timer) { _ in updateTimeRemaining() }
    }

    private func updateTimeRemaining() {
        let windowOpenTime = dose1Time.addingTimeInterval(windowOpenMinutes * 60)
        timeRemaining = max(0, windowOpenTime.timeIntervalSince(Date()))
    }

    private var formatTimeRemaining: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private var formatWindowOpenTime: String {
        dose1Time.addingTimeInterval(windowOpenMinutes * 60).formatted(date: .omitted, time: .shortened)
    }
}

private enum ExpiredDose2ResolutionChoice: String, CaseIterable, Identifiable {
    case recorded = "Already taken"
    case missed = "Missed / not taken"

    var id: String { rawValue }
}

/// Resolves an unanswered Dose 2 record after the planned timing window ends.
/// Recording an occurrence is retrospective only: this view never presents an
/// outside-window medication action as a prospective "take now" command.
struct ExpiredDose2ResolutionSheet: View {
    let allowsMarkMissed: Bool
    let dose1Time: Date
    let referenceTime: Date
    let isAlreadyMarkedMissed: Bool
    let repository: SessionRepository
    let recordOccurrence: (Date, String?, String?, WorkWakeWarning?) async -> DoseActionCoordinator.ActionResult
    let markMissed: (String?, String?) async -> DoseActionCoordinator.ActionResult
    let onCommitted: (DoseActionCoordinator.ActionResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice: ExpiredDose2ResolutionChoice
    @State private var occurrenceTime: Date
    @State private var occurrenceConfirmed = false
    @State private var takenReason: Dose2TakenReason = .unsure
    @State private var skippedReason: Dose2SkippedReason = .unsure
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var workWarning: WorkWakeWarning?

    init(
        dose1Time: Date,
        referenceTime: Date,
        isAlreadyMarkedMissed: Bool,
        repository: SessionRepository,
        recordOccurrence: @escaping (Date, String?, String?, WorkWakeWarning?) async -> DoseActionCoordinator.ActionResult,
        markMissed: @escaping (String?, String?) async -> DoseActionCoordinator.ActionResult,
        onCommitted: @escaping (DoseActionCoordinator.ActionResult) -> Void,
        allowsMarkMissed: Bool = true
    ) {
        self.repository = repository
        self.allowsMarkMissed = allowsMarkMissed
        self.dose1Time = dose1Time
        self.referenceTime = referenceTime
        self.isAlreadyMarkedMissed = isAlreadyMarkedMissed
        self.recordOccurrence = recordOccurrence
        self.markMissed = markMissed
        self.onCommitted = onCommitted
        _choice = State(initialValue: .recorded)
        _occurrenceTime = State(initialValue: max(dose1Time, referenceTime))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The planned Dose 2 window ended without a confirmed outcome. Complete the medication record; elapsed time alone never marks a dose missed.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("What happened?") {
                    Picker("Dose 2 outcome", selection: $choice) {
                        ForEach(ExpiredDose2ResolutionChoice.allCases.filter { allowsMarkMissed || $0 == .recorded }) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if choice == .recorded {
                    Section {
                        Label(
                            "Only continue if Dose 2 was actually taken. This records history; it does not advise taking medication now.",
                            systemImage: "exclamationmark.shield.fill"
                        )
                        .foregroundColor(.orange)

                        if isAlreadyMarkedMissed {
                            Label(
                                "This record is currently marked missed. Saving an actual occurrence will replace that outcome while preserving the audit history.",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        }

                        DatePicker(
                            "Actual Dose 2 time",
                            selection: $occurrenceTime,
                            in: dose1Time...latestSelectableTime,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .onChange(of: occurrenceTime) { _ in
                            occurrenceConfirmed = false
                            errorMessage = nil
                        }

                        Label(timingWarningText, systemImage: timingWarningSymbol)
                            .font(.subheadline)
                            .foregroundColor(timingWarningColor)
                    } header: {
                        Text("Actual occurrence")
                    } footer: {
                        Text("Use the time the medication was actually taken, not the time this entry is being made.")
                    }

                    Section("Timing context") {
                        Picker("Reason", selection: $takenReason) {
                            ForEach(Dose2TakenReason.allCases, id: \.self) { reason in
                                Text(reason.displayText).tag(reason)
                            }
                        }

                        Toggle(
                            "I confirm Dose 2 was already taken at the time shown.",
                            isOn: $occurrenceConfirmed
                        )
                    }
                } else {
                    Section {
                        Label(
                            isAlreadyMarkedMissed
                                ? "Dose 2 is already marked missed / not taken."
                                : "This records that Dose 2 was not taken; it cannot be inferred from the clock or an unanswered alarm.",
                            systemImage: "forward.fill"
                        )
                        .foregroundColor(.orange)

                        Picker("Reason", selection: $skippedReason) {
                            ForEach(Dose2SkippedReason.allCases, id: \.self) { reason in
                                Text(reason.displayText).tag(reason)
                            }
                        }
                    } header: {
                        Text("Missed / not taken")
                    } footer: {
                        Text("For medication decisions, follow your current prescription instructions and contact your care team with questions.")
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }

                Section {
                    Button {
                        saveResolution()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text(choice == .recorded ? "Save Actual Dose 2" : "Mark Missed / Not Taken")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(saveDisabled)
                }
            }
            .navigationTitle("Resolve Dose 2")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .sheet(item: $workWarning) { warning in
            WorkWakeWarningSheet(warning: warning, repository: repository, recordOccurrence: { acknowledged in
                await recordOccurrence(occurrenceTime, takenReason == .unsure ? nil : takenReason.rawValue, normalizedNotes, acknowledged)
            }, onResult: { result in
                onCommitted(result)
                dismiss()
            })
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var latestSelectableTime: Date {
        max(referenceTime, dose1Time)
    }

    private var elapsedMinutes: Int {
        max(0, Int(occurrenceTime.timeIntervalSince(dose1Time) / 60))
    }

    private var elapsedSeconds: TimeInterval {
        max(0, occurrenceTime.timeIntervalSince(dose1Time))
    }

    private var timingConfig: DoseCore.DoseWindowConfig {
        DoseCore.DoseWindowConfig()
    }

    private var isOutsideWindow: Bool {
        elapsedSeconds < Double(timingConfig.minIntervalMin) * 60
            || elapsedSeconds >= Double(timingConfig.maxIntervalMin) * 60
    }

    private var timingWarningText: String {
        if elapsedSeconds < Double(timingConfig.minIntervalMin) * 60 {
            return "\(elapsedMinutes) minutes after Dose 1 — before the configured \(timingConfig.minIntervalMin)-minute window. Saving requires confirmation."
        }
        if elapsedSeconds >= Double(timingConfig.maxIntervalMin) * 60 {
            return "\(elapsedMinutes) minutes after Dose 1 — outside the configured \(timingConfig.maxIntervalMin)-minute window. Saving requires confirmation."
        }
        return "\(elapsedMinutes) minutes after Dose 1 — within the configured timing window. Verify this historical time before saving."
    }

    private var timingWarningSymbol: String {
        isOutsideWindow ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var timingWarningColor: Color {
        isOutsideWindow ? .orange : .green
    }

    private var normalizedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var saveDisabled: Bool {
        if isSaving { return true }
        switch choice {
        case .recorded:
            return !occurrenceConfirmed
        case .missed:
            return isAlreadyMarkedMissed
        }
    }

    private func saveResolution() {
        isSaving = true
        errorMessage = nil
        Task {
            let result: DoseActionCoordinator.ActionResult
            switch choice {
            case .recorded:
                result = await recordOccurrence(
                    occurrenceTime,
                    takenReason == .unsure ? nil : takenReason.rawValue,
                    normalizedNotes,
                    nil
                )
            case .missed:
                result = await markMissed(
                    skippedReason == .unsure ? nil : skippedReason.rawValue,
                    normalizedNotes
                )
            }

            await MainActor.run {
                isSaving = false
                switch result {
                case .success, .attentionRequired:
                    onCommitted(result)
                    dismiss()
                case .retryRequired(let message):
                    errorMessage = message
                case .blocked(let reason):
                    errorMessage = reason
                case .needsConfirm(.workWake(let warning)):
                    workWarning = warning
                case .needsConfirm:
                    errorMessage = "Confirm the occurrence and its actual time before saving."
                }
            }
        }
    }
}

struct DoseButtonsSection: View {
    @ObservedObject var core: DoseTapCore
    @Binding var showEarlyDoseAlert: Bool
    @Binding var earlyDoseMinutes: Int
    @State private var workWakeWarning: WorkWakeWarning?
    @State private var showExpiredDose2Resolution = false
    @State private var expiredResolutionReferenceTime = Date()
    @State private var reasonCaptureMode: Dose2OutcomeReasonMode?
    @State private var actionFeedback: DoseActionFeedback?
    @State private var clearFeedbackTask: Task<Void, Never>?

    var coordinator: DoseActionCoordinator

    private let windowOpenMinutes: Double = 150

    var body: some View {
        VStack(spacing: 12) {
            Button(action: handlePrimaryButtonTap) {
                Text(primaryButtonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(primaryButtonColor)
                    .cornerRadius(12)
            }
            .disabled(primaryButtonDisabled)
            .sheet(item: $workWakeWarning) { warning in
                if let repository = coordinator.sessionRepo {
                    WorkWakeWarningSheet(warning: warning, repository: repository, coordinator: coordinator, onResult: handleActionResult)
                }
            }
            .sheet(isPresented: $showExpiredDose2Resolution) {
                if let repository = coordinator.sessionRepo, let dose1Time = core.dose1Time {
                    ExpiredDose2ResolutionSheet(
                        dose1Time: dose1Time,
                        referenceTime: expiredResolutionReferenceTime,
                        isAlreadyMarkedMissed: core.isSkipped,
                        repository: repository,
                        recordOccurrence: { occurrenceTime, reason, notes, workWarning in
                            await coordinator.recordDose2Occurrence(
                                at: occurrenceTime,
                                warningConfirmed: true,
                                acknowledgedWorkWarning: workWarning,
                                reason: reason,
                                reasonNotes: notes,
                                surface: .sessionDetail
                            )
                        },
                        markMissed: { reason, notes in
                            await coordinator.skipDose(
                                reason: reason,
                                reasonNotes: notes,
                                surface: .sessionDetail
                            )
                        },
                        onCommitted: handleActionResult
                    )
                }
            }
            .sheet(item: $reasonCaptureMode) { mode in
                Dose2OutcomeReasonSheet(
                    mode: mode,
                    onConfirm: { reason, notes in
                        Task {
                            let result: DoseActionCoordinator.ActionResult
                            switch mode {
                            case .skipDose:
                                result = await coordinator.skipDose(reason: reason, reasonNotes: notes)
                            case .earlyDose:
                                result = await coordinator.takeDose2(override: .earlyConfirmed, reason: reason, reasonNotes: notes)
                            }
                            handleActionResult(result)
                            reasonCaptureMode = nil
                        }
                    },
                    onCancel: { reasonCaptureMode = nil }
                )
            }

            if let actionFeedback {
                DoseActionFeedbackBanner(feedback: actionFeedback)
            }

            if core.currentStatus == .beforeWindow {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Dose 2 window not yet open")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            HStack(spacing: 12) {
                Button("Snooze +10m") {
                    Task {
                        handleActionResult(await coordinator.snooze())
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!snoozeEnabled)

                Button("Skip Dose") {
                    reasonCaptureMode = .skipDose
                }
                .buttonStyle(.bordered)
                .disabled(!skipEnabled)
            }
        }
        .onDisappear {
            clearFeedbackTask?.cancel()
        }
    }

    private func handlePrimaryButtonTap() {
        if core.currentStatus == .closed
            || (core.currentStatus == .completed && core.isSkipped && core.dose2Time == nil) {
            expiredResolutionReferenceTime = Date()
            showExpiredDose2Resolution = true
            Haptics.light.play()
            return
        }

        Task {
            let isDose1 = core.dose1Time == nil
            let result = isDose1 ? await coordinator.takeDose1() : await coordinator.takeDose2()
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
        case .workWake(let warning):
            workWakeWarning = warning
        case .earlyDose(let minutes):
            earlyDoseMinutes = minutes
            showEarlyDoseAlert = true
        case .outsideWindowOccurrence, .afterSkip:
            expiredResolutionReferenceTime = Date()
            showExpiredDose2Resolution = true
        case .extraDose:
            showActionFeedback(
                DoseActionFeedback(
                    kind: .blocked,
                    title: "Extra dose requires Tonight",
                    message: "Open the Tonight dose controls to confirm an extra dose.",
                    systemImageName: "exclamationmark.triangle.fill"
                )
            )
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

    private var primaryButtonText: String {
        switch core.currentStatus {
        case .noDose1: return "Take Dose 1"
        case .beforeWindow: return "Waiting..."
        case .active, .nearClose: return "Record Dose 2"
        case .closed: return "Resolve Dose 2"
        case .completed:
            return core.isSkipped && core.dose2Time == nil ? "Correct Dose 2 Record" : "Complete ✓"
        case .finalizing: return "Check-In"
        }
    }

    private var primaryButtonColor: Color {
        switch core.currentStatus {
        case .noDose1: return .blue
        case .beforeWindow: return .gray
        case .active: return .green
        case .nearClose: return .orange
        case .closed: return .orange
        case .completed: return .purple
        case .finalizing: return .yellow
        }
    }

    private var snoozeEnabled: Bool {
        if case .snoozeEnabled = core.windowContext.snooze { return true }
        return false
    }

    private var skipEnabled: Bool {
        if case .skipEnabled = core.windowContext.skip { return true }
        return false
    }

    private var primaryButtonDisabled: Bool {
        if core.currentStatus == .completed && core.isSkipped && core.dose2Time == nil {
            return false
        }
        return core.currentStatus == .completed
    }
}

enum Dose2OutcomeReasonMode: Identifiable {
    case earlyDose
    case skipDose

    var id: String {
        switch self {
        case .earlyDose: return "early_dose"
        case .skipDose: return "skip_dose"
        }
    }
}

struct Dose2OutcomeReasonSheet: View {
    let mode: Dose2OutcomeReasonMode
    let onConfirm: (String?, String?) -> Void
    let onCancel: () -> Void

    @State private var takenReason: Dose2TakenReason = .unsure
    @State private var skippedReason: Dose2SkippedReason = .unsure
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(promptText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section(mode == .skipDose ? "Skip Reason" : "Timing Reason") {
                    if mode == .skipDose {
                        Picker("Reason", selection: $skippedReason) {
                            ForEach(Dose2SkippedReason.allCases, id: \.self) { reason in
                                Text(reason.displayText).tag(reason)
                            }
                        }
                    } else {
                        Picker("Reason", selection: $takenReason) {
                            ForEach(Dose2TakenReason.allCases, id: \.self) { reason in
                                Text(reason.displayText).tag(reason)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(titleText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmText) {
                        onConfirm(selectedReason, normalizedNotes)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var selectedReason: String? {
        switch mode {
        case .skipDose:
            return skippedReason == .unsure ? nil : skippedReason.rawValue
        case .earlyDose:
            return takenReason == .unsure ? nil : takenReason.rawValue
        }
    }

    private var normalizedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var titleText: String {
        switch mode {
        case .earlyDose: return "Early Dose Reason"
        case .skipDose: return "Skip Dose Reason"
        }
    }

    private var confirmText: String {
        switch mode {
        case .skipDose: return "Skip Dose"
        default: return "Continue"
        }
    }

    private var promptText: String {
        switch mode {
        case .earlyDose:
            return "Capture why you are taking Dose 2 before the window opened."
        case .skipDose:
            return "Capture why Dose 2 is being skipped now."
        }
    }
}

struct EarlyDoseOverrideSheet: View {
    let minutesRemaining: Int
    let onConfirm: (String?, String?) -> Void
    let onCancel: () -> Void

    @State private var holdProgress: CGFloat = 0
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    @State private var takenReason: Dose2TakenReason = .unsure
    @State private var notes = ""

    private let requiredHoldDuration: CGFloat = 3.0

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)

                Text("Override Dose Timing")
                    .font(.title2.bold())

                Text("Hold to confirm early dose")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 12) {
                WarningRow(icon: "clock.badge.exclamationmark", text: "\(TimeIntervalMath.formatMinutes(minutesRemaining)) early", color: .orange)
                WarningRow(icon: "pills.fill", text: "May reduce effectiveness", color: .red)
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("Why are you taking it early?")
                    .font(.headline)
                Picker("Reason", selection: $takenReason) {
                    ForEach(Dose2TakenReason.allCases, id: \.self) { reason in
                        Text(reason.displayText).tag(reason)
                    }
                }
                .pickerStyle(.menu)

                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Text("Hold for 3 seconds")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        .frame(width: 100, height: 100)

                    Circle()
                        .trim(from: 0, to: holdProgress)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: holdProgress)

                    Image(systemName: isHolding ? "hand.tap.fill" : "hand.tap")
                        .font(.title)
                        .foregroundColor(isHolding ? .red : .gray)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !isHolding { startHolding() } }
                        .onEnded { _ in stopHolding() }
                )
            }

            Button("Cancel") { onCancel() }
                .font(.headline)
                .foregroundColor(.blue)
                .padding(.bottom, 30)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func startHolding() {
        isHolding = true
        holdProgress = 0
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            holdProgress += 0.05 / requiredHoldDuration
            if holdProgress >= 1.0 {
                holdTimer?.invalidate()
                Haptics.warning.play()
                onConfirm(selectedReason, normalizedNotes)
            }
        }
    }

    private func stopHolding() {
        isHolding = false
        holdTimer?.invalidate()
        withAnimation(.easeOut(duration: 0.3)) { holdProgress = 0 }
    }

    private var selectedReason: String? {
        takenReason == .unsure ? nil : takenReason.rawValue
    }

    private var normalizedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct WarningRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct WorkWakeWarningSheet: View {
    @State var warning: WorkWakeWarning
    let repository: SessionRepository
    var coordinator: DoseActionCoordinator? = nil
    var recordOccurrence: ((WorkWakeWarning) async -> DoseActionCoordinator.ActionResult)? = nil
    let onResult: (DoseActionCoordinator.ActionResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var saving = false
    @State private var changingWake = false
    @State private var wakeTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                if !changingWake {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Later than your work-night target", systemImage: "clock.badge.exclamationmark")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("The selected dose time is later than the target you saved for this working date.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    LabeledContent("Working date", value: warning.dateLabel)
                    LabeledContent("Wake time", value: warning.wakeLabel)
                    LabeledContent("Warning target", value: warning.target.title)
                } footer: {
                    Text("Times use \(warning.timeZoneIdentifier). This advisory does not change your medication timing window.")
                }
                Section {
                    Button("Continue to Record Dose 2") {
                        saving = true
                        Task {
                            let result: DoseActionCoordinator.ActionResult
                            if let recordOccurrence {
                                result = await recordOccurrence(warning)
                            } else if let coordinator {
                                result = await coordinator.takeDose2(acknowledgedWorkWarning: warning)
                            } else {
                                result = .blocked(reason: "Reopen the dose record and retry.")
                            }
                            saving = false
                            switch result {
                            case .success, .attentionRequired:
                                dismiss()
                                onResult(result)
                            case .needsConfirm(.workWake(let updated)):
                                warning = updated
                                error = "Your schedule changed. Review the updated warning."
                            case .blocked(let message), .retryRequired(let message): error = message
                            case .needsConfirm: error = "Dose state changed. Cancel and review the current dose action."
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(saving)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                Section {
                    Button {
                        saveException(isWorking: false)
                    } label: {
                        Label("I'm not working this date", systemImage: "calendar.badge.minus")
                    }
                    .accessibilityLabel("I'm Not Working \(warning.dateLabel)")
                    .disabled(saving)
                    Button {
                        wakeTime = warning.requiredWake
                        changingWake = true
                    } label: {
                        Label("Change this date's wake time", systemImage: "alarm")
                    }
                    .accessibilityLabel("Change \(warning.dateLabel)'s Wake Time")
                    .disabled(saving)
                } header: {
                    Text("Adjust this date")
                } footer: {
                    Text("Schedule changes leave Dose 2 unrecorded.")
                }
                }
                if changingWake {
                    Section {
                        DatePicker("Required wake", selection: $wakeTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .accessibilityLabel("Required wake time")
                            .environment(\.timeZone, TimeZone(identifier: warning.timeZoneIdentifier) ?? .current)
                        Button("Save Wake Time") { saveException(isWorking: true) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .disabled(saving)
                    } header: {
                        Text(warning.dateLabel)
                    } footer: {
                        Text("Times use \(warning.timeZoneIdentifier). This updates only this date and leaves Dose 2 unrecorded. Your recurring schedule stays the same.")
                    }
                }
                if let error { Text(error).foregroundStyle(.primary).accessibilityLabel("Not saved. \(error)") }
            }
            .navigationTitle(changingWake ? "Change Wake Time" : "Work and Wake Warning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) } }
        }
        .interactiveDismissDisabled(saving)
    }

    private func saveException(isWorking: Bool) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: warning.timeZoneIdentifier) ?? .current
        let minutes = changingWake ? calendar.component(.hour, from: wakeTime) * 60 + calendar.component(.minute, from: wakeTime) : nil
        let result = repository.changeWorkWakeDate(warning, isWorking: isWorking, wakeMinutes: minutes)
        if result.isCommitted {
            dismiss() // Schedule changes never submit a medication action.
        } else {
            error = result.failure?.detail ?? "Schedule was not saved. Please retry."
        }
    }
}
