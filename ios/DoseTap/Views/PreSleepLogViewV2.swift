//
//  PreSleepLogViewV2.swift
//  DoseTap
//
//  Single-page collapsible Pre-Sleep Check-in
//  Designed to complete in <30 seconds with one hand
//  - No card navigation friction
//  - Live summary strip updates as you fill
//  - Auto-collapsing sections based on context
//  - Sticky bottom bar with Cancel/Save
//

import SwiftUI

// MARK: - Pre-Sleep Log View (Single Page Collapsible)

struct PreSleepLogViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answers: PreSleepLogAnswers
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showSkipConfirmation = false
    @State private var showUseLastApplied = false
    @State private var changedFieldsFromUseLast: [String] = []
    
    // Section expansion states
    @State private var sleepPlanExpanded = true
    @State private var bodySubstancesExpanded = true
    @State private var painExpanded = false  // Collapsed by default if last was 0
    @State private var activityExpanded = true
    @State private var advancedExpanded = false
    
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @ObservedObject private var sleepPlanStore = SleepPlanStore.shared
    
    let existingLog: StoredPreSleepLog?
    let onComplete: (PreSleepLogAnswers) throws -> Void
    let onSkip: () throws -> Void
    
    init(
        existingLog: StoredPreSleepLog? = nil,
        onComplete: @escaping (PreSleepLogAnswers) throws -> Void,
        onSkip: @escaping () throws -> Void
    ) {
        self.existingLog = existingLog
        self.onComplete = onComplete
        self.onSkip = onSkip
        _answers = State(initialValue: existingLog?.answers ?? PreSleepLogAnswers())
        
        // Auto-expand pain if last value was > 0
        if let existing = existingLog?.answers, let pain = existing.painLevel010, pain > 0 {
            _painExpanded = State(initialValue: true)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Live Summary Strip (always visible under header)
                LiveSummaryStrip(
                    answers: answers,
                    scrollTo: scrollToSection
                )
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                
                // Plan info bar
                if let plan = planSummary {
                    PlanInfoBar(plan: plan)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                
                // Main scrollable content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            // SECTION: Sleep Plan
                            CollapsibleSection(
                                title: "Sleep Plan",
                                icon: "bed.double.fill",
                                isExpanded: $sleepPlanExpanded,
                                id: "sleepPlan"
                            ) {
                                SleepPlanContent(answers: $answers)
                            }
                            
                            // SECTION: Body & Substances
                            CollapsibleSection(
                                title: "Body & Substances",
                                icon: "cup.and.saucer.fill",
                                isExpanded: $bodySubstancesExpanded,
                                id: "bodySubstances"
                            ) {
                                BodySubstancesContent(answers: $answers)
                            }
                            
                            // SECTION: Pain (collapsed if last value was 0)
                            CollapsibleSection(
                                title: "Pain",
                                icon: "bandage.fill",
                                isExpanded: $painExpanded,
                                id: "pain",
                                badge: painBadge
                            ) {
                                PainContent(answers: $answers)
                            }
                            
                            // SECTION: Activity
                            CollapsibleSection(
                                title: "Activity",
                                icon: "figure.run",
                                isExpanded: $activityExpanded,
                                id: "activity"
                            ) {
                                ActivityContent(answers: $answers)
                            }
                            
                            // SECTION: Advanced Details (collapsed by default)
                            CollapsibleSection(
                                title: "Advanced Details",
                                icon: "slider.horizontal.3",
                                isExpanded: $advancedExpanded,
                                id: "advanced"
                            ) {
                                AdvancedDetailsContent(answers: $answers)
                            }
                            
                            // Bottom spacer for sticky bar
                            Spacer().frame(height: 80)
                        }
                        .padding()
                    }
                }
                
                // Sticky Bottom Bar
                StickyBottomBar(
                    leadingAction: {
                        if existingLog == nil {
                            showSkipConfirmation = true
                        } else {
                            dismiss()
                        }
                    },
                    leadingLabel: existingLog == nil ? "Skip Tonight" : "Cancel",
                    trailingAction: saveAndComplete,
                    trailingLabel: "Save"
                )
            }
            .navigationTitle("Pre-Sleep Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        loadLastAnswers()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Use Last")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .alert("Skip Pre-Sleep Check?", isPresented: $showSkipConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Skip Tonight", role: .destructive) {
                do {
                    try onSkip()
                    dismiss()
                } catch {
                    saveErrorMessage = error.localizedDescription
                    showSaveError = true
                }
            }
        } message: {
            Text("Your night will stay active without pre-sleep data logged.")
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .overlay(alignment: .top) {
            if showUseLastApplied {
                UseLastAppliedBanner(changedFields: changedFieldsFromUseLast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { showUseLastApplied = false }
                        }
                    }
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveAndComplete() {
        do {
            try onComplete(answers)
            
            // Save pain snapshot if user reported pain
            if let painLevel = answers.painLevel010, painLevel > 0 {
                let sessionId = sessionRepo.preSleepDisplaySessionKey(for: Date())
                let snapshot = PainSnapshot(
                    context: .preSleep,
                    overallLevel: painLevel,
                    locations: answers.painDetailedLocations ?? [],
                    primaryLocation: answers.painPrimaryLocation,
                    radiation: answers.painRadiation,
                    painWokeUser: false,
                    sessionId: sessionId
                )
                sessionRepo.savePainSnapshot(snapshot)
            }
            
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
    
    private func loadLastAnswers() {
        guard let lastLog = sessionRepo.fetchMostRecentPreSleepLog(),
              let last = lastLog.answers else { return }
        
        var changed: [String] = []
        
        // Copy environment items (stable between nights)
        if answers.roomTemp != last.roomTemp {
            answers.roomTemp = last.roomTemp
            if let val = last.roomTemp { changed.append("Room: \(val.displayText)") }
        }
        if answers.noiseLevel != last.noiseLevel {
            answers.noiseLevel = last.noiseLevel
            if let val = last.noiseLevel { changed.append("Noise: \(val.displayText)") }
        }
        if answers.screensInBed != last.screensInBed {
            answers.screensInBed = last.screensInBed
            if let val = last.screensInBed { changed.append("Screens: \(val.displayText)") }
        }
        if answers.sleepAidsUsed != last.sleepAidsUsed {
            answers.sleepAidsUsed = last.sleepAidsUsed
            if let aids = last.sleepAidsUsed, !aids.isEmpty {
                changed.append("Sleep aids: \(aids.count) items")
            }
        }
        
        if !changed.isEmpty {
            changedFieldsFromUseLast = changed
            withAnimation { showUseLastApplied = true }
        }
    }
    
    private func scrollToSection(_ sectionId: String) {
        // Expand the section and scroll to it
        switch sectionId {
        case "sleepPlan": sleepPlanExpanded = true
        case "bodySubstances": bodySubstancesExpanded = true
        case "pain": painExpanded = true
        case "activity": activityExpanded = true
        case "advanced": advancedExpanded = true
        default: break
        }
    }
    
    private var painBadge: String? {
        if let level = answers.painLevel010, level > 0 {
            return "\(level)/10"
        }
        return nil
    }
    
    private var planSummary: (wakeBy: Date, inBed: Date, windDown: Date, expectedSleep: Double)? {
        let key = sessionRepo.preSleepDisplaySessionKey(for: Date())
        let plan = sleepPlanStore.plan(for: key, now: Date(), tz: TimeZone.current)
        return (plan.wakeBy, plan.recommendedInBed, plan.windDown, plan.expectedSleepMinutes)
    }
}

// MARK: - Live Summary Strip

struct LiveSummaryStrip: View {
    let answers: PreSleepLogAnswers
    let scrollTo: (String) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                SummaryChip(
                    label: "Sleep",
                    value: answers.intendedSleepTime?.displayText ?? "—",
                    action: { scrollTo("sleepPlan") }
                )
                
                SummaryChip(
                    label: "Caffeine",
                    value: caffeineSummary,
                    action: { scrollTo("bodySubstances") }
                )
                
                SummaryChip(
                    label: "Alcohol",
                    value: answers.alcohol?.displayText ?? "—",
                    action: { scrollTo("bodySubstances") }
                )
                
                SummaryChip(
                    label: "Pain",
                    value: painSummary,
                    action: { scrollTo("pain") }
                )
                
                SummaryChip(
                    label: "Exercise",
                    value: answers.exercise?.displayText ?? "—",
                    action: { scrollTo("activity") }
                )
            }
            .padding(.horizontal, 4)
        }
    }
    
    private var caffeineSummary: String {
        if let stims = answers.stimulantsConsumed, !stims.isEmpty {
            let types = stims.map { $0.displayText }.joined(separator: ", ")
            if let time = answers.lastCaffeineTime {
                return "\(types) @ \(time.displayText)"
            }
            return types
        }
        return "None"
    }
    
    private var painSummary: String {
        if let level = answers.painLevel010, level > 0 {
            if let primary = answers.painPrimaryLocation {
                return "\(level)/10 \(primary.compactText)"
            }
            return "\(level)/10"
        }
        return "None"
    }
}

