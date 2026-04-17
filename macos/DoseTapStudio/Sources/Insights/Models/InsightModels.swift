import Foundation

enum InsightDoseEventKind: String, Sendable {
    case dose1
    case dose2
    case dose2Skipped
    case snooze
    case other

    init(eventType: EventType) {
        switch eventType {
        case .dose1_taken:
            self = .dose1
        case .dose2_taken:
            self = .dose2
        case .dose2_skipped:
            self = .dose2Skipped
        case .dose2_snoozed, .snooze:
            self = .snooze
        default:
            self = .other
        }
    }
}

struct InsightEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    let type: EventType
    let kind: InsightDoseEventKind
    let timestamp: Date
    let details: String?
}

struct InsightBundle: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let exportVersion: String?
    let appVersion: String?
    let exportedAtUTC: Date
    let timeZoneIdentifier: String?
    let localOffsetMinutes: Int?
    let consent: InsightConsentState?
    let exportWarnings: [String]?
    var importMetadata: InsightBundleImportMetadata?
    let sessions: [InsightSessionSupplement]

    init(
        schemaVersion: Int,
        exportVersion: String? = nil,
        appVersion: String? = nil,
        exportedAtUTC: Date,
        timeZoneIdentifier: String? = nil,
        localOffsetMinutes: Int? = nil,
        consent: InsightConsentState? = nil,
        exportWarnings: [String]? = nil,
        importMetadata: InsightBundleImportMetadata? = nil,
        sessions: [InsightSessionSupplement]
    ) {
        self.schemaVersion = schemaVersion
        self.exportVersion = exportVersion
        self.appVersion = appVersion
        self.exportedAtUTC = exportedAtUTC
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localOffsetMinutes = localOffsetMinutes
        self.consent = consent
        self.exportWarnings = exportWarnings
        self.importMetadata = importMetadata
        self.sessions = sessions
    }
}

struct InsightBundleImportMetadata: Codable, Hashable, Sendable {
    let fileName: String
    let byteCount: Int
    let sha256Hex: String
    let importedAtUTC: Date
}

enum InsightMetricFactCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case dosing
    case morning
    case context
    case appleHealth
    case whoop

    var label: String {
        switch self {
        case .dosing:
            return "Dosing"
        case .morning:
            return "Morning"
        case .context:
            return "Context"
        case .appleHealth:
            return "Apple Health"
        case .whoop:
            return "WHOOP"
        }
    }
}

struct InsightMetricFact: Identifiable, Hashable, Sendable {
    let id: String
    let key: String
    let title: String
    let category: InsightMetricFactCategory
    let displayValue: String
    let numericValue: Double?
    let unit: String?
    let source: String
}

struct InsightBundleEvent: Codable, Hashable, Sendable {
    let kind: String
    let eventType: String
    let occurredAtUTC: Date
    let details: String?
    let source: String?
    let deviceTime: String?
}

struct InsightSourceAvailability: Codable, Hashable, Sendable {
    let doseEvents: Bool
    let sleepEvents: Bool
    let preSleep: Bool
    let morningCheckIn: Bool
    let medications: Bool
    let healthKit: Bool
    let whoop: Bool
    let alarmDiagnostics: Bool
}

struct InsightConsentState: Codable, Hashable, Sendable {
    let appleHealthEnabled: Bool
    let appleHealthAvailable: Bool
    let appleHealthAuthorized: Bool
    let whoopEnabled: Bool
    let whoopConnected: Bool
}

struct InsightSessionSupplement: Codable, Hashable, Sendable {
    let sessionDate: String
    let dose1TimeUTC: Date?
    let dose2TimeUTC: Date?
    let rawEvents: [InsightBundleEvent]
    let normalizedEvents: [InsightBundleEvent]
    let sourceAvailability: InsightSourceAvailability?
    let metricProvenance: [String: String]?
    let dataQualityFlags: [String]?
    let exportExclusionReasons: [String]?
    let preSleep: InsightPreSleepSummary?
    let morning: InsightMorningSummary?
    let medications: [InsightMedicationSummary]
    let context: InsightSessionContext?
    let healthKit: InsightHealthKitSummary?
    let whoop: InsightWHOOPSummary?

    init(
        sessionDate: String,
        dose1TimeUTC: Date? = nil,
        dose2TimeUTC: Date? = nil,
        rawEvents: [InsightBundleEvent] = [],
        normalizedEvents: [InsightBundleEvent] = [],
        sourceAvailability: InsightSourceAvailability? = nil,
        metricProvenance: [String: String]? = nil,
        dataQualityFlags: [String]? = nil,
        exportExclusionReasons: [String]? = nil,
        preSleep: InsightPreSleepSummary?,
        morning: InsightMorningSummary?,
        medications: [InsightMedicationSummary],
        context: InsightSessionContext? = nil,
        healthKit: InsightHealthKitSummary? = nil,
        whoop: InsightWHOOPSummary? = nil
    ) {
        self.sessionDate = sessionDate
        self.dose1TimeUTC = dose1TimeUTC
        self.dose2TimeUTC = dose2TimeUTC
        self.rawEvents = rawEvents
        self.normalizedEvents = normalizedEvents
        self.sourceAvailability = sourceAvailability
        self.metricProvenance = metricProvenance
        self.dataQualityFlags = dataQualityFlags
        self.exportExclusionReasons = exportExclusionReasons
        self.preSleep = preSleep
        self.morning = morning
        self.medications = medications
        self.context = context
        self.healthKit = healthKit
        self.whoop = whoop
    }
}

struct InsightPreSleepSummary: Codable, Hashable, Sendable {
    let sessionId: String?
    let completionState: String
    let loggedAtUTC: String
    let stressLevel: Int?
    let stressDrivers: [String]
    let laterReason: String?
    let bodyPain: String?
    let caffeineSources: [String]
    let caffeineLastIntakeAtUTC: Date?
    let caffeineLastAmountMg: Int?
    let caffeineDailyTotalMg: Int?
    let alcohol: String?
    let alcoholLastDrinkAtUTC: Date?
    let alcoholLastAmountDrinks: Double?
    let alcoholDailyTotalDrinks: Double?
    let exercise: String?
    let exerciseLastAtUTC: Date?
    let exerciseDurationMinutes: Int?
    let napToday: String?
    let napCount: Int?
    let napTotalMinutes: Int?
    let napLastEndAtUTC: Date?
    let lateMeal: String?
    let lateMealEndedAtUTC: Date?
    let screensInBed: String?
    let screensLastUsedAtUTC: Date?
    let roomTemp: String?
    let noiseLevel: String?
    let sleepAids: [String]
    let notes: String?

    init(
        sessionId: String?,
        completionState: String,
        loggedAtUTC: String,
        stressLevel: Int?,
        stressDrivers: [String],
        laterReason: String?,
        bodyPain: String?,
        caffeineSources: [String],
        caffeineLastIntakeAtUTC: Date? = nil,
        caffeineLastAmountMg: Int? = nil,
        caffeineDailyTotalMg: Int? = nil,
        alcohol: String?,
        alcoholLastDrinkAtUTC: Date? = nil,
        alcoholLastAmountDrinks: Double? = nil,
        alcoholDailyTotalDrinks: Double? = nil,
        exercise: String?,
        exerciseLastAtUTC: Date? = nil,
        exerciseDurationMinutes: Int? = nil,
        napToday: String?,
        napCount: Int? = nil,
        napTotalMinutes: Int? = nil,
        napLastEndAtUTC: Date? = nil,
        lateMeal: String?,
        lateMealEndedAtUTC: Date? = nil,
        screensInBed: String?,
        screensLastUsedAtUTC: Date? = nil,
        roomTemp: String?,
        noiseLevel: String?,
        sleepAids: [String],
        notes: String?
    ) {
        self.sessionId = sessionId
        self.completionState = completionState
        self.loggedAtUTC = loggedAtUTC
        self.stressLevel = stressLevel
        self.stressDrivers = stressDrivers
        self.laterReason = laterReason
        self.bodyPain = bodyPain
        self.caffeineSources = caffeineSources
        self.caffeineLastIntakeAtUTC = caffeineLastIntakeAtUTC
        self.caffeineLastAmountMg = caffeineLastAmountMg
        self.caffeineDailyTotalMg = caffeineDailyTotalMg
        self.alcohol = alcohol
        self.alcoholLastDrinkAtUTC = alcoholLastDrinkAtUTC
        self.alcoholLastAmountDrinks = alcoholLastAmountDrinks
        self.alcoholDailyTotalDrinks = alcoholDailyTotalDrinks
        self.exercise = exercise
        self.exerciseLastAtUTC = exerciseLastAtUTC
        self.exerciseDurationMinutes = exerciseDurationMinutes
        self.napToday = napToday
        self.napCount = napCount
        self.napTotalMinutes = napTotalMinutes
        self.napLastEndAtUTC = napLastEndAtUTC
        self.lateMeal = lateMeal
        self.lateMealEndedAtUTC = lateMealEndedAtUTC
        self.screensInBed = screensInBed
        self.screensLastUsedAtUTC = screensLastUsedAtUTC
        self.roomTemp = roomTemp
        self.noiseLevel = noiseLevel
        self.sleepAids = sleepAids
        self.notes = notes
    }
}

struct InsightMorningSummary: Codable, Hashable, Sendable {
    let submittedAtUTC: Date
    let sleepQuality: Int
    let feelRested: String
    let grogginess: String
    let sleepInertiaDuration: String
    let dreamRecall: String
    let mentalClarity: Int
    let mood: String
    let anxietyLevel: String
    let stressLevel: Int?
    let stressDrivers: [String]
    let readinessForDay: Int
    let hadSleepParalysis: Bool
    let hadHallucinations: Bool
    let hadAutomaticBehavior: Bool
    let fellOutOfBed: Bool
    let hadConfusionOnWaking: Bool
    let sleepTherapyDevice: String?
    let sleepTherapyCompliance: Int?
    let drivingConfidence: Int?
    let daytimeSleepiness: Int?
    let cataplexyBurden: String?
    let painBurden: String?
    let anxietyBurden: String?
    let congestionBurden: String?
    let refluxBurden: String?
    let restlessLegsBurden: String?
    let bathroomUrgencyBurden: String?
    let sleepDisorders: [String]?
    let sleepDisorderNotes: String?
    let coMedicationNotes: String?
    let pharmacogenomicFastMetabolizer: Bool?
    let pharmacogenomicClinicianReviewed: Bool?
    let pharmacogenomicNotes: String?
    let firstNightOffAfterWorkBlock: Bool?
    let notes: String?

