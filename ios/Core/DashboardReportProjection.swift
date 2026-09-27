import Foundation

public struct DashboardReportDoseDay: Identifiable, Sendable {
    public var id: String { treatmentDate }
    public let treatmentDate: String
    public let intervalMinutes: Double?
    public let status: String
}

public struct DashboardReportMedicationEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let amount: String
    public let occurredAt: Date?
    public let recordedAt: Date?
    /// Occurrence calendar date at the saved UTC offset, never the treatment key.
    public let calendarDate: String?
    public let sourceTable: String
    public let timePrecision: String
}

/// Reporting only. Envelope validation is not authentication or source verification.
public struct DashboardReportProjection: Sendable {
    public let sourceID: String
    public let capturedAt: Date
    public let doseDays: [DashboardReportDoseDay]
    public let medications: [DashboardReportMedicationEntry]
    public let doseEventCount: Int
    public let quickLogCount: Int
    public var validDosePairCount: Int { doseDays.filter { $0.intervalMinutes != nil }.count }
    public var unknownMedicationTimeCount: Int { medications.filter { $0.occurredAt == nil }.count }

    public init(snapshot: CloudDashboardSnapshot, now: Date) throws {
        var validator = CloudDashboardCache(accountScope: "projection", sourceID: snapshot.sourceID)
        try validator.accept(snapshot, accountScope: "projection", now: now)
        sourceID = snapshot.sourceID; capturedAt = snapshot.capturedAt
        func rows(_ dataset: DashboardDataset, table: String) throws -> [ReportRow] {
            guard let data = snapshot.sections.first(where: { $0.dataset == dataset })?.rows else {
                throw DashboardSnapshotError.incompleteDataset
            }
            let result = try JSONDecoder().decode([ReportRow].self, from: data)
            guard result.allSatisfy({ $0.sourceTable == table }) else { throw DashboardSnapshotError.invalidPayload }
            return result
        }
        let doses = try rows(.doseEvents, table: "dose_events")
        doseEventCount = doses.count
        quickLogCount = try rows(.quickLogs, table: "sleep_events").count
        var groups: [String: [ReportRow]] = [:]
        var identityDates: [String: Set<String>] = [:]
        for row in doses {
            let key = try row.required("session_date")
            let formatter = Self.dayFormatter()
            guard let date = formatter.date(from: key), formatter.string(from: date) == key else {
                throw DashboardSnapshotError.invalidPayload
            }
            groups[key, default: []].append(row)
            if let identity = row.text("session_id"), !identity.isEmpty {
                identityDates[identity, default: []].insert(key)
            }
        }
        doseDays = groups.keys.sorted(by: >).map { key in
            let records = groups[key]!
            let first = records.filter { Self.kind($0.text("event_type")) == "dose1" }
            let second = records.filter { Self.kind($0.text("event_type")) == "dose2" }
            let skipped = records.filter { Self.kind($0.text("event_type")) == "skip" }
            let identities = Set(records.compactMap { $0.text("session_id") }.filter { !$0.isEmpty })
            let ids = records.compactMap { $0.text("id") }.filter { !$0.isEmpty }
            var status = "Missing dose pair", interval: Double?
            let conflict = first.count > 1 || second.count > 1 || skipped.count > 1
                || (!second.isEmpty && !skipped.isEmpty) || identities.count > 1
                || identities.contains { identityDates[$0, default: []].count > 1 }
                || Set(ids).count != records.count || records.contains { Self.kind($0.text("event_type")) == nil }
                || records.contains { $0.columns["session_id"].map { !["null", "text"].contains($0.type) } ?? false }
            if conflict { status = "Conflicting records" }
            else if !skipped.isEmpty { status = "Dose 2 explicitly skipped" }
            else if let a = first.first, let b = second.first {
                if a.text("session_id") == b.text("session_id"),
                   let start = Self.timestamp(a.text("timestamp")), let end = Self.timestamp(b.text("timestamp")),
                   end > start, end <= now {
                    interval = end.timeIntervalSince(start) / 60; status = "Recorded dose pair"
                } else { status = "Conflicting records" }
            }
            return DashboardReportDoseDay(treatmentDate: key, intervalMinutes: interval, status: status)
        }
        var entries: [DashboardReportMedicationEntry] = []
        for row in try rows(.medicationEntries, table: "medication_events") {
            let id = try row.required("id"), name = try row.required("medication_id")
            guard let occurred = Self.timestamp(row.text("taken_at_utc")), occurred <= now,
                  let amount = row.integer("dose_mg") else { throw DashboardSnapshotError.invalidPayload }
            let minutes = row.integer("local_offset_minutes")
            let offset = minutes.flatMap { (-1080...1080).contains($0) ? Int($0 * 60) : nil }
            entries.append(.init(id: "medication_events:\(id)", name: name,
                amount: "\(amount) \(row.text("dose_unit") ?? "unit unknown")", occurredAt: occurred,
                recordedAt: Self.timestamp(row.text("created_at")), calendarDate: Self.day(occurred, offset),
                sourceTable: row.sourceTable, timePrecision: "legacy recorded time"))
        }
        for row in try rows(.administrations, table: "confirmed_medication_administrations") {
            let actual = try MedicationPresetExportSnapshot.decodeAdministration(row.required("payload"))
            guard try row.required("id") == actual.id.uuidString, actual.recordedAt <= now else {
                throw DashboardSnapshotError.invalidPayload
            }
            let amount = try actual.totalMilligrams
            entries.append(.init(id: "confirmed_medication_administrations:\(actual.id.uuidString)",
                name: actual.preset.labelName, amount: "\(amount) mg", occurredAt: actual.occurredAt,
                recordedAt: actual.recordedAt, calendarDate: actual.occurredAt.flatMap { Self.day($0, actual.utcOffsetSeconds) },
                sourceTable: row.sourceTable, timePrecision: actual.precision.rawValue))
        }
        guard Set(entries.map(\.id)).count == entries.count else { throw DashboardSnapshotError.invalidPayload }
        medications = entries.sorted {
            if $0.occurredAt != $1.occurredAt { return ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
            return $0.id < $1.id
        }
    }

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter
    }
    private static func day(_ date: Date, _ offset: Int?) -> String? {
        guard let offset, let zone = TimeZone(secondsFromGMT: offset) else { return nil }
        let formatter = dayFormatter(); formatter.timeZone = zone
        return formatter.string(from: date)
    }
    private static func timestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = iso.date(from: value) { return result }
        iso.formatOptions = [.withInternetDateTime]
        if let result = iso.date(from: value) { return result }
        let sql = dayFormatter(); sql.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let result = sql.date(from: value), sql.string(from: result) == value else { return nil }
        return result
    }
    private static func kind(_ value: String?) -> String? {
        let key = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_") ?? ""
        if ["dose1", "dose_1", "dose1_taken", "dose_1_taken"].contains(key) { return "dose1" }
        if ["dose2", "dose_2", "dose2_taken", "dose_2_taken", "dose2_early", "dose_2_early",
            "dose2_late", "dose_2_late", "dose_2_(early)", "dose_2_(late)"].contains(key) { return "dose2" }
        if ["dose2_skipped", "dose_2_skipped", "skip", "skipped"].contains(key) { return "skip" }
        return ["extra_dose", "extra_dose_taken", "extra", "dose3", "dose_3", "dose_3_taken",
            "snooze", "dose2_snoozed", "history_correction"].contains(key) ? "other" : nil
    }
}

private struct ReportRow: Decodable {
    let sourceTable: String
    let columns: [String: ReportColumn]
    func text(_ key: String) -> String? { columns[key]?.type == "text" ? columns[key]?.text : nil }
    func integer(_ key: String) -> Int64? { columns[key]?.type == "integer" ? columns[key]?.integer : nil }
    func required(_ key: String) throws -> String {
        guard let value = text(key), !value.isEmpty else { throw DashboardSnapshotError.invalidPayload }
        return value
    }
}
private struct ReportColumn: Decodable {
    let type: String
    let text: String?
    let integer: Int64?
}
