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
import DoseCore

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

enum Dose2ReconciliationChoice: String, CaseIterable, Identifiable {
    case leaveAsIs = "Leave as-is"
    case taken = "Taken"
    case skipped = "Skipped"

    var id: String { rawValue }
}

struct SavedCheckInSettings: Codable {
    var sleepQuality: Int?
    var feelRested: String?
    var grogginess: String?
    var sleepInertiaDuration: String?
    var dreamRecall: String?
    var mentalClarity: Int?
    var mood: String?
    var anxietyLevel: String?
    var stressLevel: Int?
    var stressDrivers: [String]?
    var stressProgression: String?
    var stressNotes: String?
    var readinessForDay: Int?
    var usedSleepTherapy: Bool?
    var sleepTherapyDevice: SleepTherapyDevice?
    var sleepTherapyCompliance: Int?
    var sleepTherapyNotes: String?
    var hasSleepEnvironment: Bool?
    var sleepEnvironmentRoomTemp: String?
    var sleepEnvironmentNoiseLevel: String?
    var sleepEnvironmentSleepAid: String?
    var sleepEnvironmentNotes: String?
}

// MARK: - Morning Check-In View Model
@MainActor
class MorningCheckInViewModel: ObservableObject {
    let sessionId: String
    let sessionDate: String
    /// When editing, reuse the original check-in ID so INSERT OR REPLACE updates in place.
    let existingCheckInId: String?
    private let originalPhysicalSymptoms: [String: Any]
    private let originalRespiratorySymptoms: [String: Any]
    private let originalSleepTherapy: [String: Any]
    private let originalSleepEnvironment: [String: Any]
    private let originalStressContext: [String: Any]
    
    @Published var sleepQuality: Int = 3
    @Published var feelRested: RestedLevel = .moderate
    @Published var grogginess: GrogginessLevel = .mild
    @Published var sleepInertiaDuration: SleepInertiaDuration = .fiveToFifteen
    @Published var mentalClarity: Int = 5
    @Published var mood: MoodLevel = .neutral
    @Published var stressLevel: Int?
    @Published var stressDrivers: [PreSleepLogAnswers.StressDriver] = []
    @Published var stressProgression: PreSleepLogAnswers.StressProgression?
    @Published var stressNotes: String = ""
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
    @Published var hasSleepEnvironment: Bool = false
    @Published var sleepEnvironmentRoomTemp: PreSleepLogAnswers.RoomTemp = .comfortable
    @Published var sleepEnvironmentNoiseLevel: PreSleepLogAnswers.NoiseLevel = .quiet
    @Published var sleepEnvironmentSleepAid: PreSleepLogAnswers.SleepAid = .none
    @Published var sleepEnvironmentNotes: String = ""
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
    @Published var showSleepEnvironmentSection: Bool = false
    @Published var loggedDose1Time: Date?
    @Published var loggedDose2Time: Date?
    @Published var loggedDose2Skipped = false
    @Published var reconcileDose1Taken = false
    @Published var reconcileDose1Time: Date = Date()
    @Published var reconcileDose1AmountMg: Int = 4500
    @Published var dose2Reconciliation: Dose2ReconciliationChoice = .leaveAsIs
    @Published var reconcileDose2Time: Date = Date()
    @Published var reconcileDose2AmountMg: Int = 4500
    
    private static let rememberSettingsKey = "morningCheckIn.rememberSettings"
    private static let savedSettingsKey = "morningCheckIn.savedSettings"
    private static let maxDoseAmountMg = 20_000
    private static let doseWarningThresholdMg = 9_000
    
    init(sessionId: String, sessionDate: String) {
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.existingCheckInId = nil
        self.originalPhysicalSymptoms = [:]
        self.originalRespiratorySymptoms = [:]
        self.originalSleepTherapy = [:]
        self.originalSleepEnvironment = [:]
        self.originalStressContext = [:]
        loadSavedSettings()
        configureDoseReconciliationState()
    }
    
