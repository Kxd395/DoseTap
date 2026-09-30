import Foundation
import CryptoKit
import DoseCore

@MainActor
extension DashboardAnalyticsModel {
    var physicianCoverageDescription: String {
        let health = healthSnapshot?.description(provider: "Apple Health") ?? "Apple Health: no successful query snapshot."
        let whoop = whoopSnapshot?.description(provider: "WHOOP") ?? "WHOOP: no successful query snapshot."
        return health + "\n" + whoop + "\nThe report period is independent of provider query coverage. Missing provider data is not zero sleep. Local and daytime records are independent of provider availability."
    }

    func physicianReportObservations(for period: PhysicianReportPeriod) throws -> [PhysicianReportObservation] {
        try period.validate()
        guard !isLoading, providerAssociationsReady, doseReviewReadReady, contextReadReady, workContextReadReady, workInspectionAsOf == reportingAsOf, inspectionFilterIssue == nil,
              !nights.contains(where: \.outcomeReadFailed) else { throw PhysicianReviewError.invalidRevision }
        var result: [PhysicianReportObservation] = []
        var metricContext: DashboardContextStratum?
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        func payload<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        func add(_ id: String, at: Date?, metric: String, value: Double?, state: PhysicianMetricState,
                 unit: String, source: String, version: String, detail: String, ids: [String], review: Bool = false, detailOnly: Bool = false, endpoint: Date? = nil, requiresEndpoint: Bool = false, comparisonLabel: String? = nil) {
            let outside = value != nil && (endpoint.map { $0 >= period.endExclusive } ?? requiresEndpoint)
            let unresolved = review && value != nil
            let context = detailOnly ? nil : metricContext
            let suffix = context.map { "|context:" + SHA256.hash(data: Data($0.id.utf8)).map { String(format: "%02x", $0) }.joined() } ?? ""
            let sourceDetail = detail + (context.map { "\n" + $0.label + "; source records: " + $0.sourceRecordIDs.joined(separator: ", ") } ?? "")
                + (outside ? "\nNumeric period summary excluded: the ending occurrence is outside the exact report period or its source boundary is unavailable. Raw source value: \(value.map(String.init(describing:)) ?? "unknown")." : "")
            result.append(.init(id: id, observedAt: at, metricID: metric, value: outside || unresolved ? nil : value, state: unresolved ? .needsReview : outside ? .partial : state, unit: unit,
                source: source, definitionVersion: version + suffix, detail: sourceDetail + (unresolved ? "\nNumeric contribution withheld because source identity or metric evidence needs review." : ""), recordIDs: ids + (context?.sourceRecordIDs ?? []), requiresReview: review, detailOnly: detailOnly, comparisonLabel: comparisonLabel ?? context.map { $0.label + ($0.status == .documentedReference ? "" : " • observation " + id) }))
        }
        let contextDocument = workInspectionContext
        let capturedAt = now()
        let plannedContexts = plannedWorkClassifications
        let confirmedContexts = confirmedWorkClassifications
        for night in visibleInspectionNights {
            metricContext = night.contextStratum
            let pattern = night.dosePattern
            let at = night.dose1Time ?? night.dose2Time
            for (basis, contexts) in [(WorkContextBasis.planned, plannedContexts), (.confirmed, confirmedContexts)] {
                let context = contexts[night.id]
                let association = contextDocument?.association(for: night.id, asOf: reportingAsOf)
                add(night.id + ":work:" + basis.rawValue, at: at, metric: "Work context (" + basis.rawValue + ")", value: nil,
                    state: context?.phase == .unknown || context == nil ? .notCollected : .notApplicable,
                    unit: "record", source: "Patient work roster and explicit sleep association", version: "work-classification.v1",
                    detail: context.map { "\($0.phase.label) • \($0.positionLabel). \($0.detail)\n" } ?? "Unknown: no explicit sleep-to-work association. Dates alone do not assign work context.",
                    ids: [association?.id.uuidString, contextDocument?.revision.uuidString, context?.rosterID?.uuidString].compactMap { $0 },
                    detailOnly: true)
                if let context {
                    add(night.id + ":work-source:" + basis.rawValue, at: at, metric: "Work classification source", value: nil,
                        state: .notApplicable, unit: "record", source: "Patient work roster and explicit sleep association",
                        version: "work-classification.v\(context.classificationVersion)", detail: try payload(context),
                        ids: [association?.id.uuidString, contextDocument?.revision.uuidString].compactMap { $0 }, detailOnly: true)
                }
            }
            let detail = "Session/group: \(night.id); treatment date: \(night.sessionDate). \(pattern.pattern.label). Count completeness: \(pattern.countComplete). Administration amounts are not inferred from plans.\n" + (try payload(pattern))
            add(night.id + ":spacing", at: at, metric: "Dose 1 to Dose 2 spacing • " + pattern.pattern.label, value: pattern.interval.value,
                state: PhysicianMetricState(rawValue: pattern.interval.state.rawValue) ?? .needsReview,
                unit: pattern.interval.unit, source: "Reported administration occurrences", version: DashboardDosePattern.version,
                detail: detail, ids: pattern.evidenceIDs, review: night.identityNeedsReview || pattern.pattern == .needsReview, endpoint: night.dose2Time, requiresEndpoint: true)
            for event in night.doseEvents {
                add("administration:" + event.id, at: event.timestamp, metric: "Reported dose event detail", value: nil,
                    state: .notApplicable, unit: "record", source: "Patient administration event ledger", version: "dose-event.v1",
                    detail: "Type: \(event.eventType); session: \(event.sessionId ?? "unresolved"); treatment date: \(event.sessionDate). Actual amounts remain unknown unless explicitly recorded in the source metadata.\n" + (event.metadata ?? "No administration metadata recorded."),
                    ids: [event.id], review: night.identityNeedsReview, detailOnly: true)
            }
            let replay = replaySnapshot(for: night)
            for preset in DashboardIntervalPreset.allCases where preset != .dose1ToDose2 {
                let metric = replay.interval(preset)
                let start = metric.startID.flatMap { id in replay.markers.first { $0.id == id }?.occurredAt }
                add(night.id + ":interval:" + preset.rawValue, at: start ?? at, metric: preset.rawValue + " • " + pattern.pattern.label,
                    value: metric.minutes, state: PhysicianMetricState(rawValue: metric.state.rawValue) ?? .needsReview,
                    unit: "minutes", source: replay.sourcePolicy, version: replay.derivationVersion,
                    detail: try payload(metric), ids: [metric.startID, metric.endID].compactMap { $0 },
                    review: metric.state == .needsReview, endpoint: metric.endID.flatMap { id in replay.markers.first { $0.id == id }?.occurredAt }, requiresEndpoint: true)
            }
            add(night.id + ":replay", at: at, metric: "Session replay source evidence", value: nil, state: .notApplicable,
                unit: "record", source: replay.sourcePolicy, version: replay.derivationVersion,
                detail: try payload(replay), ids: replay.markers.map(\.id), review: night.identityNeedsReview, detailOnly: true)
            if let ledger = night.doseReviewLedger {
                add(night.id + ":dose-reviews", at: at, metric: "Dose-history review revisions", value: nil, state: .notApplicable,
                    unit: "record", source: "Patient dose-history review", version: "dose-review.v1", detail: try payload(ledger),
                    ids: ledger.revisions.map { $0.revisionID.uuidString }, review: ledger.current != night.doseReview, detailOnly: true)
            }
            if sleepSource == .appleHealth, let sleep = night.healthSummary {
                let projected = DashboardSleepMetricProjection.providerEpisode(totalMinutes: night.appleHealthSleepMinutes,
                    source: .appleHealth, freshness: providerSnapshotIsCurrent(.health) ? .current : .stale)
                add(night.id + ":apple-sleep", at: sleep.sleepOnset ?? sleep.recordedIntervals.map(\.start).min() ?? sleep.bedTime, metric: "Primary episode sleep • " + pattern.pattern.label, value: projected.metric.value,
                    state: PhysicianMetricState(rawValue: projected.metric.state.rawValue) ?? .needsReview, unit: "minutes", source: "Apple Health • \(sleep.source)",
                    version: projected.derivationVersion + "|" + (sleep.derivationVersion ?? "primary-episode.v1"), detail: physicianCoverageDescription + "\n" + (try payload(projected)) + "\n" + detail,
                    ids: [String(describing: sleep.id)], review: night.identityNeedsReview, detailOnly: sleepSource != .appleHealth,
                    endpoint: sleep.recordedIntervals.map(\.end).max() ?? sleep.finalWake, requiresEndpoint: true)
            } else if sleepSource == .appleHealth {
                add(night.id + ":apple-sleep", at: at, metric: "Primary episode sleep • " + pattern.pattern.label, value: nil, state: .unavailable,
                    unit: "minutes", source: "Apple Health", version: "primary-episode.v1", detail: physicianCoverageDescription,
                    ids: [night.id], review: night.identityNeedsReview, detailOnly: sleepSource != .appleHealth)
            }
            if sleepSource == .whoop, let sleep = night.whoopSummary {
                metricContext = night.contextStratum(for: .whoop)
                let projected = DashboardSleepMetricProjection.providerEpisode(totalMinutes: night.whoopSleepMinutes,
                    source: .whoop, freshness: providerSnapshotIsCurrent(.whoop) ? .current : .stale)
                add(night.id + ":whoop-sleep", at: sleep.date, metric: "Primary episode sleep • " + pattern.pattern.label, value: projected.metric.value,
                    state: PhysicianMetricState(rawValue: projected.metric.state.rawValue) ?? .needsReview,
                    unit: "minutes", source: "WHOOP", version: projected.derivationVersion + "|whoop-primary.v1",
                    detail: "Grouped date: \(night.sessionDate). Period membership uses the validated WHOOP sleep-record start, not a claimed measured onset.\n" + physicianCoverageDescription,
                    ids: [sleep.sleepId], review: night.identityNeedsReview, detailOnly: sleepSource != .whoop, requiresEndpoint: true)
            }
            if sleepSource == .whoop, night.whoopSummary == nil {
                metricContext = night.contextStratum(for: .whoop)
                add(night.id + ":whoop-sleep", at: at, metric: "Primary episode sleep • " + pattern.pattern.label, value: nil, state: .unavailable,
                    unit: "minutes", source: "WHOOP", version: "whoop-primary.v1", detail: physicianCoverageDescription,
                    ids: [night.id], review: night.identityNeedsReview)
            }
            for source in [sleepSource == .appleHealth ? DashboardSleepMetricProjection.Source.appleHealth : .whoop] {
                metricContext = night.contextStratum(for: source == .appleHealth ? .appleHealth : .whoop)
                let provider: DashboardProviderAccess.Provider = source == .appleHealth ? .health : .whoop
                let hasEvidence = source == .appleHealth ? night.healthSummary != nil : night.whoopSummary != nil
                let boundary: DashboardSleepMetricProjection.BoundaryBasis = source != .appleHealth ? .unresolved
                    : night.outcome?.finalWakeAt != nil ? .reportedFinalAwakening
                    : night.healthSummary?.finalWake != nil ? .providerLastObservedSleepEnd : .unresolved
                let endpoint: Date? = source == .appleHealth ? night.outcome?.finalWakeAt ?? night.healthSummary?.finalWake : nil
                let projected = DashboardSleepMetricProjection.afterDose2(pattern: pattern,
                    estimate: source == .appleHealth ? night.postDoseSleep : nil, source: source,
                    freshness: !hasEvidence ? .unavailable : providerSnapshotIsCurrent(provider) ? .current : .stale, boundaryBasis: boundary,
                    dose2At: night.dose2Time, endpointAt: endpoint)
                let boundaryText = endpoint.map { ISO8601DateFormatter().string(from: $0) } ?? "Unavailable"
                add(night.id + ":observed-after-d2:" + source.rawValue, at: night.dose2Time ?? at,
                    metric: "Observed sleep after Dose 2 • " + pattern.pattern.label, value: projected.metric.value,
                    state: PhysicianMetricState(rawValue: projected.metric.state.rawValue) ?? .needsReview,
                    unit: "minutes", source: source.rawValue, version: projected.derivationVersion + "|" + boundary.rawValue,
                    detail: (try payload(projected)) + "\nFinal-wake boundary: \(boundaryText).",
                    ids: pattern.evidenceIDs + [source == .appleHealth ? night.healthSummary.map { String(describing: $0.id) } : night.whoopSummary?.sleepId,
                        night.outcome?.finalWakeAt == nil ? nil : night.sessionID].compactMap { $0 },
                    review: projected.metric.state == .needsReview, detailOnly: (source == .appleHealth) != (sleepSource == .appleHealth), endpoint: endpoint, requiresEndpoint: true)
            }
            if let outcome = night.outcome {
                add(night.id + ":outcome", at: outcome.finalWakeAt ?? at, metric: "Explicit night outcome", value: nil,
                    state: .notApplicable, unit: "record", source: "Patient night-outcome diary", version: "night-outcome.v1",
                    detail: try payload(outcome), ids: [night.id], detailOnly: true)
            }
            if let preSleep = night.preSleepLog {
                let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let stamp = iso.date(from: preSleep.createdAtUtc) ?? ISO8601DateFormatter().date(from: preSleep.createdAtUtc)
                add("pre-sleep:" + preSleep.id, at: stamp, metric: "Pre-sleep questionnaire detail", value: nil, state: .notApplicable,
                    unit: "record", source: "Patient questionnaire", version: "pre-sleep.v1",
                    detail: "Recorded at \(preSleep.createdAtUtc); completion \(preSleep.completionState). Questionnaire submission is not lights out.\n" + (try payload(preSleep.answers)), ids: [preSleep.id], detailOnly: true)
            }
            for event in night.events {
                add("event:" + event.id, at: event.timestamp, metric: "Recorded night event", value: nil, state: .notApplicable,
                    unit: "record", source: "Patient event log", version: "night-event.v1",
                    detail: "\(event.eventType). \(event.notes ?? "")", ids: [event.id], detailOnly: true)
            }
            if let morning = night.morningCheckIn {
                let details = [
                    "Stored legacy morning timestamp \(morning.timestamp); assessment time was not collected. Session \(morning.sessionId), treatment date \(morning.sessionDate). Historical populated defaults and carried-forward values are not proof of explicit answers.",
                    "Sleep quality \(morning.sleepQuality); rested \(morning.feelRested); grogginess \(morning.grogginess); recovery category \(morning.sleepInertiaDuration); dream recall \(morning.dreamRecall).",
                    "Physical flag \(morning.hasPhysicalSymptoms): \(morning.physicalSymptomsJson ?? "not recorded"). Respiratory flag \(morning.hasRespiratorySymptoms): \(morning.respiratorySymptomsJson ?? "not recorded").",
                    "Recorded flags: paralysis \(morning.hadSleepParalysis); hallucinations \(morning.hadHallucinations); automatic behavior \(morning.hadAutomaticBehavior); fell out of bed \(morning.fellOutOfBed); waking confusion \(morning.hadConfusionOnWaking).",
                    "Mental clarity \(morning.mentalClarity); mood \(morning.mood); anxiety \(morning.anxietyLevel); stress \(morning.stressLevel.map(String.init) ?? "not recorded"); readiness \(morning.readinessForDay). Stress context: \(morning.stressContextJson ?? "not recorded").",
                    "Therapy flag \(morning.usedSleepTherapy): \(morning.sleepTherapyJson ?? "not recorded"). Environment flag \(morning.hasSleepEnvironment): \(morning.sleepEnvironmentJson ?? "not recorded"). Timing: \(morning.timingContextJson ?? "not recorded").", morning.notes ?? ""]
                let detail = details.joined(separator: "\n")
                add("morning:" + morning.id, at: nil, metric: "Morning questionnaire detail", value: nil, state: .needsReview,
                    unit: "record", source: "Patient questionnaire", version: "legacy-morning.v1", detail: detail, ids: [morning.id],
                    review: true, detailOnly: true)
            }
        }
        metricContext = nil
        let checkIns = try sessionRepo.daytimeCheckIns().current
        let events = try sessionRepo.daytimeEvents().current
        let earliest = (checkIns.map(\.assessedAt) + events.map(\.occurredAt)).min() ?? capturedAt
        let daytime = try DaytimeDiaryAnalysis(observations: checkIns, events: events, start: earliest, end: capturedAt,
            now: capturedAt, timeZone: reportingTimeZone)
        let groupByID = Dictionary(uniqueKeysWithValues: daytime.groups.flatMap { group in group.observationIDs.map { ($0, group) } })
        for value in checkIns {
            guard let group = groupByID[value.id] else { throw PhysicianReviewError.invalidRevision }
            let groupHash = SHA256.hash(data: Data(group.id.utf8)).map { String(format: "%02x", $0) }.joined()
            let context = "\(group.origin.rawValue) • \(group.setting.rawValue) • \(group.clockBandLabel) • \(group.timeZoneIdentifier) • \(group.samplingProtocolLabel ?? "No sampling protocol label")."
            add("daytime:" + value.id.uuidString, at: value.assessedAt, metric: "Current sleepiness (custom 0–10)",
                value: value.response.map(Double.init), state: value.status == .answered ? .available : .unavailable,
                unit: "custom rating 0–10", source: "Patient daytime diary", version: "daytime-sampling.v\(daytime.calculationVersion)|" + groupHash,
                detail: context + "\n" + (try value.encoded()), ids: [value.id.uuidString, value.revisionID.uuidString], comparisonLabel: context)
        }
        for value in events {
            add("daytime-event:" + value.id.uuidString, at: value.occurredAt, metric: value.kind.rawValue, value: nil,
                state: value.kind == .unclear ? .needsReview : .notApplicable, unit: "record", source: "Patient daytime event",
                version: "daytime-event.v\(value.version)", detail: try value.encoded(), ids: [value.id.uuidString, value.revisionID.uuidString],
                review: true, detailOnly: true)
        }
        // A raw row can be associated with more than one unresolved group; retain it once by source identity.
        return Dictionary(grouping: result.filter { $0.observedAt.map(period.contains) ?? true }, by: \.id).values.compactMap(\.first).sorted { $0.id < $1.id }
    }
    func physicianReportContexts(for period: PhysicianReportPeriod, generatedAt: Date) throws -> [PhysicianReportContext] {
        try period.validate()
        guard let zone = TimeZone(identifier: period.timeZoneIdentifier) else { throw PhysicianReviewError.invalidPeriod }
        let records = try sessionRepo.daytimeCheckIns().current, events = try sessionRepo.daytimeEvents().current
        let analysis = try DaytimeDiaryAnalysis(observations: records, events: events, start: period.start,
            end: period.endExclusive, now: generatedAt, timeZone: zone, includesEnd: false)
        let iso = ISO8601DateFormatter()
        let reviews = records.filter { $0.eventReview.map { $0.from < period.endExclusive && $0.to > period.start } ?? false }
        var lines = ["\(analysis.unplannedSleepEvents) distinct reported unplanned-sleep events; \(analysis.reviewedCalendarDays)/\(analysis.calendarDays) calendar dates have reviewed intervals; \(analysis.daysWithoutReviewedInterval) dates have no reviewed interval.",
            "\(analysis.fullyReviewedCalendarDays) fully reviewed calendar dates; \(analysis.partiallyReviewedCalendarDays) partly reviewed dates. Reviewed intervals do not establish complete waking-day surveillance.",
            "\(analysis.answeredCount) answered current-sleepiness samples on \(analysis.ratedCalendarDays) dates. Multiple observations are not independent days.",
            "\(analysis.reviewSubmissionDays) dates with review submissions. Submission dates are separate from the intervals reviewed."]
        lines += analysis.eventCountsByKind.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue): \($0.value) distinct events." }
        lines += analysis.copingResponseCounts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "Coping \($0.key.rawValue): \($0.value) responses, not event/day counts." }
        lines += reviews.compactMap { row -> String? in
            guard let review = row.eventReview else { return nil }
            return "Review \(row.id): \(review.status.rawValue), \(iso.string(from: review.from)) to \(iso.string(from: review.to)); recorded \(iso.string(from: row.recordedAt)); linked IDs \(review.eventIDs.map(\.uuidString).joined(separator: ", "))."
        }
        let sourceIDs = reviews.map { $0.revisionID.uuidString } + events.filter { period.contains($0.occurredAt) }.map { $0.revisionID.uuidString }
        var result = [try PhysicianReportContext(id: "daytime-coverage", title: "Daytime review coverage", lines: lines,
            source: "Patient daytime diary and independent event ledger", definitionVersion: "daytime-analysis.v\(analysis.calculationVersion)", recordIDs: sourceIDs)]
        for group in analysis.groups {
            let hash = SHA256.hash(data: Data(group.id.utf8)).map { String(format: "%02x", $0) }.joined()
            let distribution = group.distribution.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            result.append(try .init(id: "daytime-group:" + hash, title: "\(group.origin.rawValue) • \(group.setting.rawValue) • \(group.clockBandLabel)",
                lines: ["\(group.answeredCount)/\(group.entryCount) samples answered on \(group.ratedDays) source-local dates; median \(group.median.map { String($0) } ?? "unavailable") custom 0–10.",
                    "Response distribution (rating: count): \(distribution.isEmpty ? "No answered samples" : distribution).",
                    "Source timezone: \(group.timeZoneIdentifier). Protocol: \(group.samplingProtocolLabel ?? "No label recorded").",
                    "Sampling definition: \(group.id). Scheduled, user-initiated and retrospective observations remain separate."],
                source: "Patient daytime diary", definitionVersion: "daytime-analysis.v\(analysis.calculationVersion)", recordIDs: group.observationIDs.map(\.uuidString)))
        }
        guard contextReadReady, let timeline = contextTimeline else { throw PhysicianReviewError.invalidRevision }
        for annotation in timeline.annotations(from: period.start, to: period.endExclusive, includeBaseline: true) {
            let id = SHA256.hash(data: Data(annotation.id.utf8)).map { String(format: "%02x", $0) }.joined()
            let time = annotation.effectiveAt.map(iso.string) ?? "Unknown effective time"
            result.append(try .init(id: "reference-context:" + id, title: annotation.title,
                lines: [annotation.detail, "Effective: " + time + "; recorded/observed: " + iso.string(from: annotation.observedAt),
                    annotation.needsReview ? "Retained for review; no effective date or verified treatment effect is inferred." : "Source-backed reference context."],
                source: annotation.source, definitionVersion: annotation.definitionVersion, recordIDs: annotation.sourceRecordIDs))
        }
        return result
    }

}
