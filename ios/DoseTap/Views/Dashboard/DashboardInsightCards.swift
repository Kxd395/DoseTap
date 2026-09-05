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
            metricRow(title: "Late Meals", value: model.lateMealRate.map { String(format: "%.0f%%", $0) } ?? "No data")
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

struct DashboardDoseEffectivenessCard: View {
    let report: DoseEffectivenessReport

    private let fmt = IntervalFormat.minutes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Timing Groups", systemImage: "chart.bar.doc.horizontal")
                    .font(.headline)
                Spacer()
                Text("Recorded pairs").font(.caption).foregroundColor(.secondary)
            }

            Text(intervalChangeText)
                .font(.subheadline.bold()).foregroundColor(DashboardPalette.timing)
            Text("Recent interval change compares the newer half of recorded pairs with the older half; it does not rate a shorter or longer interval as better.")
                .font(.caption).foregroundColor(.secondary)
            Text("Descriptive groups of recorded intervals. These do not measure medication effectiveness.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            HStack(spacing: 16) {
                complianceGauge
                VStack(alignment: .leading, spacing: 4) {
                    Text("In-window pairs").font(.caption).foregroundColor(.secondary)
                    Text("\(report.totalNights) nights analyzed")
                        .font(.subheadline)
                    Text("\(report.pairableNights) with provider measurements")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Zone Breakdown")
                    .font(.subheadline.bold())

                zoneRow(
                    label: "150–165 min",
                    zone: report.optimalZone,
                    color: .green
                )
                zoneRow(
                    label: ">165–<240 min",
                    zone: report.acceptableZone,
                    color: .blue
                )
                zoneRow(
                    label: "Outside window",
                    zone: report.nonCompliant,
                    color: .orange
                )
            }

            if report.optimalZone.averageTotalSleep != nil || report.acceptableZone.averageTotalSleep != nil {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sleep by timing group")
                        .font(.subheadline.bold())
                    sleepComparisonRow(label: "150–165 min", zone: report.optimalZone, color: .green)
                    sleepComparisonRow(label: ">165–<240 min", zone: report.acceptableZone, color: .blue)
                    sleepComparisonRow(label: "Outside window", zone: report.nonCompliant, color: .orange)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private var complianceGauge: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 6)
            Circle()
                .trim(from: 0, to: report.complianceRate)
                .stroke(complianceColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(report.complianceRate * 100))")
                    .font(.system(.title3, design: .rounded).bold())
                Text("%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 60, height: 60)
    }

    private var intervalChangeText: String {
        switch report.recentTrend {
        case .improving(let delta): return String(format: "Recent interval change: −%.0f min", delta)
        case .worsening(let delta): return String(format: "Recent interval change: +%.0f min", delta)
        case .stable: return "Recent interval change: within \(Int(DoseEffectivenessCalculator.trendStableThreshold)) min"
        case nil: return "Recent interval change: needs 4 recorded pairs"
        }
    }

    private var complianceColor: Color {
        .blue
    }

    private func zoneRow(label: String, zone: DoseEffectivenessReport.ZoneSummary, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
            Spacer()
            Text("\(zone.count) night\(zone.count == 1 ? "" : "s")")
                .font(.caption.bold())
                .foregroundColor(color)
            if let averageInterval = zone.averageInterval {
                Text("avg \(fmt.string(from: averageInterval))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func sleepComparisonRow(label: String, zone: DoseEffectivenessReport.ZoneSummary, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption)
                .frame(width: 80, alignment: .leading)
                .foregroundColor(color)

            if let sleep = zone.averageTotalSleep {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sleep")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(formatHM(sleep))
                        .font(.caption.bold())
                }
            }

            if let deep = zone.averageDeepSleep {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Deep")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(formatHM(deep))
                        .font(.caption.bold())
                }
            }

            if let recovery = zone.averageRecovery {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recovery")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("\(Int(recovery))%")
                        .font(.caption.bold())
                }
            }

            if let hrv = zone.averageHRV {
                VStack(alignment: .leading, spacing: 1) {
                    Text("HRV")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("\(Int(hrv))ms")
                        .font(.caption.bold())
                }
            }

            Spacer()
        }
    }

    private func formatHM(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }
}
