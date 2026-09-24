import Foundation
import CoreFoundation

struct SWSourceValue {
    let record: String
    let table: String
    let representation: String
    let dates: String
    let associations: String
    let identity: String
    let path: String
    let value: Any
    let kind: String
    let status: String
}

extension StudioWorkbookData {
    private func sourceValues() -> [SWSourceValue] {
        if let values = cache.sourceValues { return values }
        var output: [SWSourceValue] = []
        func flatten(_ value: Any, path: String, record: String, table: String, representation: String,
                     dates: String, associations: String, identity: String, parseStrings: Bool = true) {
            func append(_ value: Any, kind: String, status: String) {
                output.append(SWSourceValue(record: record, table: table, representation: representation, dates: dates,
                    associations: associations, identity: identity, path: path, value: value, kind: kind, status: status))
            }
            if value is NSNull { append(value, kind: "null", status: "Explicit null") }
            else if let dictionary = value as? SWObject {
                if dictionary.isEmpty { append("{}", kind: "object", status: "Empty object") }
                for key in dictionary.keys.sorted() {
                    let escaped = key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
                    flatten(dictionary[key]!, path: path + "/" + escaped, record: record, table: table, representation: representation,
                            dates: dates, associations: associations, identity: identity, parseStrings: parseStrings)
                }
            } else if let array = value as? [Any] {
                if array.isEmpty { append("[]", kind: "array", status: "Empty array") }
                for (index, child) in array.enumerated() {
                    flatten(child, path: path + "/\(index)", record: record, table: table, representation: representation,
                            dates: dates, associations: associations, identity: identity, parseStrings: parseStrings)
                }
            } else if let string = value as? String {
                append(string, kind: "text", status: string.isEmpty ? "Empty text" : "Recorded")
                let first = string.drop(while: { $0.isWhitespace }).first
                if parseStrings, first == "{" || first == "[", let parsed = SW.parse(string), parsed is SWObject || parsed is [Any] {
                    flatten(parsed, path: path + "/$parsed", record: record, table: table,
                            representation: representation + "; parsed JSON view", dates: dates, associations: associations,
                            identity: identity, parseStrings: false)
                }
            } else if let number = value as? NSNumber {
                let boolean = CFGetTypeID(number) == CFBooleanGetTypeID()
                append(number, kind: boolean ? "boolean" : "number", status: "Recorded")
            } else { append(SW.canonical(value), kind: "unrecognized", status: "Original representation retained") }
        }
        var metadata = root; metadata.removeValue(forKey: groupRoot)
        flatten(metadata, path: "", record: "bundle metadata", table: "bundle", representation: "Original export metadata",
                dates: "", associations: "", identity: "Not applicable")
        flatten(["workbookSchema": 1, "sourceSHA256": sourceSHA256, "tableGrains": Self.tableGrains], path: "/workbook",
                record: "workbook mapping manifest", table: "workbook_manifest", representation: "Workbook metadata; not a clinical observation",
                dates: "", associations: "", identity: "Not applicable")
        for group in groups {
            var value = group.original; value.removeValue(forKey: "rawSourceRecords")
            flatten(value, path: "/\(groupRoot)/\(group.originalIndex)", record: group.key, table: "date_group",
                    representation: "Export views; not additional original observations", dates: group.date,
                    associations: group.key, identity: group.identity)
        }
        for record in records {
            flatten(record.payload, path: "", record: record.key, table: record.table, representation: record.representation,
                    dates: record.dateLabel, associations: record.groupKeys.sorted().joined(separator: "; "), identity: identity(for: record))
            if record.representation == "Original typed SQLite row" {
                // An explicit typed-null column needs an inspectable value, not just the word "null" in its type tag.
                for (field, raw) in SW.object(record.payload["columns"]).sorted(by: { $0.key < $1.key }) {
                    let column = SW.object(raw), type = SW.string(column["type"]) ?? "unknown"
                    let value = record.fields[field] ?? NSNull()
                    flatten(value, path: "/$typed_values/" + field.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1"),
                            record: record.key, table: record.table, representation: "SQLite \(type) value; original type tag retained",
                            dates: record.dateLabel, associations: record.groupKeys.sorted().joined(separator: "; "), identity: identity(for: record))
                }
            }
        }
        if !inventoryCSV.isEmpty {
            flatten(inventoryCSV, path: "/inventory.csv", record: "inventory.csv", table: "inventory_file",
                    representation: "Original CSV text", dates: "", associations: "", identity: "Not applicable")
        }
        cache.sourceValues = output
        return output
    }

