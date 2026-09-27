import SwiftUI
import DoseCore

/// A navigation summary, with each card stating its own population.
struct ReportOverview: View {
    let report: DashboardReportProjection
    let nights: [DashboardReportDoseDay]
    let diaryPoints: [DashboardDiaryPoint]
    let open: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var stats: DashboardReportStatistics { .init(days: nights) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your nights. Your days.").font(.largeTitle.bold())
                Text("Review what was recorded, explore changes, and see where evidence is missing.")
                    .font(.title3).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 290))], spacing: 18) {
                card("Dose timing", icon: "clock", value: stats.median.map(intervalText) ?? "Not available",
                     detail: "Median recorded spacing · \(stats.values.count) usable pairs in this range", color: .cyan)
                card("Medications", icon: "pills", value: "\(report.medications.count) records",
                     detail: "All available calendar dates · \(report.unknownMedicationTimeCount) taken times unknown", color: .teal)
                card("Sleep & check-ins", icon: "moon.stars", value: "Recorded answers",
                     detail: "Subjective sleep quality and questionnaire coverage, separate from wearable sleep", color: .indigo)
                card("Wake & sleepiness", icon: "sun.horizon", value: "\(diaryPoints.filter { $0.sleepiness0To10 != nil }.count) timed ratings",
                     detail: "Explicit diary observations, reported final wake and qualified Dose 2 associations", color: .purple)
                card("Night review", icon: "calendar", value: "\(stats.count(.conflict)) need review",
                     detail: "Conflicting dose records in this range · inspect dates before comparing", color: .orange)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("What this report can tell you", systemImage: "checklist").font(.title2.bold())
                    Text("Dose spacing uses unique reported administration times. Medication history uses the actual calendar date, so a morning medication stays on that day. Questionnaire ratings describe recorded answers; older records may not establish that each answer was freshly confirmed.")
                    Divider()
                    Label("Wearable sleep is not in this download", systemImage: "waveform.path").font(.headline).foregroundStyle(.orange)
                    Text("Apple Health and WHOOP measurements are not yet included in nearby reports. Sleep duration, sleep stages, return to sleep, and interval-versus-sleep comparisons cannot be calculated here yet. Their absence does not mean you slept zero hours.")
                        .foregroundStyle(.secondary)
                    Button("Inspect report contents") { open("Report contents") }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            if let latest = nights.first {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Latest recorded dose night", systemImage: "calendar.badge.clock").font(.headline)
                        Text(latest.treatmentDate).font(.title2.bold())
                        Text("\(latest.status) · \(latest.intervalMinutes.map(intervalText) ?? "Spacing unavailable")")
                        Button("Open night review") { open("Night review") }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
            }
        }
    }
    private func card(_ title: String, icon: String, value: String, detail: String, color: Color) -> some View {
        Button { open(title) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Label(title, systemImage: icon).font(.headline); Spacer(); Image(systemName: "arrow.up.right") }
                Text(value).font(.title.bold()).foregroundStyle(color)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading).padding(22)
                .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(0.25)))
        }.buttonStyle(.plain).accessibilityIdentifier("overview-\(title)")
    }
}