    init(
        submittedAtUTC: Date,
        sleepQuality: Int,
        feelRested: String,
        grogginess: String,
        sleepInertiaDuration: String,
        dreamRecall: String,
        mentalClarity: Int,
        mood: String,
        anxietyLevel: String,
        stressLevel: Int?,
        stressDrivers: [String],
        readinessForDay: Int,
        hadSleepParalysis: Bool,
        hadHallucinations: Bool,
        hadAutomaticBehavior: Bool,
        fellOutOfBed: Bool,
        hadConfusionOnWaking: Bool,
        sleepTherapyDevice: String? = nil,
        sleepTherapyCompliance: Int? = nil,
        drivingConfidence: Int? = nil,
        daytimeSleepiness: Int? = nil,
        cataplexyBurden: String? = nil,
        painBurden: String? = nil,
        anxietyBurden: String? = nil,
        congestionBurden: String? = nil,
        refluxBurden: String? = nil,
        restlessLegsBurden: String? = nil,
        bathroomUrgencyBurden: String? = nil,
        sleepDisorders: [String]? = nil,
        sleepDisorderNotes: String? = nil,
        coMedicationNotes: String? = nil,
        pharmacogenomicFastMetabolizer: Bool? = nil,
        pharmacogenomicClinicianReviewed: Bool? = nil,
        pharmacogenomicNotes: String? = nil,
        firstNightOffAfterWorkBlock: Bool? = nil,
        notes: String? = nil
    ) {
        self.submittedAtUTC = submittedAtUTC
        self.sleepQuality = sleepQuality
        self.feelRested = feelRested
        self.grogginess = grogginess
        self.sleepInertiaDuration = sleepInertiaDuration
        self.dreamRecall = dreamRecall
        self.mentalClarity = mentalClarity
        self.mood = mood
        self.anxietyLevel = anxietyLevel
        self.stressLevel = stressLevel
        self.stressDrivers = stressDrivers
        self.readinessForDay = readinessForDay
        self.hadSleepParalysis = hadSleepParalysis
        self.hadHallucinations = hadHallucinations
        self.hadAutomaticBehavior = hadAutomaticBehavior
        self.fellOutOfBed = fellOutOfBed
        self.hadConfusionOnWaking = hadConfusionOnWaking
        self.sleepTherapyDevice = sleepTherapyDevice
        self.sleepTherapyCompliance = sleepTherapyCompliance
        self.drivingConfidence = drivingConfidence
        self.daytimeSleepiness = daytimeSleepiness
        self.cataplexyBurden = cataplexyBurden
        self.painBurden = painBurden
        self.anxietyBurden = anxietyBurden
        self.congestionBurden = congestionBurden
        self.refluxBurden = refluxBurden
        self.restlessLegsBurden = restlessLegsBurden
        self.bathroomUrgencyBurden = bathroomUrgencyBurden
        self.sleepDisorders = sleepDisorders
        self.sleepDisorderNotes = sleepDisorderNotes
        self.coMedicationNotes = coMedicationNotes
        self.pharmacogenomicFastMetabolizer = pharmacogenomicFastMetabolizer
        self.pharmacogenomicClinicianReviewed = pharmacogenomicClinicianReviewed
        self.pharmacogenomicNotes = pharmacogenomicNotes
        self.firstNightOffAfterWorkBlock = firstNightOffAfterWorkBlock
        self.notes = notes
    }
}

struct InsightMedicationSummary: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let medicationId: String
    let doseMg: Int
    let doseUnit: String
    let formulation: String
    let takenAtUTC: Date
    let notes: String?
}

struct InsightHealthKitSummary: Codable, Hashable, Sendable {
    let totalSleepMinutes: Double
    let ttfwMinutes: Double?
    let wakeCount: Int
    let awakeMinutes: Double?
    let wakeAfterSleepOnsetMinutes: Double?
    let inBedMinutes: Double?
    let coreSleepMinutes: Double?
    let deepSleepMinutes: Double?
    let remSleepMinutes: Double?
    let bedTimeUTC: Date?
    let sleepOnsetUTC: Date?
    let finalWakeUTC: Date?
    let averageHeartRate: Double?
    let respiratoryRate: Double?
    let hrvMs: Double?
    let restingHeartRate: Double?
    let sources: [String]

    init(
        totalSleepMinutes: Double,
        ttfwMinutes: Double?,
        wakeCount: Int,
        awakeMinutes: Double? = nil,
        wakeAfterSleepOnsetMinutes: Double? = nil,
        inBedMinutes: Double? = nil,
        coreSleepMinutes: Double? = nil,
        deepSleepMinutes: Double? = nil,
        remSleepMinutes: Double? = nil,
        bedTimeUTC: Date?,
        sleepOnsetUTC: Date?,
        finalWakeUTC: Date?,
        averageHeartRate: Double?,
        respiratoryRate: Double?,
        hrvMs: Double?,
        restingHeartRate: Double?,
        sources: [String]
    ) {
        self.totalSleepMinutes = totalSleepMinutes
        self.ttfwMinutes = ttfwMinutes
        self.wakeCount = wakeCount
        self.awakeMinutes = awakeMinutes
        self.wakeAfterSleepOnsetMinutes = wakeAfterSleepOnsetMinutes
        self.inBedMinutes = inBedMinutes
        self.coreSleepMinutes = coreSleepMinutes
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.bedTimeUTC = bedTimeUTC
        self.sleepOnsetUTC = sleepOnsetUTC
        self.finalWakeUTC = finalWakeUTC
        self.averageHeartRate = averageHeartRate
        self.respiratoryRate = respiratoryRate
        self.hrvMs = hrvMs
        self.restingHeartRate = restingHeartRate
        self.sources = sources
    }
}

struct InsightWHOOPSummary: Codable, Hashable, Sendable {
    let sleepId: String
    let totalSleepMinutes: Int
    let remMinutes: Int
    let deepMinutes: Int
    let lightMinutes: Int
    let awakeMinutes: Int
    let inBedMinutes: Int?
    let disturbanceCount: Int
    let sleepEfficiency: Double?
    let sleepPerformance: Double?
    let sleepConsistency: Double?
    let respiratoryRate: Double?
    let recoveryScore: Double?
    let hrvMs: Double?
    let restingHeartRate: Double?
    let sleepNeedBaselineMinutes: Int?
    let sleepNeedDebtMinutes: Int?
    let sleepNeedStrainMinutes: Int?
    let sleepNeedNapMinutes: Int?
    let spo2Percentage: Double?
    let skinTempCelsius: Double?

    init(
        sleepId: String,
        totalSleepMinutes: Int,
        remMinutes: Int,
        deepMinutes: Int,
        lightMinutes: Int,
        awakeMinutes: Int,
        inBedMinutes: Int? = nil,
        disturbanceCount: Int,
        sleepEfficiency: Double?,
        sleepPerformance: Double? = nil,
        sleepConsistency: Double? = nil,
        respiratoryRate: Double?,
        recoveryScore: Double?,
        hrvMs: Double?,
        restingHeartRate: Double?,
        sleepNeedBaselineMinutes: Int? = nil,
        sleepNeedDebtMinutes: Int? = nil,
        sleepNeedStrainMinutes: Int? = nil,
        sleepNeedNapMinutes: Int? = nil,
        spo2Percentage: Double? = nil,
        skinTempCelsius: Double? = nil
    ) {
        self.sleepId = sleepId
        self.totalSleepMinutes = totalSleepMinutes
        self.remMinutes = remMinutes
        self.deepMinutes = deepMinutes
        self.lightMinutes = lightMinutes
        self.awakeMinutes = awakeMinutes
        self.inBedMinutes = inBedMinutes
        self.disturbanceCount = disturbanceCount
        self.sleepEfficiency = sleepEfficiency
        self.sleepPerformance = sleepPerformance
        self.sleepConsistency = sleepConsistency
        self.respiratoryRate = respiratoryRate
        self.recoveryScore = recoveryScore
        self.hrvMs = hrvMs
        self.restingHeartRate = restingHeartRate
        self.sleepNeedBaselineMinutes = sleepNeedBaselineMinutes
        self.sleepNeedDebtMinutes = sleepNeedDebtMinutes
        self.sleepNeedStrainMinutes = sleepNeedStrainMinutes
        self.sleepNeedNapMinutes = sleepNeedNapMinutes
        self.spo2Percentage = spo2Percentage
        self.skinTempCelsius = skinTempCelsius
    }
}

struct InsightAlarmContext: Codable, Hashable, Sendable {
    let scheduledForUTC: Date?
    let firstFireAtUTC: Date?
    let acknowledgedAtUTC: Date?
    let acknowledgementAction: String?
    let followUpDeliveredCount: Int
}

struct InsightDose2OutcomeContext: Codable, Hashable, Sendable {
    let takenSource: String?
    let takenAmountMg: Int?
    let takenEarly: Bool
    let takenLate: Bool
    let liveTakenReason: String?
    let liveTakenReasonNotes: String?
    let morningTakenReason: String?
    let morningTakenReasonNotes: String?
    let takenReason: String?
    let takenReasonNotes: String?
    let hasExtraDose: Bool
    let liveSkipReason: String?
    let liveSkipReasonNotes: String?
    let morningSkipReason: String?
    let morningSkipReasonNotes: String?
    let skipReason: String?
    let skipReasonNotes: String?
    let skipSource: String?
    let reasonMismatch: Bool
}

