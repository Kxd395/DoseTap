import Foundation

// MARK: - Morning Check-In Model
// Comprehensive morning questionnaire for specialist reports
// Supports progressive disclosure (only expand details if flagged)

@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
public struct MorningCheckIn: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sessionId: UUID  // Links to the specific night session
    public let timestamp: Date
    
    // MARK: - 1. Core Sleep Assessment (Always Visible)
    public var sleepQuality: Int           // 1-5 Stars
    public var feelRested: RestedLevel
    public var grogginess: GrogginessLevel
    public var sleepInertiaDuration: SleepInertiaDuration
    public var dreamRecall: DreamRecallType
    
    // MARK: - 2. Physical Symptoms (Conditional - only if hasPhysicalSymptoms)
    public var hasPhysicalSymptoms: Bool
    public var physicalSymptoms: PhysicalSymptoms?
    
    // MARK: - 3. Respiratory/Illness (Conditional - only if hasRespiratorySymptoms)
    public var hasRespiratorySymptoms: Bool
    public var respiratorySymptoms: RespiratorySymptoms?
    
    // MARK: - 4. Mental State (Always Visible - Quick)
    public var mentalClarity: Int          // 1-10 (Foggy to Sharp)
    public var mood: MoodLevel
    public var anxietyLevel: AnxietyLevel
    public var readinessForDay: Int        // 1-5
    
    // MARK: - 5. Narcolepsy-Specific (Toggle List)
    public var hadSleepParalysis: Bool
    public var hadHallucinations: Bool
    public var hadAutomaticBehavior: Bool
    public var fellOutOfBed: Bool
    public var hadConfusionOnWaking: Bool
    
    // MARK: - 6. Sleep Environment (Conditional - only if hasSleepEnvironmentData)
    public var hasSleepEnvironmentData: Bool
    public var sleepEnvironment: SleepEnvironment?
    
    // MARK: - 7. Notes
    public var notes: String?
    
    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        timestamp: Date = Date(),
        sleepQuality: Int = 3,
        feelRested: RestedLevel = .moderate,
        grogginess: GrogginessLevel = .mild,
        sleepInertiaDuration: SleepInertiaDuration = .fiveToFifteen,
        dreamRecall: DreamRecallType = .none,
        hasPhysicalSymptoms: Bool = false,
        physicalSymptoms: PhysicalSymptoms? = nil,
        hasRespiratorySymptoms: Bool = false,
        respiratorySymptoms: RespiratorySymptoms? = nil,
        mentalClarity: Int = 5,
        mood: MoodLevel = .neutral,
        anxietyLevel: AnxietyLevel = .none,
        readinessForDay: Int = 3,
        hadSleepParalysis: Bool = false,
        hadHallucinations: Bool = false,
        hadAutomaticBehavior: Bool = false,
        fellOutOfBed: Bool = false,
        hadConfusionOnWaking: Bool = false,
        hasSleepEnvironmentData: Bool = false,
        sleepEnvironment: SleepEnvironment? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.sleepQuality = sleepQuality
        self.feelRested = feelRested
        self.grogginess = grogginess
        self.sleepInertiaDuration = sleepInertiaDuration
        self.dreamRecall = dreamRecall
        self.hasPhysicalSymptoms = hasPhysicalSymptoms
        self.physicalSymptoms = physicalSymptoms
        self.hasRespiratorySymptoms = hasRespiratorySymptoms
        self.respiratorySymptoms = respiratorySymptoms
        self.mentalClarity = mentalClarity
        self.mood = mood
        self.anxietyLevel = anxietyLevel
        self.readinessForDay = readinessForDay
        self.hadSleepParalysis = hadSleepParalysis
        self.hadHallucinations = hadHallucinations
        self.hadAutomaticBehavior = hadAutomaticBehavior
        self.fellOutOfBed = fellOutOfBed
        self.hadConfusionOnWaking = hadConfusionOnWaking
        self.hasSleepEnvironmentData = hasSleepEnvironmentData
        self.sleepEnvironment = sleepEnvironment
        self.notes = notes
    }
}

// MARK: - Core Enums

