import SwiftUI
import Charts
import DoseCore

struct DashboardLifestyleFactorsCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lifestyle Factors")
                .font(.headline)

            metricRow(title: "Avg Pre-Sleep Stress", value: model.averageStressLevel.map { String(format: "%.1f / 5", $0) } ?? "No data")
            metricRow(title: "High-Stress Bedtimes", value: model.highPreSleepStressRate.map { String(format: "%.0f%%", $0) } ?? "No data")
            metricRow(title: "Top Bedtime Stressor", value: model.topPreSleepStressDriver?.displayText ?? "None recorded")
            Text("Rates use answered completed logs. Quality comparisons use paired morning ratings on the 1–5 scale; they do not establish cause.")
                .font(.caption).foregroundColor(.secondary)
            factorRow(title: "Caffeine", samples: model.lifestyleSampleCounts { $0.reportedCaffeine }, rate: model.caffeineRate, impact: model.sleepQualityByCaffeine)
            factorRow(title: "Alcohol", samples: model.lifestyleSampleCounts { $0.alcohol.map { $0 != .none } }, rate: model.alcoholRate, impact: model.sleepQualityByAlcohol)
            factorRow(title: "Screens in Bed", samples: model.lifestyleSampleCounts { $0.screensInBed.map { $0 != .none } }, rate: model.screenTimeRate, impact: model.sleepQualityByScreens)
            metricRow(title: "Exercise Days", value: model.exerciseRate.map { String(format: "%.0f%%", $0) } ?? "No data")
            metricRow(title: "Late Meals (older question)", value: model.lateMealRate.map { String(format: "%.0f%%", $0) } ?? "No data")
            Text("No data means that this field was not answered in a completed log in this range.")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func metricRow(title: String, value: String, color: Color = DashboardPalette.sleep) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(value == "No data" || value == "None recorded" ? .secondary : color)
        }
    }

    private func factorRow(title: String, samples: (answered: Int, yes: Int, no: Int), rate: Double?, impact: (with: Double?, without: Double?)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(rate.map { String(format: "%.0f%%", $0) } ?? "No data") · \(samples.answered) answered nights")
                .font(.subheadline).foregroundColor(rate == nil ? .secondary : DashboardPalette.sleep)
            Text("Sleep quality: Yes \(impact.with.map { String(format: "%.1f", $0) } ?? "No data") (n=\(samples.yes)) · No \(impact.without.map { String(format: "%.1f", $0) } ?? "No data") (n=\(samples.no))")
                .font(.caption).foregroundColor(.secondary)
        }
    }

}

struct DashboardMoodSymptomsCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mood & Symptoms")
                .font(.headline)

            if model.averageMentalClarity != nil || model.narcolepsySymptomRate != nil || model.averageMorningStressLevel != nil {
                if let clarity = model.averageMentalClarity {
                    metricRow(title: "Mental Clarity", value: String(format: "%.1f / 10", clarity))
                } else {
                    metricRow(title: "Mental Clarity", value: "No data")
                }
                if let dreamRecall = model.dreamRecallRate {
                    metricRow(title: "Dream Recall", value: String(format: "%.0f%%", dreamRecall))
                } else {
                    metricRow(title: "Dream Recall", value: "No data")
                }
                if let stress = model.averageMorningStressLevel {
                    metricRow(title: "Avg Wake Stress", value: String(format: "%.1f / 5", stress), color: DashboardPalette.sleep)
                } else {
                    metricRow(title: "Avg Wake Stress", value: "No data")
                }
                if let delta = model.averageStressDeltaToWake {
                    metricRow(
                        title: "Wake vs Bedtime",
                        value: String(format: "%+.1f pts", delta),
                        color: DashboardPalette.sleep
                    )
                } else {
                    metricRow(title: "Wake vs Bedtime", value: "No data")
                }

                if !model.moodDistribution.isEmpty,
                   let topMood = model.moodDistribution.max(by: { $0.value < $1.value }) {
                    metricRow(title: "Top Mood", value: "\(topMood.key.capitalized) (\(topMood.value)x)")
                }

                if !model.anxietyDistribution.isEmpty {
                    let anxious = model.anxietyDistribution.filter { $0.key != "none" }.values.reduce(0, +)
                    let total = model.anxietyDistribution.values.reduce(0, +)
                    if total > 0 {
                        let percent = (Double(anxious) / Double(total)) * 100
                        metricRow(title: "Anxiety Reported", value: String(format: "%.0f%%", percent), color: DashboardPalette.sleep)
                    }
                }
                if let rate = model.highMorningStressRate {
                    metricRow(title: "High Wake Stress", value: String(format: "%.0f%%", rate), color: DashboardPalette.sleep)
                } else {
                    metricRow(title: "High Wake Stress", value: "No data")
                }
                if let topDriver = model.topMorningStressDriver {
                    metricRow(title: "Top Wake Stressor", value: topDriver.displayText)
                } else {
                    metricRow(title: "Top Wake Stressor", value: "No data")
                }
                if let worseRate = model.worseByWakeStressRate {
                    metricRow(title: "Stress Worse By Wake", value: String(format: "%.0f%%", worseRate), color: DashboardPalette.sleep)
                } else {
                    metricRow(title: "Stress Worse By Wake", value: "No data")
                }

                if !model.grogginessDistribution.isEmpty {
                    let severe = (model.grogginessDistribution["severe"] ?? 0) + (model.grogginessDistribution["moderate"] ?? 0)
                    let total = model.grogginessDistribution.values.reduce(0, +)
                    if total > 0 {
                        let percent = (Double(severe) / Double(total)) * 100
                        metricRow(title: "Moderate+ Grogginess", value: String(format: "%.0f%%", percent), color: DashboardPalette.sleep)
                    }
                }

                if model.narcolepsySymptomRate != nil {
                    Divider()
                    Text("Narcolepsy Symptoms")
                        .font(.caption.bold())
                        .foregroundColor(DashboardPalette.sleep)
                    symptomRow(title: "Sleep Paralysis", count: model.sleepParalysisCount)
                    symptomRow(title: "Hallucinations", count: model.hallucinationCount)
                    symptomRow(title: "Automatic Behavior", count: model.automaticBehaviorCount)
                }
            } else {
                Text("Complete morning check-ins to track mood & symptoms.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func metricRow(title: String, value: String, color: Color = DashboardPalette.sleep) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(value == "No data" || value == "None recorded" ? .secondary : color)
        }
    }


    private func symptomRow(title: String, count: Int) -> some View {
        HStack {
            Image(systemName: "list.bullet")
                .font(.caption)
                .foregroundColor(DashboardPalette.sleep)
            Text(title).font(.caption)
            Spacer()
            Text("\(count) night\(count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
                .foregroundColor(DashboardPalette.sleep)
        }
    }
}