    func sourceFieldsSheet() -> WorkbookSheet {
        let columns = ["Source record", "Source table", "Representation", "Treatment dates", "Date groups", "Identity status", "Field reference",
            "Field path", "Part", "Parts", "Value type", "Value", "Value status", "Path part", "Path parts"]
        var rows: [[WorkbookCell]] = []
        for (fieldIndex, field) in sourceValues().enumerated() {
            let originalString = field.value as? String
            let text = originalString.map(SW.escapedControls)
            let valueParts = text.map { SW.chunks($0) } ?? [""]
            let pathParts = SW.chunks(SW.escapedControls(field.path)), count = max(valueParts.count, pathParts.count)
            let escaped = originalString != nil && originalString != text
            for index in 0..<count {
                let value: WorkbookCell
                if originalString != nil { value = index < valueParts.count ? .text(valueParts[index]) : .blank }
                else { value = index == 0 ? SW.cell(field.value) : .blank }
                rows.append([SW.text(field.record), SW.text(field.table), SW.text(field.representation + (escaped ? "; control characters escaped as \\uXXXX" : "")),
                    SW.text(field.dates), SW.text(field.associations), SW.text(field.identity), .text("field-\(fieldIndex + 1)"), SW.text(field.path),
                    .number(Double(index + 1)), .number(Double(count)), .text(field.kind), value,
                    .text(field.status), index < pathParts.count ? .text(pathParts[index]) : .blank, .number(Double(pathParts.count))])
            }
        }
        return SW.table("Source Fields", columns, rows, note: "Complete observed values and JSON-pointer paths, including unknown fields, original strings, parsed JSON and SQLite type tags. Reassemble numbered Value and Path part cells by Field reference (a snapshot-local workbook key, not a source ID). Control escapes are labeled. Date groups/Source record columns preserve record associations without a second table. Parsed/normalized export views are not extra observations. Binary payloads retain supplied base64. Keep the Studio archive for original bytes.")
    }

