import SwiftUI

struct StageLegendItem: View {
    let stage: SleepStage
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(stage.displayName)
                .foregroundColor(.secondary)
        }
    }
}

struct StageSummaryCard: View {
    let stages: [SleepStageBand]

    private var stageDurations: [SleepStage: TimeInterval] {
        var durations: [SleepStage: TimeInterval] = [:]
        for stage in stages {
            let normalizedStage: SleepStage = stage.stage == .core ? .light : stage.stage
            durations[normalizedStage, default: 0] += stage.duration
        }
        return durations
    }

    private var totalSleepDuration: TimeInterval {
        stageDurations
            .filter { $0.key != .awake }
            .values
            .reduce(0, +)
    }

    private var totalTrackedDuration: TimeInterval {
        stageDurations.values.reduce(0, +)
    }

    private var stageOrder: [SleepStage] {
        [.awake, .light, .deep, .rem]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stages")
                .font(.headline)

            if stages.isEmpty {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundColor(.secondary)
                    Text("No sleep data available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(stageOrder, id: \.self) { stage in
                    if let duration = stageDurations[stage], duration > 0 {
                        StageBreakdownRow(
                            stage: stage,
                            duration: duration,
                            percentage: totalTrackedDuration > 0 ? duration / totalTrackedDuration : 0
                        )
                    }
                }

                Divider()

                HStack {
                    Text("Total Sleep")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(formatDuration(totalSleepDuration))
                        .font(.subheadline.bold())
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

struct StageBreakdownRow: View {
    let stage: SleepStage
    let duration: TimeInterval
    let percentage: Double

    private let stageColors: [SleepStage: Color] = [
        .awake: .red.opacity(0.7),
        .light: .blue.opacity(0.4),
        .core: .blue.opacity(0.6),
        .deep: .indigo.opacity(0.8),
        .rem: .purple.opacity(0.7)
    ]

    var body: some View {
        HStack {
            Image(systemName: stage.icon)
                .font(.caption)
                .foregroundColor(stageColors[stage])
                .frame(width: 20)

            Text(stage.displayName)
                .font(.subheadline)

            Spacer()

            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray4))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(stageColors[stage] ?? .gray)
                            .frame(width: geometry.size.width * percentage)
                    }
            }
            .frame(width: 60, height: 8)

            Text(formatDuration(duration))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct NightSummaryCard: View {
    let summary: NightSummaryData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Night Summary")
                    .font(.headline)
                Spacer()
                if let rangeText = summary.rangeText {
                    Text(rangeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 16) {
                SummaryMetric(title: "Total Sleep", value: formatDuration(summary.totalSleep))
                SummaryMetric(title: "Awake", value: formatDuration(summary.awakeTime))
            }

            HStack(spacing: 16) {
                SummaryMetric(title: "Lights Out", value: formatTime(summary.lightsOut))
                SummaryMetric(title: "Final Wake", value: formatTime(summary.finalWake))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func formatDuration(_ interval: TimeInterval?) -> String {
        guard let interval, interval > 0 else { return "—" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
struct SleepStageTimeline_Previews: PreviewProvider {
    static var previews: some View {
        let now = Date()
        let startTime = Calendar.current.date(byAdding: .hour, value: -8, to: now)!

        let sampleStages: [SleepStageBand] = [
            SleepStageBand(stage: .awake, startTime: startTime, endTime: startTime.addingTimeInterval(600)),
            SleepStageBand(stage: .light, startTime: startTime.addingTimeInterval(600), endTime: startTime.addingTimeInterval(3600)),
            SleepStageBand(stage: .deep, startTime: startTime.addingTimeInterval(3600), endTime: startTime.addingTimeInterval(7200)),
            SleepStageBand(stage: .rem, startTime: startTime.addingTimeInterval(7200), endTime: startTime.addingTimeInterval(10800)),
            SleepStageBand(stage: .light, startTime: startTime.addingTimeInterval(10800), endTime: startTime.addingTimeInterval(14400)),
            SleepStageBand(stage: .awake, startTime: startTime.addingTimeInterval(14400), endTime: startTime.addingTimeInterval(14700)),
            SleepStageBand(stage: .deep, startTime: startTime.addingTimeInterval(14700), endTime: startTime.addingTimeInterval(21600)),
            SleepStageBand(stage: .rem, startTime: startTime.addingTimeInterval(21600), endTime: now)
        ]

        let sampleEvents: [TimelineEvent] = [
            TimelineEvent(name: "Dose 1", time: startTime, color: .green),
            TimelineEvent(name: "Bathroom", time: startTime.addingTimeInterval(14500), color: .blue),
            TimelineEvent(name: "Dose 2", time: startTime.addingTimeInterval(10800), color: .green)
        ]

        VStack(spacing: 20) {
            SleepStageTimeline(
                stages: sampleStages,
                events: sampleEvents,
                startTime: startTime,
                endTime: now
            )

            StageSummaryCard(stages: sampleStages)
        }
        .padding()
    }
}
#endif
