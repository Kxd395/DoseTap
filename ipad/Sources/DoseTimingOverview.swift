import SwiftUI
import Charts
import DoseCore

struct DoseTimingOverview: View {
    let nights: [DashboardReportDoseDay]
    let onSelect: (DashboardReportDoseDay) -> Void
    @State private var selectedDate: Date?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var stats: DashboardReportStatistics { DashboardReportStatistics(days: nights) }
    private var selectedNight: DashboardReportDoseDay? {
        guard let selectedDate else { return nil }
        return nights.filter { $0.intervalMinutes != nil }.min {
            abs(plotDate($0.treatmentDate).timeIntervalSince(selectedDate)) < abs(plotDate($1.treatmentDate).timeIntervalSince(selectedDate))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("DOSE TIMING", systemImage: "clock").font(.caption.weight(.semibold)).foregroundStyle(.cyan)
                    Text("Your recorded rhythm").font(.largeTitle.bold())
                    Text("\(nights.last?.treatmentDate ?? "No dates") → \(nights.first?.treatmentDate ?? "No dates")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.xyaxis.line").font(.system(size: 42)).foregroundStyle(.cyan)
            }
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)] : [GridItem(.adaptive(minimum: 210), alignment: .leading)], spacing: 14) {
                metric("Median recorded spacing", stats.median.map(intervalText) ?? "Not available", detail: "n = \(stats.values.count) usable pairs", icon: "arrow.left.and.right")
                metric("Average recorded spacing", stats.mean.map(intervalText) ?? "Not available", detail: "Same \(stats.values.count) usable pairs", icon: "sum")
                metric("Dates with dose records", "\(nights.count)", detail: "Recorded dates, not expected doses", icon: "calendar")
                metric("Usable dose pairs", "\(stats.values.count)", detail: "Positive, unambiguous timestamps", icon: "checkmark.circle")
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Interval by treatment night", systemImage: "chart.xyaxis.line").font(.title3.bold())
                    Text("Touch the chart to select the nearest recorded pair, or use Night review.").font(.subheadline).foregroundStyle(.secondary)
                    if stats.values.isEmpty { ContentUnavailableView("No usable pairs", systemImage: "clock.badge.questionmark", description: Text("Missing or conflicting times are not plotted as zero.")) }
                    else {
                        Chart {
                            ForEach(nights) { night in
                                if let minutes = night.intervalMinutes {
                                    PointMark(x: .value("Treatment night", plotDate(night.treatmentDate)), y: .value("Minutes", minutes))
                                        .foregroundStyle(.cyan).symbolSize(36)
                                        .accessibilityLabel("\(night.treatmentDate): \(intervalText(minutes))")
                                }
                            }
                            if let median = stats.median {
                                RuleMark(y: .value("Median", median)).foregroundStyle(.cyan.opacity(0.5))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            }
                            if let night = selectedNight {
                                RuleMark(x: .value("Selected", plotDate(night.treatmentDate))).foregroundStyle(.white.opacity(0.5))
                            }
                        }.chartXSelection(value: $selectedDate)
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                            .chartYAxisLabel("Elapsed minutes").frame(height: 310)
                        Text("Dashed line: median. Gaps stay gaps; dots are recorded pairs, not sleep measurements.").font(.caption).foregroundStyle(.secondary)
                        if let night = selectedNight {
                            Button { onSelect(night) } label: {
                                Label("Review \(night.treatmentDate) · \(night.intervalMinutes.map(intervalText) ?? "Unknown")", systemImage: "arrow.up.right.square")
                            }.buttonStyle(.bordered)
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)] : [GridItem(.adaptive(minimum: 330), alignment: .leading)], alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("How intervals are distributed", systemImage: "chart.bar").font(.headline)
                        Chart(stats.distribution) { bucket in
                            BarMark(x: .value("Spacing", bucket.label), y: .value("Pairs", bucket.count))
                                .foregroundStyle(.cyan.gradient)
                                .accessibilityLabel("\(bucket.label): \(bucket.count) pairs")
                        }.chartYAxisLabel("Recorded pairs").frame(height: 210)
                        Text("One-hour bands; lower bound included. 6h+ includes every longer interval. These are descriptive bands, not dosing windows.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Middle 50%: \(stats.lowerQuartile.map(intervalText) ?? "—") – \(stats.upperQuartile.map(intervalText) ?? "—")").font(.subheadline)
                    }.padding(8)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Record completeness", systemImage: "list.clipboard").font(.headline)
                        ForEach(DashboardDoseDayState.allCases, id: \.rawValue) { state in
                            HStack { Label(state.rawValue, systemImage: state == .paired ? "checkmark.circle" : "info.circle"); Spacer(); Text("\(stats.count(state))").bold().monospacedDigit() }
                                .foregroundStyle(state == .conflict ? .orange : .primary)
                        }
                        Divider()
                        Text("Counts describe \(nights.count) dates containing dose events. A missing pair is not a confirmed skipped dose. Dates with no dose events are outside this denominator.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Shortest / longest: \(stats.minimum.map(intervalText) ?? "—") / \(stats.maximum.map(intervalText) ?? "—")").font(.subheadline)
                    }.padding(8)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Month-by-month spacing", systemImage: "calendar").font(.title3.bold())
                    Text("Median of eligible pairs within the selected range; a partial month stays partial. Each row shows its own sample count.").font(.subheadline).foregroundStyle(.secondary)
                    if stats.months.isEmpty { Text("No eligible monthly observations.") }
                    ForEach(stats.months.reversed()) { month in
                        HStack { Text(month.key).monospaced(); Spacer(); Text(intervalText(month.median)).bold(); Text("n = \(month.count)").foregroundStyle(.secondary).frame(minWidth: 80, alignment: .trailing) }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Spacing uses reported administration times. This report does not establish treatment effectiveness, measured drug levels or a recommended dose interval.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func metric(_ title: String, _ value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title.bold()).foregroundStyle(.cyan)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cyan.opacity(0.2)))
    }
    private func plotDate(_ key: String) -> Date {
        let format = DateFormatter(); format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = .current; format.dateFormat = "yyyy-MM-dd"
        return format.date(from: key) ?? .distantPast
    }
}

func intervalText(_ minutes: Double) -> String {
    let value = Int(minutes.rounded()); return "\(value / 60)h \(value % 60)m"
}

struct DoseNightDetail: View {
    let night: DashboardReportDoseDay
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Treatment night") { Text(night.treatmentDate).font(.title2.bold()); Text(night.status) }
                Section("Reported administration times") {
                    LabeledContent("Dose 1", value: night.dose1At?.formatted(date: .abbreviated, time: .shortened) ?? "Not available unambiguously")
                    LabeledContent("Dose 2", value: night.dose2At?.formatted(date: .abbreviated, time: .shortened) ?? "Not available unambiguously")
                    Text("Times shown in \(TimeZone.current.identifier). Dates are shown explicitly across midnight.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Recorded spacing") {
                    Text(night.intervalMinutes.map(intervalText) ?? "Excluded from spacing statistics").font(.title2.bold())
                    Text("The difference uses reported dose occurrence times, never report capture time. Conflicting identities or duplicate doses are not silently selected. Review or correct source records on the iPhone.")
                    Text("Historical regimen and reminder settings are not classified here. A reported interval does not establish whether medication was taken within a prescribed window.").foregroundStyle(.secondary)
                }
            }.navigationTitle("Night detail").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}
