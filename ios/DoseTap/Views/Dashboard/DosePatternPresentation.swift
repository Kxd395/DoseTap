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
    @MainActor
    static func csv(model: DashboardAnalyticsModel, outcome: DosePatternSleepOutcome) -> String? {
        guard !model.isLoading, model.doseReviewReadReady, model.contextReadReady, model.workContextReadReady,
              model.inspectionFilterIssue == nil, model.currentReportWindow != nil, model.workInspectionAsOf == model.reportingAsOf,
              model.reportingAsOf.timeIntervalSince1970.isFinite else { return nil }
        struct Administration: Encodable { let id: String; let type: String; let occurredAtEpoch: Double; let amountMg: Double? }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        func number(_ value: Double?) -> String { value.map { String($0) } ?? "" }
        let freshness: DashboardSleepMetricProjection.Freshness = model.providerSnapshotIsCurrent(model.sleepSource == .appleHealth ? .health : .whoop) ? .current : .stale
        let rows = model.visibleInspectionNights.sorted { $0.sessionDate == $1.sessionDate ? $0.id < $1.id : $0.sessionDate < $1.sessionDate }
        guard !rows.isEmpty else { return nil }
        let projections = rows.map { sleepProjection($0, source: model.sleepSource, outcome: outcome, freshness: freshness) }
        let numericCount = projections.filter { $0.metric.value != nil }.count
        let partialCount = projections.filter { $0.metric.state == .partial && $0.metric.value != nil }.count
        let header = ["observation_id", "treatment_date", "source", "definition", "boundary_basis", "derivation_version", "as_of_epoch", "timezone", "range",
            "dose_pattern_filter", "work_phase_filter", "work_basis", "context_filter", "selected_observation_id", "include_partial", "selected_rows", "numeric_sleep_rows", "partial_sleep_rows",
            "pattern", "reported_count", "count_complete", "confirmed_count", "historical_plan_count", "second_not_taken", "review_revision", "review_recorded_at_epoch", "review_reason", "administrations_json", "json_date_encoding",
            "sleep_minutes", "sleep_state", "sleep_reason", "freshness", "covered_minutes", "interval_minutes", "unmeasured_minutes", "spacing_minutes", "spacing_state", "spacing_reason",
            "context_id", "context_status", "context_label", "context_source_ids_json", "context_annotations_json", "work_phase", "work_detail", "summary_included", "provider_association"]
        do {
        let body = try zip(rows, projections).map { night, projection in
            let context = night.contextStratum(for: model.sleepSource), pattern = night.dosePattern
            let administrations = night.doseEvents.filter { CanonicalDoseEventType(canonicalizing: $0.eventType)?.countsAsTakenDose == true }
                .map { Administration(id: $0.id, type: $0.eventType, occurredAtEpoch: $0.timestamp.timeIntervalSince1970, amountMg: recordedAmountMg($0)) }
            let work = model.workClassification(for: night.id)
            let included = context.status == .documentedReference && projection.summaryValue(includePartial: model.inspection.includePartialMetrics) != nil
            return ReportCSV.row([night.id, night.sessionDate, projection.source.rawValue, projection.definition.rawValue, projection.boundaryBasis.rawValue,
                projection.derivationVersion, String(model.reportingAsOf.timeIntervalSince1970), model.reportingTimeZone.identifier, model.rangeDescription,
                model.inspection.dosePatternFilter?.rawValue ?? "All", model.inspection.workPhaseFilter?.rawValue ?? "All", model.inspection.workContextBasis.rawValue,
                model.inspection.contextStratumID ?? "All", model.inspection.selectedObservationID ?? "", String(model.inspection.includePartialMetrics), String(rows.count), String(numericCount), String(partialCount),
                pattern.pattern.rawValue, String(pattern.reportedCount), String(pattern.countComplete), night.doseReview?.confirmedCount.map(String.init) ?? "",
                night.doseReview?.historicalPlanCount.map(String.init) ?? "", night.doseReview?.secondNotTaken.map(String.init) ?? "",
                night.doseReview?.revisionID.uuidString ?? "", number(night.doseReview?.recordedAt.timeIntervalSince1970), night.doseReview?.reason ?? "", try json(administrations), "unix_seconds", number(projection.metric.value), projection.metric.state.rawValue, projection.metric.reason,
                projection.freshness.rawValue, number(projection.coveredMinutes), number(projection.intervalMinutes), number(projection.unmeasuredMinutes),
                number(pattern.interval.value), pattern.interval.state.rawValue, pattern.interval.reason, context.id, context.status.rawValue, context.label,
                try json(context.sourceRecordIDs), try json(night.contextAnnotations), work?.phase.rawValue ?? "unknown", work?.detail ?? "No reviewed exact association", String(included), night.providerAssociation])
        }
        return ([ReportCSV.row(header)] + body).joined(separator: "\r\n") + "\r\n"
        } catch { return nil }
    }
    static func comparisonKey(pattern: DashboardDosePattern.Pattern, context: DashboardContextStratum,
                              projection: DashboardSleepMetricProjection) -> String {
        [pattern.rawValue, context.id, projection.source.rawValue, projection.definition.rawValue,
         projection.boundaryBasis.rawValue, projection.derivationVersion]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }
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
