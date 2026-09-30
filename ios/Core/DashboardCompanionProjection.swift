import Foundation

/// Typed reporting inputs retain stable source identities and frozen capture time.
public struct DashboardCompanionProjection: Sendable {
    public struct Night: Identifiable, Sendable {
        public let id: String
        public let sessionID: String?
        public let treatmentDate: String
        public let pattern: DashboardDosePattern
        public let administrations: [DashboardDosePattern.Administration]
        public let sourceRecordIDs: [String]
        public let reviewRevisionID: UUID?
        public let identityResolved: Bool
    }
    public let sourceID: String
    public let sequence: UInt64
    public let capturedAt: Date
    public let nights: [Night]
    public let unassignedIdentityRowCount: Int
    public let checkIns: DaytimeCheckInLedger?
    public let daytimeEvents: DaytimeEventLedger?
    public let daytimeIssue: String?
    public let workContext: WorkContextDocument?
    public let workIssue: String?
    public let completedVisits: PhysicianVisitLedger?

    public init(snapshot: CloudDashboardSnapshot, now: Date) throws {
        var cache = CloudDashboardCache(accountScope: "companion", sourceID: snapshot.sourceID)
        try cache.accept(snapshot, accountScope: "companion", now: now)
        sourceID = snapshot.sourceID; sequence = snapshot.sequence; capturedAt = snapshot.capturedAt
        completedVisits = snapshot.completedVisits
        let doses = try Self.rows(.doseEvents, snapshot)
        let sessions = try Self.rows(.sessions, snapshot)
        let logs = try Self.rows(.quickLogs, snapshot)
        let morning = try Self.rows(.morning, snapshot)
        let outcomes = try Self.rows(.normalizedAnswers, snapshot).filter { $0.text("checkin_type") == "night_outcome" }
        let identityRows = doses + sessions + logs + morning + outcomes
        var identityDates: [String: Set<String>] = [:]
        var unassignedCount = 0, unresolvedIDs = Set<String>()
        for row in identityRows {
            if row.sourceTable == "current_session", row.text("session_id") == nil { continue }
            guard let day = row.text("session_date"), DashboardReportingWindow.isValidDateKey(day) else {
                unassignedCount += 1
                if let id = row.text("session_id"), !id.isEmpty { unresolvedIDs.insert(id) }
                continue
            }
            if let id = row.text("session_id"), !id.isEmpty, id != day { identityDates[id, default: []].insert(day) }
        }
        unassignedIdentityRowCount = unassignedCount
        func identity(_ row: Row) -> (String, String?) {
            let day = row.text("session_date") ?? ""
            guard let id = row.text("session_id"), !id.isEmpty, id != day else { return ("legacy:" + day, nil) }
            return identityDates[id]?.count == 1 && !unresolvedIDs.contains(id) ? ("session:" + id, id) : ("unresolved:" + id + ":" + day, nil)
        }
        var groups: [String: [Row]] = [:]
        for row in identityRows {
            if row.sourceTable == "current_session", row.text("session_id") == nil { continue }
            guard let day = row.text("session_date"), DashboardReportingWindow.isValidDateKey(day) else { continue }
            groups[identity(row).0, default: []].append(row)
        }
        let reviews = Dictionary(uniqueKeysWithValues: (snapshot.doseReviews ?? []).map { ($0.observationID, $0) })
        nights = try groups.keys.sorted().map { key in
            let rows = groups[key]!
            let first = rows[0], sessionID = identity(first).1, day = try first.required("session_date")
            let evidence = rows.filter { $0.sourceTable == "dose_events" }
            var administrations: [DashboardDosePattern.Administration] = []
            var skipped = false, invalid = sessionID == nil
            for row in evidence {
                let kind = CompanionDoseKind(canonicalizing: try row.required("event_type"))
                let id = try row.required("id")
                let at = Self.timestamp(row.text("timestamp"))
                if at == nil || at! > snapshot.capturedAt { invalid = true }
                switch kind {
                case .dose1, .dose2:
                    administrations.append(.init(id: id, sessionID: sessionID ?? key,
                        slot: kind == .dose1 ? 1 : 2, occurredAt: at))
                case .dose2Skipped: skipped = true
                case .extraDose: administrations.append(.init(id: id, sessionID: sessionID ?? key, slot: 3, occurredAt: at))
                case .snooze, .historyCorrection: break
                case nil: invalid = true
                }
            }
            let closed = rows.contains { $0.text("end_utc") != nil || $0.text("session_end_utc") != nil || $0.sourceTable == "morning_checkins" }
            let active = !closed && rows.contains { $0.sourceTable == "current_session" && $0.text("terminal_state") == nil && ($0.text("session_start_utc") != nil || $0.text("dose1_time") != nil) }
            let review = reviews[key]
            invalid = invalid || (skipped && review?.secondNotTaken == false)
            let pattern = DashboardDosePattern.derive(sessionID: invalid ? "" : (sessionID ?? key),
                administrations: administrations, confirmedCount: review?.confirmedCount,
                historicalPlanCount: review?.historicalPlanCount, secondNotTaken: skipped || review?.secondNotTaken == true,
                sessionOpen: active)
            return Night(id: key, sessionID: sessionID, treatmentDate: day, pattern: pattern,
                administrations: administrations, sourceRecordIDs: evidence.compactMap { $0.text("id") },
                reviewRevisionID: review?.revisionID, identityResolved: sessionID != nil)
        }.sorted { $0.treatmentDate == $1.treatmentDate ? $0.id < $1.id : $0.treatmentDate > $1.treatmentDate }
        do {
            let daytime = try Self.rows(.daytimeDiary, snapshot)
            var checks: [DaytimeCheckIn] = [], events: [DaytimeEvent] = []
            for row in daytime {
                if row.sourceTable == "daytime_checkins" {
                    let value = try DaytimeCheckIn.decode(row.required("payload"))
                    guard try row.required("revision_id") == value.revisionID.uuidString,
                          try row.required("observation_id") == value.id.uuidString,
                          value.recordedAt <= snapshot.capturedAt else { throw DashboardSnapshotError.invalidPayload }
                    checks.append(value)
                } else if row.sourceTable == "daytime_events" {
                    let value = try DaytimeEvent.decode(row.required("payload"))
                    guard try row.required("revision_id") == value.revisionID.uuidString,
                          try row.required("event_id") == value.id.uuidString,
                          value.recordedAt <= snapshot.capturedAt else { throw DashboardSnapshotError.invalidPayload }
                    events.append(value)
                }
            }
            let checked = try DaytimeCheckInLedger(revisions: checks)
            let checkedEvents = try DaytimeEventLedger(revisions: events)
            checkIns = checked; daytimeEvents = checkedEvents
            daytimeIssue = nil
        } catch {
            checkIns = nil; daytimeEvents = nil
            daytimeIssue = "Daytime source records need review on the phone. Raw rows remain in this reporting copy; no daytime totals are calculated."
        }
        do {
            let contexts = try Self.rows(.workSchedule, snapshot).filter { $0.sourceTable == "work_block_context" }
            guard contexts.count <= 1 else { throw DashboardSnapshotError.invalidPayload }
            if let row = contexts.first {
                let document = try JSONDecoder().decode(WorkContextDocument.self, from: Data(row.required("payload").utf8))
                guard document.isValid, document.rosters.allSatisfy({ $0.recordedAt <= snapshot.capturedAt }),
                      document.occurrences.allSatisfy({ $0.recordedAt <= snapshot.capturedAt }),
                      document.associations.allSatisfy({ $0.recordedAt <= snapshot.capturedAt }) else { throw DashboardSnapshotError.invalidPayload }
                workContext = document
            } else { workContext = nil }
            workIssue = nil
        } catch {
            workContext = nil
            workIssue = "Work context source needs review on the phone. Raw rows remain in the report; no work-cycle classification is calculated."
        }
    }
    public func selected(range: DashboardReportingRange, timeZone: TimeZone) -> [Night] {
        guard let window = range.window(asOf: capturedAt, timeZone: timeZone) else { return [] }
        return nights.filter { window.contains($0.treatmentDate) }
    }
    struct Row: Decodable {
        struct Column: Decodable { let type: String; let text: String?; let integer: Int64? }
        let sourceTable: String
        let columns: [String: Column]
        func text(_ key: String) -> String? { columns[key]?.type == "text" ? columns[key]?.text : nil }
        func required(_ key: String) throws -> String {
            guard let value = text(key), !value.isEmpty else { throw DashboardSnapshotError.invalidPayload }; return value
        }
    }
    static func rows(_ dataset: DashboardDataset, _ snapshot: CloudDashboardSnapshot) throws -> [Row] {
        guard let data = snapshot.sections.first(where: { $0.dataset == dataset })?.rows else { throw DashboardSnapshotError.incompleteDataset }
        return try JSONDecoder().decode([Row].self, from: data)
    }
    static func timestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: value) { return date }
        format.formatOptions = [.withInternetDateTime]; return format.date(from: value)
    }
}

private enum CompanionDoseKind: String, CaseIterable {
    case dose1 = "dose1"
    case dose2 = "dose2"
    case extraDose = "extra_dose"
    case dose2Skipped = "dose2_skipped"
    case snooze = "snooze"
    case historyCorrection = "history_correction"

    init?(canonicalizing rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "history_correction": self = .historyCorrection
        case "dose1", "dose_1", "dose1_taken", "dose_1_taken":
            self = .dose1
        case "dose2", "dose_2", "dose2_taken", "dose_2_taken",
             "dose2_early", "dose_2_early", "dose2_late", "dose_2_late",
             "dose_2_(early)", "dose_2_(late)":
            self = .dose2
        case "extra_dose", "extra_dose_taken", "extra", "dose3", "dose_3", "dose_3_taken":
            self = .extraDose
        case "dose2_skipped", "dose_2_skipped", "skip", "skipped":
            self = .dose2Skipped
        case "snooze", "dose2_snoozed":
            self = .snooze
        default:
            return nil
        }
    }

    var countsAsTakenDose: Bool {
        switch self {
        case .dose1, .dose2, .extraDose:
            return true
        case .dose2Skipped, .snooze, .historyCorrection:
            return false
        }
    }
}