struct SummaryChip: View {
    let label: String
    let value: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plan Info Bar

struct PlanInfoBar: View {
    let plan: (wakeBy: Date, inBed: Date, windDown: Date, expectedSleep: Double)
    
    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }
    
    var body: some View {
        HStack(spacing: 16) {
            PlanItem(label: "Wake by", value: formatter.string(from: plan.wakeBy), icon: "sunrise")
            PlanItem(label: "In bed", value: formatter.string(from: plan.inBed), icon: "bed.double")
            PlanItem(label: "Wind down", value: formatter.string(from: plan.windDown), icon: "moon.stars")
            PlanItem(label: "Planned", value: formatMinutes(plan.expectedSleep), icon: "clock")
        }
        .font(.caption)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func formatMinutes(_ mins: Double) -> String {
        let h = Int(mins) / 60
        let m = Int(mins) % 60
        return "\(h)h \(m)m"
    }
}

struct PlanItem: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.blue)
            Text(value)
                .fontWeight(.semibold)
            Text(label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    let id: String
    var badge: String? = nil
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible, tappable)
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let badge = badge {
                        Text(badge)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange)
                            .cornerRadius(10)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(isExpanded ? 12 : 12)
            }
            .buttonStyle(.plain)
            .id(id)
            
            // Content (only when expanded)
            if isExpanded {
                VStack(spacing: 16) {
                    content
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .cornerRadius(12)
                .padding(.top, -8)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }
}

