import Foundation

public enum DashboardQuestionnaireStatus: String, CaseIterable, Sendable {
    case missing, recorded, complete, partial, skipped, conflict, unavailable
}

public struct DashboardQuestionnaireDay: Identifiable, Sendable {
    public var id: String { treatmentDate }
    public let treatmentDate: String
    public let morning: DashboardQuestionnaireStatus
    public let preSleep: DashboardQuestionnaireStatus
    public let nightOutcome: DashboardQuestionnaireStatus
    public let recordedSleepQuality: Double?
    public var sleepQualityProvenance: String? {
        recordedSleepQuality == nil ? nil : "Stored rating; freshness and confirmation unknown"
    }
    /// Stored diary answer; this projection does not verify a current dose association.
    public let dose2WakeMethod: Dose2WakeKind?
    public let followingDay: FollowingDayKind?
    public let sourceRecordIDs: [String]
    public let outcomeSessionID: String?
    /// Actual normalized submission row ID, for source inspection.
    public let outcomeSourceRecordID: String?
    public let outcomeRecordedAt: Date?
    public let reportedFinalWakeAt: Date?
    public let sleepiness0To10: Int?
    public let sleepinessAssessedAt: Date?
}

/// Local questionnaire evidence only. Stored defaults are not confirmed answers.
public struct DashboardQuestionnaireProjection: Sendable {
    public let sourceID: String
    public let capturedAt: Date
    public let days: [DashboardQuestionnaireDay]
    public let unassignedPreSleepCount: Int
    /// Source rows, not distinct questionnaires; normalized copies may overlap.
    public let unassignedSourceRowCount: Int

    public func selected(count: Int, timeZone: TimeZone) -> [DashboardQuestionnaireDay] {
        let keys = days.map { DashboardReportDoseDay(treatmentDate: $0.treatmentDate,
            intervalMinutes: nil, state: .missing, dose1At: nil, dose2At: nil) }
        let selected = Set(DashboardReportStatistics.selected(keys, count: count,
            capturedAt: capturedAt, timeZone: timeZone).map(\.treatmentDate))
        return days.filter { selected.contains($0.treatmentDate) }
    }

