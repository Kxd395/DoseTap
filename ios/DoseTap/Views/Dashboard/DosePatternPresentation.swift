import SwiftUI
import Charts
import DoseCore

enum DosePatternDisplayMode: String, CaseIterable, Identifiable {
    case byDate = "By date", compare = "Compare", paired = "Paired intervals"
    var id: String { rawValue }
}

enum DosePatternSleepOutcome: String, CaseIterable, Identifiable {
    case mainSleep = "Total main sleep", postDose2 = "Sleep after Dose 2"
    var id: String { rawValue }
}

enum DosePatternPresentation {
    private struct AmountMetadata: Decodable {
        let amountMg: Double?
        enum CodingKeys: String, CodingKey { case amountMg = "amount_mg" }
    }
    static func recordedAmountMg(_ event: StoredDoseEvent) -> Double? {
        guard CanonicalDoseEventType(canonicalizing: event.eventType)?.countsAsTakenDose == true,
              let data = event.metadata?.data(using: .utf8), let amount = try? JSONDecoder().decode(AmountMetadata.self, from: data).amountMg,
              amount.isFinite, amount > 0 else { return nil }
        return amount
    }
    static func sleepValue(_ night: DashboardNightAggregate, source: DashboardSleepSource,
                           outcome: DosePatternSleepOutcome, freshness: DashboardSleepMetricProjection.Freshness = .current) -> Double? {
        sleepProjection(night, source: source, outcome: outcome, freshness: freshness).metric.value
    }

    static func sleepMetric(_ night: DashboardNightAggregate, source: DashboardSleepSource,
                            outcome: DosePatternSleepOutcome) -> DashboardMetricValue {
        sleepProjection(night, source: source, outcome: outcome).metric
    }

    static func sleepProjection(_ night: DashboardNightAggregate, source: DashboardSleepSource,
                                outcome: DosePatternSleepOutcome, freshness: DashboardSleepMetricProjection.Freshness = .current) -> DashboardSleepMetricProjection {
        let provider: DashboardSleepMetricProjection.Source = source == .appleHealth ? .appleHealth : .whoop
        if outcome == .mainSleep {
            return .providerEpisode(totalMinutes: source == .appleHealth ? night.appleHealthSleepMinutes : night.whoopSleepMinutes,
                                    source: provider, freshness: freshness)
        }
        let basis: DashboardSleepMetricProjection.BoundaryBasis = source == .whoop ? .unresolved
            : night.outcome?.finalWakeAt != nil ? .reportedFinalAwakening
            : night.healthSummary?.finalWake != nil ? .providerLastObservedSleepEnd : .unresolved
        return .afterDose2(pattern: night.dosePattern, estimate: night.postDoseSleep, source: provider,
                           freshness: freshness, boundaryBasis: basis, dose2At: night.dose2Time,
                           endpointAt: night.outcome?.finalWakeAt ?? night.healthSummary?.finalWake)
    }

    static func coverage(_ night: DashboardNightAggregate, source: DashboardSleepSource = .appleHealth,
                         outcome: DosePatternSleepOutcome) -> String {
        guard outcome == .postDose2 else { return "Provider main-episode aggregate; complete reviewed-night coverage is not established." }
        guard source == .appleHealth else { return "WHOOP has no compatible post-dose interval coverage in this view." }
        let projection = sleepProjection(night, source: source, outcome: outcome)
        guard projection.coveredMinutes != nil else { return "No usable measured coverage for the selected post-D2 window." }
        return "Covered \(minutes(projection.coveredMinutes)) of \(minutes(projection.intervalMinutes)); "
            + "unmeasured \(minutes(projection.unmeasuredMinutes))."
    }

    static func symbol(_ pattern: DashboardDosePattern.Pattern) -> BasicChartSymbolShape {
        switch pattern {
        case .twoReported: return .circle
        case .singlePlanned, .singleOmitted, .singleUnknownPlan: return .square
        case .noneReported: return .triangle
        case .incomplete, .needsReview, .inProgress: return .diamond
        }
    }

    static func minutes(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " min" } ?? "Unavailable"
    }

    static func description(_ night: DashboardNightAggregate, sleep: Double?) -> String {
        let pattern = night.dosePattern
        return "\(night.sessionDate); \(pattern.pattern.label); sleep \(minutes(sleep)); "
            + "D1–D2 \(minutes(pattern.interval.value)), \(pattern.interval.state.rawValue): "
            + pattern.interval.reason.replacingOccurrences(of: "_", with: " ")
            + "; count \(pattern.reportedCount), \(pattern.countComplete ? "complete patient report" : "not confirmed complete")"
    }

    static func sleepDescription(_ night: DashboardNightAggregate, source: DashboardSleepSource,
                                 outcome: DosePatternSleepOutcome, freshness: DashboardSleepMetricProjection.Freshness = .current) -> String {
        let projection = sleepProjection(night, source: source, outcome: outcome, freshness: freshness)
        let metric = projection.metric
        return "\(minutes(metric.value)); \(metric.state.rawValue): \(metric.reason.replacingOccurrences(of: "_", with: " ")). "
            + "Provider snapshot: \(projection.freshness.rawValue); endpoint policy: \(projection.boundaryBasis.rawValue). "
            + coverage(night, source: source, outcome: outcome)
    }

    static func summary(_ summary: DiaryMetricSummary, total: Int) -> String {
        "\(summary.count)/\(total) with sleep; median \(minutes(summary.median)); "
            + "middle 50% \(minutes(summary.lowerQuartile))–\(minutes(summary.upperQuartile))"
    }
}