struct InsightSessionContext: Codable, Hashable, Sendable {
    let nextMorningWeekdayIndex: Int
    let nextMorningIsWeekend: Bool
    let scheduledWakeByUTC: Date?
    let scheduledWakeMinutesAfterMidnight: Int?
    let scheduleDayType: String?
    let previousScheduleDayType: String?
    let nextScheduleDayType: String?
    let explicitNightType: String?
    let firstNightOffAfterWorkBlock: Bool
    let explicitWakeType: String?
    let explicitNextDayDemand: String?
    let explicitDose2WakeMethod: String?
    let explicitBackToSleepDuration: String?
    let alarm: InsightAlarmContext?
    let dose2Outcome: InsightDose2OutcomeContext?
    let wakeSignal: String
    let wakeFinalLoggedAtUTC: Date?
    let snoozeCount: Int
    let scheduleMarkers: [String]
    let wakeRequirement: String?
    let shiftStartAtUTC: Date?
    let shiftEndAtUTC: Date?
    let nextRequiredWakeAtUTC: Date?
    let commuteMinutes: Int?
    let lateMealType: String?
    let lateMealEndedAtUTC: Date?
    let lateMealMinutesBeforeDose1: Int?
    let lateMealMinutesBeforeDose2: Int?
    let caffeineLastIntakeAtUTC: Date?
    let caffeineMinutesBeforeDose1: Int?
    let alcoholLastDrinkAtUTC: Date?
    let alcoholMinutesBeforeDose1: Int?
    let exerciseLastAtUTC: Date?
    let exerciseMinutesBeforeDose1: Int?
    let napLastEndAtUTC: Date?
    let napMinutesBeforeDose1: Int?
    let screensLastUsedAtUTC: Date?
    let screenMinutesBeforeDose1: Int?

    enum CodingKeys: String, CodingKey {
        case nextMorningWeekdayIndex
        case nextMorningIsWeekend
        case scheduledWakeByUTC
        case scheduledWakeMinutesAfterMidnight
        case scheduleDayType
        case previousScheduleDayType
        case nextScheduleDayType
        case explicitNightType
        case firstNightOffAfterWorkBlock
        case explicitWakeType
        case explicitNextDayDemand
        case explicitDose2WakeMethod
        case explicitBackToSleepDuration
        case alarm
        case dose2Outcome
        case wakeSignal
        case wakeFinalLoggedAtUTC
        case snoozeCount
        case scheduleMarkers
        case wakeRequirement
        case shiftStartAtUTC
        case shiftEndAtUTC
        case nextRequiredWakeAtUTC
        case commuteMinutes
        case lateMealType
        case lateMealEndedAtUTC
        case lateMealMinutesBeforeDose1
        case lateMealMinutesBeforeDose2
        case caffeineLastIntakeAtUTC
        case caffeineMinutesBeforeDose1
        case alcoholLastDrinkAtUTC
        case alcoholMinutesBeforeDose1
        case exerciseLastAtUTC
        case exerciseMinutesBeforeDose1
        case napLastEndAtUTC
        case napMinutesBeforeDose1
        case screensLastUsedAtUTC
        case screenMinutesBeforeDose1
    }

    init(
        nextMorningWeekdayIndex: Int,
        nextMorningIsWeekend: Bool,
        scheduledWakeByUTC: Date? = nil,
        scheduledWakeMinutesAfterMidnight: Int? = nil,
        scheduleDayType: String? = nil,
        previousScheduleDayType: String? = nil,
        nextScheduleDayType: String? = nil,
        explicitNightType: String? = nil,
        firstNightOffAfterWorkBlock: Bool = false,
        explicitWakeType: String? = nil,
        explicitNextDayDemand: String? = nil,
        explicitDose2WakeMethod: String? = nil,
        explicitBackToSleepDuration: String? = nil,
        alarm: InsightAlarmContext? = nil,
        dose2Outcome: InsightDose2OutcomeContext? = nil,
        wakeSignal: String,
        wakeFinalLoggedAtUTC: Date?,
        snoozeCount: Int,
        scheduleMarkers: [String],
        wakeRequirement: String? = nil,
        shiftStartAtUTC: Date? = nil,
        shiftEndAtUTC: Date? = nil,
        nextRequiredWakeAtUTC: Date? = nil,
        commuteMinutes: Int? = nil,
        lateMealType: String? = nil,
        lateMealEndedAtUTC: Date?,
        lateMealMinutesBeforeDose1: Int?,
        lateMealMinutesBeforeDose2: Int?,
        caffeineLastIntakeAtUTC: Date?,
        caffeineMinutesBeforeDose1: Int?,
        alcoholLastDrinkAtUTC: Date?,
        alcoholMinutesBeforeDose1: Int?,
        exerciseLastAtUTC: Date?,
        exerciseMinutesBeforeDose1: Int?,
        napLastEndAtUTC: Date?,
        napMinutesBeforeDose1: Int?,
        screensLastUsedAtUTC: Date?,
        screenMinutesBeforeDose1: Int?
    ) {
        self.nextMorningWeekdayIndex = nextMorningWeekdayIndex
        self.nextMorningIsWeekend = nextMorningIsWeekend
        self.scheduledWakeByUTC = scheduledWakeByUTC
        self.scheduledWakeMinutesAfterMidnight = scheduledWakeMinutesAfterMidnight
        self.scheduleDayType = scheduleDayType
        self.previousScheduleDayType = previousScheduleDayType
        self.nextScheduleDayType = nextScheduleDayType
        self.explicitNightType = explicitNightType
        self.firstNightOffAfterWorkBlock = firstNightOffAfterWorkBlock
        self.explicitWakeType = explicitWakeType
        self.explicitNextDayDemand = explicitNextDayDemand
        self.explicitDose2WakeMethod = explicitDose2WakeMethod
        self.explicitBackToSleepDuration = explicitBackToSleepDuration
        self.alarm = alarm
        self.dose2Outcome = dose2Outcome
        self.wakeSignal = wakeSignal
        self.wakeFinalLoggedAtUTC = wakeFinalLoggedAtUTC
        self.snoozeCount = snoozeCount
        self.scheduleMarkers = scheduleMarkers
        self.wakeRequirement = wakeRequirement
        self.shiftStartAtUTC = shiftStartAtUTC
        self.shiftEndAtUTC = shiftEndAtUTC
        self.nextRequiredWakeAtUTC = nextRequiredWakeAtUTC
        self.commuteMinutes = commuteMinutes
        self.lateMealType = lateMealType
        self.lateMealEndedAtUTC = lateMealEndedAtUTC
        self.lateMealMinutesBeforeDose1 = lateMealMinutesBeforeDose1
        self.lateMealMinutesBeforeDose2 = lateMealMinutesBeforeDose2
        self.caffeineLastIntakeAtUTC = caffeineLastIntakeAtUTC
        self.caffeineMinutesBeforeDose1 = caffeineMinutesBeforeDose1
        self.alcoholLastDrinkAtUTC = alcoholLastDrinkAtUTC
        self.alcoholMinutesBeforeDose1 = alcoholMinutesBeforeDose1
        self.exerciseLastAtUTC = exerciseLastAtUTC
        self.exerciseMinutesBeforeDose1 = exerciseMinutesBeforeDose1
        self.napLastEndAtUTC = napLastEndAtUTC
        self.napMinutesBeforeDose1 = napMinutesBeforeDose1
        self.screensLastUsedAtUTC = screensLastUsedAtUTC
        self.screenMinutesBeforeDose1 = screenMinutesBeforeDose1
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nextMorningWeekdayIndex = try container.decode(Int.self, forKey: .nextMorningWeekdayIndex)
        self.nextMorningIsWeekend = try container.decode(Bool.self, forKey: .nextMorningIsWeekend)
        self.scheduledWakeByUTC = try container.decodeIfPresent(Date.self, forKey: .scheduledWakeByUTC)
        self.scheduledWakeMinutesAfterMidnight = try container.decodeIfPresent(Int.self, forKey: .scheduledWakeMinutesAfterMidnight)
        self.scheduleDayType = try container.decodeIfPresent(String.self, forKey: .scheduleDayType)
        self.previousScheduleDayType = try container.decodeIfPresent(String.self, forKey: .previousScheduleDayType)
        self.nextScheduleDayType = try container.decodeIfPresent(String.self, forKey: .nextScheduleDayType)
        self.explicitNightType = try container.decodeIfPresent(String.self, forKey: .explicitNightType)
        self.firstNightOffAfterWorkBlock = try container.decodeIfPresent(Bool.self, forKey: .firstNightOffAfterWorkBlock) ?? false
        self.explicitWakeType = try container.decodeIfPresent(String.self, forKey: .explicitWakeType)
        self.explicitNextDayDemand = try container.decodeIfPresent(String.self, forKey: .explicitNextDayDemand)
        self.explicitDose2WakeMethod = try container.decodeIfPresent(String.self, forKey: .explicitDose2WakeMethod)
        self.explicitBackToSleepDuration = try container.decodeIfPresent(String.self, forKey: .explicitBackToSleepDuration)
        self.alarm = try container.decodeIfPresent(InsightAlarmContext.self, forKey: .alarm)
        self.dose2Outcome = try container.decodeIfPresent(InsightDose2OutcomeContext.self, forKey: .dose2Outcome)
        self.wakeSignal = try container.decode(String.self, forKey: .wakeSignal)
        self.wakeFinalLoggedAtUTC = try container.decodeIfPresent(Date.self, forKey: .wakeFinalLoggedAtUTC)
        self.snoozeCount = try container.decode(Int.self, forKey: .snoozeCount)
        self.scheduleMarkers = try container.decodeIfPresent([String].self, forKey: .scheduleMarkers) ?? []
        self.wakeRequirement = try container.decodeIfPresent(String.self, forKey: .wakeRequirement)
        self.shiftStartAtUTC = try container.decodeIfPresent(Date.self, forKey: .shiftStartAtUTC)
        self.shiftEndAtUTC = try container.decodeIfPresent(Date.self, forKey: .shiftEndAtUTC)
        self.nextRequiredWakeAtUTC = try container.decodeIfPresent(Date.self, forKey: .nextRequiredWakeAtUTC)
        self.commuteMinutes = try container.decodeIfPresent(Int.self, forKey: .commuteMinutes)
        self.lateMealType = try container.decodeIfPresent(String.self, forKey: .lateMealType)
        self.lateMealEndedAtUTC = try container.decodeIfPresent(Date.self, forKey: .lateMealEndedAtUTC)
        self.lateMealMinutesBeforeDose1 = try container.decodeIfPresent(Int.self, forKey: .lateMealMinutesBeforeDose1)
        self.lateMealMinutesBeforeDose2 = try container.decodeIfPresent(Int.self, forKey: .lateMealMinutesBeforeDose2)
        self.caffeineLastIntakeAtUTC = try container.decodeIfPresent(Date.self, forKey: .caffeineLastIntakeAtUTC)
        self.caffeineMinutesBeforeDose1 = try container.decodeIfPresent(Int.self, forKey: .caffeineMinutesBeforeDose1)
        self.alcoholLastDrinkAtUTC = try container.decodeIfPresent(Date.self, forKey: .alcoholLastDrinkAtUTC)
        self.alcoholMinutesBeforeDose1 = try container.decodeIfPresent(Int.self, forKey: .alcoholMinutesBeforeDose1)
        self.exerciseLastAtUTC = try container.decodeIfPresent(Date.self, forKey: .exerciseLastAtUTC)
        self.exerciseMinutesBeforeDose1 = try container.decodeIfPresent(Int.self, forKey: .exerciseMinutesBeforeDose1)
        self.napLastEndAtUTC = try container.decodeIfPresent(Date.self, forKey: .napLastEndAtUTC)
        self.napMinutesBeforeDose1 = try container.decodeIfPresent(Int.self, forKey: .napMinutesBeforeDose1)
        self.screensLastUsedAtUTC = try container.decodeIfPresent(Date.self, forKey: .screensLastUsedAtUTC)
        self.screenMinutesBeforeDose1 = try container.decodeIfPresent(Int.self, forKey: .screenMinutesBeforeDose1)
    }
}

