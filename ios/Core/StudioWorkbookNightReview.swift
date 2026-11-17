import Foundation

extension StudioWorkbookData {
    func nightReviewSheet() -> WorkbookSheet {
        let columns = ["Treatment date", "Date group", "Identity status", "Category", "Measure or event", "Value", "Unit",
            "Start (UTC)", "End (UTC)", "Start (local)", "End (local)", "Status or evidence", "Source record", "Details"]
        var rows: [[WorkbookCell]] = []
        for group in groups {
            func add(_ category: String, _ name: String, _ value: WorkbookCell = .blank, unit: String = "",
                     start: Date? = nil, end: Date? = nil, status: String, source: String, details: String = "") {
                rows.append([SW.text(group.date), .text(group.key), .text(group.identity), .text(category), .text(name), value, .text(unit),
                    start.map(WorkbookCell.date) ?? .blank, end.map(WorkbookCell.date) ?? .blank,
                    timestamps.localCell(start), timestamps.localCell(end), SW.text(status), SW.text(source), SW.text(details)])
            }
            let rawStatus = group.eligible ? "Supplied source timestamp" : "Identity unresolved; combined values excluded"
            for number in [1, 2] {
                let dose = reviewedDose(group, number: number)
                add("Dose records", "Dose \(number) outcome", .text(dose.outcome), start: dose.time,
                    status: dose.evidence, source: dose.record?.key ?? group.key + "/dose\(number)TimeUTC")
            }
            add("Dose records", "Dose 1 to Dose 2 interval", SW.duration(doseInterval(group)), unit: "Elapsed duration",
                start: doseTime(group, number: 1), end: doseTime(group, number: 2),
                status: doseIntervalReason(group) + "; occurrence-time difference only; historical medication window unavailable", source: group.key)
            for (field, label) in [("sleepOnsetUTC", "Apple Health supplied sleep onset"), ("finalWakeUTC", "Apple Health supplied final wake")] {
                add("Sleep timestamps", label, group.eligible ? timestampCell(group.health[field]) : .blank,
                    status: group.eligible ? (group.health[field] == nil ? "Not exported" : "Provider estimate; see supplied basis and derivation") : rawStatus,
                    source: group.key + "/healthKit/" + field,
                    details: SW.string(group.health["finalWakeBasis"]) ?? "")
            }
            let dose2 = doseTime(group, number: 2)
            let intervals = SW.objects(group.health["recordedIntervals"]).enumerated().compactMap { index, raw -> (Int, Date, Date, Bool)? in
                guard let start = timestamps.parse(raw["start"]), let end = timestamps.parse(raw["end"]), end > start, let asleep = SW.boolean(raw["asleep"]) else { return nil }
                return (index, start, end, asleep)
            }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
            let intersecting = dose2.map { dose in intervals.filter { !$0.3 && $0.1 <= dose && dose < $0.2 } } ?? []
            let asleepAtDose = dose2.map { dose in intervals.contains { $0.3 && $0.1 <= dose && dose < $0.2 } } ?? false
            let intervalStatus: String
            if !group.eligible { intervalStatus = rawStatus }
            else if dose2 == nil { intervalStatus = "No usable Dose 2 timestamp" }
            else if asleepAtDose && !intersecting.isEmpty { intervalStatus = "Conflicting awake and asleep coverage at Dose 2" }
            else if asleepAtDose { intervalStatus = "Exported asleep interval covers Dose 2; not zero return-to-sleep latency" }
            else if intersecting.isEmpty { intervalStatus = "No exported awake interval intersects Dose 2; gap/awakening duration remains unknown" }
            else { intervalStatus = "Direct exported awake-interval evidence only; not a reviewed clinical metric" }
            let missingMetric = "Reviewed dose-to-sleep metric and full evidence projection are not exported. "
            add("Reviewed metrics", "Dose 1 to observed sleep onset", status: missingMetric + "No replacement latency is calculated.", source: group.key)
            add("Reviewed metrics", "Dose 2 to observed return to sleep", status: missingMetric + intervalStatus, source: group.key)
            if intersecting.isEmpty {
                add("Dose 2 interval evidence", "Observed awake interval around Dose 2", status: intervalStatus,
                    source: group.key + "/healthKit/recordedIntervals")
            }
            for (index, start, end, _) in intersecting {
                let conflict = intervals.contains { $0.3 && $0.1 < end && $0.2 > start }
                add("Dose 2 interval evidence", "Observed awake interval around Dose 2", .durationMinutes(end.timeIntervalSince(start) / 60),
                    unit: "Source interval duration", start: start, end: end,
                    status: intervalStatus + (conflict ? "; overlapping asleep evidence elsewhere in this interval" : ""),
                    source: group.key + "/healthKit/recordedIntervals[\(index)]",
                    details: "Duration is this source interval's bounds; overlapping intervals are not summed. Bathroom/alarm overlap is not a cause attribution.")
                if let next = intervals.first(where: { $0.3 && $0.1 >= end }) {
                    add("Dose 2 interval evidence", "Next exported asleep interval start", .date(next.1), start: next.1, end: next.2,
                        status: next.1 == end ? "Adjacent exported interval; no new clinical latency calculated" : "Unmeasured gap before this interval; return time unresolved",
                        source: group.key + "/healthKit/recordedIntervals[\(next.0)]")
                } else {
                    add("Dose 2 interval evidence", "Next exported asleep interval start", status: "No later exported asleep interval; return time unresolved", source: group.key)
                }
            }
            for (key, name) in [("estimatedSleepAfterDose2Minutes", "Supplied asleep minutes after Dose 2"),
                ("sleepAfterDose2CoveredMinutes", "Supplied covered minutes after Dose 2"),
                ("sleepAfterDose2IntervalMinutes", "Supplied elapsed interval after Dose 2")] {
                add("Supplied sleep estimates", name, SW.duration(group.eligible ? SW.nonnegative(group.collected[key]) : nil), unit: "Minutes (supplied)",
                    status: group.collected[key] == nil ? "Not exported; unavailable is not zero" : rawStatus,
                    source: group.key + "/collectedNight/" + key, details: SW.string(group.collected["sleepAfterDose2Source"]) ?? "Source not supplied")
            }
            for record in groupRecords(group).filter({ eventType($0) != nil }).sorted(by: {
                let a = eventDate($0) ?? .distantFuture, b = eventDate($1) ?? .distantFuture
                return a == b ? $0.key < $1.key : a < b
            }) {
                add("Original events", eventType(record) ?? "Unknown event", start: eventDate(record),
                    status: "Original record; logging time and event time are separate. \(identity(for: record))", source: record.key,
                    details: SW.string(record.fields["details"] ?? record.fields["notes"] ?? record.fields["metadata"]) ?? "")
            }
            for (table, name, sheet) in [("pre_sleep_logs", "Original pre-sleep answers", "Pre-sleep"),
                                        ("morning_checkins", "Original morning answers", "Morning")] {
                for record in groupRecords(group, table: table) {
                    add("Questionnaires", name, .link(label: "Open \(sheet); filter Source record", target: "'\(sheet)'!A4"),
                        start: timestamps.parse(recorded(record)), status: "\(identity(for: record)); \(record.association)", source: record.key,
                        details: "Dates: \(record.dateLabel). Full recorded bed/people/pet setup, room conditions and pain fields remain in the original-record tables.")
                }
            }
            for (key, name) in [("followingDayType", "Following day (recorded)"), ("sleepiness0To10", "Sleepiness (0–10, recorded)"),
                                ("sleepinessAssessedAt", "Sleepiness assessed at")] {
                add("Daytime", name, group.eligible ? sourceCell(group.collected[key], key: key) : .blank,
                    status: group.collected[key] == nil ? "Not recorded in collected-night view; original diary remains in Daytime" : rawStatus,
                    source: group.key + "/collectedNight/" + key)
            }
        }
        return SW.table("Night Review", columns, rows, note: "Filter Treatment date + Date group for one night; every column is sortable. Times are source facts, and latency markers remain unavailable when the accepted reviewed projection was not exported. Exported interval evidence does not establish complete HealthKit consensus. Original records remain separate when identity conflicts. \(timezoneNote)")
    }
}
