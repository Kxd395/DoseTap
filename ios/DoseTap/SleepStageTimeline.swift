import SwiftUI

/// Timeline visualization for sleep stages and events
/// Shows color-coded bands for different sleep stages
struct SleepStageTimeline: View {
    let stages: [SleepStageBand]
    let events: [TimelineEvent]
    let startTime: Date
    let endTime: Date

    private let stageColors: [SleepStage: Color] = [
        .awake: .red.opacity(0.7),
        .light: .blue.opacity(0.4),
        .core: .blue.opacity(0.6),
        .deep: .indigo.opacity(0.8),
        .rem: .purple.opacity(0.7)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sleep Timeline")
                    .font(.headline)
                Spacer()
                Text("\(startTime.formatted(date: .omitted, time: .shortened)) - \(endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                let totalDuration = endTime.timeIntervalSince(startTime)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))

                    ForEach(stages) { stage in
                        let startOffset = stage.startTime.timeIntervalSince(startTime)
                        let duration = stage.endTime.timeIntervalSince(stage.startTime)
                        let xPosition = (startOffset / totalDuration) * geometry.size.width
                        let width = (duration / totalDuration) * geometry.size.width

                        RoundedRectangle(cornerRadius: 4)
                            .fill(stageColors[stage.stage] ?? .gray)
                            .frame(width: max(2, width), height: geometry.size.height - 8)
                            .offset(x: xPosition)
                            .padding(.vertical, 4)
                    }

                    ForEach(events) { event in
                        let offset = event.time.timeIntervalSince(startTime)
                        let xPosition = (offset / totalDuration) * geometry.size.width

                        Circle()
                            .fill(event.color)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                            )
                            .offset(x: xPosition - 4, y: geometry.size.height / 2 - 4)
                    }
                }
            }
            .frame(height: 40)

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

