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
        let endpoint = Self.makeDateRangeEndpoint(
            path: "/developer/v2/activity/sleep",
            startDate: startDate,
            endDate: endDate
        )
        let records = try await fetchPaginatedRecords(endpoint: endpoint, type: WHOOPSleep.self)

        lastSyncTime = Date()
        return records
    }
    
    /// Fetch recovery data for date range
    func fetchRecoveryData(from startDate: Date, to endDate: Date) async throws -> [WHOOPRecovery] {
        let endpoint = Self.makeDateRangeEndpoint(
            path: "/developer/v2/recovery",
            startDate: startDate,
            endDate: endDate
        )
        return try await fetchPaginatedRecords(endpoint: endpoint, type: WHOOPRecovery.self)
    }
    
    /// Fetch cycle (daily) data for date range
    func fetchCycleData(from startDate: Date, to endDate: Date) async throws -> [WHOOPCycle] {
        let endpoint = Self.makeDateRangeEndpoint(
            path: "/developer/v2/cycle",
            startDate: startDate,
            endDate: endDate
        )
        return try await fetchPaginatedRecords(endpoint: endpoint, type: WHOOPCycle.self)
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
    func fetchSleepStages(sleepId: String) async throws -> WHOOPSleepStages {
        let endpoint = "/developer/v2/activity/sleep/\(sleepId)"
        return try await apiRequest(endpoint, type: WHOOPSleepStages.self)
    }
    
    // MARK: - Heart Rate Data
    
    /// Fetch heart rate data for date range
    func fetchHeartRateData(from startDate: Date, to endDate: Date) async throws -> [WHOOPHeartRate] {
        let endpoint = Self.makeDateRangeEndpoint(
            path: "/developer/v2/activity/heart_rate",
            startDate: startDate,
            endDate: endDate
        )
        return try await fetchPaginatedRecords(endpoint: endpoint, type: WHOOPHeartRate.self)
    }

    /// Fetch scored WHOOP nights and merge in recovery metrics when available.
    func fetchNightSummaries(from startDate: Date, to endDate: Date) async throws -> [WHOOPNightSummary] {
        let sleeps = try await fetchSleepData(from: startDate, to: endDate)

        do {
            let recoveries = try await fetchRecoveryData(from: startDate, to: endDate)
            return Self.makeNightSummaries(sleeps: sleeps, recoveries: recoveries)
        } catch {
            // Recovery enrichment is additive. Keep the scored sleep payloads even if recovery fails.
            return Self.makeNightSummaries(sleeps: sleeps, recoveries: [])
        }
    }

    static func makeNightSummaries(sleeps: [WHOOPSleep], recoveries: [WHOOPRecovery]) -> [WHOOPNightSummary] {
        var summariesBySleepID: [String: WHOOPNightSummary] = [:]

        for sleep in sleeps {
            if let state = sleep.scoreState?.uppercased(), state != "SCORED" {
                continue
            }

            let summary = sleep.toNightSummary()
            guard summary.hasValidSleepData else { continue }
            summariesBySleepID[summary.sleepId] = summary
        }

        guard !summariesBySleepID.isEmpty else {
            return []
        }

        for recovery in recoveries {
            guard let sleepId = recovery.sleepId,
                  var summary = summariesBySleepID[sleepId] else {
                continue
            }

            summary.recoveryScore = recovery.score?.recoveryScore
            summary.hrvMs = recovery.score?.hrvMs
            summary.restingHeartRate = recovery.score?.restingHeartRate
            summary.spo2Percentage = recovery.score?.spo2Percentage
            summary.skinTempCelsius = recovery.score?.skinTempCelsius
            summariesBySleepID[sleepId] = summary
        }

        return summariesBySleepID.values.sorted { $0.date < $1.date }
    }

    private func fetchPaginatedRecords<T: Codable>(endpoint: String, type _: T.Type) async throws -> [T] {
        var records: [T] = []
        var nextToken: String?
        var seenTokens = Set<String>()
        var pageCount = 0

        repeat {
            pageCount += 1
            if pageCount > Self.paginationPageLimit {
                throw WHOOPError.apiError(
                    "pagination_limit_exceeded",
                    "WHOOP pagination exceeded \(Self.paginationPageLimit) pages"
                )
            }

            let pageEndpoint = Self.endpoint(endpoint, addingNextToken: nextToken)
            let response: WHOOPPaginatedResponse<T> = try await apiRequest(
                pageEndpoint,
                type: WHOOPPaginatedResponse<T>.self
            )

            records.append(contentsOf: response.records)

            guard let token = response.nextToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !token.isEmpty else {
                nextToken = nil
                continue
            }

            if seenTokens.contains(token) {
                throw WHOOPError.apiError(
                    "pagination_loop",
                    "WHOOP pagination returned a repeated next_token"
                )
            }

            seenTokens.insert(token)
            nextToken = token
        } while nextToken != nil

        return records
    }

    static func makeDateRangeEndpoint(path: String, startDate: Date, endDate: Date) -> String {
        makeEndpoint(
            path: path,
            queryItems: [
                URLQueryItem(name: "start", value: AppFormatters.iso8601.string(from: startDate)),
                URLQueryItem(name: "end", value: AppFormatters.iso8601.string(from: endDate))
            ]
        )
    }

    static func endpoint(_ endpoint: String, addingNextToken nextToken: String?) -> String {
        guard let nextToken = nextToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !nextToken.isEmpty,
              var components = URLComponents(string: endpoint) else {
            return endpoint
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "nextToken" }
        queryItems.append(URLQueryItem(name: "nextToken", value: nextToken))
        components.queryItems = queryItems
        return components.string ?? endpoint
    }

    private static var paginationPageLimit: Int { 100 }

    private static func makeEndpoint(path: String, queryItems: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.string ?? "\(path)?\(queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))"
    }
}

