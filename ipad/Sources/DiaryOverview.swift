import SwiftUI
import Charts
import DoseCore

struct DiaryOverview: View {
    let points: [DashboardDiaryPoint]
    let generation: UInt64
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedAssessment: Date?
    @State private var selectedComparison: DashboardDiaryPoint?
    private var rated: [DashboardDiaryPoint] {
        points.filter { $0.sleepiness0To10 != nil && $0.sleepinessAssessedAt != nil }
            .sorted { $0.sleepinessAssessedAt! < $1.sleepinessAssessedAt! }
    }
    private var summary: DashboardDiarySummary { DashboardDiaryAnalysis.summaries(for: points) }
    private var selectedPoint: DashboardDiaryPoint? {
        guard let selectedAssessment else { return nil }
        return rated.min {
            abs($0.sleepinessAssessedAt!.timeIntervalSince(selectedAssessment)) < abs($1.sleepinessAssessedAt!.timeIntervalSince(selectedAssessment))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Wake & sleepiness").font(.largeTitle.bold())
            Text("Explicit diary answers and their relationship to recorded Dose 2.")
                .font(.title3).foregroundStyle(.secondary)
            Text("\(points.count) dates with questionnaire evidence in this range. Each night has one editable diary assessment; this is not a complete series of daytime observations or an Epworth score.")
                .font(.footnote).foregroundStyle(.secondary)
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 300))], spacing: 16) {
                metric("Dose 2 → reported final wake", value: summary.medianElapsedMinutes.map(intervalText) ?? "Not available",
                       detail: "Median elapsed time, rounded to minutes · n = \(summary.elapsedCount) matched dates. This is not measured sleep.")
                metric("Sleepiness after reported final wake", value: summary.medianSleepiness.map { "\($0.formatted()) / 10" } ?? "Not available",
                       detail: "Median diary rating · n = \(summary.sleepinessCount) dates matched to Dose 2 and final wake.")
            }
            DiaryComparisons(points: points) { selectedComparison = $0 }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timed sleepiness observations").font(.title2.bold())
                    Text("\(rated.count) timed ratings, including those without a usable dose match. Violet points identify diary ratings, not treatment effectiveness.")
                    if rated.isEmpty {
                        ContentUnavailableView("No timed sleepiness ratings", systemImage: "clock.badge.questionmark", description: Text("Untimed, missing or invalid answers are not zero. Refresh after explicitly recording an assessment on your iPhone."))
                    } else {
                        Chart(rated) { point in
                            PointMark(x: .value("Assessment time", point.sleepinessAssessedAt!), y: .value("Sleepiness", point.sleepiness0To10!))
                                .foregroundStyle(.purple).symbolSize(65)
                                .accessibilityLabel("\(timestamp(point.sleepinessAssessedAt)): sleepiness \(point.sleepiness0To10!) of 10")
                        }.chartYScale(domain: 0...10).chartYAxisLabel("Diary sleepiness / 10")
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                            .chartXSelection(value: $selectedAssessment).frame(height: 280)
                            .accessibilityIdentifier("diary-sleepiness-chart")
                        Text("Touch the chart to inspect the nearest recorded assessment. Gaps are not filled; recorded values and times are also listed below.").font(.caption).foregroundStyle(.secondary)
                        if let selectedPoint { pointDetails(selectedPoint) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("What can be compared", systemImage: "line.3.horizontal.decrease.circle").font(.headline)
                    Text("Dose matches require unique, positive dose spacing and the same stored session identity. A missing match does not erase the diary observation. Reported final wake is self-report, separate from Apple Health sleep end and from time out of bed.")
                    DisclosureGroup("Excluded or unavailable measurements") {
                        exclusionList("Elapsed to final wake", summary.elapsedExclusions)
                        exclusionList("Sleepiness after final wake", summary.sleepinessExclusions)
                    }
                    Text("Times use \(TimeZone.current.identifier). Treatment dates remain the phone's recorded grouping. Calculation: dashboard-diary.v1.").font(.caption).foregroundStyle(.secondary)
                }.padding(14)
            }
            Text("Diary evidence by treatment night").font(.title2.bold())
            if points.isEmpty { Text("No questionnaire dates in this range. Widen the range or refresh the report.").foregroundStyle(.secondary) }
            ForEach(points) { point in
                GroupBox { pointDetails(point).padding(14) }
                    .accessibilityIdentifier("diary-night-\(point.treatmentDate)")
            }
        }.onChange(of: generation) { _, _ in selectedComparison = nil; selectedAssessment = nil }
            .sheet(item: $selectedComparison) { point in
            NavigationStack {
                ScrollView { pointDetails(point).padding(24) }.navigationTitle("Matched diary evidence")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedComparison = nil } } }
            }
        }
    }
    private func metric(_ title: String, value: String, detail: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                Text(value).font(.largeTitle.bold()).foregroundStyle(.purple)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
    }
    private func pointDetails(_ point: DashboardDiaryPoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(point.treatmentDate).font(.headline)
            LabeledContent("Diary sleepiness", value: point.sleepiness0To10.map { "\($0) / 10" } ?? "Not recorded")
            LabeledContent("Assessed at", value: timestamp(point.sleepinessAssessedAt))
            LabeledContent("Reported final wake", value: timestamp(point.reportedFinalWakeAt))
            LabeledContent("Matched Dose 2 occurrence", value: timestamp(point.dose2At))
            LabeledContent("Recorded Dose 1 → Dose 2 spacing", value: point.pairedIntervalMinutes.map(durationDetail) ?? "Not available")
            LabeledContent("Elapsed to reported final wake", value: point.dose2ToReportedFinalWakeMinutes.map(durationDetail) ?? "Not available")
            if let reason = point.elapsedExclusion { Text("Elapsed: \(reason.rawValue)").font(.caption).foregroundStyle(.secondary) }
            if let reason = point.sleepinessExclusion { Text("Post-wake rating: \(reason.rawValue)").font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Diary source") {
                Text("Recorded at: \(timestamp(point.recordedAt))")
                Text("Record: \(point.outcomeSourceRecordID ?? "Not available")")
                Text("Session: \(point.outcomeSessionID ?? "Not available")")
            }.font(.caption).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func exclusionList(_ title: String, _ counts: [DashboardDiaryExclusion: Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).bold()
            if counts.isEmpty { Text("No exclusions in this range.") }
            ForEach(counts.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { reason in
                Text("\(reason.rawValue): \(counts[reason]!)")
            }
        }.font(.caption).padding(.vertical, 8)
    }
    private func timestamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "Not recorded"
    }
    private func durationDetail(_ minutes: Double) -> String {
        let seconds = Int((minutes * 60).rounded())
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m \(seconds % 60)s"
    }
}
