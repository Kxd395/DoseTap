import Foundation
import HealthKit

enum HKError: Error { case unavailable, unauthorized }

enum HealthAccess {
    static let store = HKHealthStore()

    // MARK: Types
    static let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    static let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
    static let respRateType  = HKObjectType.quantityType(forIdentifier: .respiratoryRate)!
    static let spo2Type      = HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!
    static let hrvType       = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!

    // MARK: Authorization
    static func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HKError.unavailable }
        let read: Set<HKObjectType> = [sleepType, heartRateType, respRateType, spo2Type, hrvType]
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: read) { ok, err in
                if let err = err { cont.resume(throwing: err); return }
                ok ? cont.resume(returning: ()) : cont.resume(throwing: HKError.unauthorized)
            }
        }
    }

    // MARK: Queries
    static func fetchSleepSamples(start: Date, end: Date) async throws -> [HKCategorySample] {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKCategorySample], Error>) in
            let q = HKSampleQuery(sampleType: sleepType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) {
                _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                cont.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            store.execute(q)
        }
    }

    static func averageQuantity(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async throws -> Double? {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Double?, Error>) in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .discreteAverage) { _, stats, err in
                if let err = err { cont.resume(throwing: err); return }
                if let q = stats?.averageQuantity() {
                    cont.resume(returning: q.doubleValue(for: unit))
                } else {
                    cont.resume(returning: nil)
                }
            }
            store.execute(q)
        }
    }

    // MARK: Baseline helpers
    static func latestTTFWBaseline(lastNDays: Int = 30) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -lastNDays, to: Date())!
        do {
            let sleeps = try await fetchSleepSamples(start: start, end: Date())
            // Group samples by night (calendar day of start)
            let groups = Dictionary(grouping: sleeps) { sample in
                let comps = Calendar.current.dateComponents([.year, .month, .day], from: sample.startDate)
                return DateComponents(year: comps.year, month: comps.month, day: comps.day)
            }
            var minutesArray: [Int] = []
            for (_, samples) in groups {
                if let minutes = NightAnalyzer.computeTTFWMinutes(for: samples), minutes >= 150, minutes <= 240 {
                    minutesArray.append(minutes)
                }
            }
            guard !minutesArray.isEmpty else { return nil }
            let sorted = minutesArray.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 0 ? (sorted[mid-1] + sorted[mid]) / 2 : sorted[mid]
        } catch {
            print("Health baseline error: \(error)")
            return nil
        }
    }

    // MARK: Background delivery (optional helpers)
    static func enableSleepBackgroundDelivery(_ enabled: Bool, frequency: HKUpdateFrequency = .hourly) {
        if enabled {
            store.enableBackgroundDelivery(for: sleepType, frequency: frequency) { success, error in
                if let error = error { print("HK background enable error: \(error)") }
                if !success { print("HK background enable failed") }
            }
        } else {
            store.disableBackgroundDelivery(for: sleepType) { success, error in
                if let error = error { print("HK background disable error: \(error)") }
                if !success { print("HK background disable failed") }
            }
        }
    }

    static func startSleepObserver(_ handler: @escaping () -> Void) {
        let q = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, _, error in
            if let error = error { print("HK observer error: \(error)") }
            handler()
        }
        store.execute(q)
    }
}
