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
                // Stage breakdown
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
                
                // Total sleep time
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

// MARK: - Session Data for Timeline

/// Session summary data for display on timeline
struct SessionSummaryData {
    let sessionDate: String
    let dose1Time: Date?
    let dose2Time: Date?
    let doseInterval: TimeInterval?
    let snoozeCount: Int
    let dose2Skipped: Bool
    let wakeFinalTime: Date?
    let checkInCompleted: Bool
    
    var doseIntervalFormatted: String? {
        guard let interval = doseInterval else { return nil }
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
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

// MARK: - Live Timeline View (wired to HealthKit)

/// Timeline view that fetches real sleep data from HealthKit
struct LiveSleepTimelineView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var settings = UserSettingsManager.shared
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @State private var sleepBands: [SleepStageBand] = []
    @State private var doseEvents: [TimelineEvent] = []
    @State private var sleepEvents: [StoredSleepEvent] = []
    @State private var sessionSummary: SessionSummaryData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var displayRange: (start: Date, end: Date)?
    @State private var showRoutine = false
    @State private var lastSessionRefreshAt: Date?
    @State private var loadedSessionDataKey: String?
    @State private var loadedHealthKitSessionKey: String?
    
    let nightDate: Date?  // Optional: if nil, uses current session key from repository
    
    /// Initialize with a specific date or nil to use current session
    init(nightDate: Date? = nil) {
        self.nightDate = nightDate
    }
    
    /// The effective date key for data loading - uses current session if nightDate is nil
    private var effectiveSessionKey: String {
        if let date = nightDate {
            return sessionDateKey(for: date)
        }
        // Use current session key from repository (unified source of truth)
        return sessionRepo.currentSessionKey
    }
    
    /// Convert a Date to the session key format (YYYY-MM-DD) used by SessionRepository
    private func sessionDateKey(for date: Date) -> String {
        // `nightDate` comes from date-only UI selection and already represents the intended night key.
        let effectiveDate = Calendar.current.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: effectiveDate)
    }
    
