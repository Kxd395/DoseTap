import Foundation
import DoseCore

/// Pre-sleep log answers model with nested enums for type-safe options
public struct PreSleepLogAnswers: Codable {
    
    // MARK: - Nested Enums for Question Options
    
    public enum IntendedSleepTime: String, Codable, CaseIterable {
        case now = "now"
        case fifteenMin = "15min"
        case thirtyMin = "30min"
        case hour = "1hr"
        case later = "later"
        
        public var displayText: String {
            switch self {
            case .now: return "Now"
            case .fifteenMin: return "~15 min"
            case .thirtyMin: return "~30 min"
            case .hour: return "~1 hour"
            case .later: return "Later"
            }
        }
    }
    
    public typealias StressDriver = CommonStressDriver
    public typealias StressProgression = CommonStressProgression
    
    public enum PainLevel: String, Codable, CaseIterable {
        case none = "none"
        case mild = "mild"
        case moderate = "moderate"
        case severe = "severe"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .mild: return "Mild"
            case .moderate: return "Moderate"
            case .severe: return "Severe"
            }
        }
    }
    
    public enum PainLocation: String, Codable, CaseIterable {
        case head = "head"
        case neck = "neck"
        case back = "back"
        case shoulders = "shoulders"
        case legs = "legs"
        case joints = "joints"
        case stomach = "stomach"
        case other = "other"
        
        public var displayText: String {
            switch self {
            case .head: return "Head"
            case .neck: return "Neck"
            case .back: return "Back"
            case .shoulders: return "Shoulders"
            case .legs: return "Legs"
            case .joints: return "Joints"
            case .stomach: return "Stomach"
            case .other: return "Other"
            }
        }
    }
    
    public enum PainType: String, Codable, CaseIterable {
        case aching = "aching"
        case sharp = "sharp"
        case burning = "burning"
        case throbbing = "throbbing"
        case cramping = "cramping"
        
        public var displayText: String {
            switch self {
            case .aching: return "Aching"
            case .sharp: return "Sharp"
            case .burning: return "Burning"
            case .throbbing: return "Throbbing"
            case .cramping: return "Cramping"
            }
        }
    }

    public enum PainArea: String, Codable, CaseIterable {
        case headFace = "head_face"
        case neck = "neck"
        case upperBack = "upper_back"
        case midBack = "mid_back"
        case lowerBack = "lower_back"
        case shoulder = "shoulder"
        case armElbow = "arm_elbow"
        case wristHand = "wrist_hand"
        case chestRibs = "chest_ribs"
        case abdomen = "abdomen"
        case hipGlute = "hip_glute"
        case knee = "knee"
        case ankleFoot = "ankle_foot"
        case other = "other"

        public init(legacyLocation: PainLocation) {
            switch legacyLocation {
            case .head: self = .headFace
            case .neck: self = .neck
            case .back: self = .lowerBack
            case .shoulders: self = .shoulder
            case .legs: self = .ankleFoot
            case .joints: self = .knee
            case .stomach: self = .abdomen
            case .other: self = .other
            }
        }

        public var displayText: String {
            switch self {
            case .headFace: return "Head / Face"
            case .neck: return "Neck"
            case .upperBack: return "Upper Back"
            case .midBack: return "Mid Back"
            case .lowerBack: return "Lower Back"
            case .shoulder: return "Shoulder"
            case .armElbow: return "Arm / Elbow"
            case .wristHand: return "Wrist / Hand"
            case .chestRibs: return "Chest / Ribs"
            case .abdomen: return "Abdomen"
            case .hipGlute: return "Hip / Glute"
            case .knee: return "Knee"
            case .ankleFoot: return "Ankle / Foot"
            case .other: return "Other"
            }
        }
    }

    public enum PainSide: String, Codable, CaseIterable {
        case left = "left"
        case right = "right"
        case center = "center"
        case both = "both"
        case na = "na"

        public var displayText: String {
            switch self {
            case .left: return "Left"
            case .right: return "Right"
            case .center: return "Center"
            case .both: return "Both"
            case .na: return "N/A"
            }
        }
    }

    public enum PainSensation: String, Codable, CaseIterable {
        case aching = "aching"
        case sharp = "sharp"
        case shooting = "shooting"
        case stabbing = "stabbing"
        case burning = "burning"
        case throbbing = "throbbing"
        case cramping = "cramping"
        case tightness = "tightness"
        case radiating = "radiating"
        case pinsNeedles = "pins_needles"
        case numbness = "numbness"
        case other = "other"

        public var displayText: String {
            switch self {
            case .aching: return "Aching"
            case .sharp: return "Sharp"
            case .shooting: return "Shooting"
            case .stabbing: return "Stabbing"
            case .burning: return "Burning"
            case .throbbing: return "Throbbing"
            case .cramping: return "Cramping"
            case .tightness: return "Tightness"
            case .radiating: return "Radiating"
            case .pinsNeedles: return "Pins / Needles"
            case .numbness: return "Numbness"
            case .other: return "Other"
            }
        }
    }

    public enum PainPattern: String, Codable, CaseIterable {
        case constant = "constant"
        case intermittent = "intermittent"
        case unknown = "unknown"

        public var displayText: String {
            switch self {
            case .constant: return "Constant"
            case .intermittent: return "Comes and goes"
            case .unknown: return "Unknown"
            }
        }
    }

    public struct PainEntry: Codable, Hashable, Identifiable {
        public var area: PainArea
        public var side: PainSide
        public var intensity: Int
        public var sensations: [PainSensation]
        public var pattern: PainPattern?
        public var notes: String?

        public var entryKey: String {
            "\(area.rawValue)|\(side.rawValue)"
        }

        public var id: String { entryKey }

        public init(
            area: PainArea,
            side: PainSide,
            intensity: Int,
            sensations: [PainSensation],
            pattern: PainPattern? = nil,
            notes: String? = nil
        ) {
            self.area = area
            self.side = side
            self.intensity = max(0, min(10, intensity))
            self.sensations = Array(Set(sensations)).sorted { $0.rawValue < $1.rawValue }
            self.pattern = pattern
            self.notes = notes
        }
    }
    
    public enum Stimulants: String, Codable, CaseIterable {
        case none = "none"
        case coffee = "coffee"
        case tea = "tea"
        case soda = "soda"
        case energyDrink = "energy_drink"
        case multiple = "multiple"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .coffee: return "Coffee"
            case .tea: return "Tea"
            case .soda: return "Soda"
            case .energyDrink: return "Energy Drink"
            case .multiple: return "Multiple"
            }
        }
    }

    public static var caffeineSourceOptions: [Stimulants] {
        [.coffee, .tea, .soda, .energyDrink]
    }
    
    public enum AlcoholLevel: String, Codable, CaseIterable {
        case none = "none"
        case one = "1"
        case twoThree = "2-3"
        case fourPlus = "4+"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .one: return "1 drink"
            case .twoThree: return "2-3 drinks"
            case .fourPlus: return "4+ drinks"
            }
        }
    }
    
    public enum ExerciseLevel: String, Codable, CaseIterable {
        case none = "none"
        case light = "light"
        case moderate = "moderate"
        case intense = "intense"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .light: return "Light"
            case .moderate: return "Moderate"
            case .intense: return "Intense"
            }
        }
    }

    public enum ExerciseType: String, Codable, CaseIterable {
        case walking = "walking"
        case cardio = "cardio"
        case strength = "strength"
        case yogaMobility = "yoga_mobility"
        case sports = "sports"
        case labor = "labor"
        case other = "other"

        public var displayText: String {
            switch self {
            case .walking: return "Walking"
            case .cardio: return "Cardio"
            case .strength: return "Strength"
            case .yogaMobility: return "Yoga / Mobility"
            case .sports: return "Sports"
            case .labor: return "Physical Labor"
            case .other: return "Other"
            }
        }
    }
    
    public enum NapDuration: String, Codable, CaseIterable {
        case none = "none"
        case short = "short"
        case medium = "medium"
        case long = "long"
        
        public var displayText: String {
            switch self {
            case .none: return "No nap"
            case .short: return "<30 min"
            case .medium: return "30-60 min"
            case .long: return ">1 hour"
            }
        }
    }
    
    public enum LaterReason: String, Codable, CaseIterable {
        case notTired = "not_tired"
        case workToDo = "work"
        case socialPlans = "social"
        case entertainment = "entertainment"
        case other = "other"
        
        public var displayText: String {
            switch self {
            case .notTired: return "Not tired"
            case .workToDo: return "Work to do"
            case .socialPlans: return "Social plans"
            case .entertainment: return "Entertainment"
            case .other: return "Other"
            }
        }
    }
    
    public enum LateMeal: String, Codable, CaseIterable {
        case none = "none"
        case snack = "snack"
        case lightMeal = "light"
        case heavyMeal = "heavy"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .snack: return "Snack"
            case .lightMeal: return "Light meal"
            case .heavyMeal: return "Heavy meal"
            }
        }
    }
    
    public enum ScreensInBed: String, Codable, CaseIterable {
        case none = "none"
        case briefly = "briefly"
        case thirtyMin = "30min"
        case hourPlus = "1hr+"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .briefly: return "Briefly"
            case .thirtyMin: return "~30 min"
            case .hourPlus: return "1+ hour"
            }
        }
    }
    
    public enum RoomTemp: String, Codable, CaseIterable {
        case cold = "cold"
        case cool = "cool"
        case comfortable = "comfortable"
        case warm = "warm"
        case hot = "hot"
        
        public var displayText: String {
            switch self {
            case .cold: return "Cold"
            case .cool: return "Cool"
            case .comfortable: return "Comfortable"
            case .warm: return "Warm"
            case .hot: return "Hot"
            }
        }
    }
    
    public enum NoiseLevel: String, Codable, CaseIterable {
        case silent = "silent"
        case quiet = "quiet"
        case moderate = "moderate"
        case noisy = "noisy"
        
        public var displayText: String {
            switch self {
            case .silent: return "Silent"
            case .quiet: return "Quiet"
            case .moderate: return "Moderate"
            case .noisy: return "Noisy"
            }
        }
    }
    
    public enum SleepAid: String, Codable, CaseIterable {
        case none = "none"
        case eyeMask = "eye_mask"
        case earplugs = "earplugs"
        case whiteNoise = "white_noise"
        case fan = "fan"
        case blackoutCurtains = "blackout_curtains"
        case multiple = "multiple"
        
        public var displayText: String {
            switch self {
            case .none: return "None"
            case .eyeMask: return "Eye Mask"
            case .earplugs: return "Earplugs"
            case .whiteNoise: return "White Noise"
            case .fan: return "Fan"
            case .blackoutCurtains: return "Blackout Curtains"
            case .multiple: return "Multiple"
            }
        }
        
        public var icon: String {
            switch self {
            case .none: return "moon.zzz"
            case .eyeMask: return "eye"
            case .earplugs: return "ear"
            case .whiteNoise: return "waveform"
            case .fan: return "wind"
            case .blackoutCurtains: return "curtains.closed"
            case .multiple: return "square.grid.2x2"
            }
        }
    }

    public static var sleepAidOptions: [SleepAid] {
        [.eyeMask, .earplugs, .whiteNoise, .fan, .blackoutCurtains]
    }
    
    // MARK: - Properties
    
    // Card 1: Timing + Stress
    public var intendedSleepTime: IntendedSleepTime?
    public var stressLevel: Int?
    public var stressDriver: StressDriver?
    public var stressDrivers: [StressDriver]?
    public var stressProgression: StressProgression?
    public var stressNotes: String?
    public var laterReason: LaterReason?
    
    // Card 2: Body + Substances
    public var bodyPain: PainLevel?
    public var painEntries: [PainEntry]?
    public var painLocations: [PainLocation]?
    public var painType: PainType?
    public var stimulants: Stimulants?
    public var caffeineSources: [Stimulants]?
    public var caffeineLastIntakeAt: Date?
    public var caffeineLastAmountMg: Int?
    public var caffeineDailyTotalMg: Int?
    public var plannedTotalNightlyMg: Int?
    public var plannedDoseSplitRatio: [Double]?
    public var plannedDose1Mg: Int?
    public var plannedDose2Mg: Int?
    public var alcohol: AlcoholLevel?
    public var alcoholLastDrinkAt: Date?
    public var alcoholLastAmountDrinks: Double?
    public var alcoholDailyTotalDrinks: Double?
    
    // Card 3: Activity + Naps
    public var exercise: ExerciseLevel?
    public var exerciseType: ExerciseType?
    public var exerciseLastAt: Date?
    public var exerciseDurationMinutes: Int?
    public var napToday: NapDuration?
    public var napCount: Int?
    public var napTotalMinutes: Int?
    public var napLastEndAt: Date?
    
    // Optional details
    public var lateMeal: LateMeal?
    public var lateMealEndedAt: Date?
    public var screensInBed: ScreensInBed?
    public var screensLastUsedAt: Date?
    public var roomTemp: RoomTemp?
    public var noiseLevel: NoiseLevel?
    public var sleepAids: SleepAid?
    public var sleepAidSelections: [SleepAid]?
    
    // Legacy fields (for backwards compatibility)
    public var notes: String?
    
    public init(
        intendedSleepTime: IntendedSleepTime? = nil,
        stressLevel: Int? = nil,
        stressDriver: StressDriver? = nil,
        stressDrivers: [StressDriver]? = nil,
        stressProgression: StressProgression? = nil,
        stressNotes: String? = nil,
        laterReason: LaterReason? = nil,
        bodyPain: PainLevel? = nil,
        painEntries: [PainEntry]? = nil,
        painLocations: [PainLocation]? = nil,
        painType: PainType? = nil,
        stimulants: Stimulants? = nil,
        caffeineSources: [Stimulants]? = nil,
        caffeineLastIntakeAt: Date? = nil,
        caffeineLastAmountMg: Int? = nil,
        caffeineDailyTotalMg: Int? = nil,
        plannedTotalNightlyMg: Int? = nil,
        plannedDoseSplitRatio: [Double]? = nil,
        plannedDose1Mg: Int? = nil,
        plannedDose2Mg: Int? = nil,
        alcohol: AlcoholLevel? = nil,
        alcoholLastDrinkAt: Date? = nil,
        alcoholLastAmountDrinks: Double? = nil,
        alcoholDailyTotalDrinks: Double? = nil,
        exercise: ExerciseLevel? = nil,
        exerciseType: ExerciseType? = nil,
        exerciseLastAt: Date? = nil,
        exerciseDurationMinutes: Int? = nil,
        napToday: NapDuration? = nil,
        napCount: Int? = nil,
        napTotalMinutes: Int? = nil,
        napLastEndAt: Date? = nil,
        lateMeal: LateMeal? = nil,
        lateMealEndedAt: Date? = nil,
        screensInBed: ScreensInBed? = nil,
        screensLastUsedAt: Date? = nil,
        roomTemp: RoomTemp? = nil,
        noiseLevel: NoiseLevel? = nil,
        sleepAids: SleepAid? = nil,
        sleepAidSelections: [SleepAid]? = nil,
        notes: String? = nil
    ) {
        self.intendedSleepTime = intendedSleepTime
        self.stressLevel = stressLevel
        self.stressDriver = stressDriver
        self.stressDrivers = stressDrivers
        self.stressProgression = stressProgression
        self.stressNotes = stressNotes
        self.laterReason = laterReason
        self.bodyPain = bodyPain
        self.painEntries = painEntries
        self.painLocations = painLocations
        self.painType = painType
        self.stimulants = stimulants
        self.caffeineSources = caffeineSources
        self.caffeineLastIntakeAt = caffeineLastIntakeAt
        self.caffeineLastAmountMg = caffeineLastAmountMg
        self.caffeineDailyTotalMg = caffeineDailyTotalMg
        self.plannedTotalNightlyMg = plannedTotalNightlyMg
        self.plannedDoseSplitRatio = plannedDoseSplitRatio
        self.plannedDose1Mg = plannedDose1Mg
        self.plannedDose2Mg = plannedDose2Mg
        self.alcohol = alcohol
        self.alcoholLastDrinkAt = alcoholLastDrinkAt
        self.alcoholLastAmountDrinks = alcoholLastAmountDrinks
        self.alcoholDailyTotalDrinks = alcoholDailyTotalDrinks
        self.exercise = exercise
        self.exerciseType = exerciseType
        self.exerciseLastAt = exerciseLastAt
        self.exerciseDurationMinutes = exerciseDurationMinutes
        self.napToday = napToday
        self.napCount = napCount
        self.napTotalMinutes = napTotalMinutes
        self.napLastEndAt = napLastEndAt
        self.lateMeal = lateMeal
        self.lateMealEndedAt = lateMealEndedAt
        self.screensInBed = screensInBed
        self.screensLastUsedAt = screensLastUsedAt
        self.roomTemp = roomTemp
        self.noiseLevel = noiseLevel
        self.sleepAids = sleepAids
        self.sleepAidSelections = sleepAidSelections
        self.notes = notes
    }

    public static func sanitizedStressDrivers(_ drivers: [StressDriver]?) -> [StressDriver] {
        let unique = Set(drivers ?? [])
        return StressDriver.allCases.filter { unique.contains($0) }
    }

    public var resolvedStressDrivers: [StressDriver] {
        let explicit = Self.sanitizedStressDrivers(stressDrivers)
        if !explicit.isEmpty {
            return explicit
        }
        if let stressDriver {
            return [stressDriver]
        }
        return []
    }

    public var primaryStressDriver: StressDriver? {
        resolvedStressDrivers.first
    }

    public var resolvedCaffeineSources: [Stimulants] {
        let explicit = Self.sanitizedCaffeineSources(caffeineSources)
        if !explicit.isEmpty {
            return explicit
        }
        if let stimulants, Self.caffeineSourceOptions.contains(stimulants) {
            return [stimulants]
        }
        return []
    }

    public var caffeineSourceSummary: Stimulants? {
        let resolved = resolvedCaffeineSources
        switch resolved.count {
        case 0:
            return stimulants
        case 1:
            return resolved.first
        default:
            return .multiple
        }
    }

    public var hasCaffeineIntake: Bool {
        !resolvedCaffeineSources.isEmpty || caffeineSourceSummary == .multiple
    }

    public var hasLegacyUnspecifiedCaffeineSources: Bool {
        caffeineSourceSummary == .multiple && resolvedCaffeineSources.isEmpty
    }

    public var caffeineSourceDisplayText: String? {
        let resolved = resolvedCaffeineSources
        if !resolved.isEmpty {
            return resolved.map(\.displayText).joined(separator: ", ")
        }
        return caffeineSourceSummary?.displayText
    }

    public static func sanitizedCaffeineSources(_ sources: [Stimulants]?) -> [Stimulants] {
        Array(Set((sources ?? []).filter { caffeineSourceOptions.contains($0) }))
            .sorted { $0.rawValue < $1.rawValue }
    }

    public static func caffeineSummary(for sources: [Stimulants]) -> Stimulants? {
        let sanitized = sanitizedCaffeineSources(sources)
        switch sanitized.count {
        case 0:
            return nil
        case 1:
            return sanitized.first
        default:
            return .multiple
        }
    }

    public static var defaultDoseSplitRatio: [Double] {
        [0.5, 0.5]
    }

    public static func sanitizedDoseSplitRatio(_ ratio: [Double]?) -> [Double]? {
        guard let ratio, ratio.count == 2 else { return nil }
        let safeValues = ratio.map { value -> Double in
            guard value.isFinite else { return 0 }
            return max(0, value)
        }
        let total = safeValues.reduce(0, +)
        guard total > 0 else { return nil }

        let normalizedFirst = max(0, min(1, safeValues[0] / total))
        let roundedFirst = (normalizedFirst * 100).rounded() / 100
        let roundedSecond = max(0, 1 - roundedFirst)
        return [roundedFirst, roundedSecond]
    }

    public var resolvedPlannedTotalNightlyMg: Int? {
        if let plannedTotalNightlyMg, plannedTotalNightlyMg > 0 {
            return plannedTotalNightlyMg
        }
        if let plannedDose1Mg, let plannedDose2Mg {
            return max(0, plannedDose1Mg + plannedDose2Mg)
        }
        return nil
    }

    public var resolvedPlannedDoseSplitRatio: [Double] {
        if let explicit = Self.sanitizedDoseSplitRatio(plannedDoseSplitRatio) {
            return explicit
        }
        if let plannedDose1Mg, let plannedDose2Mg {
            let total = Double(plannedDose1Mg + plannedDose2Mg)
            if total > 0 {
                return [Double(plannedDose1Mg) / total, Double(plannedDose2Mg) / total]
            }
        }
        return Self.defaultDoseSplitRatio
    }

    public var plannedDosePercentages: [Int]? {
        guard let total = resolvedPlannedTotalNightlyMg, total > 0 else { return nil }
        let first = Int((resolvedPlannedDoseSplitRatio[0] * 100).rounded())
        return [first, max(0, 100 - first)]
    }

    public var resolvedSleepAidSelections: [SleepAid] {
        let explicit = Self.sanitizedSleepAidSelections(sleepAidSelections)
        if !explicit.isEmpty {
            return explicit
        }
        if let sleepAids, Self.sleepAidOptions.contains(sleepAids) {
            return [sleepAids]
        }
        return []
    }

    public var sleepAidSummary: SleepAid? {
        let resolved = resolvedSleepAidSelections
        switch resolved.count {
        case 0:
            return sleepAids
        case 1:
            return resolved.first
        default:
            return .multiple
        }
    }

    public var hasSleepAids: Bool {
        !resolvedSleepAidSelections.isEmpty || sleepAidSummary == .multiple
    }

    public var hasLegacyUnspecifiedSleepAids: Bool {
        sleepAidSummary == .multiple && resolvedSleepAidSelections.isEmpty
    }

    public var sleepAidDisplayText: String? {
        let resolved = resolvedSleepAidSelections
        if !resolved.isEmpty {
            return resolved.map(\.displayText).joined(separator: ", ")
        }
        return sleepAidSummary?.displayText
    }

    public static func sanitizedSleepAidSelections(_ selections: [SleepAid]?) -> [SleepAid] {
        Array(Set((selections ?? []).filter { sleepAidOptions.contains($0) }))
            .sorted { $0.rawValue < $1.rawValue }
    }

    public static func sleepAidSummary(for selections: [SleepAid]) -> SleepAid? {
        let sanitized = sanitizedSleepAidSelections(selections)
        switch sanitized.count {
        case 0:
            return nil
        case 1:
            return sanitized.first
        default:
            return .multiple
        }
    }
}