enum InsightNightTag: String, Hashable, Sendable {
    case workNight = "work_night"
    case offNight = "off_night"
    case transitionIntoWorkBlock = "transition_into_work_block"
    case transitionOutOfWorkBlock = "transition_out_of_work_block"
    case postShiftRecoveryNight = "post_shift_recovery_night"
    case weekdayDemandNight = "weekday_demand_night"
    case weekendNight = "weekend_night"
    case naturalWakeNight = "natural_wake_night"
    case alarmDependentNight = "alarm_dependent_night"
    case forcedWakeNight = "forced_wake_night"
    case highStressNight = "high_stress_night"
    case highPainNight = "high_pain_night"
    case highSleepDisruptionNight = "high_sleep_disruption_night"
    case scheduleMarkedNight = "schedule_marked_night"
    case highDemandNextDay = "high_demand_next_day"
    case workSafetyContextNight = "work_safety_context_night"
    case clinicalContextNight = "clinical_context_night"
    case sleepTherapyNight = "sleep_therapy_night"
    case fastMetabolizerReferenceNight = "fast_metabolizer_reference_night"
    case highSleepinessDay = "high_sleepiness_day"
    case lowDrivingConfidenceDay = "low_driving_confidence_day"

    var label: String {
        switch self {
        case .workNight:
            return "Work Night"
        case .offNight:
            return "Off Night"
        case .transitionIntoWorkBlock:
            return "Transition Into Work"
        case .transitionOutOfWorkBlock:
            return "Transition Out Of Work"
        case .postShiftRecoveryNight:
            return "Post-Shift Recovery"
        case .weekdayDemandNight:
            return "Weekday Demand"
        case .weekendNight:
            return "Weekend"
        case .naturalWakeNight:
            return "Natural Wake"
        case .alarmDependentNight:
            return "Alarm-Dependent"
        case .forcedWakeNight:
            return "Forced Wake"
        case .highStressNight:
            return "High Stress"
        case .highPainNight:
            return "High Pain"
        case .highSleepDisruptionNight:
            return "High Disruption"
        case .scheduleMarkedNight:
            return "Schedule-Marked"
        case .highDemandNextDay:
            return "High-Demand Next Day"
        case .workSafetyContextNight:
            return "Work / Safety Context"
        case .clinicalContextNight:
            return "Clinical Context"
        case .sleepTherapyNight:
            return "Sleep Therapy"
        case .fastMetabolizerReferenceNight:
            return "Fast-Metabolizer Reference"
        case .highSleepinessDay:
            return "High Sleepiness"
        case .lowDrivingConfidenceDay:
            return "Low Driving Confidence"
        }
    }
}

enum InsightConfidenceBucket: String, Hashable, Sendable {
    case high
    case medium
    case low
    case insufficient

    var label: String { rawValue.capitalized }
}

struct InsightNightClassification: Hashable, Sendable {
    let tags: [InsightNightTag]
    let comparableCohortKey: String
    let exclusionReasons: [String]
    let confidenceBucket: InsightConfidenceBucket
    let countsTowardRecommendationTraining: Bool
}

struct InsightSession: Identifiable, Hashable, Sendable {
    let id: String
    let sessionDate: String
    let startedAt: Date?
    let endedAt: Date?
    let dose1Time: Date?
    let dose2Time: Date?
    let dose2Skipped: Bool
    let snoozeCount: Int
    let adherenceFlag: String?
    let sleepEfficiency: Double?
    let whoopRecovery: Int?
    let averageHeartRate: Double?
    let notes: String?
    let events: [InsightEvent]
    let preSleep: InsightPreSleepSummary?
    let morning: InsightMorningSummary?
    let medications: [InsightMedicationSummary]
    let context: InsightSessionContext?
    let healthKit: InsightHealthKitSummary?
    let whoop: InsightWHOOPSummary?
    let rawEvents: [InsightBundleEvent]
    let normalizedEvents: [InsightBundleEvent]
    let sourceAvailability: InsightSourceAvailability?
    let metricProvenance: [String: String]
    let dataQualityFlags: [String]
    let exportExclusionReasons: [String]
    let validationFlags: [String]

    init(
        id: String,
        sessionDate: String,
        startedAt: Date?,
        endedAt: Date?,
        dose1Time: Date?,
        dose2Time: Date?,
        dose2Skipped: Bool,
        snoozeCount: Int,
        adherenceFlag: String?,
        sleepEfficiency: Double?,
        whoopRecovery: Int?,
        averageHeartRate: Double?,
        notes: String?,
        events: [InsightEvent],
        preSleep: InsightPreSleepSummary?,
        morning: InsightMorningSummary?,
        medications: [InsightMedicationSummary],
        context: InsightSessionContext? = nil,
        healthKit: InsightHealthKitSummary? = nil,
        whoop: InsightWHOOPSummary? = nil,
        rawEvents: [InsightBundleEvent] = [],
        normalizedEvents: [InsightBundleEvent] = [],
        sourceAvailability: InsightSourceAvailability? = nil,
        metricProvenance: [String: String] = [:],
        dataQualityFlags: [String] = [],
        exportExclusionReasons: [String] = [],
        validationFlags: [String] = []
    ) {
        self.id = id
        self.sessionDate = sessionDate
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.dose1Time = dose1Time
        self.dose2Time = dose2Time
        self.dose2Skipped = dose2Skipped
        self.snoozeCount = snoozeCount
        self.adherenceFlag = adherenceFlag
        self.sleepEfficiency = sleepEfficiency
        self.whoopRecovery = whoopRecovery
        self.averageHeartRate = averageHeartRate
        self.notes = notes
        self.events = events
        self.preSleep = preSleep
        self.morning = morning
        self.medications = medications
        self.context = context
        self.healthKit = healthKit
        self.whoop = whoop
        self.rawEvents = rawEvents
        self.normalizedEvents = normalizedEvents
        self.sourceAvailability = sourceAvailability
        self.metricProvenance = metricProvenance
        self.dataQualityFlags = dataQualityFlags
        self.exportExclusionReasons = exportExclusionReasons
        self.validationFlags = validationFlags
    }

    var intervalMinutes: Int? {
        guard let dose1Time, let dose2Time else { return nil }
        let delta = Int(dose2Time.timeIntervalSince(dose1Time) / 60)
        return delta >= 0 ? delta : nil
    }

    var anchoredIntervalMinutes: Int? {
        if let intervalMinutes {
            return Self.clampAnchoredInterval(intervalMinutes)
        }
        guard let dose1Time else { return nil }
        if let scheduledForUTC = context?.alarm?.scheduledForUTC {
            return Self.clampAnchoredInterval(Int(scheduledForUTC.timeIntervalSince(dose1Time) / 60))
        }
        if let firstFireAtUTC = context?.alarm?.firstFireAtUTC {
            return Self.clampAnchoredInterval(Int(firstFireAtUTC.timeIntervalSince(dose1Time) / 60))
        }
        if let scheduledWakeByUTC = context?.scheduledWakeByUTC {
            return Self.clampAnchoredInterval(Int(scheduledWakeByUTC.timeIntervalSince(dose1Time) / 60))
        }
        return nil
    }

    var eventCount: Int {
        events.count
    }

    var medicationCount: Int {
        medications.count
    }

    var preSleepStressLevel: Int? {
        preSleep?.stressLevel
    }

    var morningSleepQuality: Int? {
        morning?.sleepQuality
    }

    var morningReadiness: Int? {
        morning?.readinessForDay
    }

    var totalSleepMinutes: Double? {
        if let healthKit {
            return healthKit.totalSleepMinutes
        }
        if let whoop {
            return Double(whoop.totalSleepMinutes)
        }
        return nil
    }

    var wakeDisruptionCount: Int? {
        if let healthKit {
            return healthKit.wakeCount
        }
        return whoop?.disturbanceCount
    }

    var hrvMs: Double? {
        whoop?.hrvMs ?? healthKit?.hrvMs
    }

    var respiratoryRate: Double? {
        whoop?.respiratoryRate ?? healthKit?.respiratoryRate
    }

    var restingHeartRate: Double? {
        whoop?.restingHeartRate ?? healthKit?.restingHeartRate
    }

