import Foundation

/// WHOOP Sleep and Recovery Data Fetching
/// Extends WHOOPService with methods to fetch sleep, recovery, and cycle data
///
extension WHOOPService {
    
    // MARK: - Data Fetching API
    
    /// Fetch sleep data for date range
    /// - Parameters:
    ///   - startDate: Start of range (inclusive)
    ///   - endDate: End of range (inclusive)
    /// - Returns: Array of sleep records
    func fetchSleepData(from startDate: Date, to endDate: Date) async throws -> [WHOOPSleep] {
        let formatter = ISO8601DateFormatter()
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        
        let endpoint = "/developer/v1/activity/sleep?start=\(start)&end=\(end)"
        let response: WHOOPPaginatedResponse<WHOOPSleep> = try await apiRequest(endpoint, type: WHOOPPaginatedResponse<WHOOPSleep>.self)
        
        lastSyncTime = Date()
        return response.records
    }
    
    /// Fetch recovery data for date range
    func fetchRecoveryData(from startDate: Date, to endDate: Date) async throws -> [WHOOPRecovery] {
        let formatter = ISO8601DateFormatter()
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        
        let endpoint = "/developer/v1/recovery?start=\(start)&end=\(end)"
        let response: WHOOPPaginatedResponse<WHOOPRecovery> = try await apiRequest(endpoint, type: WHOOPPaginatedResponse<WHOOPRecovery>.self)
        
        return response.records
    }
    
    /// Fetch cycle (daily) data for date range
    func fetchCycleData(from startDate: Date, to endDate: Date) async throws -> [WHOOPCycle] {
        let formatter = ISO8601DateFormatter()
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        
        let endpoint = "/developer/v1/cycle?start=\(start)&end=\(end)"
        let response: WHOOPPaginatedResponse<WHOOPCycle> = try await apiRequest(endpoint, type: WHOOPPaginatedResponse<WHOOPCycle>.self)
        
        return response.records
    }
    
    /// Fetch recent sleep data (last N nights)
    func fetchRecentSleep(nights: Int = 14) async throws -> [WHOOPSleep] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -nights, to: endDate) ?? endDate
        return try await fetchSleepData(from: startDate, to: endDate)
    }
    
    /// Fetch single night's sleep data
    func fetchSleepForNight(_ date: Date) async throws -> WHOOPSleep? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        
        let sleeps = try await fetchSleepData(from: startOfDay, to: endOfDay)
        return sleeps.first
    }
    
    /// Fetch sleep stages for a specific sleep ID
    func fetchSleepStages(sleepId: Int) async throws -> WHOOPSleepStages {
        let endpoint = "/developer/v1/activity/sleep/\(sleepId)"
        return try await apiRequest(endpoint, type: WHOOPSleepStages.self)
    }
    
    // MARK: - Heart Rate Data
    
    /// Fetch heart rate data for date range
    func fetchHeartRateData(from startDate: Date, to endDate: Date) async throws -> [WHOOPHeartRate] {
        let formatter = ISO8601DateFormatter()
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        
        let endpoint = "/developer/v1/activity/heart_rate?start=\(start)&end=\(end)"
        let response: WHOOPPaginatedResponse<WHOOPHeartRate> = try await apiRequest(endpoint, type: WHOOPPaginatedResponse<WHOOPHeartRate>.self)
        
        return response.records
    }
}

// MARK: - WHOOP Data Models

struct WHOOPPaginatedResponse<T: Codable>: Codable {
    let records: [T]
    let nextToken: String?
    
    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

/// Type alias for backward compatibility - WHOOPSleepRecord is now WHOOPSleep
typealias WHOOPSleepRecord = WHOOPSleep

/// WHOOP Sleep Record
struct WHOOPSleep: Codable, Identifiable {
    let id: Int
    let userId: Int?
    let createdAt: Date?
    let updatedAt: Date?
    let start: Date?
    let end: Date?
    let timezoneOffset: String?
    let nap: Bool?
    let scoreState: String?
    let score: WHOOPSleepScore?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start
        case end
        case timezoneOffset = "timezone_offset"
        case nap
        case scoreState = "score_state"
        case score
    }
    
    /// Duration in minutes
    var durationMinutes: Int? {
        guard let start = start, let end = end else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }
}

