import SwiftUI
import DoseCore

struct ReviewHeaderCard: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    let hasMorningCheckIn: Bool

    private var titleText: String {
        let dateText = nightDate.formatted(date: .abbreviated, time: .omitted)
        if Calendar.current.isDateInYesterday(nightDate) {
            return "Last Night - \(dateText)"
        }
        return "Review - \(dateText)"
    }

    private var subtitleText: String {
        let start = session.dose1Time ?? events.first?.timestamp
        let end = events.last?.timestamp ?? session.dose2Time
        let status = hasMorningCheckIn ? "Session complete" : "Session recorded"

        if let start, let end {
            return "\(status) • \(start.formatted(date: .omitted, time: .shortened))-\(end.formatted(date: .omitted, time: .shortened))"
        }
        if session.dose1Time == nil, session.dose2Time == nil, events.isEmpty {
            return "No manual logs for this night"
        }
        return status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleText)
                .font(.headline)
            Text(subtitleText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct ReviewStickyHeaderBar: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    let hasMorningCheckIn: Bool
    let canGoToOlderNight: Bool
    let canGoToNewerNight: Bool
    let nightPositionText: String
    let onGoOlder: () -> Void
    let onGoNewer: () -> Void

    private var titleText: String {
        let dateText = nightDate.formatted(date: .abbreviated, time: .omitted)
        if Calendar.current.isDateInYesterday(nightDate) {
            return "Last Night - \(dateText)"
        }
        return "Review - \(dateText)"
    }

    private var subtitleText: String {
        let start = session.dose1Time ?? events.first?.timestamp
        let end = events.last?.timestamp ?? session.dose2Time
        let status = hasMorningCheckIn ? "Session complete" : "Session recorded"
        if let start, let end {
            return "\(status) • \(start.formatted(date: .omitted, time: .shortened))-\(end.formatted(date: .omitted, time: .shortened))"
        }
        if session.dose1Time == nil, session.dose2Time == nil, events.isEmpty {
            return "No manual logs for this night"
        }
        return status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: onGoOlder) {
                    Image(systemName: "chevron.left")
                        .font(.caption.bold())
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .disabled(!canGoToOlderNight)
                .opacity(canGoToOlderNight ? 1 : 0.35)
                .accessibilityLabel("Older night")

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.bold())
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text((canGoToOlderNight || canGoToNewerNight) ? nightPositionText : "Only night")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))

                Button(action: onGoNewer) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .disabled(!canGoToNewerNight)
                .opacity(canGoToNewerNight ? 1 : 0.35)
                .accessibilityLabel("Newer night")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct CoachSummaryCard: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let now: Date

    private var hasAnySessionData: Bool {
        session.dose1Time != nil || session.dose2Time != nil || session.dose2Skipped || !events.isEmpty
    }

    private var metrics: TimelineReviewMetrics {
        TimelineReviewMetrics(session: session, events: events, now: now)
    }

    private var totalInBedText: String {
        "Dose timing: \(metrics.statusText). Interval: \(metrics.intervalText)."
    }

    private var frictionText: String {
        "Disruption logs: \(metrics.disruptionText). Logs do not measure awake duration."
    }

    private var actions: [String] {
        var suggestions: [String] = []

        if !hasAnySessionData {
            return ["No manual session data recorded for this night."]
        }

        if !buildStoredEventDuplicateGroups(events: events).isEmpty {
            suggestions.append("Resolve duplicate event logs before relying on trend metrics.")
        }

        if suggestions.isEmpty {
            suggestions.append("Use History to review or correct recorded times. Missing logs remain unknown.")
        }

        return Array(suggestions.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recorded Summary")
                .font(.headline)
            Text(totalInBedText)
                .font(.subheadline)
            Text(frictionText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Divider()
            Text("Record review")
                .font(.subheadline.bold())
            ForEach(actions, id: \.self) { action in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(action)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct MergedNightTimelineItem: Identifiable {
    let id: String
    let title: String
    let time: Date
    let color: Color
}

struct MergedNightTimelineCard: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    var showFullViewLink: Bool = true
    var fullViewDestination: AnyView?
    var fullViewLabel: String = "Full view"
    var snapshotTimeline: ReviewSnapshotSleepTimeline?
    var allowLiveTimelineFallback: Bool = true

    private var mergedItems: [MergedNightTimelineItem] {
        var rows: [MergedNightTimelineItem] = []

        if let dose1 = session.dose1Time {
            rows.append(MergedNightTimelineItem(id: "dose1", title: "Dose 1", time: dose1, color: .blue))
            rows.append(MergedNightTimelineItem(id: "window_open", title: "Window Opens", time: dose1.addingTimeInterval(150 * 60), color: .orange))
            rows.append(MergedNightTimelineItem(id: "window_close", title: "Window Closes", time: dose1.addingTimeInterval(240 * 60), color: .red))
        }
        if let dose2 = session.dose2Time {
            rows.append(MergedNightTimelineItem(id: "dose2", title: "Dose 2", time: dose2, color: .green))
        }

        for event in events {
            rows.append(
                MergedNightTimelineItem(
                    id: event.id,
                    title: EventDisplayName.displayName(for: event.eventType),
                    time: event.timestamp,
                    color: Color(hex: event.colorHex ?? "#888888") ?? .gray
                )
            )
        }

        return rows.sorted(by: { $0.time < $1.time })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Night Timeline (Merged)")
                    .font(.headline)
                Spacer()
                if showFullViewLink {
                    NavigationLink(
                        destination: fullViewDestination ?? AnyView(SleepTimelineContainer())
                    ) {
                        Text(fullViewLabel)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            if let snapshotTimeline {
                SleepStageTimeline(
                    stages: snapshotTimeline.stages,
                    events: [],
                    startTime: snapshotTimeline.start,
                    endTime: snapshotTimeline.end
                )
                StageSummaryCard(stages: snapshotTimeline.stages)
            } else if allowLiveTimelineFallback {
                LiveSleepTimelineView(nightDate: nightDate)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Sleep timeline unavailable for this export.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }

            if !mergedItems.isEmpty {
                Divider()
                ForEach(mergedItems) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(item.title)
                            .font(.caption)
                        Spacer()
                        Text(item.time.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct ReviewKeyMetricsCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let now: Date

    var metrics: TimelineReviewMetrics {
        TimelineReviewMetrics(session: session, events: events, now: now)
    }

    private var metricLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private var doseIntervalColor: Color {
        switch metrics.timing {
        case .inWindow: return .blue
        case .early, .late, .invalid: return .orange
        case nil: return .secondary
        }
    }

    private var wakeToDose1Metric: WakeToDose1Metric? {
        let allEvents = SessionRepository.shared.fetchAllSleepEvents(limit: 500)
        return buildWakeToDose1Metric(
            dose1Time: session.dose1Time,
            events: allEvents + events
        )
    }

    private var wakeToDose1Text: String {
        wakeToDose1Metric?.formattedInterval ?? "Not logged"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Key Metrics")
                    .font(.headline)
                Spacer()
                Text(metrics.statusText)
                    .font(.caption)
                    .foregroundColor(doseIntervalColor)
                    .accessibilityLabel("Dose timing: \(metrics.statusText)")
            }

            metricLayout {
                ReviewMetricTile(
                    title: "Dose Interval",
                    value: metrics.intervalText,
                    icon: "clock.fill",
                    color: doseIntervalColor
                )

                ReviewMetricTile(
                    title: "Lights-out to Wake",
                    value: metrics.loggedRestText,
                    icon: "bed.double.fill",
                    color: .blue
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(wakeToDose1Metric == nil ? .gray : .orange)
                    .font(.caption)
                Text("Wake to Dose 1")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(wakeToDose1Text)
                    .font(.caption.bold())
                    .foregroundColor(wakeToDose1Metric == nil ? .secondary : .primary)
            }

            metricLayout {
                ReviewMetricTile(
                    title: "Disruption Logs",
                    value: metrics.disruptionText,
                    icon: "exclamationmark.circle.fill",
                    color: .purple
                )

                ReviewMetricTile(
                    title: "Bathroom Logs",
                    value: metrics.bathroomText,
                    icon: "list.bullet",
                    color: .purple
                )
            }

            Text("Log counts are not awake minutes. Lights-out to wake is logged elapsed time, not measured sleep.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if session.snoozeCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("\(session.snoozeCount) snooze\(session.snoozeCount == 1 ? "" : "s") used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct ReviewMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}


/// Read-only entry point for the exact night selected in Timeline Review.
struct TimelineDoseSleepCard: View {
    let sessionDate: String
    let events: [StoredSleepEvent]
    @StateObject private var model = TimelineDoseSleepModel()
    @ObservedObject private var repo = SessionRepository.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("healthkit_enabled") private var healthEnabled = false
    @State private var request: UUID?
    @State private var showWindow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dose and sleep timing").font(.headline)
            Text("Treatment night: \(sessionDate)").font(.subheadline)
            Text("Match Dose 2 to its Apple Health awakening using your saved, reviewed night window.")
                .font(.footnote).foregroundStyle(.secondary)
            Button(model.isLoading ? "Checking Apple Health…" : "Check dose and sleep timing") {
                model.invalidate()
                request = UUID()
            }
            .disabled(model.isLoading)
            .accessibilityIdentifier("timeline-dose-sleep-check")
            if model.isLoading { ProgressView() }
            if let result = model.result {
                TimelineDoseSleepResultView(result: result, events: events)
            }
            Button("Review night window") { invalidate(); showWindow = true }
                .accessibilityIdentifier("timeline-dose-sleep-window")
            Text("Checking does not save answers, record doses or change alarms. These checked results are not included in Capture review summary yet.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .sheet(isPresented: $showWindow) { NightOutcomeEditor(sessionDate: sessionDate) }
        .task(id: request) {
            guard request != nil else { return }
            await model.refresh(sessionDate: sessionDate) { await repo.reviewedNightSleep(sessionDate: $0) }
        }
        .onReceive(repo.sessionDidChange) { _ in invalidate() }
        .onChange(of: healthEnabled) { _ in invalidate() }
        .onChange(of: scenePhase) { if $0 != .active { invalidate() } }
        .onDisappear { invalidate() }
    }

    private func invalidate() { request = nil; model.invalidate() }
}

struct TimelineDoseSleepResultView: View {
    let result: ReviewedNightSleepResult
    let events: [StoredSleepEvent]
    @State private var showSources = false
    @State private var showLogs = false
    private var episode: TimelineDose2Episode? { TimelineDose2Episode(result: result) }
    private var samples: [SleepEvidenceSample] {
        episode?.samples ?? (result.evidence?.samples ?? []).sorted { $0.start < $1.start }
    }
    private func time(_ value: Date) -> String {
        let zone = TimeZone.current.abbreviation(for: value) ?? TimeZone.current.identifier
        return "\(value.formatted(date: .abbreviated, time: .standard)) (\(zone))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let episode {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Awakening around Dose 2").font(.headline)
                        .accessibilityIdentifier("timeline-dose2-episode")
                    Label("Awake begins: \(time(episode.start))", systemImage: "sun.max")
                    Label("Dose 2 taken: \(time(episode.dose))", systemImage: "pills")
                    if let returned = episode.returned {
                        Label("Sleep resumes: \(time(returned))", systemImage: "moon.zzz")
                    } else {
                        Text("Return to sleep is unresolved. See the explanation below.")
                    }
                    Text("Apple Health estimates; the dose is your recorded occurrence.")
                        .font(.footnote)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                let matching = episode.matchingEvents(events)
                if !matching.isEmpty {
                    expansionButton("Logs during this observed interval (\(matching.count))", expanded: $showLogs, id: "timeline-dose-sleep-logs")
                    if showLogs {
                        ForEach(matching.sorted { $0.timestamp < $1.timestamp }, id: \.id) { event in
                            Text("\(EventDisplayName.displayName(for: event.eventType)): \(time(event.timestamp))")
                        }
                        Text("Log times are context, not awake-duration measurements or proof of what caused waking. Alarm history is not included here.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            ReviewedNightCoverageView(result: result)
            if !samples.isEmpty {
                expansionButton(episode == nil ? "Inspect reviewed Health samples" : "Inspect awakening source samples", expanded: $showSources, id: "timeline-dose-sleep-sources")
                if showSources {
                    Text("Original sample bounds, including samples touching the transition. Display timezone: \(TimeZone.current.identifier).")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(sample.stage.rawValue.capitalized) · \(sample.origin.sourceName)").font(.subheadline.bold())
                                .accessibilityIdentifier("timeline-sleep-source-\(index)")
                            Text("\(time(sample.start)) → \(time(sample.end))")
                            if let device = sample.origin.deviceName ?? sample.origin.deviceModel { Text("Device: \(device)") }
                            if let bundle = sample.origin.bundleIdentifier { Text("Source app: \(bundle)") }
                            if let zone = sample.origin.timeZoneID { Text("Source timezone: \(zone)") }
                            if let version = sample.origin.sourceVersion { Text("Source version: \(version)") }
                        }
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        Divider()
                    }
                }
            }
        }
    }
    private func expansionButton(_ title: String, expanded: Binding<Bool>, id: String) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack {
                Text(title).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(id)
        .accessibilityValue(expanded.wrappedValue ? "Expanded" : "Collapsed")
    }

}
