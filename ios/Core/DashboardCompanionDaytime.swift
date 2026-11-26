import Foundation

/// Read-only civil-time projection of transferred source ledgers, frozen at the phone capture.
public struct DashboardCompanionDaytime: Sendable {
    public let period: PhysicianReportPeriod
    public let observations: [DaytimeCheckIn]
    public let events: [DaytimeEvent]
    public let napDocument: NapDiaryDocument?
    public let naps: [NapEpisode]
    public let napDays: [NapDayProjection]
    public let contexts: [UUID: DaytimeObservationContext]
    public let analysis: DaytimeDiaryAnalysis
    public let hasObservationRecords: Bool
    public let sourceID: String
    public let sequence: UInt64

    public init(snapshot: CloudDashboardSnapshot, period: PhysicianReportPeriod) throws {
        try period.validate()
        guard period.capturedAt == snapshot.capturedAt, let zone = TimeZone(identifier: period.timeZoneIdentifier) else {
            throw DashboardSnapshotError.invalidMetadata
        }
        let source = try Source(snapshot)
        self.period = period; sourceID = snapshot.sourceID; sequence = snapshot.sequence
        hasObservationRecords = !source.observations.isEmpty
        observations = source.observations.filter { period.contains($0.assessedAt) }
        events = source.events.filter { period.contains($0.occurredAt) }
        napDocument = source.napDocument
        let timers = NapEpisode.timers(source.markers, zone: period.timeZoneIdentifier, asOf: snapshot.capturedAt)
        let allNaps = source.napDocument?.merging(timers) ?? timers
        naps = allNaps.filter { value in
            if let time = value.start ?? value.end { return period.contains(time) }
            guard let start = WorkContextDocument.day(value.day, zone: value.timeZoneID),
                  let timeZone = TimeZone(identifier: value.timeZoneID) else { return false }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
            return start < period.endExclusive && end > period.start
        }
        var dayKeys = Set(naps.map { $0.timeZoneID + "|" + $0.day })
        for review in source.napDocument?.reviews ?? [] {
            guard let date = WorkContextDocument.day(review.day, zone: review.timeZoneID),
                  let tz = TimeZone(identifier: review.timeZoneID) else { continue }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = tz
            if let end = calendar.date(byAdding: .day, value: 1, to: date), date < period.endExclusive && end > period.start {
                dayKeys.insert(review.timeZoneID + "|" + review.day)
            }
        }
        napDays = dayKeys.sorted().compactMap { key in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return NapDayProjection(timeZoneID: parts[0], day: parts[1], episodes: allNaps,
                review: source.napDocument?.status(day: parts[1], zone: parts[0], episodes: allNaps) ?? .unreviewed)
        }
        contexts = try Dictionary(uniqueKeysWithValues: source.observations.map { observation in
            (observation.id, try DaytimeObservationContext(observation: observation, work: source.work,
                basis: .confirmed, medication: source.medication, asOf: snapshot.capturedAt))
        })
        analysis = try DaytimeDiaryAnalysis(observations: source.observations, events: source.events,
            start: period.start, end: period.endExclusive, now: snapshot.capturedAt, timeZone: zone,
            includesEnd: false, contexts: contexts)
    }

    /// Actual source occurrences only. Day-only nap reports do not invent an onset.
    public static func earliestEvidenceAt(in snapshot: CloudDashboardSnapshot) throws -> Date? {
        let source = try Source(snapshot)
        return (source.observations.map(\.assessedAt) + source.events.map(\.occurredAt) + source.markers.map(\.date)
            + (source.napDocument?.current.compactMap { $0.start ?? $0.end } ?? [])).min()
    }