struct DashboardStressTrendsCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    private struct StressSeriesPoint: Identifiable {
        var id: String { "\(date.timeIntervalSince1970)-\(series)" }
        let date: Date
        let series: String
        let value: Double
    }

    private var seriesPoints: [StressSeriesPoint] {
        model.stressTrendPoints.flatMap { point in
            var values: [StressSeriesPoint] = []
            if let bedtimeStress = point.bedtimeStress {
                values.append(StressSeriesPoint(date: point.date, series: "Bedtime Stress", value: bedtimeStress))
            }
            if let wakeStress = point.wakeStress {
                values.append(StressSeriesPoint(date: point.date, series: "Wake Stress", value: wakeStress))
            }
            if let sleepQuality = point.sleepQuality {
                values.append(StressSeriesPoint(date: point.date, series: "Sleep Quality", value: sleepQuality))
            }
            if let readiness = point.readiness {
                values.append(StressSeriesPoint(date: point.date, series: "Wake Readiness", value: readiness))
            }
            return values
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stress Trends")
                    .font(.headline)
                Spacer()
                Text("\(model.stressTrendNightCount) nights")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Compare bedtime stress, wake stress, sleep quality, and wake readiness on the same 1–5 scale.")
                .font(.caption)
                .foregroundColor(.secondary)

            #if canImport(Charts)
            if seriesPoints.isEmpty {
                emptyChartState("Complete pre-sleep stress and morning check-ins to unlock stress trends.")
            } else {
                Chart(seriesPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Score", point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Score", point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .symbolSize(28)
                }
                .chartForegroundStyleScale([
                    "Bedtime Stress": Color.orange,
                    "Wake Stress": Color.red,
                    "Sleep Quality": Color.blue,
                    "Wake Readiness": Color.green
                ])
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4, 5])
                }
                .chartYAxisLabel("1–5 Score")
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 220)
            }
            #else
            Text("Charts are unavailable on this platform build.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            #endif

            Group {
                Text("Observed comparisons · high stress 4–5, lower 1–3")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                comparisonRow(
                    title: "Sleep quality after high-stress bedtimes",
                    high: model.sleepQualityByHighBedtimeStress.high,
                    lower: model.sleepQualityByHighBedtimeStress.lower,
                    formatter: { String(format: "%.1f / 5", $0) },
                    color: impactColor(high: model.sleepQualityByHighBedtimeStress.high, lower: model.sleepQualityByHighBedtimeStress.lower, preferHigher: true)
                )
                comparisonRow(
                    title: "Wake readiness after high-stress bedtimes",
                    high: model.readinessByHighBedtimeStress.high,
                    lower: model.readinessByHighBedtimeStress.lower,
                    formatter: { String(format: "%.1f / 5", $0) },
                    color: impactColor(high: model.readinessByHighBedtimeStress.high, lower: model.readinessByHighBedtimeStress.lower, preferHigher: true)
                )
                comparisonRow(
                    title: "Dose interval on high-stress bedtimes",
                    high: model.intervalByHighBedtimeStress.high,
                    lower: model.intervalByHighBedtimeStress.lower,
                    formatter: { TimeIntervalMath.formatMinutes(Int($0.rounded())) }
                )
            }

            Group {
                Text("Recurring stressors")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                if let rate = model.stressCarryoverNightRate {
                    metricRow(
                        title: "Same driver carried into morning",
                        value: String(format: "%.0f%%", rate),
                        color: DashboardPalette.sleep
                    )
                }
                if let topDriver = model.topRecurringStressDriver {
                    metricRow(title: "Top recurring driver", value: topDriver.displayText)
                }
                if let topCarryover = model.topCarryoverStressDriver {
                    metricRow(title: "Top carryover driver", value: topCarryover.displayText, color: .orange)
                }

                if model.recurringStressDrivers.isEmpty {
                    Text("No recurring stressors tracked yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(model.recurringStressDrivers.prefix(3))) { driver in
                        HStack(alignment: .top, spacing: 10) {
                            Text(driver.driver.displayText)
                                .font(.subheadline)
                            Spacer()
                            Text("\(driver.totalCount) night\(driver.totalCount == 1 ? "" : "s")")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            if driver.carryoverCount > 0 {
                                Text("\(driver.carryoverCount) carried")
                                    .font(.caption2.bold())
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.orange.opacity(0.16))
                                    )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    @ViewBuilder
    private func comparisonRow(
        title: String,
        high: Double?,
        lower: Double?,
        formatter: (Double) -> String,
        color: Color = .secondary
    ) -> some View {
        if let high, let lower {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline)
                    Spacer()
                    Text("High: \(formatter(high))")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(color)
                    Text("Lower: \(formatter(lower))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func metricRow(title: String, value: String, color: Color = .secondary) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
    }

    private func impactColor(high: Double?, lower: Double?, preferHigher: Bool) -> Color {
        .secondary
    }

    private func emptyChartState(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct DashboardCapturedMetricsCard: View {
    let categories: [DashboardMetricCategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Captured Metrics Inventory")
                .font(.headline)
            Text("Reference for the records used in this dashboard. Availability depends on your logs, connected sources and selected dates; this list does not mean every field has data.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.title)
                        .font(.subheadline.bold())
                    ForEach(category.metrics, id: \.self) { metric in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(metric)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct DashboardFoodDiaryCard: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var day: FollowingDayKind?
    private var summary: FoodDiaryAnalytics { model.foodDiaryAnalytics(day: day) }

    private func value(_ metric: DiaryMetricSummary, minutes: Bool = true) -> String {
        let number = metric.median.map { minutes ? IntervalFormat.minutes.string(from: $0) : String(format: "%.1f / 10", $0) } ?? "—"
        return "\(number) · n = \(metric.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Food timing & next-day diary", systemImage: "fork.knife").font(.headline)
            Picker("Following day for food comparison", selection: $day) {
                Text("All days").tag(nil as FollowingDayKind?)
                ForEach(FollowingDayKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }.pickerStyle(.menu).fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("food-comparison-day-filter")
            Text("Last food recorded: \(summary.food.count) of \(summary.nightCount) nights")
                .font(.subheadline)
            Text("No completed food entry: \(summary.missingFoodCount). Older late-meal answers are kept separate.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Median food → Dose 1: \(value(summary.interval(dose: 1)))")
                Text("Median food → Dose 2: \(value(summary.interval(dose: 2)))")
            }.font(.subheadline)
            Text("High-fat: Yes \(summary.fatCount(true)) · No \(summary.fatCount(false)) · Unsure/blank \(summary.unsureFatCount)")
                .font(.caption)
            DisclosureGroup("Compare recorded food answers") {
                ForEach([true, false], id: \.self) { fat in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(fat ? "High-fat: Yes" : "High-fat: No").font(.subheadline.bold())
                        Text("Median next-day sleepiness: \(value(summary.sleepiness(highFat: fat), minutes: false))")
                        Text("Median sleep after Dose 2: \(value(summary.sleepAfterDose2(highFat: fat)))")
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
                Text("Sleep source: \(model.sleepSource.rawValue). Post-dose estimates need Apple Health segments; unmeasured time is excluded. Each n counts paired food and outcome records.").font(.caption)
            }
            Text("These are diary observations, not evidence that food caused an outcome. Missing answers are not No or zero. Food logged after a dose is excluded from that dose's interval.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct DashboardWakeComparisonCard: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var day: FollowingDayKind?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var nights: [DashboardNightAggregate] { model.wakeComparisonNights(day: day) }
    private func group(_ kind: Dose2WakeKind) -> [DashboardNightAggregate] { nights.filter { $0.effectiveWakeMethod == kind } }
    private func value(_ value: Double?, metric: WakeOutcomeMetric) -> String {
        guard let value else { return "—" }
        if metric == .sleepiness { return String(format: "%.1f", value) }
        return IntervalFormat.minutes.string(from: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Natural waking vs. alarm waking", systemImage: "sun.and.horizon").font(.headline)
            Text("Wake before Dose 2, not final morning awakening. Sleep source: \(model.sleepSource.rawValue).")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Following day", selection: $day) {
                Text("All days").tag(nil as FollowingDayKind?)
                ForEach(FollowingDayKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }.accessibilityIdentifier("wake-comparison-day-filter")
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow { Text("Metric"); Text("Natural"); Text("Alarm") }.font(.caption.bold())
                GridRow {
                    Text("Recorded nights")
                    Text("\(group(.natural).count)")
                    Text("\(group(.alarm).count)")
                }
                GridRow {
                    Text("Within-window pairs")
                    Text("\(group(.natural).filter { $0.onTimeDosing == true }.count)")
                    Text("\(group(.alarm).filter { $0.onTimeDosing == true }.count)")
                }
                if !typeSize.isAccessibilitySize {
                    ForEach(WakeOutcomeMetric.allCases, id: \.self) { metric in
                        GridRow {
                            Text("Median \(metric.rawValue.lowercased())")
                            metricCell(metric, kind: .natural)
                            metricCell(metric, kind: .alarm)
                        }
                    }
                }
            }.font(.caption)
            if typeSize.isAccessibilitySize {
                ForEach(WakeOutcomeMetric.allCases, id: \.self) { metric in
                    VStack(alignment: .leading) {
                        Text("Median \(metric.rawValue.lowercased())").font(.headline)
                        ForEach([Dose2WakeKind.natural, .alarm], id: \.self) { kind in
                            HStack { Text(kind.title); metricCell(metric, kind: kind) }
                        }
                    }
                }
            }
            Text("Other: \(group(.other).count) nights · Unknown: \(group(.unknown).count) nights")
                .font(.caption)
            Text("Each n counts nights with that measurement, not all recorded pairs. Missing data is not zero.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Middle 50% ranges") {
                ForEach(WakeOutcomeMetric.allCases, id: \.self) { metric in
                    ForEach([Dose2WakeKind.natural, .alarm], id: \.self) { kind in
                        let summary = model.wakeMetric(metric, kind: kind, day: day)
                        Text("\(metric.rawValue) · \(kind.title): \(value(summary.lowerQuartile, metric: metric))–\(value(summary.upperQuartile, metric: metric)) · n = \(summary.count)")
                            .font(.caption)
                    }
                }
            }
            DisclosureGroup("Data notes and sources") {
                let gaps = model.sleepSource == .appleHealth ? nights.filter { $0.postDoseSleep?.hasCoverageGaps == true }.count : 0
                Text(model.sleepSource == .appleHealth
                 ? "Sleep after D2 is estimated from recorded asleep segments, excluding awake periods. \(gaps) estimates have coverage gaps; unmeasured time is excluded."
                 : "Sleep after D2 is unavailable from WHOOP nightly totals; totals do not identify post-dose sleep segments.")
                .font(.caption).foregroundStyle(.secondary)
                Text("Groups use explicitly saved wake-diary answers. Confirm older nights in History; questionnaire carry-forward values are not assumed correct.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Sleepiness is a personal 0–10 diary rating. Older 1–5 answers are not converted. These associations do not establish medication effectiveness or causation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if nights.contains(where: \.outcomeReadFailed) {
                Text("Some diaries could not be read. Those wake methods remain Unknown.").font(.caption).foregroundStyle(.orange)
            }
            Divider()
            Text("Timing & status · full date range").font(.subheadline.bold())
            Text("Before window: \(model.timingCount(.early)) · Within window: \(model.timingCount(.inWindow)) · After window: \(model.timingCount(.late))")
                .font(.caption)
            Text("Before: <150 min · Within: 150–240 min inclusive · After: >240 min. Classified using unrounded elapsed time.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Confirmed skipped: \(model.skippedDose2Count) · Not logged: \(model.missingDose2OutcomeCount) · Pending: \(model.pendingDose2OutcomeCount)")
                .font(.caption)
            Text("Day filtering affects the outcome comparison only; the timing/status report keeps all nights in the selected date range.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
        .accessibilityIdentifier("wake-comparison-card")
    }

    private func metricCell(_ metric: WakeOutcomeMetric, kind: Dose2WakeKind) -> some View {
        let summary = model.wakeMetric(metric, kind: kind, day: day)
        return VStack(alignment: .leading, spacing: 2) {
            Text(value(summary.median, metric: metric)).bold()
            Text("n = \(summary.count)").foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title), median \(metric.rawValue): \(value(summary.median, metric: metric)), \(summary.count) usable nights")
    }
}
