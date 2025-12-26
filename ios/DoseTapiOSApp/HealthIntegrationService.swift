import Foundation
import HealthKit
import Combine

// MARK: - Health Data Integration Service
@MainActor
public class HealthDataService: ObservableObject {
    public static let shared = HealthDataService()
    
    @Published public private(set) var isAuthorized = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var recentSleepData: [HealthSleepData] = []
    
    private let healthStore = HKHealthStore()
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    
    private init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.healthKitNotAvailable
        }
        
        let readTypes: Set<HKObjectType> = [sleepType]
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    Task { @MainActor in
                        self.isAuthorized = true
                    }
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthDataError.authorizationDenied)
                }
            }
        }
    }
    
    private func checkAuthorizationStatus() {
        let status = healthStore.authorizationStatus(for: sleepType)
        isAuthorized = status == .sharingAuthorized
    }
    
    // MARK: - Data Fetching
    public func fetchRecentSleepData(days: Int = 30) async throws -> [HealthSleepData] {
        guard isAuthorized else { throw HealthDataError.notAuthorized }
        
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!
        
        let sleepData = try await fetchSleepSamples(from: startDate, to: endDate)
        let processedData = processSleepSamples(sleepData)
        
        // Update published properties on main actor
        self.recentSleepData = processedData
        self.lastSyncDate = Date()
        
        return processedData
    }
    
    private func fetchSleepSamples(from startDate: Date, to endDate: Date) async throws -> [HKCategorySample] {
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let sleepSamples = samples as? [HKCategorySample] ?? []
                    continuation.resume(returning: sleepSamples)
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    private func processSleepSamples(_ samples: [HKCategorySample]) -> [HealthSleepData] {
        let calendar = Calendar.current
        var nightSessions: [Date: [HKCategorySample]] = [:]
        
        // Group samples by night
        for sample in samples {
            let nightDate = calendar.startOfDay(for: sample.startDate)
            if nightSessions[nightDate] == nil {
                nightSessions[nightDate] = []
            }
            nightSessions[nightDate]?.append(sample)
        }
        
        return nightSessions.compactMap { (date, samples) in
            processSingleNight(date: date, samples: samples)
        }.sorted { $0.sleepDate > $1.sleepDate }
    }
    
    private func processSingleNight(date: Date, samples: [HKCategorySample]) -> HealthSleepData? {
        let inBedSamples = samples.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
        let asleepSamples = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
        let deepSleepSamples = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
        let remSleepSamples = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
        
        guard !inBedSamples.isEmpty || !asleepSamples.isEmpty else { return nil }
        
        let allSamples = inBedSamples + asleepSamples
        let sleepStart = allSamples.map { $0.startDate }.min()
        let sleepEnd = allSamples.map { $0.endDate }.max()
        
        let totalSleepTime = asleepSamples.reduce(0) { total, sample in
            total + sample.endDate.timeIntervalSince(sample.startDate)
        }
        
        let deepSleepTime = deepSleepSamples.reduce(0) { total, sample in
            total + sample.endDate.timeIntervalSince(sample.startDate)
        }
        
        let remSleepTime = remSleepSamples.reduce(0) { total, sample in
            total + sample.endDate.timeIntervalSince(sample.startDate)
        }
        
        // Calculate time to first wake (simplified)
        let timeToFirstWake = sleepStart != nil && sleepEnd != nil ? 
            sleepEnd!.timeIntervalSince(sleepStart!) : nil
        
        return HealthSleepData(
            sleepDate: date,
            sleepStart: sleepStart,
            sleepEnd: sleepEnd,
            timeToFirstWake: timeToFirstWake,
            totalSleepTime: totalSleepTime > 0 ? totalSleepTime : nil,
            deepSleepTime: deepSleepTime > 0 ? deepSleepTime : nil,
            remSleepTime: remSleepTime > 0 ? remSleepTime : nil
        )
    }
    
    // MARK: - Integration with DataStorageService
    public func syncWithCurrentSession() async {
        guard let sleepData = recentSleepData.first else { return }
        
        let healthData = HealthData(
            sleepStart: sleepData.sleepStart,
            sleepEnd: sleepData.sleepEnd,
            timeToFirstWake: sleepData.timeToFirstWake,
            totalSleepTime: sleepData.totalSleepTime,
            deepSleepTime: sleepData.deepSleepTime,
            remSleepTime: sleepData.remSleepTime
        )
        
        DataStorageService.shared.updateCurrentSessionHealthData(healthData)
    }
}

// MARK: - WHOOP Data Integration Service
@MainActor
public class WHOOPDataService: ObservableObject {
    public static let shared = WHOOPDataService()
    
    @Published public private(set) var isConnected = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var recentWHOOPData: [WHOOPSleepData] = []
    
    private var accessToken: String?
    private var refreshToken: String?
    
    private init() {
        loadStoredTokens()
    }
    
    // MARK: - Authentication
    public func connect() async throws {
        // TODO: Implement OAuth flow
        // For now, simulate connection
        isConnected = true
        lastSyncDate = Date()
    }
    
    public func disconnect() {
        accessToken = nil
        refreshToken = nil
        isConnected = false
        lastSyncDate = nil
        recentWHOOPData = []
        clearStoredTokens()
    }
    