// MARK: - Sticky Bottom Bar

struct StickyBottomBar: View {
    let leadingAction: () -> Void
    let leadingLabel: String
    let trailingAction: () -> Void
    let trailingLabel: String
    
    var body: some View {
        HStack {
            Button(action: leadingAction) {
                Text(leadingLabel)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: trailingAction) {
                Text(trailingLabel)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
        )
    }
}

// MARK: - Use Last Applied Banner

struct UseLastAppliedBanner: View {
    let changedFields: [String]
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Applied from last night")
                    .fontWeight(.semibold)
            }
            Text(changedFields.joined(separator: " • "))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.15))
        .cornerRadius(12)
        .padding()
    }
}

// MARK: - Section Content Views

struct SleepPlanContent: View {
    @Binding var answers: PreSleepLogAnswers
    
    var body: some View {
        VStack(spacing: 20) {
            // When do you plan to sleep?
            VStack(alignment: .leading, spacing: 8) {
                Text("When do you plan to sleep?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(PreSleepLogAnswers.IntendedSleepTime.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: answers.intendedSleepTime == option,
                            action: { answers.intendedSleepTime = option }
                        )
                    }
                }
            }
            
            // Sleepiness right now
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleepiness right now?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                SleepinessSliderCompact(value: $answers.sleepinessLevel)
            }
            
            // Stress level
            VStack(alignment: .leading, spacing: 8) {
                Text("Stress level?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                StressSliderCompact(value: $answers.stressLevel)
            }
            
            // Stress driver (only if stress >= 4)
            if let stress = answers.stressLevel, stress >= 4 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Main stress driver?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(PreSleepLogAnswers.StressDriver.allCases, id: \.self) { option in
                            OptionButton(
                                label: option.displayText,
                                isSelected: answers.stressDriver == option,
                                action: { answers.stressDriver = option }
                            )
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: answers.stressLevel)
    }
}

