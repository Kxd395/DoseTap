import Foundation
import HealthKit

enum HealthAccess {
    static let store = HKHealthStore()

    static func request() async throws {
        let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let typesToRead: Set<HKObjectType> = [sleep]
        try await store.requestAuthorization(toShare: [], read: typesToRead)
    }

    static func latestTTFWBaseline() async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        
        let sleepType = HKCategoryType(.sleepAnalysis)
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error = error {
                    print("Sleep query error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                var ttFWs: [Int] = []
                for sample in sleepSamples {
                    if sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue {
                        // Find the first awake sample after this sleep start
                        if let awakeSample = sleepSamples.first(where: { $0.startDate > sample.startDate && $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }) {
                            let minutes = Int(awakeSample.startDate.timeIntervalSince(sample.startDate) / 60)
                            if minutes >= 150 && minutes <= 240 {
                                ttFWs.append(minutes)
                            }
                        }
                    }
                }
                
                if ttFWs.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    let sorted = ttFWs.sorted()
                    let median = sorted.count % 2 == 0 ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
                    continuation.resume(returning: median)
                }
            }
            store.execute(query)
        }
    }
}