    /// Initialize with existing check-in for editing.
    init(sessionId: String, sessionDate: String, existing: StoredMorningCheckIn) {
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.existingCheckInId = existing.id
        self.originalPhysicalSymptoms = Self.jsonDictionary(from: existing.physicalSymptomsJson)
        self.originalRespiratorySymptoms = Self.jsonDictionary(from: existing.respiratorySymptomsJson)
        self.originalSleepTherapy = Self.jsonDictionary(from: existing.sleepTherapyJson)
        self.originalSleepEnvironment = Self.jsonDictionary(from: existing.sleepEnvironmentJson)
        self.originalStressContext = Self.jsonDictionary(from: existing.stressContextJson)
        self.sleepQuality = existing.sleepQuality
        self.feelRested = RestedLevel(rawValue: existing.feelRested) ?? .moderate
        self.grogginess = GrogginessLevel(rawValue: existing.grogginess) ?? .mild
        self.sleepInertiaDuration = SleepInertiaDuration(rawValue: existing.sleepInertiaDuration) ?? .fiveToFifteen
        self.dreamRecall = DreamRecallType(rawValue: existing.dreamRecall) ?? .none
        self.mentalClarity = existing.mentalClarity
        self.mood = MoodLevel(rawValue: existing.mood) ?? .neutral
        self.anxietyLevel = AnxietyLevel(rawValue: existing.anxietyLevel) ?? .none
        self.stressLevel = existing.stressLevel
        self.readinessForDay = existing.readinessForDay
        self.hasPhysicalSymptoms = existing.hasPhysicalSymptoms
        self.hasRespiratorySymptoms = existing.hasRespiratorySymptoms
        self.hadSleepParalysis = existing.hadSleepParalysis
        self.hadHallucinations = existing.hadHallucinations
        self.hadAutomaticBehavior = existing.hadAutomaticBehavior
        self.fellOutOfBed = existing.fellOutOfBed
        self.hadConfusionOnWaking = existing.hadConfusionOnWaking
        self.usedSleepTherapy = existing.usedSleepTherapy
        self.hasSleepEnvironment = existing.hasSleepEnvironment
        self.notes = existing.notes ?? ""
        hydratePhysicalState(from: originalPhysicalSymptoms)
        hydrateRespiratoryState(from: originalRespiratorySymptoms)
        hydrateSleepTherapyState(from: originalSleepTherapy)
        hydrateSleepEnvironmentState(from: originalSleepEnvironment)
        hydrateStressState(from: originalStressContext)
        if existing.usedSleepTherapy {
            self.showSleepTherapySection = true
        }
        if existing.hasSleepEnvironment {
            self.showSleepEnvironmentSection = true
        }
        if existing.hadSleepParalysis || existing.hadHallucinations || existing.hadAutomaticBehavior || existing.fellOutOfBed || existing.hadConfusionOnWaking {
            self.showNarcolepsySection = true
        }
        configureDoseReconciliationState()
    }
    
    private func loadSavedSettings() {
        rememberSettings = UserDefaults.standard.bool(forKey: Self.rememberSettingsKey)
        if rememberSettings, let data = UserDefaults.standard.data(forKey: Self.savedSettingsKey) {
            if let saved = try? JSONDecoder().decode(SavedCheckInSettings.self, from: data) {
                applySavedSettings(saved)
            }
        }
    }
    
    func saveSettingsForNextTime() {
        UserDefaults.standard.set(rememberSettings, forKey: Self.rememberSettingsKey)
        if rememberSettings {
            let settings = SavedCheckInSettings(
                sleepQuality: sleepQuality,
                feelRested: feelRested.rawValue,
                grogginess: grogginess.rawValue,
                sleepInertiaDuration: sleepInertiaDuration.rawValue,
                dreamRecall: dreamRecall.rawValue,
                mentalClarity: mentalClarity,
                mood: mood.rawValue,
                anxietyLevel: anxietyLevel.rawValue,
                stressLevel: stressLevel,
                stressDrivers: PreSleepLogAnswers.sanitizedStressDrivers(stressDrivers).map(\.rawValue),
                stressProgression: stressProgression?.rawValue,
                stressNotes: stressNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : stressNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                readinessForDay: readinessForDay,
                usedSleepTherapy: usedSleepTherapy,
                sleepTherapyDevice: sleepTherapyDevice,
                sleepTherapyCompliance: sleepTherapyCompliance,
                sleepTherapyNotes: sleepTherapyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sleepTherapyNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                hasSleepEnvironment: hasSleepEnvironment,
                sleepEnvironmentRoomTemp: sleepEnvironmentRoomTemp.rawValue,
                sleepEnvironmentNoiseLevel: sleepEnvironmentNoiseLevel.rawValue,
                sleepEnvironmentSleepAid: sleepEnvironmentSleepAid.rawValue,
                sleepEnvironmentNotes: sleepEnvironmentNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sleepEnvironmentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.savedSettingsKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: Self.savedSettingsKey)
        }
    }