struct WHOOPSleepScore: Codable {
    let stageSummary: WHOOPStageSummary?
    let sleepNeeded: WHOOPSleepNeeded?
    let respiratoryRate: Double?
    let sleepPerformancePercentage: Double?
    let sleepConsistencyPercentage: Double?
    let sleepEfficiencyPercentage: Double?
    
    enum CodingKeys: String, CodingKey {
        case stageSummary = "stage_summary"
        case sleepNeeded = "sleep_needed"
        case respiratoryRate = "respiratory_rate"
        case sleepPerformancePercentage = "sleep_performance_percentage"
        case sleepConsistencyPercentage = "sleep_consistency_percentage"
        case sleepEfficiencyPercentage = "sleep_efficiency_percentage"
    }
}

struct WHOOPStageSummary: Codable {
    let totalInBedTimeMilli: Int?
    let totalAwakeTimeMilli: Int?
    let totalNoDataTimeMilli: Int?
    let totalLightSleepTimeMilli: Int?
    let totalSlowWaveSleepTimeMilli: Int?
    let totalRemSleepTimeMilli: Int?
    let sleepCycleCount: Int?
    let disturbanceCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case totalInBedTimeMilli = "total_in_bed_time_milli"
        case totalAwakeTimeMilli = "total_awake_time_milli"
        case totalNoDataTimeMilli = "total_no_data_time_milli"
        case totalLightSleepTimeMilli = "total_light_sleep_time_milli"
        case totalSlowWaveSleepTimeMilli = "total_slow_wave_sleep_time_milli"
        case totalRemSleepTimeMilli = "total_rem_sleep_time_milli"
        case sleepCycleCount = "sleep_cycle_count"
        case disturbanceCount = "disturbance_count"
    }
    
    /// Total awake time in minutes
    var awakeMinutes: Int {
        (totalAwakeTimeMilli ?? 0) / 60000
    }
    
    /// Total light sleep in minutes
    var lightSleepMinutes: Int {
        (totalLightSleepTimeMilli ?? 0) / 60000
    }
    
    /// Total deep (slow wave) sleep in minutes
    var deepSleepMinutes: Int {
        (totalSlowWaveSleepTimeMilli ?? 0) / 60000
    }
    
    /// Total REM sleep in minutes
    var remSleepMinutes: Int {
        (totalRemSleepTimeMilli ?? 0) / 60000
    }
    
    /// Total sleep time in minutes (excluding awake)
    var totalSleepMinutes: Int {
        lightSleepMinutes + deepSleepMinutes + remSleepMinutes
    }
}

struct WHOOPSleepNeeded: Codable {
    let baselineMilli: Int?
    let needFromSleepDebtMilli: Int?
    let needFromRecentStrainMilli: Int?
    let needFromRecentNapMilli: Int?
    
    enum CodingKeys: String, CodingKey {
        case baselineMilli = "baseline_milli"
        case needFromSleepDebtMilli = "need_from_sleep_debt_milli"
        case needFromRecentStrainMilli = "need_from_recent_strain_milli"
        case needFromRecentNapMilli = "need_from_recent_nap_milli"
    }
    
    /// Total sleep needed in minutes
    var totalNeededMinutes: Int {
        let total = (baselineMilli ?? 0) + (needFromSleepDebtMilli ?? 0) +
                    (needFromRecentStrainMilli ?? 0) - (needFromRecentNapMilli ?? 0)
        return total / 60000
    }
}

/// Detailed sleep stages for visualization
struct WHOOPSleepStages: Codable {
    let id: Int
    let stages: [WHOOPStage]?
    
    struct WHOOPStage: Codable {
        let stage: String  // "wake", "light", "slow_wave", "rem"
        let startTime: Date?
        let endTime: Date?
        
        enum CodingKeys: String, CodingKey {
            case stage
            case startTime = "start_time"
            case endTime = "end_time"
        }
        
        /// Map WHOOP stage to display stage
        var displayStage: SleepDisplayStage {
            switch stage.lowercased() {
            case "wake", "awake": return .awake
            case "light": return .light
            case "slow_wave", "deep": return .deep
            case "rem": return .rem
            default: return .light
            }
        }
    }
}

