import Foundation
import DoseCore

extension DashboardAnalyticsModel {
    func sleepMinutes(for night: DashboardNightAggregate) -> Double? {
        sleepSource == .appleHealth ? night.appleHealthSleepMinutes : night.whoopSleepMinutes
    }

    var sleepSampleCount: Int { populatedNights.compactMap { sleepMinutes(for: $0) }.count }
    var recordedPairCount: Int { dosingNights.compactMap(\.exactIntervalMinutes).count }
    var skippedDose2Count: Int { dosingNights.filter { $0.dose2Skipped && $0.dose2Time == nil }.count }
    var bathroomLogCount: Int { populatedNights.reduce(0) { $0 + $1.bathroomEventCount } }
    var extraDoseCount: Int { populatedNights.reduce(0) { $0 + $1.extraDoseCount } }

    func timingCount(_ timing: DoseCore.MedicationTiming) -> Int {
        dosingNights.filter { night in
            guard let first = night.dose1Time, let second = night.dose2Time else { return false }
            return DoseCore.MedicationTiming.classify(dose1: first, dose2: second) == timing
        }.count
    }

    func counts<T: Hashable>(for values: [T]) -> [T: Int] {
        var result: [T: Int] = [:]
        for value in values {
            result[value, default: 0] += 1
        }
        return result
    }

    func topKey<T: Hashable>(in counts: [T: Int]) -> T? {
        counts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return String(describing: lhs.key) > String(describing: rhs.key)
            }
            return lhs.value < rhs.value
        })?.key
    }

    func percentage<T>(
        matching values: [T],
        where predicate: (T) -> Bool
    ) -> Double? {
        guard !values.isEmpty else { return nil }
        let matches = values.filter(predicate).count
        return (Double(matches) / Double(values.count)) * 100
    }

    func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
