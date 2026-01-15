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

// MARK: - Live Timeline View (wired to HealthKit)

/// Timeline view that fetches real sleep data from HealthKit
struct LiveSleepTimelineView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var settings = UserSettingsManager.shared
    @State private var sleepBands: [SleepStageBand] = []
    @State private var doseEvents: [TimelineEvent] = []
    @State private var sleepEvents: [StoredSleepEvent] = []
    @State private var sessionSummary: SessionSummaryData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    let nightDate: Date  // The night to display (defaults to last night)
    
    init(nightDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) {
        self.nightDate = nightDate
    }
    
    /// Convert a Date to the session key format (YYYY-MM-DD) used by SessionRepository
    private func sessionDateKey(for date: Date) -> String {
        let calendar = Calendar.current
        let rolloverHour = 18 // 6 PM rollover
        let hour = calendar.component(.hour, from: date)
        
        // If before rollover, use previous day
        let effectiveDate: Date
        if hour < rolloverHour {
            effectiveDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        } else {
            effectiveDate = date
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: effectiveDate)
    }
    
    private var timeRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        // Sleep window: 6 PM of nightDate to 12 PM next day
        var components = calendar.dateComponents([.year, .month, .day], from: nightDate)
        components.hour = 18
        let start = calendar.date(from: components) ?? nightDate
        
        let nextDay = calendar.date(byAdding: .day, value: 1, to: nightDate) ?? nightDate
        components = calendar.dateComponents([.year, .month, .day], from: nextDay)
        components.hour = 12
        let end = calendar.date(from: components) ?? nextDay
        
        return (start, end)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView("Loading sleep data...")
                    .padding()
            } else if !settings.healthKitEnabled {
                VStack(spacing: 12) {
                    Image(systemName: "heart.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Apple Health is disabled")
                        .font(.headline)
                    Text("Enable Apple Health in Settings to view your sleep timeline")
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
                                await loadSessionData()
                                await loadHealthKitData()
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
            } else if !healthKit.isAuthorized {
                VStack(spacing: 12) {
                    Image(systemName: "heart.text.square")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("HealthKit Access Required")
                        .font(.headline)
                    Text("Enable HealthKit in Settings to view your sleep timeline")
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
                                await loadSessionData()
                                await loadHealthKitData()
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
                            await loadSessionData()
                            await loadHealthKitData()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else if sleepBands.isEmpty && sessionSummary == nil && sleepEvents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No data for this night")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                // Session Summary Card (always show if we have session data)
                if let summary = sessionSummary {
                    TimelineSessionSummaryCard(summary: summary)
                }
                
                // Sleep timeline (if HealthKit data available)
                if !sleepBands.isEmpty {
                    SleepStageTimeline(
                        stages: sleepBands,
                        events: doseEvents,
                        startTime: timeRange.start,
                        endTime: timeRange.end
                    )
                    
                    StageSummaryCard(stages: sleepBands)
                }
                
                // Sleep events list (bathroom, water, etc.)
                if !sleepEvents.isEmpty {
                    TimelineSleepEventsCard(events: sleepEvents)
                }
            }
        }
        .task {
            healthKit.checkAuthorizationStatus()
            // Always load session data (doesn't require HealthKit)
            await loadSessionData()
            // Load HealthKit sleep data if available
            if settings.healthKitEnabled && healthKit.isAuthorized {
                await loadHealthKitData()
            }
        }
        .onChange(of: settings.healthKitEnabled) { _ in
            healthKit.checkAuthorizationStatus()
        }
    }
    
    /// Load session summary and logged events from SessionRepository
    private func loadSessionData() async {
        let sessionKey = sessionDateKey(for: nightDate)
        let repo = SessionRepository.shared
        
        // Fetch dose events for this session
        let doseEventsData = repo.fetchDoseEvents(forSessionDate: sessionKey)
        let dose1 = doseEventsData.first(where: { $0.eventType == "dose1_taken" })?.timestamp
        let dose2 = doseEventsData.first(where: { $0.eventType == "dose2_taken" })?.timestamp
        let skipped = doseEventsData.contains(where: { $0.eventType == "dose2_skipped" })
        let snoozes = doseEventsData.filter { $0.eventType == "snooze" }.count
        let wakeEvent = doseEventsData.first(where: { $0.eventType == "wake_final" })?.timestamp
        
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
        sleepEvents = repo.fetchSleepEvents(for: sessionKey)
    }
    
    /// Load HealthKit sleep stage data
    private func loadHealthKitData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let segments = try await healthKit.fetchSegmentsForTimeline(
                from: timeRange.start,
                to: timeRange.end
            )
            
            // Convert HealthKit segments to display bands
            sleepBands = segments.map { segment in
                let displayStage = HealthKitService.mapToDisplayStage(segment.stage)
                return SleepStageBand(
                    stage: mapDisplayStageToSleepStage(displayStage),
                    startTime: segment.start,
                    endTime: segment.end
                )
            }
        } catch {
            errorMessage = "Failed to load sleep data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Map from HealthKitService.SleepDisplayStage to SleepStageTimeline.SleepStage
    private func mapDisplayStageToSleepStage(_ displayStage: SleepDisplayStage) -> SleepStage {
        switch displayStage {
        case .awake: return .awake
        case .light: return .light
        case .core: return .core
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

/// Card showing session summary (doses, interval, etc.) for the timeline view
struct TimelineSessionSummaryCard: View {
    let summary: SessionSummaryData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundColor(.accentColor)
                Text("Session Summary")
                    .font(.headline)
                Spacer()
                if summary.checkInCompleted {
                    Label("Checked In", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Divider()
            
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
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
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
    
    private func icon(for eventType: String) -> String {
        Self.eventIcons[eventType.lowercased()] ?? "circle.fill"
    }
    
    private func color(for eventType: String) -> Color {
        Self.eventColors[eventType.lowercased()] ?? .gray
    }
    
    private func displayName(for eventType: String) -> String {
        eventType.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.accentColor)
                Text("Logged Events")
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
                            
                            if let notes = event.notes, !notes.isEmpty {
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
}
