import Foundation

/// Unified sleep session that combines data from multiple sources:
/// - DoseTap: Dose timing, sleep events, window compliance
/// - Apple Health: Heart rate, HRV, sleep stages, respiratory rate
/// - WHOOP: Recovery score, strain, sleep performance
public struct UnifiedSleepSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    
    // DoseTap core data
    public let doseData: DoseSessionData
    
    // Apple Health data (optional)
    public let healthData: HealthSleepData?
    
    // WHOOP data (optional)
    public let whoopData: WhoopSleepData?
    
    // Computed unified metrics
    public var sleepQualityScore: Int? {
        // Weight: 40% WHOOP recovery, 30% dose compliance, 30% HRV
        var score: Double = 0
        var weights: Double = 0
        
        if let whoop = whoopData?.recoveryScore {
            score += Double(whoop) * 0.4
            weights += 0.4
        }
        
        if doseData.isCompliant {
            score += 85 * 0.3
            weights += 0.3
        } else if doseData.dose2Time != nil {
            score += 60 * 0.3
            weights += 0.3
        }
        
        if let hrv = healthData?.averageHRV {
            // Normalize HRV (assume 20-100ms range)
            let normalizedHRV = min(100, max(0, (hrv - 20) / 80 * 100))
            score += normalizedHRV * 0.3
            weights += 0.3
        }
        
        guard weights > 0 else { return nil }
        return Int(score / weights)
    }
    
    public var totalSleepDuration: TimeInterval? {
        // Prefer WHOOP, then Health, then estimate from events
        if let whoop = whoopData?.totalSleepSeconds {
            return TimeInterval(whoop)
        }
        if let health = healthData?.totalSleepDuration {
            return health
        }
        return doseData.estimatedSleepDuration
    }
    
    public var awakenings: Int {
        // Combine wakeTemp events with health/WHOOP wake data
        let eventWakes = doseData.sleepEvents.filter { $0.type == .wakeTemp }.count
        let healthWakes = healthData?.awakenings ?? 0
        return max(eventWakes, healthWakes)
    }
    
    public init(
        id: UUID = UUID(),
        date: Date,
        doseData: DoseSessionData,
        healthData: HealthSleepData? = nil,
        whoopData: WhoopSleepData? = nil
    ) {
        self.id = id
        self.date = date
        self.doseData = doseData
        self.healthData = healthData
        self.whoopData = whoopData
    }
}

// MARK: - DoseTap Session Data

public struct DoseSessionData: Codable, Sendable {
    public let sessionId: UUID
    public let dose1Time: Date
    public let dose2Time: Date?
    public let dose2Skipped: Bool
    public let snoozeCount: Int
    public let sleepEvents: [SleepEventRecord]
    
    /// Dose interval in minutes (nil if dose2 not taken)
    public var intervalMinutes: Int? {
        guard let d2 = dose2Time else { return nil }
    return TimeIntervalMath.minutesBetween(start: dose1Time, end: d2)
    }
    
    /// Whether the dose interval is within the 150-240 minute window
    public var isCompliant: Bool {
        guard let interval = intervalMinutes else { return false }
        return interval >= 150 && interval <= 240
    }
    
    /// Estimated sleep duration based on lights_out and wake_final events
    public var estimatedSleepDuration: TimeInterval? {
        let lightsOut = sleepEvents.first { $0.type == .lightsOut }?.timestamp
        let wakeFinal = sleepEvents.first { $0.type == .wakeFinal }?.timestamp
        
        guard let start = lightsOut, let end = wakeFinal else { return nil }
        return end.timeIntervalSince(start)
    }
    
    /// Count of bathroom trips during session
    public var bathroomCount: Int {
        sleepEvents.filter { $0.type == .bathroom }.count
    }
    
    public init(
        sessionId: UUID = UUID(),
        dose1Time: Date,
        dose2Time: Date? = nil,
        dose2Skipped: Bool = false,
        snoozeCount: Int = 0,
        sleepEvents: [SleepEventRecord] = []
    ) {
        self.sessionId = sessionId
        self.dose1Time = dose1Time
        self.dose2Time = dose2Time
        self.dose2Skipped = dose2Skipped
        self.snoozeCount = snoozeCount
        self.sleepEvents = sleepEvents
    }
}

