import SwiftUI
import Charts

struct CorrelationsView: View {
    @ObservedObject var dataStore: DataStore
    @State private var filters = InsightFilterState()
    private let analyzer = InsightCorrelationAnalyzer()

    private var filteredSessions: [InsightSession] {
        dataStore.insightSessions.filter { $0.matches(filters: filters) }
    }

    private var intervalQualitySessions: [InsightSession] {
        filteredSessions.filter { $0.intervalMinutes != nil && $0.morningSleepQuality != nil }
    }

    private var intervalReadinessSessions: [InsightSession] {
        filteredSessions.filter { $0.intervalMinutes != nil && $0.morningReadiness != nil }
    }

    private var intervalSleepSessions: [InsightSession] {
        filteredSessions.filter { $0.intervalMinutes != nil && ($0.totalSleepMinutes != nil || $0.sleepEfficiency != nil) }
    }

    private var filteredCoverage: InsightCoverageSummary {
        InsightCoverageSummary(
            sessions: filteredSessions,
            validationReport: dataStore.validationReport
        )
    }

    private var nightTypeSegments: [InsightCorrelationSegment] {
        analyzer.segmentsByNightType(sessions: filteredSessions)
    }

    private var wakeTypeSegments: [InsightCorrelationSegment] {
        analyzer.segmentsByWakeType(sessions: filteredSessions)
    }

    private var workSafetySegments: [InsightCorrelationSegment] {
        analyzer.segmentsByWorkSafetyContext(sessions: filteredSessions)
    }

