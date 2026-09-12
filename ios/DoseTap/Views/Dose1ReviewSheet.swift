import SwiftUI

struct Dose1ReviewSheet: View {
    let review: DoseActionCoordinator.Dose1Review
    let coordinator: DoseActionCoordinator
    let onCommitted: (DoseActionCoordinator.ActionResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var settings = UserSettingsManager.shared
    @State private var takenNow = true
    @State private var earlierTime = Date()
    @State private var interval = UserSettingsManager.shared.targetIntervalMinutes
    @State private var remember = false
    @State private var busy = false
    @State private var attemptedTime: Date?
    @State private var retrySave = false
    @State private var committed = false
    @State private var savedDose: Date?
    @State private var savedSession: String?
    @State private var message: String?
    @State private var alarmVerified = false
    @State private var changingAlarm = false
    @State private var appliedInterval = UserSettingsManager.shared.targetIntervalMinutes

    private func duration(_ minutes: Int) -> String { "\(minutes / 60)h \(minutes % 60)m" }
    private func clock(_ time: Date) -> String {
        "\(time.formatted(date: .abbreviated, time: .shortened)) (\(TimeZone.current.abbreviation(for: time) ?? TimeZone.current.identifier))"
    }

    var body: some View {
        NavigationStack {
            Form {
                if !committed {
                    Section("Dose 1 taken at") {
                        Text("Confirm only after taking Dose 1. Opening this sheet records nothing.")
                        Picker("Recorded occurrence", selection: $takenNow) {
                            Text("Now").tag(true)
                            Text("Earlier tonight").tag(false)
                        }.pickerStyle(.segmented).disabled(attemptedTime != nil)
                        if !takenNow {
                            DatePicker("Taken at", selection: $earlierTime, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                .disabled(attemptedTime != nil)
                        }
                        if let attemptedTime {
                            Text("Confirmed occurrence retained for retry: \(clock(attemptedTime))")
                        }
                    }
                }
                if !committed || changingAlarm {
                    Section("Remind me for Dose 2 after") {
                        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                            ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 125))]) {
                            ForEach(settings.validTargetOptions, id: \.self) { value in
                                Button { interval = value } label: {
                                    HStack {
                                        Text(duration(value))
                                        if interval == value { Image(systemName: "checkmark.circle.fill") }
                                    }.frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .tint(interval == value ? .accentColor : .secondary)
                                .foregroundStyle(interval == value ? Color.accentColor : Color.primary)
                                .accessibilityIdentifier("dose1-interval-\(value)")
                                .accessibilityValue(interval == value ? "Selected" : "Not selected")
                            }
                        }.disabled(!committed && attemptedTime != nil)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let occurrence = savedDose ?? attemptedTime ?? (takenNow ? coordinator.dateProvider.now() : earlierTime)
                            Text("Dose 2 alarm: \(clock(occurrence.addingTimeInterval(Double(interval) * 60)))")
                                .accessibilityIdentifier("dose1-alarm-preview")
                        }
                        if !committed {
                            Toggle("Use as my usual reminder interval", isOn: $remember)
                                .accessibilityIdentifier("dose1-remember-interval")
                                .disabled(attemptedTime != nil)
                            Text("Otherwise this choice is for tonight only. The reminder target does not change your dosing window.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if committed, let attemptedTime {
                    Section("Recorded") {
                        Text("Dose 1 recorded at \(clock(attemptedTime))")
                            .accessibilityIdentifier("dose1-saved-result")
                        if alarmVerified {
                            Text("Dose 2 alarm set for \(clock(coordinator.alarmService.targetWakeTime ?? attemptedTime))")
                                .accessibilityIdentifier("dose1-alarm-result")
                        }
                        if savedSession != nil, savedDose != nil {
                            if changingAlarm || !alarmVerified {
                                Button(changingAlarm ? "Update Dose 2 alarm" : "Retry alarm setup", action: updateAlarm)
                                    .accessibilityIdentifier("dose1-retry-alarm")
                            }
                            Button(changingAlarm ? "Keep current alarm" : "Change alarm") {
                                if changingAlarm { interval = appliedInterval }
                                changingAlarm.toggle()
                            }
                                .accessibilityIdentifier("dose1-change-alarm")
                        }
                        Text("Changing or retrying the alarm does not record another dose.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    NavigationLink("Alarm options and test") { SystemAlarmSettingsView() }
                    Text("In-app snooze: \(settings.snoozeDurationMinutes) minutes, up to \(settings.maxSnoozes) times. Change snooze preferences in Settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if committed, let message { Section("Result") { Text(message).accessibilityIdentifier("dose1-review-message") } }
            }
            // A successful write replaces the form with its result. Start that
            // result at the top, including when large text required scrolling.
            .id(committed)
            .disabled(busy)
            .safeAreaInset(edge: .bottom) {
                if !committed {
                    VStack(spacing: 8) {
                    if let message { Text(message).font(.footnote).accessibilityIdentifier("dose1-review-message") }
                    Button(action: save) {
                        Text(retrySave ? "Retry saving Dose 1" : "Confirm Dose 1 taken & set alarm")
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("dose1-confirm-record")
                    .disabled(busy || (attemptedTime != nil && !retrySave))
                    }
                    .padding().background(.bar)
                }
            }
            .navigationTitle(committed ? "Dose 1 recorded" : "Review Dose 1")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(committed ? "Done" : "Cancel") { dismiss() }
                        .accessibilityIdentifier("dose1-close-review").disabled(busy)
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .onDisappear { coordinator.cancelDose1Review(review) }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                coordinator.cancelDose1Review()
                if !committed && !busy { dismiss() }
            }
        }
    }

    private func save() {
        guard !busy, !committed, scenePhase == .active else { return }
        let token: DoseActionCoordinator.Dose1Review
        if retrySave {
            guard let fresh = coordinator.prepareDose1Review() else {
                message = "The session changed. Cancel and review tonight again."; return
            }
            token = fresh
        } else { token = review }
        if attemptedTime == nil { attemptedTime = takenNow ? coordinator.dateProvider.now() : earlierTime }
        busy = true
        Task {
            let result = await coordinator.confirmDose1(token, occurrence: attemptedTime, targetMinutes: interval, remember: remember)
            busy = false
            switch result {
            case .success, .attentionRequired:
                committed = true
                appliedInterval = interval
                if let receipt = coordinator.savedDose1Review, receipt.reviewId == token.id {
                    savedDose = receipt.occurrence
                    savedSession = receipt.sessionId
                }
                alarmVerified = savedSession == coordinator.sessionRepo?.activeSessionId
                    && coordinator.sessionRepo?.dose2Time == nil && coordinator.alarmService.alarmScheduled
                message = alarmVerified ? "Dose saved. Review the alarm result above." : "Dose 1 is saved. The Dose 2 alarm is not verified."
                if case .attentionRequired(let detail) = result { message = detail }
                onCommitted(result)
            case .retryRequired(let detail): retrySave = true; message = detail
            case .blocked(let detail): retrySave = false; message = detail
            case .needsConfirm: message = "The dose state changed. Cancel and review tonight again."
            }
        }
    }

    private func updateAlarm() {
        guard !busy, scenePhase == .active, let savedSession, let savedDose else { return }
        busy = true
        Task {
            let result = await coordinator.retryDose1Alarm(sessionId: savedSession, dose1: savedDose, targetMinutes: interval)
            busy = false
            alarmVerified = coordinator.alarmService.alarmScheduled
            switch result {
            case .success(let detail): message = detail; appliedInterval = interval; changingAlarm = false
            case .attentionRequired(let detail), .retryRequired(let detail): message = detail
            case .blocked(let detail): message = detail; alarmVerified = false
            case .needsConfirm: message = "Review tonight before changing the alarm."
            }
        }
    }
}
