import SwiftUI
import Charts

struct TrendsView: View {
    @ObservedObject var dataStore: DataStore

    private var recentSessions: [InsightSession] {
        Array(dataStore.insightSessions.prefix(30).reversed())
    }

    private var averageInterval: Int? {
        let values = recentSessions.compactMap(\.intervalMinutes)
        guard !values.isEmpty else { return nil }
        return Int(Double(values.reduce(0, +)) / Double(values.count))
    }

    private var lateCount: Int {
        recentSessions.filter(\.isLateDose2).count
    }

    private var skippedCount: Int {
        recentSessions.filter(\.dose2Skipped).count
    }

    private var issueCount: Int {
        recentSessions.filter { !$0.qualityFlags.isEmpty }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Trends")
                    .font(.largeTitle.bold())

                summaryRow

                if recentSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No trend data available")
                            .font(.headline)
                        Text("Import session exports to populate interval and event trends.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    intervalChartCard
                    eventChartCard
                    outlierCard
                }
            }
            .padding()
        }
        .navigationTitle("Trends")
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            trendCard(title: "30-Night Avg Interval", value: averageInterval.map { "\($0)m" } ?? "—", accent: .blue)
            trendCard(title: "Late Dose 2", value: "\(lateCount)", accent: .orange)
            trendCard(title: "Skipped", value: "\(skippedCount)", accent: .red)
            trendCard(title: "Quality Issues", value: "\(issueCount)", accent: .purple)
            Spacer()
        }
    }

    private var intervalChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dose Interval Trend")
                .font(.headline)

            Chart(recentSessions) { session in
                if let interval = session.intervalMinutes {
                    LineMark(
                        x: .value("Night", session.sessionDate),
                        y: .value("Interval", interval)
                    )
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("Night", session.sessionDate),
                        y: .value("Interval", interval)
                    )
                    .foregroundStyle(pointColor(for: session))
                }

                RuleMark(y: .value("Window Start", 150))
                    .foregroundStyle(.green.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                RuleMark(y: .value("Window End", 240))
                    .foregroundStyle(.orange.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .frame(height: 240)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var eventChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Night Event Load")
                .font(.headline)

            Chart(recentSessions) { session in
                BarMark(
                    x: .value("Night", session.sessionDate),
                    y: .value("Events", session.eventCount)
                )
                .foregroundStyle(barColor(for: session))
            }
            .frame(height: 220)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var outlierCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Outliers")
                .font(.headline)

            let outliers = recentSessions.filter { session in
                session.isLateDose2 || session.dose2Skipped || !session.qualityFlags.isEmpty
            }

            if outliers.isEmpty {
                Text("No late, skipped, or flagged nights in the most recent imported set.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(outliers.prefix(8)) { session in
                    HStack {
                        Text(session.sessionDate)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(outlierLabel(for: session))
                            .foregroundColor(outlierColor(for: session))
                    }
                    if session.id != outliers.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func trendCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(accent)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 150, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func pointColor(for session: InsightSession) -> Color {
        if session.dose2Skipped {
            return .red
        }
        if session.isLateDose2 {
            return .orange
        }
        return .green
    }

    private func barColor(for session: InsightSession) -> Color {
        if !session.qualityFlags.isEmpty {
            return .purple
        }
        if session.eventCount >= 6 {
            return .orange
        }
        return .blue
    }

    private func outlierLabel(for session: InsightSession) -> String {
        if session.dose2Skipped {
            return "Dose 2 skipped"
        }
        if session.isLateDose2 {
            return "Late Dose 2"
        }
        return session.qualitySummary
    }

    private func outlierColor(for session: InsightSession) -> Color {
        if session.dose2Skipped {
            return .red
        }
        if session.isLateDose2 {
            return .orange
        }
        return .purple
    }
}

#Preview {
    TrendsView(dataStore: DataStore())
}
