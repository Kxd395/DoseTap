import DoseCore
import Foundation

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
    let checkInSubmissions: [InsightCheckInSubmission]
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
        checkInSubmissions: [InsightCheckInSubmission] = [],
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
        self.checkInSubmissions = checkInSubmissions
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

    var morningSleepQuality: Double? {
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
        guard let dose1Time, let dose2Time else { return false }
        return MedicationTiming.classify(dose1: dose1Time, dose2: dose2Time) == .late
    }

    var isOnTimeDose2: Bool {
        guard let dose1Time, let dose2Time else { return false }
        return MedicationTiming.classify(dose1: dose1Time, dose2: dose2Time) == .inWindow
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
                numericValue: morningSleepQuality,
                displayValue: Self.fivePointDisplay(morningSleepQuality),
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

    private static func fivePointDisplay(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))/5"
        }
        return String(format: "%.2f/5", value)
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
