//
//  PreSleepLogView.swift
//  DoseTap
//
//  Pre-Sleep Log: 3-card quick check-in before session
//  Designed to complete in <30 seconds with one hand
//

import SwiftUI

// MARK: - Pre-Sleep Log View (Main Container)
struct PreSleepLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentCard = 0
    @State private var answers: PreSleepLogAnswers
    @State private var showMoreDetails = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @ObservedObject private var sleepPlanStore = SleepPlanStore.shared
    
    let existingLog: StoredPreSleepLog?
    let onComplete: (PreSleepLogAnswers) throws -> Void
    let onSkip: () throws -> Void
    
    private let totalCards = 3
    
    init(
        existingLog: StoredPreSleepLog? = nil,
        onComplete: @escaping (PreSleepLogAnswers) throws -> Void,
        onSkip: @escaping () throws -> Void
    ) {
        self.existingLog = existingLog
        self.onComplete = onComplete
        self.onSkip = onSkip
        _answers = State(initialValue: existingLog?.answers ?? PreSleepLogAnswers())
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                ProgressBar(current: currentCard + 1, total: totalCards)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                if let plan = planSummary {
                    PlanInlineHint(plan: plan)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
                
                // Card content
                TabView(selection: $currentCard) {
                    // Card 1: Timing + Stress
                    Card1TimingStress(answers: $answers)
                        .tag(0)
                    
                    // Card 2: Body + Substances
                    Card2BodySubstances(answers: $answers)
                        .tag(1)
                    
                    // Card 3: Activity + Naps
                    Card3ActivityNaps(
                        answers: $answers,
                        showMoreDetails: $showMoreDetails
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentCard)
                
                // Navigation buttons
                HStack(spacing: 16) {
                    // Back button (hidden on first card)
                    if currentCard > 0 {
                        Button {
                            withAnimation { currentCard -= 1 }
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(.headline)
                            .foregroundColor(.secondary)
                        }
                    } else {
                        Spacer()
                    }
                    
                    Spacer()
                    
                    // Next/Done button
                    if currentCard < totalCards - 1 {
                        Button {
                            withAnimation { currentCard += 1 }
                        } label: {
                            HStack {
                                Text("Next")
                                Image(systemName: "chevron.right")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    } else {
                        Button {
                            saveAndComplete()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark")
                                Text(existingLog == nil ? "Done" : "Save")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle(existingLog == nil ? "Pre-Sleep Check" : "Edit Pre-Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if existingLog == nil {
                        Button("Skip for tonight") {
                            do {
                                try onSkip()
                                dismiss()
                            } catch {
                                saveErrorMessage = error.localizedDescription
                                showSaveError = true
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    } else {
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        loadLastAnswers()
                    } label: {
                        Text("Use last")
                            .font(.subheadline)
                    }
                }
            }
        }
        .alert("Pre-Sleep Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private func saveAndComplete() {
        do {
            try onComplete(answers)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
    
    private func loadLastAnswers() {
        // Load stable items from last log (not caffeine/alcohol)
        if let lastLog = sessionRepo.fetchMostRecentPreSleepLog(),
           let lastAnswers = lastLog.answers {
            // Only copy stable environment items
            answers.roomTemp = lastAnswers.roomTemp
            answers.noiseLevel = lastAnswers.noiseLevel
            answers.screensInBed = lastAnswers.screensInBed
        }
    }
    
    private var planSummary: (wakeBy: Date, inBed: Date, windDown: Date, expectedSleep: Double)? {
        let key = sessionRepo.preSleepDisplaySessionKey(for: Date())
        let plan = sleepPlanStore.plan(for: key, now: Date(), tz: TimeZone.current)
        return (plan.wakeBy, plan.recommendedInBed, plan.windDown, plan.expectedSleepMinutes)
    }
}

// MARK: - Progress Bar
struct ProgressBar: View {
    let current: Int
    let total: Int
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1...total, id: \.self) { index in
                    Capsule()
                        .fill(index <= current ? Color.blue : Color(.systemGray4))
                        .frame(height: 4)
                }
            }
            
            Text("Card \(current) of \(total)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct PlanInlineHint: View {
    let plan: (wakeBy: Date, inBed: Date, windDown: Date, expectedSleep: Double)
    
    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }
    
    var body: some View {
        HStack {
            Image(systemName: "bed.double.fill")
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Wake by \(formatter.string(from: plan.wakeBy))")
                    .font(.subheadline.bold())
                Text("In bed by \(formatter.string(from: plan.inBed)); wind down \(formatter.string(from: plan.windDown))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(Int(plan.expectedSleep)) min")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Card 1: Timing + Stress
struct Card1TimingStress: View {
    @Binding var answers: PreSleepLogAnswers
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Question 1: Intended sleep time
                QuestionSection(title: "When do you plan to sleep?", icon: "bed.double.fill") {
                    OptionGrid(
                        options: PreSleepLogAnswers.IntendedSleepTime.allCases,
                        selection: $answers.intendedSleepTime
                    )
                }
                
                // Question 2: Stress level
                QuestionSection(title: "Stress level right now?", icon: "brain.head.profile") {
                    StressSlider(value: $answers.stressLevel)
                }
                
                // Smart expander: Stress driver (only if stress >= 4)
                if let stress = answers.stressLevel, stress >= 4 {
                    QuestionSection(title: "Main stress driver?", icon: "exclamationmark.triangle") {
                        OptionGrid(
                            options: PreSleepLogAnswers.StressDriver.allCases,
                            selection: $answers.stressDriver
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Smart expander: Later reason (only if "later" selected)
                if answers.intendedSleepTime == .later {
                    QuestionSection(title: "Why later?", icon: "clock.badge.questionmark") {
                        OptionGrid(
                            options: PreSleepLogAnswers.LaterReason.allCases,
                            selection: $answers.laterReason
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: answers.stressLevel)
            .animation(.easeInOut(duration: 0.2), value: answers.intendedSleepTime)
        }
    }
}

// MARK: - Card 2: Body + Substances
struct Card2BodySubstances: View {
    @Binding var answers: PreSleepLogAnswers
    @State private var showMedicationPicker = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Question 3: Body pain
                QuestionSection(title: "Body pain right now?", icon: "figure.arms.open") {
                    OptionGrid(
                        options: PreSleepLogAnswers.PainLevel.allCases,
                        selection: $answers.bodyPain
                    )
                }
                
                // Smart expander: Pain details (only if pain != none)
                if let pain = answers.bodyPain, pain != .none {
                    Group {
                        QuestionSection(title: "Pain location(s)?", icon: "mappin.and.ellipse") {
                            MultiSelectGrid(
                                options: PreSleepLogAnswers.PainLocation.allCases,
                                selections: Binding(
                                    get: { answers.painLocations ?? [] },
                                    set: { answers.painLocations = $0.isEmpty ? nil : $0 }
                                )
                            )
                        }
                        
                        QuestionSection(title: "Pain type?", icon: "waveform.path") {
                            OptionGrid(
                                options: PreSleepLogAnswers.PainType.allCases,
                                selection: $answers.painType
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Question 4: Stimulants after 2pm
                QuestionSection(title: "Stimulants after 2pm?", icon: "cup.and.saucer.fill") {
                    OptionGrid(
                        options: PreSleepLogAnswers.Stimulants.allCases,
                        selection: $answers.stimulants
                    )
                }
                
                // Question 5: Alcohol today
                QuestionSection(title: "Alcohol today?", icon: "wineglass.fill") {
                    OptionGrid(
                        options: PreSleepLogAnswers.AlcoholLevel.allCases,
                        selection: $answers.alcohol
                    )
                }
                
                // Medication logging button
                QuestionSection(title: "Log medication (Adderall)?", icon: "pills.fill") {
                    Button {
                        showMedicationPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Log Medication")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .cornerRadius(10)
                    }
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: answers.bodyPain)
        }
        .sheet(isPresented: $showMedicationPicker) {
            MedicationPickerView()
        }
    }
}

// MARK: - Card 3: Activity + Naps + Optional More Details
struct Card3ActivityNaps: View {
    @Binding var answers: PreSleepLogAnswers
    @Binding var showMoreDetails: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Question 6: Exercise today
                QuestionSection(title: "Exercise today?", icon: "figure.run") {
                    OptionGrid(
                        options: PreSleepLogAnswers.ExerciseLevel.allCases,
                        selection: $answers.exercise
                    )
                }
                
                // Question 7: Nap today
                QuestionSection(title: "Nap today?", icon: "moon.zzz.fill") {
                    OptionGrid(
                        options: PreSleepLogAnswers.NapDuration.allCases,
                        selection: $answers.napToday
                    )
                }
                
                // Toggle for more details
                Divider()
                    .padding(.vertical, 8)
                
                Toggle(isOn: $showMoreDetails) {
                    Label("Add more details", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .tint(.blue)
                
                // Optional expanded details
                if showMoreDetails {
                    Group {
                        QuestionSection(title: "Late meal?", icon: "fork.knife") {
                            OptionGrid(
                                options: PreSleepLogAnswers.LateMeal.allCases,
                                selection: $answers.lateMeal
                            )
                        }
                        
                        QuestionSection(title: "Screens in bed?", icon: "iphone") {
                            OptionGrid(
                                options: PreSleepLogAnswers.ScreensInBed.allCases,
                                selection: $answers.screensInBed
                            )
                        }
                        
                        QuestionSection(title: "Room temperature?", icon: "thermometer.medium") {
                            OptionGrid(
                                options: PreSleepLogAnswers.RoomTemp.allCases,
                                selection: $answers.roomTemp
                            )
                        }
                        
                        QuestionSection(title: "Noise level?", icon: "speaker.wave.2") {
                            OptionGrid(
                                options: PreSleepLogAnswers.NoiseLevel.allCases,
                                selection: $answers.noiseLevel
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: showMoreDetails)
        }
    }
}

// MARK: - Reusable Components

struct QuestionSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            
            content
        }
    }
}

struct OptionGrid<T: RawRepresentable & CaseIterable & Hashable>: View where T.RawValue == String, T: DisplayTextProvider {
    let options: [T]
    @Binding var selection: T?
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = option
                    }
                } label: {
                    Text(option.displayText)
                        .font(.subheadline)
                        .fontWeight(selection == option ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selection == option ? Color.blue : Color(.systemGray5))
                        )
                        .foregroundColor(selection == option ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MultiSelectGrid<T: RawRepresentable & CaseIterable & Hashable>: View where T.RawValue == String, T: DisplayTextProvider {
    let options: [T]
    @Binding var selections: [T]
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if selections.contains(option) {
                            selections.removeAll { $0 == option }
                        } else {
                            selections.append(option)
                        }
                    }
                } label: {
                    Text(option.displayText)
                        .font(.subheadline)
                        .fontWeight(selections.contains(option) ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selections.contains(option) ? Color.blue : Color(.systemGray5))
                        )
                        .foregroundColor(selections.contains(option) ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StressSlider: View {
    @Binding var value: Int?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            value = level
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(level)")
                                .font(.title2.bold())
                            Text(stressLabel(level))
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(value == level ? stressColor(level) : Color(.systemGray5))
                        )
                        .foregroundColor(value == level ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func stressLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Low"
        case 2: return "Mild"
        case 3: return "Medium"
        case 4: return "High"
        case 5: return "Very High"
        default: return ""
        }
    }
    
    private func stressColor(_ level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return .mint
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .gray
        }
    }
}

// MARK: - Protocol for display text
protocol DisplayTextProvider {
    var displayText: String { get }
}

// Conform all enums
extension PreSleepLogAnswers.IntendedSleepTime: DisplayTextProvider {}
extension PreSleepLogAnswers.StressDriver: DisplayTextProvider {}
extension PreSleepLogAnswers.PainLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.PainLocation: DisplayTextProvider {}
extension PreSleepLogAnswers.PainType: DisplayTextProvider {}
extension PreSleepLogAnswers.Stimulants: DisplayTextProvider {}
extension PreSleepLogAnswers.AlcoholLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.ExerciseLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.NapDuration: DisplayTextProvider {}
extension PreSleepLogAnswers.LaterReason: DisplayTextProvider {}
extension PreSleepLogAnswers.LateMeal: DisplayTextProvider {}
extension PreSleepLogAnswers.ScreensInBed: DisplayTextProvider {}
extension PreSleepLogAnswers.RoomTemp: DisplayTextProvider {}
extension PreSleepLogAnswers.NoiseLevel: DisplayTextProvider {}

// MARK: - Preview
#Preview {
    PreSleepLogView(
        onComplete: { answers in
            print("Completed with answers: \(answers)")
        },
        onSkip: {
            print("Skipped")
        }
    )
}