    var restorativeSleepMinutes: Double? {
        if let healthKitDeep = healthKit?.deepSleepMinutes, let healthKitREM = healthKit?.remSleepMinutes {
            return healthKitDeep + healthKitREM
        }
        if let whoop {
            return Double(whoop.deepMinutes + whoop.remMinutes)
        }
        return nil
    }

    var restorativeSleepRatio: Double? {
        guard let restorativeSleepMinutes, let totalSleepMinutes, totalSleepMinutes > 0 else { return nil }
        return restorativeSleepMinutes / totalSleepMinutes
    }

    var coreOrLightSleepMinutes: Double? {
        if let coreSleepMinutes = healthKit?.coreSleepMinutes {
            return coreSleepMinutes
        }
        if let whoop {
            return Double(whoop.lightMinutes)
        }
        return nil
    }

    var deepSleepRatio: Double? {
        guard let totalSleepMinutes, totalSleepMinutes > 0 else { return nil }
        if let deepSleepMinutes = healthKit?.deepSleepMinutes {
            return deepSleepMinutes / totalSleepMinutes
        }
        if let whoop {
            return Double(whoop.deepMinutes) / totalSleepMinutes
        }
        return nil
    }

    var remSleepRatio: Double? {
        guard let totalSleepMinutes, totalSleepMinutes > 0 else { return nil }
        if let remSleepMinutes = healthKit?.remSleepMinutes {
            return remSleepMinutes / totalSleepMinutes
        }
        if let whoop {
            return Double(whoop.remMinutes) / totalSleepMinutes
        }
        return nil
    }

    var coreOrLightSleepRatio: Double? {
        guard let totalSleepMinutes, totalSleepMinutes > 0, let coreOrLightSleepMinutes else { return nil }
        return coreOrLightSleepMinutes / totalSleepMinutes
    }

    var sleepStageBalanceScore: Double? {
        guard let deepSleepRatio, let remSleepRatio, let coreOrLightSleepRatio else { return nil }
        let scores = [
            Self.rangeBalanceScore(value: deepSleepRatio, targetMin: 0.13, targetMax: 0.23, tolerance: 0.10),
            Self.rangeBalanceScore(value: remSleepRatio, targetMin: 0.20, targetMax: 0.30, tolerance: 0.10),
            Self.rangeBalanceScore(value: coreOrLightSleepRatio, targetMin: 0.45, targetMax: 0.65, tolerance: 0.15)
        ]
        return scores.reduce(0, +) / Double(scores.count)
    }

    var operationalRiskRate: Double {
        var signals = 0.0
        var total = 0.0

        func add(_ condition: Bool) {
            total += 1
            if condition {
                signals += 1
            }
        }

        add(likelyNaturalWake == false)
        add(classification.tags.contains(.forcedWakeNight))
        add((context?.snoozeCount ?? 0) > 0)
        add(hasLongCommuteBurden)
        add((morning?.daytimeSleepiness ?? 0) >= 4)
        add((morning?.drivingConfidence ?? 5) <= 2)
        add(normalizedContextValue(context?.dose2Outcome?.takenReason) != nil && hasDose2TimingExceptionReason)

        guard total > 0 else { return 0 }
        return signals / total
    }

    var hasSkipOrLateRiskSignal: Bool {
        if dose2Skipped || isLateDose2 || isMissingOutcome || wasDose2ReconciledInMorning || hasDose2ReasonMismatch {
            return true
        }
        if context?.dose2Outcome?.takenLate == true {
            return true
        }
        return normalizedContextValue(context?.dose2Outcome?.skipReason) != nil
    }

    var hasSupplementalContext: Bool {
        preSleep != nil || morning != nil || !medications.isEmpty || context != nil || healthKit != nil || whoop != nil
    }

    var hasWorkSafetyContext: Bool {
        morning?.drivingConfidence != nil ||
        morning?.daytimeSleepiness != nil ||
        morning?.cataplexyBurden != nil ||
        context?.wakeRequirement != nil ||
        context?.shiftStartAtUTC != nil ||
        context?.shiftEndAtUTC != nil ||
        context?.nextRequiredWakeAtUTC != nil ||
        context?.commuteMinutes != nil
    }

    var hasClinicalContext: Bool {
        !((morning?.sleepDisorders ?? []).isEmpty) ||
        morning?.sleepDisorderNotes?.isEmpty == false ||
        morning?.coMedicationNotes?.isEmpty == false ||
        morning?.sleepTherapyDevice?.isEmpty == false ||
        morning?.sleepTherapyCompliance != nil ||
        morning?.pharmacogenomicFastMetabolizer == true ||
        morning?.pharmacogenomicClinicianReviewed == true ||
        morning?.pharmacogenomicNotes?.isEmpty == false ||
        hasElevatedSymptomBurden
    }

    var hasSleepTherapyContext: Bool {
        morning?.sleepTherapyDevice?.isEmpty == false || morning?.sleepTherapyCompliance != nil
    }

    var hasFastMetabolizerReference: Bool {
        morning?.pharmacogenomicFastMetabolizer == true
    }

    var hasLongCommuteBurden: Bool {
        (context?.commuteMinutes ?? 0) >= 45
    }

    var bathroomCount: Int {
        events.filter { $0.type == .bathroom }.count
    }

    var hasElevatedSymptomBurden: Bool {
        [
            morning?.painBurden,
            morning?.anxietyBurden,
            morning?.congestionBurden,
            morning?.refluxBurden,
            morning?.restlessLegsBurden,
            morning?.bathroomUrgencyBurden
        ].contains(where: hasModerateOrGreaterBurden)
    }

    var lightsOutCount: Int {
        events.filter { $0.type == .lights_out }.count
    }

    var wakeFinalCount: Int {
        events.filter { $0.type == .wake_final }.count
    }

    var isLateDose2: Bool {
        guard let intervalMinutes else { return false }
        return intervalMinutes > 240
    }

    var isOnTimeDose2: Bool {
        guard let intervalMinutes else { return false }
        return (150...240).contains(intervalMinutes)
    }

    var isMissingOutcome: Bool {
        dose1Time != nil && dose2Time == nil && !dose2Skipped
    }

    var completenessScore: Double {
        var score = 0.0
        if dose1Time != nil && (dose2Time != nil || dose2Skipped) { score += 0.4 }
        if sleepEfficiency != nil { score += 0.2 }
        if whoopRecovery != nil || averageHeartRate != nil { score += 0.1 }
        if !events.isEmpty { score += 0.2 }
        if !qualityFlags.isEmpty { score -= 0.1 }
        return max(0.0, min(1.0, score))
    }

    var qualityFlags: [String] {
        var flags: [String] = []
        if isMissingOutcome {
            flags.append("Missing Dose 2 outcome")
        }
        if wasDose2ReconciledInMorning {
            flags.append("Dose 2 reconciled in morning")
        }
        if context?.dose2Outcome?.takenEarly == true {
            flags.append("Dose 2 taken early")
        }
        if hasDose2TimingExceptionReason {
            flags.append("Dose 2 timing exception logged")
        }
        if hasDose2ReasonMismatch {
            flags.append("Dose 2 reason mismatch between live and morning logs")
        }
        if normalizedContextValue(context?.dose2Outcome?.skipReason) == "slept_through" {
            flags.append("Slept through Dose 2 window")
        }
        if lightsOutCount > 1 {
            flags.append("Duplicate lights out logs")
        }
        if wakeFinalCount > 1 {
            flags.append("Duplicate wake-final logs")
        }
        if intervalMinutes == nil && dose2Time != nil {
            flags.append("Dose interval unavailable")
        }
        if morning == nil {
            flags.append("Missing morning check-in")
        }
        flags.append(contentsOf: dataQualityFlags)
        flags.append(contentsOf: validationFlags)
        return Array(Set(flags)).sorted()
    }

    var qualitySummary: String {
        qualityFlags.first ?? "Clean"
    }

    var sourceAvailabilitySummary: [String] {
        guard let sourceAvailability else { return [] }
        var sources: [String] = []
        if sourceAvailability.doseEvents { sources.append("Dose") }
        if sourceAvailability.sleepEvents { sources.append("Sleep") }
        if sourceAvailability.preSleep { sources.append("Pre-sleep") }
        if sourceAvailability.morningCheckIn { sources.append("Morning") }
        if sourceAvailability.medications { sources.append("Meds") }
        if sourceAvailability.healthKit { sources.append("Apple Health") }
        if sourceAvailability.whoop { sources.append("WHOOP") }
        if sourceAvailability.alarmDiagnostics { sources.append("Alarm diagnostics") }
        return sources
    }

