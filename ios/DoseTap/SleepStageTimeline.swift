import SwiftUI

/// Timeline visualization for sleep stages and events
/// Shows color-coded bands for different sleep stages
struct SleepStageTimeline: View {
    let stages: [SleepStageBand]
    let events: [TimelineEvent]
    let startTime: Date
    let endTime: Date
    
    // Stage colors per SSOT
    private let stageColors: [SleepStage: Color] = [
        .awake: .red.opacity(0.7),
        .light: .blue.opacity(0.4),
        .core: .blue.opacity(0.6),
        .deep: .indigo.opacity(0.8),
        .rem: .purple.opacity(0.7)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with time range
            HStack {
                Text("Sleep Timeline")
                    .font(.headline)
                Spacer()
                Text("\(startTime.formatted(date: .omitted, time: .shortened)) - \(endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Stage bands visualization
            GeometryReader { geo in
                let totalDuration = endTime.timeIntervalSince(startTime)
                
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                    
                    // Stage bands
                    ForEach(stages) { stage in
                        let startOffset = stage.startTime.timeIntervalSince(startTime)
                        let duration = stage.endTime.timeIntervalSince(stage.startTime)
                        let xPos = (startOffset / totalDuration) * geo.size.width
                        let width = (duration / totalDuration) * geo.size.width
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stageColors[stage.stage] ?? .gray)
                            .frame(width: max(2, width), height: geo.size.height - 8)
                            .offset(x: xPos)
                            .padding(.vertical, 4)
                    }
                    
                    // Event markers
                    ForEach(events) { event in
                        let offset = event.time.timeIntervalSince(startTime)
                        let xPos = (offset / totalDuration) * geo.size.width
                        
                        Circle()
                            .fill(event.color)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                            )
                            .offset(x: xPos - 4, y: geo.size.height / 2 - 4)
                    }
                }
            }
            .frame(height: 40)
            
            // Legend
            HStack(spacing: 12) {
                StageLegendItem(stage: .awake, color: stageColors[.awake]!)
                StageLegendItem(stage: .light, color: stageColors[.light]!)
                StageLegendItem(stage: .deep, color: stageColors[.deep]!)
                StageLegendItem(stage: .rem, color: stageColors[.rem]!)
            }
            .font(.caption2)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Data Types

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

// MARK: - Legend Item

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

// MARK: - Compact Stage Summary

struct StageSummaryCard: View {
    let stages: [SleepStageBand]
    
    private var stageDurations: [SleepStage: TimeInterval] {
        var durations: [SleepStage: TimeInterval] = [:]
        for stage in stages {
            durations[stage.stage, default: 0] += stage.duration
        }
        return durations
    }
    
    private var totalDuration: TimeInterval {
        stageDurations.values.reduce(0, +)
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
                // Stage breakdown
                ForEach(SleepStage.allCases, id: \.self) { stage in
                    if let duration = stageDurations[stage], duration > 0 {
                        StageBreakdownRow(
                            stage: stage,
                            duration: duration,
                            percentage: totalDuration > 0 ? duration / totalDuration : 0
                        )
                    }
                }
                
                Divider()
                
                // Total sleep time
                HStack {
                    Text("Total Sleep")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(formatDuration(totalDuration))
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
            
            // Progress bar
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray4))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(stageColors[stage] ?? .gray)
                            .frame(width: geo.size.width * percentage)
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

// MARK: - Preview Provider

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