/// Simplified sleep event record for session data
public struct SleepEventRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let type: SleepEventType
    public let timestamp: Date
    
    public init(id: UUID = UUID(), type: SleepEventType, timestamp: Date) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
    }
}

// MARK: - Apple Health Data

public struct HealthSleepData: Codable, Sendable {
    /// Total sleep duration in seconds
    public let totalSleepDuration: TimeInterval?
    
    /// Time spent in each sleep stage
    public let sleepStages: SleepStages?
    
    /// Average heart rate during sleep (bpm)
    public let averageHeartRate: Double?
    
    /// Minimum heart rate during sleep (bpm)
    public let minimumHeartRate: Double?
    
    /// Average HRV (ms) - heart rate variability
    public let averageHRV: Double?
    
    /// Average respiratory rate (breaths/min)
    public let respiratoryRate: Double?
    
    /// Blood oxygen saturation (%)
    public let oxygenSaturation: Double?
    
    /// Number of times marked awake
    public let awakenings: Int
    
    /// Time to fall asleep (minutes)
    public let sleepLatency: TimeInterval?
    
    public init(
        totalSleepDuration: TimeInterval? = nil,
        sleepStages: SleepStages? = nil,
        averageHeartRate: Double? = nil,
        minimumHeartRate: Double? = nil,
        averageHRV: Double? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturation: Double? = nil,
        awakenings: Int = 0,
        sleepLatency: TimeInterval? = nil
    ) {
        self.totalSleepDuration = totalSleepDuration
        self.sleepStages = sleepStages
        self.averageHeartRate = averageHeartRate
        self.minimumHeartRate = minimumHeartRate
        self.averageHRV = averageHRV
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        self.awakenings = awakenings
        self.sleepLatency = sleepLatency
    }
}

public struct SleepStages: Codable, Sendable {
    /// Duration in seconds
    public let awake: TimeInterval
    public let rem: TimeInterval
    public let core: TimeInterval  // Light sleep
    public let deep: TimeInterval
    
    public var total: TimeInterval {
        awake + rem + core + deep
    }
    
    /// Percentage of total sleep in each stage
    public var remPercentage: Double { total > 0 ? rem / total * 100 : 0 }
    public var deepPercentage: Double { total > 0 ? deep / total * 100 : 0 }
    public var corePercentage: Double { total > 0 ? core / total * 100 : 0 }
    
    public init(awake: TimeInterval = 0, rem: TimeInterval = 0, core: TimeInterval = 0, deep: TimeInterval = 0) {
        self.awake = awake
        self.rem = rem
        self.core = core
        self.deep = deep
    }
}

// MARK: - WHOOP Data

public struct WhoopSleepData: Codable, Sendable {
    /// Recovery score (0-100)
    public let recoveryScore: Int?
    
    /// Strain score for the day (0-21)
    public let strain: Double?
    
    /// Sleep performance percentage (0-100)
    public let sleepPerformance: Int?
    
    /// Sleep efficiency percentage
    public let sleepEfficiency: Double?
    
    /// Total sleep in seconds
    public let totalSleepSeconds: Int?
    
    /// Sleep need in seconds
    public let sleepNeed: Int?
    
    /// Sleep debt in seconds (negative = surplus)
    public let sleepDebt: Int?
    
    /// Resting heart rate (bpm)
    public let restingHeartRate: Double?
    
    /// HRV (ms)
    public let hrv: Double?
    
    /// Skin temperature deviation from baseline (°C)
    public let skinTempDeviation: Double?
    
    /// Blood oxygen (%)
    public let spo2: Double?
    
    /// Respiratory rate (breaths/min)
    public let respiratoryRate: Double?
    
    /// Sleep cycles
    public let cycles: Int?
    
    /// Disturbances (awakenings)
    public let disturbances: Int?
    
    /// Time in bed (seconds)
    public let timeInBed: Int?
    
