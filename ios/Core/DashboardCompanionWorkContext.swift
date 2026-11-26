import Foundation

/// One frozen comparison, shared by the companion chart, exact table and deliberate export.
public struct DashboardCompanionWorkContext: Sendable {
    public static let version = "companion-work-context.v1"
    public enum Metric: String, CaseIterable, Sendable {
        case mainSleep, afterDose2, doseInterval
        public var label: String {
            switch self { case .mainSleep: return "Main provider episode sleep"; case .afterDose2: return "Observed sleep after Dose 2"; case .doseInterval: return "Actual dose interval" }
        }
    }
    public struct Row: Identifiable, Sendable {
        public let id: String, treatmentDate: String, month: String
        public let phase: WorkPhase, plannedPhase: WorkPhase, confirmedPhase: WorkPhase
        public let position: String, blockID: String?, rosterID: UUID?, associationID: UUID?, planSnapshotID: UUID?
        public let isOverride: Bool, contextSnapshotAt: Date?
        public let metric: DashboardMetricValue, boundary: String, source: String, metricVersion: String
        public let coveredMinutes: Double?, intervalMinutes: Double?, unmeasuredMinutes: Double?
        public let context: DashboardContextStratum, pattern: DashboardDosePattern.Pattern
        public let sourceRecordIDs: [String]
        public var value: Double? { metric.value }
        public func eligibleValue(includePartial: Bool) -> Double? {
            metric.state == .available || (includePartial && metric.state == .partial) ? value : nil
        }
    }
    public struct Summary: Identifiable, Sendable {
        public let id: String, month: String, position: String, contextID: String, contextLabel: String, boundary: String, source: String
        public let phase: WorkPhase, pattern: DashboardDosePattern.Pattern
        public let observationIDs: [String], summary: WorkCycleSummary
    }
    public let capturedAt: Date, sourceID: String, sequence: UInt64
    public let basis: WorkContextBasis, selectedMetric: Metric, includePartial: Bool
    public let rows: [Row], summaries: [Summary], annotations: [DashboardContextAnnotation]
    public let contextIssue: String?, workIssue: String?, contextRevision: UUID?
    public var missingCount: Int { rows.filter { $0.eligibleValue(includePartial: includePartial) == nil }.count }
    public var unknownContextCount: Int { rows.filter { $0.context.status != .documentedReference }.count }