    var normalizedFacts: [InsightMetricFact] {
        var facts: [InsightMetricFact] = []

        func addFact(
            key: String,
            title: String,
            category: InsightMetricFactCategory,
            numericValue: Double?,
            displayValue: String,
            unit: String? = nil,
            fallbackSource: String
        ) {
            facts.append(
                InsightMetricFact(
                    id: "\(sessionDate)::\(key)",
                    key: key,
                    title: title,
                    category: category,
                    displayValue: displayValue,
                    numericValue: numericValue,
                    unit: unit,
                    source: metricProvenance[key] ?? fallbackSource
                )
            )
        }

        func addBurdenFact(key: String, title: String, value: String?) {
            guard let normalized = normalizedContextValue(value) else { return }
            addFact(
                key: key,
                title: title,
                category: .morning,
                numericValue: Double(symptomBurdenRank(normalized)),
                displayValue: labelForSymptomBurden(normalized) ?? normalized.capitalized,
                fallbackSource: "manual"
            )
        }

        if let intervalMinutes {
            addFact(
                key: "dose2_interval_minutes",
                title: "Dose 2 interval",
                category: .dosing,
                numericValue: Double(intervalMinutes),
                displayValue: "\(intervalMinutes)m",
                unit: "min",
                fallbackSource: "derived"
            )
        }

        if let morningSleepQuality {
            addFact(
                key: "morning_sleep_quality",
                title: "Morning sleep quality",
                category: .morning,
                numericValue: Double(morningSleepQuality),
                displayValue: "\(morningSleepQuality)/5",
                fallbackSource: "manual"
            )
        }

        if let morningReadiness {
            addFact(
                key: "morning_readiness",
                title: "Morning readiness",
                category: .morning,
                numericValue: Double(morningReadiness),
                displayValue: "\(morningReadiness)/5",
                fallbackSource: "manual"
            )
        }

        if let drivingConfidence = morning?.drivingConfidence {
            addFact(
                key: "driving_confidence",
                title: "Driving confidence",
                category: .morning,
                numericValue: Double(drivingConfidence),
                displayValue: "\(drivingConfidence)/5",
                fallbackSource: "manual"
            )
        }

        if let daytimeSleepiness = morning?.daytimeSleepiness {
            addFact(
                key: "daytime_sleepiness",
                title: "Daytime sleepiness",
                category: .morning,
                numericValue: Double(daytimeSleepiness),
                displayValue: "\(daytimeSleepiness)/5",
                fallbackSource: "manual"
            )
        }

        addBurdenFact(key: "pain_burden", title: "Pain burden", value: morning?.painBurden)
        addBurdenFact(key: "anxiety_burden", title: "Anxiety burden", value: morning?.anxietyBurden)
        addBurdenFact(key: "congestion_burden", title: "Congestion burden", value: morning?.congestionBurden)
        addBurdenFact(key: "reflux_burden", title: "Reflux burden", value: morning?.refluxBurden)
        addBurdenFact(key: "restless_legs_burden", title: "Restless legs burden", value: morning?.restlessLegsBurden)
        addBurdenFact(key: "bathroom_urgency_burden", title: "Bathroom urgency burden", value: morning?.bathroomUrgencyBurden)

        if morning?.firstNightOffAfterWorkBlock == true || context?.firstNightOffAfterWorkBlock == true {
            addFact(
                key: "first_night_off_after_work_block",
                title: "First night off after work block",
                category: .context,
                numericValue: 1,
                displayValue: "Yes",
                fallbackSource: "manual"
            )
        }

        if let preSleepStressLevel {
            addFact(
                key: "pre_sleep_stress",
                title: "Pre-sleep stress",
                category: .context,
                numericValue: Double(preSleepStressLevel),
                displayValue: "\(preSleepStressLevel)/5",
                fallbackSource: "manual"
            )
        }

        if let totalSleepMinutes {
            addFact(
                key: "total_sleep_minutes",
                title: "Total sleep",
                category: healthKit != nil ? .appleHealth : .whoop,
                numericValue: totalSleepMinutes,
                displayValue: Self.minutesDisplay(totalSleepMinutes),
                unit: "min",
                fallbackSource: healthKit != nil ? "healthkit" : "whoop"
            )
        }

        if let sleepEfficiency {
            addFact(
                key: "sleep_efficiency",
                title: "Sleep efficiency",
                category: whoop != nil ? .whoop : .appleHealth,
                numericValue: sleepEfficiency,
                displayValue: Self.percentDisplay(sleepEfficiency),
                unit: "%",
                fallbackSource: whoop != nil ? "whoop" : "derived"
            )
        }

        if let averageHeartRate {
            addFact(
                key: "average_heart_rate",
                title: "Average heart rate",
                category: healthKit?.averageHeartRate != nil ? .appleHealth : .whoop,
                numericValue: averageHeartRate,
                displayValue: Self.decimalDisplay(averageHeartRate, unit: "bpm"),
                unit: "bpm",
                fallbackSource: healthKit?.averageHeartRate != nil ? "healthkit" : "whoop"
            )
        }

        if let hrvMs {
            addFact(
                key: "hrv_ms",
                title: "HRV",
                category: whoop?.hrvMs != nil ? .whoop : .appleHealth,
                numericValue: hrvMs,
                displayValue: Self.decimalDisplay(hrvMs, unit: "ms"),
                unit: "ms",
                fallbackSource: whoop?.hrvMs != nil ? "whoop" : "healthkit"
            )
        }

        if let respiratoryRate {
            addFact(
                key: "respiratory_rate",
                title: "Respiratory rate",
                category: whoop?.respiratoryRate != nil ? .whoop : .appleHealth,
                numericValue: respiratoryRate,
                displayValue: Self.decimalDisplay(respiratoryRate, unit: "br/min"),
                unit: "br/min",
                fallbackSource: whoop?.respiratoryRate != nil ? "whoop" : "healthkit"
            )
        }

        if let restingHeartRate {
            addFact(
                key: "resting_heart_rate",
                title: "Resting heart rate",
                category: whoop?.restingHeartRate != nil ? .whoop : .appleHealth,
                numericValue: restingHeartRate,
                displayValue: Self.decimalDisplay(restingHeartRate, unit: "bpm"),
                unit: "bpm",
                fallbackSource: whoop?.restingHeartRate != nil ? "whoop" : "healthkit"
            )
        }

        if let restorativeSleepRatio {
            addFact(
                key: "restorative_sleep_ratio",
                title: "Restorative sleep ratio",
                category: healthKit != nil ? .appleHealth : .whoop,
                numericValue: restorativeSleepRatio,
                displayValue: Self.percentDisplay(restorativeSleepRatio * 100),
                unit: "%",
                fallbackSource: "derived"
            )
        }

        if let deepSleepRatio {
            addFact(
                key: "deep_sleep_ratio",
                title: "Deep sleep ratio",
                category: healthKit != nil ? .appleHealth : .whoop,
                numericValue: deepSleepRatio,
                displayValue: Self.percentDisplay(deepSleepRatio * 100),
                unit: "%",
                fallbackSource: "derived"
            )
        }

        if let remSleepRatio {
            addFact(
                key: "rem_sleep_ratio",
                title: "REM sleep ratio",
                category: healthKit != nil ? .appleHealth : .whoop,
                numericValue: remSleepRatio,
                displayValue: Self.percentDisplay(remSleepRatio * 100),
                unit: "%",
                fallbackSource: "derived"
            )
        }

        if let coreOrLightSleepRatio {
            addFact(
                key: "core_or_light_sleep_ratio",
                title: "Core/light sleep ratio",
                category: healthKit != nil ? .appleHealth : .whoop,
                numericValue: coreOrLightSleepRatio,
                displayValue: Self.percentDisplay(coreOrLightSleepRatio * 100),
                unit: "%",
                fallbackSource: "derived"
            )
        }

        if let sleepStageBalanceScore {
            addFact(
                key: "sleep_stage_balance_score",
                title: "Sleep stage balance",
                category: healthKit != nil ? .appleHealth : .whoop,
                numericValue: sleepStageBalanceScore,
                displayValue: String(format: "%.2f", sleepStageBalanceScore),
                fallbackSource: "derived"
            )
        }

        addFact(
            key: "operational_risk_rate",
            title: "Operational risk rate",
            category: .context,
            numericValue: operationalRiskRate,
            displayValue: Self.percentDisplay(operationalRiskRate * 100),
            unit: "%",
            fallbackSource: "derived"
        )

        if let healthKit {
            addFact(
                key: "wake_count",
                title: "Wake count",
                category: .appleHealth,
                numericValue: Double(healthKit.wakeCount),
                displayValue: "\(healthKit.wakeCount)",
                fallbackSource: "healthkit"
            )

            if let awakeMinutes = healthKit.awakeMinutes {
                addFact(
                    key: "awake_minutes",
                    title: "Awake minutes",
                    category: .appleHealth,
                    numericValue: awakeMinutes,
                    displayValue: Self.minutesDisplay(awakeMinutes),
                    unit: "min",
                    fallbackSource: "healthkit"
                )
            }

            if let wakeAfterSleepOnsetMinutes = healthKit.wakeAfterSleepOnsetMinutes {
                addFact(
                    key: "wake_after_sleep_onset_minutes",
                    title: "Wake after sleep onset",
                    category: .appleHealth,
                    numericValue: wakeAfterSleepOnsetMinutes,
                    displayValue: Self.minutesDisplay(wakeAfterSleepOnsetMinutes),
                    unit: "min",
                    fallbackSource: "healthkit"
                )
            }

            if let inBedMinutes = healthKit.inBedMinutes {
                addFact(
                    key: "in_bed_minutes",
                    title: "In-bed minutes",
                    category: .appleHealth,
                    numericValue: inBedMinutes,
                    displayValue: Self.minutesDisplay(inBedMinutes),
                    unit: "min",
                    fallbackSource: "healthkit"
                )
            }

            if let coreSleepMinutes = healthKit.coreSleepMinutes {
                addFact(
                    key: "core_sleep_minutes",
                    title: "Core sleep",
                    category: .appleHealth,
                    numericValue: coreSleepMinutes,
                    displayValue: Self.minutesDisplay(coreSleepMinutes),
                    unit: "min",
                    fallbackSource: "healthkit"
                )
            }

            if let deepSleepMinutes = healthKit.deepSleepMinutes {
                addFact(
                    key: "deep_sleep_minutes",
                    title: "Deep sleep",
                    category: .appleHealth,
                    numericValue: deepSleepMinutes,
                    displayValue: Self.minutesDisplay(deepSleepMinutes),
                    unit: "min",
                    fallbackSource: "healthkit"
                )
            }

            if let remSleepMinutes = healthKit.remSleepMinutes {
                addFact(
                    key: "rem_sleep_minutes",
                    title: "REM sleep",
                    category: .appleHealth,
                    numericValue: remSleepMinutes,
                    displayValue: Self.minutesDisplay(remSleepMinutes),
                    unit: "min",
                    fallbackSource: "healthkit"
                )
            }
        }

        if let whoop {
            if let recoveryScore = whoop.recoveryScore {
                addFact(
                    key: "whoop_recovery",
                    title: "WHOOP recovery",
                    category: .whoop,
                    numericValue: recoveryScore,
                    displayValue: Self.percentDisplay(recoveryScore),
                    unit: "%",
                    fallbackSource: "whoop"
                )
            }

            if let sleepPerformance = whoop.sleepPerformance {
                addFact(
                    key: "sleep_performance",
                    title: "Sleep performance",
                    category: .whoop,
                    numericValue: sleepPerformance,
                    displayValue: Self.percentDisplay(sleepPerformance),
                    unit: "%",
                    fallbackSource: "whoop"
                )
            }

            if let sleepConsistency = whoop.sleepConsistency {
                addFact(
                    key: "sleep_consistency",
                    title: "Sleep consistency",
                    category: .whoop,
                    numericValue: sleepConsistency,
                    displayValue: Self.percentDisplay(sleepConsistency),
                    unit: "%",
                    fallbackSource: "whoop"
                )
            }

            addFact(
                key: "wake_disruption_count",
                title: "Disturbance count",
                category: .whoop,
                numericValue: Double(whoop.disturbanceCount),
                displayValue: "\(whoop.disturbanceCount)",
                fallbackSource: "whoop"
            )

            addFact(
                key: "light_sleep_minutes",
                title: "Light sleep",
                category: .whoop,
                numericValue: Double(whoop.lightMinutes),
                displayValue: Self.minutesDisplay(Double(whoop.lightMinutes)),
                unit: "min",
                fallbackSource: "whoop"
            )

            if let spo2Percentage = whoop.spo2Percentage {
                addFact(
                    key: "spo2_percentage",
                    title: "SpO2",
                    category: .whoop,
                    numericValue: spo2Percentage,
                    displayValue: Self.percentDisplay(spo2Percentage),
                    unit: "%",
                    fallbackSource: "whoop"
                )
            }

            if let skinTempCelsius = whoop.skinTempCelsius {
                addFact(
                    key: "skin_temp_celsius",
                    title: "Skin temperature",
                    category: .whoop,
                    numericValue: skinTempCelsius,
                    displayValue: Self.decimalDisplay(skinTempCelsius, unit: "°C"),
                    unit: "°C",
                    fallbackSource: "whoop"
                )
            }
        }

        return facts.sorted {
            if $0.category == $1.category {
                return $0.title < $1.title
            }
            return $0.category.rawValue < $1.category.rawValue
        }
    }

