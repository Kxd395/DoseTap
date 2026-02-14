//
//  MorningCheckInView.swift
//  DoseTap
//
//  Morning questionnaire with progressive disclosure:
//  - Quick Mode: 5 core questions (30 seconds)
//  - Deep Dive: Conditional expansion for symptoms
//

import SwiftUI
import Combine

// Note: Enums are inlined here to avoid module dependency issues in the original 
// project structure, but use the unified SQLiteStoredMorningCheckIn from DoseModels.

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
}

struct SavedCheckInSettings: Codable {
    var usedSleepTherapy: Bool
    var sleepTherapyDevice: SleepTherapyDevice
}

// MARK: - Morning Check-In View Model
@MainActor
class MorningCheckInViewModel: ObservableObject {
    let sessionId: String
    let sessionDate: String
    
    @Published var sleepQuality: Int = 3
    @Published var feelRested: RestedLevel = .moderate
    @Published var grogginess: GrogginessLevel = .mild
    @Published var sleepInertiaDuration: SleepInertiaDuration = .fiveToFifteen
    @Published var mentalClarity: Int = 5
    @Published var mood: MoodLevel = .neutral
    @Published var readinessForDay: Int = 3
    
    @Published var hasPhysicalSymptoms: Bool = false
    @Published var hasRespiratorySymptoms: Bool = false
    @Published var painEntries: [PreSleepLogAnswers.PainEntry] = []
    @Published var painLocations: Set<BodyPart> = []
    @Published var painSeverity: Int = 0
    @Published var painType: PainType = .aching
    @Published var hasHeadache: Bool = false
    @Published var headacheSeverity: HeadacheSeverity = .mild
    @Published var headacheLocation: HeadacheLocation = .forehead
    @Published var isMigraine: Bool = false
    @Published var muscleStiffness: StiffnessLevel = .none
    @Published var muscleSoreness: SorenessLevel = .none
    @Published var painNotes: String = ""
    @Published var congestion: CongestionType = .none
    @Published var throatCondition: ThroatCondition = .normal
    @Published var coughType: CoughType = .none
    @Published var sinusPressure: SinusPressureLevel = .none
    @Published var feelingFeverish: Bool = false
    @Published var sicknessLevel: SicknessLevel = .no
    @Published var respiratoryNotes: String = ""
    @Published var usedSleepTherapy: Bool = false
    @Published var sleepTherapyDevice: SleepTherapyDevice = .none
    @Published var sleepTherapyCompliance: Int = 100
    @Published var sleepTherapyNotes: String = ""
    @Published var hadSleepParalysis: Bool = false
    @Published var hadHallucinations: Bool = false
    @Published var hadAutomaticBehavior: Bool = false
    @Published var fellOutOfBed: Bool = false
    @Published var hadConfusionOnWaking: Bool = false
    @Published var dreamRecall: DreamRecallType = .none
    @Published var anxietyLevel: AnxietyLevel = .none
    @Published var notes: String = ""
    @Published var rememberSettings: Bool = false
    @Published var showDeepDive: Bool = false
    @Published var isSubmitting: Bool = false
    @Published var showNarcolepsySection: Bool = false
    @Published var showSleepTherapySection: Bool = false
    
    private static let rememberSettingsKey = "morningCheckIn.rememberSettings"
    private static let savedSettingsKey = "morningCheckIn.savedSettings"
    
    init(sessionId: String, sessionDate: String) {
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        loadSavedSettings()
    }
    
    private func loadSavedSettings() {
        rememberSettings = UserDefaults.standard.bool(forKey: Self.rememberSettingsKey)
        if rememberSettings, let data = UserDefaults.standard.data(forKey: Self.savedSettingsKey) {
            if let saved = try? JSONDecoder().decode(SavedCheckInSettings.self, from: data) {
                usedSleepTherapy = saved.usedSleepTherapy
                sleepTherapyDevice = saved.sleepTherapyDevice
                showSleepTherapySection = saved.usedSleepTherapy
            }
        }
    }
    