struct BodySubstancesContent: View {
    @Binding var answers: PreSleepLogAnswers
    
    var body: some View {
        VStack(spacing: 20) {
            // Caffeine type (MULTI-SELECT - fixed bug)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Caffeine today?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("(select all)")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                CaffeineMultiSelect(selections: Binding(
                    get: { answers.stimulantsConsumed ?? [] },
                    set: { answers.stimulantsConsumed = $0.isEmpty ? nil : $0 }
                ))
            }
            
            // Last caffeine time (only if caffeine selected)
            if let stims = answers.stimulantsConsumed, !stims.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last caffeine?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TimeBucketPickerCompact(selection: $answers.lastCaffeineTime)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Alcohol
            VStack(alignment: .leading, spacing: 8) {
                Text("Alcohol today?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PreSleepLogAnswers.AlcoholLevel.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: answers.alcohol == option,
                            action: { answers.alcohol = option }
                        )
                    }
                }
            }
            
            // Last alcohol time (only if alcohol > none)
            if let alc = answers.alcohol, alc != .none {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last drink?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TimeBucketPickerCompact(selection: $answers.lastAlcoholTime)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: answers.stimulantsConsumed)
        .animation(.easeInOut(duration: 0.2), value: answers.alcohol)
    }
}

struct CaffeineMultiSelect: View {
    @Binding var selections: [PreSleepLogAnswers.Stimulants]
    
    private let options: [PreSleepLogAnswers.Stimulants] = [.coffee, .tea, .soda, .energyDrink]
    
    var body: some View {
        HStack(spacing: 8) {
            // None option
            OptionButton(
                label: "None",
                isSelected: selections.isEmpty,
                action: { selections = [] }
            )
            
            // Caffeine types (multi-select)
            ForEach(options, id: \.self) { option in
                OptionButton(
                    label: option.displayText,
                    isSelected: selections.contains(option),
                    isMultiSelect: true,
                    action: {
                        if selections.contains(option) {
                            selections.removeAll { $0 == option }
                        } else {
                            selections.append(option)
                        }
                    }
                )
            }
        }
    }
}

struct PainContent: View {
    @Binding var answers: PreSleepLogAnswers
    
    var body: some View {
        VStack(spacing: 20) {
            // Pain level (0-10)
            VStack(alignment: .leading, spacing: 8) {
                Text("Pain level right now?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                PainLevelPickerCompact(selectedLevel: $answers.painLevel010)
            }
            
            // Location details (only if pain > 0)
            if let level = answers.painLevel010, level > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Where?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("(select all)")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    
                    PainLocationPickerCompact(
                        selectedLocations: Binding(
                            get: { answers.painDetailedLocations ?? [] },
                            set: { answers.painDetailedLocations = $0.isEmpty ? nil : $0 }
                        ),
                        primaryLocation: $answers.painPrimaryLocation
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                
                // Radiation (for back/neck/leg)
                if shouldShowRadiation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Does the pain radiate?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        RadiationPickerCompact(radiation: $answers.painRadiation)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: answers.painLevel010)
    }
    
    private var shouldShowRadiation: Bool {
        guard let locations = answers.painDetailedLocations else { return false }
        return locations.contains { $0.region.supportsRadiation }
    }
}

struct ActivityContent: View {
    @Binding var answers: PreSleepLogAnswers
    @ObservedObject private var sessionRepo = SessionRepository.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Exercise
            VStack(alignment: .leading, spacing: 8) {
                Text("Exercise today?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PreSleepLogAnswers.ExerciseLevel.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: answers.exercise == option,
                            action: { answers.exercise = option }
                        )
                    }
                }
            }
            
            // Naps - integrated with actual nap events
            VStack(alignment: .leading, spacing: 8) {
                Text("Naps today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                NapSummaryCompact(napSelection: $answers.napToday)
            }
        }
    }
}

struct AdvancedDetailsContent: View {
    @Binding var answers: PreSleepLogAnswers
    