    func setRememberSettingsEnabled(_ enabled: Bool) {
        rememberSettings = enabled
        UserDefaults.standard.set(enabled, forKey: Self.rememberSettingsKey)
        if !enabled {
            UserDefaults.standard.removeObject(forKey: Self.savedSettingsKey)
        }
    }

    var reconcileDose1NeedsWarning: Bool {
        reconcileDose1AmountMg > Self.doseWarningThresholdMg
    }

    var reconcileDose2NeedsWarning: Bool {
        reconcileDose2AmountMg > Self.doseWarningThresholdMg
    }
    
    func toStoredCheckIn() -> SQLiteStoredMorningCheckIn {
        syncLegacyPainSummary()
        var physicalJson: String? = nil
        if hasPhysicalSymptoms {
            var dict = originalPhysicalSymptoms
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

            dict["painEntries"] = painPayload
            dict["painLocations"] = painLocations.map { $0.rawValue }
            dict["painSeverity"] = painSeverity
            dict["painType"] = painType.rawValue
            dict["hasHeadache"] = hasHeadache
            dict["headacheSeverity"] = headacheSeverity.rawValue
            dict["headacheLocation"] = headacheLocation.rawValue
            dict["isMigraine"] = isMigraine
            dict["muscleStiffness"] = muscleStiffness.rawValue
            dict["muscleSoreness"] = muscleSoreness.rawValue
            if painNotes.isEmpty {
                dict.removeValue(forKey: "notes")
            } else {
                dict["notes"] = painNotes
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                physicalJson = String(data: data, encoding: .utf8)
            }
        }
        
        var respiratoryJson: String? = nil
        if hasRespiratorySymptoms {
            var dict = originalRespiratorySymptoms
            dict["congestion"] = congestion.rawValue
            dict["throatCondition"] = throatCondition.rawValue
            dict["coughType"] = coughType.rawValue
            dict["sinusPressure"] = sinusPressure.rawValue
            dict["feelingFeverish"] = feelingFeverish
            dict["sicknessLevel"] = sicknessLevel.rawValue
            if respiratoryNotes.isEmpty {
                dict.removeValue(forKey: "notes")
            } else {
                dict["notes"] = respiratoryNotes
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                respiratoryJson = String(data: data, encoding: .utf8)
            }
        }
        
        var sleepTherapyJson: String? = nil
        if usedSleepTherapy && sleepTherapyDevice != .none {
            var dict = originalSleepTherapy
            dict["device"] = sleepTherapyDevice.rawValue
            dict["compliance"] = sleepTherapyCompliance
            if sleepTherapyNotes.isEmpty {
                dict.removeValue(forKey: "notes")
            } else {
                dict["notes"] = sleepTherapyNotes
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                sleepTherapyJson = String(data: data, encoding: .utf8)
            }
        }

        var sleepEnvironmentJson: String? = nil
        if hasSleepEnvironment {
            var dict = originalSleepEnvironment
            dict["roomTemp"] = sleepEnvironmentRoomTemp.rawValue
            dict["noiseLevel"] = sleepEnvironmentNoiseLevel.rawValue
            dict["sleepAids"] = sleepEnvironmentSleepAid.rawValue
            if sleepEnvironmentNotes.isEmpty {
                dict.removeValue(forKey: "notes")
            } else {
                dict["notes"] = sleepEnvironmentNotes
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                sleepEnvironmentJson = String(data: data, encoding: .utf8)
            }
        }

        let trimmedStressNotes = stressNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStressLevel = stressLevel.map { max(1, min(5, $0)) }
        let normalizedStressDrivers = PreSleepLogAnswers.sanitizedStressDrivers(stressDrivers)
        var stressContextJson: String? = nil
        if normalizedStressLevel != nil || !normalizedStressDrivers.isEmpty || stressProgression != nil || !trimmedStressNotes.isEmpty {
            var dict = originalStressContext
            if normalizedStressDrivers.isEmpty {
                dict.removeValue(forKey: "drivers")
            } else {
                dict["drivers"] = normalizedStressDrivers.map(\.rawValue)
            }
            if let stressProgression {
                dict["progression"] = stressProgression.rawValue
            } else {
                dict.removeValue(forKey: "progression")
            }
            if trimmedStressNotes.isEmpty {
                dict.removeValue(forKey: "notes")
            } else {
                dict["notes"] = trimmedStressNotes
            }
            if !dict.isEmpty, let data = try? JSONSerialization.data(withJSONObject: dict) {
                stressContextJson = String(data: data, encoding: .utf8)
            }
        }
        
        return SQLiteStoredMorningCheckIn(
            id: existingCheckInId ?? UUID().uuidString,
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
            stressLevel: normalizedStressLevel,
            stressContextJson: stressContextJson,
            readinessForDay: readinessForDay,
            hadSleepParalysis: hadSleepParalysis,
            hadHallucinations: hadHallucinations,
            hadAutomaticBehavior: hadAutomaticBehavior,
            fellOutOfBed: fellOutOfBed,
            hadConfusionOnWaking: hadConfusionOnWaking,
            usedSleepTherapy: usedSleepTherapy,
            sleepTherapyJson: sleepTherapyJson,
            hasSleepEnvironment: hasSleepEnvironment,
            sleepEnvironmentJson: sleepEnvironmentJson,
            notes: notes.isEmpty ? nil : notes
        )
    }
    
