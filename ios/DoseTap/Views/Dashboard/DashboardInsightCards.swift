import SwiftUI
import Charts
import DoseCore

struct DashboardLifestyleFactorsCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lifestyle Factors")
                .font(.headline)

            if model.averageStressLevel != nil || model.caffeineRate != nil {
                if let stress = model.averageStressLevel {
                    metricRow(title: "Avg Pre-Sleep Stress", value: String(format: "%.1f / 5", stress), color: stressColor(stress))
                }
                if let rate = model.highPreSleepStressRate {
                    metricRow(title: "High-Stress Bedtimes", value: String(format: "%.0f%%", rate), color: rate >= 50 ? .orange : .secondary)
                }
                if let topDriver = model.topPreSleepStressDriver {
                    metricRow(title: "Top Bedtime Stressor", value: topDriver.displayText)
                }
                factorRow(title: "Caffeine", rate: model.caffeineRate, impact: model.sleepQualityByCaffeine)
                factorRow(title: "Alcohol", rate: model.alcoholRate, impact: model.sleepQualityByAlcohol)
                factorRow(title: "Screens in Bed", rate: model.screenTimeRate, impact: model.sleepQualityByScreens)

                if let exercise = model.exerciseRate {
                    metricRow(title: "Exercise Days", value: String(format: "%.0f%%", exercise), color: .green)
                }
                if let meals = model.lateMealRate {
                    metricRow(title: "Late Meals", value: String(format: "%.0f%%", meals), color: meals > 40 ? .orange : .secondary)
                }
            } else {
                Text("Complete pre-sleep logs to see lifestyle impact.")
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

    private func metricRow(title: String, value: String, color: Color = .secondary) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
    }

    @ViewBuilder
    private func factorRow(title: String, rate: Double?, impact: (with: Double?, without: Double?)) -> some View {
        if let rate {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: "%.0f%%", rate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                if let withImpact = impact.with, let withoutImpact = impact.without {
                    let diff = withImpact - withoutImpact
                    Text(diff >= 0 ? "+\(String(format: "%.1f", diff))" : String(format: "%.1f", diff))
                        .font(.caption2.bold())
                        .foregroundColor(diff >= 0 ? .green : .orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill((diff >= 0 ? Color.green : Color.orange).opacity(0.15)))
                }
            }
        }
    }

    private func stressColor(_ level: Double) -> Color {
        if level <= 2 { return .green }
        if level < 4 { return .orange }
        return .red
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
                }
                if let dreamRecall = model.dreamRecallRate {
                    metricRow(title: "Dream Recall", value: String(format: "%.0f%%", dreamRecall))
                }
                if let stress = model.averageMorningStressLevel {
                    metricRow(title: "Avg Wake Stress", value: String(format: "%.1f / 5", stress), color: stressColor(stress))
                }
                if let delta = model.averageStressDeltaToWake {
                    metricRow(
                        title: "Wake vs Bedtime",
                        value: String(format: "%+.1f pts", delta),
                        color: delta > 0.15 ? .orange : (delta < -0.15 ? .green : .secondary)
                    )
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
                        metricRow(title: "Anxiety Reported", value: String(format: "%.0f%%", percent), color: percent > 50 ? .orange : .secondary)
                    }
                }
                if let rate = model.highMorningStressRate {
                    metricRow(title: "High Wake Stress", value: String(format: "%.0f%%", rate), color: rate >= 50 ? .orange : .secondary)
                }
                if let topDriver = model.topMorningStressDriver {
                    metricRow(title: "Top Wake Stressor", value: topDriver.displayText)
                }
                if let worseRate = model.worseByWakeStressRate {
                    metricRow(title: "Stress Worse By Wake", value: String(format: "%.0f%%", worseRate), color: worseRate >= 50 ? .red : .orange)
                }

                if !model.grogginessDistribution.isEmpty {
                    let severe = (model.grogginessDistribution["severe"] ?? 0) + (model.grogginessDistribution["moderate"] ?? 0)
                    let total = model.grogginessDistribution.values.reduce(0, +)
                    if total > 0 {
                        let percent = (Double(severe) / Double(total)) * 100
                        metricRow(title: "Moderate+ Grogginess", value: String(format: "%.0f%%", percent), color: percent > 50 ? .orange : .secondary)
                    }
                }

                if let narcoRate = model.narcolepsySymptomRate, narcoRate > 0 {
                    Divider()
                    Text("Narcolepsy Symptoms")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
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

    private func metricRow(title: String, value: String, color: Color = .secondary) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
    }

    private func stressColor(_ level: Double) -> Color {
        if level <= 2 { return .green }
        if level < 4 { return .orange }
        return .red
    }

    private func symptomRow(title: String, count: Int) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.orange)
            Text(title).font(.caption)
            Spacer()
            Text("\(count) night\(count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
                .foregroundColor(.orange)
        }
    }
}

struct DashboardStressTrendsCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    private struct StressSeriesPoint: Identifiable {
        let id = UUID()
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
                    .interpolationMethod(.catmullRom)

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
                Text("Impact")
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
                        color: rate >= 50 ? .orange : .secondary
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
        guard let high, let lower else { return .secondary }
        let delta = high - lower
        if abs(delta) < 0.15 { return .secondary }
        if preferHigher {
            return delta >= 0 ? .green : .orange
        }
        return delta <= 0 ? .green : .orange
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
            Text("This is the complete metric surface currently modeled for dashboarding.")
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
                Label("Dose Effectiveness", systemImage: "chart.bar.doc.horizontal")
                    .font(.headline)
                Spacer()
                trendBadge
            }

            Text("How your dose timing correlates with sleep quality")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            HStack(spacing: 16) {
                complianceGauge
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(report.totalNights) nights analyzed")
                        .font(.subheadline)
                    Text("\(report.pairableNights) with sleep data")
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
                    label: "Optimal (150-165m)",
                    zone: report.optimalZone,
                    color: .green
                )
                zoneRow(
                    label: "Acceptable (166-240m)",
                    zone: report.acceptableZone,
                    color: .blue
                )
                zoneRow(
                    label: "Non-compliant",
                    zone: report.nonCompliant,
                    color: .orange
                )
            }

            if report.optimalZone.averageTotalSleep != nil || report.acceptableZone.averageTotalSleep != nil {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sleep by Zone")
                        .font(.subheadline.bold())
                    sleepComparisonRow(label: "Optimal", zone: report.optimalZone, color: .green)
                    sleepComparisonRow(label: "Acceptable", zone: report.acceptableZone, color: .blue)
                    sleepComparisonRow(label: "Non-compliant", zone: report.nonCompliant, color: .orange)
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

    private var complianceColor: Color {
        switch report.complianceRate {
        case 0.8...: return .green
        case 0.6...: return .blue
        case 0.4...: return .orange
        default: return .red
        }
    }

    @ViewBuilder
    private var trendBadge: some View {
        if let trend = report.recentTrend {
            HStack(spacing: 4) {
                switch trend {
                case .improving(let delta):
                    Image(systemName: "arrow.down.right")
                        .foregroundColor(.green)
                    Text(String(format: "-%.0fm", delta))
                        .foregroundColor(.green)
                case .worsening(let delta):
                    Image(systemName: "arrow.up.right")
                        .foregroundColor(.orange)
                    Text(String(format: "+%.0fm", delta))
                        .foregroundColor(.orange)
                case .stable:
                    Image(systemName: "equal")
                        .foregroundColor(.secondary)
                    Text("Stable")
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
        }
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