    public init(
        recoveryScore: Int? = nil,
        strain: Double? = nil,
        sleepPerformance: Int? = nil,
        sleepEfficiency: Double? = nil,
        totalSleepSeconds: Int? = nil,
        sleepNeed: Int? = nil,
        sleepDebt: Int? = nil,
        restingHeartRate: Double? = nil,
        hrv: Double? = nil,
        skinTempDeviation: Double? = nil,
        spo2: Double? = nil,
        respiratoryRate: Double? = nil,
        cycles: Int? = nil,
        disturbances: Int? = nil,
        timeInBed: Int? = nil
    ) {
        self.recoveryScore = recoveryScore
        self.strain = strain
        self.sleepPerformance = sleepPerformance
        self.sleepEfficiency = sleepEfficiency
        self.totalSleepSeconds = totalSleepSeconds
        self.sleepNeed = sleepNeed
        self.sleepDebt = sleepDebt
        self.restingHeartRate = restingHeartRate
        self.hrv = hrv
        self.skinTempDeviation = skinTempDeviation
        self.spo2 = spo2
        self.respiratoryRate = respiratoryRate
        self.cycles = cycles
        self.disturbances = disturbances
        self.timeInBed = timeInBed
    }
}

// MARK: - Session Builder

/// Builder to construct unified sessions from multiple data sources
public struct UnifiedSessionBuilder {
    private var date: Date
    private var doseData: DoseSessionData?
    private var healthData: HealthSleepData?
    private var whoopData: WhoopSleepData?
    
    public init(date: Date) {
        self.date = date
    }
    
    public mutating func setDoseData(_ data: DoseSessionData) {
        self.doseData = data
    }
    
    public mutating func setHealthData(_ data: HealthSleepData) {
        self.healthData = data
    }
    
    public mutating func setWhoopData(_ data: WhoopSleepData) {
        self.whoopData = data
    }
    
    public func build() -> UnifiedSleepSession? {
        guard let doseData = doseData else { return nil }
        
        return UnifiedSleepSession(
            date: date,
            doseData: doseData,
            healthData: healthData,
            whoopData: whoopData
        )
    }
}

// MARK: - Session Aggregator

/// Aggregates statistics across multiple unified sessions
public struct SessionAggregator {
    private let sessions: [UnifiedSleepSession]
    
    public init(sessions: [UnifiedSleepSession]) {
        self.sessions = sessions
    }
    
    /// Average dose interval in minutes
    public var averageInterval: Double? {
        let intervals = sessions.compactMap { $0.doseData.intervalMinutes }
        guard !intervals.isEmpty else { return nil }
        return Double(intervals.reduce(0, +)) / Double(intervals.count)
    }
    
    /// Percentage of sessions with compliant dose intervals
    public var complianceRate: Double {
        let completed = sessions.filter { $0.doseData.dose2Time != nil }
        guard !completed.isEmpty else { return 0 }
        let compliant = completed.filter { $0.doseData.isCompliant }.count
        return Double(compliant) / Double(completed.count) * 100
    }
    
    /// Average sleep quality score
    public var averageSleepQuality: Double? {
        let scores = sessions.compactMap { $0.sleepQualityScore }
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }
    
    /// Average total sleep duration
    public var averageSleepDuration: TimeInterval? {
        let durations = sessions.compactMap { $0.totalSleepDuration }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }
    
    /// Average bathroom trips per night
    public var averageBathroomTrips: Double {
        guard !sessions.isEmpty else { return 0 }
        let total = sessions.map { $0.doseData.bathroomCount }.reduce(0, +)
        return Double(total) / Double(sessions.count)
    }
    
    /// Average awakenings per night
    public var averageAwakenings: Double {
        guard !sessions.isEmpty else { return 0 }
        let total = sessions.map { $0.awakenings }.reduce(0, +)
        return Double(total) / Double(sessions.count)
    }
    
    /// Average WHOOP recovery score
    public var averageRecovery: Double? {
        let scores = sessions.compactMap { $0.whoopData?.recoveryScore }
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }
    
    /// Average HRV
    public var averageHRV: Double? {
        // Prefer WHOOP HRV, fall back to Health
        let hrvValues = sessions.compactMap { session -> Double? in
            session.whoopData?.hrv ?? session.healthData?.averageHRV
        }
        guard !hrvValues.isEmpty else { return nil }
        return hrvValues.reduce(0, +) / Double(hrvValues.count)
    }
}
