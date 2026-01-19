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
    
    private let totalCards = 4
    
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
                    // Card 1: Timing + Stress + Sleepiness
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
                    
                    // Card 4: Review before save
                    Card4Review(
                        answers: answers,
                        jumpToCard: { card in
                            withAnimation { currentCard = card }
                        }
                    )
                    .tag(3)
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
            
            // Save pain snapshot if user reported pain (new 0-10 scale)
            if let painLevel = answers.painLevel010, painLevel > 0 {
                let sessionId = sessionRepo.preSleepDisplaySessionKey(for: Date())
                let snapshot = PainSnapshot(
                    context: .preSleep,
                    overallLevel: painLevel,
                    locations: answers.painDetailedLocations ?? [],
                    primaryLocation: answers.painPrimaryLocation,
                    radiation: answers.painRadiation,
                    painWokeUser: false,  // N/A for pre-sleep
                    sessionId: sessionId
                )
                EventStorage.shared.savePainSnapshot(snapshot)
            }
            // Fallback: Legacy pain tracking (deprecated - backwards compatibility only)
            else if let legacyPain = answers.legacyBodyPain, legacyPain != .none {
                let sessionId = sessionRepo.preSleepDisplaySessionKey(for: Date())
                let snapshot = PainSnapshot(
                    context: .preSleep,
                    overallLevel: legacyPain.numericEquivalent,
                    locations: [],  // Legacy doesn't have detailed locations
                    sessionId: sessionId
                )
                EventStorage.shared.savePainSnapshot(snapshot)
            }
            
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
            answers.sleepAids = lastAnswers.sleepAids
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
    var onTap: (() -> Void)? = nil
    
    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }
    
    /// Format minutes as "Xh Ym" for human readability
    private var sleepDurationFormatted: String {
        let totalMinutes = Int(plan.expectedSleep)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
    
    var body: some View {
        Button {
            onTap?()
        } label: {
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
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sleepDurationFormatted)
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)
                    Text("planned sleep")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card 1: Timing + Stress + Sleepiness
struct Card1TimingStress: View {
    @Binding var answers: PreSleepLogAnswers
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Question 1: Intended sleep time (now with better options)
                QuestionSection(title: "When do you plan to sleep?", icon: "bed.double.fill") {
                    OptionGrid(
                        options: PreSleepLogAnswers.IntendedSleepTime.allCases,
                        selection: $answers.intendedSleepTime
                    )
                }
                
                // Question 2: Sleepiness right now (for narcolepsy tracking)
                QuestionSection(title: "Sleepiness right now?", icon: "eye.slash") {
                    SleepinessSlider(value: $answers.sleepinessLevel)
                }
                
                // Question 3: Stress level
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
                
                // Question 4: Alarm plan
                QuestionSection(title: "Alarm set for tomorrow?", icon: "alarm") {
                    AlarmPlanView(alarmSet: $answers.alarmSet, alarmTime: $answers.alarmTime)
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: answers.stressLevel)
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
                // Pain tracking (0-10 scale with detailed locations)
                VStack(spacing: 20) {
                    // Pain level picker
                    PainLevelPicker(
                        selectedLevel: $answers.painLevel010,
                        context: "right now"
                    )
                    
                    // Show location details if pain > 0
                    if let level = answers.painLevel010, level > 0 {
                        Group {
                            PainLocationPicker(
                                selectedLocations: Binding(
                                    get: { answers.painDetailedLocations ?? [] },
                                    set: { answers.painDetailedLocations = $0.isEmpty ? nil : $0 }
                                ),
                                primaryLocation: $answers.painPrimaryLocation
                            )
                            
                            // Radiation (if back/neck/leg pain selected)
                            if shouldShowRadiation {
                                RadiationPicker(radiation: $answers.painRadiation)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                
                Divider()
                
                // Question 2: Stimulants - Multi-select
                QuestionSection(title: "Caffeine/stimulants today?", icon: "cup.and.saucer.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select all that apply")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        MultiSelectGridWithNone(
                            options: PreSleepLogAnswers.Stimulants.multiSelectOptions,
                            selections: Binding(
                                get: { answers.stimulantsConsumed ?? [] },
                                set: { answers.stimulantsConsumed = $0.isEmpty ? nil : $0 }
                            ),
                            noneLabel: "None"
                        )
                    }
                }
                
                // Smart expander: Last caffeine time (only if stimulants selected)
                if let stims = answers.stimulantsConsumed, !stims.isEmpty {
                    QuestionSection(title: "Last caffeine?", icon: "clock") {
                        TimeBucketPicker(selection: $answers.lastCaffeineTime)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Question 3: Alcohol today
                QuestionSection(title: "Alcohol today?", icon: "wineglass.fill") {
                    OptionGrid(
                        options: PreSleepLogAnswers.AlcoholLevel.allCases,
                        selection: $answers.alcohol
                    )
                }
                
                // Smart expander: Last alcohol time (only if alcohol > none)
                if let alc = answers.alcohol, alc != .none {
                    QuestionSection(title: "Last drink?", icon: "clock") {
                        TimeBucketPicker(selection: $answers.lastAlcoholTime)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Medication logging button
                QuestionSection(title: "Log medication?", icon: "pills.fill") {
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
            .animation(.easeInOut(duration: 0.2), value: answers.painLevel010)
            .animation(.easeInOut(duration: 0.2), value: answers.stimulantsConsumed)
            .animation(.easeInOut(duration: 0.2), value: answers.alcohol)
        }
        .sheet(isPresented: $showMedicationPicker) {
            MedicationPickerView()
        }
    }
    
    /// Show radiation picker if any back/neck/leg regions are selected
    private var shouldShowRadiation: Bool {
        guard let locations = answers.painDetailedLocations else { return false }
        return locations.contains { $0.region.supportsRadiation }
    }
}

// MARK: - Card 3: Activity + Naps + Optional More Details
struct Card3ActivityNaps: View {
    @Binding var answers: PreSleepLogAnswers
    @Binding var showMoreDetails: Bool
    @ObservedObject private var sessionRepo = SessionRepository.shared
    
    /// Fetch today's nap events from storage
    private var napsLoggedToday: (count: Int, totalMinutes: Int) {
        let napEvents = sessionRepo.fetchTonightSleepEvents().filter { $0.eventType.contains("nap") }
        // TODO: Calculate actual duration from nap_start/nap_end pairs
        return (napEvents.count, 0)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Question 1: Exercise today
                QuestionSection(title: "Exercise today?", icon: "figure.run") {
                    OptionGrid(
                        options: PreSleepLogAnswers.ExerciseLevel.allCases,
                        selection: $answers.exercise
                    )
                }
                
                // Question 2: Nap today - Now integrated with nap events
                QuestionSection(title: "Nap today?", icon: "moon.zzz.fill") {
                    NapSummaryView(
                        napSelection: $answers.napToday,
                        napsLogged: napsLoggedToday
                    )
                }
                
                // Toggle for advanced details
                Divider()
                    .padding(.vertical, 8)
                
                Toggle(isOn: $showMoreDetails) {
                    Label("Advanced details", systemImage: "slider.horizontal.3")
                        .font(.subheadline)
                }
                .tint(.blue)
                
                // Optional expanded details (Advanced mode)
                if showMoreDetails {
                    Group {
                        QuestionSection(title: "Late meal?", icon: "fork.knife") {
                            VStack(spacing: 8) {
                                OptionGrid(
                                    options: PreSleepLogAnswers.LateMeal.allCases,
                                    selection: $answers.lateMeal
                                )
                                
                                // Show time picker if meal was eaten
                                if let meal = answers.lateMeal, meal != .none {
                                    TimeBucketPicker(selection: $answers.lastMealTime)
                                }
                            }
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
                        
                        // Sleep aids - Multi-select
                        QuestionSection(title: "Sleep aids?", icon: "moon.stars") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Select all that apply")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                MultiSelectGrid(
                                    options: PreSleepLogAnswers.SleepAid.allCases,
                                    selections: Binding(
                                        get: { answers.sleepAidsUsed ?? [] },
                                        set: { answers.sleepAidsUsed = $0.isEmpty ? nil : $0 }
                                    )
                                )
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: showMoreDetails)
            .animation(.easeInOut(duration: 0.2), value: answers.lateMeal)
        }
    }
}

// MARK: - Card 4: Review Before Save
struct Card4Review: View {
    let answers: PreSleepLogAnswers
    let jumpToCard: (Int) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "checkmark.circle")
                        .font(.title)
                        .foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text("Review")
                            .font(.headline)
                        Text("Tap any section to edit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 8)
                
                // Section 1: Timing & Sleep State
                ReviewSection(title: "Sleep Plan", icon: "bed.double.fill", cardIndex: 0, jumpToCard: jumpToCard) {
                    ReviewRow(label: "Plan to sleep", value: answers.intendedSleepTime?.displayText ?? "Not set")
                    if let sleepiness = answers.sleepinessLevel {
                        ReviewRow(label: "Sleepiness", value: sleepinessLabel(sleepiness))
                    }
                    if let stress = answers.stressLevel {
                        ReviewRow(label: "Stress", value: stressLabel(stress))
                        if let driver = answers.stressDriver {
                            ReviewRow(label: "Stress driver", value: driver.displayText)
                        }
                    }
                    if let alarmSet = answers.alarmSet {
                        if alarmSet, let time = answers.alarmTime {
                            ReviewRow(label: "Alarm", value: time.formatted(date: .omitted, time: .shortened))
                        } else {
                            ReviewRow(label: "Alarm", value: "Not set")
                        }
                    }
                }
                
                // Section 2: Body & Substances
                ReviewSection(title: "Body & Substances", icon: "figure.arms.open", cardIndex: 1, jumpToCard: jumpToCard) {
                    // New pain tracking (0-10 scale)
                    if let painLevel = answers.painLevel010, painLevel > 0 {
                        let painSummary: String = {
                            var summary = "\(painLevel)/10"
                            if let primary = answers.painPrimaryLocation {
                                summary += " – \(primary.compactText)"
                            } else if let first = answers.painDetailedLocations?.first {
                                if let count = answers.painDetailedLocations?.count, count > 1 {
                                    summary += " – \(count) areas"
                                } else {
                                    summary += " – \(first.compactText)"
                                }
                            }
                            if let rad = answers.painRadiation, rad != .none {
                                summary += ", radiates \(rad.displayText.lowercased())"
                            }
                            return summary
                        }()
                        ReviewRow(label: "Pain", value: painSummary)
                    }
                    // Fallback: Legacy pain tracking (backwards compatibility only)
                    else if let pain = answers.legacyBodyPain, pain != .none {
                        let painSummary: String = {
                            var summary = pain.displayText
                            if let locations = answers.legacyPainLocations, !locations.isEmpty {
                                summary += " (\(locations.map { $0.displayText }.joined(separator: ", ")))"
                            }
                            return summary
                        }()
                        ReviewRow(label: "Pain", value: painSummary)
                    } else {
                        ReviewRow(label: "Pain", value: "None")
                    }
                    
                    if let stims = answers.stimulantsConsumed, !stims.isEmpty {
                        let stimSummary: String = {
                            var summary = stims.map { $0.displayText }.joined(separator: ", ")
                            if let time = answers.lastCaffeineTime {
                                summary += " @ \(time.displayText)"
                            }
                            return summary
                        }()
                        ReviewRow(label: "Caffeine", value: stimSummary)
                    } else {
                        ReviewRow(label: "Caffeine", value: "None")
                    }
                    
                    if let alc = answers.alcohol, alc != .none {
                        let alcSummary: String = {
                            var summary = alc.displayText
                            if let time = answers.lastAlcoholTime {
                                summary += " @ \(time.displayText)"
                            }
                            return summary
                        }()
                        ReviewRow(label: "Alcohol", value: alcSummary)
                    } else {
                        ReviewRow(label: "Alcohol", value: "None")
                    }
                }
                
                // Section 3: Activity & Environment
                ReviewSection(title: "Activity", icon: "figure.run", cardIndex: 2, jumpToCard: jumpToCard) {
                    ReviewRow(label: "Exercise", value: answers.exercise?.displayText ?? "Not set")
                    ReviewRow(label: "Nap", value: answers.napToday?.displayText ?? "Not set")
                    
                    // Advanced details if set
                    if let meal = answers.lateMeal, meal != .none {
                        ReviewRow(label: "Late meal", value: meal.displayText)
                    }
                    if let screens = answers.screensInBed, screens != .none {
                        ReviewRow(label: "Screens", value: screens.displayText)
                    }
                    if let aids = answers.sleepAidsUsed, !aids.isEmpty {
                        ReviewRow(label: "Sleep aids", value: aids.map { $0.displayText }.joined(separator: ", "))
                    }
                }
            }
            .padding()
        }
    }
    
    private func sleepinessLabel(_ level: Int) -> String {
        switch level {
        case 1: return "1 - Alert"
        case 2: return "2 - Slight"
        case 3: return "3 - Moderate"
        case 4: return "4 - Drowsy"
        case 5: return "5 - Very sleepy"
        default: return "\(level)"
        }
    }
    
    private func stressLabel(_ level: Int) -> String {
        switch level {
        case 1: return "1 - Low"
        case 2: return "2 - Mild"
        case 3: return "3 - Medium"
        case 4: return "4 - High"
        case 5: return "5 - Very high"
        default: return "\(level)"
        }
    }
}

// MARK: - Review Section
struct ReviewSection<Content: View>: View {
    let title: String
    let icon: String
    let cardIndex: Int
    let jumpToCard: (Int) -> Void
    @ViewBuilder let content: Content
    
    var body: some View {
        Button {
            jumpToCard(cardIndex)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                content
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Review Row
struct ReviewRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
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

// MARK: - Sleepiness Slider (for narcolepsy tracking)
struct SleepinessSlider: View {
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
                            Text(sleepinessLabel(level))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(value == level ? sleepinessColor(level) : Color(.systemGray5))
                        )
                        .foregroundColor(value == level ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func sleepinessLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Alert"
        case 2: return "Slight"
        case 3: return "Moderate"
        case 4: return "Drowsy"
        case 5: return "Very"
        default: return ""
        }
    }
    
    private func sleepinessColor(_ level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return .mint
        case 3: return .yellow
        case 4: return .orange
        case 5: return .purple
        default: return .gray
        }
    }
}

// MARK: - Alarm Plan View
struct AlarmPlanView: View {
    @Binding var alarmSet: Bool?
    @Binding var alarmTime: Date?
    
    var body: some View {
        VStack(spacing: 12) {
            // Yes/No toggle
            HStack(spacing: 12) {
                Button {
                    withAnimation { alarmSet = false; alarmTime = nil }
                } label: {
                    HStack {
                        Image(systemName: alarmSet == false ? "checkmark.circle.fill" : "circle")
                        Text("No")
                    }
                    .font(.subheadline)
                    .fontWeight(alarmSet == false ? .semibold : .regular)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(alarmSet == false ? Color.blue : Color(.systemGray5))
                    )
                    .foregroundColor(alarmSet == false ? .white : .primary)
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation { 
                        alarmSet = true
                        // Default to 7 AM if not set
                        if alarmTime == nil {
                            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                            components.hour = 7
                            components.minute = 0
                            alarmTime = Calendar.current.date(from: components)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: alarmSet == true ? "checkmark.circle.fill" : "circle")
                        Text("Yes")
                    }
                    .font(.subheadline)
                    .fontWeight(alarmSet == true ? .semibold : .regular)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(alarmSet == true ? Color.blue : Color(.systemGray5))
                    )
                    .foregroundColor(alarmSet == true ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            
            // Time picker (only if alarm set)
            if alarmSet == true {
                DatePicker(
                    "Alarm time",
                    selection: Binding(
                        get: { alarmTime ?? Date() },
                        set: { alarmTime = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 100)
                .clipped()
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
}

// MARK: - Time Bucket Picker (for caffeine/alcohol/meal timing)
struct TimeBucketPicker: View {
    @Binding var selection: PreSleepLogAnswers.StimulantTime?
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(PreSleepLogAnswers.StimulantTime.allCases, id: \.self) { time in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = time
                    }
                } label: {
                    Text(time.displayText)
                        .font(.caption)
                        .fontWeight(selection == time ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selection == time ? Color.blue : Color(.systemGray5))
                        )
                        .foregroundColor(selection == time ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Multi-Select Grid with None Option
struct MultiSelectGridWithNone<T: RawRepresentable & Hashable>: View where T.RawValue == String, T: DisplayTextProvider {
    let options: [T]
    @Binding var selections: [T]
    let noneLabel: String
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    private var isNoneSelected: Bool {
        selections.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // None button
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selections = []
                }
            } label: {
                Text(noneLabel)
                    .font(.subheadline)
                    .fontWeight(isNoneSelected ? .semibold : .regular)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isNoneSelected ? Color.blue : Color(.systemGray5))
                    )
                    .foregroundColor(isNoneSelected ? .white : .primary)
            }
            .buttonStyle(.plain)
            
            // Options grid
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
}

// MARK: - Nap Summary View (linked to actual nap events)
struct NapSummaryView: View {
    @Binding var napSelection: PreSleepLogAnswers.NapDuration?
    let napsLogged: (count: Int, totalMinutes: Int)
    
    var body: some View {
        VStack(spacing: 12) {
            // Show logged naps if any
            if napsLogged.count > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Naps logged today: \(napsLogged.count)")
                        .font(.subheadline)
                    if napsLogged.totalMinutes > 0 {
                        Text("(\(napsLogged.totalMinutes)m total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Edit") {
                        // TODO: Navigate to nap events
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
            }
            
            // Manual entry option (if no naps logged or want to override)
            if napsLogged.count == 0 {
                OptionGrid(
                    options: PreSleepLogAnswers.NapDuration.allCases,
                    selection: $napSelection
                )
            } else {
                // Compact override option
                HStack {
                    Text("Or estimate:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                OptionGrid(
                    options: PreSleepLogAnswers.NapDuration.allCases,
                    selection: $napSelection
                )
            }
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
// Legacy pain enums (kept for backward compatibility display - deprecation warnings expected)
extension PreSleepLogAnswers.PainLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.PainLocation: DisplayTextProvider {}
extension PreSleepLogAnswers.PainType: DisplayTextProvider {}
extension PreSleepLogAnswers.Stimulants: DisplayTextProvider {}
extension PreSleepLogAnswers.StimulantTime: DisplayTextProvider {}
extension PreSleepLogAnswers.AlcoholLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.ExerciseLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.NapDuration: DisplayTextProvider {}
extension PreSleepLogAnswers.LaterReason: DisplayTextProvider {}
extension PreSleepLogAnswers.LateMeal: DisplayTextProvider {}
extension PreSleepLogAnswers.ScreensInBed: DisplayTextProvider {}
extension PreSleepLogAnswers.RoomTemp: DisplayTextProvider {}
extension PreSleepLogAnswers.NoiseLevel: DisplayTextProvider {}
extension PreSleepLogAnswers.SleepAid: DisplayTextProvider {}

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

// MARK: - Pain Tracking UI Components (Embedded for reliable compilation)

/// Pain Level Picker (0-10 Scale)
struct PainLevelPicker: View {
    @Binding var selectedLevel: Int?
    @State private var showFullScale = false
    let context: String
    
    private let quickLevels = [0, 2, 5, 8, 10]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Pain level \(context)?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 8) {
                ForEach(quickLevels, id: \.self) { level in
                    painButton(level: level, isQuick: true)
                }
            }
            
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showFullScale.toggle()
                }
            } label: {
                HStack {
                    Text(showFullScale ? "Hide exact picker" : "Pick exact number")
                        .font(.subheadline)
                    Image(systemName: showFullScale ? "chevron.up" : "chevron.down")
                }
                .foregroundColor(.secondary)
            }
            
            if showFullScale {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(0...5, id: \.self) { level in
                            painButton(level: level, isQuick: false)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(6...10, id: \.self) { level in
                            painButton(level: level, isQuick: false)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if let level = selectedLevel {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(painColorForLevel(level))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(level)/10 – \(painAnchorLabel(level))")
                            .font(.subheadline.bold())
                        if !painAnchorDescription(level).isEmpty {
                            Text(painAnchorDescription(level))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(painColorForLevel(level).opacity(0.1))
                .cornerRadius(10)
            }
        }
    }
    
    private func painButton(level: Int, isQuick: Bool) -> some View {
        let isSelected = selectedLevel == level
        let size: CGFloat = isQuick ? 60 : 44
        
        return Button {
            withAnimation(.spring(response: 0.2)) {
                selectedLevel = level
            }
        } label: {
            Text("\(level)")
                .font(isQuick ? .title2.bold() : .body.bold())
                .frame(width: size, height: size)
                .background(isSelected ? painColorForLevel(level) : Color(.tertiarySystemGroupedBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? painColorForLevel(level) : Color.gray.opacity(0.3), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func painColorForLevel(_ level: Int) -> Color {
        switch level {
        case 0: return .green
        case 1...3: return .yellow
        case 4...6: return .orange
        case 7...8: return .red
        default: return .purple
        }
    }
    
    private func painAnchorLabel(_ level: Int) -> String {
        switch level {
        case 0: return "No pain"
        case 1...3: return "Mild"
        case 4...6: return "Moderate"
        case 7...8: return "Severe"
        default: return "Very severe"
        }
    }
    
    private func painAnchorDescription(_ level: Int) -> String {
        switch level {
        case 0: return ""
        case 1...3: return "Noticeable but easy to ignore"
        case 4...6: return "Hard to ignore, interferes with focus"
        case 7...8: return "Limits activity, hard to sleep"
        default: return "Unbearable, cannot function"
        }
    }
}

/// Pain Location Picker (Granular Regions + Laterality)
struct PainLocationPicker: View {
    @Binding var selectedLocations: [PainLocationDetail]
    @Binding var primaryLocation: PainLocationDetail?
    @State private var showingSideSelector: PainRegion?
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Where does it hurt?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Tap an area to add it")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 20) {
                painRegionCategory(title: "Head & Neck", regions: [.head, .jaw, .face, .neck])
                painRegionCategory(title: "Shoulder & Arms", regions: [.shoulder, .upperArm, .elbow, .forearm, .wrist, .hand])
                painRegionCategory(title: "Torso & Back", regions: [.upperBack, .midBack, .lowBack, .chest, .abdomen])
                painRegionCategory(title: "Hips & Legs", regions: [.hip, .thigh, .knee, .shin, .ankle, .foot])
                painRegionCategory(title: "General", regions: [.jointsWidespread, .muscleWidespread, .other])
            }
            
            if !selectedLocations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected areas:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    ForEach(selectedLocations, id: \.self) { location in
                        HStack {
                            Text(location.compactText)
                                .font(.subheadline)
                            Spacer()
                            if location == primaryLocation {
                                Text("Main")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(6)
                            }
                            Button {
                                selectedLocations.removeAll { $0 == location }
                                if primaryLocation == location {
                                    primaryLocation = selectedLocations.first
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                if selectedLocations.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Which is the main pain area?")
                            .font(.subheadline.bold())
                        
                        ForEach(selectedLocations, id: \.self) { location in
                            Button {
                                withAnimation(.spring(response: 0.2)) {
                                    primaryLocation = location
                                }
                            } label: {
                                HStack {
                                    Image(systemName: primaryLocation == location ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(primaryLocation == location ? .red : .gray)
                                    Text(location.displayText)
                                    Spacer()
                                }
                                .padding()
                                .background(primaryLocation == location ? Color.red.opacity(0.1) : Color(.tertiarySystemGroupedBackground))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }
        }
        .sheet(item: $showingSideSelector) { region in
            SideSelectorSheet(region: region) { side in
                let newLocation = PainLocationDetail(region: region, side: side)
                selectedLocations.append(newLocation)
                if selectedLocations.count == 1 {
                    primaryLocation = newLocation
                }
            }
            .presentationDetents([.height(280)])
        }
    }
    
    private func painRegionCategory(title: String, regions: [PainRegion]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            PainFlowLayout(spacing: 8) {
                ForEach(regions, id: \.self) { region in
                    painRegionChip(region)
                }
            }
        }
    }
    
    private func painRegionChip(_ region: PainRegion) -> some View {
        let isSelected = selectedLocations.contains { $0.region == region }
        
        return Button {
            if isSelected {
                selectedLocations.removeAll { $0.region == region }
                if primaryLocation?.region == region {
                    primaryLocation = nil
                }
            } else {
                if region.supportsLaterality {
                    showingSideSelector = region
                } else {
                    let newLocation = PainLocationDetail(region: region, side: .center)
                    selectedLocations.append(newLocation)
                    if selectedLocations.count == 1 {
                        primaryLocation = newLocation
                    }
                }
            }
        } label: {
            Text(region.displayText)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.red.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                .foregroundColor(isSelected ? .red : .primary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Side Selector Sheet
struct SideSelectorSheet: View {
    let region: PainRegion
    let onSelect: (PainSide) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Which side?")
                .font(.title3.bold())
            
            Text(region.displayText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                ForEach(PainSide.allCases, id: \.self) { side in
                    Button {
                        onSelect(side)
                        dismiss()
                    } label: {
                        VStack(spacing: 8) {
                            Text(side.emoji)
                                .font(.largeTitle)
                            Text(side.displayText)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

/// Radiation Picker (for back/neck/leg pain)
struct RadiationPicker: View {
    @Binding var radiation: PainRadiation?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Does the pain radiate?")
                .font(.headline)
            
            Text("Optional – for back, neck, or leg pain")
                .font(.caption)
                .foregroundColor(.secondary)
            
            PainFlowLayout(spacing: 8) {
                ForEach(PainRadiation.allCases, id: \.self) { rad in
                    radiationChip(rad)
                }
            }
        }
    }
    
    private func radiationChip(_ rad: PainRadiation) -> some View {
        let isSelected = radiation == rad
        
        return Button {
            withAnimation(.spring(response: 0.2)) {
                radiation = isSelected ? nil : rad
            }
        } label: {
            Text(rad.displayText)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.orange.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                .foregroundColor(isSelected ? .orange : .primary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Flow Layout for Pain UI
struct PainFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowResult(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    private func flowResult(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
        
        return (CGSize(width: maxWidth, height: y + lineHeight), positions)
    }
}