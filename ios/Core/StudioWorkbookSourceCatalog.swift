import Foundation

struct StudioWorkbookData {
    let root: SWObject
    let groupRoot: String
    let timezone: TimeZone
    let timezoneNote: String
    let groups: [SWGroup]
    let records: [SWRecord]
    let issues: [SWIssue]
    let inventoryCSV: String
    let sourceSHA256: [String: String]
    let cache: SWProjectionCache
    var timestamps: SWTimestampParser { cache.timestamps }

    init(bundleData: Data, inventoryCSV: String) throws {
        guard let root = try JSONSerialization.jsonObject(with: bundleData) as? SWObject,
              let version = root["schemaVersion"] as? Int, [1, 2, 3, 4].contains(version) else {
            throw StudioWorkbookProjectionError.unsupportedBundle
        }
        let groupRoot = version >= 3 ? "dateGroups" : "sessions"
        guard root[version >= 3 ? "sessions" : "dateGroups"] == nil,
              let input = root[groupRoot] as? [SWObject] else { throw StudioWorkbookProjectionError.unsupportedBundle }
        self.root = root; self.groupRoot = groupRoot; self.inventoryCSV = inventoryCSV
        sourceSHA256 = ["insights_bundle.json": SW.sha256(bundleData), "inventory.csv (UTF-8 input)": SW.sha256(Data(inventoryCSV.utf8))]
        let timezoneID = SW.string(root["timeZoneIdentifier"])
        let displayTimezone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: 0)!
        timezone = displayTimezone
        let cache = SWProjectionCache(timezone: displayTimezone); self.cache = cache
        timezoneNote = timezoneID.flatMap(TimeZone.init(identifier:)) != nil
            ? "Local display: \(timezone.identifier). UTC columns retain absolute time."
            : "Export timezone unavailable; local display uses UTC. Historical local time is not inferred from today's offset."
        var groups: [SWGroup] = [], records: [SWRecord] = [], issues: [SWIssue] = []
        var recordIndexes: [String: [Int]] = [:], canonicalPayloads: [String] = []
        for (index, item) in input.enumerated() {
            let identity = SW.object(item["identityResolution"])
            guard version < 3 || (!identity.isEmpty && identity["sessionIds"] is [String] && identity["reasons"] is [String])
            else { throw StudioWorkbookProjectionError.unsupportedBundle }
            let date = SW.string(item["sessionDate"]) ?? "Date unavailable"
            var reasons = identity["reasons"] as? [String] ?? []
            if version < 3 { reasons.append("Legacy archive has no verified identity resolution") }
            else if (identity["version"] as? Int) != 1 || SW.string(identity["status"]) != "resolved" {
                reasons.append("Identity is not supported resolved version 1")
            }
            if Set(identity["sessionIds"] as? [String] ?? []).count > 1 {
                reasons.append("Multiple session identities contradict a combined night")
            }
            if cache.timestamps.day(date) == nil { reasons.append("Invalid or missing treatment date") }
            groups.append(SWGroup(key: "\(groupRoot)[\(index)]", date: date, original: item, originalIndex: index, issues: reasons))
        }
        let dates = Dictionary(grouping: groups, by: \.date)
        for index in groups.indices where (dates[groups[index].date]?.count ?? 0) > 1 {
            groups[index].issues.append("Multiple exported date groups share this treatment date")
        }
        var declaredDates: [String: Set<String>] = [:]
        for group in groups {
            let identity = SW.object(group.original["identityResolution"])
            for id in identity["sessionIds"] as? [String] ?? [] {
                declaredDates[id, default: []].insert(group.date)
            }
        }
        for index in groups.indices {
            let identity = SW.object(groups[index].original["identityResolution"])
            if (identity["sessionIds"] as? [String] ?? []).contains(where: { (declaredDates[$0]?.count ?? 0) > 1 }) {
                groups[index].issues.append("Declared session identity spans multiple treatment dates")
            }
        }
        // Source table + original ID is the identity. Equal payloads merge associations; differing payloads survive.
        func register(table: String, id: String?, fields: SWObject, payload: SWObject,
                      representation: String, group: SWGroup?, path: String) {
            let recordID = id ?? "derived-path:\(path)"
            let baseKey = table + ":" + recordID
            let serialized = SW.canonical(payload), candidates = recordIndexes[baseKey] ?? []
            if let index = candidates.first(where: { canonicalPayloads[$0] == serialized }) {
                if let group { records[index].groupKeys.insert(group.key); records[index].dates.insert(group.date) }
                return
            }
            let variant = candidates.count + 1
            recordIndexes[baseKey, default: []].append(records.count); canonicalPayloads.append(serialized)
            records.append(SWRecord(key: baseKey + "#\(variant)", baseKey: baseKey, id: recordID, table: table,
                representation: representation, payload: payload, fields: fields,
                groupKeys: Set(group.map { [$0.key] } ?? []), dates: Set(group.map { [$0.date] } ?? [])))
        }
        for group in groups {
            for (index, source) in SW.objects(group.original["rawSourceRecords"]).enumerated() {
                let table = SW.string(source["sourceTable"]) ?? "unknown_source_table"
                let columns = SW.object(source["columns"])
                var fields: SWObject = [:]
                for (key, column) in columns {
                    let value = SW.object(column), type = SW.string(value["type"])
                    switch type {
                    case "null": fields[key] = NSNull()
                    case "text": fields[key] = value["text"] ?? NSNull()
                    case "integer": fields[key] = value["integer"] ?? NSNull()
                    case "real": fields[key] = value["real"] ?? NSNull()
                    case "blob": fields[key] = value["blobBase64"] ?? NSNull()
                    default: fields[key] = column
                    }
                }
                let id = (fields["id"] as? String) ?? (fields["id"] as? NSNumber)?.stringValue
                    ?? (table == "sleep_sessions" ? SW.string(fields["session_id"]) : nil)
                register(table: table, id: id, fields: fields, payload: source, representation: "Original typed SQLite row",
                         group: group, path: group.key + "/rawSourceRecords[\(index)]")
            }
        }
        for group in groups {
            for (index, event) in SW.objects(group.original["rawEvents"]).enumerated() {
                let table = SW.string(event["sourceTable"]) ?? "events"
                let id = SW.string(event["id"])
                if let id, records.contains(where: { $0.baseKey == table + ":" + id && $0.representation == "Original typed SQLite row" }) { continue }
                register(table: table, id: id, fields: event, payload: event, representation: "Original event export",
                         group: group, path: group.key + "/rawEvents[\(index)]")
            }
            for (index, medication) in SW.objects(group.original["medications"]).enumerated() {
                register(table: "medication_events", id: SW.string(medication["id"]), fields: medication, payload: medication,
                         representation: "Original medication export", group: group, path: group.key + "/medications[\(index)]")
            }
            // Older archives may contain only summary representations. Mark their provenance, never count both views.
            for (field, table, type) in [("preSleep", "pre_sleep_logs", "pre_night"), ("morning", "morning_checkins", "morning")] {
                let summary = SW.object(group.original[field])
                guard !summary.isEmpty, !records.contains(where: { $0.table == table && $0.groupKeys.contains(group.key) }) else { continue }
                let submission = SW.objects(group.original["checkInSubmissions"]).first { SW.string($0["checkInType"]) == type }
                let id = SW.string(submission?["sourceRecordId"])
                register(table: table, id: id, fields: summary, payload: summary, representation: "Summary only; original row unavailable",
                         group: group, path: group.key + "/" + field)
            }
            for (index, submission) in SW.objects(group.original["checkInSubmissions"]).enumerated() {
                let id = SW.string(submission["id"])
                if let id, records.contains(where: { $0.baseKey == "checkin_submissions:" + id }) { continue }
                register(table: "checkin_submissions", id: id, fields: submission, payload: submission,
                         representation: "Submission export", group: group, path: group.key + "/checkInSubmissions[\(index)]")
            }
        }
        let inventory = try Self.parseCSV(inventoryCSV)
        if let headers = inventory.first {
            guard Set(headers).count == headers.count, !headers.contains("") else { throw StudioWorkbookProjectionError.malformedInventory }
            let numeric = Set(["bottles_remaining", "doses_remaining", "estimated_days_left"])
            for (index, row) in inventory.dropFirst().enumerated() {
                guard row.count == headers.count else { throw StudioWorkbookProjectionError.malformedInventory }
                var fields: SWObject = [:]
                for (key, value) in zip(headers, row) {
                    if numeric.contains(key), let number = Double(value), number.isFinite { fields[key] = number }
                    else { fields[key] = value }
                }
                register(table: "inventory", id: SW.string(fields["id"]), fields: fields, payload: fields,
                         representation: "Inventory CSV record", group: nil, path: "inventory.csv/row[\(index + 2)]")
            }
        }
        let variants = Dictionary(grouping: records.indices, by: { records[$0].baseKey })
        for indexes in variants.values {
            for index in indexes { records[index].variantCount = indexes.count }
            guard indexes.count > 1 else { continue }
            let affected = Set(indexes.flatMap { records[$0].groupKeys })
            for index in groups.indices where affected.contains(groups[index].key) { groups[index].issues.append("Conflicting source record variants") }
            issues.append(SWIssue(group: affected.sorted().joined(separator: "; "),
                date: Set(indexes.flatMap { records[$0].dates }).sorted().joined(separator: "; "),
                category: "Conflicting source variants", reason: "All \(indexes.count) payload variants are retained; combined metrics are excluded.",
                source: records[indexes[0]].baseKey))
        }
        for record in records where record.dates.count > 1 {
            for index in groups.indices where record.groupKeys.contains(groups[index].key) { groups[index].issues.append("Source record associated with multiple dates") }
            issues.append(SWIssue(group: record.groupKeys.sorted().joined(separator: "; "), date: record.dateLabel,
                category: "Multiple-date source association", reason: "The original appears once; every exported date association is retained.", source: record.key))
        }
        for group in groups {
            for reason in Set(group.issues).sorted() {
                issues.append(SWIssue(group: group.key, date: group.date, category: "Identity exclusion", reason: reason, source: group.key))
            }
            for reason in (group.original["dataQualityFlags"] as? [String] ?? []) + (group.original["exportExclusionReasons"] as? [String] ?? []) {
                issues.append(SWIssue(group: group.key, date: group.date, category: "Export quality flag", reason: reason, source: group.key))
            }
        }
        for reason in root["exportWarnings"] as? [String] ?? [] {
            issues.append(SWIssue(group: "", date: "", category: "Export warning", reason: reason, source: "insights_bundle.json"))
        }
        self.groups = groups.sorted { $0.date == $1.date ? $0.key < $1.key : $0.date > $1.date }
        self.records = records.sorted { $0.dateSort == $1.dateSort ? $0.key < $1.key : $0.dateSort > $1.dateSort }
        self.issues = issues.sorted { $0.category == $1.category ? $0.date > $1.date : $0.category < $1.category }
    }

    /// RFC 4180 quoted fields, including embedded commas/newlines. Invalid rows fail publication.
    private static func parseCSV(_ input: String) throws -> [[String]] {
        guard !input.isEmpty else { return [] }
        let text = input.hasPrefix("\u{FEFF}") ? String(input.dropFirst()) : input
        let chars = Array(text); var i = 0, quoted = false, closed = false, field = "", row: [String] = [], rows: [[String]] = []
        func finishField() { row.append(field); field = ""; closed = false }
        func finishRow() { finishField(); rows.append(row); row = [] }
        while i < chars.count {
            let ch = chars[i]
            if quoted {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(ch) }
            } else if ch == "," { finishField() }
            else if ch == "\n" || ch == "\r" || ch == "\r\n" {
                finishRow(); if ch == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
            } else if ch == "\"", field.isEmpty, !closed { quoted = true }
            else {
                guard !closed && ch != "\"" else { throw StudioWorkbookProjectionError.malformedInventory }
                field.append(ch)
            }
            i += 1
        }
        guard !quoted else { throw StudioWorkbookProjectionError.malformedInventory }
        if !field.isEmpty || !row.isEmpty || closed { finishRow() }
        return rows
    }

    func records(table: String) -> [SWRecord] { records.filter { $0.table == table } }
    func group(for record: SWRecord) -> SWGroup? {
        guard record.groupKeys.count == 1, let key = record.groupKeys.first else { return nil }
        return groups.first { $0.key == key }
    }
    func identity(for record: SWRecord) -> String {
        record.variantCount > 1 || record.dates.count > 1 || record.groupKeys.contains(where: { key in groups.first { $0.key == key }?.eligible != true })
            ? "Needs record review" : "Resolved"
    }
    func timestampCell(_ value: Any?) -> WorkbookCell { timestamps.parse(value).map(WorkbookCell.date) ?? .blank }
    func sourceCell(_ value: Any?, key: String = "") -> WorkbookCell {
        if SW.isTimestamp(key), let date = timestamps.parse(value) { return .date(date) }
        return SW.cell(value, key: key)
    }
}
