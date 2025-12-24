//
//  MorningCheckInView.swift
//  DoseTap
//
//  Morning questionnaire with progressive disclosure:
//  - Quick Mode: 5 core questions (30 seconds)
//  - Deep Dive: Conditional expansion for symptoms
//

import SwiftUI

// MARK: - Local Enum Definitions (for Xcode app target)
// These mirror the types in DoseCore/MorningCheckIn.swift but are defined locally
// to avoid module dependency issues in the Xcode project

enum RestedLevel: String, CaseIterable {
    case notAtAll = "Not at all"
    case slightly = "Slightly"
    case moderate = "Moderately"
    case well = "Well"
    case veryWell = "Very well"
}

enum GrogginessLevel: String, CaseIterable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
    case cantFunction = "Can't function"
    
    var icon: String {
        switch self {
        case .none: return "sun.max.fill"
        case .mild: return "sun.haze.fill"
        case .moderate: return "cloud.sun.fill"
        case .severe: return "cloud.fill"
        case .cantFunction: return "moon.zzz.fill"
        }
    }
}

enum SleepInertiaDuration: String, CaseIterable {
    case lessThanFive = "<5 minutes"
    case fiveToFifteen = "5-15 minutes"
    case fifteenToThirty = "15-30 minutes"
    case thirtyToSixty = "30-60 minutes"
    case moreThanHour = ">1 hour"
}

enum DreamRecallType: String, CaseIterable {
    case none = "None"
    case vague = "Vague"
    case normal = "Normal"
    case vivid = "Vivid"
    case nightmares = "Nightmares"
    case disturbing = "Disturbing"
}

enum MoodLevel: String, CaseIterable {
    case veryLow = "Very Low"
    case low = "Low"
    case neutral = "Neutral"
    case good = "Good"
    case great = "Great"
    
    var emoji: String {
        switch self {
        case .veryLow: return "😢"
        case .low: return "😔"
        case .neutral: return "😐"
        case .good: return "🙂"
        case .great: return "😊"
        }
    }
}

enum AnxietyLevel: String, CaseIterable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case high = "High"
    case severe = "Severe"
}

enum BodyPart: String, CaseIterable {
    case head = "Head"
    case neck = "Neck"
    case shoulders = "Shoulders"
    case upperBack = "Upper Back"
    case lowerBack = "Lower Back"
    case hips = "Hips"
    case legs = "Legs"
    case knees = "Knees"
    case feet = "Feet"
    case hands = "Hands"
    case arms = "Arms"
    case chest = "Chest"
    case abdomen = "Abdomen"
    
    var icon: String {
        switch self {
        case .head: return "brain.head.profile"
        case .neck: return "figure.stand"
        case .shoulders: return "figure.arms.open"
        case .upperBack, .lowerBack: return "figure.walk"
        case .hips: return "figure.dance"
        case .legs, .knees: return "figure.run"
        case .feet: return "shoeprints.fill"
        case .hands, .arms: return "hand.raised.fill"
        case .chest: return "heart.fill"
        case .abdomen: return "staroflife.fill"
        }
    }
}

enum PainType: String, CaseIterable {
    case aching = "Aching"
    case sharp = "Sharp"
    case stiff = "Stiff"
    case throbbing = "Throbbing"
    case burning = "Burning"
    case tingling = "Tingling"
    case cramping = "Cramping"
}

enum StiffnessLevel: String, CaseIterable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
}

enum SorenessLevel: String, CaseIterable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
}

enum HeadacheSeverity: String, CaseIterable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
    case migraine = "Migraine"
}

enum HeadacheLocation: String, CaseIterable {
    case forehead = "Forehead"
    case temples = "Temples"
    case backOfHead = "Back of Head"
    case behindEyes = "Behind Eyes"
    case allOver = "All Over"
    case oneSide = "One Side"
}

enum CongestionType: String, CaseIterable {
    case none = "None"
    case stuffyNose = "Stuffy Nose"
    case runnyNose = "Runny Nose"
    case both = "Stuffy & Runny"
}

enum ThroatCondition: String, CaseIterable {
    case normal = "Normal"
    case dry = "Dry"
    case sore = "Sore"
    case scratchy = "Scratchy"
}

enum CoughType: String, CaseIterable {
    case none = "None"
    case dry = "Dry Cough"
    case productive = "Productive"
}

enum SinusPressureLevel: String, CaseIterable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
}