    func fieldGuideSheet() -> WorkbookSheet {
        let columns = ["Topic", "Field or metric", "Source path", "Observed type", "Unit or format", "Meaning and limitations",
            "Missingness", "Availability", "Owner review", "Owner notes"]
        var rows: [[WorkbookCell]] = []
        var observed: [String: (String, String, Set<String>)] = [:]
        let positions = try! NSRegularExpression(pattern: "/[0-9]+(?=/|$)")
        for field in sourceValues() {
            let path = positions.stringByReplacingMatches(in: field.path, range: NSRange(field.path.startIndex..., in: field.path), withTemplate: "/*")
            let key = field.table + "|" + path
            if var item = observed[key] { item.2.insert(field.kind); observed[key] = item }
            else { observed[key] = (field.table, path, [field.kind]) }
        }
        for key in observed.keys.sorted() {
            let (table, path, types) = observed[key]!
            let lower = path.lowercased(), units: String
            if lower.contains("minutes") { units = "Minutes, as exported" }
            else if lower.contains("hrv") { units = "Milliseconds; provider-specific method" }
            else if lower.contains("intensity") || lower.contains("sleepiness0to10") { units = "Recorded 0–10 rating" }
            else if lower.hasSuffix("utc") { units = "Original UTC timestamp; display values have typed UTC companions" }
            else { units = "Original source representation; no unit inferred" }
            rows.append([SW.text(table), SW.text(path.components(separatedBy: "/").last ?? path), SW.text(path),
                SW.text(types.sorted().joined(separator: "; ")), SW.text(units),
                .text("Observed source field. Source Fields retains values, identities, representations and numbered parts. Parsed views are not new observations."),
                .text("Absent, explicit null, empty text, zero and explicit answers remain distinct in Source Fields."), .text("Present in this export"), .blank, .blank])
        }
        let contracts: [(String, String, String)] = [
            ("Workbook schema", "2", "Reporting snapshot from one finalized Studio archive; not a tested full-app restore. Table filters do not change fixed Overview summaries."),
            ("Mean and median sleep", "Overview", "Finite nonnegative supplied totalSleepMinutes; zero is retained. One eligible date group per provider. Fixed 7/14/30/all ranges end on the latest exported treatment date."),
            ("Identity eligibility", "Nights / Included in summaries", "Resolved identity version 1, unique valid treatment date, no conflicting source variants or cross-date original associations. Unsupported/legacy identity is excluded."),
            ("Confirmed work context", "collectedNight/followingDayType", "Only recorded workday and dayOff answers define confirmed populations. Unknown/unsure/unanswered are not converted into either group."),
            ("Schedule estimates", "context/scheduleDayType", "Exported worklike/offlike recurring-wake estimates are frozen as exported. They are not verified historical shifts or attendance."),
            ("Work before/after and transitions", "Not fully available", "Do not infer work-block boundaries or 24-hour sleep categories from one Work Night label. Available shift fields remain in questionnaire/context source fields."),
            ("Dose-to-sleep clinical metrics", "Not exported", "Accepted reviewed dose/sleep metrics require their complete reviewed projection and evidence. This archive does not export those inputs; no replacement calculator is used."),
            ("Dose 2 interval evidence", "healthKit/recordedIntervals", "Intersecting awake intervals and next exported asleep start are direct evidence only. Gaps/conflicts remain visible. An interval duration is not a new clinical return-to-sleep metric."),
            ("Actual sleep after Dose 2", "collectedNight/estimatedSleepAfterDose2Minutes", "Use the supplied estimate with covered minutes, elapsed interval, final-wake basis and source. Elapsed time is not asleep time."),
            ("Per-interval stage/device/sample", "Unavailable in current archive", "Exported intervals contain start, end and asleep status only. Aggregate sources do not establish a device or stage for every interval."),
            ("Provider coverage", "healthKit / whoop / sourceAvailability", "Supplied episode/window evidence is not all Apple Health data or a complete 24-hour sleep total. WHOOP aggregates do not establish transitions."),
            ("Timestamp handling", "All record tables", timezoneNote + " Original timestamp strings and entry offsets remain in Source Fields. Treatment date is a grouping key, not an occurrence timestamp."),
            ("Legacy confirmation", "Morning / Pre-sleep", "A saved default cannot be proven freshly confirmed when confirmation provenance was not captured. No historical answer is rewritten."),
            ("Saved preferences", "Outside this archive", "Exported nightly answers do not establish full preservation of room, sleeping-setup or pain preferences. Reusable preferences are not nightly symptoms."),
            ("Medication windows", "Historical snapshots unavailable", "The workbook does not reclassify historical timing using current settings. An exported interval is descriptive, not medication advice."),
            ("Review comments", "Owner review / Owner notes", "Use Keep, Optional, Change, Remove or Need information and a note. Workbook-only comments never update app records."),
            ("Complete machine ingestion", "Studio ZIP / insights_bundle.json", "Prefer the companion versioned Studio bundle. Do not append two snapshots as new observations or treat Excel edits as a phone import.")
        ]
        rows += contracts.map { topic, path, meaning in [.text("Definitions and limits"), .text(topic), .text(path), .text("Contract"), .blank,
            SW.text(meaning), .text("Unavailable is never zero"), .text(path.contains("Unavailable") || path == "Not exported" ? "Not available" : "Defined above"), .blank, .blank] }
        rows += Self.tableGrains.keys.sorted().map { name in [.text("Table mapping"), .text(name), .text("DoseTap" + name.filter { $0.isLetter || $0.isNumber }),
            .text("Named Excel table"), .blank, SW.text(Self.tableGrains[name]), .text("Empty sources contain zero observations"), .text("Workbook schema 2"), .blank, .blank] }
        rows += sourceSHA256.keys.sorted().map { source in [.text("Source integrity"), .text(source), .text("SHA-256 of exact supplied source bytes"),
            .text("Digest"), .blank, SW.text(sourceSHA256[source]), .text("No live data refresh"), .text("Snapshot metadata"), .blank, .blank] }
        return SW.table("Field Guide", columns, rows, note: "Observed field inventory and metric definitions. Owner review/notes are workbook-only comments. Unknown future fields remain visible; their meaning is not guessed. Full source paths are retained in Source Fields even when a long label is previewed here.")
    }

    static var tableGrains: [String: String] { [
        "Overview": "One fixed period/provider/population summary; measurements are not new observations.",
        "Dose Summary": "One exported date group; reconciled dose outcomes and occurrence intervals, unresolved groups excluded.",
        "Medication Log": "One canonical dose or general-medication source identity/payload variant; audit events are not administrations.",
        "Nights": "One exported treatment-date group, including unresolved groups.",
        "Night Review": "One displayed fact or evidence reference for a date group; filter by date and group.",
        "Events": "One original table+ID+payload variant; normalized representations are not counted again.",
        "Pre-sleep": "One original pre-sleep questionnaire variant, with every associated date retained.",
        "Morning": "One original morning questionnaire variant, with every associated date retained.",
        "Pain": "One independent entry within an original questionnaire; legacy aggregates stay aggregate.",
        "Daytime": "One original night-outcome diary submission; revisions remain source evidence, not new current assessments.",
        "Sleep Measures": "One supplied provider summary per date group; provider definitions remain separate.",
        "Sleep Intervals": "One exported interval; overlaps are retained and cannot simply be summed.",
        "Medications": "One separate general-medication original record variant.",
        "Inventory": "One recorded inventory snapshot variant.",
        "Source Fields": "One source field part. Source record + Date groups supplies associations; Field reference groups numbered parts.",
        "Review Issues": "One issue or unavailable measurement; multiple issues may affect one date.",
        "Field Guide": "One observed field, definition, named table mapping or source-integrity entry."
    ] }
}
