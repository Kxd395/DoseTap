import Foundation

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

enum NightType: String, CaseIterable, Codable {
    case offNight = "off_night"
    case workNight = "work_night"
    case transitionIntoWorkBlock = "transition_into_work_block"
    case transitionOutOfWorkBlock = "transition_out_of_work_block"
    case recoveryNight = "recovery_night"
    case unsure = "unsure"

    var displayText: String {
        switch self {
        case .offNight: return "Off Night"
        case .workNight: return "Work Night"
        case .transitionIntoWorkBlock: return "Into Work Block"
        case .transitionOutOfWorkBlock: return "Out Of Work Block"
        case .recoveryNight: return "Recovery Night"
        case .unsure: return "Unsure"
        }
    }
}

enum WakeType: String, CaseIterable, Codable {
    case natural = "natural"
    case alarm = "alarm"
    case alarmThenSnooze = "alarm_then_snooze"
    case externalInterrupt = "external_interrupt"
    case mixed = "mixed"
    case unsure = "unsure"

    var displayText: String {
        switch self {
        case .natural: return "Natural"
        case .alarm: return "Alarm"
        case .alarmThenSnooze: return "Alarm + Snooze"
        case .externalInterrupt: return "External"
        case .mixed: return "Mixed"
        case .unsure: return "Unsure"
        }
    }
}

enum NextDayDemand: String, CaseIterable, Codable {
    case offDay = "off_day"
    case normalDay = "normal_day"
    case shift12h = "shift_12h"
    case shift13h = "shift_13h"
    case longDrive = "long_drive"
    case travel = "travel"
    case recoveryDay = "recovery_day"
    case unsure = "unsure"

    var displayText: String {
        switch self {
        case .offDay: return "Off Day"
        case .normalDay: return "Normal Day"
        case .shift12h: return "12h Shift"
        case .shift13h: return "13h Shift"
        case .longDrive: return "Long Drive"
        case .travel: return "Travel"
        case .recoveryDay: return "Recovery Day"
        case .unsure: return "Unsure"
        }
    }
}

enum Dose2WakeMethod: String, CaseIterable, Codable {
    case natural = "natural"
    case alarm = "alarm"
    case alarmThenSnooze = "alarm_then_snooze"
    case alreadyAwake = "already_awake"
    case externalInterrupt = "external_interrupt"
    case unsure = "unsure"

    var displayText: String {
        switch self {
        case .natural: return "Natural"
        case .alarm: return "Alarm"
        case .alarmThenSnooze: return "Alarm + Snooze"
        case .alreadyAwake: return "Already Awake"
        case .externalInterrupt: return "External"
        case .unsure: return "Unsure"
        }
    }
}

enum BackToSleepDuration: String, CaseIterable, Codable {
    case lessThanFifteen = "lt_15m"
    case fifteenToThirty = "15_30m"
    case thirtyToSixty = "30_60m"
    case moreThanHour = "gt_60m"
    case never = "never"
    case unsure = "unsure"

    var displayText: String {
        switch self {
        case .lessThanFifteen: return "<15 min"
        case .fifteenToThirty: return "15-30 min"
        case .thirtyToSixty: return "30-60 min"
        case .moreThanHour: return ">60 min"
        case .never: return "Never"
        case .unsure: return "Unsure"
        }
    }
}

enum Dose2TakenReason: String, CaseIterable, Codable {
    case forgotToTap = "forgot_to_tap"
    case fellAsleep = "fell_asleep"
    case alarmIssue = "alarm_issue"
    case intentionallyWaited = "intentionally_waited"
    case ateTooLate = "ate_too_late"
    case feltTooSedated = "felt_too_sedated"
    case painOrDiscomfort = "pain_or_discomfort"
    case scheduleConflict = "schedule_conflict"
    case other = "other"
    case unsure = "unsure"

    var displayText: String {
        switch self {
        case .forgotToTap: return "Forgot To Tap"
        case .fellAsleep: return "Fell Asleep"
        case .alarmIssue: return "Alarm Issue"
        case .intentionallyWaited: return "Intentionally Waited"
        case .ateTooLate: return "Ate Too Late"
        case .feltTooSedated: return "Felt Too Sedated"
        case .painOrDiscomfort: return "Pain Or Discomfort"
        case .scheduleConflict: return "Schedule Conflict"
        case .other: return "Other"
        case .unsure: return "Unsure"
        }
    }
}

enum Dose2SkippedReason: String, CaseIterable, Codable {
    case sleptThrough = "slept_through"
    case alarmIssue = "alarm_issue"
    case ateTooLate = "ate_too_late"
    case sideEffectConcern = "side_effect_concern"
    case feltTooSedated = "felt_too_sedated"
    case painOrDiscomfort = "pain_or_discomfort"
    case scheduleConflict = "schedule_conflict"
    case choseToSkip = "chose_to_skip"
    case other = "other"
    case unsure = "unsure"

