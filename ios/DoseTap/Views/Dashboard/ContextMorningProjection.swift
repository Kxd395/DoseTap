import Foundation
import DoseCore

enum ContextMorningMetric: String, CaseIterable, Identifiable {
    case mainSleep = "Main sleep", postDose2 = "Sleep after D2", spacing = "D1–D2 spacing"
    case quality = "Sleep quality", grogginess = "Grogginess", sleepInertia = "Sleep inertia"
    case clarity = "Mental clarity", stress = "Morning stress", recovery = "Feeling rested", symptoms = "Physical symptoms"
    var id: String { rawValue }
    var duration: Bool { [.mainSleep, .postDose2, .spacing].contains(self) }
}
enum ContextMorningGrouping: String, CaseIterable, Identifiable {
    case dayDemand = "Reported following day", workPhase = "Reviewed work phase", dose2Wake = "Dose 2 wake method"
    case finalWakeMethod = "Final-wake method", food = "Last food", foodTiming = "Food → D1 timing"
    case caffeineMass = "Verified caffeine mass", caffeineTiming = "Caffeine → D1 timing"
    case pain = "Pre-sleep pain", stress = "Pre-sleep stress", regimen = "Recorded context period", sleepDuration = "Main-sleep duration"
    var id: String { rawValue }
}

