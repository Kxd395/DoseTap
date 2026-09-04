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

struct InsightCheckInSubmission: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let sourceRecordId: String
    let sessionId: String?
    let sessionDate: String
    let checkInType: String
    let questionnaireVersion: String
    let submittedAtUTC: Date
    let localOffsetMinutes: Int
    let responsesJson: String
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
    let checkInSubmissions: [InsightCheckInSubmission]?
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
        checkInSubmissions: [InsightCheckInSubmission] = [],
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
        self.checkInSubmissions = checkInSubmissions
        self.context = context
        self.healthKit = healthKit
        self.whoop = whoop
    }
}

struct InsightPreSleepSummary: Codable, Hashable, Sendable {
    let sessionId: String?
    let completionState: String
    let loggedAtUTC: String
    let rawAnswersJson: String?
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
        rawAnswersJson: String? = nil,
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
        self.rawAnswersJson = rawAnswersJson
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
    let sleepQuality: Double
    let rawPhysicalSymptomsJson: String?
    let rawRespiratorySymptomsJson: String?
    let rawSleepTherapyJson: String?
    let rawSleepEnvironmentJson: String?
    let rawStressContextJson: String?
    let rawTimingContextJson: String?
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
        sleepQuality: Double,
        rawPhysicalSymptomsJson: String? = nil,
        rawRespiratorySymptomsJson: String? = nil,
        rawSleepTherapyJson: String? = nil,
        rawSleepEnvironmentJson: String? = nil,
        rawStressContextJson: String? = nil,
        rawTimingContextJson: String? = nil,
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
        self.rawPhysicalSymptomsJson = rawPhysicalSymptomsJson
        self.rawRespiratorySymptomsJson = rawRespiratorySymptomsJson
        self.rawSleepTherapyJson = rawSleepTherapyJson
        self.rawSleepEnvironmentJson = rawSleepEnvironmentJson
        self.rawStressContextJson = rawStressContextJson
        self.rawTimingContextJson = rawTimingContextJson
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
