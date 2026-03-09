//
//  PreSleepLogView.swift
//  DoseTap
//
//  Pre-Sleep Log: 3-card quick check-in before session
//  Designed to complete in <30 seconds with one hand
//

import DoseCore
import Foundation
import SwiftUI

// MARK: - Pre-Sleep Log View (Main Container)
struct PreSleepLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentCard = 0
    @State private var answers: PreSleepLogAnswers
    @State private var showMoreDetails = false
    @State private var rememberLastSettings: Bool
    @State private var didApplyRememberedSettings = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @ObservedObject private var sleepPlanStore = SleepPlanStore.shared
    
    let existingLog: StoredPreSleepLog?
    let onComplete: (PreSleepLogAnswers) throws -> Void
    let onSkip: () throws -> Void
    
    private let totalCards = 3
    private static let rememberLastSettingsKey = "preSleepLog.rememberLastSettings"
    fileprivate static let maxDoseAmountMg = 20_000
    fileprivate static let nightlyDoseWarningThresholdMg = 9_000
    
    init(
        existingLog: StoredPreSleepLog? = nil,
        onComplete: @escaping (PreSleepLogAnswers) throws -> Void,
        onSkip: @escaping () throws -> Void
    ) {
        self.existingLog = existingLog
        self.onComplete = onComplete
        self.onSkip = onSkip
        let initialAnswers = existingLog?.answers ?? PreSleepLogAnswers()
        _answers = State(initialValue: initialAnswers)
        _showMoreDetails = State(initialValue: Self.shouldExpandOptionalDetails(for: initialAnswers))
        _rememberLastSettings = State(initialValue: UserDefaults.standard.bool(forKey: Self.rememberLastSettingsKey))
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

                rememberLastSettingsSection
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                // Card content
                TabView(selection: $currentCard) {
                    // Card 1: Timing + Stress
                    Card1TimingStress(answers: $answers)
                        .tag(0)
                    
                    // Card 2: Body + Substances
                    Card2BodySubstances(
                        answers: $answers,
                        medicationSessionKey: medicationSessionKey
                    )
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
        .onAppear {
            applyRememberedSettingsIfNeeded()
        }
    }
    
    private func saveAndComplete() {
        if let pain = answers.bodyPain, pain != .none, (answers.painEntries ?? []).isEmpty {
            saveErrorMessage = "Add at least one pain entry with area, side, intensity, and sensation."
            showSaveError = true
            return
        }
        if answers.hasCaffeineIntake &&
            (answers.caffeineLastIntakeAt == nil || answers.caffeineLastAmountMg == nil || answers.caffeineDailyTotalMg == nil) {
            saveErrorMessage = "Add stimulant last time, last amount, and daily total."
            showSaveError = true
            return
        }
        if answers.hasCaffeineIntake {
            let last = answers.caffeineLastAmountMg ?? 0
            let total = answers.caffeineDailyTotalMg ?? 0
            if last <= 0 {
                saveErrorMessage = "Stimulant last amount must be greater than 0 oz."
                showSaveError = true
                return
            }
            if total < last {
                saveErrorMessage = "Stimulant daily total must be at least the last amount."
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
        if (answers.lateMeal ?? PreSleepLogAnswers.LateMeal.none) != .none && answers.lateMealEndedAt == nil {
            saveErrorMessage = "Add when your last late meal ended."
            showSaveError = true
            return
        }
        if (answers.screensInBed ?? PreSleepLogAnswers.ScreensInBed.none) != .none && answers.screensLastUsedAt == nil {
            saveErrorMessage = "Add when you last used a screen in bed."
            showSaveError = true
            return
        }
        do {
            UserDefaults.standard.set(rememberLastSettings, forKey: Self.rememberLastSettingsKey)
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
            answers.sleepAidSelections = lastAnswers.sleepAidSelections
            answers.plannedTotalNightlyMg = lastAnswers.plannedTotalNightlyMg
            answers.plannedDoseSplitRatio = lastAnswers.plannedDoseSplitRatio
            answers.plannedDose1Mg = lastAnswers.plannedDose1Mg
            answers.plannedDose2Mg = lastAnswers.plannedDose2Mg
            showMoreDetails = showMoreDetails || Self.shouldExpandOptionalDetails(for: answers)
        }
    }

    private func applyRememberedSettingsIfNeeded() {
        guard existingLog == nil else { return }
        guard rememberLastSettings else { return }
        guard !didApplyRememberedSettings else { return }
        didApplyRememberedSettings = true
        loadLastAnswers()
    }

    private func toggleRememberLastSettings() {
        withAnimation {
            rememberLastSettings.toggle()
        }
        UserDefaults.standard.set(rememberLastSettings, forKey: Self.rememberLastSettingsKey)
        if rememberLastSettings {
            applyRememberedSettingsIfNeeded()
        }
    }

    private var planSummary: (wakeBy: Date, inBed: Date, windDown: Date, expectedSleep: Double)? {
        let key = sessionRepo.preSleepDisplaySessionKey(for: Date())
        let plan = sleepPlanStore.plan(for: key, now: Date(), tz: TimeZone.current)
        return (plan.wakeBy, plan.recommendedInBed, plan.windDown, plan.expectedSleepMinutes)
    }

    private var medicationSessionKey: String {
        let referenceDate: Date
        if let timestamp = existingLog.flatMap({ AppFormatters.iso8601Fractional.date(from: $0.createdAtUtc) }) {
            referenceDate = timestamp
        } else {
            referenceDate = Date()
        }
        return sessionRepo.preSleepSessionDateKey(for: referenceDate)
    }

    private static func shouldExpandOptionalDetails(for answers: PreSleepLogAnswers) -> Bool {
        (answers.lateMeal ?? .none) != .none ||
        answers.lateMealEndedAt != nil ||
        (answers.screensInBed ?? .none) != .none ||
        answers.screensLastUsedAt != nil ||
        answers.roomTemp != nil ||
        answers.noiseLevel != nil ||
        answers.hasSleepAids ||
        !(answers.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var rememberLastSettingsSection: some View {
        HStack {
            Image(systemName: rememberLastSettings ? "checkmark.square.fill" : "square")
                .foregroundColor(rememberLastSettings ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Remember last pre-sleep settings")
                    .font(.subheadline)
                Text("Auto-apply the same pre-sleep setup next time. You can still override anything.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .onTapGesture {
            toggleRememberLastSettings()
        }
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
        AppFormatters.shortTime
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

    private var hasStressDetails: Bool {
        answers.stressLevel != nil
            || !answers.resolvedStressDrivers.isEmpty
            || answers.stressProgression != nil
            || !(answers.stressNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var stressDriversBinding: Binding<[PreSleepLogAnswers.StressDriver]> {
        Binding(
            get: { answers.resolvedStressDrivers },
            set: { newValue in
                let sanitized = PreSleepLogAnswers.sanitizedStressDrivers(newValue)
                answers.stressDrivers = sanitized.isEmpty ? nil : sanitized
                answers.stressDriver = sanitized.first
            }
        )
    }

    private var stressNotesBinding: Binding<String> {
        Binding(
            get: { answers.stressNotes ?? "" },
            set: { answers.stressNotes = $0 }
        )
    }
    
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
                
                if hasStressDetails {
                    QuestionSection(title: "Current stressors?", icon: "exclamationmark.triangle") {
                        MultiSelectGrid(
                            options: PreSleepLogAnswers.StressDriver.allCases,
                            selections: stressDriversBinding
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    QuestionSection(title: "Stress trend today?", icon: "chart.line.uptrend.xyaxis") {
                        OptionGrid(
                            options: PreSleepLogAnswers.StressProgression.allCases,
                            selection: $answers.stressProgression
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    QuestionSection(title: "Stress notes", icon: "square.and.pencil") {
                        TextField(
                            "What is driving it, what helped, or what got worse?",
                            text: stressNotesBinding,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
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
            .animation(.easeInOut(duration: 0.2), value: answers.stressProgression)
            .animation(.easeInOut(duration: 0.2), value: answers.intendedSleepTime)
        }
    }
}

// MARK: - Card 2: Body + Substances
struct Card2BodySubstances: View {
    @Binding var answers: PreSleepLogAnswers
    let medicationSessionKey: String
    @State private var showMedicationPicker = false
    @State private var showPainEntryEditor = false
    @State private var editingPainEntry: PreSleepLogAnswers.PainEntry?
    @ObservedObject private var sessionRepo = SessionRepository.shared

    private var painEntries: [PreSleepLogAnswers.PainEntry] {
        (answers.painEntries ?? []).sorted { $0.entryKey < $1.entryKey }
    }

    private var medicationEntries: [MedicationEntry] {
        sessionRepo.listMedicationEntries(for: medicationSessionKey)
            .sorted { $0.takenAtUTC > $1.takenAtUTC }
    }

    private var plannedTotalNightlyBinding: Binding<Int> {
        Binding(
            get: { answers.resolvedPlannedTotalNightlyMg ?? defaultNightDoseTotalMg() },
            set: { newValue in
                answers.plannedTotalNightlyMg = normalizedTotalNightlyDoseAmount(newValue)
                synchronizeDosePlan()
            }
        )
    }

    private var plannedSplitRatioBinding: Binding<[Double]> {
        Binding(
            get: { answers.resolvedPlannedDoseSplitRatio },
            set: { newValue in
                answers.plannedDoseSplitRatio = normalizedDoseSplitRatio(
                    newValue,
                    totalMg: answers.resolvedPlannedTotalNightlyMg ?? defaultNightDoseTotalMg()
                )
                synchronizeDosePlan()
            }
        )
    }

    private var dosePlanPercentages: [Int] {
        answers.plannedDosePercentages ?? [50, 50]
    }

    private var plannedDose1Amount: Int {
        if let explicit = answers.plannedDose1Mg {
            return explicit
        }
        if let total = answers.resolvedPlannedTotalNightlyMg {
            return Int((Double(total) * answers.resolvedPlannedDoseSplitRatio[0]).rounded())
        }
        return defaultNightDoseAmountMg()
    }

    private var plannedDose2Amount: Int {
        if let explicit = answers.plannedDose2Mg {
            return explicit
        }
        if let total = answers.resolvedPlannedTotalNightlyMg {
            return Int((Double(total) * answers.resolvedPlannedDoseSplitRatio[1]).rounded())
        }
        return defaultNightDoseAmountMg()
    }

    private var hasOffLabelSingleDose: Bool {
        max(plannedDose1Amount, plannedDose2Amount) > 4500
    }

    private var hasHighNightlyDoseTotal: Bool {
        (answers.plannedTotalNightlyMg ?? answers.resolvedPlannedTotalNightlyMg ?? defaultNightDoseTotalMg()) > PreSleepLogView.nightlyDoseWarningThresholdMg
    }

    private var dosePlanSection: some View {
        QuestionSection(title: "Tonight's dose plan", icon: "drop.fill") {
            SubstanceDetailCard(title: "Planned oxybate amounts") {
                SubstanceIntStepperRow(
                    label: "Total nightly plan",
                    unit: "mg",
                    range: 500...PreSleepLogView.maxDoseAmountMg,
                    step: 250,
                    value: plannedTotalNightlyBinding
                )

                VStack(spacing: 8) {
                    DosePlanPreviewRow(
                        label: "Dose 1 plan",
                        amountMg: plannedDose1Amount,
                        percentage: dosePlanPercentages[0]
                    )
                    DosePlanPreviewRow(
                        label: "Dose 2 plan",
                        amountMg: plannedDose2Amount,
                        percentage: dosePlanPercentages[1]
                    )
                }

                PreSleepDoseSplitRatioSelector(splitRatio: plannedSplitRatioBinding)

                if hasOffLabelSingleDose {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("One planned dose is above 4,500 mg. Review carefully before saving.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if hasHighNightlyDoseTotal {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Nightly total is above 9,000 mg. Double-check this plan before saving.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Set the total for the night, then adjust the split percentage. These planned amounts prefill the morning reconciliation flow if you miss a dose tap overnight.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
                    VStack(spacing: 12) {
                        HStack(alignment: .top) {
                            Text("Select every source you had. Leave blank if none.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if answers.hasCaffeineIntake {
                                Button("Clear") {
                                    clearCaffeineDetails()
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }

                        MultiSelectGrid(
                            options: PreSleepLogAnswers.caffeineSourceOptions,
                            selections: Binding(
                                get: { answers.resolvedCaffeineSources },
                                set: { updateCaffeineSources($0) }
                            )
                        )

                        if answers.hasLegacyUnspecifiedCaffeineSources {
                            Text("Older entry saved as multiple sources. Leave it as-is or reselect the exact drinks now.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if answers.hasCaffeineIntake {
                            SubstanceDetailCard(title: caffeineDetailTitle) {
                                SubstanceTimePickerRow(
                                    label: "Last intake time",
                                    value: Binding(
                                        get: { answers.caffeineLastIntakeAt ?? Date() },
                                        set: { answers.caffeineLastIntakeAt = $0 }
                                    )
                                )
                                SubstanceIntStepperRow(
                                    label: "Last drink size",
                                    unit: "oz",
                                    range: 2...48,
                                    step: 2,
                                    value: Binding(
                                        get: { answers.caffeineLastAmountMg ?? defaultCaffeineAmountOz() },
                                        set: { answers.caffeineLastAmountMg = $0 }
                                    )
                                )
                                SubstanceIntStepperRow(
                                    label: "Total today",
                                    unit: "oz",
                                    range: max(answers.caffeineLastAmountMg ?? defaultCaffeineAmountOz(), 2)...96,
                                    step: 4,
                                    value: Binding(
                                        get: { answers.caffeineDailyTotalMg ?? max(answers.caffeineLastAmountMg ?? defaultCaffeineAmountOz(), defaultCaffeineAmountOz()) },
                                        set: { answers.caffeineDailyTotalMg = $0 }
                                    )
                                )
                                Text("Amounts use beverage ounces, not estimated caffeine milligrams.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
                
                // Medication logging
                QuestionSection(title: "Medications today?", icon: "pills.fill") {
                    VStack(spacing: 12) {
                        Text("Log alerting meds, sleep meds, or anything else you took so the daytime record matches the night review.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if medicationEntries.isEmpty {
                            Text("No medications logged for this session yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(medicationEntries) { entry in
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.displayName)
                                                .font(.subheadline.weight(.semibold))
                                            Text("\(formatMedicationDose(entry)) at \(AppFormatters.shortTime.string(from: entry.takenAtUTC))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                                               !notes.isEmpty {
                                                Text(notes)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 8)
                                        Button(role: .destructive) {
                                            sessionRepo.deleteMedicationEntry(id: entry.id)
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
                        }

                        Button {
                            showMedicationPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text(medicationEntries.isEmpty ? "Log Medication" : "Add Medication")
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

                dosePlanSection
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: answers.bodyPain)
        }
        .sheet(isPresented: $showMedicationPicker) {
            MedicationPickerView()
        }
        .sheet(isPresented: $showPainEntryEditor) {
            GranularPainEntryEditorView(initialEntry: editingPainEntry) { result in
                upsertPainEntries(result.entries, replacingEntryKey: result.replacedEntryKey)
            }
        }
        .onChange(of: answers.bodyPain) { newValue in
            guard newValue == .some(PreSleepLogAnswers.PainLevel.none) else { return }
            answers.painEntries = nil
            answers.painLocations = nil
            answers.painType = nil
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
            bootstrapDosePlanIfNeeded()
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

    private func upsertPainEntries(_ entries: [PreSleepLogAnswers.PainEntry], replacingEntryKey: String?) {
        var updated = answers.painEntries ?? []
        if let replacingEntryKey {
            updated.removeAll { $0.entryKey == replacingEntryKey }
        }
        for entry in entries {
            if let idx = updated.firstIndex(where: { $0.entryKey == entry.entryKey }) {
                updated[idx] = entry
            } else {
                updated.append(entry)
            }
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

    private var caffeineDetailTitle: String {
        guard let sources = answers.caffeineSourceDisplayText, !sources.isEmpty else {
            return "Caffeine / Stimulant Details"
        }
        return "Caffeine / Stimulant Details: \(sources)"
    }

    private func updateCaffeineSources(_ sources: [PreSleepLogAnswers.Stimulants]) {
        let sanitized = PreSleepLogAnswers.sanitizedCaffeineSources(sources)
        answers.caffeineSources = sanitized.isEmpty ? nil : sanitized

        if sanitized.isEmpty {
            clearCaffeineDetails()
            return
        }

        answers.stimulants = PreSleepLogAnswers.caffeineSummary(for: sanitized)
        bootstrapCaffeineDetailsIfNeeded()
    }

    private func clearCaffeineDetails() {
        answers.stimulants = PreSleepLogAnswers.Stimulants.none
        answers.caffeineSources = nil
        answers.caffeineLastIntakeAt = nil
        answers.caffeineLastAmountMg = nil
        answers.caffeineDailyTotalMg = nil
    }

    /// Default beverage oz based on selected stimulant source.
    /// Property name retains legacy "Mg" suffix in the model for storage compatibility.
    private func defaultCaffeineAmountOz() -> Int {
        switch answers.caffeineSourceSummary ?? answers.stimulants ?? PreSleepLogAnswers.Stimulants.none {
        case .none: return 0
        case .tea: return 8
        case .soda: return 12
        case .coffee: return 12
        case .energyDrink: return 16
        case .multiple: return 24
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
        guard answers.hasCaffeineIntake else { return }
        if let amount = answers.caffeineLastAmountMg {
            answers.caffeineLastAmountMg = max(2, amount)
        }
        if let total = answers.caffeineDailyTotalMg {
            answers.caffeineDailyTotalMg = max(2, total)
        }
        if let amount = answers.caffeineLastAmountMg,
           let total = answers.caffeineDailyTotalMg,
           total < amount {
            answers.caffeineDailyTotalMg = amount
        }
    }

    private func bootstrapCaffeineDetailsIfNeeded() {
        if answers.caffeineSources == nil {
            let resolved = answers.resolvedCaffeineSources
            answers.caffeineSources = resolved.isEmpty ? nil : resolved
            if !resolved.isEmpty {
                answers.stimulants = PreSleepLogAnswers.caffeineSummary(for: resolved)
            }
        }

        guard answers.hasCaffeineIntake else { return }
        if answers.caffeineLastIntakeAt == nil { answers.caffeineLastIntakeAt = Date() }
        if answers.caffeineLastAmountMg == nil { answers.caffeineLastAmountMg = defaultCaffeineAmountOz() }
        if answers.caffeineDailyTotalMg == nil { answers.caffeineDailyTotalMg = max(defaultCaffeineAmountOz(), answers.caffeineLastAmountMg ?? 0) }
        normalizeCaffeineDetails()
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
        bootstrapCaffeineDetailsIfNeeded()

        if (answers.alcohol ?? PreSleepLogAnswers.AlcoholLevel.none) != .none {
            if answers.alcoholLastDrinkAt == nil { answers.alcoholLastDrinkAt = Date() }
            if answers.alcoholLastAmountDrinks == nil { answers.alcoholLastAmountDrinks = defaultAlcoholAmountDrinks() }
            if answers.alcoholDailyTotalDrinks == nil { answers.alcoholDailyTotalDrinks = max(defaultAlcoholAmountDrinks(), answers.alcoholLastAmountDrinks ?? 0) }
            normalizeAlcoholDetails()
        }
    }

    private func defaultNightDoseAmountMg() -> Int {
        DoseCore.MedicationConfig.nightMedications.first(where: { $0.id != "lumryz" })?.defaultDoseMg
        ?? DoseCore.MedicationConfig.nightMedications.first?.defaultDoseMg
        ?? 4500
    }

    private func defaultNightDoseTotalMg() -> Int {
        max(500, min(PreSleepLogView.maxDoseAmountMg, defaultNightDoseAmountMg() * 2))
    }

    private func normalizedDoseAmount(_ value: Int) -> Int {
        max(250, min(PreSleepLogView.maxDoseAmountMg, value))
    }

    private func normalizedTotalNightlyDoseAmount(_ value: Int) -> Int {
        let clamped = max(500, min(PreSleepLogView.maxDoseAmountMg, value))
        let step = 250
        return Int((Double(clamped) / Double(step)).rounded()) * step
    }

    private func normalizedDoseSplitRatio(_ ratio: [Double], totalMg: Int) -> [Double] {
        let sanitized = PreSleepLogAnswers.sanitizedDoseSplitRatio(ratio) ?? PreSleepLogAnswers.defaultDoseSplitRatio
        let minComponent = min(0.5, max(250.0 / Double(max(totalMg, 1)), 0.0))
        let clampedFirst = min(max(sanitized[0], minComponent), 1.0 - minComponent)
        let roundedFirst = (clampedFirst * 100).rounded() / 100
        return [roundedFirst, max(0, 1 - roundedFirst)]
    }

    private func synchronizeDosePlan() {
        let total = normalizedTotalNightlyDoseAmount(answers.plannedTotalNightlyMg ?? answers.resolvedPlannedTotalNightlyMg ?? defaultNightDoseTotalMg())
        let splitRatio = normalizedDoseSplitRatio(
            answers.plannedDoseSplitRatio ?? answers.resolvedPlannedDoseSplitRatio,
            totalMg: total
        )
        let dose1 = normalizedDoseAmount(Int((Double(total) * splitRatio[0]).rounded()))
        let dose2 = normalizedDoseAmount(max(250, total - dose1))

        answers.plannedTotalNightlyMg = total
        answers.plannedDose1Mg = dose1
        answers.plannedDose2Mg = dose2
        answers.plannedDoseSplitRatio = [Double(dose1) / Double(total), Double(dose2) / Double(total)]
    }

    private func bootstrapDosePlanIfNeeded() {
        if answers.plannedTotalNightlyMg == nil {
            answers.plannedTotalNightlyMg = normalizedTotalNightlyDoseAmount(
                answers.resolvedPlannedTotalNightlyMg ?? defaultNightDoseTotalMg()
            )
        }
        if answers.plannedDoseSplitRatio == nil {
            answers.plannedDoseSplitRatio = normalizedDoseSplitRatio(
                answers.resolvedPlannedDoseSplitRatio,
                totalMg: answers.plannedTotalNightlyMg ?? defaultNightDoseTotalMg()
            )
        }
        synchronizeDosePlan()
    }

    private func formatMedicationDose(_ entry: MedicationEntry) -> String {
        if let medication = MedicationConfig.type(for: entry.medicationId),
           medication.category == .sodiumOxybate {
            return String(format: "%.2f g", Double(entry.doseMg) / 1000.0)
        }
        return "\(entry.doseMg) mg"
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
                            VStack(spacing: 10) {
                                OptionGrid(
                                    options: PreSleepLogAnswers.LateMeal.allCases,
                                    selection: $answers.lateMeal
                                )
                                if (answers.lateMeal ?? PreSleepLogAnswers.LateMeal.none) != .none {
                                    SubstanceDetailCard(title: "Meal Timing") {
                                        SubstanceTimePickerRow(
                                            label: "Last meal ended",
                                            value: Binding(
                                                get: { answers.lateMealEndedAt ?? defaultLateMealEndedAt() },
                                                set: { answers.lateMealEndedAt = $0 }
                                            )
                                        )
                                    }
                                }
                            }
                        }
                        
                        QuestionSection(title: "Screens in bed?", icon: "iphone") {
                            VStack(spacing: 10) {
                                OptionGrid(
                                    options: PreSleepLogAnswers.ScreensInBed.allCases,
                                    selection: $answers.screensInBed
                                )
                                if (answers.screensInBed ?? PreSleepLogAnswers.ScreensInBed.none) != .none {
                                    SubstanceDetailCard(title: "Screen Timing") {
                                        SubstanceTimePickerRow(
                                            label: "Last used in bed",
                                            value: Binding(
                                                get: { answers.screensLastUsedAt ?? defaultScreensLastUsedAt() },
                                                set: { answers.screensLastUsedAt = $0 }
                                            )
                                        )
                                    }
                                }
                            }
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
                            VStack(spacing: 12) {
                                HStack(alignment: .top) {
                                    Text("Select every aid you used.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if answers.hasSleepAids {
                                        Button("Clear") {
                                            clearSleepAidSelections()
                                        }
                                        .font(.caption.weight(.semibold))
                                    }
                                }

                                MultiSelectGrid(
                                    options: PreSleepLogAnswers.sleepAidOptions,
                                    selections: Binding(
                                        get: { answers.resolvedSleepAidSelections },
                                        set: { updateSleepAidSelections($0) }
                                    )
                                )

                                if answers.hasLegacyUnspecifiedSleepAids {
                                    Text("Older entry saved as multiple sleep aids. Leave it as-is or reselect the exact aids now.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if answers.hasSleepAids {
                                    SubstanceDetailCard(title: sleepAidDetailTitle) {
                                        Text("Track combinations like fan plus earplugs without collapsing them into one vague bucket.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }

                        QuestionSection(title: "Anything else?", icon: "square.and.pencil") {
                            TextField("Notes about today, routines, symptoms, or setup", text: Binding(
                                get: { answers.notes ?? "" },
                                set: { answers.notes = $0 }
                            ), axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
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
        .onChange(of: answers.lateMeal) { newValue in
            if (newValue ?? PreSleepLogAnswers.LateMeal.none) == .none {
                answers.lateMealEndedAt = nil
            } else if answers.lateMealEndedAt == nil {
                answers.lateMealEndedAt = defaultLateMealEndedAt()
            }
        }
        .onChange(of: answers.screensInBed) { newValue in
            if (newValue ?? PreSleepLogAnswers.ScreensInBed.none) == .none {
                answers.screensLastUsedAt = nil
            } else if answers.screensLastUsedAt == nil {
                answers.screensLastUsedAt = defaultScreensLastUsedAt()
            }
        }
        .onAppear {
            bootstrapActivityDetailsIfNeeded()
            bootstrapOptionalDetailsIfNeeded()
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

    private func defaultLateMealEndedAt() -> Date {
        Date().addingTimeInterval(-2 * 3600)
    }

    private func defaultScreensLastUsedAt() -> Date {
        Date().addingTimeInterval(-45 * 60)
    }

    private var sleepAidDetailTitle: String {
        guard let aids = answers.sleepAidDisplayText, !aids.isEmpty else {
            return "Sleep Aid Details"
        }
        return "Sleep Aid Details: \(aids)"
    }

    private func updateSleepAidSelections(_ selections: [PreSleepLogAnswers.SleepAid]) {
        let sanitized = PreSleepLogAnswers.sanitizedSleepAidSelections(selections)
        answers.sleepAidSelections = sanitized.isEmpty ? nil : sanitized
        answers.sleepAids = sanitized.isEmpty
            ? PreSleepLogAnswers.SleepAid.none
            : PreSleepLogAnswers.sleepAidSummary(for: sanitized)
    }

    private func clearSleepAidSelections() {
        answers.sleepAidSelections = nil
        answers.sleepAids = PreSleepLogAnswers.SleepAid.none
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

    private func bootstrapOptionalDetailsIfNeeded() {
        if (answers.lateMeal ?? PreSleepLogAnswers.LateMeal.none) != .none, answers.lateMealEndedAt == nil {
            answers.lateMealEndedAt = defaultLateMealEndedAt()
        }

        if (answers.screensInBed ?? PreSleepLogAnswers.ScreensInBed.none) != .none, answers.screensLastUsedAt == nil {
            answers.screensLastUsedAt = defaultScreensLastUsedAt()
        }

        if answers.sleepAidSelections == nil {
            let resolved = answers.resolvedSleepAidSelections
            answers.sleepAidSelections = resolved.isEmpty ? nil : resolved
            if !resolved.isEmpty {
                answers.sleepAids = PreSleepLogAnswers.sleepAidSummary(for: resolved)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    PreSleepLogView(
        onComplete: { _ in },
        onSkip: {}
    )
}
