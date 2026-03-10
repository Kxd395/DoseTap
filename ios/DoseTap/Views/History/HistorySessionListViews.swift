import SwiftUI
import DoseCore

struct RecentSessionsList: View {
    @State private var sessions: [SessionSummary] = []

    private let sessionRepo = SessionRepository.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)

            if sessions.isEmpty {
                Text("No recent sessions found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(sessions, id: \.sessionDate) { session in
                    SessionRow(session: session)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .onAppear { loadSessions() }
    }

    private func loadSessions() {
        sessions = sessionRepo.fetchRecentSessions(days: 7)
    }
}

struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.sessionDate)
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    if session.dose1Time != nil {
                        Label("D1", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    if session.dose2Time != nil {
                        Label("D2", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else if session.skipped {
                        Label("Skipped", systemImage: "forward.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    if session.eventCount > 0 {
                        Label("\(session.eventCount)", systemImage: "list.bullet")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            Spacer()
            if let dose1Time = session.dose1Time, let dose2Time = session.dose2Time {
                let interval = TimeIntervalMath.minutesBetween(start: dose1Time, end: dose2Time)
                Text(TimeIntervalMath.formatMinutes(interval))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct SessionSearchResultRow: View {
    let session: SessionSummary

    private var statusTag: (String, Color) {
        if session.dose2Skipped { return ("Skipped", .orange) }
        guard let interval = session.intervalMinutes else {
            if session.dose1Time != nil { return ("D1 Only", .yellow) }
            return ("No Doses", .gray)
        }
        if (150...165).contains(interval) { return ("On Time", .green) }
        if interval > 165 && interval <= 240 { return ("Late", .red) }
        return ("Out of Window", .red)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.sessionDate)
                    .font(.subheadline.bold())
                Spacer()
                Text(statusTag.0)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusTag.1.opacity(0.2)))
                    .foregroundColor(statusTag.1)
            }

            HStack(spacing: 12) {
                if let dose1Time = session.dose1Time {
                    Label(dose1Time.formatted(date: .omitted, time: .shortened), systemImage: "1.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                if let dose2Time = session.dose2Time {
                    Label(dose2Time.formatted(date: .omitted, time: .shortened), systemImage: "2.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                if let interval = session.intervalMinutes {
                    Label(TimeIntervalMath.formatMinutes(interval), systemImage: "timer")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }

            if !session.sleepEvents.isEmpty {
                let eventNames = Array(Set(session.sleepEvents.map(\.eventType))).sorted().prefix(5)
                HStack(spacing: 4) {
                    ForEach(eventNames, id: \.self) { name in
                        Text(name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(.systemGray5)))
                    }
                    if session.sleepEvents.count > 5 {
                        Text("+\(session.sleepEvents.count - 5)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}
