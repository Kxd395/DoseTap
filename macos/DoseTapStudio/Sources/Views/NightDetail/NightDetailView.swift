import SwiftUI

struct NightDetailView: View {
    let session: InsightSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryCards
                eventListCard
            }
            .padding()
        }
        .navigationTitle(session.sessionDate)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.sessionDate)
                .font(.title.bold())
            Text(detailSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCards: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 140)),
                GridItem(.flexible(minimum: 140)),
                GridItem(.flexible(minimum: 140)),
                GridItem(.flexible(minimum: 140))
            ],
            spacing: 12
        ) {
            metricCard(title: "Dose 1", value: timeText(session.dose1Time), accent: .blue)
            metricCard(title: "Dose 2", value: session.dose2Skipped ? "Skipped" : timeText(session.dose2Time), accent: session.dose2Skipped ? .red : .green)
            metricCard(title: "Interval", value: session.intervalMinutes.map { "\($0)m" } ?? "—", accent: session.isLateDose2 ? .orange : .primary)
            metricCard(title: "Events", value: "\(session.eventCount)", accent: .purple)
            metricCard(title: "Snoozes", value: "\(session.snoozeCount)", accent: .orange)
            metricCard(title: "Bathroom", value: "\(session.bathroomCount)", accent: .cyan)
            metricCard(title: "Quality", value: session.qualityFlags.isEmpty ? "Clean" : "Flags", accent: session.qualityFlags.isEmpty ? .green : .orange)
            metricCard(title: "Completeness", value: "\(Int(session.completenessScore * 100))%", accent: .indigo)
        }
    }

    private var eventListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Night Events")
                .font(.headline)

            if session.events.isEmpty {
                Text("No events imported for this night.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(session.events) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(color(for: event))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(label(for: event))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let details = event.details, !details.isEmpty {
                                Text(details)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    if event.id != session.events.last?.id {
                        Divider()
                    }
                }
            }

            if !session.qualityFlags.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quality Flags")
                        .font(.headline)
                    ForEach(session.qualityFlags, id: \.self) { flag in
                        Label(flag, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var detailSubtitle: String {
        if session.dose2Skipped {
            return "Dose 2 was skipped"
        }
        if session.isLateDose2 {
            return "Late Dose 2 night"
        }
        if session.isOnTimeDose2 {
            return "On-time dosing night"
        }
        return session.qualitySummary
    }

    private func metricCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(accent)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func label(for event: InsightEvent) -> String {
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
            return "Notification Received"
        }
    }

    private func color(for event: InsightEvent) -> Color {
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
            return .secondary
        }
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    let sample = InsightSession(
        id: "2024-09-07",
        sessionDate: "2024-09-07",
        startedAt: Date(),
        endedAt: Date().addingTimeInterval(260 * 60),
        dose1Time: Date(),
        dose2Time: Date().addingTimeInterval(260 * 60),
        dose2Skipped: false,
        snoozeCount: 1,
        adherenceFlag: "late",
        sleepEfficiency: 84,
        whoopRecovery: 72,
        averageHeartRate: 64,
        notes: "Sample late night",
        events: [
            InsightEvent(id: UUID(), type: .dose1_taken, kind: .dose1, timestamp: Date(), details: nil),
            InsightEvent(id: UUID(), type: .bathroom, kind: .other, timestamp: Date().addingTimeInterval(90 * 60), details: "Brief wake"),
            InsightEvent(id: UUID(), type: .dose2_taken, kind: .dose2, timestamp: Date().addingTimeInterval(260 * 60), details: nil)
        ]
    )
    return NightDetailView(session: sample)
}