    var nextMorningWeekdayLabel: String? {
        guard let context, (1...7).contains(context.nextMorningWeekdayIndex) else { return nil }
        return Self.weekdaySymbols[context.nextMorningWeekdayIndex - 1]
    }

    var wakeSignalLabel: String {
        switch explicitWakeType ?? context?.wakeSignal {
        case "natural":
            return "Natural"
        case "alarm":
            return "Alarm"
        case "alarm_then_snooze":
            return "Alarm + Snooze"
        case "external_interrupt":
            return "External"
        case "mixed":
            return "Mixed"
        case "alarm_assisted":
            return "Alarm-assisted"
        case "likely_natural":
            return "Likely natural"
        default:
            return "Unknown"
        }
    }

    var likelyNaturalWake: Bool? {
        switch explicitWakeType ?? context?.wakeSignal {
        case "natural":
            return true
        case "alarm", "alarm_then_snooze":
            return false
        case "likely_natural":
            return true
        case "alarm_assisted":
            return false
        default:
            return nil
        }
    }

    var explicitNightTypeLabel: String? {
        labelForNightType(context?.explicitNightType)
    }

    var explicitNextDayDemandLabel: String? {
        labelForNextDayDemand(context?.explicitNextDayDemand)
    }

    var explicitDose2WakeMethodLabel: String? {
        labelForWakeMethod(context?.explicitDose2WakeMethod)
    }

    var explicitBackToSleepDurationLabel: String? {
        labelForBackToSleep(context?.explicitBackToSleepDuration)
    }

    var hasLateMealContext: Bool {
        guard let value = preSleep?.lateMeal?.lowercased() else { return false }
        return value != "none" && value != "no"
    }

    var wasDose2ReconciledInMorning: Bool {
        let source = normalizedContextValue(context?.dose2Outcome?.takenSource)
        let skipSource = normalizedContextValue(context?.dose2Outcome?.skipSource)
        return source == "morning_reconciliation" || skipSource == "morning_reconciliation"
    }

    var dose2TakenSourceLabel: String? {
        labelForDoseSource(context?.dose2Outcome?.takenSource)
    }

    var dose2TakenReasonLabel: String? {
        labelForTakenReason(context?.dose2Outcome?.takenReason)
    }

    var dose2SkipSourceLabel: String? {
        labelForDoseSource(context?.dose2Outcome?.skipSource)
    }

    var dose2SkipReasonLabel: String? {
        labelForSkipReason(context?.dose2Outcome?.skipReason)
    }

    var hasDose2ReasonMismatch: Bool {
        context?.dose2Outcome?.reasonMismatch == true
    }

    var alarmAcknowledgementActionLabel: String? {
        labelForAlarmAction(context?.alarm?.acknowledgementAction)
    }

    var classification: InsightNightClassification {
        var tags: [InsightNightTag] = []
        applyScheduleTags(to: &tags)

        if context?.nextMorningIsWeekend == true {
            tags.append(.weekendNight)
        } else if context?.nextMorningWeekdayIndex != nil {
            tags.append(.weekdayDemandNight)
        }

        if likelyNaturalWake == true {
            tags.append(.naturalWakeNight)
        } else if likelyNaturalWake == false {
            tags.append(.alarmDependentNight)
        }

        let stressSignals = [preSleepStressLevel, morning?.stressLevel].compactMap { $0 }
        if (stressSignals.max() ?? 0) >= 4 {
            tags.append(.highStressNight)
        }

        if isHighPainNight {
            tags.append(.highPainNight)
        }

        if isHighSleepDisruptionNight {
            tags.append(.highSleepDisruptionNight)
        }

        if !(context?.scheduleMarkers.isEmpty ?? true) {
            tags.append(.scheduleMarkedNight)
        }

        if isHighDemandNextDay {
            tags.append(.highDemandNextDay)
        }
        if isForcedWakeNight {
            tags.append(.forcedWakeNight)
        }
        if hasWorkSafetyContext {
            tags.append(.workSafetyContextNight)
        }
        if hasClinicalContext {
            tags.append(.clinicalContextNight)
        }
        if hasSleepTherapyContext {
            tags.append(.sleepTherapyNight)
        }
        if hasFastMetabolizerReference {
            tags.append(.fastMetabolizerReferenceNight)
        }
        if (morning?.daytimeSleepiness ?? 0) >= 4 {
            tags.append(.highSleepinessDay)
        }
        if let drivingConfidence = morning?.drivingConfidence, drivingConfidence <= 2 {
            tags.append(.lowDrivingConfidenceDay)
        }

        var exclusions: [String] = []
        if isMissingOutcome {
            exclusions.append("Missing Dose 2 outcome")
        }
        if dose2Skipped {
            exclusions.append("Dose 2 skipped")
        }
        if wasDose2ReconciledInMorning {
            exclusions.append("Dose 2 reconciled in morning")
        }
        if hasDose2TimingExceptionReason {
            exclusions.append("Dose 2 timing exception reason logged")
        }
        if hasDose2ReasonMismatch {
            exclusions.append("Dose 2 reason mismatch between live and morning logs")
        }
        if normalizedContextValue(context?.dose2Outcome?.skipReason) == "slept_through" {
            exclusions.append("Slept through Dose 2 window")
        }
        if morning == nil {
            exclusions.append("Missing morning check-in")
        }
        if !qualityFlags.isEmpty && completenessScore < 0.6 {
            exclusions.append("Low data completeness")
        }

        let confidenceBucket: InsightConfidenceBucket
        switch completenessScore {
        case 0.8... where morning != nil && (healthKit != nil || whoop != nil):
            confidenceBucket = .high
        case 0.65...:
            confidenceBucket = .medium
        case 0.5...:
            confidenceBucket = .low
        default:
            confidenceBucket = .insufficient
        }

        let cohortKey = cohortKeyForClassification(tags: tags)
        let countsTowardTraining = exclusions.isEmpty && isOnTimeDose2 && confidenceBucket != .insufficient

        return InsightNightClassification(
            tags: tags.sorted { $0.rawValue < $1.rawValue },
            comparableCohortKey: cohortKey,
            exclusionReasons: Array(Set(exclusions)).sorted(),
            confidenceBucket: confidenceBucket,
            countsTowardRecommendationTraining: countsTowardTraining
        )
    }

    var comparableCohortKey: String {
        classification.comparableCohortKey
    }

    var countsTowardRecommendationTraining: Bool {
        classification.countsTowardRecommendationTraining
    }

    private static let weekdaySymbols = Calendar.current.weekdaySymbols

    private static func clampAnchoredInterval(_ interval: Int) -> Int? {
        guard interval > 0 else { return nil }
        return min(max(interval, 150), 240)
    }

    private static func rangeBalanceScore(value: Double, targetMin: Double, targetMax: Double, tolerance: Double) -> Double {
        if (targetMin...targetMax).contains(value) {
            return 1.0
        }
        if value < targetMin {
            return max(0, 1.0 - ((targetMin - value) / max(tolerance, 0.0001)))
        }
        return max(0, 1.0 - ((value - targetMax) / max(tolerance, 0.0001)))
    }

    private static func decimalDisplay(_ value: Double, unit: String? = nil) -> String {
        let suffix = unit.map { " \($0)" } ?? ""
        return String(format: "%.1f%@", value, suffix)
    }

    private static func minutesDisplay(_ value: Double) -> String {
        String(format: "%.1f min", value)
    }