    var displayText: String {
        switch self {
        case .sleptThrough: return "Slept Through"
        case .alarmIssue: return "Alarm Issue"
        case .ateTooLate: return "Ate Too Late"
        case .sideEffectConcern: return "Side-Effect Concern"
        case .feltTooSedated: return "Felt Too Sedated"
        case .painOrDiscomfort: return "Pain Or Discomfort"
        case .scheduleConflict: return "Schedule Conflict"
        case .choseToSkip: return "Chose To Skip"
        case .other: return "Other"
        case .unsure: return "Unsure"
        }
    }
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

enum SymptomBurden: String, CaseIterable, Codable {
    case none = "none"
    case mild = "mild"
    case moderate = "moderate"
    case severe = "severe"
    case extreme = "extreme"
    case unsure = "unsure"

    var displayText: String {
        switch self {
        case .none: return "None"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        case .extreme: return "Extreme"
        case .unsure: return "Unsure"
        }
    }
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

enum WakeRequirement: String, CaseIterable, Codable {
    case selfSelected = "self_selected"
    case work = "work"
    case commute = "commute"
    case familyCare = "family_care"
    case medical = "medical"
    case travel = "travel"
    case other = "other"
    case unsure = "unsure"

    var displayText: String {
        switch self {
        case .selfSelected: return "Self-Selected"
        case .work: return "Work"
        case .commute: return "Commute"
        case .familyCare: return "Family / Care"
        case .medical: return "Medical"
        case .travel: return "Travel"
        case .other: return "Other"
        case .unsure: return "Unsure"
        }
    }
}

enum CataplexyBurden: String, CaseIterable, Codable {
    case none = "none"
    case mild = "mild"
    case moderate = "moderate"
    case severe = "severe"
    case unsure = "unsure"

    var displayText: String {
        switch self {
        case .none: return "None"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        case .unsure: return "Unsure"
        }
    }
}

enum SleepDisorder: String, CaseIterable, Codable {
    case narcolepsy = "narcolepsy"
    case insomnia = "insomnia"
    case obstructiveSleepApnea = "obstructive_sleep_apnea"
    case restlessLegs = "restless_legs"
    case circadian = "circadian_disorder"
    case shiftWork = "shift_work_disorder"
    case parasomnia = "parasomnia"
    case idiopathicHypersomnia = "idiopathic_hypersomnia"
    case other = "other"

    var displayText: String {
        switch self {
        case .narcolepsy: return "Narcolepsy"
        case .insomnia: return "Insomnia"
        case .obstructiveSleepApnea: return "Obstructive Sleep Apnea"
        case .restlessLegs: return "Restless Legs / PLMD"
        case .circadian: return "Circadian Disorder"
        case .shiftWork: return "Shift-Work Disorder"
        case .parasomnia: return "Parasomnia"
        case .idiopathicHypersomnia: return "Idiopathic Hypersomnia"
        case .other: return "Other"
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
    var sleepDisorders: [String]?
    var pharmacogenomicFastMetabolizer: Bool?
    var pharmacogenomicClinicianReviewed: Bool?
    var pharmacogenomicNotes: String?
    var coMedicationNotes: String?
}

extension RestedLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension GrogginessLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension SleepInertiaDuration: DisplayTextProvider { var displayText: String { rawValue } }
extension DreamRecallType: DisplayTextProvider { var displayText: String { rawValue } }
extension MoodLevel: DisplayTextProvider { var displayText: String { "\(emoji) \(rawValue)" } }
extension AnxietyLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension NightType: DisplayTextProvider {}
extension WakeType: DisplayTextProvider {}
extension NextDayDemand: DisplayTextProvider {}
extension Dose2WakeMethod: DisplayTextProvider {}
extension BackToSleepDuration: DisplayTextProvider {}
extension Dose2TakenReason: DisplayTextProvider {}
extension Dose2SkippedReason: DisplayTextProvider {}
extension WakeRequirement: DisplayTextProvider {}
extension CataplexyBurden: DisplayTextProvider {}
extension SleepDisorder: DisplayTextProvider {}
extension HeadacheSeverity: DisplayTextProvider { var displayText: String { rawValue } }
extension HeadacheLocation: DisplayTextProvider { var displayText: String { rawValue } }
extension CoughType: DisplayTextProvider { var displayText: String { rawValue } }
extension SinusPressureLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension SicknessLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension SymptomBurden: DisplayTextProvider {}
extension StiffnessLevel: DisplayTextProvider { var displayText: String { rawValue } }
extension SorenessLevel: DisplayTextProvider { var displayText: String { rawValue } }
