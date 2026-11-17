import SwiftUI
import Charts
import DoseCore

struct QuestionnaireOverview: View {
    let days: [DashboardQuestionnaireDay]
    let unassignedSourceRowCount: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    private var rated: [DashboardQuestionnaireDay] { days.filter { $0.recordedSleepQuality != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Sleep & check-ins").font(.largeTitle.bold())
            Text("Recorded answers, with the limits of each source visible.").font(.title3).foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Recorded sleep quality", systemImage: "moon.stars").font(.title2.bold())
                    Text("\(rated.count) dates with a usable stored rating / \(days.count) dates with questionnaire evidence in this range")
                        .font(.subheadline)
                    Text("These historical ratings may include form defaults. Freshness and individual answer confirmation are unknown. They are not wearable sleep duration or verified treatment outcomes.")
                        .foregroundStyle(.orange)
                    if rated.isEmpty {
                        ContentUnavailableView("No usable recorded ratings", systemImage: "questionmark.circle", description: Text("Unanswered, skipped and conflicting records are not zero scores."))
                    } else {
                        Chart(rated) { day in
                            PointMark(x: .value("Treatment date", plotDate(day.treatmentDate)),
                                      y: .value("Recorded quality", day.recordedSleepQuality!))
                                .foregroundStyle(.indigo).symbolSize(55)
                                .accessibilityLabel("\(day.treatmentDate): stored quality \(day.recordedSleepQuality!.formatted()) of 5; confirmation unknown")
                        }.chartYScale(domain: 1...5).chartYAxisLabel("Stored rating / 5")
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                            .frame(height: 280)
                        Text("Points show available stored answers. Gaps are not interpolated. Exact values are listed below.").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 270))], spacing: 16) {
                coverage("Pre-sleep", statuses: days.map(\.preSleep))
                coverage("Morning", statuses: days.map(\.morning))
                coverage("Night outcome diary", statuses: days.map(\.nightOutcome))
            }
            if unassignedSourceRowCount > 0 {
                Label("\(unassignedSourceRowCount) questionnaire source rows cannot be assigned to a treatment date across the full report. They are excluded from date comparisons; normalized copies may refer to the same questionnaire.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Wearable sleep measurements", systemImage: "waveform.path").font(.headline)
                    Text("Inspect Apple Health evidence for any original sleep intervals included by the phone. Reviewed total sleep, return to sleep after Dose 2, and natural-versus-alarm sleep comparisons are not calculated here yet. Questionnaire completion and dose times cannot substitute for those measurements. WHOOP is not included.")
                        .foregroundStyle(.secondary)
                }.padding(14)
            }
            Text("Answers by treatment night").font(.title2.bold())
            Text("Wake answers below are stored reports; their association with a valid Dose 2 event has not been verified. Following-day answers do not establish actual work attendance.").font(.footnote).foregroundStyle(.secondary)
            if days.isEmpty { Text("No questionnaire evidence in this range. Widen the range or refresh from your iPhone.").foregroundStyle(.secondary) }
            ForEach(days) { day in
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(day.treatmentDate).font(.headline)
                        Text("Pre-sleep: \(day.preSleep.rawValue) · Morning: \(day.morning.rawValue) · Diary: \(day.nightOutcome.rawValue)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        LabeledContent("Stored sleep quality", value: day.recordedSleepQuality.map { "\($0.formatted()) / 5" } ?? "Not available")
                        LabeledContent("Stored Dose 2 wake answer", value: day.dose2WakeMethod?.rawValue.capitalized ?? "Not available")
                        LabeledContent("Reported following day", value: followingDay(day.followingDay))
                        if let provenance = day.sleepQualityProvenance { Text(provenance).font(.caption).foregroundStyle(.secondary) }
                        DisclosureGroup("Source record identifiers") {
                            ForEach(day.sourceRecordIDs, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                        }.font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.accessibilityIdentifier("questionnaire-night-\(day.treatmentDate)")
            }
        }
    }
    private func coverage(_ title: String, statuses: [DashboardQuestionnaireStatus]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                ForEach(Array(Set(statuses.map(\.rawValue))).sorted(), id: \.self) { status in
                    HStack { Text(status.capitalized); Spacer(); Text("\(statuses.filter { $0.rawValue == status }.count)").bold() }
                }
                Text("\(days.count) questionnaire dates in range; not all expected nights.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
    private func followingDay(_ value: FollowingDayKind?) -> String {
        switch value { case .workday: return "Workday"; case .dayOff: return "Day off"; case .unknown: return "Unknown (stored)"; case nil: return "Not available" }
    }
    private func plotDate(_ key: String) -> Date {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key) ?? .distantPast
    }
}
