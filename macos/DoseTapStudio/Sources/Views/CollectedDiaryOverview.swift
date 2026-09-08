import SwiftUI
import DoseCore

struct CollectedDiaryOverview: View {
    let sessions: [InsightSession]
    @State private var day: FollowingDayKind?
    private var selected: [InsightSession] {
        sessions.filter { day == nil || ($0.collectedNight?.followingDayType ?? "unknown") == day?.rawValue }
    }
    private var food: FoodDiaryAnalytics {
        FoodDiaryAnalytics(selected.map { $0.preSleep?.completionState == "complete" ? ($0.collectedNight ?? .init()) : .init() })
    }
    private func group(_ wake: Dose2WakeKind) -> [CollectedNightSummary] {
        selected.filter { $0.recordedDose2Wake == wake }.compactMap(\.collectedNight)
    }
    private func value(_ metric: DiaryMetricSummary, unit: String) -> String {
        let number = metric.median.map { String(format: "%.1f", $0) + unit } ?? "—"
        return "\(number) · n = \(metric.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Food and next-day diary").font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Text("All imported nights, filtered by the following day. These observations do not establish cause or medication effectiveness.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Following day", selection: $day) {
                    Text("All days").tag(nil as FollowingDayKind?)
                    ForEach(FollowingDayKind.allCases, id: \.self) { kind in
                        Text(kind == .dayOff ? "Day off" : kind.rawValue.capitalized).tag(Optional(kind))
                    }
                }.frame(maxWidth: 300)
                Text("Completed last-food records: \(food.food.count) of \(food.nightCount) nights · No entry: \(food.missingFoodCount)")
                Text("High-fat: Yes \(food.fatCount(true)) · No \(food.fatCount(false)) · Unsure/blank \(food.unsureFatCount)")
                Text("Median food → Dose 1: \(value(food.interval(dose: 1), unit: "m")) · Food → Dose 2: \(value(food.interval(dose: 2), unit: "m"))")
                Divider()
                Text("Recorded waking before Dose 2").font(.headline)
                ForEach([Dose2WakeKind.natural, .alarm, .other], id: \.self) { kind in
                    let reports = group(kind)
                    Text("\(kind.rawValue.capitalized): \(reports.count) nights · Median sleepiness \(value(DiaryMetricSummary(reports.map { $0.sleepiness0To10.map(Double.init) }), unit: "/10")) · Sleep after D2 \(value(DiaryMetricSummary(reports.map(\.estimatedSleepAfterDose2Minutes)), unit: "m"))")
                }
                let unknown = selected.filter { $0.dose2Time != nil }.count - group(.natural).count - group(.alarm).count - group(.other).count
                Text("Dose 2 wake method unknown: \(unknown). No alarm-time inference is used here.").font(.caption)
                DisclosureGroup("Food answer comparisons") {
                    ForEach([true, false], id: \.self) { fat in
                        Text("High-fat \(fat ? "Yes" : "No"): median sleepiness \(value(food.sleepiness(highFat: fat), unit: "/10")) · Sleep after D2 \(value(food.sleepAfterDose2(highFat: fat), unit: "m"))")
                    }
                }
                Text("Each n counts available observations. The 0–10 diary is separate from legacy 1–5 answers. Post-dose sleep uses exported Apple Health segments, excludes unmeasured time, and is unavailable in local-only scheduled bundles. Open a night for coverage minutes and source details.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }.padding().background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
