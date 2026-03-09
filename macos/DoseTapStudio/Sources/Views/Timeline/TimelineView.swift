import SwiftUI
import Charts

struct TimelineView: View {
    @ObservedObject var dataStore: DataStore
    @State private var selectedSessionID: InsightSession.ID?

    private var sessions: [InsightSession] {
        dataStore.insightSessions
    }

    private var selectedSession: InsightSession? {
        if let selectedSessionID {
            return sessions.first(where: { $0.id == selectedSessionID })
        }
        return sessions.first
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else if let selectedSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(for: selectedSession)
                        replaySummary(for: selectedSession)
                        replayChart(for: selectedSession)
                        replayFeed(for: selectedSession)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Timeline")
        .onAppear {
            ensureSelection()
        }
        .onChange(of: sessions.map(\.id)) { _ in
            ensureSelection()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No nights imported yet")
                .font(.headline)
            Text("Import a DoseTap Studio bundle to replay a night and inspect event timing around the Dose 2 window.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func header(for session: InsightSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Night Replay")
                        .font(.largeTitle.bold())
                    Text("Review event timing against the Dose 2 window and next-morning outcome.")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    selectAdjacentSession(from: session, direction: 1)
                } label: {
                    Label("Newer", systemImage: "chevron.left")
                }
                .disabled(index(of: session) == 0)

                Picker("Night", selection: Binding(
                    get: { selectedSessionID ?? session.id },
                    set: { selectedSessionID = $0 }
                )) {
                    ForEach(sessions) { item in
                        Text(item.sessionDate).tag(item.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)

                Button {
                    selectAdjacentSession(from: session, direction: -1)
                } label: {
                    Label("Older", systemImage: "chevron.right")
                }
                .disabled(index(of: session) == sessions.count - 1)

                Spacer()

                statusBadge(
                    text: session.dose2Skipped ? "Dose 2 skipped" : session.isLateDose2 ? "Late Dose 2" : session.isOnTimeDose2 ? "On time" : session.qualitySummary,
                    color: session.dose2Skipped ? .red : session.isLateDose2 ? .orange : session.isOnTimeDose2 ? .green : .secondary
                )
            }
        }
    }

    private func replaySummary(for session: InsightSession) -> some View {
        HStack(spacing: 12) {
            summaryCard("Dose 1", timeText(session.dose1Time), color: .blue)
            summaryCard("Dose 2", session.dose2Skipped ? "Skipped" : timeText(session.dose2Time), color: session.dose2Skipped ? .red : .green)
            summaryCard("Interval", session.intervalMinutes.map { "\($0)m" } ?? "—", color: session.isLateDose2 ? .orange : .primary)
            summaryCard("Morning", session.morningSleepQuality.map { "\($0)/5" } ?? "Missing", color: session.morningSleepQuality == nil ? .orange : .indigo)
            summaryCard("Readiness", session.morningReadiness.map { "\($0)/5" } ?? "—", color: .teal)
            summaryCard("Stress", session.preSleepStressLevel.map(String.init) ?? "—", color: .pink)
            Spacer()
        }
    }