    public init(report: DashboardCompanionProjection, nights: [DashboardCompanionProjection.Night], basis: WorkContextBasis,
                metric: Metric, includePartial: Bool = false) throws {
        guard Set(nights.map(\.id)).count == nights.count else { throw DashboardSnapshotError.invalidPayload }
        let canonical = Dictionary(uniqueKeysWithValues: report.nights.map { ($0.id, $0) })
        guard nights.allSatisfy({ canonical[$0.id]?.treatmentDate == $0.treatmentDate }) else { throw DashboardSnapshotError.invalidPayload }
        capturedAt = report.capturedAt; sourceID = report.sourceID; sequence = report.sequence
        self.basis = basis; selectedMetric = metric; self.includePartial = includePartial
        workIssue = report.workIssue; contextRevision = report.workContext?.revision
        let evidence: DashboardCompanionContextEvidence?
        do { evidence = try report.workContextEvidence(); contextIssue = nil }
        catch { evidence = nil; contextIssue = "Context source needs review on the phone. Exact observations remain available; comparable context summaries are withheld." }
        let planned = report.workClassifications(basis: .planned), confirmed = report.workClassifications(basis: .confirmed)
        let links = report.workContext?.associationsBySleepID(Set(nights.map(\.id)), asOf: report.capturedAt) ?? [:]
        rows = nights.compactMap { canonical[$0.id] }.map { night in
            let selected = (basis == .planned ? planned : confirmed)[night.id], association = links[night.id]
            let sleep = report.sleepMetric(for: night, definition: metric == .afterDose2 ? .observedAfterDose2 : .mainProviderEpisode)
            return Row(id: night.id, treatmentDate: night.treatmentDate, month: String(night.treatmentDate.prefix(7)),
                phase: selected?.phase ?? .unknown, plannedPhase: planned[night.id]?.phase ?? .unknown,
                confirmedPhase: confirmed[night.id]?.phase ?? .unknown, position: selected?.positionLabel ?? "Unknown / review",
                blockID: selected?.blockID, rosterID: selected?.rosterID, associationID: association?.id, planSnapshotID: association?.planSnapshotID,
                isOverride: selected?.isOverride ?? false, contextSnapshotAt: association?.plannedAt,
                metric: metric == .doseInterval ? night.pattern.interval : sleep.metric,
                boundary: metric == .doseInterval ? "actual_dose1_to_dose2" : sleep.boundaryBasis.rawValue,
                source: metric == .doseInterval ? "recorded_administrations" : sleep.source.rawValue,
                metricVersion: metric == .doseInterval ? DashboardDosePattern.version : sleep.derivationVersion,
                coveredMinutes: metric == .doseInterval ? nil : sleep.coveredMinutes,
                intervalMinutes: metric == .doseInterval ? nil : sleep.intervalMinutes,
                unmeasuredMinutes: metric == .doseInterval ? nil : sleep.unmeasuredMinutes,
                context: evidence?.stratum(for: night, report: report) ?? .unknown(observationID: night.id), pattern: night.pattern.pattern,
                sourceRecordIDs: night.sourceRecordIDs + (report.episode(for: night).map { [$0.episodeID] } ?? []))
        }.sorted { $0.treatmentDate == $1.treatmentDate ? $0.id < $1.id : $0.treatmentDate < $1.treatmentDate }
        let groups = Dictionary(grouping: rows.filter { $0.context.status == .documentedReference }) {
            Self.key([$0.month, $0.position, $0.phase.rawValue, $0.pattern.rawValue, $0.context.id, $0.boundary, $0.source, $0.metricVersion])
        }
        summaries = groups.keys.sorted().compactMap { key in
            guard let group = groups[key], let first = group.first else { return nil }
            return Summary(id: key, month: first.month, position: first.position, contextID: first.context.id, contextLabel: first.context.label, boundary: first.boundary, source: first.source,
                phase: first.phase, pattern: first.pattern, observationIDs: group.map(\.id),
                summary: WorkCycleSummary(observations: group.map {
                    .init(sleepID: $0.id, sleepDate: $0.treatmentDate, phase: $0.phase, position: $0.position,
                        blockID: $0.blockID, value: $0.eligibleValue(includePartial: includePartial))
                }))
        }
        let relevantIDs = Set(rows.flatMap { $0.context.sourceRecordIDs })
            .union(nights.flatMap { evidence?.contentByObservationID[$0.id]?.map(\.sourceRecordID) ?? [] })
        annotations = evidence?.timeline.annotations.filter {
            // Independent daytime administrations have no reviewed link to these selected main-sleep rows.
            $0.kind != .administration && !relevantIDs.isDisjoint(with: $0.sourceRecordIDs)
        } ?? []
    }
    public func csv(timeZone: TimeZone, filterDescription: String) -> String {
        let headers = ["row_type", "observation_id", "treatment_date", "month", "phase", "planned_phase", "confirmed_phase", "position", "block_id", "value_minutes", "metric_state", "reason", "source", "metric", "metric_version", "boundary", "covered_minutes", "window_minutes", "unmeasured_minutes", "context_id", "context_status", "dose_pattern", "source_record_ids", "association_revision", "roster_revision", "plan_snapshot_id", "is_override", "context_snapshot_utc", "captured_at_utc", "report_source", "sequence", "timezone", "filters", "basis", "include_partial", "context_revision", "classification_version", "projection_version", "private_notes", "visible_count", "eligible_count", "unknown_context_count", "context_source_ids", "annotation_kind", "effective_at_utc", "observed_at_utc", "annotation_source", "annotation_definition", "annotation_source_ids"]
        func number(_ value: Double?) -> String { value.map { String($0) } ?? "" }
        func stamp(_ value: Date?) -> String { value.map { ISO8601DateFormatter().string(from: $0) } ?? "" }
        let metadata = [stamp(capturedAt), sourceID, String(sequence), timeZone.identifier, filterDescription, basis.rawValue,
                        String(includePartial), contextRevision?.uuidString ?? "", "1", Self.version, "omitted",
                        String(rows.count), String(rows.count - missingCount), String(unknownContextCount)]
        var output = [ReportCSV.row(headers)]
        if rows.isEmpty { output.append(ReportCSV.row(["metadata"] + Array(repeating: "", count: 27) + metadata + Array(repeating: "", count: 7))) }
        for row in rows {
            let values = ["observation", row.id, row.treatmentDate, row.month, row.phase.rawValue, row.plannedPhase.rawValue,
                row.confirmedPhase.rawValue, row.position, row.blockID ?? "", number(row.value), row.metric.state.rawValue,
                row.metric.reason, row.source, selectedMetric.rawValue, row.metricVersion, row.boundary,
                number(row.coveredMinutes), number(row.intervalMinutes), number(row.unmeasuredMinutes), row.context.id,
                row.context.status.rawValue, row.pattern.rawValue, row.sourceRecordIDs.joined(separator: ";"),
                row.associationID?.uuidString ?? "", row.rosterID?.uuidString ?? "", row.planSnapshotID?.uuidString ?? "",
                String(row.isOverride), stamp(row.contextSnapshotAt)]
            output.append(ReportCSV.row(values + metadata + [row.context.sourceRecordIDs.joined(separator: ";")] + Array(repeating: "", count: 6)))
        }
        for annotation in annotations {
            let provenance = ["", annotation.kind.rawValue, stamp(annotation.effectiveAt), stamp(annotation.observedAt),
                              annotation.source, annotation.definitionVersion, annotation.sourceRecordIDs.joined(separator: ";")]
            output.append(ReportCSV.row(["context_annotation"] + Array(repeating: "", count: 27) + metadata + provenance))
        }
        return output.joined(separator: "\r\n") + "\r\n"
    }
    private static func key(_ fields: [String]) -> String { fields.map { "\($0.utf8.count):\($0)" }.joined() }
}

