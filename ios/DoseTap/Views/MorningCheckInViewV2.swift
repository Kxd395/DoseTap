//
//  MorningCheckInViewV2.swift
//  DoseTap
//
//  Single-page Morning Wake Check-in
//  Closes the night, finalizes rollover, preps next night
//  - Quick outcome capture in 10 seconds
//  - Pain delta from pre-sleep
//  - Night events review (read-only)
//  - End Night + Save button that closes session
//

import SwiftUI

// MARK: - Morning Check-In View (Single Page)

struct MorningCheckInViewV2: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = MorningCheckInViewModelV2()
    @State private var showSkipConfirmation = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    
    // Section expansion states
    @State private var quickOutcomeExpanded = true
    @State private var painExpanded = true
    @State private var nightReviewExpanded = false
    @State private var disruptionExpanded = false
    
    @ObservedObject private var sessionRepo = SessionRepository.shared
    
    let sessionId: String
    let sessionDate: String
    let onComplete: () -> Void
    
    init(sessionId: String, sessionDate: String, onComplete: @escaping () -> Void) {
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Night Info Header
                NightInfoHeaderV2(sessionId: sessionId, sessionDate: sessionDate)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                
                // Main scrollable content
                ScrollView {
                    VStack(spacing: 16) {
                        // SECTION: Quick Outcome (fast, 10 seconds)
                        CollapsibleSection(
                            title: "Quick Outcome",
                            icon: "sparkles",
                            isExpanded: $quickOutcomeExpanded,
                            id: "quickOutcome"
                        ) {
                            QuickOutcomeContentV2(viewModel: viewModel)
                        }
                        
                        // SECTION: Pain on Waking
                        CollapsibleSection(
                            title: "Pain on Waking",
                            icon: "bandage.fill",
                            isExpanded: $painExpanded,
                            id: "pain",
                            badge: viewModel.wakePainLevel.map { "\($0)/10" }
                        ) {
                            WakePainContentV2(viewModel: viewModel)
                        }
                        
                        // SECTION: Night Events Review (read-only)
                        CollapsibleSection(
                            title: "Night Events",
                            icon: "moon.stars",
                            isExpanded: $nightReviewExpanded,
                            id: "nightReview"
                        ) {
                            NightEventsReviewV2(sessionId: sessionId, sessionDate: sessionDate)
                        }
                        
                        // SECTION: Sleep Disruption (optional)
                        CollapsibleSection(
                            title: "Sleep Disruption",
                            icon: "exclamationmark.triangle",
                            isExpanded: $disruptionExpanded,
                            id: "disruption"
                        ) {
                            SleepDisruptionContentV2(viewModel: viewModel)
                        }
                        
                        // Notes (optional)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes (optional)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            TextField("How was your night?", text: $viewModel.notes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                        }
                        .padding()
                        .background(Color(.systemGroupedBackground))
                        .cornerRadius(12)
                        
                        // Bottom spacer for sticky bar
                        Spacer().frame(height: 100)
                    }
                    .padding()
                }
                
                // Sticky Bottom Bar with End Night + Save
                EndNightBottomBar(
                    onSkip: { showSkipConfirmation = true },
                    onSave: endNightAndSave
                )
            }
            .navigationTitle("Morning Check-in")
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
        .alert("Skip Morning Check-in?", isPresented: $showSkipConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Skip", role: .destructive) {
                // Still close the session even if skipped
                closeSessionWithoutSurvey()
            }
        } message: {
            Text("The night will be closed without wake survey data.")
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .onAppear {
            viewModel.loadPreSleepPain(sessionId: sessionId)
        }
    }
    
    // MARK: - Actions
    
    private func endNightAndSave() {
        do {
            // 1. Persist wake survey event
            try viewModel.saveWakeSurvey(sessionId: sessionId, sessionDate: sessionDate)
            
            // 2. Save pain snapshot if reported
            if let painLevel = viewModel.wakePainLevel, painLevel > 0 {
                let snapshot = PainSnapshot(
                    context: .wake,
                    overallLevel: painLevel,
                    locations: viewModel.wakePainLocations,
                    primaryLocation: viewModel.wakePainPrimary,
                    radiation: viewModel.wakePainRadiation,
                    painWokeUser: viewModel.painWokeUser,
                    sessionId: sessionId
                )
                EventStorage.shared.savePainSnapshot(snapshot)
            }
            
            // 3. Mark session closed via SessionRepository
            sessionRepo.completeCheckIn()
            
            // 4. Log diagnostic event
            EventStorage.shared.insertSleepEvent(
                eventType: "session_closed",
                timestamp: Date(),
                sessionDate: sessionDate,
                sessionId: sessionId,
                notes: "{\"reason\":\"wake_survey_submit\"}"
            )
            
            // 5. Transition to day mode
            onComplete()
            dismiss()
            
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
    
    private func closeSessionWithoutSurvey() {
        // Mark session as skipped
        sessionRepo.completeCheckIn()
        
        EventStorage.shared.insertSleepEvent(
            eventType: "session_closed",
            timestamp: Date(),
            sessionDate: sessionDate,
            sessionId: sessionId,
            notes: "{\"reason\":\"wake_survey_skipped\"}"
        )
        
        onComplete()
        dismiss()
    }
    
    private func loadLastAnswers() {
        // Load from last wake survey
        // TODO: Implement
    }
}

// MARK: - View Model

@MainActor
class MorningCheckInViewModelV2: ObservableObject {
    // Quick Outcome
    @Published var feelingNow: Feeling = .ok
    @Published var sleepQuality: Int = 3
    @Published var sleepinessNow: Int = 2
    
    // Pain
    @Published var wakePainLevel: Int? = nil
    @Published var wakePainLocations: [PainLocationDetail] = []
    @Published var wakePainPrimary: PainLocationDetail? = nil
    @Published var wakePainRadiation: PainRadiation? = nil
    @Published var painWokeUser: Bool = false
    @Published var painDelta: PainDelta? = nil
    
    // Pre-sleep pain baseline (loaded)
    @Published var preSleepPainLevel: Int? = nil
    @Published var preSleepPainLocation: PainLocationDetail? = nil
    
    // Sleep Disruption
    @Published var awakeningsCount: AwakeningsCount = .none
    @Published var longAwakePeriod: LongAwakePeriod = .none
    @Published var dreamIntensity: DreamIntensity? = nil
    
    // Notes
    @Published var notes: String = ""
    
    enum Feeling: String, CaseIterable {
        case great = "Great"
        case ok = "OK"
        case rough = "Rough"
        
        var emoji: String {
            switch self {
            case .great: return "😊"
            case .ok: return "😐"
            case .rough: return "😫"
            }
        }
        
        var color: Color {
            switch self {
            case .great: return .green
            case .ok: return .yellow
            case .rough: return .red
            }
        }
    }
    
    enum PainDelta: String, CaseIterable {
        case muchBetter = "Much Better"
        case better = "Better"
        case same = "Same"
        case worse = "Worse"
        case muchWorse = "Much Worse"
        
        var emoji: String {
            switch self {
            case .muchBetter: return "🎉"
            case .better: return "⬆️"
            case .same: return "↔️"
            case .worse: return "⬇️"
            case .muchWorse: return "😣"
            }
        }
        
        var levelAdjustment: Int {
            switch self {
            case .muchBetter: return -3
            case .better: return -1
            case .same: return 0
            case .worse: return 1
            case .muchWorse: return 3
            }
        }
    }
    
    enum AwakeningsCount: String, CaseIterable {
        case none = "No"
        case oneTwo = "1-2"
        case threeFour = "3-4"
        case fivePlus = "5+"
        
        var displayText: String { rawValue }
    }
    
    enum LongAwakePeriod: String, CaseIterable {
        case none = "None"
        case lessThan15 = "<15m"
        case fifteenToSixty = "15-60m"
        case overHour = "1h+"
        
        var displayText: String { rawValue }
    }
    
    enum DreamIntensity: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        
        var displayText: String { rawValue }
    }
    
    func loadPreSleepPain(sessionId: String) {
        // Load pre-sleep pain from storage
        if let snapshot = EventStorage.shared.getPainSnapshot(sessionId: sessionId, context: .preSleep) {
            preSleepPainLevel = snapshot.overallLevel
            preSleepPainLocation = snapshot.primaryLocation
        }
    }
    
    func saveWakeSurvey(sessionId: String, sessionDate: String) throws {
        // Build payload JSON
        let payloadDict: [String: Any] = [
            "feeling": feelingNow.rawValue,
            "sleep_quality": sleepQuality,
            "sleepiness_now": sleepinessNow,
            "pain_level": wakePainLevel ?? 0,
            "pain_woke_user": painWokeUser,
            "awakenings": awakeningsCount.rawValue,
            "long_awake": longAwakePeriod.rawValue,
            "notes": notes
        ]
        
        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict)
        let payloadJson = String(data: payloadData, encoding: .utf8)
        
        // Save via EventStorage sleep event
        EventStorage.shared.insertSleepEvent(
            eventType: "wake_survey",
            timestamp: Date(),
            sessionDate: sessionDate,
            sessionId: sessionId,
            notes: payloadJson
        )
    }
}