    var body: some View {
        VStack(spacing: 20) {
            // Late meal
            VStack(alignment: .leading, spacing: 8) {
                Text("Late meal?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PreSleepLogAnswers.LateMeal.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: answers.lateMeal == option,
                            action: { answers.lateMeal = option }
                        )
                    }
                }
            }
            
            // Screens in bed
            VStack(alignment: .leading, spacing: 8) {
                Text("Screens in bed?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PreSleepLogAnswers.ScreensInBed.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: answers.screensInBed == option,
                            action: { answers.screensInBed = option }
                        )
                    }
                }
            }
            
            // Room temp
            VStack(alignment: .leading, spacing: 8) {
                Text("Room temperature?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PreSleepLogAnswers.RoomTemp.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: answers.roomTemp == option,
                            action: { answers.roomTemp = option }
                        )
                    }
                }
            }
            
            // Noise level
            VStack(alignment: .leading, spacing: 8) {
                Text("Noise level?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PreSleepLogAnswers.NoiseLevel.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: answers.noiseLevel == option,
                            action: { answers.noiseLevel = option }
                        )
                    }
                }
            }
            
            // Sleep aids (multi-select)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sleep aids?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("(select all)")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                SleepAidsMultiSelect(selections: Binding(
                    get: { answers.sleepAidsUsed ?? [] },
                    set: { answers.sleepAidsUsed = $0.isEmpty ? nil : $0 }
                ))
            }
        }
    }
}

