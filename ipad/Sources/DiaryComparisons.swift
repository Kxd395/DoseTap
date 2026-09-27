import SwiftUI
import Charts
import DoseCore

struct DiaryComparisons: View {
    let points: [DashboardDiaryPoint]
    let inspect: (DashboardDiaryPoint) -> Void
    @State private var elapsedToWake = false
    @State private var selectedX: Double?
    private var matched: [DashboardDiaryPoint] {
        points.filter { $0.matchedSleepiness0To10 != nil && x($0) != nil }
    }
    private var nearest: [DashboardDiaryPoint] {
        guard let selectedX, let closest = matched.min(by: { abs(x($0)! - selectedX) < abs(x($1)! - selectedX) }), let value = x(closest) else { return [] }
        return matched.filter { x($0) == value }
    }
    private var axis: String { elapsedToWake ? "Elapsed Dose 2 to reported final wake (minutes)" : "Recorded Dose 1 to Dose 2 spacing (minutes)" }
    private func x(_ point: DashboardDiaryPoint) -> Double? {
        elapsedToWake ? point.dose2ToReportedFinalWakeMinutes : point.pairedIntervalMinutes
    }
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("Timing and reported sleepiness").font(.title2.bold())
                Picker("Compare sleepiness with", selection: $elapsedToWake) {
                    Text("Dose spacing").tag(false)
                    Text("Elapsed to final wake").tag(true)
                }.pickerStyle(.menu).accessibilityIdentifier("diary-comparison-picker")
                    .onChange(of: elapsedToWake) { _, _ in selectedX = nil }
                Text("n = \(matched.count) matched dates / \(points.count) questionnaire dates. Each point is one diary assessment after a matched Dose 2 and reported final wake.")
                    .font(.subheadline)
                if matched.isEmpty {
                    Text("No comparable observations in this range. A valid dose pair, matching session identity, reported final wake and timed sleepiness are all required.").foregroundStyle(.secondary)
                } else {
                    Chart(matched) { point in
                        PointMark(x: .value(axis, x(point)!), y: .value("Diary sleepiness", point.matchedSleepiness0To10!))
                            .foregroundStyle(.purple).symbolSize(65)
                            .accessibilityLabel("\(point.treatmentDate): \(x(point)!.formatted()) minutes; sleepiness \(point.matchedSleepiness0To10!) of 10")
                    }.chartYScale(domain: 0...10).chartYAxisLabel("Diary sleepiness / 10")
                        .chartXAxisLabel(axis).chartXSelection(value: $selectedX).frame(height: 280)
                        .accessibilityIdentifier("diary-comparison-chart")
                    if Set(matched.compactMap(\.matchedSleepiness0To10)).count == 1 {
                        Text("All matched ratings are the same. These observations cannot distinguish better or worse sleepiness outcomes.").foregroundStyle(.secondary)
                    }
                    Text("Touch a horizontal position to list its nearest records. Violet means diary evidence; it is not a dosing-window or effectiveness rating.").font(.caption).foregroundStyle(.secondary)
                    ForEach(nearest) { point in
                        Button("Inspect \(point.treatmentDate) · \(point.matchedSleepiness0To10!) / 10") { inspect(point) }
                    }
                    DisclosureGroup("Matched records") {
                        ForEach(matched) { point in
                            Button("\(point.treatmentDate) · \(x(point)!.formatted()) min · \(point.matchedSleepiness0To10!) / 10") { inspect(point) }
                                .accessibilityIdentifier("diary-matched-\(point.treatmentDate)")
                        }
                    }
                }
                Text("This comparison describes recorded observations. Elapsed to final wake includes awake and unknown time. Different assessment times, sleep opportunity, work, pain and other factors can affect the comparison; it does not identify a best dose interval.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
    }
}