enum SicknessLevel: String, CaseIterable {
    case no = "No"
    case comingDown = "Coming down with something"
    case activelySick = "Actively sick"
    case recovering = "Recovering"
}

// MARK: - Sleep Therapy Device Types
enum SleepTherapyDevice: String, CaseIterable, Codable {
    case none = "None"
    case cpap = "CPAP"
    case bipap = "BiPAP"
    case apap = "APAP (Auto)"
    case oxygen = "Oxygen Concentrator"
    case oralAppliance = "Oral Appliance"
    case positionalTherapy = "Positional Therapy"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .none: return "moon.zzz"
        case .cpap, .bipap, .apap: return "wind"
        case .oxygen: return "o.circle.fill"
        case .oralAppliance: return "mouth"
        case .positionalTherapy: return "bed.double"
        case .other: return "questionmark.circle"
        }
    }
    
    var description: String {
        switch self {
        case .none: return "No device used"
        case .cpap: return "Continuous Positive Airway Pressure"
        case .bipap: return "Bilevel Positive Airway Pressure"
        case .apap: return "Auto-adjusting PAP"
        case .oxygen: return "Supplemental oxygen therapy"
        case .oralAppliance: return "Mandibular advancement device"
        case .positionalTherapy: return "Side-sleeping aids"
        case .other: return "Other sleep therapy device"
        }
    }
}

// MARK: - Saved Settings for Persistence
/// Settings that can be remembered between sessions
struct SavedCheckInSettings: Codable {
    var usedSleepTherapy: Bool
    var sleepTherapyDevice: SleepTherapyDevice
}

// MARK: - Morning Check-In View Model
@MainActor
class MorningCheckInViewModel: ObservableObject {
    // Session context
    let sessionId: UUID
    
    // Quick Mode (Always visible)
    @Published var sleepQuality: Int = 3  // 1-5 stars
    @Published var feelRested: RestedLevel = .moderate
    @Published var grogginess: GrogginessLevel = .mild
    @Published var sleepInertiaDuration: SleepInertiaDuration = .fiveToFifteen
    @Published var mentalClarity: Int = 5  // 1-10
    @Published var mood: MoodLevel = .neutral
    @Published var readinessForDay: Int = 3  // 1-5
    
    // Deep Dive toggles
    @Published var hasPhysicalSymptoms: Bool = false
    @Published var hasRespiratorySymptoms: Bool = false
    
    // Physical Symptoms (conditional)
    @Published var painLocations: Set<BodyPart> = []
    @Published var painSeverity: Int = 0
    @Published var painType: PainType = .aching
    @Published var hasHeadache: Bool = false
    @Published var headacheSeverity: HeadacheSeverity = .mild
    @Published var headacheLocation: HeadacheLocation = .forehead
    @Published var isMigraine: Bool = false
    @Published var muscleStiffness: StiffnessLevel = .none
    @Published var muscleSoreness: SorenessLevel = .none
    @Published var painNotes: String = ""  // NEW: Notes for pain symptoms
    
    // Respiratory Symptoms (conditional)
    @Published var congestion: CongestionType = .none
    @Published var throatCondition: ThroatCondition = .normal
    @Published var coughType: CoughType = .none
    @Published var sinusPressure: SinusPressureLevel = .none
    @Published var feelingFeverish: Bool = false
    @Published var sicknessLevel: SicknessLevel = .no
    @Published var respiratoryNotes: String = ""  // NEW: Notes for respiratory symptoms
    
    // Sleep Therapy Device (NEW)
    @Published var usedSleepTherapy: Bool = false
    @Published var sleepTherapyDevice: SleepTherapyDevice = .none
    @Published var sleepTherapyCompliance: Int = 100  // Percentage of night used (0-100)
    @Published var sleepTherapyNotes: String = ""  // e.g., "mask leaked", "removed at 3am"
    
    // Narcolepsy flags (toggle list)
    @Published var hadSleepParalysis: Bool = false
    @Published var hadHallucinations: Bool = false
    @Published var hadAutomaticBehavior: Bool = false
    @Published var fellOutOfBed: Bool = false
    @Published var hadConfusionOnWaking: Bool = false
    
    // Dream recall
    @Published var dreamRecall: DreamRecallType = .none
    
    // Anxiety
    @Published var anxietyLevel: AnxietyLevel = .none
    
    // Notes
    @Published var notes: String = ""
    
