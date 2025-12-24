import Foundation
import HealthKit

struct NightVitals {
    var avgHR: Double?      // bpm
    var avgRR: Double?      // breaths/min
    var avgSpO2: Double?    // 0.0–1.0
    var avgHRV: Double?     // ms
}

struct NightAnalyzer {
    static func computeTTFWMinutes(for samples: [HKCategorySample]) -> Int? {
        guard let bedtime = samples.min(by: { $0.startDate < $1.startDate })?.startDate else { return nil }
        let firstArousal = samples
            .sorted(by: { $0.startDate < $1.startDate })
            .first(where: { sample in
                guard sample.startDate > bedtime else { return false }
                if sample.value == HKCategoryValueSleepAnalysis.awake.rawValue { return true }
                if #available(iOS 16.0, *) {
                    return sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                } else {
                    return false
                }
            })
        guard let arousal = firstArousal else { return nil }
        let minutes = Int(arousal.startDate.timeIntervalSince(bedtime) / 60.0)
        return minutes
    }

    private static func averageQuantity(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async throws -> Double? {
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
            HKHealthStore().execute(q)
        }
    }

    static func fetchVitalsDuringSleep(start: Date, end: Date) async -> NightVitals {
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let rrType = HKObjectType.quantityType(forIdentifier: .respiratoryRate)!
        let sO2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!
        let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!

        async let hr = try? averageQuantity(type: hrType, unit: HKUnit(from: "count/min"), start: start, end: end)
        async let rr = try? averageQuantity(type: rrType, unit: HKUnit(from: "count/min"), start: start, end: end)
        async let sO2 = try? averageQuantity(type: sO2Type, unit: HKUnit.percent(), start: start, end: end)
        async let hrv = try? averageQuantity(type: hrvType, unit: HKUnit.secondUnit(with: .milli), start: start, end: end)
        let (avgHR, avgRR, avgSpO2, avgHRV) = await (hr, rr, sO2, hrv)
        return NightVitals(avgHR: avgHR ?? nil, avgRR: avgRR ?? nil, avgSpO2: avgSpO2 ?? nil, avgHRV: avgHRV ?? nil)
    }
}