public struct DashboardCompanionContextEvidence: Sendable {
    public let timeline: DashboardContextTimeline
    public let contentByObservationID: [String: [DashboardContentObservation]]
    public func stratum(for night: DashboardCompanionProjection.Night, report: DashboardCompanionProjection) -> DashboardContextStratum {
        guard night.identityResolved, night.pattern.pattern != .needsReview else { return .unknown(observationID: night.id) }
        let points = night.administrations.compactMap(\.occurredAt) + (report.episode(for: night)?.intervals.flatMap { [$0.start, $0.end] } ?? [])
        guard let start = points.min(), let end = points.max(), start < end else { return .unknown(observationID: night.id) }
        return timeline.stratum(observationID: night.id, start: start, end: end, content: contentByObservationID[night.id] ?? [])
    }
}

public extension DashboardCompanionProjection {
    /// Exact phone B24 provenance contract. Raw legacy responses never gain a generated version.
    func workContextEvidence() throws -> DashboardCompanionContextEvidence {
        let normalized = try Self.rows(.normalizedAnswers, sourceSnapshot)
        var content: [String: DashboardContentObservation] = [:]
        var byID: [String: [DashboardContentObservation]] = [:]
        for row in normalized {
            let id = "checkin_submissions:" + (try row.required("id")), kind = try row.required("checkin_type")
            guard content[id] == nil, let at = Self.timestamp(row.text("submitted_at_utc")), at <= capturedAt else { throw DashboardSnapshotError.invalidPayload }
            content[id] = try .init(sourceRecordID: id, instrumentID: "dosetap." + kind,
                contentVersion: row.text("questionnaire_version").flatMap { $0.isEmpty ? nil : $0 }, language: nil, observedAt: at)
        }
        var links: [CompanionContextJoin: [DashboardContentObservation]] = [:]
        for row in normalized {
            if let key = CompanionContextJoin(row), let id = row.text("id"), let value = content["checkin_submissions:" + id] {
                links[key, default: []].append(value)
            }
        }
        let raw = try Self.rows(.morning, sourceSnapshot) + Self.rows(.preSleep, sourceSnapshot)
        let rawIDs = try raw.map { $0.sourceTable + ":" + (try $0.required("id")) }
        guard Set(rawIDs).count == rawIDs.count else { throw DashboardSnapshotError.invalidPayload }
        let rawBySession = Dictionary(grouping: raw, by: { $0.text("session_id") ?? "" })
        var processedRaw = Set<String>()
        for night in nights {
            var values: [DashboardContentObservation] = []
            if let session = night.sessionID {
                for row in rawBySession[session] ?? [] where row.sourceTable == "pre_sleep_logs" || row.text("session_date") == night.treatmentDate {
                    let id = try row.required("id"), pre = row.sourceTable == "pre_sleep_logs", kind = pre ? "pre_night" : "morning"
                    processedRaw.insert(row.sourceTable + ":" + id)
                    let matches = links[.init(kind: kind, source: id, session: session, date: night.treatmentDate)] ?? []
                    if matches.count == 1 { values.append(matches[0]) }
                    else {
                        guard let at = Self.timestamp(row.text(pre ? "created_at_utc" : "timestamp")), at <= capturedAt else { throw DashboardSnapshotError.invalidPayload }
                        let value = try DashboardContentObservation(sourceRecordID: row.sourceTable + ":" + id,
                            instrumentID: "dosetap." + kind, contentVersion: nil, language: nil, observedAt: at)
                        values.append(value); content[value.sourceRecordID] = value
                    }
                }
                values += links[.init(kind: "night_outcome", source: session, session: session, date: night.treatmentDate)] ?? []
            }
            byID[night.id] = values
        }
        for row in raw {
            let id = row.sourceTable + ":" + (try row.required("id"))
            guard !processedRaw.contains(id) else { continue }
            let pre = row.sourceTable == "pre_sleep_logs"
            guard let at = Self.timestamp(row.text(pre ? "created_at_utc" : "timestamp")), at <= capturedAt else { throw DashboardSnapshotError.invalidPayload }
            content[id] = try .init(sourceRecordID: id, instrumentID: pre ? "dosetap.pre_night" : "dosetap.morning",
                contentVersion: nil, language: nil, observedAt: at)
        }
        let presets = try Self.rows(.presetVersions, sourceSnapshot).map { try $0.required("payload") }
        let actual = try Self.rows(.administrations, sourceSnapshot).map { try $0.required("payload") }
        let timeline = try DashboardContextTimeline(presets: .init(presetRevisions: presets, administrations: actual),
            content: Array(content.values), capturedAt: capturedAt)
        return .init(timeline: timeline, contentByObservationID: byID)
    }
}

private struct CompanionContextJoin: Hashable {
    let kind: String, source: String, session: String, date: String
    init(kind: String, source: String, session: String, date: String) {
        self.kind = kind; self.source = source; self.session = session; self.date = date
    }
    init?(_ row: DashboardCompanionProjection.Row) {
        guard let kind = row.text("checkin_type"), let source = row.text("source_record_id"),
              let session = row.text("session_id"), let date = row.text("session_date") else { return nil }
        self.init(kind: kind, source: source, session: session, date: date)
    }
}
