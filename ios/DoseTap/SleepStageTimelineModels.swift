import SwiftUI

enum SleepStage: String, CaseIterable, Codable {
    case awake = "Awake"
    case light = "Light"
    case core = "Core"
    case deep = "Deep"
    case rem = "REM"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .awake: return "eye.fill"
        case .light: return "moon.fill"
        case .core: return "moon.zzz"
        case .deep: return "moon.stars.fill"
        case .rem: return "sparkles"
        }
    }
}

struct SleepStageBand: Identifiable {
    let id: UUID
    let stage: SleepStage
    let startTime: Date
    let endTime: Date

    init(id: UUID = UUID(), stage: SleepStage, startTime: Date, endTime: Date) {
        self.id = id
        self.stage = stage
        self.startTime = startTime
        self.endTime = endTime
    }

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

private struct SleepBandCluster {
    let bands: [SleepStageBand]

    var sleepDuration: TimeInterval {
        bands.reduce(0) { partial, band in
            let normalized: SleepStage = band.stage == .core ? .light : band.stage
            return normalized == .awake ? partial : partial + band.duration
        }
    }

    var coverageDuration: TimeInterval {
        guard let start = bands.map(\.startTime).min(),
              let end = bands.map(\.endTime).max() else {
            return 0
        }
        return end.timeIntervalSince(start)
    }

    var firstSleepStart: Date? {
        bands.first { ($0.stage == .core ? .light : $0.stage) != .awake }?.startTime
    }

    var lastSleepEnd: Date? {
        bands.last { ($0.stage == .core ? .light : $0.stage) != .awake }?.endTime
    }
}

func primaryNightSleepBands(
    from bands: [SleepStageBand],
    maxGap: TimeInterval = 90 * 60,
    maxLeadingAwake: TimeInterval = 25 * 60,
    maxTrailingAwake: TimeInterval = 30 * 60,
    minimumSleepDuration: TimeInterval = 20 * 60
) -> [SleepStageBand] {
    let sorted = bands.sorted { $0.startTime < $1.startTime }
    guard !sorted.isEmpty else { return [] }

    let sleepOnly = sorted.filter { ($0.stage == .core ? .light : $0.stage) != .awake }
    guard !sleepOnly.isEmpty else { return [] }

    var sleepClusters: [[SleepStageBand]] = []
    var current: [SleepStageBand] = [sleepOnly[0]]

    for band in sleepOnly.dropFirst() {
        guard let last = current.last else {
            current = [band]
            continue
        }

        let gap = band.startTime.timeIntervalSince(last.endTime)
        if gap > maxGap {
            sleepClusters.append(current)
            current = [band]
        } else {
            current.append(band)
        }
    }
    sleepClusters.append(current)

    let clustered = sleepClusters.map(SleepBandCluster.init)
    guard let best = clustered.max(by: { lhs, rhs in
        if lhs.sleepDuration == rhs.sleepDuration {
            return lhs.coverageDuration < rhs.coverageDuration
        }
        return lhs.sleepDuration < rhs.sleepDuration
    }),
    best.sleepDuration >= minimumSleepDuration,
    let sleepStart = best.firstSleepStart,
    let sleepEnd = best.lastSleepEnd else {
        return []
    }

    let primaryCluster = sorted.filter { band in
        let normalized: SleepStage = band.stage == .core ? .light : band.stage
        if normalized != .awake {
            return band.endTime > sleepStart && band.startTime < sleepEnd
        }

        if band.endTime > sleepStart && band.startTime < sleepEnd {
            return true
        }
        if band.endTime <= sleepStart {
            return sleepStart.timeIntervalSince(band.endTime) <= maxLeadingAwake
                && band.duration <= maxLeadingAwake
        }
        if band.startTime >= sleepEnd {
            return band.startTime.timeIntervalSince(sleepEnd) <= maxTrailingAwake
                && band.duration <= maxTrailingAwake
        }
        return false
    }
    .sorted { $0.startTime < $1.startTime }

    let retainedSleepDuration = primaryCluster.reduce(0) { partial, band in
        let normalized: SleepStage = band.stage == .core ? .light : band.stage
        return normalized == .awake ? partial : partial + band.duration
    }

    return retainedSleepDuration >= minimumSleepDuration ? primaryCluster : []
}

struct TimelineEvent: Identifiable {
    let id: UUID
    let name: String
    let time: Date
    let color: Color
    let icon: String

    init(id: UUID = UUID(), name: String, time: Date, color: Color, icon: String = "circle.fill") {
        self.id = id
        self.name = name
        self.time = time
        self.color = color
        self.icon = icon
    }
}

/// Night summary data for Timeline report
struct NightSummaryData {
    let totalSleep: TimeInterval?
    let awakeTime: TimeInterval?
    let lightsOut: Date?
    let finalWake: Date?
    let rangeText: String?
}
