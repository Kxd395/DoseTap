import Foundation
import HealthKit

/// HealthKit service for reading sleep data and computing TTFW baselines
/// TTFW = Time to First Wake (minutes from "asleep" to first "awake" segment)
///
/// Conforms to `HealthKitProviding` protocol for dependency injection.
/// Tests should use `NoOpHealthKitProvider` instead to avoid HealthKit entitlements.
@MainActor
final class HealthKitService: ObservableObject, HealthKitProviding {
    
    static let shared = HealthKitService()
    
    private let healthStore = HKHealthStore()
    
    // MARK: - Published State
    @Published var isAuthorized = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var lastError: String?
    @Published var ttfwBaseline: Double?  // Average TTFW in minutes
    @Published var sleepHistory: [SleepNightSummary] = []
    
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
    
    // MARK: - Authorization
    
    /// Check if HealthKit is available
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    /// Request HealthKit authorization for sleep data
    func requestAuthorization() async -> Bool {
        guard isAvailable else {
            lastError = "HealthKit is not available on this device"
            return false
        }
        
        let typesToRead: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis)
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            isAuthorized = true
            print("✅ HealthKitService: Authorization granted")
            return true
        } catch {
            lastError = error.localizedDescription
            print("❌ HealthKitService: Authorization failed: \(error)")
            return false
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() {
        let sleepType = HKCategoryType(.sleepAnalysis)
        authorizationStatus = healthStore.authorizationStatus(for: sleepType)
        isAuthorized = authorizationStatus == .sharingAuthorized
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
                print("✅ HealthKitService: TTFW baseline computed: \(ttfwBaseline ?? 0) min from \(validTTFWs.count) nights")
            } else {
                ttfwBaseline = nil
                print("⚠️ HealthKitService: No TTFW data found in \(days) nights")
            }
            
        } catch {
            lastError = error.localizedDescription
            print("❌ HealthKitService: Failed to fetch sleep data: \(error)")
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

// MARK: - HealthKit Extension for iOS 16+ Sleep Values

@available(iOS 16.0, *)
extension HKCategoryValueSleepAnalysis {
    static var asleepUnspecified: HKCategoryValueSleepAnalysis {
        HKCategoryValueSleepAnalysis(rawValue: 2) ?? .asleepCore
    }
}