    private var clinicalSegments: [InsightCorrelationSegment] {
        analyzer.segmentsByClinicalContext(sessions: filteredSessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Correlations")
                    .font(.largeTitle.bold())

                Text("Review interval relationships only within segmented work-pattern and wake-type cohorts.")
                    .foregroundColor(.secondary)

                filterBar
                summaryCard
                readinessCalloutCard
                segmentCard(title: "Work Pattern Segments", segments: nightTypeSegments)
                segmentCard(title: "Wake Pattern Segments", segments: wakeTypeSegments)
                segmentCard(title: "Work / Safety Context Segments", segments: workSafetySegments)
                segmentCard(title: "Clinical Context Segments", segments: clinicalSegments)
                intervalVsQualityCard
                intervalVsReadinessCard
                intervalVsSleepCard
            }
            .padding()
        }
        .navigationTitle("Correlations")
    }

    private var filterBar: some View {
        InsightFilterBar(
            filters: $filters,
            showsSearch: true,
            showsLateDose: false,
            showsSkipped: false,
            showsQualityIssues: true,
            showsTrainable: true
        )
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filtered Cohort")
                .font(.headline)

            HStack(spacing: 12) {
                metric("Visible", "\(filteredSessions.count)")
                metric("Trainable", "\(filteredSessions.filter(\.countsTowardRecommendationTraining).count)")
                metric("Flagged", "\(filteredSessions.filter { !$0.qualityFlags.isEmpty }.count)")
                metric("Work", "\(filteredSessions.filter { $0.nightTypeFilter == .work }.count)")
                metric("Off", "\(filteredSessions.filter { $0.nightTypeFilter == .off }.count)")
                metric("Natural", "\(filteredSessions.filter { $0.nightWakeFilter == .natural }.count)")
                metric("Alarm", "\(filteredSessions.filter { $0.nightWakeFilter == .alarm }.count)")
                metric("Work / Safety", "\(filteredSessions.filter(\.hasWorkSafetyContext).count)")
                metric("Clinical", "\(filteredSessions.filter(\.hasClinicalContext).count)")
            }

            Text("Charts below reflect the current segmentation. Keep unlike nights separated.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var readinessCalloutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chart Trust and Exclusions")
                    .font(.headline)
                Spacer()
                InsightBadge(
                    text: filteredCoverage.readiness.rawValue,
                    tint: readinessTint(filteredCoverage.readiness)
                )
            }

            HStack(spacing: 12) {
                metric("Trainable", "\(filteredCoverage.trainableNights)")
                metric("Excluded", "\(filteredCoverage.exclusionNights)")
                metric("Flagged", "\(filteredCoverage.flaggedNights)")
                metric("Import Issues", "\(dataStore.validationReport.totalIssueCount)")
            }

            Text(filteredCoverage.readinessSummary)
                .foregroundColor(.secondary)

            if filteredCoverage.exclusionNights > 0 || dataStore.validationReport.hasIssues {
                Text("Use chart patterns as observational only. Excluded nights are omitted from recommendation training, and import warnings still reduce confidence.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func segmentCard(title: String, segments: [InsightCorrelationSegment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if segments.isEmpty {
                Text("No segmented cohort rows are available for the current filters.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(segments) { segment in
                    HStack(spacing: 12) {
                        Text(segment.title)
                            .frame(width: 120, alignment: .leading)
                        metric("Nights", "\(segment.sessionCount)")
                        metric("Trainable", "\(segment.trainableCount)")
                        metric("Excluded", "\(segment.excludedCount)")
                        metric("Avg Interval", segment.averageIntervalMinutes.map { String(format: "%.0f min", $0) } ?? "—")
                        metric("Avg SQ", segment.averageSleepQuality.map { String(format: "%.1f", $0) } ?? "—")
                        metric("Avg RD", segment.averageReadiness.map { String(format: "%.1f", $0) } ?? "—")
                        metric("Drive", segment.averageDrivingConfidence.map { String(format: "%.1f/5", $0) } ?? "—")
                        metric("Sleepy", segment.averageDaytimeSleepiness.map { String(format: "%.1f/5", $0) } ?? "—")
                        metric("Avg Sleep", segment.averageTotalSleepMinutes.map(durationText) ?? "—")
                        metric("Efficiency", segment.averageSleepEfficiency.map { String(format: "%.1f%%", $0) } ?? "—")
                        Spacer()
                    }
                    .font(.caption)
                    if segment.id != segments.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var intervalVsQualityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dose Interval vs Morning Sleep Quality")
                .font(.headline)

            if intervalQualitySessions.isEmpty {
                Text("No interval + morning-quality pairs are available for the current filters.")
                    .foregroundColor(.secondary)
            } else {
                Chart(intervalQualitySessions) { session in
                    PointMark(
                        x: .value("Interval", session.intervalMinutes ?? 0),
                        y: .value("Sleep Quality", session.morningSleepQuality ?? 0)
                    )
                    .foregroundStyle(pointColor(for: session))
                    .symbolSize(session.countsTowardRecommendationTraining ? 110 : 70)
                }
                .chartXScale(domain: 150...240)
                .chartYScale(domain: 1...5)
                .frame(height: 260)

                Text("Color indicates work/off/transition pattern. Smaller points are excluded nights. Compare only against the segment rows above, not across unlike schedules.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var intervalVsReadinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dose Interval vs Next-Day Readiness")
                .font(.headline)

            if intervalReadinessSessions.isEmpty {
                Text("No interval + readiness pairs are available for the current filters.")
                    .foregroundColor(.secondary)
            } else {
                Chart(intervalReadinessSessions) { session in
                    PointMark(
                        x: .value("Interval", session.intervalMinutes ?? 0),
                        y: .value("Readiness", session.morningReadiness ?? 0)
                    )
                    .foregroundStyle(wakeColor(for: session))
                    .symbolSize(session.countsTowardRecommendationTraining ? 110 : 70)
                }
                .chartXScale(domain: 150...240)
                .chartYScale(domain: 1...5)
                .frame(height: 260)

                Text("Color indicates wake type. Segment by wake pattern before comparing readiness outcomes. Excluded nights still appear visually but do not count toward training.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var intervalVsSleepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dose Interval vs Sleep Duration / Efficiency")
                .font(.headline)

            if intervalSleepSessions.isEmpty {
                Text("No interval + wearable sleep metrics are available for the current filters.")
                    .foregroundColor(.secondary)
            } else {
                Chart(intervalSleepSessions) { session in
                    if let totalSleepMinutes = session.totalSleepMinutes {
                        PointMark(
                            x: .value("Interval", session.intervalMinutes ?? 0),
                            y: .value("Total Sleep Hours", totalSleepMinutes / 60.0)
                        )
                        .foregroundStyle(pointColor(for: session).opacity(0.8))
                    }

                    if let efficiency = session.sleepEfficiency {
                        PointMark(
                            x: .value("Interval", session.intervalMinutes ?? 0),
                            y: .value("Efficiency / 10", efficiency / 10.0)
                        )
                        .foregroundStyle(.indigo)
                        .symbol(.square)
                    }
                }
                .chartXScale(domain: 150...240)
                .frame(height: 260)

                Text("Round points show total sleep hours; square points show sleep efficiency divided by 10. Check segment-level counts before trusting any apparent cluster.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func readinessTint(_ readiness: InsightRecommendationReadiness) -> Color {
        switch readiness {
        case .ready:
            return .green
        case .caution:
            return .orange
        case .limited:
            return .red
        }
    }

    private func durationText(_ minutes: Double) -> String {
        let roundedMinutes = Int(minutes.rounded())
        return "\(roundedMinutes / 60)h \(roundedMinutes % 60)m"
    }

    private func pointColor(for session: InsightSession) -> Color {
        switch session.nightTypeFilter {
        case .work:
            return .blue
        case .off:
            return .teal
        case .transition:
            return .orange
        case .weekend:
            return .purple
        case .weekday, .all:
            return .secondary
        }
    }

    private func wakeColor(for session: InsightSession) -> Color {
        switch session.nightWakeFilter {
        case .natural:
            return .green
        case .alarm:
            return .orange
        case .mixed:
            return .purple
        case .unknown, .all:
            return .secondary
        }
    }
}