/// Timeline view that fetches real sleep data from HealthKit
struct LiveSleepTimelineView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var whoop = WHOOPService.shared
    @StateObject private var settings = UserSettingsManager.shared
    @StateObject private var sessionRepo = SessionRepository.shared
    @State private var sleepBands: [SleepStageBand] = []
    @State private var sleepEvents: [StoredSleepEvent] = []
    @State private var doseEvents: [TimelineEvent] = []
    @State private var heartRateData: [HeartRateDataPoint] = []
    @State private var respiratoryRateData: [RespiratoryRateDataPoint] = []
    @State private var hrvData: [HRVDataPoint] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var displayRange: (start: Date, end: Date)?
    @State private var showRoutine = false
    @State private var whoopTimelineStatus: String?
    @State private var stageSourceDescription = "Apple Health stages"
    @State private var biometricSourceDescription: String?

    let nightDate: Date

    init(nightDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) {
        self.nightDate = nightDate
    }

    private var timeRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: nightDate)
        components.hour = 18
        let start = calendar.date(from: components) ?? nightDate

        let nextDay = calendar.date(byAdding: .day, value: 1, to: nightDate) ?? nightDate
        components = calendar.dateComponents([.year, .month, .day], from: nextDay)
        components.hour = 12
        let end = calendar.date(from: components) ?? nextDay

        return (start, end)
    }

    private var queryRange: (start: Date, end: Date) {
        timeRange
    }

    private var displayRangeEffective: (start: Date, end: Date) {
        displayRange ?? queryRange
    }

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
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
                            await loadSessionData()
                            await loadHealthKitData()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else if sleepBands.isEmpty {
                noSleepDataState
            } else {
                EnhancedSleepTimeline(
                    stages: sleepBands,
                    events: doseEvents,
                    startTime: displayRangeEffective.start,
                    endTime: displayRangeEffective.end,
                    heartRateData: heartRateData,
                    respiratoryRateData: respiratoryRateData,
                    hrvData: hrvData
                )

                StageSummaryCard(stages: sleepBands)

                HStack(spacing: 8) {
                    Image(systemName: timelineSourceIconName)
                        .foregroundColor(timelineSourceColor)
                    Text(timelineSourceText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)

                if let whoopTimelineStatus, !hasWhoopOverlayData {
                    Text(whoopTimelineStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
        }
        .task(id: nightDate) {
            healthKit.checkAuthorizationStatus()
            await loadSessionData()
            await loadHealthKitData()
        }
        .onChange(of: settings.healthKitEnabled) { _ in
            healthKit.checkAuthorizationStatus()
        }
    }

    private var hasWhoopOverlayData: Bool {
        biometricSourceDescription?.contains("WHOOP") == true
    }

    private var timelineSourceText: String {
        if let biometricSourceDescription, !biometricSourceDescription.isEmpty {
            return "\(stageSourceDescription) + \(biometricSourceDescription)"
        }
        return stageSourceDescription
    }

    private var timelineSourceIconName: String {
        if stageSourceDescription.contains("WHOOP") || hasWhoopOverlayData {
            return "waveform.path.ecg"
        }
        return "heart.fill"
    }

    private var timelineSourceColor: Color {
        if stageSourceDescription.contains("WHOOP") || hasWhoopOverlayData {
            return .green
        }
        if stageSourceDescription.contains("Apple") {
            return .red
        }
        return .secondary
    }

    private var canUseAppleHealth: Bool {
        settings.healthKitEnabled && healthKit.isAvailable && healthKit.isAuthorized
    }

    private var canUseWhoop: Bool {
        WHOOPService.isEnabled && settings.whoopEnabled && whoop.isConnected
    }

    @ViewBuilder
    private var noSleepDataState: some View {
        if !canUseAppleHealth && !canUseWhoop {
            healthSourcePrompt
        } else {
            VStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No sleep data for this night")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let whoopTimelineStatus {
                    Text(whoopTimelineStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
    }

    private var healthSourcePrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Connect a sleep source")
                .font(.headline)
            Text("Enable Apple Health or connect WHOOP to load the nightly timeline and biometrics.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if healthKit.isAvailable {
                Button("Enable Apple Health") {
                    Task {
                        settings.healthKitEnabled = true
                        let authorized = await healthKit.requestAuthorization()
                        if authorized {
                            await loadSessionData()
                            await loadHealthKitData()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
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
            .map(\.timestamp)
        return candidates.min()
    }

    private var finalWakeTime: Date? {
        if sessionRepo.sessionDateString(for: nightDate) == sessionRepo.currentSessionDateString(),
           let wake = sessionRepo.wakeFinalTime {
            return wake
        }
        let candidates = sleepEvents
            .filter {
                let type = normalizedEventType($0.eventType)
                return type == "wake_final" || type == "wake"
            }
            .map(\.timestamp)
        if let latestEvent = candidates.max() {
            return latestEvent
        }
        return sleepBands.map(\.endTime).max()
    }

    private var displayRangeText: String? {
        let start = displayRangeEffective.start
        let end = displayRangeEffective.end
        guard end > start else { return nil }
        return "\(AppFormatters.shortTime.string(from: start)) → \(AppFormatters.shortTime.string(from: end))"
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
                title: "Apple Health Access Required",
                message: "Enable Apple Health in Settings to view your sleep timeline"
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
                        await loadSessionData()
                        await loadHealthKitData()
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func recomputeDisplayRange() {
        guard
            let earliestBand = sleepBands.map(\.startTime).min(),
            let latestBand = sleepBands.map(\.endTime).max()
        else {
            displayRange = queryRange
            return
        }

        var start = earliestBand
        var end = latestBand

        if let lightsOut = lightsOutTime {
            let lead = earliestBand.timeIntervalSince(lightsOut)
            if (0...(60 * 60)).contains(lead) {
                start = lightsOut
            }
        }

        if let wake = finalWakeTime {
            let tail = wake.timeIntervalSince(latestBand)
            if (0...(60 * 60)).contains(tail) {
                end = wake
            }
        }

        displayRange = end > start ? (start, end) : (earliestBand, latestBand)
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

    private func loadSessionData() async {
        let sessionDate = sessionRepo.sessionDateString(for: nightDate)
        let events = sessionRepo.fetchSleepEvents(for: sessionDate)
        sleepEvents = events

        var markers: [TimelineEvent] = []
        for event in events {
            let normalizedType = normalizedEventType(event.eventType)
            if normalizedType == "lights_out" || normalizedType == "wake_final" {
                markers.append(
                    TimelineEvent(
                        name: normalizedType == "lights_out" ? "Lights Out" : "Wake",
                        time: event.timestamp,
                        color: normalizedType == "lights_out" ? .purple : .orange,
                        icon: normalizedType == "lights_out" ? "light.max" : "sun.max.fill"
                    )
                )
            }
        }
        doseEvents = markers.sorted { $0.time < $1.time }
        recomputeDisplayRange()
    }

    private func loadHealthKitData() async {
        await loadSleepData()
        await loadBiometricData()
    }

    private func loadSleepData() async {
        isLoading = true
        errorMessage = nil

        var stageBands: [SleepStageBand] = []
        var stageStatus: String?

        if canUseAppleHealth {
            do {
                let segments = try await healthKit.fetchSegmentsForTimeline(
                    from: timeRange.start,
                    to: timeRange.end
                )
                let mappedBands = segments.map { segment in
                    let displayStage = HealthKitService.mapToDisplayStage(segment.stage)
                    return SleepStageBand(
                        stage: mapDisplayStageToSleepStage(displayStage),
                        startTime: segment.start,
                        endTime: segment.end
                    )
                }
                stageBands = primaryNightSleepBands(from: mappedBands)
                if !stageBands.isEmpty {
                    stageSourceDescription = "Apple Health stages"
                }
            } catch {
                stageStatus = "Apple Health data could not be loaded: \(error.localizedDescription)"
            }
        }

        if stageBands.isEmpty, canUseWhoop {
            do {
                let whoopBands = try await loadWhoopSleepBands()
                if !whoopBands.isEmpty {
                    stageBands = whoopBands
                    stageSourceDescription = "WHOOP stages"
                    stageStatus = nil
                }
            } catch {
                stageStatus = "WHOOP sleep stages could not be loaded: \(error.localizedDescription)"
            }
        }

        sleepBands = stageBands
        recomputeDisplayRange()
        if sleepBands.isEmpty {
            errorMessage = nil
            whoopTimelineStatus = stageStatus
        } else {
            errorMessage = nil
        }

        isLoading = false
    }

    private func loadBiometricData() async {
        heartRateData = []
        respiratoryRateData = []
        hrvData = []
        whoopTimelineStatus = nil
        biometricSourceDescription = nil

        var sources: [String] = []
        var statusMessages: [String] = []

        if canUseAppleHealth {
            do {
                let appleBiometrics = try await healthKit.fetchTimelineBiometrics(from: timeRange.start, to: timeRange.end)
                heartRateData = appleBiometrics.heartRate
                respiratoryRateData = appleBiometrics.respiratoryRate
                hrvData = appleBiometrics.hrv
                if appleBiometrics.hasAnyData {
                    sources.append("Apple Health biometrics")
                }
            } catch {
                statusMessages.append("Apple Health biometrics could not be loaded: \(error.localizedDescription)")
            }
        }

        if canUseWhoop {
            do {
                guard let matchedSleep = try await matchedWhoopSleep() else {
                    statusMessages.append("WHOOP is connected, but no matching sleep was found for this night.")
                    biometricSourceDescription = sources.isEmpty ? nil : sources.joined(separator: " + ")
                    whoopTimelineStatus = statusMessages.joined(separator: " ")
                    return
                }

                let biometrics = await whoop.extractBiometricData(from: matchedSleep)
                if !biometrics.heartRate.isEmpty {
                    heartRateData = biometrics.heartRate
                }
                if !biometrics.respiratoryRate.isEmpty {
                    respiratoryRateData = biometrics.respiratoryRate
                }
                if !biometrics.hrv.isEmpty {
                    hrvData = biometrics.hrv
                }
                if !biometrics.heartRate.isEmpty || !biometrics.respiratoryRate.isEmpty || !biometrics.hrv.isEmpty {
                    sources.append("WHOOP biometrics")
                } else {
                    statusMessages.append("WHOOP sleep matched this night, but no biometric overlays were returned.")
                }
            } catch {
                statusMessages.append("WHOOP data could not be loaded: \(error.localizedDescription)")
            }
        }

        biometricSourceDescription = sources.isEmpty ? nil : sources.joined(separator: " + ")
        if biometricSourceDescription == nil {
            whoopTimelineStatus = statusMessages.isEmpty ? "No biometric overlays available for this night." : statusMessages.joined(separator: " ")
        } else if !statusMessages.isEmpty {
            whoopTimelineStatus = statusMessages.joined(separator: " ")
        }
    }

    private func overlapDuration(for sleep: WHOOPSleep) -> TimeInterval {
        guard let start = sleep.start, let end = sleep.end, end > start else {
            return 0
        }

        let overlapStart = max(start, timeRange.start)
        let overlapEnd = min(end, timeRange.end)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }

    private func matchedWhoopSleep() async throws -> WHOOPSleep? {
        let sleeps = try await whoop.fetchSleepData(from: timeRange.start, to: timeRange.end)
        let candidates = sleeps.filter { $0.nap != true }
        guard let matchedSleep = candidates.max(by: { overlapDuration(for: $0) < overlapDuration(for: $1) }),
              overlapDuration(for: matchedSleep) > 0 else {
            return nil
        }
        return matchedSleep
    }

    private func loadWhoopSleepBands() async throws -> [SleepStageBand] {
        guard let matchedSleep = try await matchedWhoopSleep() else {
            return []
        }

        let stages = try await whoop.fetchSleepStages(sleepId: matchedSleep.id)
        let mapped = (stages.stages ?? [])
            .compactMap { $0.toSleepStageBand() }
            .sorted { $0.startTime < $1.startTime }
        return primaryNightSleepBands(from: mapped)
    }

    private func mapDisplayStageToSleepStage(_ displayStage: SleepDisplayStage) -> SleepStage {
        switch displayStage {
        case .awake:
            return .awake
        case .light:
            return .light
        case .core:
            return .light
        case .deep:
            return .deep
        case .rem:
            return .rem
        }
    }
}

/// Full sleep timeline with night picker for browsing history
struct SleepTimelineContainer: View {
    @State private var selectedNight: Date

    init() {
        _selectedNight = State(initialValue: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    if let previous = Calendar.current.date(byAdding: .day, value: -1, to: selectedNight) {
                        selectedNight = previous
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                .accessibilityLabel("Previous night")

                Spacer()

                VStack {
                    Text("Night of")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(selectedNight.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)
                }

                Spacer()

                Button {
                    if let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedNight),
                       next <= Date() {
                        selectedNight = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                }
                .disabled(Calendar.current.isDateInToday(selectedNight))
                .accessibilityLabel("Next night")
            }
            .padding(.horizontal)

            LiveSleepTimelineView(nightDate: selectedNight)
        }
        .navigationTitle("Sleep Timeline")
        .navigationBarTitleDisplayMode(.inline)
    }
}