    func saveSettingsForNextTime() {
        UserDefaults.standard.set(rememberSettings, forKey: Self.rememberSettingsKey)
        if rememberSettings {
            let settings = SavedCheckInSettings(usedSleepTherapy: usedSleepTherapy, sleepTherapyDevice: sleepTherapyDevice)
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.savedSettingsKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: Self.savedSettingsKey)
        }
    }
    
    func toStoredCheckIn() -> SQLiteStoredMorningCheckIn {
        syncLegacyPainSummary()
        var physicalJson: String? = nil
        if hasPhysicalSymptoms {
            let painPayload = painEntries.map { entry -> [String: Any] in
                var item: [String: Any] = [
                    "entry_key": entry.entryKey,
                    "area": entry.area.rawValue,
                    "side": entry.side.rawValue,
                    "intensity": entry.intensity,
                    "sensations": entry.sensations.map(\.rawValue)
                ]
                if let pattern = entry.pattern {
                    item["pattern"] = pattern.rawValue
                }
                if let notes = entry.notes, !notes.isEmpty {
                    item["notes"] = notes
                }
                return item
            }

            let dict: [String: Any] = [
                "painEntries": painPayload,
                "painLocations": painLocations.map { $0.rawValue },
                "painSeverity": painSeverity,
                "painType": painType.rawValue,
                "hasHeadache": hasHeadache,
                "headacheSeverity": headacheSeverity.rawValue,
                "headacheLocation": headacheLocation.rawValue,
                "isMigraine": isMigraine,
                "muscleStiffness": muscleStiffness.rawValue,
                "muscleSoreness": muscleSoreness.rawValue,
                "notes": painNotes
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                physicalJson = String(data: data, encoding: .utf8)
            }
        }
        
        var respiratoryJson: String? = nil
        if hasRespiratorySymptoms {
            let dict: [String: Any] = [
                "congestion": congestion.rawValue,
                "throatCondition": throatCondition.rawValue,
                "coughType": coughType.rawValue,
                "sinusPressure": sinusPressure.rawValue,
                "feelingFeverish": feelingFeverish,
                "sicknessLevel": sicknessLevel.rawValue,
                "notes": respiratoryNotes
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                respiratoryJson = String(data: data, encoding: .utf8)
            }
        }
        
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
        
        return SQLiteStoredMorningCheckIn(
            id: UUID().uuidString,
            sessionId: sessionId,
            timestamp: Date(),
            sessionDate: sessionDate,
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
            usedSleepTherapy: usedSleepTherapy,
            sleepTherapyJson: sleepTherapyJson,
            notes: notes.isEmpty ? nil : notes
        )
    }
    
    func submit() async {
        isSubmitting = true
        saveSettingsForNextTime()
        let checkIn = toStoredCheckIn()
        // Route through SessionRepository for unified storage
        await MainActor.run {
            SessionRepository.shared.saveMorningCheckIn(checkIn, sessionDateOverride: sessionDate)
        }
        isSubmitting = false
    }

    func upsertPainEntry(_ entry: PreSleepLogAnswers.PainEntry) {
        if let idx = painEntries.firstIndex(where: { $0.entryKey == entry.entryKey }) {
            painEntries[idx] = entry
        } else {
            painEntries.append(entry)
        }
        syncLegacyPainSummary()
    }

    func removePainEntry(_ entryKey: String) {
        painEntries.removeAll { $0.entryKey == entryKey }
        syncLegacyPainSummary()
    }

    private func syncLegacyPainSummary() {
        painEntries.sort { $0.entryKey < $1.entryKey }
        guard !painEntries.isEmpty else {
            painLocations = []
            painSeverity = 0
            painType = .aching
            return
        }

        painLocations = Set(painEntries.compactMap { bodyPart(for: $0.area) })
        painSeverity = painEntries.map(\.intensity).max() ?? 0
        if let first = painEntries.first?.sensations.first {
            painType = legacyPainType(for: first)
        }
    }

    private func bodyPart(for area: PreSleepLogAnswers.PainArea) -> BodyPart? {
        switch area {
        case .headFace: return .head
        case .neck: return .neck
        case .upperBack: return .upperBack
        case .midBack, .lowerBack: return .lowerBack
        case .shoulder: return .shoulders
        case .armElbow: return .arms
        case .wristHand: return .hands
        case .chestRibs: return .chest
        case .abdomen: return .abdomen
        case .hipGlute: return .hips
        case .knee: return .knees
        case .ankleFoot: return .feet
        case .other: return nil
        }
    }

    private func legacyPainType(for sensation: PreSleepLogAnswers.PainSensation) -> PainType {
        switch sensation {
        case .aching: return .aching
        case .sharp, .shooting, .stabbing: return .sharp
        case .burning: return .burning
        case .throbbing: return .throbbing
        case .cramping, .tightness: return .cramping
        case .radiating, .pinsNeedles, .numbness, .other: return .aching
        }
    }
}