// MARK: - Flexible ID Decoding Helpers

extension KeyedDecodingContainer {
    func decodeStringOrIntIfPresent(forKey key: Key) -> String? {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }
        return nil
    }

    func decodeStringOrInt(forKey key: Key) throws -> String {
        if let stringValue = try? decode(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try? decode(Int.self, forKey: key) {
            return String(intValue)
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected String or Int")
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
    let id: String
    let userId: String?
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeStringOrInt(forKey: .id)
        userId = c.decodeStringOrIntIfPresent(forKey: .userId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        timezoneOffset = try c.decodeIfPresent(String.self, forKey: .timezoneOffset)
        nap = try c.decodeIfPresent(Bool.self, forKey: .nap)
        scoreState = try c.decodeIfPresent(String.self, forKey: .scoreState)
        score = try c.decodeIfPresent(WHOOPSleepScore.self, forKey: .score)
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
    let id: String
    let stages: [WHOOPStage]?

    enum CodingKeys: String, CodingKey {
        case id
        case stages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeStringOrInt(forKey: .id)
        stages = try c.decodeIfPresent([WHOOPStage].self, forKey: .stages)
    }
    
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
    let cycleId: String
    let sleepId: String?
    let userId: String?
    let createdAt: Date?
    let updatedAt: Date?
    let scoreState: String?
    let score: WHOOPRecoveryScore?
    
    var id: String { cycleId }
    
    enum CodingKeys: String, CodingKey {
        case cycleId = "cycle_id"
        case sleepId = "sleep_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case scoreState = "score_state"
        case score
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cycleId = try c.decodeStringOrInt(forKey: .cycleId)
        sleepId = c.decodeStringOrIntIfPresent(forKey: .sleepId)
        userId = c.decodeStringOrIntIfPresent(forKey: .userId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        scoreState = try c.decodeIfPresent(String.self, forKey: .scoreState)
        score = try c.decodeIfPresent(WHOOPRecoveryScore.self, forKey: .score)
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
    let id: String
    let userId: String?
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeStringOrInt(forKey: .id)
        userId = c.decodeStringOrIntIfPresent(forKey: .userId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        timezoneOffset = try c.decodeIfPresent(String.self, forKey: .timezoneOffset)
        scoreState = try c.decodeIfPresent(String.self, forKey: .scoreState)
        score = try c.decodeIfPresent(WHOOPCycleScore.self, forKey: .score)
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
            inBedMinutes: score?.stageSummary?.totalInBedTimeMilli.map { $0 / 60000 },
            disturbanceCount: score?.stageSummary?.disturbanceCount ?? 0,
            sleepEfficiency: score?.sleepEfficiencyPercentage,
            sleepPerformance: score?.sleepPerformancePercentage,
            sleepConsistency: score?.sleepConsistencyPercentage,
            respiratoryRate: score?.respiratoryRate,
            sleepNeedBaselineMinutes: score?.sleepNeeded?.baselineMilli.map { $0 / 60000 },
            sleepNeedDebtMinutes: score?.sleepNeeded?.needFromSleepDebtMilli.map { $0 / 60000 },
            sleepNeedStrainMinutes: score?.sleepNeeded?.needFromRecentStrainMilli.map { $0 / 60000 },
            sleepNeedNapMinutes: score?.sleepNeeded?.needFromRecentNapMilli.map { $0 / 60000 }
        )
    }
}

/// Simplified night summary for UI display
struct WHOOPNightSummary: Identifiable {
    let date: Date
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
    let sleepNeedBaselineMinutes: Int?
    let sleepNeedDebtMinutes: Int?
    let sleepNeedStrainMinutes: Int?
    let sleepNeedNapMinutes: Int?
    
    // Recovery data (merged from WHOOPRecovery — set after initial creation)
    var recoveryScore: Double?
    var hrvMs: Double?
    var restingHeartRate: Double?
    var spo2Percentage: Double?
    var skinTempCelsius: Double?
    
    var id: String { sleepId }
    
    var formattedTotalSleep: String {
        let hours = totalSleepMinutes / 60
        let mins = totalSleepMinutes % 60
        return "\(hours)h \(mins)m"
    }

    /// True when the sleep record has actual scored data (not all zeros).
    var hasValidSleepData: Bool {
        totalSleepMinutes > 0 || deepMinutes > 0 || remMinutes > 0 || lightMinutes > 0
    }
}