    // Persistence preference (NEW)
    @Published var rememberSettings: Bool = false  // Remember last night's settings
    
    // UI state
    @Published var showDeepDive: Bool = false
    @Published var isSubmitting: Bool = false
    @Published var showNarcolepsySection: Bool = false
    @Published var showSleepTherapySection: Bool = false  // NEW
    
    // UserDefaults keys for persistence
    private static let rememberSettingsKey = "morningCheckIn.rememberSettings"
    private static let savedSettingsKey = "morningCheckIn.savedSettings"
    
    init(sessionId: UUID = UUID()) {
        self.sessionId = sessionId
        loadSavedSettings()
    }
    
    /// Load saved settings if "Remember" is enabled
    private func loadSavedSettings() {
        rememberSettings = UserDefaults.standard.bool(forKey: Self.rememberSettingsKey)
        
        if rememberSettings, let data = UserDefaults.standard.data(forKey: Self.savedSettingsKey) {
            if let saved = try? JSONDecoder().decode(SavedCheckInSettings.self, from: data) {
                // Apply saved settings (only the "stable" ones, not symptoms)
                usedSleepTherapy = saved.usedSleepTherapy
                sleepTherapyDevice = saved.sleepTherapyDevice
                showSleepTherapySection = saved.usedSleepTherapy
            }
        }
    }
    
    /// Save current settings for next time
    func saveSettingsForNextTime() {
        UserDefaults.standard.set(rememberSettings, forKey: Self.rememberSettingsKey)
        
        if rememberSettings {
            let settings = SavedCheckInSettings(
                usedSleepTherapy: usedSleepTherapy,
                sleepTherapyDevice: sleepTherapyDevice
            )
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.savedSettingsKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: Self.savedSettingsKey)
        }
    }
    
    /// Convert to storable model
    func toStoredCheckIn() -> StoredMorningCheckIn {
        // Build physical symptoms JSON if needed
        var physicalJson: String? = nil
        if hasPhysicalSymptoms {
            let dict: [String: Any] = [
                "painLocations": painLocations.map { $0.rawValue },
                "painSeverity": painSeverity,
                "painType": painType.rawValue,
                "hasHeadache": hasHeadache,
                "headacheSeverity": headacheSeverity.rawValue,
                "headacheLocation": headacheLocation.rawValue,
                "isMigraine": isMigraine,
                "muscleStiffness": muscleStiffness.rawValue,
                "muscleSoreness": muscleSoreness.rawValue,
                "notes": painNotes  // NEW: Pain notes
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                physicalJson = String(data: data, encoding: .utf8)
            }
        }
        
        // Build respiratory symptoms JSON if needed
        var respiratoryJson: String? = nil
        if hasRespiratorySymptoms {
            let dict: [String: Any] = [
                "congestion": congestion.rawValue,
                "throatCondition": throatCondition.rawValue,
                "coughType": coughType.rawValue,
                "sinusPressure": sinusPressure.rawValue,
                "feelingFeverish": feelingFeverish,
                "sicknessLevel": sicknessLevel.rawValue,
                "notes": respiratoryNotes  // NEW: Respiratory notes
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                respiratoryJson = String(data: data, encoding: .utf8)
            }
        }
        
        // Build sleep therapy JSON if needed (NEW)
        var sleepTherapyJson: String? = nil
        if usedSleepTherapy && sleepTherapyDevice != .none {
            let dict: [String: Any] = [
                "device": sleepTherapyDevice.rawValue,
                "compliance": sleepTherapyCompliance,
                "notes": sleepTherapyNotes
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                sleepTherapyJson = String(data: data, encoding: .utf8)
            }
        }
        
        return StoredMorningCheckIn(
            id: UUID().uuidString,
            sessionId: sessionId.uuidString,
            timestamp: Date(),
            sessionDate: "", // Will be set by EventStorage
            sleepQuality: sleepQuality,
            feelRested: feelRested.rawValue,
            grogginess: grogginess.rawValue,
            sleepInertiaDuration: sleepInertiaDuration.rawValue,
            dreamRecall: dreamRecall.rawValue,
            hasPhysicalSymptoms: hasPhysicalSymptoms,
            physicalSymptomsJson: physicalJson,
            hasRespiratorySymptoms: hasRespiratorySymptoms,
            respiratorySymptomsJson: respiratoryJson,
            mentalClarity: mentalClarity,
            mood: mood.rawValue,
            anxietyLevel: anxietyLevel.rawValue,
            readinessForDay: readinessForDay,
            hadSleepParalysis: hadSleepParalysis,
            hadHallucinations: hadHallucinations,
            hadAutomaticBehavior: hadAutomaticBehavior,
            fellOutOfBed: fellOutOfBed,
            hadConfusionOnWaking: hadConfusionOnWaking,
            usedSleepTherapy: usedSleepTherapy,  // NEW
            sleepTherapyJson: sleepTherapyJson,  // NEW
            notes: notes.isEmpty ? nil : notes
        )
    }
    
    func submit() async {
        isSubmitting = true
        saveSettingsForNextTime()  // NEW: Save settings if "Remember" is enabled
        let checkIn = toStoredCheckIn()
        EventStorage.shared.saveMorningCheckIn(checkIn)
        isSubmitting = false
    }
}

