import Foundation
import Combine
import DoseCore

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
    private let originalTimingContext: [String: Any]

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
    @Published var nightType: NightType = .unsure
    @Published var firstNightOffAfterWorkBlock: Bool = false
    @Published var wakeType: WakeType = .unsure
    @Published var nextDayDemand: NextDayDemand = .unsure
    @Published var dose2WakeMethod: Dose2WakeMethod = .unsure
    @Published var backToSleepDuration: BackToSleepDuration = .unsure
    @Published var dose2TakenReason: Dose2TakenReason = .unsure
    @Published var dose2SkippedReason: Dose2SkippedReason = .unsure
    @Published var dose2ReasonNotes: String = ""
    @Published var hasWorkSafetyContext: Bool = false
    @Published var hasClinicalContext: Bool = false
    @Published var wakeRequirement: WakeRequirement = .unsure
    @Published var trackShiftWindow: Bool = false
    @Published var shiftStartAt: Date = Date()
    @Published var shiftEndAt: Date = Date()
    @Published var trackNextRequiredWake: Bool = false
    @Published var nextRequiredWakeAt: Date = Date()
    @Published var commuteMinutes: Int = 0
    @Published var drivingConfidence: Int = 3
    @Published var daytimeSleepiness: Int = 3
    @Published var cataplexyBurden: CataplexyBurden = .unsure
    @Published var sleepDisorders: [SleepDisorder] = []
    @Published var sleepDisorderNotes: String = ""
    @Published var coMedicationNotes: String = ""
    @Published var pharmacogenomicFastMetabolizer: Bool = false
    @Published var pharmacogenomicClinicianReviewed: Bool = false
    @Published var pharmacogenomicNotes: String = ""

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
    @Published var refluxBurden: SymptomBurden = .unsure
    @Published var restlessLegsBurden: SymptomBurden = .unsure
    @Published var bathroomUrgencyBurden: SymptomBurden = .unsure
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
    static let maxDoseAmountMg = 20_000
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
        self.originalTimingContext = [:]
        loadSavedSettings()
        configureDoseReconciliationState()
    }

    init(sessionId: String, sessionDate: String, existing: StoredMorningCheckIn) {
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.existingCheckInId = existing.id
        self.originalPhysicalSymptoms = Self.jsonDictionary(from: existing.physicalSymptomsJson)
        self.originalRespiratorySymptoms = Self.jsonDictionary(from: existing.respiratorySymptomsJson)
        self.originalSleepTherapy = Self.jsonDictionary(from: existing.sleepTherapyJson)
        self.originalSleepEnvironment = Self.jsonDictionary(from: existing.sleepEnvironmentJson)
        self.originalStressContext = Self.jsonDictionary(from: existing.stressContextJson)
        self.originalTimingContext = Self.jsonDictionary(from: existing.timingContextJson)
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
        hydrateTimingContextState(from: originalTimingContext)
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
        rememberSettings = Self.rememberSettingsDefault()
        if rememberSettings, let data = UserDefaults.standard.data(forKey: Self.savedSettingsKey),
           let saved = try? JSONDecoder().decode(SavedCheckInSettings.self, from: data) {
            applySavedSettings(saved)
        } else if rememberSettings,
                  let latest = SessionRepository.shared.fetchMostRecentMorningCheckIn(excluding: sessionDate) {
            applyCarryForward(from: latest)
        }
    }

    static func rememberSettingsDefault(userDefaults: UserDefaults = .standard) -> Bool {
        if let stored = userDefaults.object(forKey: rememberSettingsKey) as? Bool {
            return stored
        }
        return true
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
                sleepEnvironmentNotes: sleepEnvironmentNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sleepEnvironmentNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                sleepDisorders: sleepDisorders.map(\.rawValue),
                pharmacogenomicFastMetabolizer: pharmacogenomicFastMetabolizer,
                pharmacogenomicClinicianReviewed: pharmacogenomicClinicianReviewed,
                pharmacogenomicNotes: pharmacogenomicNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : pharmacogenomicNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                coMedicationNotes: coMedicationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : coMedicationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var effectiveDose2Status: Dose2ReconciliationChoice? {
        if loggedDose2Time != nil {
            return .taken
        }
        if loggedDose2Skipped {
            return .skipped
        }
        return dose2Reconciliation == .leaveAsIs ? nil : dose2Reconciliation
    }

    var showsDose2TakenReason: Bool {
        effectiveDose2Status == .taken
    }

    var showsDose2SkippedReason: Bool {
        effectiveDose2Status == .skipped
    }

    var derivedPainBurden: SymptomBurden {
        let highestPainIntensity = painEntries.map(\.intensity).max() ?? painSeverity
        if isMigraine || headacheSeverity == .migraine {
            return .extreme
        }
        switch highestPainIntensity {
        case 9...:
            return .extreme
        case 7...8:
            return .severe
        case 4...6:
            return .moderate
        case 1...3:
            return .mild
        default:
            if hasHeadache || muscleStiffness != .none || muscleSoreness != .none {
                return .mild
            }
            return .none
        }
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
            dict["painLocations"] = painLocations.map(\.rawValue)
            dict["painSeverity"] = painSeverity
            dict["painType"] = painType.rawValue
            dict["hasHeadache"] = hasHeadache
            dict["headacheSeverity"] = headacheSeverity.rawValue
            dict["headacheLocation"] = headacheLocation.rawValue
            dict["isMigraine"] = isMigraine
            dict["painBurden"] = derivedPainBurden.rawValue
            dict["refluxBurden"] = refluxBurden.rawValue
            dict["restlessLegsBurden"] = restlessLegsBurden.rawValue
            dict["bathroomUrgencyBurden"] = bathroomUrgencyBurden.rawValue
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

        var timingContextJson: String? = nil
        if nightType != .unsure
            || firstNightOffAfterWorkBlock
            || wakeType != .unsure
            || nextDayDemand != .unsure
            || dose2WakeMethod != .unsure
            || backToSleepDuration != .unsure
            || dose2TakenReason != .unsure
            || dose2SkippedReason != .unsure
            || hasWorkSafetyContext
            || hasClinicalContext
            || !dose2ReasonNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var dict = originalTimingContext
            dict["nightType"] = nightType.rawValue
            dict["firstNightOffAfterWorkBlock"] = firstNightOffAfterWorkBlock
            dict["wakeType"] = wakeType.rawValue
            dict["nextDayDemand"] = nextDayDemand.rawValue
            dict["dose2WakeMethod"] = dose2WakeMethod.rawValue
            dict["backToSleepDuration"] = backToSleepDuration.rawValue
            dict["dose2TakenReason"] = dose2TakenReason.rawValue
            dict["dose2SkippedReason"] = dose2SkippedReason.rawValue
            dict["hasWorkSafetyContext"] = hasWorkSafetyContext
            dict["hasClinicalContext"] = hasClinicalContext
            let trimmedDose2ReasonNotes = dose2ReasonNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedDose2ReasonNotes.isEmpty {
                dict.removeValue(forKey: "dose2ReasonNotes")
            } else {
                dict["dose2ReasonNotes"] = trimmedDose2ReasonNotes
            }
            if hasWorkSafetyContext {
                dict["wakeRequirement"] = wakeRequirement.rawValue
                dict["commuteMinutes"] = commuteMinutes
                dict["drivingConfidence"] = drivingConfidence
                dict["daytimeSleepiness"] = daytimeSleepiness
                dict["cataplexyBurden"] = cataplexyBurden.rawValue
                if trackShiftWindow {
                    dict["shiftStartAtUTC"] = Self.isoFormatter.string(from: shiftStartAt)
                    dict["shiftEndAtUTC"] = Self.isoFormatter.string(from: shiftEndAt)
                } else {
                    dict.removeValue(forKey: "shiftStartAtUTC")
                    dict.removeValue(forKey: "shiftEndAtUTC")
                }
                if trackNextRequiredWake {
                    dict["nextRequiredWakeAtUTC"] = Self.isoFormatter.string(from: nextRequiredWakeAt)
                } else {
                    dict.removeValue(forKey: "nextRequiredWakeAtUTC")
                }
            } else {
                [
                    "wakeRequirement",
                    "commuteMinutes",
                    "drivingConfidence",
                    "daytimeSleepiness",
                    "cataplexyBurden",
                    "shiftStartAtUTC",
                    "shiftEndAtUTC",
                    "nextRequiredWakeAtUTC"
                ].forEach { dict.removeValue(forKey: $0) }
            }
            if hasClinicalContext {
                dict["sleepDisorders"] = sleepDisorders.map(\.rawValue)
                if sleepDisorderNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    dict.removeValue(forKey: "sleepDisorderNotes")
                } else {
                    dict["sleepDisorderNotes"] = sleepDisorderNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if coMedicationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    dict.removeValue(forKey: "coMedicationNotes")
                } else {
                    dict["coMedicationNotes"] = coMedicationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                dict["pharmacogenomicFastMetabolizer"] = pharmacogenomicFastMetabolizer
                dict["pharmacogenomicClinicianReviewed"] = pharmacogenomicClinicianReviewed
                if pharmacogenomicNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    dict.removeValue(forKey: "pharmacogenomicNotes")
                } else {
                    dict["pharmacogenomicNotes"] = pharmacogenomicNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                [
                    "sleepDisorders",
                    "sleepDisorderNotes",
                    "coMedicationNotes",
                    "pharmacogenomicFastMetabolizer",
                    "pharmacogenomicClinicianReviewed",
                    "pharmacogenomicNotes"
                ].forEach { dict.removeValue(forKey: $0) }
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                timingContextJson = String(data: data, encoding: .utf8)
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
            timingContextJson: timingContextJson,
            notes: notes.isEmpty ? nil : notes
        )
    }

    func submit() async {
        isSubmitting = true
        saveSettingsForNextTime()
        let checkIn = toStoredCheckIn()
        await MainActor.run {
            applyDoseReconciliation()
            SessionRepository.shared.saveMorningCheckIn(checkIn, sessionDateOverride: sessionDate)
        }
        isSubmitting = false
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
        if let value = physical["refluxBurden"] as? String {
            refluxBurden = SymptomBurden(rawValue: value) ?? refluxBurden
        }
        if let value = physical["restlessLegsBurden"] as? String {
            restlessLegsBurden = SymptomBurden(rawValue: value) ?? restlessLegsBurden
        }
        if let value = physical["bathroomUrgencyBurden"] as? String {
            bathroomUrgencyBurden = SymptomBurden(rawValue: value) ?? bathroomUrgencyBurden
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

    private func hydrateTimingContextState(from timing: [String: Any]) {
        if let value = timing["nightType"] as? String {
            nightType = NightType(rawValue: value) ?? .unsure
        }
        if let value = timing["firstNightOffAfterWorkBlock"] as? Bool {
            firstNightOffAfterWorkBlock = value
        }
        if let value = timing["wakeType"] as? String {
            wakeType = WakeType(rawValue: value) ?? .unsure
        }
        if let value = timing["nextDayDemand"] as? String {
            nextDayDemand = NextDayDemand(rawValue: value) ?? .unsure
        }
        if let value = timing["dose2WakeMethod"] as? String {
            dose2WakeMethod = Dose2WakeMethod(rawValue: value) ?? .unsure
        }
        if let value = timing["backToSleepDuration"] as? String {
            backToSleepDuration = BackToSleepDuration(rawValue: value) ?? .unsure
        }
        if let value = timing["dose2TakenReason"] as? String {
            dose2TakenReason = Dose2TakenReason(rawValue: value) ?? .unsure
        }
        if let value = timing["dose2SkippedReason"] as? String {
            dose2SkippedReason = Dose2SkippedReason(rawValue: value) ?? .unsure
        }
        if let value = timing["dose2ReasonNotes"] as? String {
            dose2ReasonNotes = value
        }
        if let value = timing["hasWorkSafetyContext"] as? Bool {
            hasWorkSafetyContext = value
        }
        if let value = timing["hasClinicalContext"] as? Bool {
            hasClinicalContext = value
        }
        if let value = timing["wakeRequirement"] as? String {
            wakeRequirement = WakeRequirement(rawValue: value) ?? .unsure
        }
        if let value = Self.intValue(from: timing["commuteMinutes"]) {
            commuteMinutes = max(0, min(240, value))
        }
        if let value = Self.intValue(from: timing["drivingConfidence"]) {
            drivingConfidence = max(1, min(5, value))
            hasWorkSafetyContext = true
        }
        if let value = Self.intValue(from: timing["daytimeSleepiness"]) {
            daytimeSleepiness = max(1, min(5, value))
            hasWorkSafetyContext = true
        }
        if let value = timing["cataplexyBurden"] as? String {
            cataplexyBurden = CataplexyBurden(rawValue: value) ?? .unsure
            hasWorkSafetyContext = true
        }
        if let value = Self.dateValue(from: timing["shiftStartAtUTC"]) {
            shiftStartAt = value
            trackShiftWindow = true
            hasWorkSafetyContext = true
        }
        if let value = Self.dateValue(from: timing["shiftEndAtUTC"]) {
            shiftEndAt = value
            trackShiftWindow = true
            hasWorkSafetyContext = true
        }
        if let value = Self.dateValue(from: timing["nextRequiredWakeAtUTC"]) {
            nextRequiredWakeAt = value
            trackNextRequiredWake = true
            hasWorkSafetyContext = true
        }
        if let values = timing["sleepDisorders"] as? [String] {
            sleepDisorders = values.compactMap(SleepDisorder.init(rawValue:))
            hasClinicalContext = hasClinicalContext || !sleepDisorders.isEmpty
        }
        if let value = timing["sleepDisorderNotes"] as? String {
            sleepDisorderNotes = value
            hasClinicalContext = true
        }
        if let value = timing["coMedicationNotes"] as? String {
            coMedicationNotes = value
            hasClinicalContext = true
        }
        if let value = timing["pharmacogenomicFastMetabolizer"] as? Bool {
            pharmacogenomicFastMetabolizer = value
            hasClinicalContext = hasClinicalContext || value
        }
        if let value = timing["pharmacogenomicClinicianReviewed"] as? Bool {
            pharmacogenomicClinicianReviewed = value
            hasClinicalContext = hasClinicalContext || value
        }
        if let value = timing["pharmacogenomicNotes"] as? String {
            pharmacogenomicNotes = value
            hasClinicalContext = true
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
        if let savedSleepDisorders = saved.sleepDisorders {
            self.sleepDisorders = savedSleepDisorders.compactMap(SleepDisorder.init(rawValue:))
            self.hasClinicalContext = hasClinicalContext || !self.sleepDisorders.isEmpty
        }
        if let value = saved.pharmacogenomicFastMetabolizer {
            self.pharmacogenomicFastMetabolizer = value
            self.hasClinicalContext = hasClinicalContext || value
        }
        if let value = saved.pharmacogenomicClinicianReviewed {
            self.pharmacogenomicClinicianReviewed = value
            self.hasClinicalContext = hasClinicalContext || value
        }
        self.pharmacogenomicNotes = saved.pharmacogenomicNotes ?? ""
        self.coMedicationNotes = saved.coMedicationNotes ?? ""
        if !self.pharmacogenomicNotes.isEmpty || !self.coMedicationNotes.isEmpty {
            self.hasClinicalContext = true
        }
    }

    private func applyCarryForward(from checkIn: StoredMorningCheckIn) {
        sleepQuality = checkIn.sleepQuality
        feelRested = RestedLevel(rawValue: checkIn.feelRested) ?? feelRested
        grogginess = GrogginessLevel(rawValue: checkIn.grogginess) ?? grogginess
        sleepInertiaDuration = SleepInertiaDuration(rawValue: checkIn.sleepInertiaDuration) ?? sleepInertiaDuration
        dreamRecall = DreamRecallType(rawValue: checkIn.dreamRecall) ?? dreamRecall
        mentalClarity = checkIn.mentalClarity
        mood = MoodLevel(rawValue: checkIn.mood) ?? mood
        anxietyLevel = AnxietyLevel(rawValue: checkIn.anxietyLevel) ?? anxietyLevel
        stressLevel = checkIn.stressLevel
        readinessForDay = checkIn.readinessForDay

        hasPhysicalSymptoms = checkIn.hasPhysicalSymptoms
        hasRespiratorySymptoms = checkIn.hasRespiratorySymptoms
        usedSleepTherapy = checkIn.usedSleepTherapy
        hasSleepEnvironment = checkIn.hasSleepEnvironment
        hadSleepParalysis = checkIn.hadSleepParalysis
        hadHallucinations = checkIn.hadHallucinations
        hadAutomaticBehavior = checkIn.hadAutomaticBehavior
        fellOutOfBed = checkIn.fellOutOfBed
        hadConfusionOnWaking = checkIn.hadConfusionOnWaking

        hydratePhysicalState(from: Self.jsonDictionary(from: checkIn.physicalSymptomsJson))
        hydrateRespiratoryState(from: Self.jsonDictionary(from: checkIn.respiratorySymptomsJson))
        hydrateSleepTherapyState(from: Self.jsonDictionary(from: checkIn.sleepTherapyJson))
        hydrateSleepEnvironmentState(from: Self.jsonDictionary(from: checkIn.sleepEnvironmentJson))
        hydrateStressState(from: Self.jsonDictionary(from: checkIn.stressContextJson))
        hydrateTimingContextState(from: Self.carryForwardTimingContext(from: checkIn.timingContextJson))

        if usedSleepTherapy {
            showSleepTherapySection = true
        }
        if hasSleepEnvironment {
            showSleepEnvironmentSection = true
        }
        if hadSleepParalysis || hadHallucinations || hadAutomaticBehavior || fellOutOfBed || hadConfusionOnWaking {
            showNarcolepsySection = true
        }
        notes = ""
    }

    private static func carryForwardTimingContext(from json: String?) -> [String: Any] {
        var timing = jsonDictionary(from: json)
        [
            "dose2TakenReason",
            "dose2SkippedReason",
            "dose2ReasonNotes",
            "shiftStartAtUTC",
            "shiftEndAtUTC",
            "nextRequiredWakeAtUTC"
        ].forEach { timing.removeValue(forKey: $0) }
        return timing
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

    static func intValue(from value: Any?) -> Int? {
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

    private static func dateValue(from value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return isoFormatter.date(from: string)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