// MARK: - Main View
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
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    quickModeSection
                    symptomTogglesSection
                    if viewModel.hasPhysicalSymptoms { physicalSymptomsSection }
                    if viewModel.hasRespiratorySymptoms { respiratorySymptomsSection }
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
                GranularPainEntryEditorView(initialEntry: editingPainEntry) { entry in
                    viewModel.upsertPainEntry(entry)
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sunrise.fill").font(.system(size: 48)).foregroundStyle(.orange.gradient)
            Text("Good Morning!").font(.title2.bold())
            Text("Quick check-in about last night's sleep").font(.subheadline).foregroundColor(.secondary)
        }.padding(.bottom, 8)
    }
    
    private var quickModeSection: some View {
        VStack(spacing: 20) {
            cardView(title: "Sleep Quality", icon: "star.fill") {
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { star in
                        Button { viewModel.sleepQuality = star } label: {
                            Image(systemName: star <= viewModel.sleepQuality ? "star.fill" : "star")
                                .font(.title)
                                .foregroundColor(star <= viewModel.sleepQuality ? .yellow : .gray.opacity(0.3))
                        }
                    }
                }.padding(.vertical, 8)
            }
            cardView(title: "How Rested Do You Feel?", icon: "battery.100") { restedPicker }
            cardView(title: "Morning Grogginess", icon: "cloud.sun.fill") { grogginessPicker }
        }
    }
    
    private var symptomTogglesSection: some View {
        VStack(spacing: 12) {
            Text("Any Issues?").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
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
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(isActive ? Color.red.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            .foregroundColor(isActive ? .red : .secondary).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isActive ? Color.red : Color.clear, lineWidth: 2))
        }
    }
    
    private var physicalSymptomsSection: some View {
        VStack(spacing: 16) {
            Text("Physical Symptoms").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
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
            Toggle("Headache", isOn: $viewModel.hasHeadache).padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
        }.transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }
    
    private var respiratorySymptomsSection: some View {
        VStack(spacing: 16) {
            Text("Respiratory / Illness").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            cardView(title: "Nose", icon: "wind") { congestionPicker }
            cardView(title: "Throat", icon: "mouth") { throatPicker }
        }.transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }
    
    private var sleepTherapySection: some View {
        VStack(spacing: 12) {
            Button { withAnimation(.spring(response: 0.3)) { viewModel.showSleepTherapySection.toggle() } } label: {
                HStack {
                    Image(systemName: "wind").foregroundColor(.cyan)
                    Text("Sleep Therapy Device").foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showSleepTherapySection ? "chevron.up" : "chevron.down").foregroundColor(.secondary)
                }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
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
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private var narcolepsySection: some View {
        VStack(spacing: 12) {
            Button { withAnimation(.spring(response: 0.3)) { viewModel.showNarcolepsySection.toggle() } } label: {
                HStack {
                    Image(systemName: "moon.zzz.fill").foregroundColor(.indigo)
                    Text("Narcolepsy Symptoms").foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showNarcolepsySection ? "chevron.up" : "chevron.down").foregroundColor(.secondary)
                }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
            }
            if viewModel.showNarcolepsySection {
                VStack(spacing: 8) {
                    Toggle("Sleep Paralysis", isOn: $viewModel.hadSleepParalysis).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Hallucinations", isOn: $viewModel.hadHallucinations).toggleStyle(SwitchToggleStyle(tint: .indigo))
                }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text").font(.headline)
            TextField("Anything else to note?", text: $viewModel.notes, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
        }
    }
    
    private var rememberSettingsSection: some View {
        HStack {
            Image(systemName: viewModel.rememberSettings ? "checkmark.square.fill" : "square").foregroundColor(viewModel.rememberSettings ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Remember my device settings").font(.subheadline)
                Text("Pre-fill sleep therapy for next time").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12).onTapGesture { withAnimation { viewModel.rememberSettings.toggle() } }
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
                    if viewModel.isSubmitting { ProgressView().tint(.white) }
                    else { Image(systemName: "checkmark.circle.fill"); Text("Complete Check-In") }
                }
                .font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.green.gradient).cornerRadius(16)
            }
            .disabled(viewModel.isSubmitting || (viewModel.hasPhysicalSymptoms && viewModel.painEntries.isEmpty))
        }
        .padding(.top, 8)
    }
    
    private func cardView<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.subheadline.bold()).foregroundColor(.secondary)
            content()
        }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
    }
    
    private var restedPicker: some View { Picker("Rested", selection: $viewModel.feelRested) { ForEach(RestedLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
    private var grogginessPicker: some View {
        HStack(spacing: 12) {
            ForEach(GrogginessLevel.allCases, id: \.self) { level in
                Button { viewModel.grogginess = level } label: {
                    VStack(spacing: 4) { Image(systemName: level.icon).font(.title2); Text(level.rawValue).font(.caption2) }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(viewModel.grogginess == level ? Color.orange.opacity(0.2) : Color.clear)
                    .foregroundColor(viewModel.grogginess == level ? .orange : .secondary).cornerRadius(8)
                }
            }
        }
    }
    private var congestionPicker: some View { Picker("", selection: $viewModel.congestion) { ForEach(CongestionType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
    private var throatPicker: some View { Picker("", selection: $viewModel.throatCondition) { ForEach(ThroatCondition.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
}

// MARK: - V2 Test Compatibility

enum WakeFeelingNow: String {
    case rough
    case okay
    case good
    case great

    init(rawSurveyValue: String) {
        switch rawSurveyValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "rough": self = .rough
        case "great": self = .great
        case "good": self = .good
        default: self = .okay
        }
    }
}

enum WakeAwakeningsCount: String {
    case none
    case oneTwo
    case threeFour
    case fivePlus

    init(rawSurveyValue: String) {
        switch rawSurveyValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1-2", "one-two": self = .oneTwo
        case "3-4", "three-four": self = .threeFour
        case "5+", "5plus", "five-plus": self = .fivePlus
        default: self = .none
        }
    }
}

enum WakeLongAwakePeriod: String {
    case none
    case lessThan15
    case fifteenTo30
    case thirtyTo60
    case oneHourPlus

    init(rawSurveyValue: String) {
        switch rawSurveyValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "<15m", "<15", "less_than_15": self = .lessThan15
        case "15-30m", "15-30": self = .fifteenTo30
        case "30-60m", "30-60": self = .thirtyTo60
        case "1h+", "1h", "1hour+", "60+": self = .oneHourPlus
        default: self = .none
        }
    }
}

@MainActor
final class MorningCheckInViewModelV2 {
    var feelingNow: WakeFeelingNow = .okay
    var sleepQuality: Int = 3
    var sleepinessNow: Int = 3
    var wakePainLevel: Int = 0
    var painWokeUser: Bool = false
    var awakeningsCount: WakeAwakeningsCount = .none
    var longAwakePeriod: WakeLongAwakePeriod = .none
    var notes: String = ""

    @discardableResult
    func applyLastWakeSurvey(from events: [StoredSleepEvent], excludingSessionDate: String) -> Bool {
        guard
            let latest = events.filter({ $0.eventType == "wake_survey" && $0.sessionDate != excludingSessionDate }).sorted(by: { $0.timestamp > $1.timestamp }).first,
            let payloadText = latest.notes,
            let payloadData = payloadText.data(using: .utf8),
            let payload = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any]
        else {
            return false
        }

        if let value = payload["feeling"] as? String { feelingNow = WakeFeelingNow(rawSurveyValue: value) }
        if let value = payload["sleep_quality"] as? Int { sleepQuality = value }
        if let value = payload["sleepiness_now"] as? Int { sleepinessNow = value }
        if let value = payload["pain_level"] as? Int { wakePainLevel = value }
        if let value = payload["pain_woke_user"] as? Bool { painWokeUser = value }
        if let value = payload["awakenings"] as? String { awakeningsCount = WakeAwakeningsCount(rawSurveyValue: value) }
        if let value = payload["long_awake"] as? String { longAwakePeriod = WakeLongAwakePeriod(rawSurveyValue: value) }
        if let value = payload["notes"] as? String { notes = value }
        return true
    }
}

#Preview { MorningCheckInView(sessionId: "preview-session", sessionDate: "2025-01-01") }