struct SleepAidsMultiSelect: View {
    @Binding var selections: [PreSleepLogAnswers.SleepAid]
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(PreSleepLogAnswers.SleepAid.allCases, id: \.self) { option in
                OptionButton(
                    label: option.displayText,
                    isSelected: selections.contains(option),
                    isMultiSelect: true,
                    action: {
                        if selections.contains(option) {
                            selections.removeAll { $0 == option }
                        } else {
                            selections.append(option)
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Compact UI Components

struct OptionButton: View {
    let label: String
    let isSelected: Bool
    var isMultiSelect: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.blue : Color(.tertiarySystemGroupedBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

struct SleepinessSliderCompact: View {
    @Binding var value: Int?
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { level in
                Button {
                    value = level
                } label: {
                    VStack(spacing: 4) {
                        Text("\(level)")
                            .font(.headline)
                        Text(sleepinessLabel(level))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(value == level ? Color.purple : Color(.tertiarySystemGroupedBackground))
                    .foregroundColor(value == level ? .white : .primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func sleepinessLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Alert"
        case 2: return "OK"
        case 3: return "Drowsy"
        case 4: return "Tired"
        case 5: return "Fighting"
        default: return ""
        }
    }
}

struct StressSliderCompact: View {
    @Binding var value: Int?
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { level in
                Button {
                    value = level
                } label: {
                    Text("\(level)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(value == level ? stressColor(level) : Color(.tertiarySystemGroupedBackground))
                        .foregroundColor(value == level ? .white : .primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        
        if let v = value {
            Text(stressDescription(v))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
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
    
    private func stressDescription(_ level: Int) -> String {
        switch level {
        case 1: return "Calm, relaxed"
        case 2: return "Slightly tense"
        case 3: return "Moderate stress"
        case 4: return "High stress"
        case 5: return "Extremely stressed"
        default: return ""
        }
    }
}

struct TimeBucketPickerCompact: View {
    @Binding var selection: PreSleepLogAnswers.StimulantTime?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PreSleepLogAnswers.StimulantTime.allCases, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(option.displayText)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selection == option ? Color.blue : Color(.tertiarySystemGroupedBackground))
                            .foregroundColor(selection == option ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PainLevelPickerCompact: View {
    @Binding var selectedLevel: Int?
    
    private let quickLevels = [0, 2, 5, 8, 10]
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(quickLevels, id: \.self) { level in
                    Button {
                        selectedLevel = level
                    } label: {
                        Text("\(level)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selectedLevel == level ? painColor(level) : Color(.tertiarySystemGroupedBackground))
                            .foregroundColor(selectedLevel == level ? .white : .primary)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if let level = selectedLevel, level > 0 {
                Text(painDescription(level))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func painColor(_ level: Int) -> Color {
        switch level {
        case 0: return .green
        case 1...3: return .yellow
        case 4...6: return .orange
        case 7...8: return .red
        default: return .purple
        }
    }
    
    private func painDescription(_ level: Int) -> String {
        switch level {
        case 0: return "No pain"
        case 1...3: return "Mild - noticeable but easy to ignore"
        case 4...6: return "Moderate - hard to ignore"
        case 7...8: return "Severe - limits activity"
        default: return "Very severe - unbearable"
        }
    }
}

struct PainLocationPickerCompact: View {
    @Binding var selectedLocations: [PainLocationDetail]
    @Binding var primaryLocation: PainLocationDetail?
    @State private var showingSideSelector: PainRegion?
    
    private let commonRegions: [PainRegion] = [.neck, .shoulder, .upperBack, .midBack, .lowBack, .hip, .knee, .head]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Common locations (quick access)
            PainFlowLayout(spacing: 8) {
                ForEach(commonRegions, id: \.self) { region in
                    painChip(region)
                }
                
                // "Other" expander
                Button {
                    // Could show full picker
                } label: {
                    Text("More...")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .foregroundColor(.secondary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            // Selected locations
            if !selectedLocations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected: \(selectedLocations.map { $0.compactText }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if selectedLocations.count > 1, let primary = primaryLocation {
                        Text("Primary: \(primary.displayText)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .sheet(item: $showingSideSelector) { region in
            SideSelectorSheetCompact(region: region) { side in
                let loc = PainLocationDetail(region: region, side: side)
                selectedLocations.append(loc)
                if selectedLocations.count == 1 {
                    primaryLocation = loc
                }
            }
            .presentationDetents([.height(250)])
        }
    }
    
    private func painChip(_ region: PainRegion) -> some View {
        let isSelected = selectedLocations.contains { $0.region == region }
        
        return Button {
            if isSelected {
                selectedLocations.removeAll { $0.region == region }
                if primaryLocation?.region == region {
                    primaryLocation = selectedLocations.first
                }
            } else {
                if region.supportsLaterality {
                    showingSideSelector = region
                } else {
                    let loc = PainLocationDetail(region: region, side: .center)
                    selectedLocations.append(loc)
                    if selectedLocations.count == 1 {
                        primaryLocation = loc
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

struct SideSelectorSheetCompact: View {
    let region: PainRegion
    let onSelect: (PainSide) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Which side?")
                .font(.headline)
            
            Text(region.displayText)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                ForEach(PainSide.allCases, id: \.self) { side in
                    Button {
                        onSelect(side)
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            Text(side.emoji)
                                .font(.title)
                            Text(side.displayText)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

struct RadiationPickerCompact: View {
    @Binding var radiation: PainRadiation?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PainRadiation.allCases, id: \.self) { rad in
                    Button {
                        radiation = radiation == rad ? nil : rad
                    } label: {
                        Text(rad.displayText)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(radiation == rad ? Color.orange.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                            .foregroundColor(radiation == rad ? .orange : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NapSummaryCompact: View {
    @Binding var napSelection: PreSleepLogAnswers.NapDuration?
    @ObservedObject private var sessionRepo = SessionRepository.shared
    
    private var napsLogged: (count: Int, totalMinutes: Int) {
        sessionRepo.napSummary(for: sessionRepo.plannerSessionKey(for: Date()))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if napsLogged.count > 0 {
                // Show logged naps
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Naps logged: \(napsLogged.count), total \(napsLogged.totalMinutes)m")
                        .font(.subheadline)
                    Spacer()
                    Text("See Tonight events")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                // No naps logged - show quick options
                HStack(spacing: 8) {
                    ForEach(PreSleepLogAnswers.NapDuration.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: napSelection == option,
                            action: { napSelection = option }
                        )
                    }
                }
            }
        }
    }
}

/// Lightweight flow layout used by pain chips/selectors.
struct PainFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        return flowResult(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowResult(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
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

// MARK: - Preview

#Preview {
    PreSleepLogViewV2(
        onComplete: { _ in },
        onSkip: { }
    )
}
