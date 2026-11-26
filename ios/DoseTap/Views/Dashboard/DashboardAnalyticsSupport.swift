import Foundation
import DoseCore

enum WakeOutcomeMetric: String, CaseIterable {
    case interval = "Dose interval"
    case totalSleep = "Total sleep"
    case sleepAfterDose2 = "Est. sleep after D2"
    case sleepiness = "Sleepiness 0–10"
}

extension DashboardAnalyticsModel {
    func wakeComparisonNights(day: FollowingDayKind?) -> [DashboardNightAggregate] {
        dosingNights.filter { day == nil || ($0.outcome?.dayType ?? .unknown) == day }
    }

    func wakeMetric(_ metric: WakeOutcomeMetric, kind: Dose2WakeKind, day: FollowingDayKind?) -> DiaryMetricSummary {
        DiaryMetricSummary(wakeComparisonNights(day: day).filter { $0.effectiveWakeMethod == kind }.map { night in
            switch metric {
            case .interval: return night.exactIntervalMinutes
            case .totalSleep: return sleepMinutes(for: night)
            case .sleepAfterDose2: return sleepSource == .appleHealth ? night.postDoseSleep?.asleepMinutes : nil
            case .sleepiness: return night.outcome?.sleepiness.map(Double.init)
            }
        })
    }
    func sleepMinutes(for night: DashboardNightAggregate) -> Double? {
        sleepSource == .appleHealth ? night.appleHealthSleepMinutes : night.whoopSleepMinutes
    }

    var unmatchedSelectedSleepCount: Int {
        populatedNights.filter { $0.unmatchedProviderEvidence != nil && sleepMinutes(for: $0) != nil }.count
    }
    var pairedSleepCount: Int {
        populatedNights.filter { $0.exactIntervalMinutes != nil && sleepMinutes(for: $0) != nil }.count
    }
    var automaticSleepMatchCount: Int {
        populatedNights.filter { $0.associationLabel(for: sleepSource).hasPrefix("Automatic time") && sleepMinutes(for: $0) != nil }.count
    }
    var sleepPairingSummary: String {
        "Dose pairs: \(recordedPairCount) · Sleep records: \(sleepSampleCount) · Paired: \(pairedSleepCount)"
    }
    var intervalSleepEmptyReason: String {
        if unmatchedSelectedSleepCount > 0 { return "Sleep records are available, but their session matches need review." }
        if recordedPairCount == 0 { return "No recorded two-dose intervals in this period. Confirmed single-dose nights are shown in Overview → Sleep vs spacing." }
        return "Dose intervals are available, but no \(sleepSource.rawValue) sleep is loaded for them. Refresh or check the selected sleep source."
    }

    var sleepSampleCount: Int { populatedNights.compactMap { sleepMinutes(for: $0) }.count }
    var recordedPairCount: Int { dosingNights.compactMap(\.exactIntervalMinutes).count }
    var invalidIntervalCount: Int {
        dosingNights.filter { $0.dose1Time != nil && $0.dose2Time != nil && $0.exactIntervalMinutes == nil }.count
    }
    var skippedDose2Count: Int { dosingNights.filter { $0.dose2Skipped && $0.dose2Time == nil }.count }
    var bathroomLogCount: Int { populatedNights.reduce(0) { $0 + $1.bathroomEventCount } }
    var extraDoseCount: Int { populatedNights.reduce(0) { $0 + $1.extraDoseCount } }

    func timingCount(_ timing: DoseCore.MedicationTiming) -> Int {
        dosingNights.filter { night in
            guard let first = night.dose1Time, let second = night.dose2Time,
                  night.exactIntervalMinutes != nil else { return false }
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