// MARK: - Main View
struct MorningCheckInView: View {
    @StateObject private var viewModel: MorningCheckInViewModel
    @Environment(\.dismiss) private var dismiss
    
    let onComplete: () -> Void
    
    init(sessionId: UUID = UUID(), onComplete: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: MorningCheckInViewModel(sessionId: sessionId))
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Quick Mode (always visible)
                    quickModeSection
                    
                    // Symptom toggles
                    symptomTogglesSection
                    
                    // Conditional Deep Dive
                    if viewModel.hasPhysicalSymptoms {
                        physicalSymptomsSection
                    }
                    
                    if viewModel.hasRespiratorySymptoms {
                        respiratorySymptomsSection
                    }
                    
                    // Sleep Therapy section (NEW - expandable)
                    sleepTherapySection
                    
                    // Narcolepsy section (expandable)
                    narcolepsySection
                    
                    // Notes
                    notesSection
                    
                    // Remember Settings (NEW)
                    rememberSettingsSection
                    
                    // Submit button
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
        }
    }
    
    // MARK: - Header Section
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
    
    // MARK: - Quick Mode Section
    private var quickModeSection: some View {
        VStack(spacing: 20) {
            // Sleep Quality Stars
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
            
            // Feel Rested
            cardView(title: "How Rested Do You Feel?", icon: "battery.100") {
                restedPicker
            }
            
            // Grogginess
            cardView(title: "Morning Grogginess", icon: "cloud.sun.fill") {
                grogginessPicker
            }
            
            // Mental Clarity Slider
            cardView(title: "Mental Clarity", icon: "brain.head.profile") {
                VStack(spacing: 8) {
                    HStack {
                        Text("Foggy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Sharp")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(viewModel.mentalClarity) },
                        set: { viewModel.mentalClarity = Int($0) }
                    ), in: 1...10, step: 1)
                    .tint(.purple)
                    
                    Text("\(viewModel.mentalClarity)/10")
                        .font(.headline)
                        .foregroundColor(.purple)
                }
            }
            
            // Mood
            cardView(title: "Mood", icon: "face.smiling") {
                moodPicker
            }
        }
    }
    
    // MARK: - Symptom Toggles Section
    private var symptomTogglesSection: some View {
        VStack(spacing: 12) {
            Text("Any Issues?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                symptomToggleButton(
                    title: "Physical Pain",
                    icon: "figure.wave",
                    isActive: viewModel.hasPhysicalSymptoms
                ) {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.hasPhysicalSymptoms.toggle()
                    }
                }
                
                symptomToggleButton(
                    title: "Sick/Respiratory",
                    icon: "lungs.fill",
                    isActive: viewModel.hasRespiratorySymptoms
                ) {
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
    
    // MARK: - Physical Symptoms Section
    private var physicalSymptomsSection: some View {
        VStack(spacing: 16) {
            Text("Physical Symptoms")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Pain locations grid
            cardView(title: "Where does it hurt?", icon: "figure.arms.open") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(BodyPart.allCases, id: \.self) { part in
                        bodyPartButton(part)
                    }
                }
            }
            
            // Pain severity
            if !viewModel.painLocations.isEmpty {
                cardView(title: "Pain Severity", icon: "gauge.with.dots.needle.bottom.50percent") {
                    VStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { Double(viewModel.painSeverity) },
                            set: { viewModel.painSeverity = Int($0) }
                        ), in: 0...10, step: 1)
                        .tint(.red)
                        
                        Text("\(viewModel.painSeverity)/10")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                }
                
                // Pain type
                cardView(title: "Type of Pain", icon: "waveform.path") {
                    painTypePicker
                }
            }
            
            // Headache detail
            Toggle("Headache", isOn: $viewModel.hasHeadache)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            
            if viewModel.hasHeadache {
                cardView(title: "Headache Details", icon: "brain.head.profile") {
                    VStack(spacing: 12) {
                        headacheSeverityPicker
                        headacheLocationPicker
                        Toggle("Migraine", isOn: $viewModel.isMigraine)
                    }
                }
            }
            
            // Muscle stiffness/soreness
            HStack(spacing: 12) {
                cardView(title: "Stiffness", icon: "figure.walk") {
                    stiffnessPicker
                }
                cardView(title: "Soreness", icon: "figure.run") {
                    sorenessPicker
                }
            }
            
            // Pain Notes (NEW)
            cardView(title: "Pain Notes", icon: "note.text") {
                TextField("Describe your pain (location, triggers, etc.)", text: $viewModel.painNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }
    
    // MARK: - Respiratory Symptoms Section
    private var respiratorySymptomsSection: some View {
        VStack(spacing: 16) {
            Text("Respiratory / Illness")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            cardView(title: "Nose", icon: "wind") {
                congestionPicker
            }
            
            cardView(title: "Throat", icon: "mouth") {
                throatPicker
            }
            
            cardView(title: "Cough", icon: "waveform") {
                coughPicker
            }
            
            cardView(title: "Sinus Pressure", icon: "face.dashed") {
                sinusPicker
            }
            
            Toggle("Feeling Feverish", isOn: $viewModel.feelingFeverish)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            
            cardView(title: "Sick?", icon: "cross.case") {
                sicknessPicker
            }
            
            // Respiratory Notes (NEW)
            cardView(title: "Respiratory Notes", icon: "note.text") {
                TextField("Describe symptoms (when started, severity, etc.)", text: $viewModel.respiratoryNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }
    
    // MARK: - Narcolepsy Section
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
                    narcolepsyToggle("Sleep Paralysis", isOn: $viewModel.hadSleepParalysis)
                    narcolepsyToggle("Hallucinations", isOn: $viewModel.hadHallucinations)
                    narcolepsyToggle("Automatic Behavior", isOn: $viewModel.hadAutomaticBehavior)
                    narcolepsyToggle("Fell Out of Bed", isOn: $viewModel.fellOutOfBed)
                    narcolepsyToggle("Confusion on Waking", isOn: $viewModel.hadConfusionOnWaking)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func narcolepsyToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(SwitchToggleStyle(tint: .indigo))
    }
    
    // MARK: - Sleep Therapy Section (NEW)
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
                    if viewModel.usedSleepTherapy {
                        Text(viewModel.sleepTherapyDevice.rawValue)
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                    Image(systemName: viewModel.showSleepTherapySection ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            
            if viewModel.showSleepTherapySection {
                VStack(spacing: 16) {
                    // Did you use a device?
                    Toggle("Used Sleep Therapy Device", isOn: $viewModel.usedSleepTherapy.animation(.spring(response: 0.3)))
                        .toggleStyle(SwitchToggleStyle(tint: .cyan))
                    
                    if viewModel.usedSleepTherapy {
                        // Device type picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Device Type")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(SleepTherapyDevice.allCases.filter { $0 != .none }, id: \.self) { device in
                                        deviceButton(device)
                                    }
                                }
                            }
                        }
                        
                        // Compliance slider
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How much of the night?")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Slider(value: Binding(
                                    get: { Double(viewModel.sleepTherapyCompliance) },
                                    set: { viewModel.sleepTherapyCompliance = Int($0) }
                                ), in: 0...100, step: 10)
                                .tint(.cyan)
                                
                                Text("\(viewModel.sleepTherapyCompliance)%")
                                    .font(.headline)
                                    .foregroundColor(.cyan)
                                    .frame(width: 50)
                            }
                        }
                        
                        // Notes
                        TextField("Notes (mask issues, removed early, etc.)", text: $viewModel.sleepTherapyNotes, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func deviceButton(_ device: SleepTherapyDevice) -> some View {
        Button {
            viewModel.sleepTherapyDevice = device
        } label: {
            VStack(spacing: 4) {
                Image(systemName: device.icon)
                    .font(.title3)
                Text(device.rawValue)
                    .font(.caption2)
            }
            .frame(width: 70, height: 60)
            .background(viewModel.sleepTherapyDevice == device ? Color.cyan.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
            .foregroundColor(viewModel.sleepTherapyDevice == device ? .cyan : .secondary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(viewModel.sleepTherapyDevice == device ? Color.cyan : Color.clear, lineWidth: 2)
            )
        }
    }
    
    // MARK: - Remember Settings Section (NEW)
    private var rememberSettingsSection: some View {
        HStack {
            Image(systemName: viewModel.rememberSettings ? "checkmark.square.fill" : "square")
                .foregroundColor(viewModel.rememberSettings ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Remember my device settings")
                    .font(.subheadline)
                Text("Pre-fill sleep therapy for next time")
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
                viewModel.rememberSettings.toggle()
            }
        }
    }

    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
            
            TextField("Anything else to note?", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    // MARK: - Submit Button
    private var submitButton: some View {
        Button {
            Task {
                await viewModel.submit()
                dismiss()
                onComplete()
            }
        } label: {
            HStack {
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(.white)
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
        .disabled(viewModel.isSubmitting)
        .padding(.top, 8)
    }
    
    // MARK: - Helper Views
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
    
    private func bodyPartButton(_ part: BodyPart) -> some View {
        let isSelected = viewModel.painLocations.contains(part)
        return Button {
            if isSelected {
                viewModel.painLocations.remove(part)
            } else {
                viewModel.painLocations.insert(part)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: part.icon)
                    .font(.title3)
                Text(part.rawValue)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.red.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
            .foregroundColor(isSelected ? .red : .secondary)
            .cornerRadius(8)
        }
    }
    
    // MARK: - Pickers
    private var restedPicker: some View {
        Picker("Rested", selection: $viewModel.feelRested) {
            ForEach(RestedLevel.allCases, id: \.self) { level in
                Text(level.rawValue).tag(level)
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
    
    private var moodPicker: some View {
        HStack(spacing: 8) {
            ForEach(MoodLevel.allCases, id: \.self) { level in
                Button {
                    viewModel.mood = level
                } label: {
                    VStack(spacing: 4) {
                        Text(level.emoji)
                            .font(.title)
                        Text(level.rawValue)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(viewModel.mood == level ? Color.blue.opacity(0.2) : Color.clear)
                    .foregroundColor(viewModel.mood == level ? .blue : .secondary)
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var painTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PainType.allCases, id: \.self) { type in
                    Button {
                        viewModel.painType = type
                    } label: {
                        Text(type.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(viewModel.painType == type ? Color.red.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                            .foregroundColor(viewModel.painType == type ? .red : .secondary)
                            .cornerRadius(16)
                    }
                }
            }
        }
    }
    
    private var headacheSeverityPicker: some View {
        Picker("Severity", selection: $viewModel.headacheSeverity) {
            ForEach(HeadacheSeverity.allCases, id: \.self) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var headacheLocationPicker: some View {
        Picker("Location", selection: $viewModel.headacheLocation) {
            ForEach(HeadacheLocation.allCases, id: \.self) { loc in
                Text(loc.rawValue).tag(loc)
            }
        }
        .pickerStyle(.menu)
    }
    
    private var stiffnessPicker: some View {
        Picker("", selection: $viewModel.muscleStiffness) {
            ForEach(StiffnessLevel.allCases, id: \.self) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.menu)
    }
    
    private var sorenessPicker: some View {
        Picker("", selection: $viewModel.muscleSoreness) {
            ForEach(SorenessLevel.allCases, id: \.self) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.menu)
    }
    
    private var congestionPicker: some View {
        Picker("", selection: $viewModel.congestion) {
            ForEach(CongestionType.allCases, id: \.self) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var throatPicker: some View {
        Picker("", selection: $viewModel.throatCondition) {
            ForEach(ThroatCondition.allCases, id: \.self) { cond in
                Text(cond.rawValue).tag(cond)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var coughPicker: some View {
        Picker("", selection: $viewModel.coughType) {
            ForEach(CoughType.allCases, id: \.self) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var sinusPicker: some View {
        Picker("", selection: $viewModel.sinusPressure) {
            ForEach(SinusPressureLevel.allCases, id: \.self) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var sicknessPicker: some View {
        Picker("", selection: $viewModel.sicknessLevel) {
            ForEach(SicknessLevel.allCases, id: \.self) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Preview
#Preview {
    MorningCheckInView()
}