    private static func percentDisplay(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private var isHighPainNight: Bool {
        if let painBurden = morning?.painBurden, hasModerateOrGreaterBurden(painBurden) {
            return true
        }
        guard let bodyPain = preSleep?.bodyPain?.lowercased() else { return false }
        return ["moderate", "severe", "high"].contains(bodyPain)
    }

    private var isHighSleepDisruptionNight: Bool {
        (wakeDisruptionCount ?? 0) >= 3
            || bathroomCount >= 2
            || hasModerateOrGreaterBurden(morning?.bathroomUrgencyBurden)
            || hasModerateOrGreaterBurden(morning?.restlessLegsBurden)
            || hasModerateOrGreaterBurden(morning?.refluxBurden)
    }

    private func symptomBurdenRank(_ value: String) -> Int {
        switch normalizedContextValue(value) {
        case "none":
            return 0
        case "mild":
            return 1
        case "moderate":
            return 2
        case "severe":
            return 3
        case "extreme":
            return 4
        default:
            return 0
        }
    }

    private func hasModerateOrGreaterBurden(_ value: String?) -> Bool {
        guard let value = normalizedContextValue(value) else { return false }
        return symptomBurdenRank(value) >= 2
    }

    private func cohortKeyForClassification(tags: [InsightNightTag]) -> String {
        let scheduleType: String
        if tags.contains(.workNight) {
            scheduleType = tags.contains(.transitionIntoWorkBlock) ? "transition_into_work" : "work"
        } else if tags.contains(.offNight) {
            if tags.contains(.postShiftRecoveryNight) {
                scheduleType = "post_shift_recovery"
            } else {
                scheduleType = tags.contains(.transitionOutOfWorkBlock) ? "transition_out_of_work" : "off"
            }
        } else {
            scheduleType = tags.contains(.weekendNight) ? "weekend" : "weekday"
        }
        let wakeType = tags.contains(.naturalWakeNight)
            ? "natural"
            : (tags.contains(.alarmDependentNight) ? "alarm" : "unknown")
        let demandBand = demandBandKey
        let wakeRequirementBand = wakeRequirementBandKey
        let therapyBand = hasSleepTherapyContext ? "sleep_therapy" : "no_sleep_therapy"
        let metabolizerBand = hasFastMetabolizerReference ? "fast_met_ref" : "baseline_metabolism"
        let commuteBand = hasLongCommuteBurden ? "long_commute" : "baseline_commute"
        let clinicalBand = hasClinicalContext ? "clinical_context" : "baseline_clinical"
        let stressBand = tags.contains(.highStressNight) ? "high_stress" : "baseline_stress"
        let painBand = tags.contains(.highPainNight) ? "high_pain" : "baseline_pain"
        let disruptionBand = tags.contains(.highSleepDisruptionNight) ? "high_disruption" : "baseline_disruption"
        return [
            scheduleType,
            wakeType,
            demandBand,
            wakeRequirementBand,
            commuteBand,
            therapyBand,
            metabolizerBand,
            clinicalBand,
            stressBand,
            painBand,
            disruptionBand
        ].joined(separator: "__")
    }

    private var explicitWakeType: String? {
        normalizedContextValue(context?.explicitWakeType)
    }

    private var demandBandKey: String {
        switch normalizedContextValue(context?.explicitNextDayDemand) {
        case "shift_12h", "shift_13h", "long_drive", "travel":
            return normalizedContextValue(context?.explicitNextDayDemand) ?? "high_demand"
        case let value?:
            return value
        default:
            return "baseline_demand"
        }
    }

    private var isHighDemandNextDay: Bool {
        switch normalizedContextValue(context?.explicitNextDayDemand) {
        case "shift_12h", "shift_13h", "long_drive", "travel":
            return true
        default:
            return false
        }
    }

    private var isForcedWakeNight: Bool {
        switch normalizedContextValue(context?.wakeRequirement) {
        case nil, "", "self_selected", "unsure":
            return false
        default:
            return true
        }
    }

    private var wakeRequirementBandKey: String {
        switch normalizedContextValue(context?.wakeRequirement) {
        case "work":
            return "wake_req_work"
        case "commute":
            return "wake_req_commute"
        case "family_care":
            return "wake_req_family"
        case "medical":
            return "wake_req_medical"
        case "travel":
            return "wake_req_travel"
        case "other":
            return "wake_req_other"
        case "self_selected", "unsure", nil, "":
            return "wake_req_self"
        default:
            return "wake_req_forced"
        }
    }

    private func applyScheduleTags(to tags: inout [InsightNightTag]) {
        if context?.firstNightOffAfterWorkBlock == true || morning?.firstNightOffAfterWorkBlock == true {
            tags.append(.transitionOutOfWorkBlock)
            tags.append(.offNight)
            tags.append(.postShiftRecoveryNight)
            return
        }

        switch normalizedContextValue(context?.explicitNightType) {
        case "work_night":
            tags.append(.workNight)
        case "off_night":
            tags.append(.offNight)
        case "recovery_night":
            tags.append(.offNight)
            tags.append(.postShiftRecoveryNight)
        case "transition_into_work_block":
            tags.append(.transitionIntoWorkBlock)
            tags.append(.workNight)
        case "transition_out_of_work_block":
            tags.append(.transitionOutOfWorkBlock)
            tags.append(.offNight)
        default:
            switch context?.scheduleDayType {
            case "worklike":
                tags.append(.workNight)
            case "offlike":
                tags.append(.offNight)
            default:
                break
            }

            if context?.scheduleDayType == "offlike", context?.nextScheduleDayType == "worklike" {
                tags.append(.transitionIntoWorkBlock)
            } else if context?.scheduleDayType == "worklike", context?.nextScheduleDayType == "offlike" {
                tags.append(.transitionOutOfWorkBlock)
            }
        }
    }

    private func normalizedContextValue(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var hasDose2TimingExceptionReason: Bool {
        switch normalizedContextValue(context?.dose2Outcome?.takenReason) {
        case nil, "unsure", "forgot_to_tap":
            return false
        default:
            return true
        }
    }

    private func labelForNightType(_ raw: String?) -> String? {
        switch normalizedContextValue(raw) {
        case "off_night":
            return "Off Night"
        case "work_night":
            return "Work Night"
        case "transition_into_work_block":
            return "Into Work Block"
        case "transition_out_of_work_block":
            return "Out Of Work Block"
        case "recovery_night":
            return "Recovery Night"
        case "unsure":
            return "Unsure"
        default:
            return nil
        }
    }

    private func labelForSymptomBurden(_ raw: String?) -> String? {
        switch normalizedContextValue(raw) {
        case "none":
            return "None"
        case "mild":
            return "Mild"
        case "moderate":
            return "Moderate"
        case "severe":
            return "Severe"
        case "extreme":
            return "Extreme"
        case "unsure":
            return "Unsure"
        default:
            return nil
        }
    }

    private func labelForNextDayDemand(_ raw: String?) -> String? {
        switch normalizedContextValue(raw) {
        case "off_day":
            return "Off Day"
        case "normal_day":
            return "Normal Day"
        case "shift_12h":
            return "12h Shift"
        case "shift_13h":
            return "13h Shift"
        case "long_drive":
            return "Long Drive"
        case "travel":
            return "Travel"
        case "recovery_day":
            return "Recovery Day"
        case "unsure":
            return "Unsure"
        default:
            return nil
        }
    }

    private func labelForWakeMethod(_ raw: String?) -> String? {
        switch normalizedContextValue(raw) {
        case "natural":
            return "Natural"
        case "alarm":
            return "Alarm"
        case "alarm_then_snooze":
            return "Alarm + Snooze"
        case "already_awake":
            return "Already Awake"
        case "external_interrupt":
            return "External"
        case "mixed":
            return "Mixed"
        case "unsure":
            return "Unsure"
        default:
            return nil
        }
    }

    private func labelForBackToSleep(_ raw: String?) -> String? {
        switch normalizedContextValue(raw) {
        case "lt_15m":
            return "<15 min"
        case "15_30m":
            return "15-30 min"
        case "30_60m":
            return "30-60 min"
        case "gt_60m":
            return ">60 min"
        case "never":
            return "Never"
        case "unsure":
            return "Unsure"
        default:
            return nil
        }
    }

    private func labelForDoseSource(_ raw: String?) -> String? {
        switch normalizedContextValue(raw) {
        case "manual":
            return "Manual"
        case "automatic":
            return "Automatic"
        case "morning_reconciliation":
            return "Morning Reconciliation"
        case let value?:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        default:
            return nil
        }
    }

    private func labelForTakenReason(_ raw: String?) -> String? {
        switch normalizedContextValue(raw) {
        case "forgot_to_tap":
            return "Forgot To Tap"
        case "fell_asleep":
            return "Fell Asleep"
        case "alarm_issue":
            return "Alarm Issue"
        case "intentionally_waited":
            return "Intentionally Waited"
        case "ate_too_late":
            return "Ate Too Late"
        case "felt_too_sedated":
            return "Felt Too Sedated"
        case "pain_or_discomfort":
            return "Pain Or Discomfort"
        case "schedule_conflict":
            return "Schedule Conflict"
        case "other":
            return "Other"
        case "unsure":
            return "Unsure"
        case let value?:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        default:
            return nil
        }
    }

    private func labelForSkipReason(_ raw: String?) -> String? {
        switch normalizedContextValue(raw) {
        case "slept_through":
            return "Slept Through"
        case "alarm_issue":
            return "Alarm Issue"
        case "ate_too_late":
            return "Ate Too Late"
        case "side_effect_concern":
            return "Side-Effect Concern"
        case "felt_too_sedated":
            return "Felt Too Sedated"
        case "pain_or_discomfort":
            return "Pain Or Discomfort"
        case "schedule_conflict":
            return "Schedule Conflict"
        case "chose_to_skip":
            return "Chose To Skip"
        case "other":
            return "Other"
        case "unsure":
            return "Unsure"
        case let value?:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        default:
            return nil
        }
    }

    private func labelForAlarmAction(_ raw: String?) -> String? {
        switch normalizedContextValue(raw) {
        case "stop":
            return "Stopped Alarm"
        case "snooze":
            return "Snoozed"
        case "opened_app":
            return "Opened App"
        case "dismissed":
            return "Dismissed"
        case "acknowledged":
            return "Acknowledged"
        case let value?:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        default:
            return nil
        }
    }

}

struct InsightFilterState: Equatable, Sendable {
    var searchText = ""
    var lateDoseOnly = false
    var skippedOnly = false
    var qualityIssuesOnly = false
    var trainableOnly = false
    var workSafetyContextOnly = false
    var clinicalContextOnly = false
    var nightType: InsightNightTypeFilter = .all
    var wakeType: InsightWakeTypeFilter = .all
    var schedule: InsightScheduleFilter = .all

    var isDefault: Bool {
        self == InsightFilterState()
    }
}