public enum RestedLevel: String, Codable, CaseIterable, Sendable {
    case notAtAll = "Not at all"
    case slightly = "Slightly"
    case moderate = "Moderately"
    case well = "Well"
    case veryWell = "Very well"
    
    public var numericValue: Int {
        switch self {
        case .notAtAll: return 1
        case .slightly: return 2
        case .moderate: return 3
        case .well: return 4
        case .veryWell: return 5
        }
    }
}

public enum GrogginessLevel: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
    case cantFunction = "Can't function"
    
    public var icon: String {
        switch self {
        case .none: return "sun.max.fill"
        case .mild: return "sun.haze.fill"
        case .moderate: return "cloud.sun.fill"
        case .severe: return "cloud.fill"
        case .cantFunction: return "moon.zzz.fill"
        }
    }
}

public enum SleepInertiaDuration: String, Codable, CaseIterable, Sendable {
    case lessThanFive = "<5 minutes"
    case fiveToFifteen = "5-15 minutes"
    case fifteenToThirty = "15-30 minutes"
    case thirtyToSixty = "30-60 minutes"
    case moreThanHour = ">1 hour"
    
    public var midpointMinutes: Int {
        switch self {
        case .lessThanFive: return 3
        case .fiveToFifteen: return 10
        case .fifteenToThirty: return 22
        case .thirtyToSixty: return 45
        case .moreThanHour: return 90
        }
    }
}

public enum DreamRecallType: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case vague = "Vague"
    case normal = "Normal"
    case vivid = "Vivid"
    case nightmares = "Nightmares"
    case disturbing = "Disturbing"
}

public enum MoodLevel: String, Codable, CaseIterable, Sendable {
    case veryLow = "Very Low"
    case low = "Low"
    case neutral = "Neutral"
    case good = "Good"
    case great = "Great"
    
    public var emoji: String {
        switch self {
        case .veryLow: return "😢"
        case .low: return "😔"
        case .neutral: return "😐"
        case .good: return "🙂"
        case .great: return "😊"
        }
    }
}

public enum AnxietyLevel: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case high = "High"
    case severe = "Severe"
}

// MARK: - Physical Symptoms Sub-Model

public struct PhysicalSymptoms: Codable, Sendable {
    public var painLocations: Set<BodyPart>
    public var painSeverity: Int  // 1-10
    public var painType: PainType
    public var headache: HeadacheDetails?
    public var muscleStiffness: StiffnessLevel
    public var muscleSoreness: SorenessLevel
    
    public init(
        painLocations: Set<BodyPart> = [],
        painSeverity: Int = 0,
        painType: PainType = .aching,
        headache: HeadacheDetails? = nil,
        muscleStiffness: StiffnessLevel = .none,
        muscleSoreness: SorenessLevel = .none
    ) {
        self.painLocations = painLocations
        self.painSeverity = painSeverity
        self.painType = painType
        self.headache = headache
        self.muscleStiffness = muscleStiffness
        self.muscleSoreness = muscleSoreness
    }
}

public enum BodyPart: String, Codable, CaseIterable, Sendable {
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
    
    public var icon: String {
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

public enum PainType: String, Codable, CaseIterable, Sendable {
    case aching = "Aching"
    case sharp = "Sharp"
    case stiff = "Stiff"
    case throbbing = "Throbbing"
    case burning = "Burning"
    case tingling = "Tingling"
    case cramping = "Cramping"
}

public enum StiffnessLevel: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
}

public enum SorenessLevel: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
}

// MARK: - Headache Sub-Model

public struct HeadacheDetails: Codable, Sendable {
    public var severity: HeadacheSeverity
    public var location: HeadacheLocation
    public var isMigraine: Bool
    
    public init(
        severity: HeadacheSeverity = .mild,
        location: HeadacheLocation = .forehead,
        isMigraine: Bool = false
    ) {
        self.severity = severity
        self.location = location
        self.isMigraine = isMigraine
    }
}

public enum HeadacheSeverity: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
    case migraine = "Migraine"
}

public enum HeadacheLocation: String, Codable, CaseIterable, Sendable {
    case forehead = "Forehead"
    case temples = "Temples"
    case backOfHead = "Back of Head"
    case behindEyes = "Behind Eyes"
    case allOver = "All Over"
    case oneSide = "One Side"
}