    private func replayChart(for session: InsightSession) -> some View {
        let points = replayPoints(for: session)
        let domain = xDomain(for: points)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Relative Night Timeline")
                .font(.headline)

            Chart {
                RuleMark(x: .value("Dose 1", 0))
                    .foregroundStyle(.blue.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, spacing: 8) {
                        Text("Dose 1")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.blue)
                    }

                RuleMark(x: .value("Window Opens", 150))
                    .foregroundStyle(.green.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, spacing: 8) {
                        Text("150m")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                RuleMark(x: .value("Window Closes", 240))
                    .foregroundStyle(.orange.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, spacing: 8) {
                        Text("240m")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                ForEach(points) { point in
                    PointMark(
                        x: .value("Minutes From Dose 1", point.relativeMinutes),
                        y: .value("Lane", point.lane)
                    )
                    .foregroundStyle(point.color)
                    .symbolSize(point.isDoseAction ? 140 : 80)

                    RuleMark(
                        x: .value("Minutes From Dose 1", point.relativeMinutes)
                    )
                    .foregroundStyle(point.color.opacity(0.15))
                }
            }
            .chartXScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .stride(by: 30)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let minutes = value.as(Int.self) {
                            Text("\(minutes)m")
                        }
                    }
                }
            }
            .frame(height: 320)

            HStack(spacing: 12) {
                legendChip("Dose actions", color: .blue)
                legendChip("Window open", color: .green)
                legendChip("Window close", color: .orange)
                legendChip("Wake / symptoms", color: .purple)
                legendChip("Bathroom / misc", color: .secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func replayFeed(for session: InsightSession) -> some View {
        let points = replayPoints(for: session)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Replay Feed")
                .font(.headline)

            if let notes = session.preSleep?.notes, !notes.isEmpty {
                insightCallout(title: "Pre-sleep note", value: notes, color: .pink)
            }

            if let notes = session.morning?.notes, !notes.isEmpty {
                insightCallout(title: "Morning note", value: notes, color: .teal)
            }

            if points.isEmpty {
                Text("No replay events are available for this night.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(points) { point in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(point.color)
                            .frame(width: 10, height: 10)
                            .padding(.top, 5)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(point.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(point.offsetLabel)
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }

                            Text(point.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let details = point.details, !details.isEmpty {
                                Text(details)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if point.id != points.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func ensureSelection() {
        guard !sessions.isEmpty else {
            selectedSessionID = nil
            return
        }
        if let selectedSessionID,
           sessions.contains(where: { $0.id == selectedSessionID }) {
            return
        }
        selectedSessionID = sessions.first?.id
    }

    private func index(of session: InsightSession) -> Int {
        sessions.firstIndex(where: { $0.id == session.id }) ?? 0
    }

    private func selectAdjacentSession(from session: InsightSession, direction: Int) {
        let current = index(of: session)
        let next = max(0, min(sessions.count - 1, current + direction))
        selectedSessionID = sessions[next].id
    }

    private func replayPoints(for session: InsightSession) -> [TimelinePoint] {
        let anchor = session.dose1Time ?? session.startedAt ?? session.events.first?.timestamp
        guard let anchor else { return [] }

        return session.events
            .sorted { $0.timestamp < $1.timestamp }
            .map { event in
                let relativeMinutes = Int(event.timestamp.timeIntervalSince(anchor) / 60)
                return TimelinePoint(
                    id: event.id,
                    title: eventTitle(for: event),
                    lane: eventLane(for: event),
                    relativeMinutes: relativeMinutes,
                    timestamp: event.timestamp,
                    details: event.details,
                    color: eventColor(for: event),
                    isDoseAction: event.kind == .dose1 || event.kind == .dose2 || event.kind == .dose2Skipped
                )
            }
    }

    private func xDomain(for points: [TimelinePoint]) -> ClosedRange<Int> {
        let minimum = min(points.map(\.relativeMinutes).min() ?? 0, -30)
        let maximum = max(points.map(\.relativeMinutes).max() ?? 240, 270)
        return minimum...maximum
    }

    private func eventTitle(for event: InsightEvent) -> String {
        switch event.type {
        case .dose1_taken:
            return "Dose 1"
        case .dose2_taken:
            return "Dose 2"
        case .dose2_skipped:
            return "Dose 2 Skipped"
        case .dose2_snoozed, .snooze:
            return "Snooze"
        case .bathroom:
            return "Bathroom"
        case .lights_out:
            return "Lights Out"
        case .wake_final:
            return "Wake Final"
        case .undo:
            return "Undo"
        case .app_opened:
            return "App Opened"
        case .notification_received:
            return "Notification"
        }
    }

    private func eventLane(for event: InsightEvent) -> String {
        switch event.type {
        case .dose1_taken, .dose2_taken, .dose2_skipped, .dose2_snoozed, .snooze:
            return "Dose"
        case .bathroom:
            return "Bathroom"
        case .lights_out, .wake_final:
            return "Sleep"
        case .notification_received, .app_opened:
            return "System"
        case .undo:
            return "Corrections"
        }
    }

    private func eventColor(for event: InsightEvent) -> Color {
        switch event.kind {
        case .dose1:
            return .blue
        case .dose2:
            return .green
        case .dose2Skipped:
            return .red
        case .snooze:
            return .orange
        case .other:
            switch event.type {
            case .bathroom:
                return .purple
            case .lights_out, .wake_final:
                return .indigo
            default:
                return .secondary
            }
        }
    }

    private func summaryCard(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 120, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func legendChip(_ label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func insightCallout(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            Text(value)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct TimelinePoint: Identifiable {
    let id: UUID
    let title: String
    let lane: String
    let relativeMinutes: Int
    let timestamp: Date
    let details: String?
    let color: Color
    let isDoseAction: Bool

    var offsetLabel: String {
        if relativeMinutes == 0 {
            return "Dose 1"
        }
        if relativeMinutes > 0 {
            return "+\(relativeMinutes)m"
        }
        return "\(relativeMinutes)m"
    }
}

#Preview {
    TimelineView(dataStore: DataStore())
}
