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

struct DashboardChartValue: Identifiable {
    let name: String
    let value: Double
    let count: Int
    var id: String { name }
}

extension DashboardAnalyticsModel {
    var weekdayTimingValues: [DashboardChartValue] {
        let calendar = Calendar.current
        var buckets: [Int: [Bool]] = [:]
        for night in populatedNights {
            guard let onTime = night.onTimeDosing, let date = Self.keyFormatter.date(from: night.sessionDate) else { continue }
            buckets[calendar.component(.weekday, from: date), default: []].append(onTime)
        }
        return (0..<7).compactMap { offset in
            let day = (calendar.firstWeekday - 1 + offset) % 7 + 1
            guard let values = buckets[day], !values.isEmpty else { return nil }
            return DashboardChartValue(name: calendar.shortWeekdaySymbols[day - 1],
                value: Double(values.filter { $0 }.count) / Double(values.count) * 100, count: values.count)
        }
    }

    var screenSleepValues: [DashboardChartValue] {
        [false, true].compactMap { screens in
            let values = populatedNights.compactMap { night -> Double? in
                guard night.preSleepLog?.completionState == "complete",
                      let answer = night.preSleepLog?.answers?.screensInBed,
                      (answer != .none) == screens else { return nil }
                return sleepMinutes(for: night)
            }
            guard let value = average(values) else { return nil }
            return DashboardChartValue(name: screens ? "Screens" : "No screens", value: value, count: values.count)
        }
    }
}