enum ContextMorningProjection {
    static func observation(_ night: DashboardNightAggregate, metric: ContextMorningMetric, grouping: ContextMorningGrouping,
                            source: DashboardSleepSource, freshness: DashboardSleepMetricProjection.Freshness,
                            work: WorkPhaseResult?, asOf: Date) -> ContextOutcomeObservation {
        let diary = night.outcomeReadFailed || night.outcome?.validationError(now: asOf) != nil ? nil : night.outcome
        let pre = night.preSleepLog.flatMap { log -> PreSleepLogAnswers? in
            guard log.sessionId == night.sessionID, log.completionState == "complete",
                  let time = AppFormatters.parseISO8601Flexible(log.createdAtUtc), time <= asOf else { return nil }
            return log.answers
        }
        let morning = night.morningCheckIn.flatMap { record -> StoredMorningCheckIn? in
            record.sessionId == night.sessionID && record.sessionDate == night.sessionDate
                && record.timestamp.timeIntervalSince1970.isFinite && record.timestamp <= asOf ? record : nil
        }
        func elapsed(_ start: Date?, _ end: Date?) -> String? {
            guard let start, let end, start <= asOf, end <= asOf, end >= start,
                  start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite else { return nil }
            return ((end.timeIntervalSince(start) / 60).formatted(.number.precision(.fractionLength(0...2)))) + " min"
        }
        let context: String?
        switch grouping {
        case .dayDemand:
            context = diary?.dayType == .workday ? "Reported workday" : diary?.dayType == .dayOff ? "Reported day off" : nil
        case .workPhase: context = work.flatMap { $0.phase == .unknown ? nil : $0.phase.rawValue }
        case .dose2Wake: context = night.effectiveWakeMethod == .unknown ? nil : night.effectiveWakeMethod.rawValue
        case .finalWakeMethod: context = nil
        case .food: context = pre?.lastFood?.highFat.map { $0 ? "Reported high-fat food" : "Reported not high-fat" }
        case .foodTiming: context = elapsed(pre?.lastFood?.finishedAt, night.dose1Time)
        case .caffeineTiming: context = elapsed(pre?.caffeineLastIntakeAt, night.dose1Time)
        case .caffeineMass:
            if let amount = pre?.caffeineAmounts, amount.validationError == nil,
               [.userReported, .labelReported].contains(amount.source), let mg = amount.lastCaffeineMg {
                context = mg.formatted(.number.precision(.fractionLength(0...2))) + " mg · " + amount.source.rawValue
            } else { context = nil }
        case .pain: context = pre?.bodyPain?.rawValue
        case .stress: context = pre?.stressLevel.flatMap { (1...5).contains($0) ? "\($0) / 5" : nil }
        case .regimen: context = night.contextStratum(for: source).status == .documentedReference ? night.contextStratum(for: source).label : nil
        case .sleepDuration:
            let projection = DosePatternPresentation.sleepProjection(night, source: source, outcome: .mainSleep, freshness: freshness)
            context = projection.summaryValue().map { $0.formatted(.number.precision(.fractionLength(0...2))) + " min · " + source.rawValue }
        }
        var value: Double?, category: String?, time: Date?
        var state = DashboardMetricState.unavailable, reason = "No usable saved answer"
        var evidenceSource = "Saved morning diary; assessment time not collected"
        if metric == .mainSleep || metric == .postDose2 {
            let projection = DosePatternPresentation.sleepProjection(night, source: source,
                outcome: metric == .mainSleep ? .mainSleep : .postDose2, freshness: freshness)
            value = projection.metric.value; state = projection.metric.state
            reason = projection.metric.reason + "; " + projection.definition.rawValue + "; snapshot " + freshness.rawValue
            if let covered = projection.coveredMinutes, let interval = projection.intervalMinutes {
                reason += "; covered \(covered) of \(interval) minutes; unmeasured \(projection.unmeasuredMinutes ?? 0)"
            }
            evidenceSource = source.rawValue
            if source == .appleHealth { time = metric == .mainSleep ? night.healthSummary?.sleepOnset : night.dose2Time }
        } else if metric == .spacing {
            value = night.dosePattern.interval.value; state = night.dosePattern.interval.state
            reason = night.dosePattern.interval.reason; evidenceSource = "Reported administration occurrences"; time = night.dose1Time
        } else if let morning {
            switch metric {
            case .quality: if morning.sleepQuality.isFinite && (1...5).contains(morning.sleepQuality) { category = "\(morning.sleepQuality.formatted()) / 5" }
            case .grogginess: category = morning.grogginess
            case .sleepInertia: category = morning.sleepInertiaDuration
            case .clarity: if (1...5).contains(morning.mentalClarity) { category = "\(morning.mentalClarity) / 5" }
            case .stress: category = morning.stressLevel.flatMap { (1...5).contains($0) ? "\($0) / 5" : nil }
            case .recovery: category = morning.feelRested
            case .symptoms: category = morning.hasPhysicalSymptoms ? "Saved yes" : "Saved no"
            default: break
            }
            if category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                state = .needsReview; reason = "Original saved answer; legacy default/freshness confirmation unavailable"
            }
        }
        if night.identityNeedsReview || night.sessionID == nil { state = .needsReview; reason = "Session identity unresolved" }
        let stratum = night.contextStratum(for: source)
        return .init(id: night.id, sessionID: night.sessionID ?? "", treatmentDate: night.sessionDate, occurredAt: time,
            context: context, compatibilityStratum: stratum.status == .documentedReference ? stratum.id : nil,
            source: evidenceSource, unit: metric.duration ? "minutes" : "original category", value: value, category: category,
            state: state, reason: reason,
            relationship: metric.duration ? "Within preceding main-sleep session; context may be recorded before or afterward" : "Following waking day; context association does not establish temporal prediction")
    }
}

extension DashboardAnalyticsModel {
    func contextOutcomeReport(metric: ContextMorningMetric, grouping: ContextMorningGrouping) -> ContextOutcomeComparison {
        let freshness: DashboardSleepMetricProjection.Freshness = providerSnapshotIsCurrent(sleepSource == .appleHealth ? .health : .whoop) ? .current : .stale
        let rows = visibleInspectionNights.map { ContextMorningProjection.observation($0, metric: metric, grouping: grouping,
            source: sleepSource, freshness: freshness, work: workClassification(for: $0.id), asOf: reportingAsOf) }
        let filters = rangeDescription + "; context=" + grouping.rawValue + "; dose=" + (inspection.dosePatternFilter?.rawValue ?? "all")
            + "; work=" + (inspection.workPhaseFilter?.rawValue ?? "all") + "; basis=" + inspection.workContextBasis.rawValue
            + "; period=" + (inspection.contextStratumID ?? "all")
        return .init(observations: rows, asOf: reportingAsOf, timeZoneID: reportingTimeZone.identifier,
            filterDescription: filters, metric: metric.rawValue, includePartial: inspection.includePartialMetrics)
    }
}
