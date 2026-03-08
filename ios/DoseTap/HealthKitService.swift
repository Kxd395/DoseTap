import Foundation
import HealthKit
import os.log

private let healthKitLog = Logger(subsystem: "com.dosetap.app", category: "HealthKitService")

/// HealthKit service for reading sleep data and computing TTFW baselines
/// TTFW = Time to First Wake (minutes from "asleep" to first "awake" segment)
///
/// Conforms to `HealthKitProviding` protocol for dependency injection.
/// Tests should use `NoOpHealthKitProvider` instead to avoid HealthKit entitlements.
@MainActor
final class HealthKitService: ObservableObject, HealthKitProviding {
    
    static let shared = HealthKitService()
    
    private let healthStore = HKHealthStore()
    private let readTypes: Set<HKObjectType>
    private let authorizationTimeoutSeconds: UInt64 = 15
    
    // MARK: - Published State
    @Published var isAuthorized = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    
    // MARK: - Initialization
    private init() {
        self.readTypes = Self.defaultReadTypes()
        if HKHealthStore.isHealthDataAvailable() {
            // Restore authorization status on init so state is consistent after app restart.
            checkAuthorizationStatus()
            #if DEBUG
            healthKitLog.debug("Init authorization status: \(self.authorizationStatus.rawValue, privacy: .public), isAuthorized: \(self.isAuthorized, privacy: .public)")
            #endif
        }
    }
    @Published var lastError: String?
    @Published var ttfwBaseline: Double?  // Average TTFW in minutes
    @Published var sleepHistory: [SleepNightSummary] = []

    private enum AuthorizationError: Error {
        case timedOut
    }
    
    // MARK: - Data Types
    
    struct SleepNightSummary: Identifiable {
        let id = UUID()
        let date: Date          // Night start date
        let bedTime: Date?      // When user got in bed
        let sleepOnset: Date?   // When first fell asleep
        let firstWake: Date?    // First wake after sleep onset
        let finalWake: Date?    // Final wake up
        let ttfwMinutes: Double?  // Time to first wake
        let totalSleepMinutes: Double
        let wakeCount: Int      // Number of wake periods (WASO proxy)
        let source: String
    }
    
    enum SleepStage {
        case inBed
        case asleep
        case asleepCore
        case asleepDeep
        case asleepREM
        case awake
        
        static func from(hkValue: Int) -> SleepStage {
            switch hkValue {
            case HKCategoryValueSleepAnalysis.inBed.rawValue: return .inBed
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return .asleepCore
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .asleepDeep
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .asleepREM
            case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
            default: return .asleep
            }
        }
        
        var isAsleep: Bool {
            switch self {
            case .asleep, .asleepCore, .asleepDeep, .asleepREM: return true
            default: return false
            }
        }
    }
    
    struct SleepSegment {
        let start: Date
        let end: Date
        let stage: SleepStage
        let source: String
    }

    struct NightBiometricsSummary {
        let averageHeartRate: Double?
        let respiratoryRate: Double?
        let hrvMs: Double?
        let restingHeartRate: Double?

        var hasAnyMetric: Bool {
            averageHeartRate != nil || respiratoryRate != nil || hrvMs != nil || restingHeartRate != nil
        }
    }

    struct TimelineBiometrics {
        let heartRate: [HeartRateDataPoint]
        let respiratoryRate: [RespiratoryRateDataPoint]
        let hrv: [HRVDataPoint]
        let summary: NightBiometricsSummary

        var hasAnyData: Bool {
            !heartRate.isEmpty || !respiratoryRate.isEmpty || !hrv.isEmpty || summary.hasAnyMetric
        }
    }
    
    // MARK: - Authorization
    