    public init(snapshot: CloudDashboardSnapshot, now: Date) throws {
        var validator = CloudDashboardCache(accountScope: "questionnaire", sourceID: snapshot.sourceID)
        try validator.accept(snapshot, accountScope: "questionnaire", now: now)
        sourceID = snapshot.sourceID; capturedAt = snapshot.capturedAt
        func rows(_ dataset: DashboardDataset, _ tables: Set<String>) throws -> [QuestionnaireRow] {
            guard let data = snapshot.sections.first(where: { $0.dataset == dataset })?.rows else {
                throw DashboardSnapshotError.incompleteDataset
            }
            let rows = try JSONDecoder().decode([QuestionnaireRow].self, from: data)
            guard rows.allSatisfy({ tables.contains($0.sourceTable) }) else { throw DashboardSnapshotError.invalidPayload }
            return rows
        }
        let morning = try rows(.morning, ["morning_checkins"])
        let pre = try rows(.preSleep, ["pre_sleep_logs"])
        let submissions = try rows(.normalizedAnswers, ["checkin_submissions"])
        let evidence = try rows(.sessions, ["sleep_sessions", "current_session"])
            + rows(.doseEvents, ["dose_events"]) + rows(.quickLogs, ["sleep_events"])
            + rows(.medicationEntries, ["medication_events"]) + morning + submissions
        var identities: [String: Set<String>] = [:], dates: [String: Set<String>] = [:]
        var keys = Set((morning + submissions).compactMap { row -> String? in
            guard let date = row.text("session_date"), Self.isDate(date) else { return nil }
            return date
        })
        for row in evidence {
            guard row.validIdentity else { throw DashboardSnapshotError.invalidPayload }
            guard let key = row.text("session_date"), Self.isDate(key) else {
                // Missing dates contribute to unassigned counts below, not to
                // the set of distinct known dates for a durable identity.
                continue
            }
            if let identity = row.text("session_id"), !identity.isEmpty, identity != key {
                identities[key, default: []].insert(identity); dates[identity, default: []].insert(key)
            }
        }
        var outcomeDates: [String: Set<String>] = [:]
        for row in submissions where row.text("checkin_type") == "night_outcome" {
            if let identity = row.text("session_id"), !identity.isEmpty,
               let key = row.text("session_date"), Self.isDate(key) {
                outcomeDates[identity, default: []].insert(key)
            }
        }
        var preByDate: [String: [QuestionnaireRow]] = [:], ambiguousPre = Set<String>(), unassigned = 0
        for row in pre {
            guard row.validIdentity, let id = row.text("id"), !id.isEmpty else { throw DashboardSnapshotError.invalidPayload }
            var linked = Set(submissions.filter { $0.text("checkin_type") == "pre_night" && $0.text("source_record_id") == id }
                .compactMap { $0.text("session_date") }.filter(Self.isDate))
            if let identity = row.text("session_id"), !identity.isEmpty {
                linked.formUnion(Self.isDate(identity) ? [identity] : dates[identity, default: []].filter(Self.isDate))
            }
            if linked.isEmpty { unassigned += 1 }
            for key in linked {
                keys.insert(key); preByDate[key, default: []].append(row)
                if linked.count > 1 { ambiguousPre.insert(key) }
                if let identity = row.text("session_id"), !identity.isEmpty, identity != key {
                    identities[key, default: []].insert(identity); dates[identity, default: []].insert(key)
                }
            }
        }
        unassignedPreSleepCount = unassigned
        unassignedSourceRowCount = unassigned + (morning + submissions).filter {
            $0.text("session_date").map(Self.isDate) != true
        }.count
        days = keys.sorted(by: >).map { key in
            let m = morning.filter { $0.text("session_date") == key }, p = preByDate[key, default: []]
            let s = submissions.filter { $0.text("session_date") == key }
            let o = s.filter { $0.text("checkin_type") == "night_outcome" }
            let mCopies = s.filter { $0.text("checkin_type") == "morning" }
            let pCopies = s.filter { $0.text("checkin_type") == "pre_night" }
            let conflict = identities[key, default: []].count > 1 || ambiguousPre.contains(key)
                || identities[key, default: []].contains { dates[$0, default: []].count > 1 }
                || m.count > 1 || p.count > 1 || o.count > 1 || mCopies.count > 1 || pCopies.count > 1
                || mCopies.contains { $0.text("source_record_id") != m.first?.text("id") }
                || pCopies.contains { $0.text("source_record_id") != p.first?.text("id") }
            var mState: DashboardQuestionnaireStatus = m.isEmpty ? .missing : .recorded
            var pState: DashboardQuestionnaireStatus = p.isEmpty ? .missing : .unavailable
            var oState: DashboardQuestionnaireStatus = o.isEmpty ? .missing : .unavailable
            var quality: Double?, wake: Dose2WakeKind?, following: FollowingDayKind?
            var diary: QuestionnaireOutcome?, diaryIdentity: String?, diarySource: String?
            if conflict {
                if !m.isEmpty || !mCopies.isEmpty { mState = .conflict }
                if !p.isEmpty || !pCopies.isEmpty { pState = .conflict }
            } else {
                if let row = m.first {
                    if let number = row.number("sleep_quality"), number.isFinite, (1...5).contains(number) { quality = number }
                    else if row.columns["sleep_quality"]?.type != nil && row.columns["sleep_quality"]?.type != "null" { mState = .unavailable }
                }
                if let state = p.first?.text("completion_state") {
                    pState = ["complete": .complete, "partial": .partial, "skipped": .skipped][state] ?? .unavailable
                }
            }
            // A valid diary is an observation even when it cannot join the dose
            // ledger. Only this diary's ambiguity suppresses its own answers.
            let outcomeConflict = o.count > 1 || o.contains { row in
                row.text("session_id").map { dates[$0, default: []].count > 1 || outcomeDates[$0, default: []].count > 1 } ?? false
            }
            if outcomeConflict { oState = .conflict }
            else if let row = o.first, row.text("questionnaire_version") == "night_outcome.v1",
               let identity = row.text("session_id"), !identity.isEmpty,
               row.text("source_record_id") == identity, let raw = row.text("responses_json") {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                if let outcome = try? decoder.decode(QuestionnaireOutcome.self, from: Data(raw.utf8)),
                   outcome.recordedAt.timeIntervalSince1970.isFinite,
                   outcome.recordedAt <= snapshot.capturedAt,
                   outcome.answers.validationError(now: outcome.recordedAt) == nil,
                   outcome.answers.reviewedSleepWindow.map({ $0.sessionID == identity }) ?? true {
                    oState = .recorded
                    diary = outcome; diaryIdentity = identity; diarySource = row.text("id")
                    wake = outcome.answers.wakeMethod == .unknown ? nil : outcome.answers.wakeMethod
                    following = outcome.answers.dayType == .unknown ? nil : outcome.answers.dayType
                }
            }
            let sources = (m + p + s).compactMap { row in row.text("id").map { "\(row.sourceTable):\($0)" } }.sorted()
            return DashboardQuestionnaireDay(treatmentDate: key, morning: mState, preSleep: pState,
                nightOutcome: oState, recordedSleepQuality: quality, dose2WakeMethod: wake,
                followingDay: following, sourceRecordIDs: sources,
                outcomeSessionID: diaryIdentity, outcomeSourceRecordID: diarySource,
                outcomeRecordedAt: diary?.recordedAt, reportedFinalWakeAt: diary?.answers.finalWakeAt,
                sleepiness0To10: diary?.answers.sleepiness, sleepinessAssessedAt: diary?.answers.assessedAt)
        }
    }

    private static func isDate(_ key: String) -> Bool {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter.date(from: key).map { formatter.string(from: $0) == key } ?? false
    }
}

private struct QuestionnaireRow: Decodable {
    let sourceTable: String
    let columns: [String: QuestionnaireColumn]
    func text(_ key: String) -> String? { columns[key]?.type == "text" ? columns[key]?.text : nil }
    func number(_ key: String) -> Double? {
        guard let column = columns[key] else { return nil }
        return column.type == "real" ? column.real : column.type == "integer" ? column.integer.map(Double.init) : nil
    }
    var validIdentity: Bool {
        guard let column = columns["session_id"] else { return true }
        return column.type == "null" || (column.type == "text" && column.text != nil)
    }
}
private struct QuestionnaireColumn: Decodable {
    let type: String
    let text: String?
    let integer: Int64?
    let real: Double?
}
/// Wire shape mirrors the app's NightOutcomeRecord. Required fields and typed
/// revision entries must decode even though this view displays only current answers.
private struct QuestionnaireOutcome: Decodable {
    struct Revision: Decodable {
        let answers: NightOutcomeDiary
        let recordedAt: Date
        let reason: String
    }
    let answers: NightOutcomeDiary
    let recordedAt: Date
    let revisions: [Revision]
}