// MARK: - Night Info Header

struct NightInfoHeaderV2: View {
    let sessionId: String
    let sessionDate: String
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Night Session")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(sessionDate)
                    .font(.subheadline.monospaced())
            }
            
            Divider().frame(height: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Started")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(startTime)
                    .font(.subheadline)
            }
            
            Divider().frame(height: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Doses")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text(dosesSummary)
                        .font(.subheadline)
                    if hasLateDose {
                        Text("(Late)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private var sessionIdDisplay: String {
        sessionId
    }
    
    private var startTime: String {
        // TODO: Load from session data
        return "—"
    }
    
    private var dosesSummary: String {
        // TODO: Get actual dose count from session
        return "2"
    }
    
    private var hasLateDose: Bool {
        // TODO: Check if dose 2 was late
        return false
    }
}

// MARK: - Quick Outcome Content

struct QuickOutcomeContentV2: View {
    @ObservedObject var viewModel: MorningCheckInViewModelV2
    
    var body: some View {
        VStack(spacing: 20) {
            // How do you feel right now?
            VStack(alignment: .leading, spacing: 8) {
                Text("How do you feel right now?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    ForEach(MorningCheckInViewModelV2.Feeling.allCases, id: \.self) { feeling in
                        Button {
                            viewModel.feelingNow = feeling
                        } label: {
                            VStack(spacing: 6) {
                                Text(feeling.emoji)
                                    .font(.title)
                                Text(feeling.rawValue)
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(viewModel.feelingNow == feeling ? feeling.color.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(viewModel.feelingNow == feeling ? feeling.color : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Sleep quality overall
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep quality overall")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            viewModel.sleepQuality = level
                        } label: {
                            Text("\(level)")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(viewModel.sleepQuality == level ? Color.blue : Color(.tertiarySystemGroupedBackground))
                                .foregroundColor(viewModel.sleepQuality == level ? .white : .primary)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                HStack {
                    Text("Poor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Excellent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Sleepiness now
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleepiness right now")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            viewModel.sleepinessNow = level
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(level)")
                                    .font(.headline)
                                Text(sleepinessLabel(level))
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(viewModel.sleepinessNow == level ? Color.purple : Color(.tertiarySystemGroupedBackground))
                            .foregroundColor(viewModel.sleepinessNow == level ? .white : .primary)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
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

// MARK: - Wake Pain Content

struct WakePainContentV2: View {
    @ObservedObject var viewModel: MorningCheckInViewModelV2
    
    var body: some View {
        VStack(spacing: 20) {
            // Pre-sleep pain baseline (if exists)
            if let preSleepLevel = viewModel.preSleepPainLevel, preSleepLevel > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pre-sleep pain")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("\(preSleepLevel)/10")
                            .font(.headline)
                        if let loc = viewModel.preSleepPainLocation {
                            Text("– \(loc.compactText)")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                    
                    // Quick delta buttons
                    Text("Compared to pre-sleep:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(MorningCheckInViewModelV2.PainDelta.allCases, id: \.self) { delta in
                            Button {
                                viewModel.painDelta = delta
                                // Auto-calculate wake pain level
                                let newLevel = max(0, min(10, preSleepLevel + delta.levelAdjustment))
                                viewModel.wakePainLevel = newLevel
                                // Copy location from pre-sleep
                                if let loc = viewModel.preSleepPainLocation {
                                    viewModel.wakePainLocations = [loc]
                                    viewModel.wakePainPrimary = loc
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Text(delta.emoji)
                                        .font(.title3)
                                    Text(delta.rawValue)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(viewModel.painDelta == delta ? Color.blue : Color(.tertiarySystemGroupedBackground))
                                .foregroundColor(viewModel.painDelta == delta ? .white : .primary)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Divider()
            }
            
            // Pain level now
            VStack(alignment: .leading, spacing: 8) {
                Text("Pain level now")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                PainLevelPickerCompact(selectedLevel: $viewModel.wakePainLevel)
            }
            
            // Pain woke me up toggle
            Toggle(isOn: $viewModel.painWokeUser) {
                HStack {
                    Image(systemName: "moon.stars.fill")
                        .foregroundColor(.purple)
                    Text("Pain woke me up during the night")
                        .font(.subheadline)
                }
            }
            .tint(.purple)
            
            // Location details (if pain > 0)
            if let level = viewModel.wakePainLevel, level > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    PainLocationPickerCompact(
                        selectedLocations: $viewModel.wakePainLocations,
                        primaryLocation: $viewModel.wakePainPrimary
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.wakePainLevel)
    }
}

// MARK: - Night Events Review

struct NightEventsReviewV2: View {
    let sessionId: String
    let sessionDate: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Dose summary
            HStack {
                Label("Dose 1", systemImage: "1.circle.fill")
                    .font(.subheadline)
                Spacer()
                Text(dose1Time)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Dose 2", systemImage: "2.circle.fill")
                    .font(.subheadline)
                Spacer()
                Text(dose2Time)
                    .foregroundColor(dose2Late ? .orange : .secondary)
                if dose2Late {
                    Text("(Late)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            HStack {
                Label("Interval", systemImage: "arrow.left.and.right")
                    .font(.subheadline)
                Spacer()
                Text(interval)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Pre-sleep summary
            HStack {
                Label("Sleep plan", systemImage: "bed.double")
                    .font(.subheadline)
                Spacer()
                Text(sleepPlan)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Caffeine", systemImage: "cup.and.saucer")
                    .font(.subheadline)
                Spacer()
                Text(caffeineSummary)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Alcohol", systemImage: "wineglass")
                    .font(.subheadline)
                Spacer()
                Text(alcoholSummary)
                    .foregroundColor(.secondary)
            }
            
            // Edit button
            Button {
                // Open night details editor
            } label: {
                HStack {
                    Image(systemName: "pencil")
                    Text("Edit night details")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
    
    // TODO: Implement actual data fetching
    private var dose1Time: String { "11:05 PM" }
    private var dose2Time: String { "2:41 AM" }
    private var dose2Late: Bool { true }
    private var interval: String { "3h 36m" }
    private var sleepPlan: String { "Now" }
    private var caffeineSummary: String { "Coffee @ 4pm" }
    private var alcoholSummary: String { "None" }
}

// MARK: - Sleep Disruption Content

struct SleepDisruptionContentV2: View {
    @ObservedObject var viewModel: MorningCheckInViewModelV2
    
    var body: some View {
        VStack(spacing: 20) {
            // Awakenings count
            VStack(alignment: .leading, spacing: 8) {
                Text("Woke up during the night?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(MorningCheckInViewModelV2.AwakeningsCount.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: viewModel.awakeningsCount == option,
                            action: { viewModel.awakeningsCount = option }
                        )
                    }
                }
            }
            
            // Long awake period
            VStack(alignment: .leading, spacing: 8) {
                Text("Long awake period?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(MorningCheckInViewModelV2.LongAwakePeriod.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: viewModel.longAwakePeriod == option,
                            action: { viewModel.longAwakePeriod = option }
                        )
                    }
                }
            }
            
            // Dream intensity (optional)
            VStack(alignment: .leading, spacing: 8) {
                Text("Dream intensity (optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(MorningCheckInViewModelV2.DreamIntensity.allCases, id: \.self) { option in
                        OptionButton(
                            label: option.displayText,
                            isSelected: viewModel.dreamIntensity == option,
                            action: { viewModel.dreamIntensity = option }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - End Night Bottom Bar

struct EndNightBottomBar: View {
    let onSkip: () -> Void
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // Main action bar
            HStack {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onSave) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("End Night + Save")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .cornerRadius(12)
                }
            }
            
            // Helper text
            Text("Closes session and prepares next night")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
        )
    }
}

// MARK: - Preview

#Preview {
    MorningCheckInViewV2(
        sessionId: "preview-session",
        sessionDate: "2026-01-14",
        onComplete: { }
    )
}