// MARK: - Respiratory Symptoms Sub-Model

public struct RespiratorySymptoms: Codable, Sendable {
    public var congestion: CongestionType
    public var throatCondition: ThroatCondition
    public var coughType: CoughType
    public var sinusPressure: SinusPressureLevel
    public var feelingFeverish: Bool
    public var sicknessLevel: SicknessLevel
    
    public init(
        congestion: CongestionType = .none,
        throatCondition: ThroatCondition = .normal,
        coughType: CoughType = .none,
        sinusPressure: SinusPressureLevel = .none,
        feelingFeverish: Bool = false,
        sicknessLevel: SicknessLevel = .no
    ) {
        self.congestion = congestion
        self.throatCondition = throatCondition
        self.coughType = coughType
        self.sinusPressure = sinusPressure
        self.feelingFeverish = feelingFeverish
        self.sicknessLevel = sicknessLevel
    }
}

public enum CongestionType: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case stuffyNose = "Stuffy Nose"
    case runnyNose = "Runny Nose"
    case both = "Stuffy & Runny"
}

public enum ThroatCondition: String, Codable, CaseIterable, Sendable {
    case normal = "Normal"
    case dry = "Dry"
    case sore = "Sore"
    case scratchy = "Scratchy"
}

public enum CoughType: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case dry = "Dry Cough"
    case productive = "Productive"
}

public enum SinusPressureLevel: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
}

public enum SicknessLevel: String, Codable, CaseIterable, Sendable {
    case no = "No"
    case comingDown = "Coming down with something"
    case activelySick = "Actively sick"
    case recovering = "Recovering"
}

// MARK: - Sleep Environment Sub-Model

/// Captures sleep setup details and aids used for correlation analysis
public struct SleepEnvironment: Codable, Sendable {
    // Sleep aids used (multi-select)
    public var sleepAidsUsed: Set<SleepAid>
    
    // Room conditions
    public var roomDarkness: DarknessLevel
    public var noiseLevel: NoiseLevel
    
    // Screen/device usage
    public var screenInBedMinutesBucket: ScreenTimeBucket
    
    // Temperature comfort
    public var temperatureComfort: TemperatureComfort
    
    // Partner/pet disruptions
    public var hadPartnerDisruption: Bool
    public var hadPetDisruption: Bool
    
    public init(
        sleepAidsUsed: Set<SleepAid> = [],
        roomDarkness: DarknessLevel = .dark,
        noiseLevel: NoiseLevel = .quiet,
        screenInBedMinutesBucket: ScreenTimeBucket = .none,
        temperatureComfort: TemperatureComfort = .comfortable,
        hadPartnerDisruption: Bool = false,
        hadPetDisruption: Bool = false
    ) {
        self.sleepAidsUsed = sleepAidsUsed
        self.roomDarkness = roomDarkness
        self.noiseLevel = noiseLevel
        self.screenInBedMinutesBucket = screenInBedMinutesBucket
        self.temperatureComfort = temperatureComfort
        self.hadPartnerDisruption = hadPartnerDisruption
        self.hadPetDisruption = hadPetDisruption
    }
}

/// Sleep aids that may be used (multi-select chip UI)
public enum SleepAid: String, Codable, CaseIterable, Sendable {
    case eyeMask = "Eye Mask"
    case earplugs = "Earplugs"
    case whiteNoise = "White Noise"
    case fan = "Fan"
    case weightedBlanket = "Weighted Blanket"
    case sleepMeditation = "Sleep Meditation"
    case breathingExercises = "Breathing Exercises"
    case sleepPodcast = "Sleep Podcast"
    case melatonin = "Melatonin"  // OTC supplement
    case magnesium = "Magnesium"  // OTC supplement
    case cbdOrThc = "CBD/THC"
    case tvOn = "TV On"
    case phoneInBed = "Phone in Bed"
    