    /// Observation filters do not silently change event-review coverage denominators.
    public func csv(observationIDs: Set<UUID>, filterDescription: String) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let header = ["source_id", "sequence", "captured_at", "period_start", "period_end_exclusive", "period_timezone", "filters", "observation_id", "revision_id", "assessed_at", "recorded_at", "observation_timezone", "instrument", "version", "language", "origin", "status", "response", "setting", "activity", "coping", "context", "source_links"]
        let prefix = [sourceID, String(sequence), formatter.string(from: period.capturedAt), formatter.string(from: period.start),
            formatter.string(from: period.endExclusive), period.timeZoneIdentifier, filterDescription]
        var output = [header]
        for row in observations where observationIDs.contains(row.id) {
            var cells = prefix
            cells += [row.id.uuidString, row.revisionID.uuidString, formatter.string(from: row.assessedAt), formatter.string(from: row.recordedAt)]
            cells += [row.timeZoneIdentifier, row.instrumentID, row.contentVersion, row.language, row.origin.rawValue, row.status.rawValue]
            cells += [row.response.map(String.init) ?? "", row.setting.rawValue, row.activity?.rawValue ?? "", row.coping.rawValue]
            cells += [contexts[row.id]?.label ?? "Unknown", row.sourceLinks?.map(\.sourceID).joined(separator: "|") ?? ""]
            output.append(cells)
        }
        return output.map(ReportCSV.row).joined(separator: "\r\n") + "\r\n"
    }

    private struct Source {
        let observations: [DaytimeCheckIn]
        let events: [DaytimeEvent]
        let napDocument: NapDiaryDocument?
        let markers: [NapTimerMarker]
        let work: WorkContextDocument?
        let medication: DashboardContextTimeline?
        init(_ snapshot: CloudDashboardSnapshot) throws {
            var cache = CloudDashboardCache(accountScope: "companion", sourceID: snapshot.sourceID)
            try cache.accept(snapshot, accountScope: "companion", now: snapshot.capturedAt)
            func rows(_ dataset: DashboardDataset) throws -> [Row] {
                guard let data = snapshot.sections.first(where: { $0.dataset == dataset })?.rows else {
                    throw DashboardSnapshotError.incompleteDataset
                }
                return try JSONDecoder().decode([Row].self, from: data)
            }
            let diary = try rows(.daytimeDiary)
            let revisions = try diary.filter { $0.sourceTable == "daytime_checkins" }.map { row in
                let value = try DaytimeCheckIn.decode(row.required("payload"))
                guard try row.required("revision_id") == value.revisionID.uuidString,
                      try row.required("observation_id") == value.id.uuidString, value.recordedAt <= snapshot.capturedAt else { throw DaytimeDiaryError.invalid }
                return value
            }
            observations = try DaytimeCheckInLedger(revisions: revisions).current
            let eventRevisions = try diary.filter { $0.sourceTable == "daytime_events" }.map { row in
                let value = try DaytimeEvent.decode(row.required("payload"))
                guard try row.required("revision_id") == value.revisionID.uuidString,
                      try row.required("event_id") == value.id.uuidString, value.recordedAt <= snapshot.capturedAt else { throw DaytimeDiaryError.invalid }
                return value
            }
            events = try DaytimeEventLedger(revisions: eventRevisions).current
            let napRows = diary.filter { $0.sourceTable == "nap_diary" }
            guard napRows.count <= 1 else { throw DaytimeDiaryError.invalid }
            napDocument = try napRows.first.map { row in
                let value = try JSONDecoder().decode(NapDiaryDocument.self, from: Data(row.required("payload").utf8))
                guard row.columns["id"]?.integer == 1, value.isValid,
                      value.episodes.allSatisfy({ $0.recordedAt <= snapshot.capturedAt }),
                      value.reviews.allSatisfy({ $0.recordedAt <= snapshot.capturedAt }) else { throw DaytimeDiaryError.invalid }
                return value
            }
            let time = ISO8601DateFormatter(); time.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            markers = try rows(.quickLogs).filter { ["nap_start", "nap_end"].contains($0.text("event_type") ?? "") }.map { row in
                let raw = try row.required("timestamp")
                guard row.sourceTable == "sleep_events", let date = time.date(from: raw) ?? plain.date(from: raw), date <= snapshot.capturedAt else { throw DaytimeDiaryError.invalid }
                return NapTimerMarker(id: try row.required("id"), sessionID: row.text("session_id"), date: date, isStart: row.text("event_type") == "nap_start")
            }
            guard Set(markers.map(\.id)).count == markers.count else { throw DaytimeDiaryError.invalid }
            let workRows = try rows(.workSchedule).filter { $0.sourceTable == "work_block_context" }
            guard workRows.count <= 1 else { throw DaytimeDiaryError.invalid }
            work = try workRows.first.map { row in
                let value = try JSONDecoder().decode(WorkContextDocument.self, from: Data(row.required("payload").utf8))
                guard value.isValid else { throw DaytimeDiaryError.invalid }; return value
            }
            let presets = try rows(.presetVersions).filter { $0.sourceTable == "medication_preset_revisions" }.map { try $0.required("payload") }
            let actual = try rows(.administrations).filter { $0.sourceTable == "confirmed_medication_administrations" }.map { try $0.required("payload") }
            medication = try DashboardContextTimeline(presets: .init(presetRevisions: presets, administrations: actual), content: [], capturedAt: snapshot.capturedAt)
        }
    }
    private struct Row: Decodable {
        struct Column: Decodable { let type: String; let text: String?; let integer: Int64? }
        let sourceTable: String
        let columns: [String: Column]
        func text(_ key: String) -> String? { columns[key]?.type == "text" ? columns[key]?.text : nil }
        func required(_ key: String) throws -> String {
            guard let value = text(key) else { throw DaytimeDiaryError.unreadable }; return value
        }
    }
}
