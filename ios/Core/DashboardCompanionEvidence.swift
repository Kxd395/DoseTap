import Foundation

public extension DashboardCompanionProjection {
    func episode(for night: Night) -> DashboardSharedSleepEpisode? {
        let candidates = (sourceSnapshot.sleepEpisodes ?? []).filter {
            if let session = night.sessionID { return $0.sessionID == session && $0.treatmentDate == night.treatmentDate }
            return $0.sessionID == nil && $0.episodeID == night.id
        }
        return night.identityResolved && candidates.count == 1 ? candidates.first : nil
    }
    func workClassifications(basis: WorkContextBasis) -> [String: WorkPhaseResult] {
        workContext?.classificationsBySleepID(Set(nights.filter(\.identityResolved).map(\.id)), basis: basis, asOf: capturedAt) ?? [:]
    }
    func visible(range: DashboardReportingRange, period: PhysicianReportPeriod?, timeZone: TimeZone,
                 inspection: DashboardInspectionState) -> [Night] {
        if inspection.workPhaseFilter != nil && workIssue != nil { return [] }
        let work = workClassifications(basis: inspection.workContextBasis)
        let contextTimeline = try? self.contextTimeline()
        return selected(range: range, timeZone: timeZone, period: period).filter { night in
            if let pattern = inspection.dosePatternFilter, night.pattern.pattern != pattern { return false }
            if let phase = inspection.workPhaseFilter, (work[night.id]?.phase ?? .unknown) != phase { return false }
            if let context = inspection.contextStratumID, contextStratum(for: night, timeline: contextTimeline).id != context { return false }
            return true
        }
    }
    func sleepMetric(for night: Night, definition: DashboardSleepMetricProjection.Definition) -> DashboardSleepMetricProjection {
        let source = episode(for: night)
        let freshness: DashboardSleepMetricProjection.Freshness = source == nil ? .unavailable : .current
        if definition == .mainProviderEpisode {
            return .providerEpisode(totalMinutes: source?.totalSleepMinutes, source: .appleHealth, freshness: freshness)
        }
        let start = night.administrations.first { $0.slot == 2 }?.occurredAt
        let reported = outcome(for: night)?.answers.finalWakeAt
        let end = reported ?? source?.finalWake
        let coverage = start.flatMap { lower in end.flatMap { SleepIntervalCoverage.calculate(start: lower, end: $0, intervals: source?.intervals ?? []) } }
        let estimate = coverage.flatMap { value in value.asleepMinutes.map { PostDoseSleepEstimate(asleepMinutes: $0, coveredMinutes: value.coveredMinutes, intervalMinutes: value.intervalMinutes) } }
        return .afterDose2(pattern: night.pattern, estimate: estimate, source: .appleHealth, freshness: freshness,
            boundaryBasis: reported != nil ? .reportedFinalAwakening : source?.finalWake != nil ? .providerLastObservedSleepEnd : .unresolved, dose2At: start, endpointAt: end)
    }
    func contextStratum(for night: Night, timeline supplied: DashboardContextTimeline? = nil) -> DashboardContextStratum {
        guard night.identityResolved, let timeline = supplied ?? (try? contextTimeline()) else { return .unknown(observationID: night.id) }
        let source = episode(for: night)
        let points = night.administrations.compactMap(\.occurredAt) + (source?.intervals.flatMap { [$0.start, $0.end] } ?? [])
        guard let start = points.min(), let end = points.max(), start < end else { return .unknown(observationID: night.id) }
        return timeline.stratum(observationID: night.id, start: start, end: end, content: content(for: night))
    }
    func contextTimeline() throws -> DashboardContextTimeline {
        let presets = try Self.rows(.presetVersions, sourceSnapshot).map { try $0.required("payload") }
        let administrations = try Self.rows(.administrations, sourceSnapshot).map { try $0.required("payload") }
        return try DashboardContextTimeline(presets: MedicationPresetExportSnapshot(presetRevisions: presets, administrations: administrations),
            content: try Self.rows(.normalizedAnswers, sourceSnapshot).compactMap { row in
                guard let id = row.text("id"), let instrument = row.text("checkin_type"),
                      let at = Self.timestamp(row.text("submitted_at_utc")), at <= capturedAt else { return nil }
                return try? DashboardContentObservation(sourceRecordID: id, instrumentID: instrument,
                    contentVersion: row.text("questionnaire_version"), language: row.text("language"), observedAt: at)
            }, capturedAt: capturedAt)
    }
    func replay(for night: Night, timeZone: TimeZone, filterDescription: String) -> DashboardReplaySnapshot {
        let session = night.sessionID ?? night.id
        var markers = night.administrations.compactMap { value -> DashboardReplayMarker? in
            guard let at = value.occurredAt else { return nil }
            return .init(id: value.id, sessionID: session, kind: value.slot == 1 ? .dose1 : value.slot == 2 ? .dose2 : .extraDose,
                         occurredAt: at, source: "Recorded administration", sourceRecordID: value.id)
        }
        if let source = episode(for: night) {
            if let at = source.sleepOnset { markers.append(.init(id: source.episodeID + ":start", sessionID: session, kind: .mainSleepStart, occurredAt: at, source: source.source, sourceRecordID: source.episodeID)) }
            if let at = source.finalWake { markers.append(.init(id: source.episodeID + ":end", sessionID: session, kind: .deviceSleepEnd, occurredAt: at, source: source.source, sourceRecordID: source.episodeID)) }
        }
        if let value = outcome(for: night), let wake = value.answers.finalWakeAt {
            markers.append(.init(id: value.id + ":wake", sessionID: session, kind: .reportedWake, occurredAt: wake, recordedAt: value.recordedAt, source: "Patient-reported night outcome", sourceRecordID: value.id))
        }
        for row in (try? Self.rows(.quickLogs, sourceSnapshot)) ?? [] where row.text("session_id") == night.sessionID && night.sessionID != nil {
            guard let id = row.text("id"), let at = Self.timestamp(row.text("timestamp")), at <= capturedAt else { continue }
            let kind = row.text("event_type") == "caffeine" ? DashboardReplayMarker.Kind.caffeine : .event
            markers.append(.init(id: id, sessionID: session, kind: kind, occurredAt: at, source: row.text("event_type") ?? "Recorded event", sourceRecordID: id))
        }
        return .init(sessionID: session, treatmentDate: night.treatmentDate, asOf: capturedAt, timeZoneID: timeZone.identifier,
            sourcePolicy: "Apple Health primary episode + exact local session", filterDescription: filterDescription,
            markers: markers, dose2NotTaken: night.pattern.postDose2State == .notApplicable,
            identityResolved: night.identityResolved, mainEpisodeIntervals: episode(for: night)?.intervals ?? [])
    }
    struct Outcome: Sendable {
        public let id: String
        public let recordedAt: Date
        public let answers: NightOutcomeDiary
    }
    func outcome(for night: Night) -> Outcome? {
        guard let session = night.sessionID, night.identityResolved else { return nil }
        let rows = ((try? Self.rows(.normalizedAnswers, sourceSnapshot)) ?? []).filter {
            $0.text("session_id") == session && $0.text("source_record_id") == session && $0.text("session_date") == night.treatmentDate && $0.text("checkin_type") == "night_outcome"
        }
        struct Record: Decodable { let recordedAt: Date; let answers: NightOutcomeDiary }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard rows.count == 1, let row = rows.first, row.text("questionnaire_version") == "night_outcome.v1",
              let id = row.text("id"), let text = row.text("responses_json"),
              let value = try? decoder.decode(Record.self, from: Data(text.utf8)), value.recordedAt <= capturedAt,
              value.answers.validationError(now: value.recordedAt) == nil,
              value.answers.reviewedSleepWindow.map({ $0.sessionID == session }) ?? true else { return nil }
        return .init(id: id, recordedAt: value.recordedAt, answers: value.answers)
    }
    private func content(for night: Night) -> [DashboardContentObservation] {
        guard let session = night.sessionID else { return [] }
        return ((try? Self.rows(.normalizedAnswers, sourceSnapshot)) ?? []).compactMap { row in
            guard row.text("session_id") == session, row.text("session_date") == night.treatmentDate,
                  let id = row.text("id"), let instrument = row.text("checkin_type"),
                  let at = Self.timestamp(row.text("submitted_at_utc")), at <= capturedAt else { return nil }
            return try? .init(sourceRecordID: id, instrumentID: instrument, contentVersion: row.text("questionnaire_version"), language: row.text("language"), observedAt: at)
        }
    }
}
