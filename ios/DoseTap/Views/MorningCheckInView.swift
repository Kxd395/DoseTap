//
//  MorningCheckInView.swift
//  DoseTap
//
//  Morning questionnaire with progressive disclosure:
//  - Quick Mode: 5 core questions (30 seconds)
//  - Deep Dive: Conditional expansion for symptoms
//

import SwiftUI
import DoseCore

public struct MorningCheckInView: View {
    @StateObject private var viewModel: MorningCheckInViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPainEntryEditor = false
    @State private var editingPainEntry: PreSleepLogAnswers.PainEntry?

    let onComplete: () -> Void

    public init(sessionId: String, sessionDate: String, onComplete: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: MorningCheckInViewModel(sessionId: sessionId, sessionDate: sessionDate))
        self.onComplete = onComplete
    }

    public init(sessionId: String, sessionDate: String, existingCheckIn: StoredMorningCheckIn, onComplete: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: MorningCheckInViewModel(sessionId: sessionId, sessionDate: sessionDate, existing: existingCheckIn))
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    quickModeSection
                    doseReconciliationSection
                    morningFunctioningSection
                    symptomTogglesSection
                    if viewModel.hasPhysicalSymptoms { physicalSymptomsSection }
                    if viewModel.hasRespiratorySymptoms { respiratorySymptomsSection }
                    sleepEnvironmentSection
                    sleepTherapySection
                    narcolepsySection
                    notesSection
                    rememberSettingsSection
                    submitButton
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Morning Check-In")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        dismiss()
                        onComplete()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .sheet(isPresented: $showPainEntryEditor) {
                GranularPainEntryEditorView(initialEntry: editingPainEntry) { result in
                    viewModel.upsertPainEntries(result.entries, replacingEntryKey: result.replacedEntryKey)
                }
            }
        }
    }

    private var doseReconciliationSection: some View {
        VStack(spacing: 16) {
            Text("Dose Confirmation")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            cardView(title: "Dose 1", icon: "1.circle.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    if let loggedDose1Time = viewModel.loggedDose1Time {
                        doseStatusRow(
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
                            doseStatusRow(
                                title: "No backfill selected",
                                detail: "Leave this off if Dose 1 was not taken or if you want to keep the session incomplete."
                            )
                        }
                    }
                }
            }

            cardView(title: "Dose 2", icon: "2.circle.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    if let loggedDose2Time = viewModel.loggedDose2Time {
                        doseStatusRow(
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
                            doseStatusRow(
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
                            doseStatusRow(
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

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange.gradient)
            Text("Good Morning!")
                .font(.title2.bold())
            Text("Quick check-in about last night's sleep")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 8)
    }

    private var quickModeSection: some View {
        VStack(spacing: 20) {
            cardView(title: "Sleep Quality", icon: "star.fill") {
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
            cardView(title: "How Rested Do You Feel?", icon: "battery.100") { restedPicker }
            cardView(title: "Morning Grogginess", icon: "cloud.sun.fill") { grogginessPicker }
        }
    }

    private var morningFunctioningSection: some View {
        VStack(spacing: 16) {
            Text("Morning Functioning")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            cardView(title: "Sleep Inertia", icon: "timer") {
                OptionGrid(
                    options: SleepInertiaDuration.allCases,
                    selection: optionalBinding(\.sleepInertiaDuration)
                )
            }
            cardView(title: "Mental Clarity", icon: "lightbulb.max.fill") {
                scoreSlider(
                    value: $viewModel.mentalClarity,
                    range: 1...5,
                    accentColor: .yellow,
                    lowLabel: "Foggy",
                    highLabel: "Clear"
                )
            }
            cardView(title: "Mood", icon: "face.smiling") {
                OptionGrid(
                    options: MoodLevel.allCases,
                    selection: optionalBinding(\.mood)
                )
            }
            cardView(title: "Anxiety", icon: "heart.text.square") {
                OptionGrid(
                    options: AnxietyLevel.allCases,
                    selection: optionalBinding(\.anxietyLevel)
                )
            }
            cardView(title: "Stress Level", icon: "brain.head.profile") {
                StressSlider(value: $viewModel.stressLevel)
            }
            if viewModel.stressLevel != nil || !viewModel.stressDrivers.isEmpty || viewModel.stressProgression != nil || !viewModel.stressNotes.isEmpty {
                cardView(title: "Current Stressors", icon: "exclamationmark.triangle") {
                    MultiSelectGrid(
                        options: PreSleepLogAnswers.StressDriver.allCases,
                        selections: $viewModel.stressDrivers
                    )
                }
                cardView(title: "Stress Trend Since Bedtime", icon: "chart.line.uptrend.xyaxis") {
                    OptionGrid(
                        options: PreSleepLogAnswers.StressProgression.allCases,
                        selection: Binding(
                            get: { viewModel.stressProgression },
                            set: { viewModel.stressProgression = $0 }
                        )
                    )
                }
                cardView(title: "Stress Notes", icon: "square.and.pencil") {
                    TextField(
                        "What is driving it, what helped, or what worsened overnight?",
                        text: $viewModel.stressNotes,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                }
            }
            cardView(title: "Readiness For The Day", icon: "figure.walk") {
                scoreSlider(
                    value: $viewModel.readinessForDay,
                    range: 1...5,
                    accentColor: .green,
                    lowLabel: "Barely",
                    highLabel: "Ready"
                )
            }
            cardView(title: "Dream Recall", icon: "sparkles") {
                OptionGrid(
                    options: DreamRecallType.allCases,
                    selection: optionalBinding(\.dreamRecall)
                )
            }
        }
    }

    private var symptomTogglesSection: some View {
        VStack(spacing: 12) {
            Text("Any Issues?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                symptomToggleButton(title: "Physical Pain", icon: "figure.wave", isActive: viewModel.hasPhysicalSymptoms) {
                    withAnimation(.spring(response: 0.3)) { viewModel.hasPhysicalSymptoms.toggle() }
                }
                symptomToggleButton(title: "Sick/Respiratory", icon: "lungs.fill", isActive: viewModel.hasRespiratorySymptoms) {
                    withAnimation(.spring(response: 0.3)) { viewModel.hasRespiratorySymptoms.toggle() }
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

    private var physicalSymptomsSection: some View {
        VStack(spacing: 16) {
            Text("Physical Symptoms")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            cardView(title: "Pain detail by area + side", icon: "figure.arms.open") {
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
            cardView(title: "Headache", icon: "brain.head.profile") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Headache", isOn: $viewModel.hasHeadache)
                    if viewModel.hasHeadache {
                        OptionGrid(
                            options: HeadacheSeverity.allCases,
                            selection: optionalBinding(\.headacheSeverity)
                        )
                        OptionGrid(
                            options: HeadacheLocation.allCases,
                            selection: optionalBinding(\.headacheLocation)
                        )
                        Toggle("Migraine-like", isOn: $viewModel.isMigraine)
                    }
                }
            }
            cardView(title: "Muscle Stiffness", icon: "figure.strengthtraining.traditional") {
                OptionGrid(
                    options: StiffnessLevel.allCases,
                    selection: optionalBinding(\.muscleStiffness)
                )
            }
            cardView(title: "Muscle Soreness", icon: "figure.cooldown") {
                OptionGrid(
                    options: SorenessLevel.allCases,
                    selection: optionalBinding(\.muscleSoreness)
                )
            }
            cardView(title: "Pain Notes", icon: "note.text") {
                TextField("Add anything specific that stood out", text: $viewModel.painNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }

    private var respiratorySymptomsSection: some View {
        VStack(spacing: 16) {
            Text("Respiratory / Illness")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            cardView(title: "Nose", icon: "wind") { congestionPicker }
            cardView(title: "Throat", icon: "mouth") { throatPicker }
            cardView(title: "Cough", icon: "lungs") {
                OptionGrid(
                    options: CoughType.allCases,
                    selection: optionalBinding(\.coughType)
                )
            }
            cardView(title: "Sinus Pressure", icon: "face.dashed") {
                OptionGrid(
                    options: SinusPressureLevel.allCases,
                    selection: optionalBinding(\.sinusPressure)
                )
            }
            cardView(title: "Illness Severity", icon: "thermometer.medium") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Feeling feverish", isOn: $viewModel.feelingFeverish)
                    OptionGrid(
                        options: SicknessLevel.allCases,
                        selection: optionalBinding(\.sicknessLevel)
                    )
                    TextField("Respiratory notes", text: $viewModel.respiratoryNotes, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }

    private var sleepEnvironmentSection: some View {
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
                        cardView(title: "Room Temperature", icon: "thermometer") {
                            OptionGrid(
                                options: PreSleepLogAnswers.RoomTemp.allCases,
                                selection: optionalBinding(\.sleepEnvironmentRoomTemp)
                            )
                        }
                        cardView(title: "Noise Level", icon: "speaker.wave.2.fill") {
                            OptionGrid(
                                options: PreSleepLogAnswers.NoiseLevel.allCases,
                                selection: optionalBinding(\.sleepEnvironmentNoiseLevel)
                            )
                        }
                        cardView(title: "Sleep Aids / Setup", icon: "moon.zzz") {
                            OptionGrid(
                                options: PreSleepLogAnswers.SleepAid.allCases,
                                selection: optionalBinding(\.sleepEnvironmentSleepAid)
                            )
                        }
                        cardView(title: "Environment Notes", icon: "note.text") {
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

    private var sleepTherapySection: some View {
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
                        cardView(title: "How Much Of The Night?", icon: "percent") {
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
                        cardView(title: "Sleep Therapy Notes", icon: "note.text") {
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

    private var narcolepsySection: some View {
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

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
            TextField("Anything else to note?", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func doseStatusRow(title: String, detail: String) -> some View {
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

    private var rememberSettingsSection: some View {
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

    private var submitButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasPhysicalSymptoms && viewModel.painEntries.isEmpty {
                Text("Add at least one pain entry before submitting.")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button {
                Task {
                    await viewModel.submit()
                    dismiss()
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

    private func cardView<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            content()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var restedPicker: some View {
        Picker("Rested", selection: $viewModel.feelRested) {
            ForEach(RestedLevel.allCases, id: \.self) {
                Text($0.rawValue).tag($0)
            }
        }
        .pickerStyle(.segmented)
    }

    private var grogginessPicker: some View {
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

    private var congestionPicker: some View {
        Picker("", selection: $viewModel.congestion) {
            ForEach(CongestionType.allCases, id: \.self) {
                Text($0.rawValue).tag($0)
            }
        }
        .pickerStyle(.segmented)
    }

    private var throatPicker: some View {
        Picker("", selection: $viewModel.throatCondition) {
            ForEach(ThroatCondition.allCases, id: \.self) {
                Text($0.rawValue).tag($0)
            }
        }
        .pickerStyle(.segmented)
    }

    private func optionalBinding<T>(_ keyPath: ReferenceWritableKeyPath<MorningCheckInViewModel, T>) -> Binding<T?> {
        Binding<T?>(
            get: { .some(viewModel[keyPath: keyPath]) },
            set: { newValue in
                guard let newValue else { return }
                viewModel[keyPath: keyPath] = newValue
            }
        )
    }

    private func scoreSlider(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        accentColor: Color,
        lowLabel: String,
        highLabel: String
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(lowLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(value.wrappedValue)/\(range.upperBound)")
                    .font(.headline)
                Spacer()
                Text(highLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(accentColor)
        }
    }
}

#Preview { MorningCheckInView(sessionId: "preview-session", sessionDate: "2025-01-01") }
