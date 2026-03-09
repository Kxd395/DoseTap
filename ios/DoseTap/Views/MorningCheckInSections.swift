//
//  MorningCheckInSections.swift
//  DoseTap
//

import SwiftUI
import DoseCore

struct MorningCheckInQuickModeSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 20) {
            MorningCheckInSectionCard(title: "Sleep Quality", icon: "star.fill") {
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            viewModel.sleepQuality = star
                        } label: {
                            Image(systemName: star <= viewModel.sleepQuality ? "star.fill" : "star")
                                .font(.title)
                                .foregroundColor(star <= viewModel.sleepQuality ? .yellow : .gray.opacity(0.3))
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            MorningCheckInSectionCard(title: "How Rested Do You Feel?", icon: "battery.100") {
                MorningCheckInRestedPicker(viewModel: viewModel)
            }

            MorningCheckInSectionCard(title: "Morning Grogginess", icon: "cloud.sun.fill") {
                MorningCheckInGrogginessPicker(viewModel: viewModel)
            }
        }
    }
}

struct MorningCheckInDoseReconciliationSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Dose Confirmation")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Dose 1", icon: "1.circle.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    if let loggedDose1Time = viewModel.loggedDose1Time {
                        MorningCheckInDoseStatusRow(
                            title: "Logged overnight",
                            detail: "Dose 1 was already recorded at \(AppFormatters.shortTime.string(from: loggedDose1Time))."
                        )
                    } else {
                        Toggle("I took Dose 1 but missed the tap", isOn: $viewModel.reconcileDose1Taken)
                        if viewModel.reconcileDose1Taken {
                            DatePicker(
                                "Approximate Dose 1 time",
                                selection: $viewModel.reconcileDose1Time,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            Stepper(value: $viewModel.reconcileDose1AmountMg, in: 250...20_000, step: 250) {
                                HStack {
                                    Text("Dose 1 amount")
                                    Spacer()
                                    Text("\(viewModel.reconcileDose1AmountMg.formatted(.number.grouping(.automatic))) mg")
                                        .foregroundColor(.secondary)
                                }
                            }
                            if viewModel.reconcileDose1NeedsWarning {
                                Text("Dose 1 amount is above 9,000 mg. Double-check before saving.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        } else {
                            MorningCheckInDoseStatusRow(
                                title: "No backfill selected",
                                detail: "Leave this off if Dose 1 was not taken or if you want to keep the session incomplete."
                            )
                        }
                    }
                }
            }

            MorningCheckInSectionCard(title: "Dose 2", icon: "2.circle.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    if let loggedDose2Time = viewModel.loggedDose2Time {
                        MorningCheckInDoseStatusRow(
                            title: "Logged overnight",
                            detail: "Dose 2 was already recorded at \(AppFormatters.shortTime.string(from: loggedDose2Time))."
                        )
                    } else {
                        Picker("Dose 2 status", selection: $viewModel.dose2Reconciliation) {
                            ForEach(Dose2ReconciliationChoice.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch viewModel.dose2Reconciliation {
                        case .leaveAsIs:
                            MorningCheckInDoseStatusRow(
                                title: "Leave unchanged",
                                detail: "Use this if you do not want morning check-in to change Dose 2 for this session."
                            )
                        case .taken:
                            DatePicker(
                                "Approximate Dose 2 time",
                                selection: $viewModel.reconcileDose2Time,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            Stepper(value: $viewModel.reconcileDose2AmountMg, in: 250...20_000, step: 250) {
                                HStack {
                                    Text("Dose 2 amount")
                                    Spacer()
                                    Text("\(viewModel.reconcileDose2AmountMg.formatted(.number.grouping(.automatic))) mg")
                                        .foregroundColor(.secondary)
                                }
                            }
                            if viewModel.reconcileDose2NeedsWarning {
                                Text("Dose 2 amount is above 9,000 mg. Double-check before saving.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        case .skipped:
                            MorningCheckInDoseStatusRow(
                                title: "Mark Dose 2 skipped",
                                detail: "Morning check-in will keep this session complete and record that Dose 2 was skipped."
                            )
                        }
                    }

                    Text("Approximate times are fine here. Use this when you forgot to tap the dose button overnight.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct MorningCheckInMorningFunctioningSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Morning Functioning")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Sleep Inertia", icon: "timer") {
                OptionGrid(
                    options: SleepInertiaDuration.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.sleepInertiaDuration)
                )
            }

            MorningCheckInSectionCard(title: "Mental Clarity", icon: "lightbulb.max.fill") {
                MorningCheckInScoreSlider(
                    value: $viewModel.mentalClarity,
                    range: 1...5,
                    accentColor: .yellow,
                    lowLabel: "Foggy",
                    highLabel: "Clear"
                )
            }

            MorningCheckInSectionCard(title: "Mood", icon: "face.smiling") {
                OptionGrid(
                    options: MoodLevel.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.mood)
                )
            }

            MorningCheckInSectionCard(title: "Anxiety", icon: "heart.text.square") {
                OptionGrid(
                    options: AnxietyLevel.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.anxietyLevel)
                )
            }

            MorningCheckInSectionCard(title: "Stress Level", icon: "brain.head.profile") {
                StressSlider(value: $viewModel.stressLevel)
            }

            if viewModel.stressLevel != nil || !viewModel.stressDrivers.isEmpty || viewModel.stressProgression != nil || !viewModel.stressNotes.isEmpty {
                MorningCheckInSectionCard(title: "Current Stressors", icon: "exclamationmark.triangle") {
                    MultiSelectGrid(
                        options: PreSleepLogAnswers.StressDriver.allCases,
                        selections: $viewModel.stressDrivers
                    )
                }

                MorningCheckInSectionCard(title: "Stress Trend Since Bedtime", icon: "chart.line.uptrend.xyaxis") {
                    OptionGrid(
                        options: PreSleepLogAnswers.StressProgression.allCases,
                        selection: Binding(
                            get: { viewModel.stressProgression },
                            set: { viewModel.stressProgression = $0 }
                        )
                    )
                }

                MorningCheckInSectionCard(title: "Stress Notes", icon: "square.and.pencil") {
                    TextField(
                        "What is driving it, what helped, or what worsened overnight?",
                        text: $viewModel.stressNotes,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                }
            }

            MorningCheckInSectionCard(title: "Readiness For The Day", icon: "figure.walk") {
                MorningCheckInScoreSlider(
                    value: $viewModel.readinessForDay,
                    range: 1...5,
                    accentColor: .green,
                    lowLabel: "Barely",
                    highLabel: "Ready"
                )
            }

            MorningCheckInSectionCard(title: "Dream Recall", icon: "sparkles") {
                OptionGrid(
                    options: DreamRecallType.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.dreamRecall)
                )
            }
        }
    }
}

struct MorningCheckInSymptomTogglesSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Any Issues?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                symptomToggleButton(title: "Physical Pain", icon: "figure.wave", isActive: viewModel.hasPhysicalSymptoms) {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.hasPhysicalSymptoms.toggle()
                    }
                }

                symptomToggleButton(title: "Sick/Respiratory", icon: "lungs.fill", isActive: viewModel.hasRespiratorySymptoms) {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.hasRespiratorySymptoms.toggle()
                    }
                }
            }
        }
    }

    private func symptomToggleButton(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isActive ? Color.red.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            .foregroundColor(isActive ? .red : .secondary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.red : Color.clear, lineWidth: 2)
            )
        }
    }
}

struct MorningCheckInPhysicalSymptomsSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel
    @Binding var showPainEntryEditor: Bool
    @Binding var editingPainEntry: PreSleepLogAnswers.PainEntry?

    var body: some View {
        VStack(spacing: 16) {
            Text("Physical Symptoms")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Pain detail by area + side", icon: "figure.arms.open") {
                VStack(spacing: 10) {
                    if viewModel.painEntries.isEmpty {
                        Text("Add entries like Mid Back (Both) 2/10 and Lower Back (Right) 9/10.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(viewModel.painEntries, id: \.entryKey) { entry in
                            HStack(spacing: 10) {
                                GranularPainEntryRow(entry: entry)
                                Spacer(minLength: 4)

                                Button {
                                    editingPainEntry = entry
                                    showPainEntryEditor = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    viewModel.removePainEntry(entry.entryKey)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(10)
                        }
                    }

                    Button {
                        editingPainEntry = nil
                        showPainEntryEditor = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Pain Entry")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(10)
                    }
                }
            }

            MorningCheckInSectionCard(title: "Headache", icon: "brain.head.profile") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Headache", isOn: $viewModel.hasHeadache)
                    if viewModel.hasHeadache {
                        OptionGrid(
                            options: HeadacheSeverity.allCases,
                            selection: morningCheckInOptionalBinding(viewModel, \.headacheSeverity)
                        )
                        OptionGrid(
                            options: HeadacheLocation.allCases,
                            selection: morningCheckInOptionalBinding(viewModel, \.headacheLocation)
                        )
                        Toggle("Migraine-like", isOn: $viewModel.isMigraine)
                    }
                }
            }

            MorningCheckInSectionCard(title: "Muscle Stiffness", icon: "figure.strengthtraining.traditional") {
                OptionGrid(
                    options: StiffnessLevel.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.muscleStiffness)
                )
            }

            MorningCheckInSectionCard(title: "Muscle Soreness", icon: "figure.cooldown") {
                OptionGrid(
                    options: SorenessLevel.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.muscleSoreness)
                )
            }

            MorningCheckInSectionCard(title: "Pain Notes", icon: "note.text") {
                TextField("Add anything specific that stood out", text: $viewModel.painNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }
}

struct MorningCheckInRespiratorySymptomsSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Respiratory / Illness")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            MorningCheckInSectionCard(title: "Nose", icon: "wind") {
                MorningCheckInCongestionPicker(viewModel: viewModel)
            }

            MorningCheckInSectionCard(title: "Throat", icon: "mouth") {
                MorningCheckInThroatPicker(viewModel: viewModel)
            }

            MorningCheckInSectionCard(title: "Cough", icon: "lungs") {
                OptionGrid(
                    options: CoughType.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.coughType)
                )
            }

            MorningCheckInSectionCard(title: "Sinus Pressure", icon: "face.dashed") {
                OptionGrid(
                    options: SinusPressureLevel.allCases,
                    selection: morningCheckInOptionalBinding(viewModel, \.sinusPressure)
                )
            }

            MorningCheckInSectionCard(title: "Illness Severity", icon: "thermometer.medium") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Feeling feverish", isOn: $viewModel.feelingFeverish)
                    OptionGrid(
                        options: SicknessLevel.allCases,
                        selection: morningCheckInOptionalBinding(viewModel, \.sicknessLevel)
                    )
                    TextField("Respiratory notes", text: $viewModel.respiratoryNotes, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }
}

struct MorningCheckInSleepEnvironmentSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.showSleepEnvironmentSection.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "bed.double.circle")
                        .foregroundColor(.teal)
                    Text("Sleep Environment")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showSleepEnvironmentSection ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            if viewModel.showSleepEnvironmentSection {
                VStack(spacing: 16) {
                    Toggle("Add room/setup details", isOn: $viewModel.hasSleepEnvironment.animation(.spring(response: 0.3)))
                        .toggleStyle(SwitchToggleStyle(tint: .teal))

                    if viewModel.hasSleepEnvironment {
                        MorningCheckInSectionCard(title: "Room Temperature", icon: "thermometer") {
                            OptionGrid(
                                options: PreSleepLogAnswers.RoomTemp.allCases,
                                selection: morningCheckInOptionalBinding(viewModel, \.sleepEnvironmentRoomTemp)
                            )
                        }

                        MorningCheckInSectionCard(title: "Noise Level", icon: "speaker.wave.2.fill") {
                            OptionGrid(
                                options: PreSleepLogAnswers.NoiseLevel.allCases,
                                selection: morningCheckInOptionalBinding(viewModel, \.sleepEnvironmentNoiseLevel)
                            )
                        }

                        MorningCheckInSectionCard(title: "Sleep Aids / Setup", icon: "moon.zzz") {
                            OptionGrid(
                                options: PreSleepLogAnswers.SleepAid.allCases,
                                selection: morningCheckInOptionalBinding(viewModel, \.sleepEnvironmentSleepAid)
                            )
                        }

                        MorningCheckInSectionCard(title: "Environment Notes", icon: "note.text") {
                            TextField("Example: outside noise, too warm, travel setup", text: $viewModel.sleepEnvironmentNotes, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct MorningCheckInSleepTherapySection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.showSleepTherapySection.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "wind")
                        .foregroundColor(.cyan)
                    Text("Sleep Therapy Device")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showSleepTherapySection ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            if viewModel.showSleepTherapySection {
                VStack(spacing: 16) {
                    Toggle("Used Sleep Therapy Device", isOn: $viewModel.usedSleepTherapy.animation(.spring(response: 0.3)))
                        .toggleStyle(SwitchToggleStyle(tint: .cyan))

                    if viewModel.usedSleepTherapy {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Device Type")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(SleepTherapyDevice.allCases.filter { $0 != .none }, id: \.self) { device in
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            viewModel.sleepTherapyDevice = device
                                        }
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: device.icon)
                                                .font(.title2)
                                                .foregroundColor(viewModel.sleepTherapyDevice == device ? .cyan : .secondary)
                                            Text(device.rawValue)
                                                .font(.caption)
                                                .foregroundColor(viewModel.sleepTherapyDevice == device ? .primary : .secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(viewModel.sleepTherapyDevice == device ? Color.cyan.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(viewModel.sleepTherapyDevice == device ? Color.cyan : Color.clear, lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        MorningCheckInSectionCard(title: "How Much Of The Night?", icon: "percent") {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Compliance")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(viewModel.sleepTherapyCompliance)%")
                                        .font(.headline)
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.sleepTherapyCompliance) },
                                        set: { viewModel.sleepTherapyCompliance = Int($0.rounded()) }
                                    ),
                                    in: 0...100,
                                    step: 5
                                )
                                .tint(.cyan)
                            }
                        }

                        MorningCheckInSectionCard(title: "Sleep Therapy Notes", icon: "note.text") {
                            TextField("Mask fit, comfort, leaks, or anything notable", text: $viewModel.sleepTherapyNotes, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct MorningCheckInNarcolepsySection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.showNarcolepsySection.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundColor(.indigo)
                    Text("Narcolepsy Symptoms")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showNarcolepsySection ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            if viewModel.showNarcolepsySection {
                VStack(spacing: 8) {
                    Toggle("Sleep Paralysis", isOn: $viewModel.hadSleepParalysis).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Hallucinations", isOn: $viewModel.hadHallucinations).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Automatic Behavior", isOn: $viewModel.hadAutomaticBehavior).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Fell Out Of Bed", isOn: $viewModel.fellOutOfBed).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Confusion On Waking", isOn: $viewModel.hadConfusionOnWaking).toggleStyle(SwitchToggleStyle(tint: .indigo))
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct MorningCheckInNotesSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
            TextField("Anything else to note?", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct MorningCheckInRememberSettingsSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        HStack {
            Image(systemName: viewModel.rememberSettings ? "checkmark.square.fill" : "square")
                .foregroundColor(viewModel.rememberSettings ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Remember last wake-up settings")
                    .font(.subheadline)
                Text("Auto-prefill your last morning check-in setup next time.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .onTapGesture {
            withAnimation {
                viewModel.setRememberSettingsEnabled(!viewModel.rememberSettings)
            }
        }
    }
}

struct MorningCheckInSubmitSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel
    let dismissAction: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasPhysicalSymptoms && viewModel.painEntries.isEmpty {
                Text("Add at least one pain entry before submitting.")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button {
                Task {
                    await viewModel.submit()
                    dismissAction()
                    onComplete()
                }
            } label: {
                HStack {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Complete Check-In")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.gradient)
                .cornerRadius(16)
            }
            .disabled(viewModel.isSubmitting || (viewModel.hasPhysicalSymptoms && viewModel.painEntries.isEmpty))
        }
        .padding(.top, 8)
    }
}

struct MorningCheckInSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            content
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct MorningCheckInDoseStatusRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

struct MorningCheckInRestedPicker: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        Picker("Rested", selection: $viewModel.feelRested) {
            ForEach(RestedLevel.allCases, id: \.self) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct MorningCheckInGrogginessPicker: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        HStack(spacing: 12) {
            ForEach(GrogginessLevel.allCases, id: \.self) { level in
                Button {
                    viewModel.grogginess = level
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: level.icon)
                            .font(.title2)
                        Text(level.rawValue)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(viewModel.grogginess == level ? Color.orange.opacity(0.2) : Color.clear)
                    .foregroundColor(viewModel.grogginess == level ? .orange : .secondary)
                    .cornerRadius(8)
                }
            }
        }
    }
}

struct MorningCheckInCongestionPicker: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        Picker("", selection: $viewModel.congestion) {
            ForEach(CongestionType.allCases, id: \.self) { value in
                Text(value.rawValue).tag(value)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct MorningCheckInThroatPicker: View {
    @ObservedObject var viewModel: MorningCheckInViewModel

    var body: some View {
        Picker("", selection: $viewModel.throatCondition) {
            ForEach(ThroatCondition.allCases, id: \.self) { value in
                Text(value.rawValue).tag(value)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct MorningCheckInScoreSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let accentColor: Color
    let lowLabel: String
    let highLabel: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(lowLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(value)/\(range.upperBound)")
                    .font(.headline)
                Spacer()
                Text(highLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(accentColor)
        }
    }
}

func morningCheckInOptionalBinding<T>(
    _ viewModel: MorningCheckInViewModel,
    _ keyPath: ReferenceWritableKeyPath<MorningCheckInViewModel, T>
) -> Binding<T?> {
    Binding<T?>(
        get: { .some(viewModel[keyPath: keyPath]) },
        set: { newValue in
            guard let newValue else { return }
            viewModel[keyPath: keyPath] = newValue
        }
    )
}