    /// Convert session key to Date for HealthKit queries
    private func dateFromSessionKey(_ key: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key) ?? Date()
    }
    
    private var queryRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        // Use effective date from session key
        let baseDate = nightDate ?? dateFromSessionKey(effectiveSessionKey)
        
        // Sleep window: 6 PM of baseDate to 12 PM next day
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = 18
        let start = calendar.date(from: components) ?? baseDate
        
        let nextDay = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        components = calendar.dateComponents([.year, .month, .day], from: nextDay)
        components.hour = 12
        let end = calendar.date(from: components) ?? nextDay
        
        return (start, end)
    }

    private var displayRangeEffective: (start: Date, end: Date) {
        if let displayRange {
            return displayRange
        }
        return queryRange
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if let summaryData = nightSummaryData {
                NightSummaryCard(summary: summaryData)
            }

            freshnessStatusCard
            
            healthKitSection
            
            if !sleepEvents.isEmpty {
                TimelineSleepEventsCard(events: sleepEvents)
            }
            
            if let summary = sessionSummary {
                DisclosureGroup(isExpanded: $showRoutine) {
                    RoutineSummaryCard(summary: summary)
                } label: {
                    Text("Routine")
                        .font(.headline)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            }
            
            if nightSummaryData == nil && sleepBands.isEmpty && sleepEvents.isEmpty && sessionSummary == nil && !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No data for this night")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .task(id: effectiveSessionKey) {
            await refreshTimelineData(forceSessionReload: true, forceHealthKitReload: true)
        }
        .onChange(of: settings.healthKitEnabled) { isEnabled in
            Task {
                if isEnabled {
                    await refreshTimelineData(forceSessionReload: false, forceHealthKitReload: true)
                } else {
                    healthKit.checkAuthorizationStatus()
                    sleepBands = []
                    loadedHealthKitSessionKey = nil
                    errorMessage = nil
                    recomputeDisplayRange()
                }
            }
        }
        .onChange(of: healthKit.isAuthorized) { isAuthorized in
            guard settings.healthKitEnabled else { return }
            Task {
                if isAuthorized {
                    await loadHealthKitData(forceReload: true)
                } else {
                    sleepBands = []
                    loadedHealthKitSessionKey = nil
                    errorMessage = nil
                    recomputeDisplayRange()
                }
            }
        }
        .onReceive(sessionRepo.sessionDidChange) { _ in
            guard nightDate == nil || sessionRepo.currentSessionKey == effectiveSessionKey else { return }
            Task {
                await refreshTimelineData(forceSessionReload: true, forceHealthKitReload: false)
            }
        }
    }

    private var nightSummaryData: NightSummaryData? {
        let durations = sleepDurations
        let totalSleep = durations.sleep > 0 ? durations.sleep : nil
        let awake = durations.awake > 0 ? durations.awake : nil
        let lightsOut = lightsOutTime
        let finalWake = finalWakeTime
        let rangeText = displayRangeText
        
        if totalSleep != nil || awake != nil || lightsOut != nil || finalWake != nil {
            return NightSummaryData(
                totalSleep: totalSleep,
                awakeTime: awake,
                lightsOut: lightsOut,
                finalWake: finalWake,
                rangeText: rangeText
            )
        }
        return nil
    }

    private var sleepDurations: (sleep: TimeInterval, awake: TimeInterval) {
        var sleep: TimeInterval = 0
        var awake: TimeInterval = 0
        for band in sleepBands {
            let stage = band.stage == .core ? .light : band.stage
            if stage == .awake {
                awake += band.duration
            } else {
                sleep += band.duration
            }
        }
        return (sleep, awake)
    }

    private var lightsOutTime: Date? {
        let candidates = sleepEvents
            .filter { normalizedEventType($0.eventType) == "lights_out" }
            .map { $0.timestamp }
        return candidates.min()
    }

    private var finalWakeTime: Date? {
        if let wake = sessionSummary?.wakeFinalTime {
            return wake
        }
        let candidates = sleepEvents
            .filter {
                let type = normalizedEventType($0.eventType)
                return type == "wake_final" || type == "wake"
            }
            .map { $0.timestamp }
        if let latestEvent = candidates.max() {
            return latestEvent
        }
        return sleepBands.map { $0.endTime }.max()
    }

    private var displayRangeText: String? {
        let start = displayRangeEffective.start
        let end = displayRangeEffective.end
        guard end > start else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) → \(formatter.string(from: end))"
    }

    private var freshnessStatusCard: some View {
        HStack(spacing: 10) {
            freshnessBadge(
                title: "Session",
                timestamp: lastSessionRefreshAt,
                staleAfterMinutes: 5
            )
            freshnessBadge(
                title: "Health",
                timestamp: healthKit.lastTimelineSyncAt,
                staleAfterMinutes: 60,
                disabled: !settings.healthKitEnabled || !healthKit.isAuthorized
            )
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func freshnessBadge(
        title: String,
        timestamp: Date?,
        staleAfterMinutes: Int,
        disabled: Bool = false
    ) -> some View {
        let status = freshnessState(
            timestamp: timestamp,
            staleAfterMinutes: staleAfterMinutes,
            disabled: disabled
        )

        return HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text("\(title): \(status.label)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func freshnessState(
        timestamp: Date?,
        staleAfterMinutes: Int,
        disabled: Bool
    ) -> (label: String, color: Color) {
        if disabled {
            return ("Disabled", .secondary)
        }
        guard let timestamp else {
            return ("Not loaded", .orange)
        }

        let minutes = max(0, Int(Date().timeIntervalSince(timestamp) / 60))
        if minutes <= staleAfterMinutes {
            return ("\(minutes)m ago", .green)
        }
        return ("\(minutes)m ago", .orange)
    }

    @ViewBuilder
    private var healthKitSection: some View {
        if !settings.healthKitEnabled {
            healthKitPrompt(
                icon: "heart.slash",
                title: "Apple Health is disabled",
                message: "Enable Apple Health in Settings to view your sleep timeline"
            )
        } else if !healthKit.isAuthorized {
            healthKitPrompt(
                icon: "heart.text.square",
                title: "HealthKit Access Required",
                message: "Enable HealthKit in Settings to view your sleep timeline"
            )
        } else if isLoading {
            ProgressView("Loading sleep data...")
                .padding()
        } else if let error = errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Retry") {
                    Task {
                        await refreshTimelineData(forceSessionReload: true, forceHealthKitReload: true)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        } else if sleepBands.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No sleep data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
        } else {
            SleepStageTimeline(
                stages: sleepBands,
                events: doseEvents,
                startTime: displayRangeEffective.start,
                endTime: displayRangeEffective.end
            )
            
            StageSummaryCard(stages: sleepBands)
        }
    }

    private func healthKitPrompt(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    isLoading = true
                    settings.healthKitEnabled = true
                    let authorized = await healthKit.requestAuthorization()
                    isLoading = false
                    if authorized {
                        await refreshTimelineData(forceSessionReload: true, forceHealthKitReload: true)
                    }
                }
            } label: {
                HStack {
                    Text("Enable HealthKit")
                    if isLoading {
                        ProgressView()
                            .padding(.leading, 4)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
            
            if let error = healthKit.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func recomputeDisplayRange() {
        var startCandidates: [Date] = []
        var endCandidates: [Date] = []
        
        if let lightsOut = lightsOutTime {
            startCandidates.append(lightsOut)
        }
        if let earliestBand = sleepBands.map({ $0.startTime }).min() {
            startCandidates.append(earliestBand)
        }
        if let dose1 = sessionSummary?.dose1Time {
            startCandidates.append(dose1)
        }
        
        if let wake = finalWakeTime {
            endCandidates.append(wake)
        }
        if let latestBand = sleepBands.map({ $0.endTime }).max() {
            endCandidates.append(latestBand)
        }
        if let dose2 = sessionSummary?.dose2Time {
            endCandidates.append(dose2)
        }
        
        let start = startCandidates.min() ?? queryRange.start
        let end = endCandidates.max() ?? queryRange.end
        displayRange = end > start ? (start, end) : queryRange
    }

    private func normalizedEventType(_ eventType: String) -> String {
        let lower = eventType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "lightsout", "lights_out", "lights out", "lightsout_event", "lightsout_event_legacy":
            return "lights_out"
        case "wakefinal", "wake_final", "wake up", "wake":
            return "wake_final"
        default:
            return lower.replacingOccurrences(of: " ", with: "_")
        }
    }
    
    /// Load session summary and logged events from SessionRepository
    private func loadSessionData(forceReload: Bool = false) async {
        let sessionKey = effectiveSessionKey  // Use unified session key
        if !forceReload && loadedSessionDataKey == sessionKey {
            return
        }
        let repo = SessionRepository.shared
        
        // Fetch sleep events for this session (bathroom, wake, etc.)
        let sleepEventsData = repo.fetchSleepEvents(for: sessionKey)

        // Fetch dose events for this session
        let doseEventsData = repo.fetchDoseEvents(forSessionDate: sessionKey)
        let dose1 = doseEventsData.first(where: { $0.eventType == "dose1" })?.timestamp
        let dose2 = doseEventsData.first(where: { $0.eventType == "dose2" })?.timestamp
        let skipped = doseEventsData.contains(where: { $0.eventType == "dose2_skipped" })
        let snoozes = doseEventsData.filter { $0.eventType == "snooze" }.count
        let wakeEvent = sleepEventsData.first(where: {
            let type = $0.eventType.lowercased()
            return type == "wake_final" || type == "wakefinal" || type == "wake"
        })?.timestamp
        
        // Calculate dose interval if both doses taken
        var interval: TimeInterval? = nil
        if let d1 = dose1, let d2 = dose2 {
            interval = d2.timeIntervalSince(d1)
        }
        
        // Only create summary if we have any data
        if dose1 != nil || dose2 != nil || skipped || snoozes > 0 || wakeEvent != nil {
            sessionSummary = SessionSummaryData(
                sessionDate: sessionKey,
                dose1Time: dose1,
                dose2Time: dose2,
                doseInterval: interval,
                snoozeCount: snoozes,
                dose2Skipped: skipped,
                wakeFinalTime: wakeEvent,
                checkInCompleted: repo.fetchMorningCheckIn(for: sessionKey) != nil
            )
        } else {
            sessionSummary = nil
        }
        
        // Build dose timeline events for the visualization
        var timelineEvents: [TimelineEvent] = []
        if let d1 = dose1 {
            timelineEvents.append(TimelineEvent(name: "Dose 1", time: d1, color: .green, icon: "pill.fill"))
        }
        if let d2 = dose2 {
            timelineEvents.append(TimelineEvent(name: "Dose 2", time: d2, color: .green, icon: "pill.fill"))
        }
        if skipped, let skipEvent = doseEventsData.first(where: { $0.eventType == "dose2_skipped" }) {
            timelineEvents.append(TimelineEvent(name: "Skipped", time: skipEvent.timestamp, color: .orange, icon: "xmark.circle.fill"))
        }
        if let wake = wakeEvent {
            timelineEvents.append(TimelineEvent(name: "Wake", time: wake, color: .yellow, icon: "sun.max.fill"))
        }
        doseEvents = timelineEvents
        
        // Fetch sleep events (bathroom, water, etc.)
        sleepEvents = sleepEventsData
        loadedSessionDataKey = sessionKey
        lastSessionRefreshAt = Date()
        recomputeDisplayRange()
    }

    private func refreshTimelineData(forceSessionReload: Bool, forceHealthKitReload: Bool) async {
        healthKit.checkAuthorizationStatus()
        await loadSessionData(forceReload: forceSessionReload)

        if settings.healthKitEnabled && healthKit.isAuthorized {
            await loadHealthKitData(forceReload: forceHealthKitReload)
        } else {
            sleepBands = []
            loadedHealthKitSessionKey = nil
            errorMessage = nil
            recomputeDisplayRange()
        }
    }
    
    /// Load HealthKit sleep stage data
    private func loadHealthKitData(forceReload: Bool = false) async {
        guard settings.healthKitEnabled && healthKit.isAuthorized else {
            sleepBands = []
            loadedHealthKitSessionKey = nil
            errorMessage = nil
            return
        }

        let sessionKey = effectiveSessionKey
        if !forceReload && loadedHealthKitSessionKey == sessionKey {
            return
        }

        let range = queryRange
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let segments = try await healthKit.fetchSegmentsForTimeline(
                from: range.start,
                to: range.end
            )

            guard sessionKey == effectiveSessionKey else {
                return
            }
            
            // Convert HealthKit segments to display bands
            sleepBands = segments.map { segment in
                let displayStage = HealthKitService.mapToDisplayStage(segment.stage)
                return SleepStageBand(
                    stage: mapDisplayStageToSleepStage(displayStage),
                    startTime: segment.start,
                    endTime: segment.end
                )
            }
            loadedHealthKitSessionKey = sessionKey
            recomputeDisplayRange()
        } catch {
            guard sessionKey == effectiveSessionKey else {
                return
            }
            errorMessage = "Failed to load sleep data: \(error.localizedDescription)"
        }
    }
    
    /// Map from HealthKitService.SleepDisplayStage to SleepStageTimeline.SleepStage
    private func mapDisplayStageToSleepStage(_ displayStage: SleepDisplayStage) -> SleepStage {
        switch displayStage {
        case .awake: return .awake
        case .light: return .light
        case .core: return .light
        case .deep: return .deep
        case .rem: return .rem
        }
    }
}

// MARK: - Night Picker Timeline Container

/// Full sleep timeline with night picker for browsing history
struct SleepTimelineContainer: View {
    @State private var selectedNight: Date
    @State private var showDatePicker = false
    @State private var dragOffset: CGFloat = 0
    
    private let calendar = Calendar.current
    private let today = Date()
    
    // Earliest date we allow (90 days back)
    private var earliestDate: Date {
        calendar.date(byAdding: .day, value: -90, to: today) ?? today
    }
    
    // Latest date is yesterday (can't view tonight yet)
    private var latestDate: Date {
        calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }
    
    init() {
        // Default to last night
        _selectedNight = State(initialValue: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Date Navigation Header
            dateNavigationHeader
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
            
            Divider()
            
            // Timeline Content with swipe gesture
            ScrollView {
                LiveSleepTimelineView(nightDate: selectedNight)
                    .id(selectedNight) // Force refresh when date changes
                    .padding()
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let threshold: CGFloat = 50
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if value.translation.width > threshold {
                                // Swipe right → go to previous night
                                goToPreviousNight()
                            } else if value.translation.width < -threshold {
                                // Swipe left → go to next night
                                goToNextNight()
                            }
                            dragOffset = 0
                        }
                    }
            )
        }
        .navigationTitle("Sleep Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
    }
    
    // MARK: - Date Navigation Header
    
    private var dateNavigationHeader: some View {
        HStack(spacing: 16) {
            // Previous button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    goToPreviousNight()
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundColor(canGoBack ? .accentColor : .gray.opacity(0.3))
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Previous night")
            
            Spacer()
            
            // Date display - tap to pick
            Button {
                showDatePicker = true
            } label: {
                VStack(spacing: 2) {
                    Text("Night of")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Text(formattedDate)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    
                    // Relative date label
                    if let relativeLabel = relativeDateLabel {
                        Text(relativeLabel)
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .accessibilityLabel("Select date, currently \(formattedDate)")
            .accessibilityHint("Double tap to open date picker")
            
            Spacer()
            
            // Next button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    goToNextNight()
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(canGoForward ? .accentColor : .gray.opacity(0.3))
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next night")
        }
    }
    
    // MARK: - Date Picker Sheet
    
    private var datePickerSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                DatePicker(
                    "Select Night",
                    selection: $selectedNight,
                    in: earliestDate...latestDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                
                // Quick jump buttons
                VStack(spacing: 12) {
                    Text("Quick Jump")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        quickJumpButton(label: "Last Night", daysAgo: 1)
                        quickJumpButton(label: "1 Week Ago", daysAgo: 7)
                        quickJumpButton(label: "2 Weeks Ago", daysAgo: 14)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Select Night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showDatePicker = false
                    }
                }
            }
        }
    }
    
    private func quickJumpButton(label: String, daysAgo: Int) -> some View {
        Button {
            if let date = calendar.date(byAdding: .day, value: -daysAgo, to: today),
               date >= earliestDate {
                selectedNight = date
                showDatePicker = false
            }
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))
                .foregroundColor(.accentColor)
                .cornerRadius(8)
        }
    }
    
    // MARK: - Navigation Logic
    
    private var canGoBack: Bool {
        if let prev = calendar.date(byAdding: .day, value: -1, to: selectedNight) {
            return prev >= earliestDate
        }
        return false
    }
    
    private var canGoForward: Bool {
        if let next = calendar.date(byAdding: .day, value: 1, to: selectedNight) {
            return next <= latestDate
        }
        return false
    }
    
    private func goToPreviousNight() {
        if let prev = calendar.date(byAdding: .day, value: -1, to: selectedNight),
           prev >= earliestDate {
            selectedNight = prev
        }
    }
    
    private func goToNextNight() {
        if let next = calendar.date(byAdding: .day, value: 1, to: selectedNight),
           next <= latestDate {
            selectedNight = next
        }
    }
    
    // MARK: - Date Formatting
    
    private var formattedDate: String {
        selectedNight.formatted(date: .abbreviated, time: .omitted)
    }
    
    private var relativeDateLabel: String? {
        let daysAgo = calendar.dateComponents([.day], from: selectedNight, to: today).day ?? 0
        
        switch daysAgo {
        case 1: return "Last Night"
        case 2: return "2 nights ago"
        case 3...6: return "\(daysAgo) nights ago"
        case 7: return "1 week ago"
        case 8...13: return "\(daysAgo) nights ago"
        case 14: return "2 weeks ago"
        default: return nil
        }
    }
}

