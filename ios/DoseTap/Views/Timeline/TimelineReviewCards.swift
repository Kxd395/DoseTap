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

    private var hasAnySessionData: Bool {
        session.dose1Time != nil || session.dose2Time != nil || !events.isEmpty
    }

    private var doseWindow: (open: Date, close: Date)? {
        guard let dose1 = session.dose1Time else { return nil }
        return (dose1.addingTimeInterval(150 * 60), dose1.addingTimeInterval(240 * 60))
    }

    private var lightsOutTime: Date? {
        events
            .filter { normalizeStoredEventType($0.eventType) == "lights_out" }
            .map(\.timestamp)
            .min()
    }

    private var totalInBedText: String {
        guard
            let lightsOut = lightsOutTime,
            let wake = events
                .filter({ normalizeStoredEventType($0.eventType) == "wake_final" })
                .map(\.timestamp)
                .max()
        else {
            if !hasAnySessionData {
                return "No session data recorded."
            }
            return session.intervalMinutes.map { "Dose interval was \(TimeIntervalMath.formatMinutes($0))." }
                ?? "Session data captured."
        }
        let minutes = TimeIntervalMath.minutesBetween(start: lightsOut, end: wake)
        return "Top outcome: \(TimeIntervalMath.formatMinutes(minutes)) in bed."
    }

    private var frictionText: String {
        let disruptions = events.filter {
            let normalized = normalizeStoredEventType($0.eventType)
            return normalized == "bathroom" || normalized == "wake_temp" || normalized == "noise" || normalized == "pain"
        }
        if !hasAnySessionData {
            return "Biggest friction: insufficient data logged."
        }
        if disruptions.isEmpty {
            return "Biggest friction: no major disruptions logged."
        }
        return "Biggest friction: \(disruptions.count) overnight disruptions logged."
    }

    private var actions: [String] {
        var suggestions: [String] = []

        if !hasAnySessionData {
            return ["Log lights out, final wake, and only meaningful overnight disruptions tonight."]
        }

        if let window = doseWindow, let lightsOut = lightsOutTime {
            if lightsOut < window.open || lightsOut > window.close {
                suggestions.append("Aim lights-out inside the window (\(window.open.formatted(date: .omitted, time: .shortened))-\(window.close.formatted(date: .omitted, time: .shortened))).")
            }
        }

        if let interval = session.intervalMinutes, !(150...240).contains(interval) {
            suggestions.append("Move Dose 2 toward the 150-240 minute window after Dose 1.")
        }

        if !buildStoredEventDuplicateGroups(events: events).isEmpty {
            suggestions.append("Resolve duplicate event logs before relying on trend metrics.")
        }

        if suggestions.isEmpty {
            suggestions.append("Keep timing consistent tonight and log only meaningful wake events.")
        }

        return Array(suggestions.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach Summary")
                .font(.headline)
            Text(totalInBedText)
                .font(.subheadline)
            Text(frictionText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Divider()
            Text("Tonight's focus")
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
    let session: SessionSummary
    let events: [StoredSleepEvent]

    private var doseIntervalText: String {
        guard let minutes = session.intervalMinutes else {
            if session.dose1Time == nil {
                return "No doses"
            }
            if session.dose2Skipped {
                return "Skipped"
            }
            return "Pending"
        }
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h \(m)m"
    }

    private var doseIntervalColor: Color {
        guard let minutes = session.intervalMinutes else {
            return session.dose2Skipped ? .orange : .gray
        }
        if (150...240).contains(minutes) {
            return .green
        }
        return .red
    }

    private var isOnTime: Bool {
        guard let minutes = session.intervalMinutes else { return false }
        return (150...240).contains(minutes)
    }

    private var bathroomCount: Int {
        events.filter { normalizeStoredEventType($0.eventType) == "bathroom" }.count
    }

    private var estimatedWASO: String {
        let count = bathroomCount
        guard count > 0 else { return "0 min" }
        return "\(count * 5) min"
    }

    private var lightsOutTime: Date? {
        events
            .filter { normalizeStoredEventType($0.eventType) == "lights_out" }
            .map(\.timestamp)
            .min()
    }

    private var finalWakeTime: Date? {
        events
            .filter { normalizeStoredEventType($0.eventType) == "wake_final" }
            .map(\.timestamp)
            .max()
    }

    private var timeInBedText: String {
        guard let lightsOutTime, let finalWakeTime else { return "—" }
        let minutes = TimeIntervalMath.minutesBetween(start: lightsOutTime, end: finalWakeTime)
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h \(m)m"
    }

    private var disruptionCount: Int {
        events.filter {
            let name = normalizeStoredEventType($0.eventType)
            return name == "bathroom" || name == "wake_temp" || name == "noise" || name == "pain" || name == "anxiety"
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Key Metrics")
                    .font(.headline)
                Spacer()
                if session.dose1Time != nil {
                    HStack(spacing: 4) {
                        Image(systemName: isOnTime ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isOnTime ? .green : .orange)
                            .font(.caption)
                        Text(isOnTime ? "On-Time" : "Off-Window")
                            .font(.caption)
                            .foregroundColor(isOnTime ? .green : .orange)
                    }
                }
            }

            HStack(spacing: 12) {
                ReviewMetricTile(
                    title: "Dose Interval",
                    value: doseIntervalText,
                    icon: "clock.fill",
                    color: doseIntervalColor
                )

                ReviewMetricTile(
                    title: "Time in Bed",
                    value: timeInBedText,
                    icon: "bed.double.fill",
                    color: lightsOutTime != nil && finalWakeTime != nil ? .blue : .gray
                )
            }

            HStack(spacing: 12) {
                ReviewMetricTile(
                    title: "Disruptions",
                    value: disruptionCount == 0 ? "None" : "\(disruptionCount)",
                    icon: "exclamationmark.circle.fill",
                    color: disruptionCount == 0 ? .green : (disruptionCount <= 2 ? .yellow : .orange)
                )

                ReviewMetricTile(
                    title: "Est. WASO",
                    value: estimatedWASO,
                    icon: "moon.zzz.fill",
                    color: bathroomCount == 0 ? .green : .purple
                )
            }

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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
