//
//  PreSleepLogView.swift
//  DoseTap
//
//  Pre-Sleep Log: 3-card quick check-in before session
//  Designed to complete in <30 seconds with one hand
//

import Foundation
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
        if let pain = answers.bodyPain, pain != .none, (answers.painEntries ?? []).isEmpty {
            saveErrorMessage = "Add at least one pain entry with area, side, intensity, and sensation."
            showSaveError = true
            return
        }
        if (answers.stimulants ?? PreSleepLogAnswers.Stimulants.none) != .none &&
            (answers.caffeineLastIntakeAt == nil || answers.caffeineLastAmountMg == nil || answers.caffeineDailyTotalMg == nil) {
            saveErrorMessage = "Add caffeine last time, last amount, and daily total."
            showSaveError = true
            return
        }
        if (answers.stimulants ?? PreSleepLogAnswers.Stimulants.none) != .none {
            let last = answers.caffeineLastAmountMg ?? 0
            let total = answers.caffeineDailyTotalMg ?? 0
            if last <= 0 {
                saveErrorMessage = "Caffeine last amount must be greater than 0 mg."
                showSaveError = true
                return
            }
            if total < last {
                saveErrorMessage = "Caffeine daily total must be at least the last amount."
                showSaveError = true
                return
            }
        }
        if (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none &&
            (answers.alcoholLastDrinkAt == nil || answers.alcoholLastAmountDrinks == nil || answers.alcoholDailyTotalDrinks == nil) {
            saveErrorMessage = "Add alcohol last time, last amount, and daily total."
            showSaveError = true
            return
        }
        if (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none {
            let last = answers.alcoholLastAmountDrinks ?? 0
            let total = answers.alcoholDailyTotalDrinks ?? 0
            if last <= 0 {
                saveErrorMessage = "Alcohol last amount must be greater than 0 drinks."
                showSaveError = true
                return
            }
            if total < last {
                saveErrorMessage = "Alcohol daily total must be at least the last amount."
                showSaveError = true
                return
            }
        }
        if (answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none) != .none &&
            (answers.exerciseType == nil || answers.exerciseLastAt == nil || answers.exerciseDurationMinutes == nil) {
            saveErrorMessage = "Add exercise type, last time, and duration."
            showSaveError = true
            return
        }
        if (answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none) != .none && (answers.exerciseDurationMinutes ?? 0) < 5 {
            saveErrorMessage = "Exercise duration must be at least 5 minutes."
            showSaveError = true
            return
        }
        if (answers.napToday ?? PreSleepLogAnswers.NapDuration.none) != .none &&
            (answers.napCount == nil || answers.napTotalMinutes == nil || answers.napLastEndAt == nil) {
            saveErrorMessage = "Add nap count, total minutes, and last nap end time."
            showSaveError = true
            return
        }
        if (answers.napToday ?? PreSleepLogAnswers.NapDuration.none) != .none && ((answers.napCount ?? 0) < 1 || (answers.napTotalMinutes ?? 0) < 5) {
            saveErrorMessage = "Nap count must be at least 1 and total nap time at least 5 minutes."
            showSaveError = true
            return
        }
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
    @State private var showPainEntryEditor = false
    @State private var editingPainEntry: PreSleepLogAnswers.PainEntry?

    private var painEntries: [PreSleepLogAnswers.PainEntry] {
        (answers.painEntries ?? []).sorted { $0.entryKey < $1.entryKey }
    }
    
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
                    QuestionSection(title: "Pain detail by area + side", icon: "mappin.and.ellipse") {
                        VStack(spacing: 10) {
                            if painEntries.isEmpty {
                                Text("Add one entry per area/side. Example: Mid Back (Both) 2/10, Lower Back (Right) 9/10.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 2)
                            } else {
                                ForEach(painEntries, id: \.entryKey) { entry in
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
                                            removePainEntry(entry)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                    .background(Color(.secondarySystemGroupedBackground))
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
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Question 4: Caffeine / stimulants
                QuestionSection(title: "Caffeine / stimulants today?", icon: "cup.and.saucer.fill") {
                    VStack(spacing: 10) {
                        OptionGrid(
                            options: PreSleepLogAnswers.Stimulants.allCases,
                            selection: $answers.stimulants
                        )
                        if (answers.stimulants ?? PreSleepLogAnswers.Stimulants.none) != .none {
                            SubstanceDetailCard(title: "Caffeine Details") {
                                SubstanceTimePickerRow(
                                    label: "Last intake time",
                                    value: Binding(
                                        get: { answers.caffeineLastIntakeAt ?? Date() },
                                        set: { answers.caffeineLastIntakeAt = $0 }
                                    )
                                )
                                SubstanceIntStepperRow(
                                    label: "Last amount",
                                    unit: "mg",
                                    range: 5...600,
                                    step: 5,
                                    value: Binding(
                                        get: { answers.caffeineLastAmountMg ?? defaultCaffeineAmountMg() },
                                        set: { answers.caffeineLastAmountMg = $0 }
                                    )
                                )
                                SubstanceIntStepperRow(
                                    label: "Daily total",
                                    unit: "mg",
                                    range: max(answers.caffeineLastAmountMg ?? defaultCaffeineAmountMg(), 5)...1200,
                                    step: 10,
                                    value: Binding(
                                        get: { answers.caffeineDailyTotalMg ?? max(answers.caffeineLastAmountMg ?? defaultCaffeineAmountMg(), defaultCaffeineAmountMg()) },
                                        set: { answers.caffeineDailyTotalMg = $0 }
                                    )
                                )
                            }
                        }
                    }
                }
                
                // Question 5: Alcohol
                QuestionSection(title: "Alcohol today?", icon: "wineglass.fill") {
                    VStack(spacing: 10) {
                        OptionGrid(
                            options: PreSleepLogAnswers.AlcoholLevel.allCases,
                            selection: $answers.alcohol
                        )
                        if (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none {
                            SubstanceDetailCard(title: "Alcohol Details") {
                                SubstanceTimePickerRow(
                                    label: "Last drink time",
                                    value: Binding(
                                        get: { answers.alcoholLastDrinkAt ?? Date() },
                                        set: { answers.alcoholLastDrinkAt = $0 }
                                    )
                                )
                                SubstanceDoubleStepperRow(
                                    label: "Last amount",
                                    unit: "drinks",
                                    range: 0.5...8,
                                    step: 0.5,
                                    value: Binding(
                                        get: { answers.alcoholLastAmountDrinks ?? defaultAlcoholAmountDrinks() },
                                        set: { answers.alcoholLastAmountDrinks = $0 }
                                    )
                                )
                                SubstanceDoubleStepperRow(
                                    label: "Daily total",
                                    unit: "drinks",
                                    range: max(answers.alcoholLastAmountDrinks ?? defaultAlcoholAmountDrinks(), 0.5)...20,
                                    step: 0.5,
                                    value: Binding(
                                        get: { answers.alcoholDailyTotalDrinks ?? max(answers.alcoholLastAmountDrinks ?? defaultAlcoholAmountDrinks(), defaultAlcoholAmountDrinks()) },
                                        set: { answers.alcoholDailyTotalDrinks = $0 }
                                    )
                                )
                            }
                        }
                    }
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
        .sheet(isPresented: $showPainEntryEditor) {
            GranularPainEntryEditorView(initialEntry: editingPainEntry) { savedEntry in
                upsertPainEntry(savedEntry)
            }
        }
        .onChange(of: answers.bodyPain) { newValue in
            guard newValue == .some(PreSleepLogAnswers.PainLevel.none) else { return }
            answers.painEntries = nil
            answers.painLocations = nil
            answers.painType = nil
        }
        .onChange(of: answers.stimulants) { newValue in
            if (newValue ?? PreSleepLogAnswers.Stimulants.none) == PreSleepLogAnswers.Stimulants.none {
                answers.caffeineLastIntakeAt = nil
                answers.caffeineLastAmountMg = nil
                answers.caffeineDailyTotalMg = nil
            } else {
                if answers.caffeineLastIntakeAt == nil { answers.caffeineLastIntakeAt = Date() }
                if answers.caffeineLastAmountMg == nil { answers.caffeineLastAmountMg = defaultCaffeineAmountMg() }
                if answers.caffeineDailyTotalMg == nil { answers.caffeineDailyTotalMg = max(defaultCaffeineAmountMg(), answers.caffeineLastAmountMg ?? 0) }
                normalizeCaffeineDetails()
            }
        }
        .onChange(of: answers.caffeineLastAmountMg) { _ in
            normalizeCaffeineDetails()
        }
        .onChange(of: answers.caffeineDailyTotalMg) { _ in
            normalizeCaffeineDetails()
        }
        .onChange(of: answers.alcohol) { newValue in
            if (newValue ?? PreSleepLogAnswers.AlcoholLevel.none) == PreSleepLogAnswers.AlcoholLevel.none {
                answers.alcoholLastDrinkAt = nil
                answers.alcoholLastAmountDrinks = nil
                answers.alcoholDailyTotalDrinks = nil
            } else {
                if answers.alcoholLastDrinkAt == nil { answers.alcoholLastDrinkAt = Date() }
                if answers.alcoholLastAmountDrinks == nil { answers.alcoholLastAmountDrinks = defaultAlcoholAmountDrinks() }
                if answers.alcoholDailyTotalDrinks == nil { answers.alcoholDailyTotalDrinks = max(defaultAlcoholAmountDrinks(), answers.alcoholLastAmountDrinks ?? 0) }
                normalizeAlcoholDetails()
            }
        }
        .onChange(of: answers.alcoholLastAmountDrinks) { _ in
            normalizeAlcoholDetails()
        }
        .onChange(of: answers.alcoholDailyTotalDrinks) { _ in
            normalizeAlcoholDetails()
        }
        .onAppear {
            bootstrapLegacyPainEntriesIfNeeded()
            bootstrapSubstanceDetailsIfNeeded()
        }
    }

    private func upsertPainEntry(_ entry: PreSleepLogAnswers.PainEntry) {
        var updated = answers.painEntries ?? []
        if let idx = updated.firstIndex(where: { $0.entryKey == entry.entryKey }) {
            updated[idx] = entry
        } else {
            updated.append(entry)
        }
        applyPainEntries(updated)
    }

    private func removePainEntry(_ entry: PreSleepLogAnswers.PainEntry) {
        let updated = (answers.painEntries ?? []).filter { $0.entryKey != entry.entryKey }
        applyPainEntries(updated)
    }

    private func applyPainEntries(_ entries: [PreSleepLogAnswers.PainEntry]) {
        let normalized = entries.sorted { $0.entryKey < $1.entryKey }
        answers.painEntries = normalized.isEmpty ? nil : normalized

        if normalized.isEmpty {
            answers.painLocations = nil
            answers.painType = nil
            answers.bodyPain = PreSleepLogAnswers.PainLevel.none
            return
        }

        answers.painLocations = Array(Set(normalized.map { legacyLocation(for: $0.area) })).sorted { $0.rawValue < $1.rawValue }
        if let firstSensation = normalized.first?.sensations.first {
            answers.painType = legacyPainType(for: firstSensation)
        }
        let maxIntensity = normalized.map(\.intensity).max() ?? 0
        answers.bodyPain = painLevel(for: maxIntensity)
    }

    private func bootstrapLegacyPainEntriesIfNeeded() {
        guard (answers.painEntries ?? []).isEmpty else { return }
        guard let locations = answers.painLocations, !locations.isEmpty else { return }
        guard let bodyPain = answers.bodyPain, bodyPain != .none else { return }

        let intensity: Int
        switch bodyPain {
        case .none: intensity = 0
        case .mild: intensity = 3
        case .moderate: intensity = 6
        case .severe: intensity = 8
        }
        let sensation = answers.painType.map { legacySensation(for: $0) } ?? .aching
        let restored = locations.map { location in
            PreSleepLogAnswers.PainEntry(
                area: area(for: location),
                side: .na,
                intensity: intensity,
                sensations: [sensation],
                pattern: nil,
                notes: nil
            )
        }
        answers.painEntries = restored
    }

    private func legacyLocation(for area: PreSleepLogAnswers.PainArea) -> PreSleepLogAnswers.PainLocation {
        switch area {
        case .headFace: return .head
        case .neck: return .neck
        case .upperBack, .midBack, .lowerBack: return .back
        case .shoulder: return .shoulders
        case .armElbow, .wristHand: return .joints
        case .chestRibs, .abdomen: return .stomach
        case .hipGlute, .knee, .ankleFoot: return .legs
        case .other: return .other
        }
    }

    private func area(for location: PreSleepLogAnswers.PainLocation) -> PreSleepLogAnswers.PainArea {
        switch location {
        case .head: return .headFace
        case .neck: return .neck
        case .back: return .lowerBack
        case .shoulders: return .shoulder
        case .legs: return .ankleFoot
        case .joints: return .knee
        case .stomach: return .abdomen
        case .other: return .other
        }
    }

    private func legacyPainType(for sensation: PreSleepLogAnswers.PainSensation) -> PreSleepLogAnswers.PainType {
        switch sensation {
        case .aching: return .aching
        case .sharp, .shooting, .stabbing: return .sharp
        case .burning: return .burning
        case .throbbing: return .throbbing
        case .cramping, .tightness: return .cramping
        case .radiating, .pinsNeedles, .numbness, .other: return .aching
        }
    }

    private func legacySensation(for type: PreSleepLogAnswers.PainType) -> PreSleepLogAnswers.PainSensation {
        switch type {
        case .aching: return .aching
        case .sharp: return .sharp
        case .burning: return .burning
        case .throbbing: return .throbbing
        case .cramping: return .cramping
        }
    }

    private func painLevel(for intensity: Int) -> PreSleepLogAnswers.PainLevel {
        switch intensity {
        case ..<1: return .none
        case 1...3: return .mild
        case 4...6: return .moderate
        default: return .severe
        }
    }

    private func defaultCaffeineAmountMg() -> Int {
        switch answers.stimulants ?? PreSleepLogAnswers.Stimulants.none {
        case .none: return 0
        case .tea: return 40
        case .soda: return 45
        case .coffee: return 95
        case .energyDrink: return 150
        case .multiple: return 200
        }
    }

    private func defaultAlcoholAmountDrinks() -> Double {
        switch answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none {
        case .none: return 0
        case .one: return 1
        case .twoThree: return 2.5
        case .fourPlus: return 4
        }
    }

    private func normalizeCaffeineDetails() {
        guard (answers.stimulants ?? PreSleepLogAnswers.Stimulants.none) != .none else { return }
        if let amount = answers.caffeineLastAmountMg {
            answers.caffeineLastAmountMg = max(5, amount)
        }
        if let total = answers.caffeineDailyTotalMg {
            answers.caffeineDailyTotalMg = max(5, total)
        }
        if let amount = answers.caffeineLastAmountMg,
           let total = answers.caffeineDailyTotalMg,
           total < amount {
            answers.caffeineDailyTotalMg = amount
        }
    }

    private func normalizeAlcoholDetails() {
        guard (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none else { return }
        if let amount = answers.alcoholLastAmountDrinks {
            answers.alcoholLastAmountDrinks = max(0.5, amount)
        }
        if let total = answers.alcoholDailyTotalDrinks {
            answers.alcoholDailyTotalDrinks = max(0.5, total)
        }
        if let amount = answers.alcoholLastAmountDrinks,
           let total = answers.alcoholDailyTotalDrinks,
           total < amount {
            answers.alcoholDailyTotalDrinks = amount
        }
    }

    private func bootstrapSubstanceDetailsIfNeeded() {
        if (answers.stimulants ?? PreSleepLogAnswers.Stimulants.none) != .none {
            if answers.caffeineLastIntakeAt == nil { answers.caffeineLastIntakeAt = Date() }
            if answers.caffeineLastAmountMg == nil { answers.caffeineLastAmountMg = defaultCaffeineAmountMg() }
            if answers.caffeineDailyTotalMg == nil { answers.caffeineDailyTotalMg = max(defaultCaffeineAmountMg(), answers.caffeineLastAmountMg ?? 0) }
            normalizeCaffeineDetails()
        }

        if (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none {
            if answers.alcoholLastDrinkAt == nil { answers.alcoholLastDrinkAt = Date() }
            if answers.alcoholLastAmountDrinks == nil { answers.alcoholLastAmountDrinks = defaultAlcoholAmountDrinks() }
            if answers.alcoholDailyTotalDrinks == nil { answers.alcoholDailyTotalDrinks = max(defaultAlcoholAmountDrinks(), answers.alcoholLastAmountDrinks ?? 0) }
            normalizeAlcoholDetails()
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
                    VStack(spacing: 10) {
                        OptionGrid(
                            options: PreSleepLogAnswers.ExerciseLevel.allCases,
                            selection: $answers.exercise
                        )
                        if (answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none) != .none {
                            SubstanceDetailCard(title: "Exercise Details") {
                                Picker("Type", selection: Binding(get: {
                                    answers.exerciseType ?? defaultExerciseType()
                                }, set: { answers.exerciseType = $0 })) {
                                    ForEach(PreSleepLogAnswers.ExerciseType.allCases, id: \.self) { type in
                                        Text(type.displayText).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                SubstanceTimePickerRow(
                                    label: "Last exercise time",
                                    value: Binding(
                                        get: { answers.exerciseLastAt ?? defaultExerciseLastAt() },
                                        set: { answers.exerciseLastAt = $0 }
                                    )
                                )
                                SubstanceIntStepperRow(
                                    label: "Duration",
                                    unit: "min",
                                    range: 5...600,
                                    step: 5,
                                    value: Binding(
                                        get: { answers.exerciseDurationMinutes ?? defaultExerciseDurationMinutes() },
                                        set: { answers.exerciseDurationMinutes = $0 }
                                    )
                                )
                            }
                        }
                    }
                }
                
                // Question 7: Nap today
                QuestionSection(title: "Nap today?", icon: "moon.zzz.fill") {
                    VStack(spacing: 10) {
                        OptionGrid(
                            options: PreSleepLogAnswers.NapDuration.allCases,
                            selection: $answers.napToday
                        )
                        if (answers.napToday ?? PreSleepLogAnswers.NapDuration.none) != .none {
                            SubstanceDetailCard(title: "Nap Details") {
                                SubstanceIntStepperRow(
                                    label: "Nap count",
                                    unit: "naps",
                                    range: 1...6,
                                    step: 1,
                                    value: Binding(
                                        get: { answers.napCount ?? 1 },
                                        set: { answers.napCount = $0 }
                                    )
                                )
                                SubstanceIntStepperRow(
                                    label: "Total nap time",
                                    unit: "min",
                                    range: 5...360,
                                    step: 5,
                                    value: Binding(
                                        get: { answers.napTotalMinutes ?? defaultNapTotalMinutes() },
                                        set: { answers.napTotalMinutes = $0 }
                                    )
                                )
                                SubstanceTimePickerRow(
                                    label: "Last nap ended",
                                    value: Binding(
                                        get: { answers.napLastEndAt ?? defaultNapLastEndAt() },
                                        set: { answers.napLastEndAt = $0 }
                                    )
                                )
                            }
                        }
                    }
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
                        
                        QuestionSection(title: "Sleep aids?", icon: "moon.stars") {
                            OptionGrid(
                                options: PreSleepLogAnswers.SleepAid.allCases,
                                selection: $answers.sleepAids
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: showMoreDetails)
        }
        .onChange(of: answers.exercise) { newValue in
            if (newValue ?? PreSleepLogAnswers.ExerciseLevel.none) == PreSleepLogAnswers.ExerciseLevel.none {
                answers.exerciseType = nil
                answers.exerciseLastAt = nil
                answers.exerciseDurationMinutes = nil
            } else {
                if answers.exerciseType == nil { answers.exerciseType = defaultExerciseType() }
                if answers.exerciseLastAt == nil { answers.exerciseLastAt = defaultExerciseLastAt() }
                if answers.exerciseDurationMinutes == nil { answers.exerciseDurationMinutes = defaultExerciseDurationMinutes() }
                normalizeExerciseDetails()
            }
        }
        .onChange(of: answers.exerciseDurationMinutes) { _ in
            normalizeExerciseDetails()
        }
        .onChange(of: answers.napToday) { newValue in
            if (newValue ?? PreSleepLogAnswers.NapDuration.none) == PreSleepLogAnswers.NapDuration.none {
                answers.napCount = nil
                answers.napTotalMinutes = nil
                answers.napLastEndAt = nil
            } else {
                if answers.napCount == nil { answers.napCount = 1 }
                if answers.napTotalMinutes == nil { answers.napTotalMinutes = defaultNapTotalMinutes() }
                if answers.napLastEndAt == nil { answers.napLastEndAt = defaultNapLastEndAt() }
                normalizeNapDetails()
            }
        }
        .onChange(of: answers.napCount) { _ in
            normalizeNapDetails()
        }
        .onChange(of: answers.napTotalMinutes) { _ in
            normalizeNapDetails()
        }
        .onAppear {
            bootstrapActivityDetailsIfNeeded()
        }
    }

    private func defaultExerciseType() -> PreSleepLogAnswers.ExerciseType {
        switch answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none {
        case .none: return .walking
        case .light: return .walking
        case .moderate: return .cardio
        case .intense: return .strength
        }
    }

    private func defaultExerciseLastAt() -> Date {
        Date().addingTimeInterval(-4 * 3600)
    }

    private func defaultExerciseDurationMinutes() -> Int {
        switch answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none {
        case .none: return 5
        case .light: return 20
        case .moderate: return 40
        case .intense: return 60
        }
    }

    private func defaultNapTotalMinutes() -> Int {
        switch answers.napToday ?? PreSleepLogAnswers.NapDuration.none {
        case .none: return 5
        case .short: return 20
        case .medium: return 45
        case .long: return 90
        }
    }

    private func defaultNapLastEndAt() -> Date {
        Date().addingTimeInterval(-6 * 3600)
    }

    private func normalizeExerciseDetails() {
        guard (answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none) != .none else { return }
        if let duration = answers.exerciseDurationMinutes {
            answers.exerciseDurationMinutes = max(5, min(600, duration))
        }
    }

    private func normalizeNapDetails() {
        guard (answers.napToday ?? PreSleepLogAnswers.NapDuration.none) != .none else { return }
        if let count = answers.napCount {
            answers.napCount = max(1, min(6, count))
        }
        if let total = answers.napTotalMinutes {
            answers.napTotalMinutes = max(5, min(360, total))
        }
    }

    private func bootstrapActivityDetailsIfNeeded() {
        if (answers.exercise ?? PreSleepLogAnswers.ExerciseLevel.none) != .none {
            if answers.exerciseType == nil { answers.exerciseType = defaultExerciseType() }
            if answers.exerciseLastAt == nil { answers.exerciseLastAt = defaultExerciseLastAt() }
            if answers.exerciseDurationMinutes == nil { answers.exerciseDurationMinutes = defaultExerciseDurationMinutes() }
            normalizeExerciseDetails()
        }

        if (answers.napToday ?? PreSleepLogAnswers.NapDuration.none) != .none {
            if answers.napCount == nil { answers.napCount = 1 }
            if answers.napTotalMinutes == nil { answers.napTotalMinutes = defaultNapTotalMinutes() }
            if answers.napLastEndAt == nil { answers.napLastEndAt = defaultNapLastEndAt() }
            normalizeNapDetails()
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

struct SubstanceDetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            content
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

struct SubstanceTimePickerRow: View {
    let label: String
    @Binding var value: Date

    var body: some View {
        DatePicker(
            label,
            selection: $value,
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.compact)
    }
}

struct SubstanceIntStepperRow: View {
    let label: String
    let unit: String
    let range: ClosedRange<Int>
    let step: Int
    @Binding var value: Int

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value) \(unit)")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SubstanceDoubleStepperRow: View {
    let label: String
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    @Binding var value: Double

    private var displayValue: String {
        let roundedToInt = abs(value.rounded() - value) < 0.001
        if roundedToInt {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(displayValue) \(unit)")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct GranularPainEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let initialEntry: PreSleepLogAnswers.PainEntry?
    let onSave: (PreSleepLogAnswers.PainEntry) -> Void

    @State private var area: PreSleepLogAnswers.PainArea
    @State private var side: PreSleepLogAnswers.PainSide
    @State private var intensity: Double
    @State private var sensations: Set<PreSleepLogAnswers.PainSensation>
    @State private var pattern: PreSleepLogAnswers.PainPattern?
    @State private var notes: String

    init(
        initialEntry: PreSleepLogAnswers.PainEntry? = nil,
        onSave: @escaping (PreSleepLogAnswers.PainEntry) -> Void
    ) {
        self.initialEntry = initialEntry
        self.onSave = onSave
        _area = State(initialValue: initialEntry?.area ?? .midBack)
        _side = State(initialValue: initialEntry?.side ?? .both)
        _intensity = State(initialValue: Double(initialEntry?.intensity ?? 5))
        _sensations = State(initialValue: Set(initialEntry?.sensations ?? [.aching]))
        _pattern = State(initialValue: initialEntry?.pattern)
        _notes = State(initialValue: initialEntry?.notes ?? "")
    }

    private var canSave: Bool {
        !sensations.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Area & Side") {
                    Picker("Area", selection: $area) {
                        ForEach(PreSleepLogAnswers.PainArea.allCases, id: \.self) { value in
                            Text(value.displayText).tag(value)
                        }
                    }

                    Picker("Side", selection: $side) {
                        ForEach(PreSleepLogAnswers.PainSide.allCases, id: \.self) { value in
                            Text(value.displayText).tag(value)
                        }
                    }
                }

                Section("Intensity") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(Int(intensity))/10")
                            .font(.headline)
                        Slider(value: $intensity, in: 0...10, step: 1)
                            .tint(.red)
                    }
                }

                Section("Sensations") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(PreSleepLogAnswers.PainSensation.allCases, id: \.self) { value in
                            Button {
                                if sensations.contains(value) {
                                    sensations.remove(value)
                                } else {
                                    sensations.insert(value)
                                }
                            } label: {
                                Text(value.displayText)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(sensations.contains(value) ? Color.accentColor : Color(.secondarySystemBackground))
                                    )
                                    .foregroundColor(sensations.contains(value) ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Pattern (optional)") {
                    Picker("Pattern", selection: $pattern) {
                        Text("Not set").tag(Optional<PreSleepLogAnswers.PainPattern>.none)
                        ForEach(PreSleepLogAnswers.PainPattern.allCases, id: \.self) { value in
                            Text(value.displayText).tag(Optional(value))
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextField("Add detail", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(initialEntry == nil ? "Add Pain Entry" : "Edit Pain Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            PreSleepLogAnswers.PainEntry(
                                area: area,
                                side: side,
                                intensity: Int(intensity),
                                sensations: Array(sensations).sorted { $0.rawValue < $1.rawValue },
                                pattern: pattern,
                                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                            )
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

struct GranularPainEntryRow: View {
    let entry: PreSleepLogAnswers.PainEntry

    private var detailText: String {
        let sensationText = entry.sensations.map(\.displayText).joined(separator: ", ")
        if let pattern = entry.pattern {
            return "\(sensationText) • \(pattern.displayText)"
        }
        return sensationText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(entry.area.displayText) (\(entry.side.displayText))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(entry.intensity)/10")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.red)
            }
            Text(detailText)
                .font(.caption)
                .foregroundColor(.secondary)
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
extension PreSleepLogAnswers.ExerciseType: DisplayTextProvider {}
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
        onComplete: { _ in },
        onSkip: {}
    )
}