    func submit() async {
        isSubmitting = true
        saveSettingsForNextTime()
        let checkIn = toStoredCheckIn()
        // Route through SessionRepository for unified storage
        await MainActor.run {
            applyDoseReconciliation()
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

    func upsertPainEntries(_ entries: [PreSleepLogAnswers.PainEntry], replacingEntryKey: String?) {
        if let replacingEntryKey {
            painEntries.removeAll { $0.entryKey == replacingEntryKey }
        }
        for entry in entries {
            if let idx = painEntries.firstIndex(where: { $0.entryKey == entry.entryKey }) {
                painEntries[idx] = entry
            } else {
                painEntries.append(entry)
            }
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

    private func hydratePhysicalState(from physical: [String: Any]) {
        if let entries = physical["painEntries"] as? [[String: Any]] {
            painEntries = entries.compactMap(Self.parsePainEntry(from:))
        }
        if painEntries.isEmpty {
            painEntries = Self.legacyPainEntries(from: physical)
        }
        if let value = physical["hasHeadache"] as? Bool {
            hasHeadache = value
        }
        if let value = physical["headacheSeverity"] as? String {
            headacheSeverity = HeadacheSeverity(rawValue: value) ?? headacheSeverity
        }
        if let value = physical["headacheLocation"] as? String {
            headacheLocation = HeadacheLocation(rawValue: value) ?? headacheLocation
        }
        if let value = physical["isMigraine"] as? Bool {
            isMigraine = value
        }
        if let value = physical["muscleStiffness"] as? String {
            muscleStiffness = StiffnessLevel(rawValue: value) ?? muscleStiffness
        }
        if let value = physical["muscleSoreness"] as? String {
            muscleSoreness = SorenessLevel(rawValue: value) ?? muscleSoreness
        }
        if let value = physical["notes"] as? String {
            painNotes = value
        }
        syncLegacyPainSummary()
        if painEntries.isEmpty {
            if let locations = physical["painLocations"] as? [String] {
                painLocations = Set(locations.compactMap(Self.bodyPart(fromLegacyPainLocation:)))
            }
            if let value = Self.intValue(from: physical["painSeverity"]) {
                painSeverity = value
            }
            if let value = physical["painType"] as? String {
                painType = PainType(rawValue: value) ?? painType
            }
        }
    }

    private func hydrateRespiratoryState(from respiratory: [String: Any]) {
        if let value = respiratory["congestion"] as? String {
            congestion = CongestionType(rawValue: value) ?? congestion
        }
        if let value = respiratory["throatCondition"] as? String {
            throatCondition = ThroatCondition(rawValue: value) ?? throatCondition
        }
        if let value = respiratory["coughType"] as? String {
            coughType = CoughType(rawValue: value) ?? coughType
        }
        if let value = respiratory["sinusPressure"] as? String {
            sinusPressure = SinusPressureLevel(rawValue: value) ?? sinusPressure
        }
        if let value = respiratory["feelingFeverish"] as? Bool {
            feelingFeverish = value
        }
        if let value = respiratory["sicknessLevel"] as? String {
            sicknessLevel = SicknessLevel(rawValue: value) ?? sicknessLevel
        }
        if let value = respiratory["notes"] as? String {
            respiratoryNotes = value
        }
    }

    private func hydrateSleepTherapyState(from therapy: [String: Any]) {
        if let value = therapy["device"] as? String {
            sleepTherapyDevice = SleepTherapyDevice(rawValue: value) ?? sleepTherapyDevice
        }
        if let value = Self.intValue(from: therapy["compliance"]) {
            sleepTherapyCompliance = value
        }
        if let value = therapy["notes"] as? String {
            sleepTherapyNotes = value
        }
    }

    private func hydrateSleepEnvironmentState(from environment: [String: Any]) {
        if let value = environment["roomTemp"] as? String {
            sleepEnvironmentRoomTemp = PreSleepLogAnswers.RoomTemp(rawValue: value) ?? sleepEnvironmentRoomTemp
        }
        if let value = environment["noiseLevel"] as? String {
            sleepEnvironmentNoiseLevel = PreSleepLogAnswers.NoiseLevel(rawValue: value) ?? sleepEnvironmentNoiseLevel
        }
        if let value = environment["sleepAids"] as? String {
            sleepEnvironmentSleepAid = PreSleepLogAnswers.SleepAid(rawValue: value) ?? sleepEnvironmentSleepAid
        }
        if let value = environment["notes"] as? String {
            sleepEnvironmentNotes = value
        }
    }

    private func hydrateStressState(from stress: [String: Any]) {
        if let values = stress["drivers"] as? [String] {
            stressDrivers = PreSleepLogAnswers.sanitizedStressDrivers(values.compactMap(PreSleepLogAnswers.StressDriver.init(rawValue:)))
        }
        if let value = stress["progression"] as? String {
            stressProgression = PreSleepLogAnswers.StressProgression(rawValue: value)
        }
        if let value = stress["notes"] as? String {
            stressNotes = value
        }
    }

    private func applySavedSettings(_ saved: SavedCheckInSettings) {
        if let sleepQuality = saved.sleepQuality {
            self.sleepQuality = max(1, min(5, sleepQuality))
        }
        if let value = saved.feelRested {
            self.feelRested = RestedLevel(rawValue: value) ?? self.feelRested
        }
        if let value = saved.grogginess {
            self.grogginess = GrogginessLevel(rawValue: value) ?? self.grogginess
        }
        if let value = saved.sleepInertiaDuration {
            self.sleepInertiaDuration = SleepInertiaDuration(rawValue: value) ?? self.sleepInertiaDuration
        }
        if let value = saved.dreamRecall {
            self.dreamRecall = DreamRecallType(rawValue: value) ?? self.dreamRecall
        }
        if let mentalClarity = saved.mentalClarity {
            self.mentalClarity = max(1, min(5, mentalClarity))
        }
        if let value = saved.mood {
            self.mood = MoodLevel(rawValue: value) ?? self.mood
        }
        if let value = saved.anxietyLevel {
            self.anxietyLevel = AnxietyLevel(rawValue: value) ?? self.anxietyLevel
        }
        self.stressLevel = saved.stressLevel.map { max(1, min(5, $0)) }
        if let savedDrivers = saved.stressDrivers {
            self.stressDrivers = PreSleepLogAnswers.sanitizedStressDrivers(savedDrivers.compactMap(PreSleepLogAnswers.StressDriver.init(rawValue:)))
        }
        if let value = saved.stressProgression {
            self.stressProgression = PreSleepLogAnswers.StressProgression(rawValue: value)
        } else {
            self.stressProgression = nil
        }
        self.stressNotes = saved.stressNotes ?? ""
        if let readinessForDay = saved.readinessForDay {
            self.readinessForDay = max(1, min(5, readinessForDay))
        }
        if let usedSleepTherapy = saved.usedSleepTherapy {
            self.usedSleepTherapy = usedSleepTherapy
            self.showSleepTherapySection = usedSleepTherapy
        }
        if let sleepTherapyDevice = saved.sleepTherapyDevice {
            self.sleepTherapyDevice = sleepTherapyDevice
        }
        if let sleepTherapyCompliance = saved.sleepTherapyCompliance {
            self.sleepTherapyCompliance = max(0, min(100, sleepTherapyCompliance))
        }
        self.sleepTherapyNotes = saved.sleepTherapyNotes ?? ""
        if let hasSleepEnvironment = saved.hasSleepEnvironment {
            self.hasSleepEnvironment = hasSleepEnvironment
            self.showSleepEnvironmentSection = hasSleepEnvironment
        }
        if let value = saved.sleepEnvironmentRoomTemp {
            self.sleepEnvironmentRoomTemp = PreSleepLogAnswers.RoomTemp(rawValue: value) ?? self.sleepEnvironmentRoomTemp
        }
        if let value = saved.sleepEnvironmentNoiseLevel {
            self.sleepEnvironmentNoiseLevel = PreSleepLogAnswers.NoiseLevel(rawValue: value) ?? self.sleepEnvironmentNoiseLevel
        }
        if let value = saved.sleepEnvironmentSleepAid {
            self.sleepEnvironmentSleepAid = PreSleepLogAnswers.SleepAid(rawValue: value) ?? self.sleepEnvironmentSleepAid
        }
        self.sleepEnvironmentNotes = saved.sleepEnvironmentNotes ?? ""
    }

    private static func jsonDictionary(from json: String?) -> [String: Any] {
        guard
            let json,
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else {
            return [:]
        }
        return dict
    }

    private static func parsePainEntry(from item: [String: Any]) -> PreSleepLogAnswers.PainEntry? {
        guard
            let areaValue = item["area"] as? String,
            let area = PreSleepLogAnswers.PainArea(rawValue: areaValue)
        else {
            return nil
        }

        let sideValue = item["side"] as? String ?? PreSleepLogAnswers.PainSide.na.rawValue
        let side = PreSleepLogAnswers.PainSide(rawValue: sideValue) ?? .na
        let intensity = intValue(from: item["intensity"]) ?? 0
        let sensations = (item["sensations"] as? [String] ?? [])
            .compactMap(PreSleepLogAnswers.PainSensation.init(rawValue:))
        let pattern = (item["pattern"] as? String).flatMap(PreSleepLogAnswers.PainPattern.init(rawValue:))
        let notes = item["notes"] as? String

        return PreSleepLogAnswers.PainEntry(
            area: area,
            side: side,
            intensity: intensity,
            sensations: sensations.isEmpty ? [.aching] : sensations,
            pattern: pattern,
            notes: notes
        )
    }

    private static func legacyPainEntries(from physical: [String: Any]) -> [PreSleepLogAnswers.PainEntry] {
        guard let locations = physical["painLocations"] as? [String], !locations.isEmpty else {
            return []
        }

        let intensity = max(1, intValue(from: physical["painSeverity"]) ?? 1)
        let sensation = painSensation(fromLegacyPainType: physical["painType"] as? String)

        return locations.compactMap { location in
            guard let area = painArea(fromLegacyLocation: location) else { return nil }
            return PreSleepLogAnswers.PainEntry(
                area: area,
                side: .na,
                intensity: intensity,
                sensations: [sensation]
            )
        }
    }

    private static func painArea(fromLegacyLocation value: String) -> PreSleepLogAnswers.PainArea? {
        if let exact = PreSleepLogAnswers.PainArea(rawValue: value) {
            return exact
        }

        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "head": return .headFace
        case "neck": return .neck
        case "shoulders": return .shoulder
        case "upper back": return .upperBack
        case "lower back": return .lowerBack
        case "hips": return .hipGlute
        case "legs", "feet": return .ankleFoot
        case "knees": return .knee
        case "hands": return .wristHand
        case "arms": return .armElbow
        case "chest": return .chestRibs
        case "abdomen": return .abdomen
        default: return .other
        }
    }

    private static func bodyPart(fromLegacyPainLocation value: String) -> BodyPart? {
        BodyPart.allCases.first { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }
    }

    private static func painSensation(fromLegacyPainType value: String?) -> PreSleepLogAnswers.PainSensation {
        switch value {
        case PainType.sharp.rawValue: return .sharp
        case PainType.burning.rawValue: return .burning
        case PainType.throbbing.rawValue: return .throbbing
        case PainType.cramping.rawValue, PainType.stiff.rawValue: return .tightness
        default: return .aching
        }
    }

    private static func intValue(from value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func configureDoseReconciliationState() {
        let sessionRepo = SessionRepository.shared
        let doseLog = sessionRepo.fetchDoseLog(forSession: sessionDate)
        let doseEvents = sessionRepo.fetchDoseEvents(forSessionDate: sessionDate)
        let preSleepAnswers = sessionRepo.fetchMostRecentPreSleepLog(sessionId: sessionId)?.answers

        let plannedDose1 = Self.normalizedDoseAmount(
            Self.parseDoseAmount(from: doseEvents, eventType: "dose1")
                ?? Self.plannedDoseAmount(from: preSleepAnswers, eventType: "dose1")
                ?? Self.defaultDoseAmountMg()
        )
        let plannedDose2 = Self.normalizedDoseAmount(
            Self.parseDoseAmount(from: doseEvents, eventType: "dose2")
                ?? Self.plannedDoseAmount(from: preSleepAnswers, eventType: "dose2")
                ?? Self.defaultDoseAmountMg()
        )

        loggedDose1Time = doseLog?.dose1Time
        loggedDose2Time = doseLog?.dose2Time
        loggedDose2Skipped = doseLog?.dose2Skipped ?? doseEvents.contains(where: { $0.eventType == "dose2_skipped" })

        reconcileDose1Taken = loggedDose1Time == nil
        reconcileDose1Time = doseLog?.dose1Time ?? Self.defaultDose1Time(for: sessionDate)
        reconcileDose2Time = doseLog?.dose2Time ?? Self.defaultDose2Time(for: sessionDate, dose1Time: reconcileDose1Time)
        reconcileDose1AmountMg = plannedDose1
        reconcileDose2AmountMg = plannedDose2
        dose2Reconciliation = loggedDose2Time != nil
            ? .leaveAsIs
            : (loggedDose2Skipped ? .skipped : .taken)
    }

    private func applyDoseReconciliation() {
        let sessionRepo = SessionRepository.shared

        if loggedDose1Time == nil, reconcileDose1Taken {
            sessionRepo.reconcileDose1(
                sessionDate: sessionDate,
                takenAt: reconcileDose1Time,
                amountMg: Self.normalizedDoseAmount(reconcileDose1AmountMg)
            )
        }

        if loggedDose2Time == nil {
            switch dose2Reconciliation {
            case .leaveAsIs:
                break
            case .taken:
                sessionRepo.reconcileDose2(
                    sessionDate: sessionDate,
                    takenAt: reconcileDose2Time,
                    amountMg: Self.normalizedDoseAmount(reconcileDose2AmountMg)
                )
            case .skipped:
                sessionRepo.reconcileDose2Skipped(sessionDate: sessionDate, timestamp: reconcileDose2Time)
            }
        }
    }

    private static func parseDoseAmount(from events: [DoseCore.StoredDoseEvent], eventType: String) -> Int? {
        guard
            let metadata = events.first(where: { $0.eventType == eventType })?.metadata,
            let data = metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return intValue(from: object["amount_mg"])
    }

    private static func plannedDoseAmount(from answers: PreSleepLogAnswers?, eventType: String) -> Int? {
        guard let answers else { return nil }
        if eventType == "dose1", let explicit = answers.plannedDose1Mg {
            return explicit
        }
        if eventType == "dose2", let explicit = answers.plannedDose2Mg {
            return explicit
        }
        guard let total = answers.resolvedPlannedTotalNightlyMg else { return nil }
        let ratioIndex = eventType == "dose1" ? 0 : 1
        return Int((Double(total) * answers.resolvedPlannedDoseSplitRatio[ratioIndex]).rounded())
    }

    private static func defaultDoseAmountMg() -> Int {
        DoseCore.MedicationConfig.nightMedications.first(where: { $0.id != "lumryz" })?.defaultDoseMg
        ?? DoseCore.MedicationConfig.nightMedications.first?.defaultDoseMg
        ?? 4500
    }

    private static func normalizedDoseAmount(_ value: Int) -> Int {
        max(250, min(maxDoseAmountMg, value))
    }

    private static func defaultDose1Time(for sessionDate: String) -> Date {
        guard let night = AppFormatters.sessionDate.date(from: sessionDate) else {
            return Date()
        }
        return Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: night) ?? night
    }

    private static func defaultDose2Time(for sessionDate: String, dose1Time: Date) -> Date {
        if let parsedNight = AppFormatters.sessionDate.date(from: sessionDate),
           let nextMorning = Calendar.current.date(byAdding: .day, value: 1, to: parsedNight),
           let morningDefault = Calendar.current.date(bySettingHour: 1, minute: 0, second: 0, of: nextMorning) {
            return morningDefault
        }
        return dose1Time.addingTimeInterval(3 * 60 * 60)
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
    
    /// Initialize for editing an existing morning check-in.
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

    private var morningFunctioningSection: some View {
        VStack(spacing: 16) {
            Text("Morning Functioning").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
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
        }.transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }
    
    private var respiratorySymptomsSection: some View {
        VStack(spacing: 16) {
            Text("Respiratory / Illness").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
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
        }.transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
    }

    private var sleepEnvironmentSection: some View {
        VStack(spacing: 12) {
            Button { withAnimation(.spring(response: 0.3)) { viewModel.showSleepEnvironmentSection.toggle() } } label: {
                HStack {
                    Image(systemName: "bed.double.circle").foregroundColor(.teal)
                    Text("Sleep Environment").foregroundColor(.primary)
                    Spacer()
                    Image(systemName: viewModel.showSleepEnvironmentSection ? "chevron.up" : "chevron.down").foregroundColor(.secondary)
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
                    Toggle("Automatic Behavior", isOn: $viewModel.hadAutomaticBehavior).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Fell Out Of Bed", isOn: $viewModel.fellOutOfBed).toggleStyle(SwitchToggleStyle(tint: .indigo))
                    Toggle("Confusion On Waking", isOn: $viewModel.hadConfusionOnWaking).toggleStyle(SwitchToggleStyle(tint: .indigo))
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
            Image(systemName: viewModel.rememberSettings ? "checkmark.square.fill" : "square").foregroundColor(viewModel.rememberSettings ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Remember last wake-up settings").font(.subheadline)
                Text("Auto-prefill your last morning check-in setup next time.").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12).onTapGesture {
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

extension RestedLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension GrogginessLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension SleepInertiaDuration: DisplayTextProvider { var displayText: String { rawValue } }
extension DreamRecallType: DisplayTextProvider { var displayText: String { rawValue } }
extension MoodLevel: DisplayTextProvider { var displayText: String { "\(emoji) \(rawValue)" } }
extension AnxietyLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension HeadacheSeverity: DisplayTextProvider { var displayText: String { rawValue } }
extension HeadacheLocation: DisplayTextProvider { var displayText: String { rawValue } }
extension CoughType: DisplayTextProvider { var displayText: String { rawValue } }
extension SinusPressureLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension SicknessLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension StiffnessLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension SorenessLevel: DisplayTextProvider { var displayText: String { rawValue } }

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
