import SwiftUI

struct RecommendationDetailView: View {
    @ObservedObject var dataStore: DataStore
    @State private var mode: InsightRecommendationMode = .restfulSleep
    @State private var filters = InsightFilterState()
    private let engine = InsightRecommendationEngine()

    private var filteredSessions: [InsightSession] {
        dataStore.insightSessions.filter { $0.matches(filters: filters) }
    }

    private var filteredCoverage: InsightCoverageSummary {
        InsightCoverageSummary(
            sessions: filteredSessions,
            validationReport: dataStore.validationReport
        )
    }

    private var recommendation: InsightRecommendationResult {
        engine.recommend(sessions: filteredSessions, mode: mode)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Timing Insight Detail")
                    .font(.largeTitle.bold())

                Text("Review historical timing patterns inside comparable cohorts before treating any band as clinically actionable.")
                    .foregroundColor(.secondary)

                filterBar

                evidenceSummaryCard
                RecommendationInsightsView(
                    sessions: filteredSessions,
                    coverage: filteredCoverage,
                    validationReport: dataStore.validationReport,
                    mode: $mode
                )

                matchedNightsCard
                exclusionReviewCard
                cohortRosterCard
            }
            .padding()
        }
        .navigationTitle("Timing Insight Detail")
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

    private var evidenceSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cohort Confidence")
                    .font(.headline)
                Spacer()
                InsightBadge(
                    text: recommendation.confidenceBucket.label,
                    tint: insightConfidenceColor(for: recommendation.confidenceBucket)
                )
            }

            HStack(spacing: 12) {
                metric("Visible", "\(filteredSessions.count)")
                metric("Trainable", "\(filteredCoverage.trainableNights)")
                metric("Excluded", "\(recommendation.nightsExcluded)")
                metric("Import Issues", "\(dataStore.validationReport.totalIssueCount)")
                metric("Readiness", filteredCoverage.readiness.rawValue)
                metric("Wearable", "\(filteredSessions.filter { $0.hrvMs != nil || $0.restingHeartRate != nil || $0.respiratoryRate != nil }.count)")
            }

            if recommendation.nightsExcluded > 0 || dataStore.validationReport.hasIssues {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Exclusion and Trust Callout")
                        .font(.subheadline.weight(.semibold))
                    Text(filteredCoverage.readinessSummary)
                        .foregroundColor(.secondary)
                    if recommendation.nightsExcluded > 0 {
                        Text("\(recommendation.nightsExcluded) comparable night(s) are excluded from training for missing outcome, reconciliation, timing exceptions, or mismatch flags.")
                            .foregroundColor(.orange)
                    }
                    if dataStore.validationReport.hasIssues {
                        Text("\(dataStore.validationReport.totalIssueCount) import issue(s) remain active across \(dataStore.validationReport.affectedSessionCount) night(s).")
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.08))
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var matchedNightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Matched-Night Detail")
                .font(.headline)

            if recommendation.matchedNights.isEmpty {
                Text("No trainable comparable nights are available for the current filters.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(recommendation.matchedNights.prefix(16))) { night in
                    HStack(spacing: 12) {
                        Text(night.sessionDate)
                            .frame(width: 96, alignment: .leading)
                        Text(night.bandLabel ?? "—")
                            .frame(width: 70, alignment: .leading)
                        Text(night.intervalMinutes.map { "\($0)m" } ?? "—")
                            .frame(width: 56, alignment: .leading)
                        Text(night.sleepQuality.map { "SQ \($0)" } ?? "SQ —")
                            .frame(width: 54, alignment: .leading)
                        Text(night.readiness.map { "RD \($0)" } ?? "RD —")
                            .frame(width: 54, alignment: .leading)
                        InsightBadge(text: night.nightType, tint: badgeTint(for: night.nightType))
                        InsightBadge(text: night.wakeType, tint: badgeTint(for: night.wakeType))
                        Spacer()
                        Text(night.score.map { String(format: "%.2f", $0) } ?? "—")
                            .foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .font(.caption)
                    if night.id != recommendation.matchedNights.prefix(16).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var exclusionReviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Excluded Comparable Nights")
                .font(.headline)

            if recommendation.excludedNights.isEmpty {
                Text("No comparable nights are currently excluded.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(recommendation.excludedNights.prefix(12))) { night in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(night.sessionDate)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            InsightBadge(
                                text: night.bandLabel ?? "No Band",
                                tint: night.trainable ? .green : .orange
                            )
                        }
                        Text(night.exclusionReasons.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if night.id != recommendation.excludedNights.prefix(12).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var cohortRosterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filtered Cohort Roster")
                .font(.headline)

            if filteredSessions.isEmpty {
                Text("No sessions match the current recommendation filters.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(filteredSessions.prefix(12))) { session in
                    HStack(alignment: .center, spacing: 12) {
                        Text(session.sessionDate)
                            .frame(width: 96, alignment: .leading)
                        Text(session.intervalMinutes.map { "\($0)m" } ?? "—")
                            .frame(width: 56, alignment: .leading)
                        InsightBadge(
                            text: session.nightTypeFilter.rawValue.replacingOccurrences(of: " Nights", with: ""),
                            tint: insightNightTypeColor(for: session)
                        )
                        InsightBadge(
                            text: session.nightWakeFilter.rawValue.replacingOccurrences(of: " Wake", with: ""),
                            tint: insightWakeTypeColor(for: session)
                        )
                        if session.countsTowardRecommendationTraining {
                            InsightBadge(text: "Trainable", tint: .green)
                        } else {
                            InsightBadge(text: "Excluded", tint: .orange)
                        }
                        Spacer()
                        Text(session.comparableCohortKey)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if session.id != filteredSessions.prefix(12).last?.id {
                        Divider()
                    }
                }
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

    private func badgeTint(for label: String) -> Color {
        let normalized = label.lowercased()
        if normalized.contains("work") {
            return .blue
        }
        if normalized.contains("off") {
            return .teal
        }
        if normalized.contains("transition") {
            return .orange
        }
        if normalized.contains("natural") {
            return .green
        }
        if normalized.contains("alarm") {
            return .orange
        }
        return .secondary
    }
}