// MARK: - Timeline Session Summary Card

/// Card showing routine details (doses, interval, etc.) for the timeline view
struct RoutineSummaryCard: View {
    let summary: SessionSummaryData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Dose 1
            HStack {
                Label {
                    Text("Dose 1")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "1.circle.fill")
                        .foregroundColor(.green)
                }
                Spacer()
                if let d1 = summary.dose1Time {
                    Text(d1.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                } else {
                    Text("Not taken")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Dose 2
            HStack {
                Label {
                    Text("Dose 2")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "2.circle.fill")
                        .foregroundColor(summary.dose2Skipped ? .orange : .green)
                }
                Spacer()
                if summary.dose2Skipped {
                    Text("Skipped")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                } else if let d2 = summary.dose2Time {
                    Text(d2.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                } else {
                    Text("Not taken")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Interval (if both doses taken)
            if let interval = summary.doseIntervalFormatted {
                HStack {
                    Label {
                        Text("Interval")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .foregroundColor(.blue)
                    }
                    Spacer()
                    Text(interval)
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundColor(.primary)
                }
            }
            
            // Snoozes (if any)
            if summary.snoozeCount > 0 {
                HStack {
                    Label {
                        Text("Snoozes")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "bell.badge")
                            .foregroundColor(.purple)
                    }
                    Spacer()
                    Text("\(summary.snoozeCount)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            
            // Wake time (if logged)
            if let wake = summary.wakeFinalTime {
                HStack {
                    Label {
                        Text("Wake Up")
                        .font(.subheadline)
                    } icon: {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.yellow)
                    }
                    Spacer()
                    Text(wake.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            
            if summary.checkInCompleted {
                HStack {
                    Label {
                        Text("Check-in")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Text("Completed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Timeline Sleep Events Card

/// Card showing logged sleep events (bathroom, water, etc.) for timeline view
struct TimelineSleepEventsCard: View {
    let events: [StoredSleepEvent]

    private static let eventIcons: [String: String] = [
        "bathroom": "toilet.fill",
        "water": "drop.fill",
        "lights_out": "lightbulb.slash.fill",
        "wake_final": "sun.max.fill",
        "snack": "fork.knife",
        "discomfort": "exclamationmark.triangle.fill",
        "noise": "speaker.wave.2.fill",
        "temperature": "thermometer.medium",
        "partner": "person.2.fill",
        "pet": "pawprint.fill"
    ]
    
    private static let eventColors: [String: Color] = [
        "bathroom": .blue,
        "water": .cyan,
        "lights_out": .indigo,
        "wake_final": .yellow,
        "snack": .orange,
        "discomfort": .red,
        "noise": .purple,
        "temperature": .pink,
        "partner": .green,
        "pet": .brown
    ]

    private struct PainNotesPayload: Decodable {
        struct Location: Decodable {
            let region: String
            let side: String
        }
        
        let overallLevel: Int
        let locations: [Location]
        let primaryLocation: Location?
        let radiation: String?
        let painWokeUser: Bool
        let delta: String?
    }
    
    private func icon(for eventType: String) -> String {
        let key = normalizedType(eventType)
        if key.hasPrefix("pain.") { return "bandage.fill" }
        return Self.eventIcons[key] ?? "circle.fill"
    }
    
    private func color(for eventType: String) -> Color {
        let key = normalizedType(eventType)
        if key.hasPrefix("pain.") { return .red }
        return Self.eventColors[key] ?? .gray
    }
    
    private func displayName(for eventType: String) -> String {
        // Use centralized display name mapper
        EventDisplayName.displayName(for: eventType)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.accentColor)
                Text("Events")
                    .font(.headline)
                Spacer()
                Text("\(events.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }
            
            Divider()
            
            if events.isEmpty {
                Text("No events logged")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(events.sorted(by: { $0.timestamp < $1.timestamp })) { event in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: event.eventType))
                            .font(.system(size: 14))
                            .foregroundColor(color(for: event.eventType))
                            .frame(width: 24, height: 24)
                            .background(color(for: event.eventType).opacity(0.15))
                            .cornerRadius(6)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName(for: event.eventType))
                                .font(.subheadline)
                            
                            if let notes = formattedNotes(for: event) {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                        
                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func normalizedType(_ eventType: String) -> String {
        let lower = eventType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "lightsout", "lights_out", "lights out":
            return "lights_out"
        case "wakefinal", "wake_final", "wake", "wake up":
            return "wake_final"
        default:
            return lower.replacingOccurrences(of: " ", with: "_")
        }
    }

    private func formattedNotes(for event: StoredSleepEvent) -> String? {
        guard let notes = event.notes, !notes.isEmpty else { return nil }
        let type = normalizedType(event.eventType)
        if type == "pain.pre_sleep" || type == "pain.wake" || type == "pain" {
            return parsePainNotes(notes)
        }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return nil
        }
        return trimmed
    }

    private func parsePainNotes(_ notes: String) -> String? {
        guard let data = notes.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PainNotesPayload.self, from: data) else {
            return nil
        }
        
        var parts: [String] = ["\(payload.overallLevel)/10"]
        
        let locationText: String? = {
            if let primary = payload.primaryLocation {
                return painLocationText(primary)
            }
            if payload.locations.count == 1, let first = payload.locations.first {
                return painLocationText(first)
            }
            if payload.locations.count > 1 {
                return "\(payload.locations.count) areas"
            }
            return nil
        }()
        
        if let locationText {
            parts.append(locationText)
        }
        
        if let radiation = payload.radiation, radiation != "none" {
            let normalizedRadiation = radiation.replacingOccurrences(of: "_", with: " ")
            parts.append("radiating \(normalizedRadiation)")
        }
        
        if payload.painWokeUser {
            parts.append("woke you")
        }
        
        if let delta = payload.delta {
            let normalizedDelta = delta.replacingOccurrences(of: "_", with: " ")
            parts.append(normalizedDelta)
        }
        
        return parts.joined(separator: " – ")
    }
    
    private func painLocationText(_ location: PainNotesPayload.Location) -> String {
        let region = PainRegion(rawValue: location.region)
        let side = PainSide(rawValue: location.side)
        if let region, let side {
            let detail = PainLocationDetail(region: region, side: side)
            return detail.compactText
        }
        return "Pain"
    }
}