/// WHOOP Recovery Record
struct WHOOPRecovery: Codable, Identifiable {
    let cycleId: Int
    let sleepId: Int?
    let userId: Int?
    let createdAt: Date?
    let updatedAt: Date?
    let scoreState: String?
    let score: WHOOPRecoveryScore?
    
    var id: Int { cycleId }
    
    enum CodingKeys: String, CodingKey {
        case cycleId = "cycle_id"
        case sleepId = "sleep_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case scoreState = "score_state"
        case score
    }
}

struct WHOOPRecoveryScore: Codable {
    let userCalibrating: Bool?
    let recoveryScore: Double?
    let restingHeartRate: Double?
    let hrvRmssdMilli: Double?
    let spo2Percentage: Double?
    let skinTempCelsius: Double?
    
    enum CodingKeys: String, CodingKey {
        case userCalibrating = "user_calibrating"
        case recoveryScore = "recovery_score"
        case restingHeartRate = "resting_heart_rate"
        case hrvRmssdMilli = "hrv_rmssd_milli"
        case spo2Percentage = "spo2_percentage"
        case skinTempCelsius = "skin_temp_celsius"
    }
    
    /// HRV in ms
    var hrvMs: Double? {
        hrvRmssdMilli
    }
}

/// WHOOP Cycle (daily) Record
struct WHOOPCycle: Codable, Identifiable {
    let id: Int
    let userId: Int?
    let createdAt: Date?
    let updatedAt: Date?
    let start: Date?
    let end: Date?
    let timezoneOffset: String?
    let scoreState: String?
    let score: WHOOPCycleScore?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start
        case end
        case timezoneOffset = "timezone_offset"
        case scoreState = "score_state"
        case score
    }
}

struct WHOOPCycleScore: Codable {
    let strain: Double?
    let kilojoule: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    
    enum CodingKeys: String, CodingKey {
        case strain
        case kilojoule
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
    }
}

/// Heart rate data point
struct WHOOPHeartRate: Codable, Identifiable {
    let time: Date
    let heartRate: Int
    
    var id: Date { time }
    
    enum CodingKeys: String, CodingKey {
        case time
        case heartRate = "heart_rate"
    }
}

// MARK: - Conversion to DoseTap Models

extension WHOOPSleepStages.WHOOPStage {
    /// Convert to SleepStageBand for timeline display
    func toSleepStageBand() -> SleepStageBand? {
        guard let start = startTime, let end = endTime else { return nil }
        
        let sleepStage: SleepStage
        switch stage.lowercased() {
        case "wake", "awake": sleepStage = .awake
        case "light": sleepStage = .light
        case "slow_wave", "deep": sleepStage = .deep
        case "rem": sleepStage = .rem
        default: sleepStage = .core
        }
        
        return SleepStageBand(stage: sleepStage, startTime: start, endTime: end)
    }
}

extension WHOOPSleep {
    /// Convert WHOOP sleep to night summary
    func toNightSummary() -> WHOOPNightSummary {
        WHOOPNightSummary(
            date: start ?? Date(),
            sleepId: id,
            totalSleepMinutes: score?.stageSummary?.totalSleepMinutes ?? 0,
            remMinutes: score?.stageSummary?.remSleepMinutes ?? 0,
            deepMinutes: score?.stageSummary?.deepSleepMinutes ?? 0,
            lightMinutes: score?.stageSummary?.lightSleepMinutes ?? 0,
            awakeMinutes: score?.stageSummary?.awakeMinutes ?? 0,
            disturbanceCount: score?.stageSummary?.disturbanceCount ?? 0,
            sleepEfficiency: score?.sleepEfficiencyPercentage,
            respiratoryRate: score?.respiratoryRate
        )
    }
}

/// Simplified night summary for UI display
struct WHOOPNightSummary: Identifiable {
    let date: Date
    let sleepId: Int
    let totalSleepMinutes: Int
    let remMinutes: Int
    let deepMinutes: Int
    let lightMinutes: Int
    let awakeMinutes: Int
    let disturbanceCount: Int
    let sleepEfficiency: Double?
    let respiratoryRate: Double?
    
    var id: Int { sleepId }
    
    var formattedTotalSleep: String {
        let hours = totalSleepMinutes / 60
        let mins = totalSleepMinutes % 60
        return "\(hours)h \(mins)m"
    }
}
