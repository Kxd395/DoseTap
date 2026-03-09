import Foundation

struct AdherenceBucketSummary: Equatable {
    let early: Int
    let onTime: Int
    let late: Int
    let skipped: Int
    let missingOutcome: Int

    var total: Int {
        early + onTime + late + skipped + missingOutcome
    }

    var onTimeRate: Double {
        guard total > 0 else { return 0 }
        return Double(onTime) / Double(total)
    }
}

struct WeekdayAdherenceStat: Identifiable, Equatable {
    let weekdayIndex: Int
    let weekdayLabel: String
    let total: Int
    let onTime: Int

    var id: Int { weekdayIndex }

    var onTimeRate: Double {
        guard total > 0 else { return 0 }
        return Double(onTime) / Double(total)
    }
}

struct StressAdherenceSummary: Equatable {
    let highStressNightCount: Int
    let highStressOnTimeRate: Double?
    let lowStressNightCount: Int
    let lowStressOnTimeRate: Double?
}

struct MorningOutcomeSummary: Equatable {
    let onTimeAverageSleepQuality: Double?
    let lateAverageSleepQuality: Double?
    let skippedAverageSleepQuality: Double?
}

struct InsightAdherenceAnalyzer {
    func bucketSummary(sessions: [InsightSession]) -> AdherenceBucketSummary {
        var early = 0
        var onTime = 0
        var late = 0
        var skipped = 0
        var missingOutcome = 0

        for session in sessions {
            if session.dose2Skipped {
                skipped += 1
            } else if session.isOnTimeDose2 {
                onTime += 1
            } else if session.isLateDose2 {
                late += 1
            } else if session.intervalMinutes != nil {
                early += 1
            } else {
                missingOutcome += 1
            }
        }

        return AdherenceBucketSummary(
            early: early,
            onTime: onTime,
            late: late,
            skipped: skipped,
            missingOutcome: missingOutcome
        )
    }

    func weekdayStats(sessions: [InsightSession]) -> [WeekdayAdherenceStat] {
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let grouped = Dictionary(grouping: sessions) { session in
            weekdayIndex(for: session.sessionDate)
        }

        return labels.enumerated().map { index, label in
            let weekdaySessions = grouped[index + 1] ?? []
            let onTime = weekdaySessions.filter(\.isOnTimeDose2).count
            return WeekdayAdherenceStat(
                weekdayIndex: index + 1,
                weekdayLabel: label,
                total: weekdaySessions.count,
                onTime: onTime
            )
        }
    }

    func stressSummary(sessions: [InsightSession]) -> StressAdherenceSummary {
        let highStress = sessions.filter { ($0.preSleepStressLevel ?? 0) >= 4 }
        let lowStress = sessions.filter {
            guard let stress = $0.preSleepStressLevel else { return false }
            return stress <= 2
        }

        return StressAdherenceSummary(
            highStressNightCount: highStress.count,
            highStressOnTimeRate: onTimeRate(for: highStress),
            lowStressNightCount: lowStress.count,
            lowStressOnTimeRate: onTimeRate(for: lowStress)
        )
    }

    func morningOutcomeSummary(sessions: [InsightSession]) -> MorningOutcomeSummary {
        let onTime = sessions.filter(\.isOnTimeDose2).compactMap(\.morningSleepQuality)
        let late = sessions.filter(\.isLateDose2).compactMap(\.morningSleepQuality)
        let skipped = sessions.filter(\.dose2Skipped).compactMap(\.morningSleepQuality)

        return MorningOutcomeSummary(
            onTimeAverageSleepQuality: average(of: onTime),
            lateAverageSleepQuality: average(of: late),
            skippedAverageSleepQuality: average(of: skipped)
        )
    }

    private func weekdayIndex(for sessionDate: String) -> Int {
        guard let date = Self.dateFormatter.date(from: sessionDate) else {
            return 1
        }
        return Calendar.current.component(.weekday, from: date)
    }

    private func onTimeRate(for sessions: [InsightSession]) -> Double? {
        guard !sessions.isEmpty else { return nil }
        return Double(sessions.filter(\.isOnTimeDose2).count) / Double(sessions.count)
    }

    private func average(of values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