    public var icon: String {
        switch self {
        case .eyeMask: return "eye.slash.fill"
        case .earplugs: return "ear.badge.checkmark"
        case .whiteNoise: return "waveform"
        case .fan: return "fan.fill"
        case .weightedBlanket: return "bed.double.fill"
        case .sleepMeditation: return "brain.head.profile"
        case .breathingExercises: return "wind"
        case .sleepPodcast: return "headphones"
        case .melatonin: return "pills.fill"
        case .magnesium: return "pill.fill"
        case .cbdOrThc: return "leaf.fill"
        case .tvOn: return "tv.fill"
        case .phoneInBed: return "iphone"
        }
    }
    
    public var category: SleepAidCategory {
        switch self {
        case .eyeMask, .earplugs, .whiteNoise, .fan, .weightedBlanket:
            return .physical
        case .sleepMeditation, .breathingExercises, .sleepPodcast:
            return .relaxation
        case .melatonin, .magnesium, .cbdOrThc:
            return .supplement
        case .tvOn, .phoneInBed:
            return .screen
        }
    }
}

public enum SleepAidCategory: String, Codable, CaseIterable, Sendable {
    case physical = "Physical"
    case relaxation = "Relaxation"
    case supplement = "Supplements"
    case screen = "Screens"
    
    public var aids: [SleepAid] {
        SleepAid.allCases.filter { $0.category == self }
    }
}

public enum DarknessLevel: String, Codable, CaseIterable, Sendable {
    case pitch = "Pitch Black"
    case dark = "Dark"
    case dim = "Dim Light"
    case bright = "Bright"
    
    public var icon: String {
        switch self {
        case .pitch: return "moon.fill"
        case .dark: return "moon.stars.fill"
        case .dim: return "sun.haze.fill"
        case .bright: return "sun.max.fill"
        }
    }
}

public enum NoiseLevel: String, Codable, CaseIterable, Sendable {
    case silent = "Silent"
    case quiet = "Quiet"
    case whiteNoise = "White Noise"
    case someNoise = "Some Noise"
    case noisy = "Noisy"
    
    public var icon: String {
        switch self {
        case .silent: return "speaker.slash.fill"
        case .quiet: return "speaker.fill"
        case .whiteNoise: return "waveform"
        case .someNoise: return "speaker.wave.2.fill"
        case .noisy: return "speaker.wave.3.fill"
        }
    }
}

public enum ScreenTimeBucket: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case under15 = "<15 min"
    case fifteenToThirty = "15-30 min"
    case thirtyToSixty = "30-60 min"
    case overHour = ">1 hour"
    
    public var midpointMinutes: Int {
        switch self {
        case .none: return 0
        case .under15: return 7
        case .fifteenToThirty: return 22
        case .thirtyToSixty: return 45
        case .overHour: return 90
        }
    }
}

public enum TemperatureComfort: String, Codable, CaseIterable, Sendable {
    case tooCold = "Too Cold"
    case comfortable = "Comfortable"
    case tooWarm = "Too Warm"
    
    public var icon: String {
        switch self {
        case .tooCold: return "snowflake"
        case .comfortable: return "thermometer.medium"
        case .tooWarm: return "flame.fill"
        }
    }
}

// MARK: - Helper Extensions

@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
extension MorningCheckIn {
    /// Quick check if any narcolepsy symptoms were reported
    public var hasNarcolepsySymptoms: Bool {
        hadSleepParalysis || hadHallucinations || hadAutomaticBehavior || fellOutOfBed || hadConfusionOnWaking
    }
    
    /// Overall wellness score (for trend tracking)
    public var wellnessScore: Double {
        var score = 0.0
        
        // Sleep quality contributes 30%
        score += Double(sleepQuality) / 5.0 * 30
        
        // Rested feeling contributes 25%
        score += Double(feelRested.numericValue) / 5.0 * 25
        
        // Mental clarity contributes 20%
        score += Double(mentalClarity) / 10.0 * 20
        
        // Mood contributes 15%
        let moodScore = Double(MoodLevel.allCases.firstIndex(of: mood) ?? 2) + 1
        score += moodScore / 5.0 * 15
        
        // Readiness contributes 10%
        score += Double(readinessForDay) / 5.0 * 10
        
        // Deductions for symptoms
        if hasPhysicalSymptoms { score -= 10 }
        if hasRespiratorySymptoms { score -= 5 }
        if hasNarcolepsySymptoms { score -= 5 }
        
        return max(0, min(100, score))
    }
}
