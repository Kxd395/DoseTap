import SwiftUI
import Charts

struct AdherenceView: View {
    @ObservedObject var dataStore: DataStore

    private let analyzer = InsightAdherenceAnalyzer()

    private var sessions: [InsightSession] {
        Array(dataStore.insightSessions.prefix(60))
    }

    private var bucketSummary: AdherenceBucketSummary {
        analyzer.bucketSummary(sessions: sessions)
    }

    private var weekdayStats: [WeekdayAdherenceStat] {
        analyzer.weekdayStats(sessions: sessions)
    }

    private var stressSummary: StressAdherenceSummary {
        analyzer.stressSummary(sessions: sessions)
    }

    private var morningSummary: MorningOutcomeSummary {
        analyzer.morningOutcomeSummary(sessions: sessions)
    }

    private var averageInterval: Double? {
        let values = sessions.compactMap(\.intervalMinutes)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var flaggedSessions: [InsightSession] {
        sessions.filter { $0.isLateDose2 || $0.dose2Skipped || $0.isMissingOutcome }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Adherence Analysis")
                    .font(.largeTitle.bold())

                if sessions.isEmpty {
                    emptyState
                } else {
                    summaryRow
                    bucketChartCard
                    weekdayChartCard
                    factorCards
                    flaggedNightsCard
                }
            }
            .padding()
        }
        .navigationTitle("Adherence")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No adherence data available")
                .font(.headline)
            Text("Import a DoseTap Studio bundle to analyze on-time, late, skipped, and missing Dose 2 outcomes.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            summaryCard("On-Time Rate", String(format: "%.0f%%", bucketSummary.onTimeRate * 100), color: .green)
            summaryCard("Avg Interval", averageInterval.map { String(format: "%.0f min", $0) } ?? "—", color: .blue)
            summaryCard("Late", "\(bucketSummary.late)", color: .orange)
            summaryCard("Skipped", "\(bucketSummary.skipped)", color: .red)
            summaryCard("Missing", "\(bucketSummary.missingOutcome)", color: .purple)
            Spacer()
        }
    }

    private var bucketChartCard: some View {
        let buckets = [
            BucketPoint(label: "Early", count: bucketSummary.early, color: .yellow),
            BucketPoint(label: "On Time", count: bucketSummary.onTime, color: .green),
            BucketPoint(label: "Late", count: bucketSummary.late, color: .orange),
            BucketPoint(label: "Skipped", count: bucketSummary.skipped, color: .red),
            BucketPoint(label: "Missing", count: bucketSummary.missingOutcome, color: .purple)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            Text("Window Distribution")
                .font(.headline)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Bucket", bucket.label),
                    y: .value("Nights", bucket.count)
                )
                .foregroundStyle(bucket.color)
            }
            .frame(height: 240)

            Text("Early means Dose 2 was logged before the 150-minute window. Missing means Dose 1 exists but there is no Dose 2 outcome.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var weekdayChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekday On-Time Rate")
                .font(.headline)

            Chart(weekdayStats) { stat in
                BarMark(
                    x: .value("Weekday", stat.weekdayLabel),
                    y: .value("On-Time Rate", stat.onTimeRate * 100)
                )
                .foregroundStyle(.blue.gradient)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 240)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var factorCards: some View {
        HStack(alignment: .top, spacing: 12) {
            factorCard(
                title: "Stress Pattern",
                rows: [
                    factorRow("High stress nights", "\(stressSummary.highStressNightCount)"),
                    factorRow("High stress on-time", percentText(stressSummary.highStressOnTimeRate)),
                    factorRow("Low stress nights", "\(stressSummary.lowStressNightCount)"),
                    factorRow("Low stress on-time", percentText(stressSummary.lowStressOnTimeRate))
                ]
            )

            factorCard(
                title: "Morning Quality",
                rows: [
                    factorRow("On-time avg quality", qualityText(morningSummary.onTimeAverageSleepQuality)),
                    factorRow("Late avg quality", qualityText(morningSummary.lateAverageSleepQuality)),
                    factorRow("Skipped avg quality", qualityText(morningSummary.skippedAverageSleepQuality))
                ]
            )
        }
    }

    private var flaggedNightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Flagged Nights")
                .font(.headline)

            if flaggedSessions.isEmpty {
                Text("No late, skipped, or missing-outcome nights in the imported set.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(flaggedSessions.prefix(10)) { session in
                    HStack {
                        Text(session.sessionDate)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(flagText(for: session))
                            .foregroundColor(flagColor(for: session))
                    }
                    if session.id != flaggedSessions.prefix(10).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func summaryCard(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 135, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func factorCard(title: String, rows: [FactorRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ForEach(rows) { row in
                HStack {
                    Text(row.label)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(row.value)
                }
                .font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func factorRow(_ label: String, _ value: String) -> FactorRow {
        FactorRow(label: label, value: value)
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value * 100)
    }

    private func qualityText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f / 5", value)
    }

    private func flagText(for session: InsightSession) -> String {
        if session.dose2Skipped {
            return "Dose 2 skipped"
        }
        if session.isLateDose2 {
            return "Late Dose 2"
        }
        if session.isMissingOutcome {
            return "Missing outcome"
        }
        return session.qualitySummary
    }

    private func flagColor(for session: InsightSession) -> Color {
        if session.dose2Skipped {
            return .red
        }
        if session.isLateDose2 {
            return .orange
        }
        return .purple
    }
}

private struct BucketPoint: Identifiable {
    let label: String
    let count: Int
    let color: Color

    var id: String { label }
}

private struct FactorRow: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

#Preview {
    AdherenceView(dataStore: DataStore())
}
