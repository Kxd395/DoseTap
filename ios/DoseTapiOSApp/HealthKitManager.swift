import Foundation
import HealthKit

/// Manages HealthKit data access for heart rate, HRV, and sleep data
/// WHOOP syncs to Apple Health, so we can pull granular HR samples here
@MainActor
final class HealthKitManager: ObservableObject {
    
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    
    @Published var isAuthorized = false
    @Published var lastError: String?
    
    // MARK: - Heart Rate Data Types
    
    struct HeartRateSample: Identifiable {
        let id = UUID()
        let timestamp: Date
        let bpm: Double
        let source: String  // e.g., "WHOOP", "Apple Watch"
    }
    
    struct HRVSample: Identifiable {
        let id = UUID()
        let timestamp: Date
        let sdnn: Double  // Standard deviation of NN intervals (ms)
        let source: String
    }
    
    struct SleepSegment: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        let stage: SleepStage
        let source: String
    }
    
    enum SleepStage: String {
        case inBed = "In Bed"
        case asleepUnspecified = "Asleep"
        case asleepCore = "Core Sleep"
        case asleepDeep = "Deep Sleep"
        case asleepREM = "REM Sleep"
        case awake = "Awake"
    }
    
    // MARK: - Authorization
    
    /// Request HealthKit authorization for HR, HRV, and Sleep data
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        
        // Types we want to read
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
            HKCategoryType(.sleepAnalysis)
        ]
        
        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
        isAuthorized = true
    }
    
    // MARK: - Heart Rate Queries
    
    /// Fetch heart rate samples for a specific time range
    /// - Parameters:
    ///   - start: Start of the time range
    ///   - end: End of the time range
    /// - Returns: Array of heart rate samples sorted by timestamp
    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let hrSamples = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HeartRateSample(
                        timestamp: sample.startDate,
                        bpm: sample.quantity.doubleValue(for: HKUnit(from: "count/min")),
                        source: sample.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: hrSamples)
            }
            healthStore.execute(query)
        }
    }
    
    /// Fetch heart rate samples during last night's sleep (midnight to now)
    func fetchOvernightHeartRate() async throws -> [HeartRateSample] {
        let calendar = Calendar.current
        let now = Date()
        
        // Get last night: from 8 PM yesterday to 10 AM today
        guard let yesterday8PM = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: now)!),
              let today10AM = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) else {
            throw HealthKitError.invalidDateRange
        }
        
        return try await fetchHeartRateSamples(from: yesterday8PM, to: today10AM)
    }
    
    // MARK: - HRV Queries
    
    /// Fetch HRV (SDNN) samples for a specific time range
    func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let hrvSamples = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HRVSample(
                        timestamp: sample.startDate,
                        sdnn: sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)),
                        source: sample.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: hrvSamples)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Sleep Analysis
    
    /// Fetch sleep analysis segments for a specific time range
    func fetchSleepSegments(from start: Date, to end: Date) async throws -> [SleepSegment] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let segments = (samples as? [HKCategorySample] ?? []).compactMap { sample -> SleepSegment? in
                    let stage: SleepStage
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        stage = .inBed
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        stage = .asleepUnspecified
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        stage = .asleepCore
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        stage = .asleepDeep
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        stage = .asleepREM
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        stage = .awake
                    default:
                        stage = .asleepUnspecified
                    }
                    
                    return SleepSegment(
                        start: sample.startDate,
                        end: sample.endDate,
                        stage: stage,
                        source: sample.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: segments)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Convenience: Overnight Summary
    
    struct OvernightSummary {
        let heartRateSamples: [HeartRateSample]
        let hrvSamples: [HRVSample]
        let sleepSegments: [SleepSegment]
        
        var minHR: Double? { heartRateSamples.map(\.bpm).min() }
        var maxHR: Double? { heartRateSamples.map(\.bpm).max() }
        var avgHR: Double? {
            guard !heartRateSamples.isEmpty else { return nil }
            return heartRateSamples.map(\.bpm).reduce(0, +) / Double(heartRateSamples.count)
        }
        var avgHRV: Double? {
            guard !hrvSamples.isEmpty else { return nil }
            return hrvSamples.map(\.sdnn).reduce(0, +) / Double(hrvSamples.count)
        }
        
        /// Filter HR samples during a specific sleep stage
        func heartRateDuring(stage: SleepStage) -> [HeartRateSample] {
            heartRateSamples.filter { hr in
                sleepSegments.contains { segment in
                    segment.stage == stage && hr.timestamp >= segment.start && hr.timestamp <= segment.end
                }
            }
        }
        
        /// Get HR samples from WHOOP only
        var whoopHeartRateSamples: [HeartRateSample] {
            heartRateSamples.filter { $0.source.lowercased().contains("whoop") }
        }
    }
    
    /// Fetch all overnight health data
    func fetchOvernightSummary() async throws -> OvernightSummary {
        let calendar = Calendar.current
        let now = Date()
        
        guard let yesterday8PM = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: now)!),
              let today10AM = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) else {
            throw HealthKitError.invalidDateRange
        }
        
        async let hr = fetchHeartRateSamples(from: yesterday8PM, to: today10AM)
        async let hrv = fetchHRVSamples(from: yesterday8PM, to: today10AM)
        async let sleep = fetchSleepSegments(from: yesterday8PM, to: today10AM)
        
        return try await OvernightSummary(
            heartRateSamples: hr,
            hrvSamples: hrv,
            sleepSegments: sleep
        )
    }
    
    // MARK: - Errors
    
    enum HealthKitError: LocalizedError {
        case notAvailable
        case notAuthorized
        case invalidDateRange
        
        var errorDescription: String? {
            switch self {
            case .notAvailable: return "HealthKit is not available on this device"
            case .notAuthorized: return "HealthKit access not authorized"
            case .invalidDateRange: return "Invalid date range"
            }
        }
    }
}

// MARK: - Preview/Testing Support

#if DEBUG
extension HealthKitManager {
    /// Generate mock data for previews
    static func mockOvernightSummary() -> OvernightSummary {
        let now = Date()
        let calendar = Calendar.current
        
        // Generate HR samples every 5 minutes from 10 PM to 6 AM
        var hrSamples: [HeartRateSample] = []
        var currentTime = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: now)!)!
        let endTime = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: now)!
        
        while currentTime < endTime {
            // Simulate lower HR during deep sleep (1-3 AM)
            let hour = calendar.component(.hour, from: currentTime)
            let baseHR: Double = (hour >= 1 && hour <= 3) ? 52 : 62
            let variation = Double.random(in: -5...5)
            
            hrSamples.append(HeartRateSample(
                timestamp: currentTime,
                bpm: baseHR + variation,
                source: "WHOOP"
            ))
            currentTime = calendar.date(byAdding: .minute, value: 5, to: currentTime)!
        }
        
        return OvernightSummary(
            heartRateSamples: hrSamples,
            hrvSamples: [
                HRVSample(timestamp: now, sdnn: 45.0, source: "WHOOP")
            ],
            sleepSegments: []
        )
    }
}
#endif
