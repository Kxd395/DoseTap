import SwiftUI

struct RecommendationInsightsView: View {
    let sessions: [InsightSession]
    let coverage: InsightCoverageSummary
    let validationReport: ImportValidationReport
    @Binding var mode: InsightRecommendationMode

    private let engine = InsightRecommendationEngine()

    private var recommendation: InsightRecommendationResult {
        engine.recommend(sessions: Array(sessions.prefix(60)), mode: mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            readinessCallout
            recommendationSummary
            metricsRow
            topFactorsSection
            timingBandSection
            matchedNightsSection
            excludedNightsSection
            disclaimerSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var header: some View {
        HStack {
            Text("Timing Insight")
                .font(.headline)
            Spacer()
            Picker("Mode", selection: $mode) {
                ForEach(InsightRecommendationMode.allCases) { item in
                    Text(item.displayTitle).tag(item)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 240)
        }
    }

    @ViewBuilder
    private var readinessCallout: some View {
        if coverage.readiness != .ready || validationReport.hasIssues {
            VStack(alignment: .leading, spacing: 6) {
                Text("Evidence Readiness")
                    .font(.subheadline.weight(.semibold))
                Text(coverage.readinessSummary)
                    .foregroundColor(.secondary)
                if validationReport.hasIssues {
                    Text("\(validationReport.totalIssueCount) import issue(s) are still active across \(validationReport.affectedSessionCount) night(s).")
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.08))
            .cornerRadius(10)
        }
    }

    private var recommendationSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let band = recommendation.recommendedBand {
                Text("\(band.label) min")
                    .font(.title2.bold())
                    .foregroundColor(color(for: recommendation.confidenceBucket))
            } else {
                Text("Not enough evidence")
                    .font(.title3.bold())
                    .foregroundColor(.orange)
            }

            Text(recommendation.summary)
                .foregroundColor(.secondary)

            Text(recommendation.cohortDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(mode.transparencySummary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 16) {
            metric(title: "Cohort", value: recommendation.cohortKey ?? "—")
            metric(title: "Confidence", value: recommendation.confidenceBucket.label)
            metric(title: "Used", value: "\(recommendation.nightsUsed)")
            metric(title: "Excluded", value: "\(recommendation.nightsExcluded)")
        }
    }

    @ViewBuilder
    private var topFactorsSection: some View {
        if !recommendation.topFactors.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Top Factors")
                    .font(.subheadline.weight(.semibold))

                ForEach(recommendation.topFactors, id: \.self) { factor in
                    Text("• \(factor)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var timingBandSection: some View {
        if !recommendation.candidates.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Timing Bands")
                    .font(.subheadline.weight(.semibold))

                ForEach(recommendation.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(candidate.band.label)
                                .font(.subheadline.monospacedDigit())
                            Spacer()
                            Text("\(candidate.sampleCount) nights")
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f", candidate.averageScore))
                                .foregroundColor(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }

                        HStack(spacing: 12) {
                            compactMetric("SQ", candidate.averageSleepQuality.map { String(format: "%.1f", $0) } ?? "—")
                            compactMetric("RD", candidate.averageReadiness.map { String(format: "%.1f", $0) } ?? "—")
                            compactMetric("HRV", candidate.averageHRV.map { String(format: "%.1f ms", $0) } ?? "—")
                            compactMetric("RHR", candidate.averageRestingHeartRate.map { String(format: "%.1f bpm", $0) } ?? "—")
                            compactMetric("Resp", candidate.averageRespiratoryRate.map { String(format: "%.1f", $0) } ?? "—")
                            compactMetric("Restor", candidate.averageRestorativeSleepRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                            compactMetric("Stage", candidate.averageSleepStageBalance.map { String(format: "%.2f", $0) } ?? "—")
                            compactMetric("Alarm", candidate.alarmDependenceRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                            compactMetric("Skip/Late", candidate.skipLateRiskRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                            compactMetric("Risk", candidate.operationalRiskRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var matchedNightsSection: some View {
        if !recommendation.matchedNights.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Matched-Night Comparison")
                    .font(.subheadline.weight(.semibold))

                ForEach(Array(recommendation.matchedNights.prefix(6))) { night in
                    HStack {
                        Text(night.sessionDate)
                            .frame(width: 96, alignment: .leading)
                        Text(night.bandLabel ?? "—")
                            .frame(width: 70, alignment: .leading)
                        Text(night.intervalMinutes.map { "\($0)m" } ?? "—")
                            .frame(width: 56, alignment: .leading)
                        Text(night.sleepQuality.map { "SQ \($0)" } ?? "SQ —")
                            .frame(width: 52, alignment: .leading)
                        Text(night.readiness.map { "RD \($0)" } ?? "RD —")
                            .frame(width: 52, alignment: .leading)
                        Text(night.wakeType)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(night.score.map { String(format: "%.2f", $0) } ?? "—")
                            .foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var excludedNightsSection: some View {
        if !recommendation.excludedNights.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Excluded Comparable Nights")
                    .font(.subheadline.weight(.semibold))

                ForEach(Array(recommendation.excludedNights.prefix(5))) { night in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(night.sessionDate)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(night.bandLabel ?? "—")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(night.exclusionReasons.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text(recommendation.disclaimer)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func compactMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func color(for bucket: InsightConfidenceBucket) -> Color {
        switch bucket {
        case .high:
            return .green
        case .medium:
            return .blue
        case .low:
            return .orange
        case .insufficient:
            return .secondary
        }
    }
}
