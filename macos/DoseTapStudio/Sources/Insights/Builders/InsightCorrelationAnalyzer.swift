import Foundation

struct InsightCorrelationSegment: Hashable, Sendable, Identifiable {
    let key: String
    let title: String
    let sessionCount: Int
    let trainableCount: Int
    let excludedCount: Int
    let averageIntervalMinutes: Double?
    let averageSleepQuality: Double?
    let averageReadiness: Double?
    let averageTotalSleepMinutes: Double?
    let averageSleepEfficiency: Double?
    let averageDrivingConfidence: Double?
    let averageDaytimeSleepiness: Double?

    var id: String { key }
}

struct InsightCorrelationAnalyzer {
    func segmentsByNightType(sessions: [InsightSession]) -> [InsightCorrelationSegment] {
        InsightNightTypeFilter.allCases
            .filter { $0 != .all }
            .compactMap { filter in
                makeSegment(
                    key: "night_type:\(filter.rawValue)",
                    title: filter.rawValue,
                    sessions: sessions.filter { $0.nightTypeFilter == filter }
                )
            }
    }

    func segmentsByWakeType(sessions: [InsightSession]) -> [InsightCorrelationSegment] {
        InsightWakeTypeFilter.allCases
            .filter { $0 != .all }
            .compactMap { filter in
                makeSegment(
                    key: "wake_type:\(filter.rawValue)",
                    title: filter.rawValue,
                    sessions: sessions.filter { $0.nightWakeFilter == filter }
                )
            }
    }

    func segmentsByWorkSafetyContext(sessions: [InsightSession]) -> [InsightCorrelationSegment] {
        [
            makeSegment(
                key: "work_safety:yes",
                title: "Work / Safety Context",
                sessions: sessions.filter(\.hasWorkSafetyContext)
            ),
            makeSegment(
                key: "work_safety:no",
                title: "No Work / Safety Context",
                sessions: sessions.filter { !$0.hasWorkSafetyContext }
            )
        ]
        .compactMap { $0 }
    }

    func segmentsByClinicalContext(sessions: [InsightSession]) -> [InsightCorrelationSegment] {
        [
            makeSegment(
                key: "clinical:yes",
                title: "Clinical Context",
                sessions: sessions.filter(\.hasClinicalContext)
            ),
            makeSegment(
                key: "clinical:no",
                title: "No Clinical Context",
                sessions: sessions.filter { !$0.hasClinicalContext }
            )
        ]
        .compactMap { $0 }
    }

    private func makeSegment(key: String, title: String, sessions: [InsightSession]) -> InsightCorrelationSegment? {
        guard !sessions.isEmpty else { return nil }

        return InsightCorrelationSegment(
            key: key,
            title: title,
            sessionCount: sessions.count,
            trainableCount: sessions.filter(\.countsTowardRecommendationTraining).count,
            excludedCount: sessions.filter { !$0.classification.exclusionReasons.isEmpty }.count,
            averageIntervalMinutes: average(sessions.compactMap(\.intervalMinutes).map(Double.init)),
            averageSleepQuality: average(sessions.compactMap(\.morningSleepQuality).map(Double.init)),
            averageReadiness: average(sessions.compactMap(\.morningReadiness).map(Double.init)),
            averageTotalSleepMinutes: average(sessions.compactMap(\.totalSleepMinutes)),
            averageSleepEfficiency: average(sessions.compactMap(\.sleepEfficiency)),
            averageDrivingConfidence: average(sessions.compactMap { $0.morning?.drivingConfidence }.map(Double.init)),
            averageDaytimeSleepiness: average(sessions.compactMap { $0.morning?.daytimeSleepiness }.map(Double.init))
        )
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
