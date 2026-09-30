import Foundation

/// Immutable physician review of the exact read-only companion source and selection.
public struct DashboardCompanionPhysicianReport: Sendable {
    public static let version = "companion-physician.v1"
    public let preview: PhysicianReportSnapshot
    private let source: CloudDashboardSnapshot
    private let nightIDs: [String]
    private let inspection: DashboardInspectionState
    private let filterDescription: String

    public enum Failure: Error, LocalizedError {
        case missingPeriod, mixedSource, invalidSelection, invalidContext, invalidDaytime
        public var errorDescription: String? {
            switch self {
            case .missingPeriod: return "Choose a valid report period before preparing the physician review."
            case .mixedSource: return "The received source and report do not match. Refresh the dashboard before preparing a review."
            case .invalidSelection: return "The selected night records or report cutoff changed. Refresh the selection before preparing a review."
            case .invalidDaytime: return "The independent daytime or nap records could not be validated. Refresh the phone report before preparing this review."
            case .invalidContext: return "The received context records could not be validated. Refresh the report from the phone before preparing a physician review."
            }
        }
    }
    public init(snapshot: CloudDashboardSnapshot, report: DashboardCompanionProjection,
                nights: [DashboardCompanionProjection.Night], period: PhysicianReportPeriod?,
                inspection: DashboardInspectionState, filterDescription: String, appVersion: String) throws {
        guard let period else { throw Failure.missingPeriod }
        try period.validate()
        guard snapshot == report.sourceSnapshot, snapshot.sourceID == report.sourceID,
              snapshot.sequence == report.sequence, snapshot.capturedAt == report.capturedAt else { throw Failure.mixedSource }
        guard period.capturedAt == snapshot.capturedAt, !filterDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, filterDescription.count <= 3500,
              Set(nights.map(\.id)).count == nights.count else { throw Failure.invalidSelection }
        let canonical = Dictionary(uniqueKeysWithValues: report.nights.map { ($0.id, $0) })
        for night in nights {
            guard let current = canonical[night.id], current.sessionID == night.sessionID,
                  current.treatmentDate == night.treatmentDate, current.pattern == night.pattern,
                  current.administrations == night.administrations, current.sourceRecordIDs == night.sourceRecordIDs,
                  current.reviewRevisionID == night.reviewRevisionID, current.identityResolved == night.identityResolved else { throw Failure.invalidSelection }
        }
        source = snapshot; nightIDs = nights.map(\.id).sorted(); self.inspection = inspection
        self.filterDescription = filterDescription
        let evidence: DashboardCompanionContextEvidence
        do { evidence = try report.workContextEvidence() } catch { throw Failure.invalidContext }
        let daytime: DashboardCompanionDaytime
        do { daytime = try .init(snapshot: snapshot, period: period) } catch { throw Failure.invalidDaytime }
        let work = report.workClassifications(basis: inspection.workContextBasis)
        var observations: [PhysicianReportObservation] = []
        var contexts: [PhysicianReportContext] = []
        let selected = "Selected nights: \(nightIDs.count). Shared filters: \(filterDescription)"
        let provider = "Sleep source: transferred Apple Health evidence. WHOOP sleep/recovery metrics are unavailable in this received reporting format; missing source data is not zero."
        let scope = "Independent daytime observations use their own occurrence times within this period. Night filters do not associate them with selected nights. Daytime panel origin/protocol filters are not inherited. Daytime work context uses confirmed occurrence evidence independently of the night work-basis selection."
        contexts.append(try Self.context(id: "companion-source", title: "Captured source and selection", source: "Received DoseTap report", definitionVersion: Self.version,
            lines: ["Source \(snapshot.sourceID), sequence \(snapshot.sequence), captured \(snapshot.capturedAt.timeIntervalSince1970) seconds since 1970.", selected,
                "Dose pattern: \(inspection.dosePatternFilter?.rawValue ?? "all"); work phase: \(inspection.workPhaseFilter?.rawValue ?? "all"); work basis: \(inspection.workContextBasis.rawValue); context: \(inspection.contextStratumID ?? "all").",
                "Inspected observation: \(inspection.selectedObservationID ?? "none"); selected observation is inspection state, not an additional report filter.", scope, provider, "\(report.unassignedIdentityRowCount) unassigned source rows remain outside night metrics. Phone visit notes and saved reports are not transported."], recordIDs: nightIDs))
        for section in snapshot.sections {
            contexts.append(try Self.context(id: "source-coverage:" + section.dataset.rawValue, title: "Source coverage: " + section.dataset.rawValue,
                source: "Received DoseTap report", definitionVersion: Self.version,
                lines: [section.notCollectedBySource == true ? "Not collected by the source." : section.unavailableReason.map { "Unavailable: \($0)" }
                    ?? "\(section.rowCount ?? 0) transported source rows; this is not a count of eligible observations."], recordIDs: []))
        }
        for night in nights {
            let stratum = evidence.stratum(for: night, report: report)
            let comparison = night.pattern.pattern.label + " | " + stratum.label + " [" + stratum.id + "]"
            let at = night.administrations.compactMap(\.occurredAt).min() ?? report.episode(for: night)?.sleepOnset
            let identity = "Treatment date \(night.treatmentDate); observation \(night.id); \(night.pattern.pattern.label)."
            func append(_ name: String, _ metric: DashboardMetricValue, observedAt: Date?, source: String, version: String, detail: String, recordIDs: [String]) {
                observations.append(.init(id: night.id + ":" + name, observedAt: observedAt, metricID: name, value: metric.value,
                    state: PhysicianMetricState(rawValue: metric.state.rawValue) ?? .needsReview, unit: metric.unit,
                    source: source, definitionVersion: version, detail: identity + " " + detail,
                    recordIDs: recordIDs, requiresReview: metric.state == .needsReview, comparisonLabel: comparison))
            }
            append("dose.interval", night.pattern.interval, observedAt: night.administrations.first { $0.slot == 1 }?.occurredAt, source: "Patient-recorded administrations", version: DashboardDosePattern.version,
                detail: night.pattern.interval.reason, recordIDs: night.sourceRecordIDs)
            let count = DashboardMetricValue(value: night.pattern.countComplete && night.pattern.pattern != .needsReview ? Double(night.pattern.reportedCount) : nil,
                state: night.pattern.pattern == .needsReview ? .needsReview : night.pattern.countComplete ? .available : .unavailable,
                reason: night.pattern.countComplete ? "confirmed_reported_count" : "count_completion_unknown", unit: "doses")
            append("dose.reported-count", count, observedAt: at, source: "Patient-recorded dose history", version: DashboardDosePattern.version,
                detail: count.reason, recordIDs: night.sourceRecordIDs + (night.reviewRevisionID.map { [$0.uuidString] } ?? []))
            for definition in [DashboardSleepMetricProjection.Definition.mainProviderEpisode, .observedAfterDose2] {
                let metric = report.sleepMetric(for: night, definition: definition)
                let coverage = "Covered \(metric.coveredMinutes.map(String.init(describing:)) ?? "unknown") / interval \(metric.intervalMinutes.map(String.init(describing:)) ?? "unknown") minutes; unmeasured \(metric.unmeasuredMinutes.map(String.init(describing:)) ?? "unknown")."
                let occurrence = definition == .mainProviderEpisode ? report.episode(for: night)?.sleepOnset : night.administrations.first { $0.slot == 2 }?.occurredAt
                append("sleep." + definition.rawValue, metric.metric, observedAt: occurrence, source: metric.source.rawValue, version: metric.derivationVersion,
                    detail: "\(metric.metric.reason); boundary \(metric.boundaryBasis.rawValue); freshness \(metric.freshness.rawValue). \(coverage)",
                    recordIDs: night.sourceRecordIDs + (report.episode(for: night).map { [$0.episodeID] } ?? []))
            }
            if let outcome = report.outcome(for: night) {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                let detail = String(decoding: try encoder.encode(outcome.answers), as: UTF8.self)
                observations.append(.init(id: "night-outcome:" + outcome.id, observedAt: outcome.answers.finalWakeAt,
                    metricID: "night.outcome.source", value: nil, state: .notApplicable, unit: "source detail",
                    source: "Patient-reported night outcome", definitionVersion: "night_outcome.v1",
                    detail: identity + " Recorded at \(outcome.recordedAt.timeIntervalSince1970) seconds since 1970. " + detail,
                    recordIDs: ["checkin_submissions:" + outcome.id], requiresReview: true, detailOnly: true))
            }
            contexts.append(try Self.context(id: "night-context:" + night.id, title: identity, source: "Received DoseTap context", definitionVersion: Self.version,
                lines: [stratum.label, "Context identity: \(stratum.id)", "Work phase (\(inspection.workContextBasis.rawValue)): \(work[night.id]?.phase.rawValue ?? "unknown")"],
                recordIDs: stratum.sourceRecordIDs + night.sourceRecordIDs))
        }
        for annotation in evidence.timeline.annotations(from: period.start, to: period.endExclusive, includeBaseline: true) {
            contexts.append(try Self.context(id: "annotation:" + annotation.id, title: annotation.title, source: annotation.source,
                definitionVersion: annotation.definitionVersion, lines: [annotation.detail,
                    "Effective time: \(annotation.effectiveAt.map { String($0.timeIntervalSince1970) } ?? "unknown"); observed time: \(annotation.observedAt.timeIntervalSince1970) (seconds since 1970)."], recordIDs: annotation.sourceRecordIDs))
        }
        let samplingGroups = Dictionary(uniqueKeysWithValues: daytime.analysis.groups.flatMap { group in group.observationIDs.map { ($0, group) } })
        for entry in daytime.observations {
            let group = samplingGroups[entry.id], context = daytime.contexts[entry.id]
            let compatibility = "\(entry.origin.title); \(group?.clockBandLabel ?? "unknown time band"); \(entry.setting.rawValue); \(entry.timeZoneIdentifier); protocol \(entry.samplingProtocolID?.uuidString ?? "none"); \(context?.label ?? "unknown context") [\(group?.id ?? entry.id.uuidString)]"
            observations.append(.init(id: "daytime-checkin:" + entry.revisionID.uuidString, observedAt: entry.assessedAt,
                metricID: entry.instrumentID, value: entry.response.map(Double.init), state: entry.status == .answered ? .available : .unavailable,
                unit: "custom 0–10", source: "Patient-reported daytime check-in", definitionVersion: entry.contentVersion,
                detail: try entry.encoded(), recordIDs: ["daytime_checkins:" + entry.revisionID.uuidString] + (context?.sourceRecordIDs ?? []), comparisonLabel: compatibility))
        }
        for entry in daytime.events {
            observations.append(.init(id: "daytime-event:" + entry.revisionID.uuidString, observedAt: entry.occurredAt,
                metricID: "daytime.event." + entry.kind.rawValue, value: entry.kind == .unclear ? nil : 1, state: entry.kind == .unclear ? .needsReview : .available,
                unit: "reported event", source: "Patient-reported daytime event", definitionVersion: "daytime-event.v\(entry.version)",
                detail: try entry.encoded(), recordIDs: ["daytime_events:" + entry.revisionID.uuidString], requiresReview: true, detailOnly: true))
        }
        let analysis = daytime.analysis
        contexts.append(try Self.context(id: "daytime-coverage", title: "Independent daytime coverage", source: "Patient-reported daytime diary",
            definitionVersion: "daytime-analysis.v\(analysis.calculationVersion)", lines: [
                "\(analysis.answeredCount) answered observations on \(analysis.ratedCalendarDays)/\(analysis.calendarDays) calendar days.",
                "Event-review intervals cover \(analysis.fullyReviewedCalendarDays) complete and \(analysis.partiallyReviewedCalendarDays) partial calendar days; \(analysis.daysWithoutReviewedInterval) days have no reviewed interval.",
                "Reported unplanned sleep events: \(analysis.unplannedSleepEvents). This is a reported event count, not an all-day event-free denominator."]
                + analysis.groups.map { "\($0.origin.title), \($0.clockBandLabel), \($0.timeZoneIdentifier), protocol \($0.samplingProtocolLabel ?? "none"): \($0.answeredCount)/\($0.entryCount) answered, \($0.ratedDays) rated days." },
            recordIDs: daytime.observations.map { "daytime_checkins:" + $0.revisionID.uuidString }))
        let napDaysByID = Dictionary(grouping: daytime.napDays.flatMap { day in day.episodes.map { ($0.id, day) } }, by: { $0.0 })
        for nap in daytime.naps {
            let candidates = napDaysByID[nap.id] ?? []
            let day = candidates.count == 1 ? candidates.first?.1 : nil
            let needsReview = nap.sourceNeedsReview || candidates.count > 1 || day?.overlapIDs.contains(nap.id) == true || day?.unresolvedDuplicateIDs.contains(nap.id) == true
            let excludedDuplicate = day == nil && nap.duplicateOf != nil
            let amount = needsReview || excludedDuplicate ? nil : nap.estimatedSleepMinutes
            let detail = String(decoding: try JSONEncoder().encode(nap), as: UTF8.self)
            observations.append(.init(id: "nap:" + nap.id + ":" + nap.revision.uuidString, observedAt: nap.start ?? nap.end,
                metricID: "nap.patient-estimated-sleep", value: amount, state: excludedDuplicate ? .notApplicable : needsReview ? .needsReview : amount == nil ? .unavailable : .available,
                unit: "minutes", source: "Patient-reported nap", definitionVersion: "nap-diary.v1",
                detail: "Source JSON timestamps use seconds since 2001. Day-only entries remain unplaced. " + detail,
                recordIDs: ["nap_diary:" + nap.revision.uuidString] + nap.sourceEventIDs, requiresReview: needsReview, detailOnly: excludedDuplicate,
                comparisonLabel: "Intent: " + nap.intent.rawValue))
        }
        contexts.append(try Self.context(id: "nap-coverage", title: "Independent nap coverage", source: "Patient-reported nap history",
            definitionVersion: "nap-diary.v1", lines: ["\(daytime.naps.count) reported episodes. Day-only reports keep their original civil date and zone without an invented onset.",
                "Unreviewed days are unknown. Confirmed no-nap days remain day reviews and do not fabricate a midnight episode.",
                "Provider nap reconciliation is unavailable in this transferred copy; estimated sleep is patient-reported and timer elapsed time is not measured sleep."]
                + daytime.napDays.map { "\($0.day): \($0.completenessLabel); \($0.episodeCount) episodes, \($0.unavailableCount) durations unavailable/review." },
            recordIDs: daytime.naps.map { "nap_diary:" + $0.revision.uuidString }))
        if let issue = report.daytimeIssue {
            contexts.append(try Self.context(id: "daytime-unavailable", title: "Daytime source unavailable", source: "Received DoseTap report",
                definitionVersion: Self.version, lines: [issue, "Failed source reads are not an empty or symptom-free diary."], recordIDs: []))
        }
        if let issue = report.workIssue {
            contexts.append(try Self.context(id: "work-unavailable", title: "Work context unavailable", source: "Received DoseTap report",
                definitionVersion: Self.version, lines: [issue], recordIDs: []))
        }
        preview = try .init(period: period, observations: observations, notes: [], questions: [], appVersion: appVersion,
            generatedAt: snapshot.capturedAt, coverageDescription: selected + " " + provider + " " + scope + " Unknown occurrence times remain unplaced; treatment dates do not manufacture timestamps.",
            contexts: contexts, includePartialMetrics: inspection.includePartialMetrics)
    }
    public func matches(snapshot: CloudDashboardSnapshot, nights: [DashboardCompanionProjection.Night],
                        period: PhysicianReportPeriod?, inspection: DashboardInspectionState, filterDescription: String) -> Bool {
        source == snapshot && nightIDs == nights.map(\.id).sorted() && preview.period == period
            && self.inspection == inspection && self.filterDescription == filterDescription
    }
    private static func context(id: String, title: String, source: String, definitionVersion: String,
                                lines: [String], recordIDs: [String]) throws -> PhysicianReportContext {
        try .init(id: id, title: title, lines: lines, source: source, definitionVersion: definitionVersion, recordIDs: recordIDs)
    }

}