    /// Check if HealthKit is available
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private static func defaultReadTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis)]
        let additionalIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .respiratoryRate,
            .heartRateVariabilitySDNN,
            .restingHeartRate
        ]

        for identifier in additionalIdentifiers {
            if let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(quantityType)
            }
        }

        return types
    }
    
    /// Request HealthKit authorization for sleep data
    func requestAuthorization() async -> Bool {
        guard isAvailable else {
            lastError = "HealthKit is not available on this device"
            return false
        }

        do {
            _ = try await withTimeout(seconds: authorizationTimeoutSeconds) {
                try await self.requestAuthorizationViaCallback()
            }
            await refreshReadAuthorization()
            if isAuthorized {
                lastError = nil
                healthKitLog.info("Authorization granted")
            } else {
                lastError = "HealthKit permission not granted"
                healthKitLog.warning("Authorization denied")
            }
            return isAuthorized
        } catch AuthorizationError.timedOut {
            lastError = "HealthKit authorization timed out. Open Health and try again."
            healthKitLog.warning("Authorization timed out")
            return false
        } catch {
            lastError = error.localizedDescription
            healthKitLog.error("Authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() {
        guard isAvailable else {
            authorizationStatus = .notDetermined
            isAuthorized = false
            lastError = "HealthKit is not available on this device"
            return
        }

        let sleepType = HKCategoryType(.sleepAnalysis)
        authorizationStatus = healthStore.authorizationStatus(for: sleepType)

        Task { @MainActor in
            await refreshReadAuthorization()
        }
    }

    private func refreshReadAuthorization() async {
        do {
            let sleepType = HKCategoryType(.sleepAnalysis)
            authorizationStatus = healthStore.authorizationStatus(for: sleepType)
            let requestStatus = try await requestStatusForRead()
            switch requestStatus {
            case .shouldRequest:
                isAuthorized = false
                lastError = nil
                return
            case .unnecessary:
                let canRead = try await probeSleepReadAccess()
                isAuthorized = canRead
                lastError = canRead ? nil : "HealthKit permission not granted"
            case .unknown:
                isAuthorized = false
                lastError = "HealthKit authorization state unknown"
            @unknown default:
                isAuthorized = false
                lastError = "HealthKit authorization state unknown"
            }
        } catch {
            if isAuthorizationDenied(error) {
                isAuthorized = false
                lastError = "HealthKit permission not granted"
            } else {
                isAuthorized = false
                lastError = error.localizedDescription
            }
        }
    }

    private func requestStatusForRead() async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func probeSleepReadAccess() async throws -> Bool {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: true)
                }
            }
            healthStore.execute(query)
        }
    }

    private func isAuthorizationDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain,
              let code = HKError.Code(rawValue: nsError.code) else {
            return false
        }
        return code == .errorAuthorizationDenied || code == .errorHealthDataUnavailable
    }

    private func requestAuthorizationViaCallback() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private func withTimeout<T>(
        seconds: UInt64,
        operation: @MainActor @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw AuthorizationError.timedOut
            }
            guard let result = try await group.next() else {
                throw AuthorizationError.timedOut
            }
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Sleep Data Queries
    
    /// Fetch sleep segments for a date range
    private func fetchSleepSegments(from start: Date, to end: Date) async throws -> [SleepSegment] {
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
                
                let segments = (samples as? [HKCategorySample] ?? []).map { sample in
                    SleepSegment(
                        start: sample.startDate,
                        end: sample.endDate,
                        stage: SleepStage.from(hkValue: sample.value),
                        source: sample.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: segments)
            }
            healthStore.execute(query)
        }
    }

    private func fetchQuantitySamples(
        type: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date
    ) async throws -> [HKQuantitySample] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func averageQuantityValue(samples: [HKQuantitySample], unit: HKUnit) -> Double? {
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0.0) { partial, sample in
            partial + sample.quantity.doubleValue(for: unit)
        }
        return total / Double(samples.count)
    }
    
    /// Analyze a single night's sleep data
    private func analyzeSleepNight(segments: [SleepSegment], nightStart: Date) -> SleepNightSummary? {
        guard !segments.isEmpty else { return nil }
        
        // Sort by start time
        let sorted = segments.sorted { $0.start < $1.start }
        
        // Find bed time (first "in bed" segment)
        let bedTime = sorted.first { $0.stage == .inBed }?.start
        
        // Find sleep onset (first asleep segment)
        let sleepOnset = sorted.first { $0.stage.isAsleep }?.start
        
        // Find first wake after sleep onset
        var firstWake: Date? = nil
        var foundSleep = false
        for segment in sorted {
            if segment.stage.isAsleep {
                foundSleep = true
            } else if foundSleep && segment.stage == .awake {
                firstWake = segment.start
                break
            }
        }
        
        // Find final wake (last segment end that's awake or last segment end)
        let finalWake = sorted.last?.end
        
        // Calculate TTFW (Time to First Wake)
        var ttfwMinutes: Double? = nil
        if let onset = sleepOnset, let wake = firstWake {
            ttfwMinutes = wake.timeIntervalSince(onset) / 60
        }
        
        // Calculate total sleep time (sum of all asleep segments)
        let totalSleepMinutes = sorted
            .filter { $0.stage.isAsleep }
            .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }
        
        // Count wake periods (WASO)
        let wakeCount = sorted.filter { $0.stage == .awake }.count
        
        // Get primary source
        let source = sorted.first?.source ?? "Unknown"
        
        return SleepNightSummary(
            date: nightStart,
            bedTime: bedTime,
            sleepOnset: sleepOnset,
            firstWake: firstWake,
            finalWake: finalWake,
            ttfwMinutes: ttfwMinutes,
            totalSleepMinutes: totalSleepMinutes,
            wakeCount: wakeCount,
            source: source
        )
    }
    
    // MARK: - TTFW Baseline Computation
    
    /// Fetch sleep history and compute TTFW baseline
    /// - Parameter days: Number of nights to analyze (14-30 recommended)
    func computeTTFWBaseline(days: Int = 14) async {
        guard isAvailable else {
            lastError = "HealthKit not available"
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Start from 'days' ago at 6 PM (typical sleep start)
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: now) else { return }
        
        do {
            let segments = try await fetchSleepSegments(from: startDate, to: now)
            
            // Group segments by night (6 PM to 6 PM next day)
            var nightSummaries: [SleepNightSummary] = []
            
            for dayOffset in 0..<days {
                guard let nightStart = calendar.date(byAdding: .day, value: -days + dayOffset, to: now),
                      let nightEnd = calendar.date(byAdding: .day, value: 1, to: nightStart) else { continue }
                
                // Get 6 PM of nightStart to 12 PM of next day
                var components = calendar.dateComponents([.year, .month, .day], from: nightStart)
                components.hour = 18
                guard let windowStart = calendar.date(from: components) else { continue }
                
                components = calendar.dateComponents([.year, .month, .day], from: nightEnd)
                components.hour = 12
                guard let windowEnd = calendar.date(from: components) else { continue }
                
                let nightSegments = segments.filter { $0.start >= windowStart && $0.start < windowEnd }
                
                if let summary = analyzeSleepNight(segments: nightSegments, nightStart: nightStart) {
                    nightSummaries.append(summary)
                }
            }
            
            sleepHistory = nightSummaries.sorted { $0.date > $1.date }
            
            // Compute average TTFW from nights that have data
            let validTTFWs = nightSummaries.compactMap { $0.ttfwMinutes }
            if !validTTFWs.isEmpty {
                ttfwBaseline = validTTFWs.reduce(0, +) / Double(validTTFWs.count)
                healthKitLog.info("TTFW baseline computed: \(self.ttfwBaseline ?? 0, privacy: .private) min from \(validTTFWs.count, privacy: .public) nights")
            } else {
                ttfwBaseline = nil
                healthKitLog.warning("No TTFW data found in \(days, privacy: .public) nights")
            }
            
        } catch {
            lastError = error.localizedDescription
            healthKitLog.error("Failed to fetch sleep data: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Same-Night Nudge
    
    /// Calculate suggested nudge based on TTFW baseline
    /// Returns suggested adjustment in minutes (-15 to +15)
    func calculateNudgeSuggestion() -> Int? {
        guard let baseline = ttfwBaseline else { return nil }
        
        // Target: wake up around baseline TTFW
        // If baseline TTFW is 180 min and target interval is 165 min,
        // suggest +15 min nudge
        let targetInterval = UserSettingsManager.shared.targetIntervalMinutes
        let diff = Int(baseline) - targetInterval
        
        // Clamp to ±15 min
        return max(-15, min(15, diff))
    }
    
    /// Check if tonight's sleep pattern suggests adjusting wake time
    /// - Parameters:
    ///   - dose1Time: When Dose 1 was taken
    ///   - currentTargetMinutes: Current target interval
    /// - Returns: Suggested new target, or nil if no change
    func sameNightNudge(dose1Time: Date, currentTargetMinutes: Int) async -> Int? {
        // For same-night nudge, we need recent sleep pattern
        // This is a simplified version - real implementation would analyze
        // tonight's sleep stages in real-time
        
        guard let baseline = ttfwBaseline else { return nil }
        
        // Only suggest if significant difference (>10 min)
        let diff = Int(baseline) - currentTargetMinutes
        if abs(diff) >= 10 {
            // Suggest moving toward baseline, clamped to valid options
            let validOptions = [165, 180, 195, 210, 225]
            let suggested = currentTargetMinutes + (diff > 0 ? 15 : -15)
            
            // Find closest valid option
            return validOptions.min(by: { abs($0 - suggested) < abs($1 - suggested) })
        }
        
        return nil
    }

    // MARK: - Timeline Integration
    
    /// Fetch sleep segments for timeline visualization
    /// - Parameters:
    ///   - from: Start date of the range
    ///   - to: End date of the range
    /// - Returns: Array of SleepSegment for timeline display
    func fetchSegmentsForTimeline(from start: Date, to end: Date) async throws -> [SleepSegment] {
        try await fetchSleepSegments(from: start, to: end)
    }

    func fetchNightBiometrics(from start: Date, to end: Date) async throws -> NightBiometricsSummary {
        let timeline = try await fetchTimelineBiometrics(from: start, to: end)
        return timeline.summary
    }

    func fetchTimelineBiometrics(from start: Date, to end: Date) async throws -> TimelineBiometrics {
        async let heartRateSamples = fetchQuantitySamples(type: .heartRate, from: start, to: end)
        async let respiratorySamples = fetchQuantitySamples(type: .respiratoryRate, from: start, to: end)
        async let hrvSamples = fetchQuantitySamples(type: .heartRateVariabilitySDNN, from: start, to: end)
        async let restingHeartRateSamples = fetchQuantitySamples(type: .restingHeartRate, from: start, to: end)

        let heartUnit = HKUnit.count().unitDivided(by: .minute())
        let respiratoryUnit = HKUnit.count().unitDivided(by: .minute())
        let hrvUnit = HKUnit.secondUnit(with: .milli)

        let heartSamples = try await heartRateSamples
        let respiratory = try await respiratorySamples
        let hrv = try await hrvSamples
        let resting = try await restingHeartRateSamples

        let heartRate = heartSamples.map {
            HeartRateDataPoint(timestamp: $0.startDate, bpm: $0.quantity.doubleValue(for: heartUnit))
        }
        let respiratoryRate = respiratory.map {
            RespiratoryRateDataPoint(timestamp: $0.startDate, breathsPerMinute: $0.quantity.doubleValue(for: respiratoryUnit))
        }
        let hrvData = hrv.map {
            HRVDataPoint(timestamp: $0.startDate, rmssd: $0.quantity.doubleValue(for: hrvUnit))
        }

        let summary = NightBiometricsSummary(
            averageHeartRate: averageQuantityValue(samples: heartSamples, unit: heartUnit),
            respiratoryRate: averageQuantityValue(samples: respiratory, unit: respiratoryUnit),
            hrvMs: averageQuantityValue(samples: hrv, unit: hrvUnit),
            restingHeartRate: averageQuantityValue(samples: resting, unit: heartUnit)
        )

        return TimelineBiometrics(
            heartRate: heartRate,
            respiratoryRate: respiratoryRate,
            hrv: hrvData,
            summary: summary
        )
    }
    
    /// Convert HealthKit sleep stage to timeline display stage
    static func mapToDisplayStage(_ hkStage: SleepStage) -> SleepDisplayStage {
        switch hkStage {
        case .awake: return .awake
        case .inBed: return .awake  // In-bed but not asleep shows as awake
        case .asleep, .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        }
    }
}

// MARK: - Display Stage Type (matches SleepStageTimeline)

/// Sleep stage enum for timeline display, matches SleepStageTimeline.SleepStage
enum SleepDisplayStage: String, CaseIterable {
    case awake = "Awake"
    case light = "Light"
    case core = "Core"
    case deep = "Deep"
    case rem = "REM"
}