    // MARK: - Data Fetching
    public func fetchRecentSleepData(days: Int = 30) async throws -> [WHOOPSleepData] {
        guard isConnected else { throw WHOOPDataError.notConnected }
        
        // TODO: Implement actual WHOOP API calls
        // For now, return mock data
        let mockData = generateMockWHOOPData(days: days)
        
        DispatchQueue.main.async {
            self.recentWHOOPData = mockData
            self.lastSyncDate = Date()
        }
        
        return mockData
    }
    
    private func generateMockWHOOPData(days: Int) -> [WHOOPSleepData] {
        let calendar = Calendar.current
        var data: [WHOOPSleepData] = []
        
        for i in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -i, to: Date()) else { continue }
            
            let sleepStart = calendar.date(bySettingHour: 22, minute: Int.random(in: 30...59), second: 0, of: date)
            let sleepDuration = TimeInterval.random(in: 6*3600...9*3600) // 6-9 hours
            let sleepEnd = sleepStart?.addingTimeInterval(sleepDuration)
            
            let whoopData = WHOOPSleepData(
                sleepDate: date,
                cycleId: "cycle_\(UUID().uuidString.prefix(8))",
                sleepStart: sleepStart,
                sleepEnd: sleepEnd,
                timeToFirstWake: TimeInterval.random(in: 150*60...240*60), // 2.5-4 hours
                sleepScore: Int.random(in: 60...95),
                recoveryScore: Int.random(in: 50...90),
                strain: Double.random(in: 8...18),
                hrv: Double.random(in: 20...80),
                restingHeartRate: Int.random(in: 45...70)
            )
            
            data.append(whoopData)
        }
        
        return data.sorted { $0.sleepDate > $1.sleepDate }
    }
    
    // MARK: - Integration with DataStorageService
    public func syncWithCurrentSession() async {
        guard let whoopData = recentWHOOPData.first else { return }
        
        let data = WHOOPData(
            cycleId: whoopData.cycleId,
            sleepStart: whoopData.sleepStart,
            sleepEnd: whoopData.sleepEnd,
            timeToFirstWake: whoopData.timeToFirstWake,
            sleepScore: whoopData.sleepScore,
            recoveryScore: whoopData.recoveryScore,
            strain: whoopData.strain,
            hrv: whoopData.hrv,
            restingHeartRate: whoopData.restingHeartRate
        )
        
        DataStorageService.shared.updateCurrentSessionWHOOPData(data)
    }
    
    // MARK: - Token Management
    private func loadStoredTokens() {
        // SECURITY FIX: Use Keychain instead of UserDefaults for token storage
        accessToken = KeychainHelper.shared.whoopAccessToken
        refreshToken = KeychainHelper.shared.whoopRefreshToken
        isConnected = accessToken != nil
        
        // Migration: Clear any tokens from UserDefaults (legacy)
        UserDefaults.standard.removeObject(forKey: "whoop_access_token")
        UserDefaults.standard.removeObject(forKey: "whoop_refresh_token")
    }
    
    private func clearStoredTokens() {
        KeychainHelper.shared.clearWHOOPTokens()
    }
}

// MARK: - Data Models
public struct HealthSleepData: Identifiable, Codable {
    public let id = UUID()
    public let sleepDate: Date
    public let sleepStart: Date?
    public let sleepEnd: Date?
    public let timeToFirstWake: TimeInterval?
    public let totalSleepTime: TimeInterval?
    public let deepSleepTime: TimeInterval?
    public let remSleepTime: TimeInterval?
    
    private enum CodingKeys: String, CodingKey {
        case sleepDate, sleepStart, sleepEnd, timeToFirstWake, totalSleepTime, deepSleepTime, remSleepTime
    }
}

public struct WHOOPSleepData: Identifiable, Codable {
    public let id = UUID()
    public let sleepDate: Date
    public let cycleId: String?
    public let sleepStart: Date?
    public let sleepEnd: Date?
    public let timeToFirstWake: TimeInterval?
    public let sleepScore: Int?
    public let recoveryScore: Int?
    public let strain: Double?
    public let hrv: Double?
    public let restingHeartRate: Int?
    
    private enum CodingKeys: String, CodingKey {
        case sleepDate, cycleId, sleepStart, sleepEnd, timeToFirstWake, sleepScore, recoveryScore, strain, hrv, restingHeartRate
    }
}

// MARK: - Error Types
public enum HealthDataError: Error, LocalizedError {
    case healthKitNotAvailable
    case authorizationDenied
    case notAuthorized
    case dataFetchFailed
    
    public var errorDescription: String? {
        switch self {
        case .healthKitNotAvailable:
            return "HealthKit is not available on this device"
        case .authorizationDenied:
            return "Health data access was denied"
        case .notAuthorized:
            return "Health data access not authorized"
        case .dataFetchFailed:
            return "Failed to fetch health data"
        }
    }
}

public enum WHOOPDataError: Error, LocalizedError {
    case notConnected
    case authenticationFailed
    case dataFetchFailed
    case networkError
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "WHOOP account not connected"
        case .authenticationFailed:
            return "WHOOP authentication failed"
        case .dataFetchFailed:
            return "Failed to fetch WHOOP data"
        case .networkError:
            return "Network error occurred"
        }
    }
}
